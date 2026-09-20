import Foundation
import CoreBluetooth
import Combine

// MARK: - Bluetooth Sensor Types
public enum SensorDeviceType: String, CaseIterable {
    case heartRate = "心率帶 (HRP 0x180D)"
    case cadence = "踏頻/速度感測器 (CSCP 0x1816)"
    case power = "功率計 (CPP 0x1818)"
    case unknown = "藍牙運動設備"
    
    public var icon: String {
        switch self {
        case .heartRate: return "heart.fill"
        case .cadence: return "bicycle"
        case .power: return "bolt.fill"
        case .unknown: return "sensor.tag.radiowaves.forward.fill"
        }
    }
}

public struct DiscoveredDevice: Identifiable, Equatable {
    public var id: UUID { peripheral.identifier }
    public let peripheral: CBPeripheral
    public var name: String
    public var rssi: Int
    public var type: SensorDeviceType
    public var isConnected: Bool
    public var isRemembered: Bool
}

// MARK: - Standard Bluetooth SIG UUIDs
public struct BLEGATTUUIDs {
    // Heart Rate Service & Measurement (0x180D / 0x2A37)
    public static let heartRateService = CBUUID(string: "180D")
    public static let heartRateMeasurement = CBUUID(string: "2A37")
    
    // Cycling Speed and Cadence Service & Measurement (0x1816 / 0x2A5B)
    public static let cyclingSpeedCadenceService = CBUUID(string: "1816")
    public static let cscMeasurement = CBUUID(string: "2A5B")
    
    // Cycling Power Service & Measurement (0x1818 / 0x2A63)
    public static let cyclingPowerService = CBUUID(string: "1818")
    public static let cyclingPowerMeasurement = CBUUID(string: "2A63")
}

// MARK: - Bluetooth Sensor Manager with Auto-Reconnect & Power Meter
@MainActor
public class BluetoothSensorManager: NSObject, ObservableObject, CBCentralManagerDelegate, CBPeripheralDelegate {
    public static let shared = BluetoothSensorManager()
    
    private let savedDeviceIdsKey = "velodice_saved_ble_sensor_uuids"
    
    // Discovered & Connected Devices
    @Published public var discoveredDevices: [DiscoveredDevice] = []
    @Published public var isScanning: Bool = false
    @Published public var bluetoothStateDescription: String = "未初始化"
    
    // Live Decoded Sensor Values
    @Published public var liveHeartRateBpm: Int? = nil
    @Published public var liveCadenceRpm: Int? = nil
    @Published public var livePowerWatts: Int? = nil
    
    @Published public var connectedHeartRateDeviceName: String? = nil
    @Published public var connectedCadenceDeviceName: String? = nil
    @Published public var connectedPowerDeviceName: String? = nil
    
    private var centralManager: CBCentralManager?
    private var connectedPeripherals: [UUID: CBPeripheral] = [:]
    
    // Cadence Protocol State tracking & Coasting Auto-Zero Timer
    private var lastCrankRevs: UInt16? = nil
    private var lastCrankEventTime: UInt16? = nil
    private var lastCadencePacketDate: Date? = nil
    private var lastPowerPacketDate: Date? = nil
    private var watchdogTimer: Timer? = nil
    
    override public init() {
        super.init()
        centralManager = CBCentralManager(delegate: self, queue: nil)
        setupWatchdogs()
    }
    
    private func setupWatchdogs() {
        watchdogTimer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { [weak self] _ in
            guard let self = self else { return }
            let now = Date()
            
            // 滑行自動踏頻歸零 (3秒內無踏頻封包視為滑行)
            if let last = self.lastCadencePacketDate, now.timeIntervalSince(last) >= 3.0 {
                if self.liveCadenceRpm != 0 && self.liveCadenceRpm != nil {
                    self.liveCadenceRpm = 0
                }
            }
            
            // 滑行自動功率歸零 (3.5秒內無功率封包)
            if let lastP = self.lastPowerPacketDate, now.timeIntervalSince(lastP) >= 3.5 {
                if self.livePowerWatts != 0 && self.livePowerWatts != nil {
                    self.livePowerWatts = 0
                }
            }
        }
    }
    
    // MARK: - Remember / Auto-Reconnect Management
    public func getRememberedUUIDStrings() -> [String] {
        UserDefaults.standard.stringArray(forKey: savedDeviceIdsKey) ?? []
    }
    
    public func isDeviceRemembered(id: UUID) -> Bool {
        getRememberedUUIDStrings().contains(id.uuidString)
    }
    
    public func rememberDevice(id: UUID) {
        var list = getRememberedUUIDStrings()
        if !list.contains(id.uuidString) {
            list.append(id.uuidString)
            UserDefaults.standard.set(list, forKey: savedDeviceIdsKey)
        }
        updateRememberedStateInList()
    }
    
    public func forgetDevice(id: UUID) {
        var list = getRememberedUUIDStrings()
        list.removeAll(where: { $0 == id.uuidString })
        UserDefaults.standard.set(list, forKey: savedDeviceIdsKey)
        updateRememberedStateInList()
    }
    
    private func updateRememberedStateInList() {
        let remembered = Set(getRememberedUUIDStrings())
        for idx in discoveredDevices.indices {
            discoveredDevices[idx].isRemembered = remembered.contains(discoveredDevices[idx].id.uuidString)
        }
    }
    
    private func attemptAutoReconnectKnownDevices() {
        guard let central = centralManager, central.state == .poweredOn else { return }
        let remembered = getRememberedUUIDStrings().compactMap { UUID(uuidString: $0) }
        guard !remembered.isEmpty else { return }
        
        let peripherals = central.retrievePeripherals(withIdentifiers: remembered)
        for p in peripherals {
            p.delegate = self
            connectedPeripherals[p.identifier] = p
            central.connect(p, options: nil)
        }
    }
    
    // MARK: - User Controls
    public func startScanning() {
        guard let central = centralManager, central.state == .poweredOn else {
            bluetoothStateDescription = "藍牙尚未開啟，請先開啟系統藍牙"
            return
        }
        
        isScanning = true
        discoveredDevices.removeAll(where: { !$0.isConnected })
        
        // 全面掃描附近感測器 (心率帶、踏頻計、功率計)
        central.scanForPeripherals(
            withServices: nil,
            options: [CBCentralManagerScanOptionAllowDuplicatesKey: false]
        )
    }
    
    public func stopScanning() {
        centralManager?.stopScan()
        isScanning = false
    }
    
    public func connect(device: DiscoveredDevice) {
        let p = device.peripheral
        p.delegate = self
        connectedPeripherals[p.identifier] = p
        rememberDevice(id: p.identifier) // 自動記住連線設備，下次啟動自動連線
        centralManager?.connect(p, options: nil)
    }
    
    public func disconnect(device: DiscoveredDevice) {
        let p = device.peripheral
        centralManager?.cancelPeripheralConnection(p)
        connectedPeripherals.removeValue(forKey: p.identifier)
        if p.name == connectedHeartRateDeviceName {
            connectedHeartRateDeviceName = nil
            liveHeartRateBpm = nil
        }
        if p.name == connectedCadenceDeviceName {
            connectedCadenceDeviceName = nil
            liveCadenceRpm = nil
        }
        if p.name == connectedPowerDeviceName {
            connectedPowerDeviceName = nil
            livePowerWatts = nil
        }
    }
    
    // MARK: - CBCentralManagerDelegate
    nonisolated public func centralManagerDidUpdateState(_ central: CBCentralManager) {
        Task { @MainActor in
            switch central.state {
            case .poweredOn:
                self.bluetoothStateDescription = "藍牙已就緒，可搜尋設備"
                self.attemptAutoReconnectKnownDevices()
            case .poweredOff:
                self.bluetoothStateDescription = "藍牙已關閉，請開啟藍牙以連接感測器"
                self.stopScanning()
            case .unauthorized:
                self.bluetoothStateDescription = "尚未取得藍牙權限，請至系統設定中授權"
            case .unsupported:
                self.bluetoothStateDescription = "此裝置不支援低功耗藍牙 (BLE)"
            default:
                self.bluetoothStateDescription = "藍牙狀態未知"
            }
        }
    }
    
    nonisolated public func centralManager(_ central: CBCentralManager, didDiscover peripheral: CBPeripheral, advertisementData: [String : Any], rssi RSSI: NSNumber) {
        Task { @MainActor in
            let rawName = peripheral.name ?? (advertisementData[CBAdvertisementDataLocalNameKey] as? String) ?? "未命名感測器"
            let devName = rawName.trimmingCharacters(in: .whitespacesAndNewlines)
            
            var devType: SensorDeviceType = .unknown
            if let advertisedUUIDs = advertisementData[CBAdvertisementDataServiceUUIDsKey] as? [CBUUID] {
                if advertisedUUIDs.contains(BLEGATTUUIDs.heartRateService) {
                    devType = .heartRate
                } else if advertisedUUIDs.contains(BLEGATTUUIDs.cyclingSpeedCadenceService) {
                    devType = .cadence
                } else if advertisedUUIDs.contains(BLEGATTUUIDs.cyclingPowerService) {
                    devType = .power
                }
            }
            
            // 若廣播未附帶 UUID，則智慧比對各大品牌關鍵字
            if devType == .unknown {
                let lower = devName.lowercased()
                if lower.contains("hr") || lower.contains("heart") || lower.contains("tickr") ||
                   lower.contains("polar") || lower.contains("h10") || lower.contains("h9") ||
                   lower.contains("h64") || lower.contains("magene") || lower.contains("coospo") ||
                   lower.contains("garmin") || lower.contains("decathlon") || lower.contains("igpsport") {
                    devType = .heartRate
                } else if lower.contains("pwr") || lower.contains("power") || lower.contains("assioma") ||
                          lower.contains("stages") || lower.contains("vector") || lower.contains("rally") ||
                          lower.contains("4iiii") || lower.contains("sram") || lower.contains("quarq") ||
                          lower.contains("spider") || lower.contains("inpeak") {
                    devType = .power
                } else if lower.contains("cad") || lower.contains("cadence") || lower.contains("spd") ||
                          lower.contains("vortex") || lower.contains("speed") {
                    devType = .cadence
                }
            }
            
            let isRemembered = self.isDeviceRemembered(id: peripheral.identifier)
            
            if let idx = self.discoveredDevices.firstIndex(where: { $0.id == peripheral.identifier }) {
                self.discoveredDevices[idx].rssi = RSSI.intValue
                self.discoveredDevices[idx].name = devName
                self.discoveredDevices[idx].isRemembered = isRemembered
                if devType != .unknown { self.discoveredDevices[idx].type = devType }
            } else {
                self.discoveredDevices.append(DiscoveredDevice(
                    peripheral: peripheral,
                    name: devName,
                    rssi: RSSI.intValue,
                    type: devType,
                    isConnected: false,
                    isRemembered: isRemembered
                ))
            }
            
            // 自動重連：若為記住的設備且尚未連線，自動發起連線
            if isRemembered && !peripheral.state.hashValue.words.isEmpty && peripheral.state != .connected {
                peripheral.delegate = self
                self.connectedPeripherals[peripheral.identifier] = peripheral
                central.connect(peripheral, options: nil)
            }
        }
    }
    
    nonisolated public func centralManager(_ central: CBCentralManager, didConnect peripheral: CBPeripheral) {
        Task { @MainActor in
            if let idx = self.discoveredDevices.firstIndex(where: { $0.id == peripheral.identifier }) {
                self.discoveredDevices[idx].isConnected = true
            }
            self.rememberDevice(id: peripheral.identifier)
            peripheral.discoverServices(nil)
        }
    }
    
    nonisolated public func centralManager(_ central: CBCentralManager, didDisconnectPeripheral peripheral: CBPeripheral, error: Error?) {
        Task { @MainActor in
            if let idx = self.discoveredDevices.firstIndex(where: { $0.id == peripheral.identifier }) {
                self.discoveredDevices[idx].isConnected = false
            }
            if peripheral.name == self.connectedHeartRateDeviceName {
                self.connectedHeartRateDeviceName = nil
                self.liveHeartRateBpm = nil
            }
            if peripheral.name == self.connectedCadenceDeviceName {
                self.connectedCadenceDeviceName = nil
                self.liveCadenceRpm = nil
                self.lastCadencePacketDate = nil
            }
            if peripheral.name == self.connectedPowerDeviceName {
                self.connectedPowerDeviceName = nil
                self.livePowerWatts = nil
                self.lastPowerPacketDate = nil
            }
        }
    }
    
    // MARK: - CBPeripheralDelegate
    nonisolated public func peripheral(_ peripheral: CBPeripheral, didDiscoverServices error: Error?) {
        guard let services = peripheral.services else { return }
        for s in services {
            peripheral.discoverCharacteristics(nil, for: s)
        }
    }
    
    nonisolated public func peripheral(_ peripheral: CBPeripheral, didDiscoverCharacteristicsFor service: CBService, error: Error?) {
        guard let characteristics = service.characteristics else { return }
        for c in characteristics {
            if c.properties.contains(.notify) || c.properties.contains(.indicate) {
                peripheral.setNotifyValue(true, for: c)
            }
            if (c.uuid == BLEGATTUUIDs.heartRateMeasurement ||
                c.uuid == BLEGATTUUIDs.cscMeasurement ||
                c.uuid == BLEGATTUUIDs.cyclingPowerMeasurement) && c.properties.contains(.read) {
                peripheral.readValue(for: c)
            }
        }
    }
    
    nonisolated public func peripheral(_ peripheral: CBPeripheral, didUpdateValueFor characteristic: CBCharacteristic, error: Error?) {
        guard let data = characteristic.value, !data.isEmpty else { return }
        let charUUID = characteristic.uuid
        
        Task { @MainActor in
            if charUUID == BLEGATTUUIDs.heartRateMeasurement {
                self.parseHeartRateMeasurement(data: data, peripheralName: peripheral.name)
            } else if charUUID == BLEGATTUUIDs.cscMeasurement {
                self.parseCyclingSpeedCadence(data: data, peripheralName: peripheral.name)
            } else if charUUID == BLEGATTUUIDs.cyclingPowerMeasurement {
                self.parseCyclingPower(data: data, peripheralName: peripheral.name)
            }
        }
    }
    
    // MARK: - Protocol Parsers
    private func parseHeartRateMeasurement(data: Data, peripheralName: String?) {
        guard data.count >= 2 else { return }
        let flags = data[0]
        let isUInt16 = (flags & 0x01) != 0
        
        var hrValue: Int = 0
        if isUInt16 {
            if data.count >= 3 {
                let lower = UInt16(data[1])
                let upper = UInt16(data[2])
                hrValue = Int(lower | (upper << 8))
            }
        } else {
            hrValue = Int(data[1])
        }
        
        if hrValue > 0 && hrValue < 250 {
            self.liveHeartRateBpm = hrValue
            if let name = peripheralName {
                self.connectedHeartRateDeviceName = name
                if let idx = self.discoveredDevices.firstIndex(where: { $0.name == name }) {
                    self.discoveredDevices[idx].type = .heartRate
                }
            }
        }
    }
    
    private func parseCyclingSpeedCadence(data: Data, peripheralName: String?) {
        guard data.count >= 1 else { return }
        let flags = data[0]
        let wheelDataPresent = (flags & 0x01) != 0
        let crankDataPresent = (flags & 0x02) != 0
        
        if crankDataPresent {
            let offset = wheelDataPresent ? 7 : 1
            guard data.count >= offset + 4 else { return }
            
            let crankRevs = UInt16(data[offset]) | (UInt16(data[offset + 1]) << 8)
            let eventTime = UInt16(data[offset + 2]) | (UInt16(data[offset + 3]) << 8)
            
            if let prevRevs = lastCrankRevs, let prevTime = lastCrankEventTime {
                let cRevs = UInt32(crankRevs)
                let pRevs = UInt32(prevRevs)
                let deltaRevs: UInt32 = (cRevs >= pRevs) ? (cRevs - pRevs) : (65536 + cRevs - pRevs)
                
                let cTime = UInt32(eventTime)
                let pTime = UInt32(prevTime)
                let deltaTime: UInt32 = (cTime >= pTime) ? (cTime - pTime) : (65536 + cTime - pTime)
                
                if deltaTime > 0 && deltaRevs > 0 {
                    let timeSeconds = Double(deltaTime) / 1024.0
                    let rpm = (Double(deltaRevs) / timeSeconds) * 60.0
                    if rpm >= 0 && rpm <= 220 {
                        self.liveCadenceRpm = Int(round(rpm))
                        if let name = peripheralName {
                            self.connectedCadenceDeviceName = name
                            if let idx = self.discoveredDevices.firstIndex(where: { $0.name == name }) {
                                self.discoveredDevices[idx].type = .cadence
                            }
                        }
                    }
                } else if deltaRevs == 0 {
                    self.liveCadenceRpm = 0
                }
            }
            
            lastCrankRevs = crankRevs
            lastCrankEventTime = eventTime
            lastCadencePacketDate = Date()
        }
    }
    
    private func parseCyclingPower(data: Data, peripheralName: String?) {
        guard data.count >= 4 else { return }
        // Flags: 16-bit
        // Instantaneous Power: sint16 at byte 2,3 (Watts)
        let rawPower = Int16(bitPattern: UInt16(data[2]) | (UInt16(data[3]) << 8))
        let watts = max(0, Int(rawPower))
        if watts >= 0 && watts < 2500 {
            self.livePowerWatts = watts
            if let name = peripheralName {
                self.connectedPowerDeviceName = name
                if let idx = self.discoveredDevices.firstIndex(where: { $0.name == name }) {
                    self.discoveredDevices[idx].type = .power
                }
            }
        }
        lastPowerPacketDate = Date()
    }
}

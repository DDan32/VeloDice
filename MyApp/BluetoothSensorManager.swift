import Foundation
import CoreBluetooth
import Combine

// MARK: - Bluetooth Sensor Types
public enum SensorDeviceType: String {
    case heartRate = "心率帶 (HRP 0x180D)"
    case cadence = "踏頻/速度感測器 (CSCP 0x1816)"
    case unknown = "藍牙運動設備"
    
    public var icon: String {
        switch self {
        case .heartRate: return "heart.fill"
        case .cadence: return "bicycle"
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
}

// MARK: - Standard Bluetooth SIG UUIDs
public struct BLEGATTUUIDs {
    // Heart Rate Service & Measurement (0x180D / 0x2A37)
    public static let heartRateService = CBUUID(string: "180D")
    public static let heartRateMeasurement = CBUUID(string: "2A37")
    
    // Cycling Speed and Cadence Service & Measurement (0x1816 / 0x2A5B)
    public static let cyclingSpeedCadenceService = CBUUID(string: "1816")
    public static let cscMeasurement = CBUUID(string: "2A5B")
}

// MARK: - Bluetooth Sensor Manager for XOSS & Standard Cycling Devices
@MainActor
public class BluetoothSensorManager: NSObject, ObservableObject, CBCentralManagerDelegate, CBPeripheralDelegate {
    public static let shared = BluetoothSensorManager()
    
    // Discovered & Connected Devices
    @Published public var discoveredDevices: [DiscoveredDevice] = []
    @Published public var isScanning: Bool = false
    @Published public var bluetoothStateDescription: String = "未初始化"
    
    // Live Decoded Sensor Values (From Real XOSS / BLE Packets)
    @Published public var liveHeartRateBpm: Int? = nil
    @Published public var liveCadenceRpm: Int? = nil
    @Published public var connectedHeartRateDeviceName: String? = nil
    @Published public var connectedCadenceDeviceName: String? = nil
    
    private var centralManager: CBCentralManager?
    private var connectedPeripherals: [UUID: CBPeripheral] = [:]
    
    // Cadence Protocol State tracking & Coasting Auto-Zero Timer
    private var lastCrankRevs: UInt16? = nil
    private var lastCrankEventTime: UInt16? = nil
    private var lastCadencePacketDate: Date? = nil
    private var cadenceWatchdogTimer: Timer? = nil
    
    override public init() {
        super.init()
        centralManager = CBCentralManager(delegate: self, queue: nil)
        setupCadenceWatchdog()
    }
    
    private func setupCadenceWatchdog() {
        cadenceWatchdogTimer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { [weak self] _ in
            guard let self = self else { return }
            if let last = self.lastCadencePacketDate, Date().timeIntervalSince(last) >= 3.0 {
                if self.liveCadenceRpm != 0 && self.liveCadenceRpm != nil {
                    self.liveCadenceRpm = 0
                }
            }
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
        
        central.scanForPeripherals(
            withServices: nil, // 允許全面掃描附近藍牙運動感測器 (包含未在廣播包內寫入 Service UUID 的 XOSS/邁金感測器)
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
    }
    
    // MARK: - CBCentralManagerDelegate
    nonisolated public func centralManagerDidUpdateState(_ central: CBCentralManager) {
        Task { @MainActor in
            switch central.state {
            case .poweredOn:
                self.bluetoothStateDescription = "藍牙已就緒，可搜尋設備"
            case .poweredOff:
                self.bluetoothStateDescription = "藍牙已關閉，請開啟藍牙以連接 XOSS 設備"
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
            
            // 檢查廣播包服務 UUID (最準確的 BLE 標準判斷)
            var devType: SensorDeviceType = .unknown
            if let advertisedUUIDs = advertisementData[CBAdvertisementDataServiceUUIDsKey] as? [CBUUID] {
                if advertisedUUIDs.contains(BLEGATTUUIDs.heartRateService) {
                    devType = .heartRate
                } else if advertisedUUIDs.contains(BLEGATTUUIDs.cyclingSpeedCadenceService) {
                    devType = .cadence
                }
            }
            
            // 若廣播未附帶 UUID，則智慧比對市售各大品牌關鍵字
            if devType == .unknown {
                let lower = devName.lowercased()
                if lower.contains("hr") || lower.contains("heart") || lower.contains("tickr") ||
                   lower.contains("polar") || lower.contains("h10") || lower.contains("h9") ||
                   lower.contains("h64") || lower.contains("magene") || lower.contains("coospo") ||
                   lower.contains("garmin") || lower.contains("decathlon") || lower.contains("igpsport") {
                    devType = .heartRate
                } else if lower.contains("cad") || lower.contains("cadence") || lower.contains("spd") ||
                          lower.contains("vortex") || lower.contains("speed") {
                    devType = .cadence
                }
            }
            
            if let idx = self.discoveredDevices.firstIndex(where: { $0.id == peripheral.identifier }) {
                self.discoveredDevices[idx].rssi = RSSI.intValue
                self.discoveredDevices[idx].name = devName
                if devType != .unknown { self.discoveredDevices[idx].type = devType }
            } else {
                self.discoveredDevices.append(DiscoveredDevice(
                    peripheral: peripheral,
                    name: devName,
                    rssi: RSSI.intValue,
                    type: devType,
                    isConnected: false
                ))
            }
        }
    }
    
    nonisolated public func centralManager(_ central: CBCentralManager, didConnect peripheral: CBPeripheral) {
        Task { @MainActor in
            if let idx = self.discoveredDevices.firstIndex(where: { $0.id == peripheral.identifier }) {
                self.discoveredDevices[idx].isConnected = true
            }
            // 發現所有可用服務，避免因特定 UUID 造成過濾失敗 (支援更多自定義或雙模感測器)
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
        }
    }
    
    // MARK: - CBPeripheralDelegate
    nonisolated public func peripheral(_ peripheral: CBPeripheral, didDiscoverServices error: Error?) {
        guard let services = peripheral.services else { return }
        for s in services {
            // 探索該服務的所有特徵值
            peripheral.discoverCharacteristics(nil, for: s)
        }
    }
    
    nonisolated public func peripheral(_ peripheral: CBPeripheral, didDiscoverCharacteristicsFor service: CBService, error: Error?) {
        guard let characteristics = service.characteristics else { return }
        for c in characteristics {
            // 凡是有 notify 或 indicate 屬性的運動特徵值，皆主動啟用監聽
            if c.properties.contains(.notify) || c.properties.contains(.indicate) {
                peripheral.setNotifyValue(true, for: c)
            }
            // 若為心率或踏頻特徵值且支援 read，先讀取一次初始值
            if (c.uuid == BLEGATTUUIDs.heartRateMeasurement || c.uuid == BLEGATTUUIDs.cscMeasurement) && c.properties.contains(.read) {
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
}

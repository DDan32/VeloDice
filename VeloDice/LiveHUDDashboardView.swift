import SwiftUI
import CoreLocation
import MapKit

public struct LiveHUDDashboardView: View {
    let track: GPXTrack
    var onWorkoutFinished: ((GPXTrack) -> Void)? = nil
    
    @ObservedObject private var tracker = WorkoutTracker.shared
    @ObservedObject private var bleManager = BluetoothSensorManager.shared
    
    // AI Prediction State
    @State private var aiPrediction: AIEstimationEngine.PredictionResult?
    
    // Weather State
    @State private var weatherForecasts: [RouteWeatherForecast] = []
    
    // Strava-style Save Workout Sheet
    @State private var showSaveWorkoutSheet: Bool = false
    @State private var finishedTrackToSave: GPXTrack? = nil
    
    // Snapshot of Finished Workout Metrics (Preserved after tracker reset)
    @State private var snapshotDuration: TimeInterval = 0
    @State private var snapshotMovingDuration: TimeInterval = 0
    @State private var snapshotDistance: Double = 0
    @State private var snapshotAscent: Double = 0
    @State private var snapshotHR: Int? = nil
    @State private var snapshotCadence: Int? = nil
    @State private var snapshotPower: Int? = nil
    
    // Bluetooth Sensor Sheet
    @State private var showBluetoothSheet: Bool = false
    
    // Mini Navigation Map Camera State (Battery Saving: Collapsible)
    @State private var navMapPosition: MapCameraPosition = .userLocation(fallback: .automatic)
    @State private var isMapExpanded: Bool = true
    
    public init(track: GPXTrack, onWorkoutFinished: ((GPXTrack) -> Void)? = nil) {
        self.track = track
        self.onWorkoutFinished = onWorkoutFinished
    }
    
    public var body: some View {
        ScrollView {
            VStack(spacing: 16) {
                // Active Turn-by-Turn Navigation Guidance Banner (Like Apple Maps / Carplay)
                if tracker.state == .recording || tracker.state == .paused {
                    activeTurnByTurnBanner
                }
                
                // Embedded Mini Navigation Route Map (簡易路線圖 & 轉彎跟隨)
                if (tracker.state == .recording || tracker.state == .paused || track.points.count > 1) {
                    liveNavigationMiniMapCard
                }
                
                // Bluetooth Sensor Connectivity Banner
                bluetoothSensorStatusBanner
                
                // Workout Control Bar (Start / Pause / Resume / Stop)
                workoutControlCenter
                
                // Primary Metric HUD (Speed, Time, Distance, HR, Cadence, Elevation, Power)
                primaryMetricGrid
                
                // AI ETA & Arrival Predictor Card
                aiArrivalPredictorCard
                
                // Weather Along Route & Radar Echo Card
                weatherAlongRouteCard
            }
            .padding()
        }
        .onAppear {
            updateAIPredictionAndWeather()
        }
        .onChange(of: tracker.currentDistanceKm) { _ in
            updateAIPredictionAndWeather()
        }
        .onChange(of: tracker.currentUserLocation?.coordinate.latitude) { _ in
            updateAIPredictionAndWeather()
        }
        .sheet(isPresented: $showSaveWorkoutSheet) {
            if let finTrack = finishedTrackToSave {
                SaveWorkoutSheet(
                    finishedTrack: finTrack,
                    durationSeconds: snapshotDuration,
                    movingDurationSeconds: snapshotMovingDuration,
                    distanceKm: snapshotDistance,
                    totalAscentMeters: snapshotAscent,
                    avgHeartRate: snapshotHR,
                    avgCadence: snapshotCadence,
                    avgPowerWatts: snapshotPower,
                    onSaved: { saved in
                        showSaveWorkoutSheet = false
                        tracker.resetAllMetrics()
                        onWorkoutFinished?(saved.track)
                    },
                    onDismiss: {
                        showSaveWorkoutSheet = false
                        tracker.resetAllMetrics()
                    }
                )
            }
        }
        .sheet(isPresented: $showBluetoothSheet) {
            bluetoothPairingSheet
        }
    }
    
    // MARK: - Active Turn-by-Turn Navigation Guidance Banner
    private var activeTurnByTurnBanner: some View {
        VStack(spacing: 8) {
            if !tracker.activeNavigationSteps.isEmpty && tracker.currentStepIndex < tracker.activeNavigationSteps.count {
                let currentStep = tracker.activeNavigationSteps[tracker.currentStepIndex]
                
                HStack(alignment: .top, spacing: 14) {
                    // Turn Direction Icon
                    Image(systemName: currentStep.iconName)
                        .font(.system(size: 36, weight: .bold))
                        .foregroundColor(.white)
                        .frame(width: 52, height: 52)
                        .background(RoundedRectangle(cornerRadius: 14).fill(Color.blue))
                    
                    VStack(alignment: .leading, spacing: 4) {
                        // Distance to turn
                        HStack {
                            Text(formatDistance(tracker.distanceToNextStepMeters))
                                .font(.system(size: 24, weight: .heavy, design: .rounded))
                                .foregroundColor(.primary)
                            
                            Spacer()
                            
                            Text("指引 \(tracker.currentStepIndex + 1) / \(tracker.activeNavigationSteps.count)")
                                .font(.caption.bold())
                                .foregroundColor(.secondary)
                        }
                        
                        // Main Instruction
                        Text(currentStep.instruction)
                            .font(.headline.bold())
                            .foregroundColor(.primary)
                            .lineLimit(2)
                        
                        // Next Step Preview
                        if tracker.currentStepIndex + 1 < tracker.activeNavigationSteps.count {
                            let nextStep = tracker.activeNavigationSteps[tracker.currentStepIndex + 1]
                            HStack(spacing: 4) {
                                Text("隨後")
                                    .font(.caption2.bold())
                                    .foregroundColor(.secondary)
                                Image(systemName: nextStep.iconName)
                                    .font(.caption)
                                    .foregroundColor(.blue)
                                Text(nextStep.instruction)
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                                    .lineLimit(1)
                            }
                            .padding(.top, 2)
                        }
                    }
                }
                .padding()
                .background(RoundedRectangle(cornerRadius: 16).fill(.ultraThinMaterial))
                .shadow(color: .black.opacity(0.15), radius: 6, y: 3)
            }
        }
    }
    
    // MARK: - Mini Navigation Map Card
    private var liveNavigationMiniMapCard: some View {
        VStack(spacing: 8) {
            HStack {
                Image(systemName: "map.fill")
                    .foregroundColor(.blue)
                Text("動態路線預覽")
                    .font(.subheadline.bold())
                
                Spacer()
                
                Button {
                    withAnimation {
                        isMapExpanded.toggle()
                    }
                } label: {
                    HStack(spacing: 4) {
                        Image(systemName: isMapExpanded ? "chevron.up.circle.fill" : "chevron.down.circle.fill")
                        Text(isMapExpanded ? "收合地圖 (省電)" : "展開地圖")
                            .font(.caption2.bold())
                    }
                    .foregroundColor(.secondary)
                }
                .buttonStyle(.plain)
            }
            
            if isMapExpanded {
                ZStack(alignment: .bottomTrailing) {
                    Map(position: $navMapPosition) {
                        UserAnnotation {
                            HeadingConeBeamView(heading: tracker.currentUserHeading)
                        }
                        
                        // Real Planned Route Polyline
                        if track.points.count > 1 {
                            MapPolyline(coordinates: track.points.map(\.coordinate))
                                .stroke(Color.blue, style: StrokeStyle(lineWidth: 6, lineCap: .round, lineJoin: .round))
                        }
                        
                        // Live GPS Recorded Breadcrumb Trail (Orange High-Visibility)
                        if tracker.recordedPoints.count > 1 {
                            MapPolyline(coordinates: tracker.recordedPoints.map(\.coordinate))
                                .stroke(Color.orange, style: StrokeStyle(lineWidth: 5, lineCap: .round, lineJoin: .round))
                        }
                        
                        // Start Point
                        if let start = track.points.first {
                            Annotation("起點", coordinate: start.coordinate) {
                                Image(systemName: "flag.circle.fill")
                                    .foregroundColor(.green)
                                    .background(Circle().fill(.white))
                            }
                        }
                        
                        // Destination Point
                        if let end = track.points.last {
                            Annotation("終點", coordinate: end.coordinate) {
                                Image(systemName: "flag.checkered.circle.fill")
                                    .foregroundColor(.red)
                                    .background(Circle().fill(.white))
                            }
                        }
                    }
                    .mapStyle(.standard)
                    .frame(height: 220)
                    .clipShape(RoundedRectangle(cornerRadius: 14))
                    
                    // Recenter on Location Button
                    Button {
                        if let userLoc = tracker.currentUserLocation?.coordinate {
                            navMapPosition = .region(MKCoordinateRegion(center: userLoc, span: MKCoordinateSpan(latitudeDelta: 0.02, longitudeDelta: 0.02)))
                        } else if let firstPt = track.points.first {
                            navMapPosition = .region(MKCoordinateRegion(center: firstPt.coordinate, span: MKCoordinateSpan(latitudeDelta: 0.04, longitudeDelta: 0.04)))
                        }
                    } label: {
                        Image(systemName: "location.fill")
                            .foregroundColor(.blue)
                            .padding(8)
                            .background(.ultraThinMaterial, in: Circle())
                            .shadow(radius: 2)
                    }
                    .buttonStyle(.plain)
                    .padding(10)
                }
            }
        }
        .padding(12)
        .background(RoundedRectangle(cornerRadius: 16).fill(.ultraThinMaterial))
        .shadow(radius: 3)
    }
    
    // MARK: - Bluetooth Sensor Status Banner
    private var bluetoothSensorStatusBanner: some View {
        HStack(spacing: 12) {
            Image(systemName: "sensor.tag.radiowaves.forward.fill")
                .foregroundColor(.blue)
                .font(.title3)
            
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 8) {
                    Text("藍牙運動感測器:")
                        .font(.caption.bold())
                    
                    if let hrName = bleManager.connectedHeartRateDeviceName {
                        HStack(spacing: 3) {
                            Circle().fill(Color.green).frame(width: 6, height: 6)
                            Text(hrName).font(.caption2.bold()).foregroundColor(.green)
                        }
                    }
                    
                    if let cadName = bleManager.connectedCadenceDeviceName {
                        HStack(spacing: 3) {
                            Circle().fill(Color.green).frame(width: 6, height: 6)
                            Text(cadName).font(.caption2.bold()).foregroundColor(.green)
                        }
                    }
                    
                    if let powName = bleManager.connectedPowerDeviceName {
                        HStack(spacing: 3) {
                            Circle().fill(Color.green).frame(width: 6, height: 6)
                            Text(powName).font(.caption2.bold()).foregroundColor(.green)
                        }
                    }
                    
                    if bleManager.connectedHeartRateDeviceName == nil && bleManager.connectedCadenceDeviceName == nil && bleManager.connectedPowerDeviceName == nil {
                        Text("未連接 (點擊右側配對)")
                            .font(.caption2)
                            .foregroundColor(.secondary)
                    }
                }
                
                Text(bleManager.connectedHeartRateDeviceName != nil || bleManager.connectedCadenceDeviceName != nil || bleManager.connectedPowerDeviceName != nil
                     ? "已連線設備具備自動重連記憶 · 廣播標準 GATT (0x180D/0x1816/0x1818)"
                     : "支援心率帶、踏頻器、功率計等標準 BLE 單車感測器（自動記憶重連）")
                    .font(.system(size: 10))
                    .foregroundColor(.secondary)
            }
            
            Spacer()
            
            Button {
                showBluetoothSheet = true
                bleManager.startScanning()
            } label: {
                HStack(spacing: 4) {
                    Image(systemName: "dot.radiowaves.left.and.right")
                    Text("配對設備")
                        .font(.caption.bold())
                }
                .padding(.horizontal, 10)
                .padding(.vertical, 6)
                .background(Color.blue.opacity(0.12), in: Capsule())
            }
            .buttonStyle(.plain)
        }
        .padding(10)
        .background(RoundedRectangle(cornerRadius: 12).fill(.ultraThinMaterial))
    }
    
    // MARK: - Workout Control Center
    private var workoutControlCenter: some View {
        VStack(spacing: 12) {
            HStack {
                HStack(spacing: 8) {
                    Circle()
                        .fill(stateColor)
                        .frame(width: 12, height: 12)
                    Text("運動狀態: \(tracker.state.rawValue)")
                        .font(.headline.bold())
                    
                    if tracker.isAutoPaused && tracker.state == .recording {
                        Text("⏸️ 停等紅綠燈 · 自動暫停")
                            .font(.caption2.bold())
                            .foregroundColor(.orange)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(Color.orange.opacity(0.15), in: Capsule())
                    }
                }
                
                Spacer()
            }
            
            Divider()
            
            // Big Action Buttons
            HStack(spacing: 16) {
                if tracker.state == .idle || tracker.state == .finished {
                    Button {
                        tracker.startWorkout(withPlan: track)
                    } label: {
                        HStack {
                            Image(systemName: "play.fill")
                            Text("開始記錄運動")
                        }
                        .font(.title3.bold())
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 14)
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(.green)
                } else if tracker.state == .recording {
                    Button {
                        tracker.pauseWorkout()
                    } label: {
                        HStack {
                            Image(systemName: "pause.fill")
                            Text("手動暫停")
                        }
                        .font(.headline.bold())
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 12)
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(.orange)
                    
                    Button {
                        finishCurrentWorkout()
                    } label: {
                        HStack {
                            Image(systemName: "stop.fill")
                            Text("結束並儲存")
                        }
                        .font(.headline.bold())
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 12)
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(.red)
                } else if tracker.state == .paused {
                    Button {
                        tracker.resumeWorkout()
                    } label: {
                        HStack {
                            Image(systemName: "play.fill")
                            Text("繼續記錄")
                        }
                        .font(.headline.bold())
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 12)
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(.green)
                    
                    Button {
                        finishCurrentWorkout()
                    } label: {
                        HStack {
                            Image(systemName: "stop.fill")
                            Text("結束並儲存")
                        }
                        .font(.headline.bold())
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 12)
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(.red)
                    
                    Button {
                        tracker.resetAllMetrics()
                    } label: {
                        Image(systemName: "trash")
                            .font(.headline)
                            .padding(.horizontal, 10)
                            .padding(.vertical, 12)
                    }
                    .buttonStyle(.bordered)
                    .tint(.secondary)
                    .help("放棄本次記錄並歸零")
                }
            }
            
            if tracker.state == .recording {
                Text("🛰️ 正在接收真實 CoreLocation GPS 衛星訊號 (支援背景持續定位與停等自動暫停)。")
                    .font(.caption2)
                    .foregroundColor(.green)
            }
        }
        .padding()
        .background(RoundedRectangle(cornerRadius: 16).fill(.ultraThinMaterial))
        .shadow(radius: 3)
    }
    
    private var stateColor: Color {
        switch tracker.state {
        case .idle: return .gray
        case .recording: return .green
        case .paused: return .orange
        case .finished: return .blue
        }
    }
    
    private func finishCurrentWorkout() {
        // 1. 快照保存即將儲存的完整運動紀錄 (使用正值有效非零均值，解決平均踏頻為0與心率計算問題)
        snapshotDuration = tracker.elapsedSeconds
        snapshotMovingDuration = tracker.movingSeconds
        snapshotDistance = tracker.currentDistanceKm
        snapshotAscent = tracker.totalAscentMeters
        snapshotHR = tracker.calculatedAvgHeartRate
        snapshotCadence = tracker.calculatedAvgCadence
        snapshotPower = tracker.calculatedAvgPower
        
        // 2. 結束運動並產出最終 GPX 軌跡
        let resultTrack = tracker.stopAndFinishWorkout()
        finishedTrackToSave = resultTrack
        
        // 3. 運動結束後立即將即時速度、時間、里程等儀表板數據全部歸零
        tracker.resetAllMetrics()
        
        // 4. 開啟儲存運動紀錄畫面
        showSaveWorkoutSheet = true
    }
    
    // MARK: - Primary Metric HUD (Accurate Sensor Values or "--")
    private var primaryMetricGrid: some View {
        VStack(spacing: 12) {
            // Big Speed & Time
            HStack(spacing: 20) {
                VStack(alignment: .leading) {
                    Text("即時速度")
                        .font(.caption)
                        .foregroundColor(.secondary)
                    HStack(alignment: .lastTextBaseline, spacing: 4) {
                        Text(String(format: "%.1f", tracker.currentSpeedKmh))
                            .font(.system(size: 44, weight: .heavy, design: .rounded))
                        Text("km/h")
                            .font(.headline)
                            .foregroundColor(.secondary)
                    }
                }
                
                Spacer()
                
                VStack(alignment: .trailing) {
                    HStack(spacing: 4) {
                        Text("運動時間")
                            .font(.caption)
                            .foregroundColor(.secondary)
                        if tracker.isAutoPaused && tracker.state == .recording {
                            Text("⏸ 自動暫停")
                                .font(.system(size: 10, weight: .bold))
                                .foregroundColor(.orange)
                                .padding(.horizontal, 6)
                                .padding(.vertical, 2)
                                .background(Color.orange.opacity(0.15), in: Capsule())
                        }
                    }
                    Text(formattedTime(tracker.movingSeconds))
                        .font(.system(size: 44, weight: .heavy, design: .monospaced))
                        .foregroundColor(tracker.isAutoPaused && tracker.state == .recording ? .secondary : .primary)
                    
                    if tracker.elapsedSeconds > tracker.movingSeconds + 5 {
                        Text("總歷時: \(formattedTime(tracker.elapsedSeconds))")
                            .font(.caption2)
                            .foregroundColor(.secondary)
                    }
                }
            }
            
            Divider()
            
            // 6-Quadrant Multi-Metric Cards (HR, Cadence, Power, Distance, Elevation, Avg Speed)
            LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 12) {
                // Heart Rate
                metricCard(
                    title: "即時心率",
                    value: tracker.currentHeartRateBpm != nil ? "\(tracker.currentHeartRateBpm!)" : "--",
                    unit: "BPM",
                    icon: "heart.fill",
                    color: .red,
                    extraNote: bleManager.connectedHeartRateDeviceName != nil ? "BLE 已連線" : "未連接"
                )
                
                // Cadence
                metricCard(
                    title: "即時踏頻",
                    value: tracker.currentCadenceRpm != nil ? "\(tracker.currentCadenceRpm!)" : "--",
                    unit: "RPM",
                    icon: "bicycle",
                    color: .purple,
                    extraNote: bleManager.connectedCadenceDeviceName != nil ? "BLE 已連線" : "未連接"
                )
                
                // Power
                metricCard(
                    title: "即時功率",
                    value: tracker.currentPowerWatts != nil ? "\(tracker.currentPowerWatts!)" : "--",
                    unit: "W",
                    icon: "bolt.fill",
                    color: .yellow,
                    extraNote: bleManager.connectedPowerDeviceName != nil ? "BLE 功率計" : "未連接"
                )
                
                // Moving Avg Speed
                metricCard(
                    title: "運動均速",
                    value: String(format: "%.1f", tracker.avgMovingSpeedKmh),
                    unit: "KM/H",
                    icon: "gauge.with.needle",
                    color: .green,
                    extraNote: "有效踩踏"
                )
                
                // Distance
                metricCard(
                    title: "累積里程",
                    value: String(format: "%.2f", tracker.currentDistanceKm),
                    unit: "KM",
                    icon: "road.lanes",
                    color: .blue,
                    extraNote: "GPS 測距"
                )
                
                // Elevation & Grade
                metricCard(
                    title: "海拔高度 (坡度)",
                    value: "\(Int(tracker.currentElevationMeters))",
                    unit: "M (\(String(format: "%.1f%%", tracker.currentGradientPercent)))",
                    icon: "mountain.2.fill",
                    color: .teal,
                    extraNote: "爬升 \(Int(tracker.totalAscentMeters)) m"
                )
            }
        }
        .padding()
        .background(RoundedRectangle(cornerRadius: 16).fill(.ultraThinMaterial))
        .shadow(radius: 3)
    }
    
    private func metricCard(title: String, value: String, unit: String, icon: String, color: Color, extraNote: String) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Image(systemName: icon)
                    .foregroundColor(color)
                    .font(.caption)
                Text(title)
                    .font(.caption)
                    .foregroundColor(.secondary)
                Spacer()
                Text(extraNote)
                    .font(.system(size: 9, weight: .semibold))
                    .padding(3)
                    .background(color.opacity(0.12), in: Capsule())
                    .foregroundColor(color)
            }
            
            HStack(alignment: .lastTextBaseline, spacing: 3) {
                Text(value)
                    .font(.system(size: 28, weight: .bold, design: .rounded))
                Text(unit)
                    .font(.caption.bold())
                    .foregroundColor(.secondary)
            }
        }
        .padding(12)
        .background(RoundedRectangle(cornerRadius: 12).fill(Color.secondary.opacity(0.08)))
    }
    
    // MARK: - Bluetooth Pairing Sheet
    private var bluetoothPairingSheet: some View {
        NavigationStack {
            List {
                Section(header: Text("藍牙連線狀態")) {
                    HStack {
                        Image(systemName: "antenna.radiowaves.left.and.right")
                            .foregroundColor(.blue)
                        Text(bleManager.bluetoothStateDescription)
                            .font(.subheadline)
                        Spacer()
                        if bleManager.isScanning {
                            ProgressView().controlSize(.small)
                        }
                    }
                    
                    HStack {
                        Button {
                            if bleManager.isScanning {
                                bleManager.stopScanning()
                            } else {
                                bleManager.startScanning()
                            }
                        } label: {
                            Text(bleManager.isScanning ? "停止搜尋" : "重新搜尋周圍感測器")
                                .font(.caption.bold())
                        }
                        .buttonStyle(.borderedProminent)
                        
                        Spacer()
                    }
                }
                
                Section(header: Text("搜尋到的藍牙運動感測器")) {
                    if bleManager.discoveredDevices.isEmpty {
                        VStack(spacing: 10) {
                            Image(systemName: "magnifyingglass")
                                .font(.title)
                                .foregroundColor(.secondary)
                            Text("正在搜尋周圍的心率帶、踏頻器與功率計...\n請先轉動踏頻器/功率計曲柄或佩戴心率帶以喚醒藍牙廣播。")
                                .font(.caption)
                                .foregroundColor(.secondary)
                                .multilineTextAlignment(.center)
                        }
                        .padding(.vertical, 16)
                        .frame(maxWidth: .infinity)
                    } else {
                        ForEach(bleManager.discoveredDevices) { dev in
                            HStack(spacing: 12) {
                                Image(systemName: dev.type.icon)
                                    .font(.title2)
                                    .foregroundColor(.blue)
                                    .frame(width: 32)
                                
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(dev.name)
                                        .font(.headline)
                                    Text(dev.type.rawValue)
                                        .font(.caption)
                                        .foregroundColor(.secondary)
                                }
                                
                                Spacer()
                                
                                if dev.isConnected {
                                    Button("已連線 (斷開)") {
                                        bleManager.disconnect(device: dev)
                                    }
                                    .buttonStyle(.bordered)
                                    .tint(.red)
                                    .controlSize(.small)
                                } else {
                                    Button("連線") {
                                        bleManager.connect(device: dev)
                                    }
                                    .buttonStyle(.borderedProminent)
                                    .tint(.blue)
                                    .controlSize(.small)
                                }
                            }
                            .padding(.vertical, 4)
                        }
                    }
                }
                
                Section(header: Text("連線與協定說明")) {
                    VStack(alignment: .leading, spacing: 6) {
                        Text("• 具備「自動記憶重連」功能：配對過的裝備在下次開啟 App 時將自動連線，無須每次重新手動配對。")
                        Text("• 心率設備遵循藍牙標準 Heart Rate Profile (Service: 0x180D, Characteristic: 0x2A37)。")
                        Text("• 踏頻器遵循藍牙標準 Cycling Speed and Cadence (Service: 0x1816, Characteristic: 0x2A5B)。")
                        Text("• 功率計遵循藍牙標準 Cycling Power Profile (Service: 0x1818, Characteristic: 0x2A63)。")
                        Text("• 主機端毫秒級即時解析曲柄迴轉數與事件時間差，保證踏頻與功率反應迅速精準。")
                    }
                    .font(.caption2)
                    .foregroundColor(.secondary)
                }
            }
            .navigationTitle("連接藍牙運動感測器")
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("完成") { showBluetoothSheet = false }
                }
            }
        }
    }
    
    // MARK: - AI Arrival Predictor Card
    private var aiArrivalPredictorCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Image(systemName: "brain.head.profile")
                    .foregroundColor(.purple)
                Text("AI 即時動態完賽與抵達預測 (AI ETA Engine)")
                    .font(.headline.bold())
                Spacer()
                Text("動態自適應")
                    .font(.caption2.bold())
                    .padding(4)
                    .background(Color.purple.opacity(0.15), in: Capsule())
                    .foregroundColor(.purple)
            }
            
            if let pred = aiPrediction {
                HStack(spacing: 20) {
                    VStack(alignment: .leading) {
                        Text("預計抵達時間")
                            .font(.caption)
                            .foregroundColor(.secondary)
                        Text(formattedDate(pred.estimatedArrivalDate))
                            .font(.title2.bold())
                            .foregroundColor(.purple)
                    }
                    
                    Spacer()
                    
                    VStack(alignment: .trailing) {
                        Text("剩餘所需時間")
                            .font(.caption)
                            .foregroundColor(.secondary)
                        Text(formattedTime(pred.estimatedDurationSeconds))
                            .font(.title2.bold())
                    }
                }
                
                Divider()
                
                Text(pred.explanation)
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
        }
        .padding()
        .background(RoundedRectangle(cornerRadius: 16).fill(.ultraThinMaterial))
        .shadow(radius: 3)
    }
    
    // MARK: - Weather Along Route & Waypoint Rain Timeline
    private var weatherAlongRouteCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Image(systemName: "cloud.rainbow.fill")
                    .foregroundColor(.orange)
                Text("沿途路段路過時間與降雨預報")
                    .font(.headline.bold())
                Spacer()
                Text("動態時段預報")
                    .font(.caption2.bold())
                    .padding(4)
                    .background(Color.orange.opacity(0.15), in: Capsule())
                    .foregroundColor(.orange)
            }
            
            if weatherForecasts.isEmpty {
                Text("尚未載入路線氣象數據")
                    .font(.caption)
                    .foregroundColor(.secondary)
            } else {
                VStack(spacing: 8) {
                    ForEach(weatherForecasts) { wf in
                        weatherForecastRow(wf)
                    }
                }
            }
        }
        .padding()
        .background(RoundedRectangle(cornerRadius: 16).fill(.ultraThinMaterial))
        .shadow(radius: 3)
    }
    
    private func weatherForecastRow(_ wf: RouteWeatherForecast) -> some View {
        HStack(alignment: .center, spacing: 12) {
            // Status / Rain Icon
            ZStack {
                Circle()
                    .fill(wf.isPassed ? Color.gray.opacity(0.2) : (wf.rainProbabilityPercent > 50 ? Color.red.opacity(0.15) : Color.blue.opacity(0.12)))
                    .frame(width: 40, height: 40)
                
                if wf.isPassed {
                    Image(systemName: "checkmark")
                        .foregroundColor(.secondary)
                        .font(.caption.bold())
                } else {
                    Image(systemName: wf.weatherSymbol)
                        .foregroundColor(wf.rainProbabilityPercent > 50 ? .red : (wf.rainProbabilityPercent > 30 ? .orange : .blue))
                        .font(.subheadline)
                }
            }
            
            // Checkpoint Details
            VStack(alignment: .leading, spacing: 3) {
                HStack {
                    Text(wf.waypointName)
                        .font(.subheadline.bold())
                        .foregroundColor(wf.isPassed ? .secondary : .primary)
                    
                    if wf.elevationMeters > 0 {
                        Text("\(Int(wf.elevationMeters))m")
                            .font(.system(size: 10, weight: .bold))
                            .padding(.horizontal, 4)
                            .padding(.vertical, 1)
                            .background(Color.teal.opacity(0.12), in: RoundedRectangle(cornerRadius: 4))
                            .foregroundColor(.teal)
                    }
                }
                
                HStack(spacing: 6) {
                    if wf.isPassed {
                        Text("✅ 已通過")
                            .font(.caption2)
                            .foregroundColor(.secondary)
                    } else {
                        Text("⏱ 預計 \(formattedDate(wf.projectedTime)) 通過")
                            .font(.caption2.bold())
                            .foregroundColor(.purple)
                        Text("· 剩餘 \(String(format: "%.1f", max(0, wf.distanceKm - tracker.currentDistanceKm))) km")
                            .font(.caption2)
                            .foregroundColor(.secondary)
                    }
                }
                
                // 風向與風速指示 (逆風:紅色、順風:綠色、側風:黃橘色)
                windPillBadge(for: wf)
                
                if !wf.advice.isEmpty && !wf.isPassed {
                    Text(wf.advice)
                        .font(.system(size: 10))
                        .foregroundColor(wf.rainProbabilityPercent > 50 ? .orange : .secondary)
                        .lineLimit(1)
                }
            }
            
            Spacer()
            
            // Rain Probability & Temperature
            VStack(alignment: .trailing, spacing: 3) {
                HStack(spacing: 2) {
                    Image(systemName: "drop.fill")
                        .font(.system(size: 10))
                        .foregroundColor(wf.rainProbabilityPercent > 50 ? .red : .blue)
                    Text("\(wf.rainProbabilityPercent)%")
                        .font(.subheadline.bold())
                        .foregroundColor(wf.rainProbabilityPercent > 50 ? .red : (wf.rainProbabilityPercent > 30 ? .orange : .primary))
                }
                
                Text("\(String(format: "%.1f", wf.temperatureC))°C")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
        }
        .padding(10)
        .background(RoundedRectangle(cornerRadius: 12).fill(wf.isPassed ? Color.secondary.opacity(0.04) : Color.secondary.opacity(0.08)))
    }
    
    private func windPillBadge(for wf: RouteWeatherForecast) -> some View {
        let windRel = wf.relativeWind(to: tracker.currentUserHeading)
        return HStack(spacing: 4) {
            Image(systemName: "wind")
                .font(.system(size: 8))
            Text(windRel.description)
                .font(.system(size: 9, weight: .bold))
        }
        .padding(.horizontal, 6)
        .padding(.vertical, 2)
        .background(windRel.color.opacity(0.15), in: Capsule())
        .foregroundColor(windRel.color)
    }
    
    private func updateAIPredictionAndWeather() {
        let userCoord = tracker.currentUserLocation?.coordinate
        let speed = tracker.avgMovingSpeedKmh > 3.0 ? tracker.avgMovingSpeedKmh : (tracker.currentSpeedKmh > 3.0 ? tracker.currentSpeedKmh : 20.0)
        
        let ratio = track.totalDistanceKm > 0 ? min(1.0, tracker.currentDistanceKm / track.totalDistanceKm) : 0.0
        aiPrediction = AIEstimationEngine.shared.predictETA(
            track: track,
            currentUserLocation: userCoord,
            currentProgressRatio: ratio,
            trackerDistanceKm: tracker.currentDistanceKm,
            rollingAvgSpeedKmh: tracker.avgMovingSpeedKmh,
            userBaseSpeedKmh: speed
        )
        weatherForecasts = RouteWeatherService.shared.getRouteForecast(
            track: track,
            currentUserCoord: userCoord,
            currentDistanceKm: tracker.currentDistanceKm,
            currentMovingSpeedKmh: speed
        )
    }
    
    private func formatDistance(_ meters: Double) -> String {
        if meters >= 1000 {
            return String(format: "%.1f 公里", meters / 1000.0)
        } else {
            return "\(Int(meters)) 公尺"
        }
    }
    
    private func formattedDate(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "HH:mm"
        return formatter.string(from: date)
    }
    
    private func formattedTime(_ seconds: TimeInterval) -> String {
        let total = Int(seconds)
        let hrs = total / 3600
        let mins = (total % 3600) / 60
        let secs = total % 60
        if hrs > 0 {
            return String(format: "%d:%02d:%02d", hrs, mins, secs)
        } else {
            return String(format: "%02d:%02d", mins, secs)
        }
    }
}

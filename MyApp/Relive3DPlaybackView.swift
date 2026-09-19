import SwiftUI
import MapKit

public struct Relive3DPlaybackView: View {
    let track: GPXTrack
    @Environment(\.dismiss) private var dismiss
    
    public enum CameraViewMode: String, CaseIterable {
        case followDrone = "🦅 航拍跟隨"
        case overview = "🗺️ 全景鳥瞰"
    }
    
    @State private var cameraMode: CameraViewMode = .followDrone
    @State private var progress: Double = 0.0
    @State private var isPlaying: Bool = false
    @State private var playbackSpeed: Double = 1.0 // 0.5x, 1x, 2x, 3x
    @State private var cameraPosition: MapCameraPosition = .automatic
    @State private var timer: Timer? = nil
    
    // Map tile warm-up & buffering state
    @State private var isMapWarmingUp: Bool = true
    
    // Smooth camera state
    @State private var currentHeading: Double = 0.0
    @State private var currentInterpolatedCoordinate: CLLocationCoordinate2D? = nil
    
    public init(track: GPXTrack) {
        self.track = track
    }
    
    public var body: some View {
        ZStack(alignment: .top) {
            // MapKit 3D Realistic Flyover Map
            if track.points.count > 1 && track.totalDistanceKm > 0.03 {
                main3DPlaybackMap
            } else {
                stationaryActivityFallbackView
            }
            
            // Map Tile Loading Indicator (Warm-up buffer)
            if isMapWarmingUp {
                VStack {
                    Spacer()
                    HStack(spacing: 8) {
                        ProgressView()
                            .tint(.white)
                        Text("3D 衛星與地形圖資緩衝中...")
                            .font(.caption.bold())
                            .foregroundColor(.white)
                    }
                    .padding(.horizontal, 16)
                    .padding(.vertical, 10)
                    .background(Color.black.opacity(0.75), in: Capsule())
                    .shadow(radius: 6)
                    .padding(.bottom, 120)
                }
                .transition(.opacity)
            }
            
            // Floating Top Flight Info HUD & Dismiss Button
            VStack(spacing: 0) {
                topFlightInfoHUD
                    .padding(.horizontal)
                    .padding(.top, 10)
                
                Spacer()
                
                if track.points.count > 1 && track.totalDistanceKm > 0.03 {
                    bottomPlaybackControls
                        .padding()
                }
            }
        }
        .edgesIgnoringSafeArea(track.points.count > 1 ? .bottom : [])
        .onAppear {
            initializePlaybackPosition()
            // Allow 1.2s for initial high-res satellite 3D mesh tiles to stream before action
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.2) {
                withAnimation {
                    isMapWarmingUp = false
                }
            }
        }
        .onDisappear {
            stopPlayback()
        }
    }
    
    // MARK: - Main 3D Playback Map
    private var main3DPlaybackMap: some View {
        Map(position: $cameraPosition) {
            // Completed trail (Solid Vibrant Orange)
            let completed = currentPointsUpToProgress()
            if completed.count > 1 {
                MapPolyline(coordinates: completed.map(\.coordinate))
                    .stroke(
                        LinearGradient(
                            colors: [.orange, .yellow],
                            startPoint: .leading,
                            endPoint: .trailing
                        ),
                        style: StrokeStyle(lineWidth: 6, lineCap: .round, lineJoin: .round)
                    )
            }
            
            // Upcoming trail (Subtle Dashed White)
            MapPolyline(coordinates: track.points.map(\.coordinate))
                .stroke(Color.white.opacity(0.4), style: StrokeStyle(lineWidth: 3, dash: [6, 4]))
            
            // Animated Rider Avatar with Pulsing Halo
            if let liveCoord = currentInterpolatedCoordinate ?? track.points.first?.coordinate {
                Annotation("騎乘者", coordinate: liveCoord) {
                    ZStack {
                        Circle()
                            .fill(Color.orange.opacity(0.35))
                            .frame(width: 46, height: 46)
                        Circle()
                            .fill(Color.white)
                            .frame(width: 28, height: 28)
                            .shadow(color: .black.opacity(0.3), radius: 4)
                        Image(systemName: "figure.outdoor.cycle")
                            .font(.system(size: 15, weight: .bold))
                            .foregroundColor(.orange)
                    }
                }
            }
            
            // Key Waypoints & Milestones
            ForEach(track.waypoints) { wpt in
                Annotation(wpt.name, coordinate: wpt.coordinate) {
                    VStack(spacing: 2) {
                        Image(systemName: wpt.iconName)
                            .font(.system(size: 14, weight: .bold))
                            .foregroundColor(.yellow)
                            .padding(6)
                            .background(Circle().fill(Color.black.opacity(0.75)))
                            .shadow(radius: 2)
                        Text(wpt.name)
                            .font(.system(size: 10, weight: .bold))
                            .foregroundColor(.white)
                            .padding(.horizontal, 5)
                            .padding(.vertical, 2)
                            .background(.ultraThinMaterial, in: Capsule())
                    }
                }
            }
        }
        .mapStyle(.imagery(elevation: .realistic))
        .edgesIgnoringSafeArea(.all)
    }
    
    // MARK: - Stationary Activity Fallback View
    private var stationaryActivityFallbackView: some View {
        ZStack {
            Map(position: $cameraPosition) {
                if let loc = track.points.first {
                    Annotation("活動位置", coordinate: loc.coordinate) {
                        ZStack {
                            Circle().fill(Color.orange.opacity(0.3)).frame(width: 44, height: 44)
                            Image(systemName: "location.circle.fill")
                                .font(.title)
                                .foregroundColor(.orange)
                        }
                    }
                }
            }
            .mapStyle(.standard(elevation: .realistic))
            
            VStack(spacing: 12) {
                Spacer()
                VStack(spacing: 8) {
                    Image(systemName: "figure.stand")
                        .font(.system(size: 40))
                        .foregroundColor(.orange)
                    Text("原地記錄活動")
                        .font(.headline.bold())
                    Text("本次運動為原地停留記錄（總位移小於 30 公尺），尚無連續位移軌跡供 3D 動態巡航重播。")
                        .font(.caption)
                        .foregroundColor(.secondary)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal)
                }
                .padding(20)
                .background(RoundedRectangle(cornerRadius: 16).fill(.ultraThinMaterial))
                .shadow(radius: 6)
                .padding()
                Spacer()
            }
        }
    }
    
    // MARK: - Current Interpolated Point
    private var currentEstimatedPoint: RoutePoint? {
        guard !track.points.isEmpty else { return nil }
        let idx = min(Int(progress), track.points.count - 1)
        return track.points[idx]
    }
    
    private func currentPointsUpToProgress() -> [RoutePoint] {
        guard !track.points.isEmpty else { return [] }
        let endIdx = min(Int(progress) + 1, track.points.count)
        var pts = Array(track.points[0..<endIdx])
        if let live = currentInterpolatedCoordinate {
            let lastEle = pts.last?.elevation ?? 0
            pts.append(RoutePoint(latitude: live.latitude, longitude: live.longitude, elevation: lastEle))
        }
        return pts
    }
    
    // MARK: - Top Flight Info HUD with High-Contrast Dismiss Button
    private var topFlightInfoHUD: some View {
        HStack(spacing: 10) {
            // Prominent Dismiss Button
            Button {
                stopPlayback()
                dismiss()
            } label: {
                Image(systemName: "xmark.circle.fill")
                    .font(.system(size: 32, weight: .medium))
                    .foregroundColor(.white)
                    .background(Circle().fill(Color.black.opacity(0.6)))
                    .shadow(radius: 4)
            }
            .buttonStyle(.plain)
            
            // Title & Status
            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 6) {
                    Circle()
                        .fill(isPlaying ? Color.red : Color.gray)
                        .frame(width: 8, height: 8)
                    Text(isPlaying ? "3D 慢速航拍中" : "3D 航拍已暫停")
                        .font(.system(size: 11, weight: .bold))
                        .foregroundColor(.white)
                }
                
                Text(track.title.isEmpty ? "運動記錄重播" : track.title)
                    .font(.subheadline.bold())
                    .foregroundColor(.white)
                    .lineLimit(1)
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 7)
            .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 12))
            
            Spacer()
            
            // Real-time Flight Metrics (Actual Altitude & Speed)
            if let pt = currentEstimatedPoint {
                HStack(spacing: 10) {
                    VStack(alignment: .trailing, spacing: 1) {
                        Text("海拔")
                            .font(.system(size: 9))
                            .foregroundColor(.white.opacity(0.8))
                        Text("\(Int(pt.elevation)) m")
                            .font(.system(size: 13, weight: .heavy, design: .rounded))
                            .foregroundColor(.yellow)
                    }
                    
                    VStack(alignment: .trailing, spacing: 1) {
                        Text("時速")
                            .font(.system(size: 9))
                            .foregroundColor(.white.opacity(0.8))
                        Text(String(format: "%.1f", pt.speedKmh ?? 0.0))
                            .font(.system(size: 13, weight: .heavy, design: .rounded))
                            .foregroundColor(.white)
                    }
                }
                .padding(.horizontal, 10)
                .padding(.vertical, 7)
                .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 12))
            }
            
            // Recenter Camera Button
            Button {
                recenterCamera()
            } label: {
                Image(systemName: "scope")
                    .font(.system(size: 14, weight: .bold))
                    .foregroundColor(.white)
                    .padding(8)
                    .background(.ultraThinMaterial, in: Circle())
            }
            .buttonStyle(.plain)
        }
    }
    
    // MARK: - Bottom Playback Controls
    private var bottomPlaybackControls: some View {
        VStack(spacing: 10) {
            // Camera Mode Picker
            HStack {
                Picker("鏡頭模式", selection: $cameraMode) {
                    ForEach(CameraViewMode.allCases, id: \.self) { mode in
                        Text(mode.rawValue).tag(mode)
                    }
                }
                .pickerStyle(.segmented)
                .onChange(of: cameraMode) { _ in
                    updateSmoothCamera()
                }
            }
            
            // Progress Scrubbing Slider
            HStack(spacing: 10) {
                Text("0.0 km")
                    .font(.system(size: 11, design: .monospaced))
                    .foregroundColor(.secondary)
                
                Slider(
                    value: Binding(
                        get: { progress },
                        set: { newProg in
                            progress = newProg
                            computeInterpolatedCoordinate()
                            updateSmoothCamera()
                        }
                    ),
                    in: 0...Double(max(1, track.points.count - 1))
                )
                .tint(.orange)
                
                Text(String(format: "%.1f km", track.totalDistanceKm))
                    .font(.system(size: 11, design: .monospaced))
                    .foregroundColor(.secondary)
            }
            
            // Media Controls Row
            HStack(spacing: 16) {
                // Play / Pause Button
                Button {
                    togglePlayback()
                } label: {
                    Image(systemName: isPlaying ? "pause.circle.fill" : "play.circle.fill")
                        .font(.system(size: 42))
                        .foregroundColor(.orange)
                }
                .buttonStyle(.plain)
                
                // Replay from start
                Button {
                    progress = 0.0
                    computeInterpolatedCoordinate()
                    updateSmoothCamera()
                } label: {
                    Label("重頭", systemImage: "backward.fill")
                        .font(.caption.bold())
                }
                .buttonStyle(.bordered)
                
                Spacer()
                
                // Slow / Standard Speed Selector (0.5x, 1x, 2x, 3x)
                Picker("倍速", selection: $playbackSpeed) {
                    Text("0.5x").tag(0.5)
                    Text("1x").tag(1.0)
                    Text("2x").tag(2.0)
                    Text("3x").tag(3.0)
                }
                .pickerStyle(.segmented)
                .frame(width: 175)
            }
        }
        .padding(14)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 18))
        .shadow(color: .black.opacity(0.25), radius: 8, y: 4)
    }
    
    // MARK: - Playback Logic & Smooth Look-Ahead Camera Engine
    private func initializePlaybackPosition() {
        guard let first = track.points.first else { return }
        currentInterpolatedCoordinate = first.coordinate
        
        if track.points.count > 1 {
            let next = track.points[1]
            currentHeading = calculateBearing(from: first.coordinate, to: next.coordinate)
            computeInterpolatedCoordinate()
            updateSmoothCamera()
        } else {
            cameraPosition = .region(MKCoordinateRegion(
                center: first.coordinate,
                span: MKCoordinateSpan(latitudeDelta: 0.008, longitudeDelta: 0.008)
            ))
        }
    }
    
    private func togglePlayback() {
        if isPlaying {
            stopPlayback()
        } else {
            startPlayback()
        }
    }
    
    private func startPlayback() {
        guard track.points.count > 1 else { return }
        if progress >= Double(track.points.count - 1) {
            progress = 0.0
        }
        isPlaying = true
        
        let frameRate: Double = 24.0
        let frameDuration = 1.0 / frameRate
        
        let totalPts = Double(track.points.count)
        
        // 慢速細緻航拍時長控制：
        // 設定基準巡航時長為 75~120 秒，確保網路有充足時間即時下載 3D 衛星與地形高程瓦片
        let baseReplaySeconds: Double = max(75.0, min(130.0, Double(track.points.count) / 6.0))
        let baseStepPerSecond = max(0.15, totalPts / baseReplaySeconds)
        
        timer?.invalidate()
        timer = Timer.scheduledTimer(withTimeInterval: frameDuration, repeats: true) { _ in
            let step = (baseStepPerSecond * self.playbackSpeed) * frameDuration
            let maxProgress = Double(self.track.points.count - 1)
            
            if self.progress + step < maxProgress {
                self.progress += step
                self.computeInterpolatedCoordinate()
                self.updateSmoothCamera()
            } else {
                self.progress = maxProgress
                self.computeInterpolatedCoordinate()
                self.updateSmoothCamera()
                self.stopPlayback()
            }
        }
    }
    
    private func stopPlayback() {
        isPlaying = false
        timer?.invalidate()
        timer = nil
    }
    
    private func recenterCamera() {
        computeInterpolatedCoordinate()
        updateSmoothCamera()
    }
    
    /// 精準內插即時座標，並透過前瞻預判航向
    private func computeInterpolatedCoordinate() {
        guard track.points.count > 1 else { return }
        let count = track.points.count
        let i0 = min(Int(progress), count - 1)
        let i1 = min(i0 + 1, count - 1)
        let fraction = progress - Double(i0)
        
        let p0 = track.points[i0]
        let p1 = track.points[i1]
        
        // 1. 線性座標平滑內插
        let lat = p0.latitude + (p1.latitude - p0.latitude) * fraction
        let lon = p0.longitude + (p1.longitude - p0.longitude) * fraction
        let live = CLLocationCoordinate2D(latitude: lat, longitude: lon)
        self.currentInterpolatedCoordinate = live
        
        // 2. 前瞻航向計算 (Look-Ahead Bearing)
        let lookAheadIdx = min(i0 + 3, count - 1)
        let lookAheadPoint = track.points[lookAheadIdx]
        let targetHeading = calculateBearing(from: live, to: lookAheadPoint.coordinate)
        
        // 3. 最短圓周角阻尼濾波
        var diff = targetHeading - currentHeading
        while diff < -180.0 { diff += 360.0 }
        while diff > 180.0 { diff -= 360.0 }
        currentHeading = (currentHeading + diff * 0.35 + 360.0).truncatingRemainder(dividingBy: 360.0)
    }
    
    private func calculateBearing(from start: CLLocationCoordinate2D, to end: CLLocationCoordinate2D) -> Double {
        let lat1 = start.latitude * .pi / 180.0
        let lon1 = start.longitude * .pi / 180.0
        let lat2 = end.latitude * .pi / 180.0
        let lon2 = end.longitude * .pi / 180.0
        let dLon = lon2 - lon1
        
        let y = sin(dLon) * cos(lat2)
        let x = cos(lat1) * sin(lat2) - sin(lat1) * cos(lat2) * cos(dLon)
        return (atan2(y, x) * 180.0 / .pi + 360.0).truncatingRemainder(dividingBy: 360.0)
    }
    
    /// 即時更新相機：跟隨模式採 1450m 視距與 34° 俯仰角，提供最佳圖資串流效率與壯闊景深
    private func updateSmoothCamera() {
        guard let live = currentInterpolatedCoordinate else { return }
        
        switch cameraMode {
        case .followDrone:
            let camera = MapCamera(
                centerCoordinate: live,
                distance: 1450, // 擴大相機距離至 1450m，降低瓦片層級負擔，確保 3D 衛星網格隨傳隨顯
                heading: currentHeading,
                pitch: 34.0 // 舒適俯仰角
            )
            self.cameraPosition = .camera(camera)
            
        case .overview:
            let camera = MapCamera(
                centerCoordinate: live,
                distance: 2600, // 全景鳥瞰
                heading: 0.0,
                pitch: 0.0
            )
            self.cameraPosition = .camera(camera)
        }
    }
}

import SwiftUI
import MapKit

public struct Relive3DPlaybackView: View {
    let track: GPXTrack
    @Environment(\.dismiss) private var dismiss
    @ObservedObject private var profileStore = UserProfileStore.shared
    
    public enum PlaybackMapStyle: String, CaseIterable {
        case imagery = "3D 衛星"
        case standard = "Apple 標準"
    }
    
    public enum CameraMode: String, CaseIterable {
        case followRider = "聚焦騎士"
        case overview = "全景俯瞰"
    }
    
    @State private var mapStyleSelection: PlaybackMapStyle = .imagery
    @State private var cameraMode: CameraMode = .followRider
    @State private var progress: Double = 0.0
    @State private var isPlaying: Bool = false
    @State private var playbackSpeed: Double = 1.0 // 0.5x, 1x, 2x, 3x
    @State private var cameraPosition: MapCameraPosition = .automatic
    @State private var timer: Timer? = nil
    
    @State private var currentInterpolatedCoordinate: CLLocationCoordinate2D? = nil
    @State private var currentHeading: Double = 0.0
    @State private var frameCounter: Int = 0
    
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
            initializeCamera()
        }
        .onDisappear {
            stopPlayback()
        }
    }
    
    // MARK: - Main 3D Panoramic Playback Map (Zero Deformation & Zero Flickering)
    private var main3DPlaybackMap: some View {
        Map(position: $cameraPosition) {
            // Static Full Track Polyline: Never reconstructed on every frame, eliminating route deformation & flickering
            MapPolyline(coordinates: track.points.map(\.coordinate))
                .stroke(
                    LinearGradient(
                        colors: [.orange, .yellow, .cyan],
                        startPoint: .leading,
                        endPoint: .trailing
                    ),
                    style: StrokeStyle(lineWidth: 6, lineCap: .round, lineJoin: .round)
                )
            
            // Start Flag Pin
            if let start = track.points.first {
                Annotation("起點", coordinate: start.coordinate) {
                    VStack(spacing: 2) {
                        Image(systemName: "flag.fill")
                            .font(.system(size: 11, weight: .bold))
                            .foregroundColor(.white)
                            .padding(5)
                            .background(Circle().fill(Color.green))
                            .shadow(radius: 3)
                        Text("起點")
                            .font(.system(size: 9, weight: .bold))
                            .foregroundColor(.white)
                            .padding(.horizontal, 4)
                            .background(Color.black.opacity(0.7), in: Capsule())
                    }
                }
            }
            
            // Finish Flag Pin
            if let end = track.points.last, track.points.count > 1 {
                Annotation("終點", coordinate: end.coordinate) {
                    VStack(spacing: 2) {
                        Image(systemName: "flag.checkered")
                            .font(.system(size: 11, weight: .bold))
                            .foregroundColor(.white)
                            .padding(5)
                            .background(Circle().fill(Color.orange))
                            .shadow(radius: 3)
                        Text("終點")
                            .font(.system(size: 9, weight: .bold))
                            .foregroundColor(.white)
                            .padding(.horizontal, 4)
                            .background(Color.black.opacity(0.7), in: Capsule())
                    }
                }
            }
            
            // Animated Rider Avatar with User Circular Avatar (Smaller, Sleek, Glowing)
            if let liveCoord = currentInterpolatedCoordinate ?? track.points.first?.coordinate {
                Annotation("騎乘者", coordinate: liveCoord) {
                    VStack(spacing: 2) {
                        // Compact Nickname & Speed Capsule
                        HStack(spacing: 3) {
                            Image(systemName: "figure.outdoor.cycle")
                                .font(.system(size: 8, weight: .bold))
                                .foregroundColor(.orange)
                            Text(profileStore.profile.nickname.isEmpty ? "騎士" : profileStore.profile.nickname)
                                .font(.system(size: 9, weight: .heavy))
                                .foregroundColor(.white)
                            if let pt = currentEstimatedPoint, let spd = pt.speedKmh, spd > 0 {
                                Text(String(format: "%.0f km/h", spd))
                                    .font(.system(size: 8, weight: .bold, design: .rounded))
                                    .foregroundColor(.yellow)
                            }
                        }
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2.5)
                        .background(Color.black.opacity(0.85), in: Capsule())
                        .shadow(color: .black.opacity(0.4), radius: 2)
                        
                        // Circular Small Avatar with Neon Glow Ring (Outer 26pt, Inner 22pt)
                        ZStack {
                            Circle()
                                .fill(LinearGradient(colors: [.orange, .yellow], startPoint: .topLeading, endPoint: .bottomTrailing))
                                .frame(width: 26, height: 26)
                                .shadow(color: .orange.opacity(0.7), radius: 4)
                            
                            if let data = profileStore.profile.avatarData, let uiImg = UIImage(data: data) {
                                Image(uiImage: uiImg)
                                    .resizable()
                                    .scaledToFill()
                                    .frame(width: 22, height: 22)
                                    .clipShape(Circle())
                            } else {
                                ZStack {
                                    Color.black.opacity(0.85)
                                    Image(systemName: "figure.outdoor.cycle")
                                        .font(.system(size: 11, weight: .bold))
                                        .foregroundColor(.orange)
                                }
                                .frame(width: 22, height: 22)
                                .clipShape(Circle())
                            }
                        }
                        
                        // Ground anchor pointer dot
                        Circle()
                            .fill(Color.orange)
                            .frame(width: 4, height: 4)
                            .shadow(color: .orange, radius: 2)
                    }
                }
            }
            
            // Key Waypoints & Milestones
            ForEach(track.waypoints) { wpt in
                Annotation(wpt.name, coordinate: wpt.coordinate) {
                    VStack(spacing: 2) {
                        Image(systemName: wpt.iconName)
                            .font(.system(size: 11, weight: .bold))
                            .foregroundColor(.yellow)
                            .padding(5)
                            .background(Circle().fill(Color.black.opacity(0.75)))
                            .shadow(radius: 2)
                        Text(wpt.name)
                            .font(.system(size: 8, weight: .bold))
                            .foregroundColor(.white)
                            .padding(.horizontal, 4)
                            .padding(.vertical, 2)
                            .background(.ultraThinMaterial, in: Capsule())
                    }
                }
            }
        }
        .mapStyle(mapStyleSelection == .imagery ? .imagery(elevation: .realistic) : .standard(elevation: .realistic))
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
            .mapStyle(mapStyleSelection == .imagery ? .imagery(elevation: .realistic) : .standard(elevation: .realistic))
            
            VStack {
                HStack {
                    Button {
                        dismiss()
                    } label: {
                        Image(systemName: "xmark")
                            .font(.headline)
                            .foregroundColor(.white)
                            .padding(10)
                            .background(Circle().fill(Color.black.opacity(0.6)))
                    }
                    Spacer()
                }
                .padding()
                
                Spacer()
                
                Text("此活動無足夠位移軌跡，無法進行 3D 巡航重播。")
                    .font(.subheadline)
                    .foregroundColor(.white)
                    .padding()
                    .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 12))
                    .padding(.bottom, 40)
            }
        }
    }
    
    // MARK: - Top Flight HUD
    private var topFlightInfoHUD: some View {
        HStack(spacing: 8) {
            Button {
                dismiss()
            } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 13, weight: .bold))
                    .foregroundColor(.white)
                    .padding(8)
                    .background(.ultraThinMaterial, in: Circle())
            }
            .buttonStyle(.plain)
            
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 4) {
                    Circle()
                        .fill(isPlaying ? Color.green : Color.gray)
                        .frame(width: 7, height: 7)
                    Text(isPlaying ? "3D 巡航中" : "已暫停")
                        .font(.system(size: 10, weight: .bold))
                        .foregroundColor(.white)
                }
                
                Text(track.title.isEmpty ? "運動重播" : track.title)
                    .font(.subheadline.bold())
                    .foregroundColor(.white)
                    .lineLimit(1)
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 6)
            .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 10))
            
            Spacer()
            
            if let pt = currentEstimatedPoint {
                HStack(spacing: 8) {
                    VStack(alignment: .trailing, spacing: 1) {
                        Text("海拔")
                            .font(.system(size: 8))
                            .foregroundColor(.white.opacity(0.8))
                        Text("\(Int(pt.elevation)) m")
                            .font(.system(size: 12, weight: .heavy, design: .rounded))
                            .foregroundColor(.yellow)
                    }
                    
                    VStack(alignment: .trailing, spacing: 1) {
                        Text("時速")
                            .font(.system(size: 8))
                            .foregroundColor(.white.opacity(0.8))
                        Text(String(format: "%.1f", pt.speedKmh ?? 0.0))
                            .font(.system(size: 12, weight: .heavy, design: .rounded))
                            .foregroundColor(.white)
                    }
                }
                .padding(.horizontal, 8)
                .padding(.vertical, 6)
                .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 10))
            }
            
            // Camera Mode Toggle: Follow Rider vs Overview
            Button {
                withAnimation(.easeInOut(duration: 0.5)) {
                    if cameraMode == .followRider {
                        cameraMode = .overview
                        zoomToOverview()
                    } else {
                        cameraMode = .followRider
                        zoomToRider(animated: true)
                    }
                }
            } label: {
                HStack(spacing: 4) {
                    Image(systemName: cameraMode == .followRider ? "scope" : "map")
                        .font(.system(size: 11, weight: .bold))
                    Text(cameraMode == .followRider ? "追隨騎士" : "全景俯瞰")
                        .font(.system(size: 10, weight: .bold))
                }
                .foregroundColor(.white)
                .padding(.horizontal, 8)
                .padding(.vertical, 6)
                .background(Color.orange.opacity(0.85), in: Capsule())
            }
            .buttonStyle(.plain)
        }
    }
    
    // MARK: - Bottom Playback Controls
    private var bottomPlaybackControls: some View {
        VStack(spacing: 10) {
            // Map Style Toggle
            Picker("地圖樣式", selection: $mapStyleSelection) {
                ForEach(PlaybackMapStyle.allCases, id: \.self) { style in
                    Text(style.rawValue).tag(style)
                }
            }
            .pickerStyle(.segmented)
            
            // Progress Scrubbing Slider
            HStack(spacing: 10) {
                Text("0.0 km")
                    .font(.system(size: 10, design: .monospaced))
                    .foregroundColor(.secondary)
                
                Slider(
                    value: Binding(
                        get: { progress },
                        set: { newProg in
                            progress = newProg
                            computeInterpolatedCoordinate()
                            if cameraMode == .followRider {
                                zoomToRider(animated: false)
                            }
                        }
                    ),
                    in: 0...Double(max(1, track.points.count - 1))
                )
                .tint(.orange)
                
                Text(String(format: "%.1f km", track.totalDistanceKm))
                    .font(.system(size: 10, design: .monospaced))
                    .foregroundColor(.secondary)
            }
            
            // Media Controls Row
            HStack(alignment: .center) {
                Button {
                    progress = 0.0
                    computeInterpolatedCoordinate()
                    if cameraMode == .followRider {
                        zoomToRider(animated: true)
                    }
                } label: {
                    HStack(spacing: 4) {
                        Image(systemName: "backward.fill")
                        Text("起點")
                    }
                    .font(.caption.bold())
                    .padding(.horizontal, 10)
                    .padding(.vertical, 7)
                }
                .buttonStyle(.bordered)
                .tint(.primary)
                
                Spacer()
                
                Button {
                    togglePlayback()
                } label: {
                    Image(systemName: isPlaying ? "pause.circle.fill" : "play.circle.fill")
                        .font(.system(size: 44))
                        .foregroundColor(.orange)
                }
                .buttonStyle(.plain)
                
                Spacer()
                
                Picker("倍速", selection: $playbackSpeed) {
                    Text("0.5x").tag(0.5)
                    Text("1x").tag(1.0)
                    Text("2x").tag(2.0)
                    Text("3x").tag(3.0)
                }
                .pickerStyle(.segmented)
                .frame(width: 140)
            }
        }
        .padding(12)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 16))
        .shadow(color: .black.opacity(0.25), radius: 6, y: 3)
    }
    
    // MARK: - Camera Control
    private func initializeCamera() {
        guard !track.points.isEmpty else { return }
        currentInterpolatedCoordinate = track.points.first?.coordinate
        computeInterpolatedCoordinate()
        if cameraMode == .followRider {
            zoomToRider(animated: false)
        } else {
            zoomToOverview()
        }
    }
    
    private func zoomToRider(animated: Bool) {
        guard let coord = currentInterpolatedCoordinate ?? track.points.first?.coordinate else { return }
        let camera = MapCamera(
            centerCoordinate: coord,
            distance: 1400, // 3D Satellite Flyover altitude
            heading: currentHeading,
            pitch: 45 // 3D dynamic perspective
        )
        if animated {
            withAnimation(.easeInOut(duration: 0.6)) {
                self.cameraPosition = .camera(camera)
            }
        } else {
            self.cameraPosition = .camera(camera)
        }
    }
    
    private func zoomToOverview() {
        guard !track.points.isEmpty else { return }
        let lats = track.points.map(\.latitude)
        let lons = track.points.map(\.longitude)
        guard let minLat = lats.min(), let maxLat = lats.max(),
              let minLon = lons.min(), let maxLon = lons.max() else { return }
        
        let center = CLLocationCoordinate2D(
            latitude: (minLat + maxLat) / 2.0,
            longitude: (minLon + maxLon) / 2.0
        )
        let spanLat = max(0.015, (maxLat - minLat) * 1.5)
        let spanLon = max(0.015, (maxLon - minLon) * 1.5)
        
        withAnimation(.easeInOut(duration: 0.8)) {
            self.cameraPosition = .region(MKCoordinateRegion(
                center: center,
                span: MKCoordinateSpan(latitudeDelta: spanLat, longitudeDelta: spanLon)
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
        
        let frameRate: Double = 30.0
        let frameDuration = 1.0 / frameRate
        let totalPts = Double(track.points.count)
        
        let baseReplaySeconds: Double = max(35.0, min(80.0, totalPts / 6.0))
        let baseStepPerSecond = max(0.3, totalPts / baseReplaySeconds)
        
        frameCounter = 0
        timer?.invalidate()
        timer = Timer.scheduledTimer(withTimeInterval: frameDuration, repeats: true) { _ in
            let step = (baseStepPerSecond * self.playbackSpeed) * frameDuration
            let maxProgress = Double(self.track.points.count - 1)
            
            if self.progress + step < maxProgress {
                self.progress += step
                self.computeInterpolatedCoordinate()
            } else {
                self.progress = maxProgress
                self.computeInterpolatedCoordinate()
                self.stopPlayback()
            }
            
            self.frameCounter += 1
            // Smoothly update camera focus on rider every 5 frames (~6 times/sec) to avoid tile thrashing
            if self.cameraMode == .followRider && self.frameCounter % 5 == 0 {
                if let coord = self.currentInterpolatedCoordinate {
                    withAnimation(.linear(duration: frameDuration * 5.0)) {
                        self.cameraPosition = .camera(MapCamera(
                            centerCoordinate: coord,
                            distance: 1400,
                            heading: self.currentHeading,
                            pitch: 45
                        ))
                    }
                }
            }
        }
    }
    
    private func stopPlayback() {
        isPlaying = false
        timer?.invalidate()
        timer = nil
    }
    
    private func computeInterpolatedCoordinate() {
        guard track.points.count > 1 else { return }
        let count = track.points.count
        let i0 = min(Int(progress), count - 1)
        let i1 = min(i0 + 1, count - 1)
        let fraction = progress - Double(i0)
        
        let p0 = track.points[i0]
        let p1 = track.points[i1]
        
        let lat = p0.latitude + (p1.latitude - p0.latitude) * fraction
        let lon = p0.longitude + (p1.longitude - p0.longitude) * fraction
        self.currentInterpolatedCoordinate = CLLocationCoordinate2D(latitude: lat, longitude: lon)
        
        // Calculate heading from p0 to p1
        if i0 != i1 {
            let lat1 = p0.latitude * .pi / 180.0
            let lon1 = p0.longitude * .pi / 180.0
            let lat2 = p1.latitude * .pi / 180.0
            let lon2 = p1.longitude * .pi / 180.0
            let dLon = lon2 - lon1
            let y = sin(dLon) * cos(lat2)
            let x = cos(lat1) * sin(lat2) - sin(lat1) * cos(lat2) * cos(dLon)
            let rawBearing = (atan2(y, x) * 180.0 / .pi + 360.0).truncatingRemainder(dividingBy: 360.0)
            
            // Smooth heading transition
            let diff = (rawBearing - self.currentHeading + 540.0).truncatingRemainder(dividingBy: 360.0) - 180.0
            self.currentHeading = (self.currentHeading + diff * 0.2 + 360.0).truncatingRemainder(dividingBy: 360.0)
        }
    }
    
    private var currentEstimatedPoint: RoutePoint? {
        guard !track.points.isEmpty else { return nil }
        let idx = min(Int(progress), track.points.count - 1)
        return track.points[idx]
    }
}

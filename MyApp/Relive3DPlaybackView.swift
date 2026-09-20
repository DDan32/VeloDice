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
    
    @State private var mapStyleSelection: PlaybackMapStyle = .imagery
    @State private var progress: Double = 0.0
    @State private var isPlaying: Bool = false
    @State private var playbackSpeed: Double = 1.0 // 0.5x, 1x, 2x, 3x
    @State private var cameraPosition: MapCameraPosition = .automatic
    @State private var timer: Timer? = nil
    
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
            initializePanoramicCamera()
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
                            .font(.system(size: 12, weight: .bold))
                            .foregroundColor(.white)
                            .padding(6)
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
                            .font(.system(size: 13, weight: .bold))
                            .foregroundColor(.white)
                            .padding(6)
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
            
            // Animated Rider Avatar with User Custom Square Avatar and Nickname Tag
            if let liveCoord = currentInterpolatedCoordinate ?? track.points.first?.coordinate {
                Annotation("騎乘者", coordinate: liveCoord) {
                    VStack(spacing: 3) {
                        // User Nickname Bubble with Live Speed
                        HStack(spacing: 4) {
                            Image(systemName: "figure.outdoor.cycle")
                                .font(.system(size: 9, weight: .bold))
                                .foregroundColor(.orange)
                            Text(profileStore.profile.nickname)
                                .font(.system(size: 10, weight: .heavy))
                                .foregroundColor(.white)
                            if let pt = currentEstimatedPoint, let spd = pt.speedKmh, spd > 0 {
                                Text(String(format: "%.0f km/h", spd))
                                    .font(.system(size: 9, weight: .bold, design: .rounded))
                                    .foregroundColor(.yellow)
                            }
                        }
                        .padding(.horizontal, 8)
                        .padding(.vertical, 3)
                        .background(Color.black.opacity(0.85), in: Capsule())
                        .shadow(color: .black.opacity(0.5), radius: 3)
                        
                        // Square Avatar with Neon Orange Border
                        ZStack {
                            RoundedRectangle(cornerRadius: 8)
                                .fill(LinearGradient(colors: [.orange, .yellow], startPoint: .topLeading, endPoint: .bottomTrailing))
                                .frame(width: 36, height: 36)
                                .shadow(color: .orange.opacity(0.5), radius: 4)
                            
                            if let data = profileStore.profile.avatarData, let uiImg = UIImage(data: data) {
                                Image(uiImage: uiImg)
                                    .resizable()
                                    .scaledToFill()
                                    .frame(width: 31, height: 31)
                                    .clipShape(RoundedRectangle(cornerRadius: 6))
                            } else {
                                ZStack {
                                    Color.black.opacity(0.85)
                                    Image(systemName: "person.fill")
                                        .font(.system(size: 16))
                                        .foregroundColor(.white)
                                }
                                .frame(width: 31, height: 31)
                                .clipShape(RoundedRectangle(cornerRadius: 6))
                            }
                        }
                    }
                }
            }
            
            // Key Waypoints & Milestones
            ForEach(track.waypoints) { wpt in
                Annotation(wpt.name, coordinate: wpt.coordinate) {
                    VStack(spacing: 2) {
                        Image(systemName: wpt.iconName)
                            .font(.system(size: 13, weight: .bold))
                            .foregroundColor(.yellow)
                            .padding(6)
                            .background(Circle().fill(Color.black.opacity(0.75)))
                            .shadow(radius: 2)
                        Text(wpt.name)
                            .font(.system(size: 9, weight: .bold))
                            .foregroundColor(.white)
                            .padding(.horizontal, 5)
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
    
    // MARK: - Top Flight Info HUD with High-Contrast Dismiss Button
    private var topFlightInfoHUD: some View {
        HStack(spacing: 10) {
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
            
            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 6) {
                    Circle()
                        .fill(isPlaying ? Color.green : Color.gray)
                        .frame(width: 8, height: 8)
                    Text(isPlaying ? "3D 全景重播中" : "3D 全景已暫停")
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
            
            Button {
                recenterPanoramicCamera()
            } label: {
                Image(systemName: "arrow.triangle.2.circlepath.camera")
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
        VStack(spacing: 12) {
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
                    .font(.system(size: 11, design: .monospaced))
                    .foregroundColor(.secondary)
                
                Slider(
                    value: Binding(
                        get: { progress },
                        set: { newProg in
                            progress = newProg
                            computeInterpolatedCoordinate()
                        }
                    ),
                    in: 0...Double(max(1, track.points.count - 1))
                )
                .tint(.orange)
                
                Text(String(format: "%.1f km", track.totalDistanceKm))
                    .font(.system(size: 11, design: .monospaced))
                    .foregroundColor(.secondary)
            }
            
            // Media Controls Row: Centered & Balanced
            HStack(alignment: .center) {
                Button {
                    progress = 0.0
                    computeInterpolatedCoordinate()
                } label: {
                    HStack(spacing: 4) {
                        Image(systemName: "backward.fill")
                        Text("回到起點")
                    }
                    .font(.caption.bold())
                    .padding(.horizontal, 10)
                    .padding(.vertical, 8)
                }
                .buttonStyle(.bordered)
                .tint(.primary)
                
                Spacer()
                
                Button {
                    togglePlayback()
                } label: {
                    Image(systemName: isPlaying ? "pause.circle.fill" : "play.circle.fill")
                        .font(.system(size: 46))
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
                .frame(width: 145)
            }
        }
        .padding(14)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 18))
        .shadow(color: .black.opacity(0.25), radius: 8, y: 4)
    }
    
    // MARK: - Panoramic Camera Setup & Playback Engine
    private func initializePanoramicCamera() {
        guard !track.points.isEmpty else { return }
        currentInterpolatedCoordinate = track.points.first?.coordinate
        recenterPanoramicCamera()
    }
    
    private func recenterPanoramicCamera() {
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
        
        // Adaptive replay duration (40~90s for standard replay)
        let baseReplaySeconds: Double = max(40.0, min(90.0, totalPts / 6.0))
        let baseStepPerSecond = max(0.25, totalPts / baseReplaySeconds)
        
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
    }
}

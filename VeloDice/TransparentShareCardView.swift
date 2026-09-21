import SwiftUI
import UniformTypeIdentifiers
import Photos
import MapKit
#if os(iOS)
import UIKit
#elseif os(macOS)
import AppKit
#endif

#if os(iOS)
// Helper for iOS Native System Share Sheet (AirDrop, Save to Files, Social, etc.)
public struct ActivityShareSheet: UIViewControllerRepresentable {
    public let items: [Any]
    
    public init(items: [Any]) {
        self.items = items
    }
    
    public func makeUIViewController(context: Context) -> UIActivityViewController {
        let controller = UIActivityViewController(activityItems: items, applicationActivities: nil)
        return controller
    }
    
    public func updateUIViewController(_ uiViewController: UIActivityViewController, context: Context) {}
}
#endif

public enum ShareCardMetric: String, CaseIterable, Identifiable {
    case distance = "總里程"
    case elevation = "總爬升"
    case movingTime = "運動耗時"
    case avgSpeed = "運動均速"
    case maxSpeed = "極速"
    case calories = "熱量消耗"
    case cadence = "平均踏頻"
    case heartRate = "平均心率"
    case power = "平均功率"
    
    public var id: String { rawValue }
}

public struct TransparentShareCardView: View {
    let track: GPXTrack
    @Environment(\.dismiss) private var dismiss
    
    public enum CardTheme: String, CaseIterable {
        case pureRouteSticker = "純路線貼圖"
        case transparentDark = "去背純黑浮印"
        case transparentWhite = "去背純白浮印"
        case mapBackground = "路線+地圖背景"
        case glassMorphism = "毛玻璃霧面"
    }
    
    @State private var selectedTheme: CardTheme = .pureRouteSticker
    @State private var alertTitle: String = "提示"
    @State private var alertMessage: String = ""
    @State private var showAlert: Bool = false
    @State private var openInstagramAfterAlert: Bool = false
    
    // Customizable metrics
    @State private var visibleMetrics: Set<ShareCardMetric> = [
        .distance, .elevation, .movingTime, .avgSpeed
    ]
    @State private var showCustomMetricsSheet: Bool = false
    
    #if os(iOS)
    @State private var shareSheetItems: [Any] = []
    @State private var showShareSheet: Bool = false
    #endif
    
    public init(track: GPXTrack) {
        self.track = track
    }
    
    // MARK: - 100% 依據實際記錄之真實數據
    private var actualTitle: String {
        track.title.isEmpty ? "戶外騎行紀錄" : track.title
    }
    
    private var actualDistanceKm: Double {
        track.totalDistanceKm
    }
    
    private var actualElevationMeters: Double {
        track.totalAscentMeters
    }
    
    private var actualDurationSeconds: TimeInterval {
        if let first = track.points.first?.timestamp, let last = track.points.last?.timestamp, last > first {
            return last.timeIntervalSince(first)
        }
        return 0
    }
    
    private var actualMovingDurationSeconds: TimeInterval {
        var moving: TimeInterval = 0
        guard track.points.count > 1 else { return actualDurationSeconds }
        for i in 1..<track.points.count {
            let p0 = track.points[i - 1]
            let p1 = track.points[i]
            if let t0 = p0.timestamp, let t1 = p1.timestamp, t1 > t0 {
                let dt = t1.timeIntervalSince(t0)
                if dt > 0 && dt <= 10 {
                    let d = CLLocation(latitude: p0.latitude, longitude: p0.longitude).distance(from: CLLocation(latitude: p1.latitude, longitude: p1.longitude))
                    let spd = d / dt
                    if spd >= 0.8 { // 速度 > ~3 km/h
                        moving += dt
                    }
                }
            }
        }
        return moving > 0 ? moving : actualDurationSeconds
    }
    
    private var actualAvgSpeedKmh: Double {
        let hrs = actualMovingDurationSeconds / 3600.0
        return (hrs > 0 && actualDistanceKm >= 0.03) ? (actualDistanceKm / hrs) : 0.0
    }
    
    private var actualMaxSpeedKmh: Double {
        let validSpeeds = track.points.compactMap(\.speedKmh).filter { $0 > 0 }
        return validSpeeds.max() ?? 0.0
    }
    
    private var actualCalories: Int {
        actualDistanceKm > 0 ? Int(actualDistanceKm * 32.0 + actualElevationMeters * 0.8) : 0
    }
    
    private var actualAvgCadence: Int? {
        let cads = track.points.compactMap(\.cadence).filter { $0 > 0 }
        guard !cads.isEmpty else { return nil }
        return cads.reduce(0, +) / cads.count
    }
    
    private var actualAvgHeartRate: Int? {
        let hrs = track.points.compactMap(\.heartRate).filter { $0 > 0 }
        guard !hrs.isEmpty else { return nil }
        return hrs.reduce(0, +) / hrs.count
    }
    
    private var actualAvgPower: Int? {
        let pows = track.points.compactMap(\.powerWatts).filter { $0 > 0 }
        guard !pows.isEmpty else { return nil }
        return pows.reduce(0, +) / pows.count
    }
    
    private var actualDateString: String {
        if let date = track.points.first?.timestamp {
            return date.formatted(date: .numeric, time: .shortened)
        }
        return Date().formatted(date: .numeric, time: .shortened)
    }
    
    public var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 16) {
                    // Theme selector
                    Picker("卡片風格", selection: $selectedTheme) {
                        ForEach(CardTheme.allCases, id: \.self) { theme in
                            Text(theme.rawValue).tag(theme)
                        }
                    }
                    .pickerStyle(.segmented)
                    .padding(.horizontal)
                    
                    // Card Preview Container
                    ZStack {
                        if selectedTheme == .pureRouteSticker || selectedTheme == .transparentDark || selectedTheme == .transparentWhite {
                            checkerboardBackground
                                .frame(width: 360, height: 480)
                                .clipShape(RoundedRectangle(cornerRadius: 24))
                        }
                        
                        shareCardHUD
                            .frame(width: 360, height: 480)
                    }
                    .shadow(color: .black.opacity(0.18), radius: 10, x: 0, y: 5)
                    
                    if selectedTheme == .pureRouteSticker {
                        Text("💡 純路線貼圖模式：無底框、無日期與標題，可自由勾選下方數據，分享到 IG 即為高反差純去背路線懸浮貼圖！")
                            .font(.caption2)
                            .foregroundColor(.orange)
                            .multilineTextAlignment(.center)
                            .padding(.horizontal, 24)
                    }
                    
                    // Customizable Metrics Selector
                    VStack(alignment: .leading, spacing: 8) {
                        HStack {
                            Text("選擇顯示數據 (點擊切換)")
                                .font(.subheadline.bold())
                                .foregroundColor(.secondary)
                            Spacer()
                            Text("已勾選 \(visibleMetrics.count) 項")
                                .font(.caption.bold())
                                .foregroundColor(.orange)
                        }
                        
                        ScrollView(.horizontal, showsIndicators: false) {
                            HStack(spacing: 8) {
                                ForEach(ShareCardMetric.allCases) { metric in
                                    let isSelected = visibleMetrics.contains(metric)
                                    Button {
                                        if isSelected {
                                            if visibleMetrics.count > 1 {
                                                visibleMetrics.remove(metric)
                                            }
                                        } else {
                                            visibleMetrics.insert(metric)
                                        }
                                    } label: {
                                        HStack(spacing: 4) {
                                            Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                                                .font(.caption)
                                            Text(metric.rawValue)
                                                .font(.caption.bold())
                                        }
                                        .padding(.horizontal, 10)
                                        .padding(.vertical, 6)
                                        .background(isSelected ? Color.orange : Color.secondary.opacity(0.12), in: Capsule())
                                        .foregroundColor(isSelected ? .white : .primary)
                                    }
                                    .buttonStyle(.plain)
                                }
                            }
                        }
                    }
                    .padding(.horizontal)
                    
                    // Export Actions
                    VStack(spacing: 12) {
                        #if os(iOS)
                        // Instagram Stories Direct Button
                        Button {
                            shareToInstagramStories()
                        } label: {
                            HStack(spacing: 8) {
                                Image(systemName: "camera.circle.fill")
                                    .font(.title3)
                                Text("分享至 Instagram 限時動態")
                                    .font(.headline)
                            }
                            .foregroundColor(.white)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 14)
                            .background(
                                LinearGradient(
                                    colors: [Color(red: 0.51, green: 0.18, blue: 0.87), Color(red: 0.88, green: 0.19, blue: 0.42), Color(red: 0.98, green: 0.73, blue: 0.23)],
                                    startPoint: .leading,
                                    endPoint: .trailing
                                ),
                                in: RoundedRectangle(cornerRadius: 14)
                            )
                            .shadow(color: Color.purple.opacity(0.35), radius: 6, y: 3)
                        }
                        .buttonStyle(.plain)
                        
                        // Copy Sticker to Clipboard (Instagram Story Instant Popup)
                        Button {
                            copyStickerToClipboard()
                        } label: {
                            HStack(spacing: 6) {
                                Image(systemName: "doc.on.doc.fill")
                                Text("複製去背貼圖（打開 IG 拍限動自動貼上）")
                            }
                            .font(.subheadline.bold())
                            .foregroundColor(.orange)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 11)
                            .background(Color.orange.opacity(0.12), in: RoundedRectangle(cornerRadius: 12))
                        }
                        .buttonStyle(.plain)
                        #endif
                        
                        HStack(spacing: 12) {
                            // Primary: Save to Photos
                            Button {
                                exportTransparentPNG()
                            } label: {
                                Label("儲存至相簿", systemImage: "photo.badge.arrow.down.fill")
                                    .font(.subheadline.bold())
                                    .frame(maxWidth: .infinity)
                                    .padding(.vertical, 11)
                            }
                            .buttonStyle(.borderedProminent)
                            .tint(.orange)
                            
                            #if os(iOS)
                            // Secondary: System Share
                            Button {
                                triggerSystemShare()
                            } label: {
                                Label("系統分享 / 檔案", systemImage: "square.and.arrow.up")
                                    .font(.subheadline.bold())
                                    .frame(maxWidth: .infinity)
                                    .padding(.vertical, 11)
                            }
                            .buttonStyle(.bordered)
                            #else
                            Button {
                                copyCardToClipboard()
                            } label: {
                                Label("複製到剪貼簿", systemImage: "doc.on.doc.fill")
                                    .font(.subheadline.bold())
                                    .frame(maxWidth: .infinity)
                                    .padding(.vertical, 11)
                            }
                            .buttonStyle(.bordered)
                            #endif
                        }
                        
                        // Strava / Velodash GPX Export
                        Button {
                            shareGPXForCyclingApps()
                        } label: {
                            HStack(spacing: 6) {
                                Image(systemName: "arrow.triangle.swap")
                                Text("匯出 GPX 至 Strava / Velodash")
                            }
                            .font(.caption.bold())
                            .foregroundColor(.secondary)
                        }
                        .padding(.top, 4)
                    }
                    .padding(.horizontal)
                }
                .padding(.vertical)
            }
            .navigationTitle("分享活動")
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("關閉") { dismiss() }
                }
            }
            .alert(alertTitle, isPresented: $showAlert) {
                if openInstagramAfterAlert {
                    Button("打開 Instagram") {
                        #if os(iOS)
                        if let url = URL(string: "instagram://app"), UIApplication.shared.canOpenURL(url) {
                            UIApplication.shared.open(url)
                        }
                        #endif
                    }
                    Button("好", role: .cancel) { }
                } else {
                    Button("好", role: .cancel) { }
                }
            } message: {
                Text(alertMessage)
            }
            #if os(iOS)
            .sheet(isPresented: $showShareSheet) {
                if !shareSheetItems.isEmpty {
                    ActivityShareSheet(items: shareSheetItems)
                }
            }
            #endif
        }
    }
    
    // MARK: - The Share Card View (Pure Route Sticker vs Standard HUD)
    @ViewBuilder
    private var shareCardHUD: some View {
        if selectedTheme == .pureRouteSticker {
            pureRouteStickerView
        } else {
            standardCardHUD
        }
    }
    
    // MARK: - Pure Route Sticker (Only Route Outline + Selectable Stats, No Date, No Title, No Box!)
    private var pureRouteStickerView: some View {
        VStack(spacing: 14) {
            // Real GPS Track Outline
            if track.points.count > 1 && track.totalDistanceKm > 0.03 {
                RouteSilhouetteShape(points: track.points)
                    .stroke(
                        LinearGradient(
                            colors: [.orange, .yellow],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        ),
                        style: StrokeStyle(lineWidth: 5.5, lineCap: .round, lineJoin: .round)
                    )
                    .shadow(color: .black.opacity(0.8), radius: 5, x: 0, y: 2)
                    .frame(height: 220)
                    .padding(.horizontal, 24)
            } else {
                VStack(spacing: 8) {
                    Image(systemName: "figure.outdoor.cycle")
                        .font(.system(size: 40))
                        .foregroundColor(.orange)
                    Text("騎乘軌跡")
                        .font(.headline.bold())
                        .foregroundColor(.white)
                }
                .frame(height: 200)
            }
            
            // Customizable Real Metric Stats (Floating text, high-contrast drop shadow)
            let selectedList = ShareCardMetric.allCases.filter { visibleMetrics.contains($0) }
            LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible()), GridItem(.flexible())], spacing: 12) {
                ForEach(selectedList) { metric in
                    pureMetricPill(metric: metric)
                }
            }
            .padding(.horizontal, 16)
        }
        .padding(.vertical, 20)
        .background(Color.clear) // Absolutely transparent!
    }
    
    private func pureMetricPill(metric: ShareCardMetric) -> some View {
        VStack(spacing: 2) {
            Text(metric.rawValue)
                .font(.system(size: 11, weight: .bold))
                .foregroundColor(.white.opacity(0.85))
                .shadow(color: .black.opacity(0.9), radius: 3, x: 0, y: 1)
            
            HStack(alignment: .firstTextBaseline, spacing: 2) {
                Text(statValueFor(metric))
                    .font(.system(size: 21, weight: .heavy, design: .rounded))
                    .foregroundColor(.white)
                    .shadow(color: .black.opacity(0.95), radius: 4, x: 0, y: 1.5)
                
                let unit = statUnitFor(metric)
                if !unit.isEmpty {
                    Text(unit)
                        .font(.system(size: 9, weight: .black, design: .rounded))
                        .foregroundColor(.orange)
                        .shadow(color: .black.opacity(0.9), radius: 3, x: 0, y: 1)
                }
            }
        }
        .frame(maxWidth: .infinity)
    }
    
    // MARK: - Standard Card HUD (With Background & Frame)
    private var standardCardHUD: some View {
        VStack(alignment: .leading, spacing: 12) {
            // Header: App badge & Date
            HStack {
                HStack(spacing: 6) {
                    Image(systemName: "flame.fill")
                        .foregroundColor(.orange)
                    Text(AppConstants.appName.uppercased())
                        .font(.system(size: 14, weight: .black, design: .rounded))
                        .foregroundColor(textColor)
                }
                Spacer()
                Text(actualDateString)
                    .font(.system(size: 12, weight: .semibold, design: .monospaced))
                    .foregroundColor(textColor.opacity(0.85))
            }
            
            // Route Title
            Text(actualTitle)
                .font(.system(size: 20, weight: .heavy, design: .rounded))
                .foregroundColor(textColor)
                .lineLimit(1)
            
            // Real GPS Track Outline or Map Background
            ZStack {
                if selectedTheme == .mapBackground {
                    if track.points.count > 1 {
                        Map(position: .constant(.region(trackRegion()))) {
                            MapPolyline(coordinates: track.points.map(\.coordinate))
                                .stroke(Color.orange, style: StrokeStyle(lineWidth: 5, lineCap: .round, lineJoin: .round))
                        }
                        .mapStyle(.standard(pointsOfInterest: .excludingAll))
                        .clipShape(RoundedRectangle(cornerRadius: 16))
                        .disabled(true)
                    } else {
                        RoundedRectangle(cornerRadius: 16)
                            .fill(Color.secondary.opacity(0.15))
                    }
                } else {
                    RoundedRectangle(cornerRadius: 16)
                        .fill(themeInnerBackground)
                    
                    if track.points.count > 1 && track.totalDistanceKm > 0.03 {
                        RouteSilhouetteShape(points: track.points)
                            .stroke(routeStrokeColor, style: StrokeStyle(lineWidth: 4, lineCap: .round, lineJoin: .round))
                            .padding(18)
                    } else {
                        VStack(spacing: 6) {
                            Image(systemName: "location.circle.fill")
                                .font(.system(size: 32))
                                .foregroundColor(.orange)
                            Text("原地活動 · 無位移軌跡")
                                .font(.caption.bold())
                                .foregroundColor(textColor.opacity(0.8))
                        }
                    }
                }
            }
            .frame(height: 175)
            
            // Customizable Real Metric Stats Grid
            let selectedList = ShareCardMetric.allCases.filter { visibleMetrics.contains($0) }
            LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible()), GridItem(.flexible())], spacing: 10) {
                ForEach(selectedList) { metric in
                    statBlock(title: metric.rawValue, value: statValueFor(metric), unit: statUnitFor(metric))
                }
            }
            .padding(.horizontal, 4)
            .padding(.top, 4)
        }
        .padding(20)
        .background(cardBackground)
        .clipShape(RoundedRectangle(cornerRadius: 24))
        .overlay(
            RoundedRectangle(cornerRadius: 24)
                .stroke(cardBorderColor, lineWidth: 1.5)
        )
    }
    
    private func trackRegion() -> MKCoordinateRegion {
        guard !track.points.isEmpty else {
            return MKCoordinateRegion(center: CLLocationCoordinate2D(latitude: 25.033, longitude: 121.565), span: MKCoordinateSpan(latitudeDelta: 0.05, longitudeDelta: 0.05))
        }
        let lats = track.points.map(\.latitude)
        let lons = track.points.map(\.longitude)
        let center = CLLocationCoordinate2D(latitude: (lats.min()! + lats.max()!) / 2.0, longitude: (lons.min()! + lons.max()!) / 2.0)
        let span = MKCoordinateSpan(latitudeDelta: max(0.02, (lats.max()! - lats.min()!) * 1.3), longitudeDelta: max(0.02, (lons.max()! - lons.min()!) * 1.3))
        return MKCoordinateRegion(center: center, span: span)
    }
    
    private func statBlock(title: String, value: String, unit: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(title)
                .font(.system(size: 10, weight: .bold))
                .foregroundColor(textColor.opacity(0.65))
            HStack(alignment: .lastTextBaseline, spacing: 2) {
                Text(value)
                    .font(.system(size: 17, weight: .heavy, design: .rounded))
                    .foregroundColor(textColor)
                if !unit.isEmpty {
                    Text(unit)
                        .font(.system(size: 8, weight: .black, design: .rounded))
                        .foregroundColor(.orange)
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
    
    private func statValueFor(_ metric: ShareCardMetric) -> String {
        switch metric {
        case .distance: return String(format: "%.2f", actualDistanceKm)
        case .elevation: return "\(Int(actualElevationMeters))"
        case .movingTime: return formatDuration(actualMovingDurationSeconds)
        case .avgSpeed: return String(format: "%.1f", actualAvgSpeedKmh)
        case .maxSpeed: return String(format: "%.1f", actualMaxSpeedKmh)
        case .calories: return "\(actualCalories)"
        case .cadence: return actualAvgCadence != nil ? "\(actualAvgCadence!)" : "--"
        case .heartRate: return actualAvgHeartRate != nil ? "\(actualAvgHeartRate!)" : "--"
        case .power: return actualAvgPower != nil ? "\(actualAvgPower!)" : "--"
        }
    }
    
    private func statUnitFor(_ metric: ShareCardMetric) -> String {
        switch metric {
        case .distance: return "KM"
        case .elevation: return "M"
        case .movingTime: return ""
        case .avgSpeed: return "KM/H"
        case .maxSpeed: return "KM/H"
        case .calories: return "KCAL"
        case .cadence: return "RPM"
        case .heartRate: return "BPM"
        case .power: return "W"
        }
    }
    
    // MARK: - Theme Helpers
    private var textColor: Color {
        switch selectedTheme {
        case .pureRouteSticker: return .white
        case .transparentDark: return .white
        case .transparentWhite: return .black
        case .mapBackground: return .primary
        case .glassMorphism: return .primary
        }
    }
    
    private var routeStrokeColor: Color {
        switch selectedTheme {
        case .pureRouteSticker: return .orange
        case .transparentDark: return .orange
        case .transparentWhite: return .black
        case .mapBackground: return .orange
        case .glassMorphism: return .accentColor
        }
    }
    
    private var cardBorderColor: Color {
        switch selectedTheme {
        case .pureRouteSticker: return Color.clear
        case .transparentDark: return Color.white.opacity(0.15)
        case .transparentWhite: return Color.black.opacity(0.15)
        case .mapBackground: return Color.secondary.opacity(0.2)
        case .glassMorphism: return Color.white.opacity(0.2)
        }
    }
    
    private var themeInnerBackground: Color {
        switch selectedTheme {
        case .pureRouteSticker: return Color.clear
        case .transparentDark: return Color.white.opacity(0.08)
        case .transparentWhite: return Color.black.opacity(0.08)
        case .mapBackground: return Color.clear
        case .glassMorphism: return Color.secondary.opacity(0.08)
        }
    }
    
    @ViewBuilder
    private var cardBackground: some View {
        switch selectedTheme {
        case .pureRouteSticker:
            Color.clear
        case .transparentDark:
            Color.black.opacity(0.72)
        case .transparentWhite:
            Color.white.opacity(0.85)
        case .mapBackground:
            Color.clear.background(.ultraThinMaterial)
        case .glassMorphism:
            Rectangle().fill(.ultraThinMaterial)
        }
    }
    
    private var checkerboardBackground: some View {
        Canvas { context, size in
            let step: CGFloat = 16
            let cols = Int(size.width / step) + 1
            let rows = Int(size.height / step) + 1
            for r in 0..<rows {
                for c in 0..<cols {
                    if (r + c) % 2 == 0 {
                        context.fill(Path(CGRect(x: CGFloat(c) * step, y: CGFloat(r) * step, width: step, height: step)), with: .color(.gray.opacity(0.25)))
                    }
                }
            }
        }
    }
    
    // MARK: - Safe ImageRenderer Export
    @MainActor
    private func exportTransparentPNG() {
        let renderer = ImageRenderer(content: shareCardHUD.frame(width: 360, height: 480))
        renderer.scale = 2.0
        renderer.isOpaque = (selectedTheme == .mapBackground)
        
        #if os(macOS)
        if let cgImg = renderer.cgImage {
            let savePanel = NSSavePanel()
            savePanel.allowedContentTypes = [.png]
            savePanel.canCreateDirectories = true
            savePanel.isExtensionHidden = false
            savePanel.title = "儲存分享卡片"
            let sanitized = actualTitle.components(separatedBy: CharacterSet.alphanumerics.inverted).joined(separator: "_")
            savePanel.nameFieldStringValue = "\(sanitized)_路線貼圖.png"
            
            savePanel.begin { response in
                if response == .OK, let targetURL = savePanel.url {
                    let rep = NSBitmapImageRep(cgImage: cgImg)
                    rep.size = NSSize(width: 360, height: 480)
                    if let data = rep.representation(using: .png, properties: [:]) {
                        try? data.write(to: targetURL)
                        alertTitle = "儲存成功"
                        alertMessage = "貼圖已成功儲存至檔案：\n\(targetURL.lastPathComponent)"
                        showAlert = true
                    }
                }
            }
        }
        #elseif os(iOS)
        guard let uiImg = renderer.uiImage else {
            alertTitle = "輸出錯誤"
            alertMessage = "無法產生卡片圖片，請重試。"
            showAlert = true
            return
        }
        
        let status = PHPhotoLibrary.authorizationStatus(for: .addOnly)
        switch status {
        case .authorized, .limited:
            saveImageDirectlyToPhotoLibrary(uiImg)
        case .notDetermined:
            PHPhotoLibrary.requestAuthorization(for: .addOnly) { newStatus in
                DispatchQueue.main.async {
                    if newStatus == .authorized || newStatus == .limited {
                        self.saveImageDirectlyToPhotoLibrary(uiImg)
                    } else {
                        self.alertTitle = "尚未取得相簿存取權限"
                        self.alertMessage = "無法儲存至相簿：請點擊「系統分享 / 檔案」按鈕直接儲存，或至 iOS「設定」>「\(AppConstants.appName)」開啟照片寫入權限。"
                        self.showAlert = true
                    }
                }
            }
        case .denied, .restricted:
            alertTitle = "尚未取得相簿存取權限"
            alertMessage = "無法儲存至相簿：系統相簿權限已被關閉。\n\n💡 請點擊「系統分享 / 檔案」直接儲存，或至 iOS「設定」開啟照片寫入權限。"
            showAlert = true
        @unknown default:
            alertTitle = "無法儲存"
            alertMessage = "相簿狀態未知，請改用「系統分享」儲存卡片。"
            showAlert = true
        }
        #endif
    }
    
    #if os(iOS)
    @MainActor
    private func triggerSystemShare() {
        let renderer = ImageRenderer(content: shareCardHUD.frame(width: 360, height: 480))
        renderer.scale = 2.0
        renderer.isOpaque = (selectedTheme == .mapBackground)
        if let uiImg = renderer.uiImage {
            self.shareSheetItems = [uiImg]
            self.showShareSheet = true
        }
    }
    
    @MainActor
    private func copyStickerToClipboard() {
        let renderer = ImageRenderer(content: shareCardHUD.frame(width: 360, height: 480))
        renderer.scale = 2.0
        renderer.isOpaque = (selectedTheme == .mapBackground)
        
        guard let uiImg = renderer.uiImage else {
            alertTitle = "複製失敗"
            alertMessage = "無法產生貼圖圖片。"
            showAlert = true
            return
        }
        
        UIPasteboard.general.image = uiImg
        openInstagramAfterAlert = true
        alertTitle = "貼圖已複製至剪貼簿！"
        alertMessage = "去背透明路線貼圖已在剪貼簿中。\n\n💡 點擊「打開 Instagram」進入限時動態拍照時，左下角會自動跳出「新增貼圖」，點擊即可將透明路線懸浮在照片或影片上！"
        showAlert = true
    }
    
    @MainActor
    private func shareToInstagramStories() {
        let renderer = ImageRenderer(content: shareCardHUD.frame(width: 360, height: 480))
        renderer.scale = 2.0
        renderer.isOpaque = (selectedTheme == .mapBackground)
        
        guard let uiImg = renderer.uiImage, let pngData = uiImg.pngData() else {
            alertTitle = "產生失敗"
            alertMessage = "無法產生分享貼圖，請重試。"
            showAlert = true
            return
        }
        
        // Always write to general clipboard image so Instagram camera detects it as a sticker
        UIPasteboard.general.image = uiImg
        
        let storyURL = URL(string: "instagram-stories://share")!
        let hasStoryApp = UIApplication.shared.canOpenURL(storyURL)
        
        var pasteboardDict: [String: Any] = [:]
        if selectedTheme == .mapBackground {
            // Render 9:16 portrait full Story container for map background to prevent aspect ratio rejection
            let storyCanvas = ZStack {
                Color(red: 0.08, green: 0.09, blue: 0.11)
                shareCardHUD
                    .frame(width: 360, height: 480)
            }
            .frame(width: 414, height: 736)
            
            let bgRenderer = ImageRenderer(content: storyCanvas)
            bgRenderer.scale = 2.0
            bgRenderer.isOpaque = true
            if let bgImg = bgRenderer.uiImage, let bgPng = bgImg.pngData() {
                pasteboardDict["com.instagram.sharedSticker.backgroundImage"] = bgPng
            } else {
                pasteboardDict["com.instagram.sharedSticker.stickerImage"] = pngData
                pasteboardDict["com.instagram.sharedSticker.backgroundTopColor"] = "#14161B"
                pasteboardDict["com.instagram.sharedSticker.backgroundBottomColor"] = "#090A0C"
            }
        } else {
            // Pure transparent sticker
            pasteboardDict["com.instagram.sharedSticker.stickerImage"] = pngData
            pasteboardDict["com.instagram.sharedSticker.backgroundTopColor"] = "#14161B"
            pasteboardDict["com.instagram.sharedSticker.backgroundBottomColor"] = "#090A0C"
        }
        
        let pasteboardOptions: [UIPasteboard.OptionsKey: Any] = [
            .expirationDate: Date().addingTimeInterval(300)
        ]
        UIPasteboard.general.setItems([pasteboardDict], options: pasteboardOptions)
        
        if hasStoryApp {
            UIApplication.shared.open(storyURL)
        } else if let igURL = URL(string: "instagram://app"), UIApplication.shared.canOpenURL(igURL) {
            UIApplication.shared.open(igURL)
        } else {
            openInstagramAfterAlert = false
            alertTitle = "尚未安裝 Instagram"
            alertMessage = "裝置尚未安裝 Instagram App，已為您開啟系統分享選單，可直接儲存至相簿或傳送給好友。"
            showAlert = true
            triggerSystemShare()
        }
    }
    #endif
    
    private func saveImageDirectlyToPhotoLibrary(_ image: UIImage) {
        UIImageWriteToSavedPhotosAlbum(image, nil, nil, nil)
        openInstagramAfterAlert = false
        alertTitle = "儲存成功"
        alertMessage = "分享卡片已成功儲存至相簿！"
        showAlert = true
    }
    
    private func shareGPXForCyclingApps() {
        let gpxContent = track.toGPXString()
        let cleanTitle = actualTitle
            .replacingOccurrences(of: " ", with: "_")
            .replacingOccurrences(of: "/", with: "_") + ".gpx"
        let tempURL = FileManager.default.temporaryDirectory.appendingPathComponent(cleanTitle)
        
        do {
            try gpxContent.write(to: tempURL, atomically: true, encoding: .utf8)
            #if os(iOS)
            self.shareSheetItems = [tempURL]
            self.showShareSheet = true
            #elseif os(macOS)
            let savePanel = NSSavePanel()
            savePanel.allowedContentTypes = [UTType(filenameExtension: "gpx") ?? .data]
            savePanel.nameFieldStringValue = cleanTitle
            savePanel.begin { response in
                if response == .OK, let targetURL = savePanel.url {
                    try? FileManager.default.copyItem(at: tempURL, to: targetURL)
                }
            }
            #endif
        } catch {
            alertTitle = "匯出失敗"
            alertMessage = error.localizedDescription
            showAlert = true
        }
    }
    
    private func formatDuration(_ sec: TimeInterval) -> String {
        let total = Int(sec)
        let m = (total % 3600) / 60
        let s = total % 60
        let h = total / 3600
        if h > 0 {
            return String(format: "%d:%02d:%02d", h, m, s)
        } else {
            return String(format: "%02d:%02d", m, s)
        }
    }
}


// MARK: - Route Silhouette Normalized Shape
public struct RouteSilhouetteShape: Shape {
    let points: [RoutePoint]
    
    public init(points: [RoutePoint]) {
        self.points = points
    }
    
    public func path(in rect: CGRect) -> Path {
        var path = Path()
        guard points.count > 1 else { return path }
        
        let lats = points.map(\.latitude)
        let lons = points.map(\.longitude)
        
        guard let minLat = lats.min(), let maxLat = lats.max(),
              let minLon = lons.min(), let maxLon = lons.max() else { return path }
        
        let latDelta = max(0.0001, maxLat - minLat)
        let lonDelta = max(0.0001, maxLon - minLon)
        
        let usableWidth = rect.width * 0.88
        let usableHeight = rect.height * 0.88
        let offsetX = rect.midX - usableWidth / 2.0
        let offsetY = rect.midY - usableHeight / 2.0
        
        for (i, pt) in points.enumerated() {
            let normX = (pt.longitude - minLon) / lonDelta
            let normY = 1.0 - ((pt.latitude - minLat) / latDelta)
            let x = offsetX + CGFloat(normX) * usableWidth
            let y = offsetY + CGFloat(normY) * usableHeight
            
            if i == 0 {
                path.move(to: CGPoint(x: x, y: y))
            } else {
                path.addLine(to: CGPoint(x: x, y: y))
            }
        }
        return path
    }
}

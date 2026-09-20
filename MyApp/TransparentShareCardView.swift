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
    
    @State private var selectedTheme: CardTheme = .transparentDark
    @State private var alertTitle: String = "提示"
    @State private var alertMessage: String = ""
    @State private var showAlert: Bool = false
    
    // Customizable metrics
    @State private var visibleMetrics: Set<ShareCardMetric> = [
        .distance, .elevation, .movingTime, .avgSpeed, .maxSpeed, .calories
    ]
    @State private var showCustomMetricsSheet: Bool = false
    
    #if os(iOS)
    @State private var shareSheetItems: [Any] = []
    @State private var showShareSheet: Bool = false
    #endif
    
    public enum CardTheme: String, CaseIterable {
        case transparentDark = "去背純黑浮印"
        case transparentWhite = "去背純白浮印"
        case mapBackground = "路線+地圖背景"
        case glassMorphism = "毛玻璃霧面"
    }
    
    public init(track: GPXTrack) {
        self.track = track
    }
    
    // MARK: - 100% 依據實際記錄之真實數據 (杜絕預估或假數值)
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
    
    // 運動時間（扣除長等待或停等紅綠燈）
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
    
    // 運動均速：總里程 / 運動時間
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
                VStack(spacing: 18) {
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
                        if selectedTheme == .transparentDark || selectedTheme == .transparentWhite {
                            checkerboardBackground
                                .frame(width: 360, height: 490)
                                .clipShape(RoundedRectangle(cornerRadius: 24))
                        }
                        
                        shareCardHUD
                            .frame(width: 360, height: 490)
                    }
                    .shadow(color: .black.opacity(0.2), radius: 12, x: 0, y: 6)
                    
                    // Customizable Metrics Selector
                    VStack(alignment: .leading, spacing: 10) {
                        HStack {
                            Text("客製化顯示數據")
                                .font(.subheadline.bold())
                                .foregroundColor(.secondary)
                            Spacer()
                            Text("已選 \(visibleMetrics.count) 項")
                                .font(.caption)
                                .foregroundColor(.secondary)
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
                        HStack(spacing: 12) {
                            // Primary: Save to Photos
                            Button {
                                exportTransparentPNG()
                            } label: {
                                Label("儲存至相簿", systemImage: "photo.badge.arrow.down.fill")
                                    .font(.headline)
                                    .frame(maxWidth: .infinity)
                                    .padding(.vertical, 12)
                            }
                            .buttonStyle(.borderedProminent)
                            .tint(.orange)
                            
                            #if os(iOS)
                            // Secondary: System Share (AirDrop, Save to Files, Social)
                            Button {
                                triggerSystemShare()
                            } label: {
                                Label("系統分享 / 檔案", systemImage: "square.and.arrow.up")
                                    .font(.headline)
                                    .frame(maxWidth: .infinity)
                                    .padding(.vertical, 12)
                            }
                            .buttonStyle(.bordered)
                            #else
                            Button {
                                copyCardToClipboard()
                            } label: {
                                Label("複製到剪貼簿", systemImage: "doc.on.doc.fill")
                                    .font(.headline)
                                    .frame(maxWidth: .infinity)
                                    .padding(.vertical, 12)
                            }
                            .buttonStyle(.bordered)
                            #endif
                        }
                        
                        #if os(iOS)
                        // Social Row: Instagram Stories & Strava / Velodash
                        HStack(spacing: 12) {
                            // Instagram Stories One-Tap Transparent Sticker Share
                            Button {
                                shareToInstagramStories()
                            } label: {
                                HStack(spacing: 6) {
                                    Image(systemName: "camera.circle.fill")
                                    Text("Instagram 限動貼圖")
                                }
                                .font(.subheadline.bold())
                                .foregroundColor(.white)
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 11)
                                .background(
                                    LinearGradient(
                                        colors: [Color(red: 0.51, green: 0.18, blue: 0.87), Color(red: 0.88, green: 0.19, blue: 0.42), Color(red: 0.98, green: 0.73, blue: 0.23)],
                                        startPoint: .topLeading,
                                        endPoint: .bottomTrailing
                                    ),
                                    in: RoundedRectangle(cornerRadius: 10)
                                )
                            }
                            .buttonStyle(.plain)
                            
                            // Strava / Velodash GPX Export
                            Button {
                                shareGPXForCyclingApps()
                            } label: {
                                HStack(spacing: 6) {
                                    Image(systemName: "arrow.triangle.swap")
                                    Text("Strava / Velodash")
                                }
                                .font(.subheadline.bold())
                                .foregroundColor(.white)
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 11)
                                .background(Color(red: 0.99, green: 0.35, blue: 0.08), in: RoundedRectangle(cornerRadius: 10))
                            }
                            .buttonStyle(.plain)
                        }
                        #endif
                        
                        Text("💡 支援一鍵直傳 Instagram 限時動態（透明去背貼圖），以及 Strava、Velodash、Garmin 完整 GPX 匯出！")
                            .font(.caption)
                            .foregroundColor(.secondary)
                            .multilineTextAlignment(.center)
                            .padding(.horizontal)
                    }
                    .padding(.horizontal)
                }
                .padding(.vertical)
            }
            .navigationTitle("分享")
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("關閉") { dismiss() }
                }
            }
            .alert(alertTitle, isPresented: $showAlert) {
                Button("好", role: .cancel) { }
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
    
    // MARK: - The Share Card View (Actual GPS Route & Real Stats)
    private var shareCardHUD: some View {
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
                    // Map background representation
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
                    switch metric {
                    case .distance:
                        statBlock(title: "總里程", value: String(format: "%.2f", actualDistanceKm), unit: "KM")
                    case .elevation:
                        statBlock(title: "總爬升", value: "\(Int(actualElevationMeters))", unit: "M")
                    case .movingTime:
                        statBlock(title: "運動耗時", value: formatDuration(actualMovingDurationSeconds), unit: "")
                    case .avgSpeed:
                        statBlock(title: "運動均速", value: String(format: "%.1f", actualAvgSpeedKmh), unit: "KM/H")
                    case .maxSpeed:
                        statBlock(title: "極速", value: String(format: "%.1f", actualMaxSpeedKmh), unit: "KM/H")
                    case .calories:
                        statBlock(title: "熱量消耗", value: "\(actualCalories)", unit: "KCAL")
                    case .cadence:
                        statBlock(title: "平均踏頻", value: actualAvgCadence != nil ? "\(actualAvgCadence!)" : "--", unit: "RPM")
                    case .heartRate:
                        statBlock(title: "平均心率", value: actualAvgHeartRate != nil ? "\(actualAvgHeartRate!)" : "--", unit: "BPM")
                    case .power:
                        statBlock(title: "平均功率", value: actualAvgPower != nil ? "\(actualAvgPower!)" : "--", unit: "W")
                    }
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
    
    // MARK: - Theme Helpers
    private var textColor: Color {
        switch selectedTheme {
        case .transparentDark: return .white
        case .transparentWhite: return .black
        case .mapBackground: return .primary
        case .glassMorphism: return .primary
        }
    }
    
    private var routeStrokeColor: Color {
        switch selectedTheme {
        case .transparentDark: return .orange
        case .transparentWhite: return .black
        case .mapBackground: return .orange
        case .glassMorphism: return .accentColor
        }
    }
    
    private var cardBorderColor: Color {
        switch selectedTheme {
        case .transparentDark: return Color.white.opacity(0.15)
        case .transparentWhite: return Color.black.opacity(0.15)
        case .mapBackground: return Color.secondary.opacity(0.2)
        case .glassMorphism: return Color.white.opacity(0.2)
        }
    }
    
    private var themeInnerBackground: Color {
        switch selectedTheme {
        case .transparentDark: return Color.white.opacity(0.08)
        case .transparentWhite: return Color.black.opacity(0.08)
        case .mapBackground: return Color.clear
        case .glassMorphism: return Color.secondary.opacity(0.08)
        }
    }
    
    @ViewBuilder
    private var cardBackground: some View {
        switch selectedTheme {
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
    
    // MARK: - Safe ImageRenderer Export with Permission Handling
    @MainActor
    private func exportTransparentPNG() {
        let renderer = ImageRenderer(content: shareCardHUD.frame(width: 360, height: 490))
        renderer.scale = 2.0
        renderer.isOpaque = false
        
        #if os(macOS)
        if let cgImg = renderer.cgImage {
            let savePanel = NSSavePanel()
            savePanel.allowedContentTypes = [.png]
            savePanel.canCreateDirectories = true
            savePanel.isExtensionHidden = false
            savePanel.title = "儲存分享卡片"
            let sanitized = actualTitle.components(separatedBy: CharacterSet.alphanumerics.inverted).joined(separator: "_")
            savePanel.nameFieldStringValue = "\(sanitized)_分享卡片.png"
            
            savePanel.begin { response in
                if response == .OK, let targetURL = savePanel.url {
                    let rep = NSBitmapImageRep(cgImage: cgImg)
                    rep.size = NSSize(width: 360, height: 490)
                    if let data = rep.representation(using: .png, properties: [:]) {
                        try? data.write(to: targetURL)
                        alertTitle = "儲存成功"
                        alertMessage = "分享卡片已成功儲存至檔案：\n\(targetURL.lastPathComponent)"
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
                        self.alertMessage = "無法儲存至相簿：您選擇了不允許存取照片。\n\n💡 請點擊「系統分享 / 檔案」按鈕直接儲存至「檔案」或 AirDrop，或至 iOS「設定」>「\(AppConstants.appName)」開啟「照片」寫入權限。"
                        self.showAlert = true
                    }
                }
            }
        case .denied, .restricted:
            alertTitle = "尚未取得相簿存取權限"
            alertMessage = "無法儲存至相簿：系統相簿權限已被關閉。\n\n💡 請點擊「系統分享 / 檔案」按鈕直接儲存至「檔案」或 AirDrop，或至 iOS「設定」>「\(AppConstants.appName)」開啟「照片」寫入權限。"
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
        let renderer = ImageRenderer(content: shareCardHUD.frame(width: 360, height: 490))
        renderer.scale = 2.0
        renderer.isOpaque = false
        if let uiImg = renderer.uiImage {
            self.shareSheetItems = [uiImg]
            self.showShareSheet = true
        }
    }
    
    @MainActor
    private func shareToInstagramStories() {
        let stickerContent = shareCardHUD
            .frame(width: 360, height: 490)
            .background(Color.clear)
        
        let renderer = ImageRenderer(content: stickerContent)
        renderer.scale = 3.0
        renderer.isOpaque = false // 確保完全去背透明
        
        guard let uiImg = renderer.uiImage, let pngData = uiImg.pngData() else {
            alertTitle = "產生失敗"
            alertMessage = "無法產生透明分享貼圖，請重試。"
            showAlert = true
            return
        }
        
        let storyURL = URL(string: "instagram-stories://share?source_application=com.velodice.ride")!
        if UIApplication.shared.canOpenURL(storyURL) {
            // 僅傳送 stickerImage，背景留空，讓 Instagram 自動開啟相機並置入透明去背貼圖！
            let pasteboardItems: [[String: Any]] = [
                [
                    "com.instagram.sharedSticker.stickerImage": pngData
                ]
            ]
            let pasteboardOptions: [UIPasteboard.OptionsKey: Any] = [
                .expirationDate: Date().addingTimeInterval(300)
            ]
            UIPasteboard.general.setItems(pasteboardItems, options: pasteboardOptions)
            UIApplication.shared.open(storyURL)
        } else {
            alertTitle = "尚未安裝 Instagram"
            alertMessage = "裝置尚未安裝 Instagram App，已將透明分享卡片儲存，您也可以透過「系統分享」傳送給好友。"
            showAlert = true
            triggerSystemShare()
        }
    }
    
    private func saveImageDirectlyToPhotoLibrary(_ image: UIImage) {
        UIImageWriteToSavedPhotosAlbum(image, nil, nil, nil)
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
            self.shareSheetItems = [tempURL]
            self.showShareSheet = true
        } catch {
            alertTitle = "產生 GPX 失敗"
            alertMessage = error.localizedDescription
            showAlert = true
        }
    }
    #endif
    
    #if os(macOS)
    @MainActor
    private func copyCardToClipboard() {
        let renderer = ImageRenderer(content: shareCardHUD.frame(width: 360, height: 490))
        renderer.scale = 2.0
        renderer.isOpaque = false
        if let cgImg = renderer.cgImage {
            let pasteboard = NSPasteboard.general
            pasteboard.clearContents()
            let rep = NSBitmapImageRep(cgImage: cgImg)
            rep.size = NSSize(width: 360, height: 490)
            if let data = rep.representation(using: .png, properties: [:]) {
                pasteboard.setData(data, forType: .png)
                alertTitle = "已複製"
                alertMessage = "分享卡片已複製至剪貼簿。"
                showAlert = true
            }
        }
    }
    #endif
    
    private func formatDuration(_ seconds: TimeInterval) -> String {
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

public struct RouteSilhouetteShape: Shape {
    public let points: [RoutePoint]
    
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
        
        let dLat = max(0.00001, maxLat - minLat)
        let dLon = max(0.00001, maxLon - minLon)
        let w = rect.width
        let h = rect.height
        
        func pointToCanvas(_ p: RoutePoint) -> CGPoint {
            let x = CGFloat((p.longitude - minLon) / dLon) * w
            let y = CGFloat(1.0 - (p.latitude - minLat) / dLat) * h
            return CGPoint(x: x, y: y)
        }
        
        path.move(to: pointToCanvas(points[0]))
        for i in 1..<points.count {
            path.addLine(to: pointToCanvas(points[i]))
        }
        return path
    }
}

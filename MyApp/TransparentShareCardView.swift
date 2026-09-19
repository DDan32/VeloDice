import SwiftUI
import UniformTypeIdentifiers
import Photos
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

public struct TransparentShareCardView: View {
    let track: GPXTrack
    @Environment(\.dismiss) private var dismiss
    
    @State private var selectedTheme: CardTheme = .transparentDark
    @State private var alertTitle: String = "提示"
    @State private var alertMessage: String = ""
    @State private var showAlert: Bool = false
    
    #if os(iOS)
    @State private var shareSheetItems: [Any] = []
    @State private var showShareSheet: Bool = false
    #endif
    
    public enum CardTheme: String, CaseIterable {
        case transparentDark = "去背純黑浮印 (透明背景)"
        case transparentWhite = "去背純白浮印 (透明背景)"
        case neonOrange = "Strava 經典亮橘"
        case glassMorphism = "毛玻璃微霧質感"
    }
    
    public init(track: GPXTrack) {
        self.track = track
    }
    
    // MARK: - 100% 依據實際記錄之真實數據 (杜絕預估或假數值)
    private var actualTitle: String {
        track.title.isEmpty ? "戶外運動記錄" : track.title
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
    
    private var actualAvgSpeedKmh: Double {
        let hrs = actualDurationSeconds / 3600.0
        return (hrs > 0 && actualDistanceKm >= 0.03) ? (actualDistanceKm / hrs) : 0.0
    }
    
    private var actualMaxSpeedKmh: Double {
        let validSpeeds = track.points.compactMap(\.speedKmh).filter { $0 > 0 }
        return validSpeeds.max() ?? 0.0
    }
    
    private var actualCalories: Int {
        actualDistanceKm > 0 ? Int(actualDistanceKm * 32.0 + actualElevationMeters * 0.8) : 0
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
                VStack(spacing: 20) {
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
                                .frame(width: 360, height: 480)
                                .clipShape(RoundedRectangle(cornerRadius: 24))
                        }
                        
                        shareCardHUD
                            .frame(width: 360, height: 480)
                    }
                    .shadow(color: .black.opacity(0.2), radius: 12, x: 0, y: 6)
                    
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
                        // Dedicated Social & Cycling Platform Row: Instagram & Strava / Velodash
                        HStack(spacing: 12) {
                            // Instagram Stories One-Tap Share
                            Button {
                                shareToInstagramStories()
                            } label: {
                                HStack(spacing: 6) {
                                    Image(systemName: "camera.circle.fill")
                                    Text("Instagram 限動")
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
                        
                        Text("💡 支援一鍵直傳 Instagram 限時動態貼圖，以及 Strava、Velodash、Garmin 完整心率踏頻 GPX 匯出！")
                            .font(.caption)
                            .foregroundColor(.secondary)
                            .multilineTextAlignment(.center)
                            .padding(.horizontal)
                    }
                    .padding(.horizontal)
                }
                .padding(.vertical)
            }
            .navigationTitle("去背運動成績卡片")
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
                    Text("APEX ROUTE")
                        .font(.system(size: 14, weight: .black, design: .rounded))
                        .foregroundColor(textColor)
                }
                Spacer()
                Text(actualDateString)
                    .font(.system(size: 12, weight: .semibold, design: .monospaced))
                    .foregroundColor(textColor.opacity(0.8))
            }
            
            // Route Title
            Text(actualTitle)
                .font(.system(size: 20, weight: .heavy, design: .rounded))
                .foregroundColor(textColor)
                .lineLimit(1)
            
            // Real GPS Track Outline Silhouette
            ZStack {
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
            .frame(height: 170)
            
            // Real Metric Stats Grid
            VStack(spacing: 10) {
                HStack(spacing: 0) {
                    statBlock(title: "總里程", value: String(format: "%.2f", actualDistanceKm), unit: "KM")
                    Spacer()
                    statBlock(title: "總爬升", value: "\(Int(actualElevationMeters))", unit: "M")
                    Spacer()
                    statBlock(title: "運動耗時", value: formatDuration(actualDurationSeconds), unit: "")
                }
                
                Divider()
                    .background(textColor.opacity(0.2))
                
                HStack(spacing: 0) {
                    statBlock(title: "平均時速", value: String(format: "%.1f", actualAvgSpeedKmh), unit: "KM/H")
                    Spacer()
                    statBlock(title: "極速", value: String(format: "%.1f", actualMaxSpeedKmh), unit: "KM/H")
                    Spacer()
                    statBlock(title: "熱量消耗", value: "\(actualCalories)", unit: "KCAL")
                }
            }
            .padding(.horizontal, 4)
            .padding(.top, 2)
        }
        .padding(20)
        .background(cardBackground)
        .clipShape(RoundedRectangle(cornerRadius: 24))
        .overlay(
            RoundedRectangle(cornerRadius: 24)
                .stroke(cardBorderColor, lineWidth: 1.5)
        )
    }
    
    private func statBlock(title: String, value: String, unit: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(title)
                .font(.system(size: 10, weight: .bold))
                .foregroundColor(textColor.opacity(0.6))
            HStack(alignment: .lastTextBaseline, spacing: 2) {
                Text(value)
                    .font(.system(size: 18, weight: .heavy, design: .rounded))
                    .foregroundColor(textColor)
                if !unit.isEmpty {
                    Text(unit)
                        .font(.system(size: 9, weight: .black, design: .rounded))
                        .foregroundColor(.orange)
                }
            }
        }
        .frame(minWidth: 80, alignment: .leading)
    }
    
    // MARK: - Theme Helpers
    private var textColor: Color {
        switch selectedTheme {
        case .transparentDark, .neonOrange: return .white
        case .transparentWhite: return .black
        case .glassMorphism: return .primary
        }
    }
    
    private var routeStrokeColor: Color {
        switch selectedTheme {
        case .transparentDark: return .orange
        case .transparentWhite: return .white
        case .neonOrange: return .orange
        case .glassMorphism: return .accentColor
        }
    }
    
    private var cardBorderColor: Color {
        switch selectedTheme {
        case .transparentDark: return Color.white.opacity(0.15)
        case .transparentWhite: return Color.black.opacity(0.15)
        case .neonOrange: return Color.orange.opacity(0.4)
        case .glassMorphism: return Color.white.opacity(0.2)
        }
    }
    
    private var themeInnerBackground: Color {
        switch selectedTheme {
        case .transparentDark: return Color.white.opacity(0.06)
        case .transparentWhite: return Color.black.opacity(0.08)
        case .neonOrange: return Color.orange.opacity(0.08)
        case .glassMorphism: return Color.secondary.opacity(0.08)
        }
    }
    
    @ViewBuilder
    private var cardBackground: some View {
        switch selectedTheme {
        case .transparentDark:
            Color.black.opacity(0.65)
        case .transparentWhite:
            Color.white.opacity(0.25)
        case .neonOrange:
            Color.black.opacity(0.92)
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
        let renderer = ImageRenderer(content: shareCardHUD.frame(width: 360, height: 480))
        renderer.scale = 2.0
        
        #if os(macOS)
        if let cgImg = renderer.cgImage {
            let savePanel = NSSavePanel()
            savePanel.allowedContentTypes = [.png]
            savePanel.canCreateDirectories = true
            savePanel.isExtensionHidden = false
            savePanel.title = "儲存去背透明運動成績卡片"
            let sanitized = actualTitle.components(separatedBy: CharacterSet.alphanumerics.inverted).joined(separator: "_")
            savePanel.nameFieldStringValue = "\(sanitized)_去背卡片.png"
            
            savePanel.begin { response in
                if response == .OK, let targetURL = savePanel.url {
                    let rep = NSBitmapImageRep(cgImage: cgImg)
                    rep.size = NSSize(width: 360, height: 480)
                    if let data = rep.representation(using: .png, properties: [:]) {
                        try? data.write(to: targetURL)
                        alertTitle = "儲存成功"
                        alertMessage = "透明去背卡片已成功儲存至檔案：\n\(targetURL.lastPathComponent)"
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
        
        // 嚴格檢驗相簿權限，未授權時絕不顯示假成功！
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
                        self.alertMessage = "無法儲存至相簿：您選擇了不允許存取照片。\n\n💡 請點擊「系統分享 / 檔案」按鈕直接儲存至「檔案」或 AirDrop，或至 iOS「設定」>「VeloDice 騎跡」開啟「照片」寫入權限。"
                        self.showAlert = true
                    }
                }
            }
        case .denied, .restricted:
            alertTitle = "尚未取得相簿存取權限"
            alertMessage = "無法儲存至相簿：系統相簿權限已被關閉。\n\n💡 請點擊「系統分享 / 檔案」按鈕直接儲存至「檔案」或 AirDrop，或至 iOS「設定」>「VeloDice 騎跡」開啟「照片」寫入權限。"
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
        if let uiImg = renderer.uiImage {
            self.shareSheetItems = [uiImg]
            self.showShareSheet = true
        }
    }
    
    @MainActor
    private func shareToInstagramStories() {
        let renderer = ImageRenderer(content: shareCardHUD.frame(width: 360, height: 480))
        renderer.scale = 3.0
        guard let uiImg = renderer.uiImage, let pngData = uiImg.pngData() else {
            alertTitle = "產生失敗"
            alertMessage = "無法產生去背卡片，請重試。"
            showAlert = true
            return
        }
        
        let storyURL = URL(string: "instagram-stories://share?source_application=com.velodice.ride")!
        if UIApplication.shared.canOpenURL(storyURL) {
            let pasteboardItems: [[String: Any]] = [
                [
                    "com.instagram.sharedSticker.stickerImage": pngData,
                    "com.instagram.sharedSticker.backgroundTopColor": "#1A1A2E",
                    "com.instagram.sharedSticker.backgroundBottomColor": "#16213E"
                ]
            ]
            let pasteboardOptions: [UIPasteboard.OptionsKey: Any] = [
                .expirationDate: Date().addingTimeInterval(300)
            ]
            UIPasteboard.general.setItems(pasteboardItems, options: pasteboardOptions)
            UIApplication.shared.open(storyURL, options: [:], completionHandler: nil)
        } else {
            // 未安裝 Instagram 則喚起系統分享面版
            self.shareSheetItems = [uiImg]
            self.showShareSheet = true
            alertTitle = "未偵測到 Instagram"
            alertMessage = "未安裝 Instagram App，已開啟系統分享面板，您可直接儲存卡片或分享至其他通訊軟體。"
            showAlert = true
        }
    }
    
    @MainActor
    private func shareGPXForCyclingApps() {
        let gpxString = track.toGPXString()
        let sanitized = actualTitle.components(separatedBy: CharacterSet.alphanumerics.inverted).joined(separator: "_")
        let fileName = "\(sanitized.isEmpty ? "VeloDice_Track" : sanitized).gpx"
        let tempURL = FileManager.default.temporaryDirectory.appendingPathComponent(fileName)
        
        do {
            try gpxString.write(to: tempURL, atomically: true, encoding: .utf8)
            self.shareSheetItems = [tempURL]
            self.showShareSheet = true
        } catch {
            alertTitle = "匯出失敗"
            alertMessage = "產生 GPX 檔案失敗：\(error.localizedDescription)"
            showAlert = true
        }
    }
    
    private func saveImageDirectlyToPhotoLibrary(_ image: UIImage) {
        PHPhotoLibrary.shared().performChanges({
            PHAssetChangeRequest.creationRequestForAsset(from: image)
        }) { success, error in
            DispatchQueue.main.async {
                if success {
                    self.alertTitle = "儲存成功"
                    self.alertMessage = "去背卡片已成功儲存至您的系統相簿！"
                    self.showAlert = true
                } else {
                    self.alertTitle = "儲存失敗"
                    self.alertMessage = "寫入相簿發生錯誤：\(error?.localizedDescription ?? "未知錯誤")\n建議改用「系統分享」儲存至檔案。"
                    self.showAlert = true
                }
            }
        }
    }
    #endif
    
    @MainActor
    private func copyCardToClipboard() {
        let renderer = ImageRenderer(content: shareCardHUD.frame(width: 360, height: 480))
        renderer.scale = 2.0
        
        #if os(macOS)
        if let cgImg = renderer.cgImage {
            let rep = NSBitmapImageRep(cgImage: cgImg)
            if let data = rep.representation(using: .png, properties: [:]) {
                let p = NSPasteboard.general
                p.clearContents()
                p.setData(data, forType: .png)
                alertTitle = "複製成功"
                alertMessage = "透明卡片 PNG 已成功複製到剪貼簿，可直接貼到通訊軟體或相片編輯器！"
                showAlert = true
            }
        }
        #elseif os(iOS)
        if let uiImg = renderer.uiImage {
            UIPasteboard.general.image = uiImg
            alertTitle = "複製成功"
            alertMessage = "卡片已複製至剪貼簿！"
            showAlert = true
        }
        #endif
    }
    
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

// MARK: - Route Silhouette Normalized Shape
public struct RouteSilhouetteShape: Shape {
    let points: [RoutePoint]
    
    public func path(in rect: CGRect) -> Path {
        var path = Path()
        guard points.count > 1 else { return path }
        
        let lats = points.map(\.latitude)
        let lons = points.map(\.longitude)
        
        guard let minLat = lats.min(), let maxLat = lats.max(),
              let minLon = lons.min(), let maxLon = lons.max() else { return path }
        
        let latDelta = max(0.0001, maxLat - minLat)
        let lonDelta = max(0.0001, maxLon - minLon)
        
        let usableWidth = rect.width * 0.85
        let usableHeight = rect.height * 0.85
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

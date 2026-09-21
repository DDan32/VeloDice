import Foundation
import SwiftUI
import Combine

// MARK: - Supported App Languages
public enum AppLanguage: String, CaseIterable, Identifiable, Codable {
    case traditionalChinese = "zh-Hant"
    case english = "en"
    
    public var id: String { rawValue }
    
    public var displayName: String {
        switch self {
        case .traditionalChinese: return "繁體中文"
        case .english: return "English"
        }
    }
    
    public var localizedDescription: String {
        switch self {
        case .traditionalChinese: return "繁體中文 (Traditional Chinese)"
        case .english: return "English (英文)"
        }
    }
    
    public var flag: String {
        switch self {
        case .traditionalChinese: return "🇹🇼"
        case .english: return "🇺🇸"
        }
    }
}

// MARK: - App Language Manager
@MainActor
public class AppLanguageManager: ObservableObject {
    public static let shared = AppLanguageManager()
    
    private let storageKey = "velodice_selected_app_language_v1"
    
    @Published public var currentLanguage: AppLanguage {
        didSet {
            UserDefaults.standard.set(currentLanguage.rawValue, forKey: storageKey)
        }
    }
    
    public var locale: Locale {
        Locale(identifier: currentLanguage.rawValue)
    }
    
    public init() {
        if let saved = UserDefaults.standard.string(forKey: storageKey),
           let lang = AppLanguage(rawValue: saved) {
            self.currentLanguage = lang
        } else {
            // Default to system language if Chinese, otherwise English
            let preferred = Locale.preferredLanguages.first ?? "zh-Hant"
            if preferred.hasPrefix("zh") {
                self.currentLanguage = .traditionalChinese
            } else {
                self.currentLanguage = .english
            }
        }
    }
    
    public func setLanguage(_ language: AppLanguage) {
        withAnimation(.spring(response: 0.35, dampingFraction: 0.7)) {
            self.currentLanguage = language
        }
    }
    
    public func toggleLanguage() {
        if currentLanguage == .traditionalChinese {
            setLanguage(.english)
        } else {
            setLanguage(.traditionalChinese)
        }
    }
}

// MARK: - Localization Dictionary & Quick Access
public struct L10n {
    @MainActor
    public static func tr(_ zh: String, _ en: String) -> String {
        return AppLanguageManager.shared.currentLanguage == .traditionalChinese ? zh : en
    }
    
    // MARK: - Navigation Tabs
    public struct Tab {
        @MainActor public static var routePlanning: String { L10n.tr("地圖導航", "Navigation") }
        @MainActor public static var liveHUD: String { L10n.tr("即時記錄", "Live HUD") }
        @MainActor public static var myActivities: String { L10n.tr("我的活動", "My Activities") }
    }
    
    // MARK: - VeloDice Lucky Roll
    public struct VeloDice {
        @MainActor public static var luckyRoute: String { L10n.tr("隨機路線", "Lucky Route") }
        @MainActor public static var rollTitle: String { L10n.tr("🎲 命運單車骰", "🎲 VeloDice Lucky Roll") }
        @MainActor public static var rollSubtitle: String { L10n.tr("隨機探索距離目前位置 30 公里內熱門路線", "Explore popular cycling routes within 30 km") }
        @MainActor public static var reRoll: String { L10n.tr("不喜歡？重新擲骰 🎲", "Reroll Dice 🎲") }
        @MainActor public static var confirmNavigate: String { L10n.tr("確認導航至此路線", "Navigate to This Route") }
        @MainActor public static var highlights: String { L10n.tr("路線特色", "Highlights") }
        @MainActor public static var estDistance: String { L10n.tr("預估里程", "Est. Distance") }
        @MainActor public static var estAscent: String { L10n.tr("預估爬升", "Est. Climb") }
        @MainActor public static var estTime: String { L10n.tr("預估騎時", "Est. Time") }
        @MainActor public static var difficulty: String { L10n.tr("路線等級", "Level") }
        @MainActor public static var fromYou: String { L10n.tr("距目前位置", "From You") }
        @MainActor public static var within30km: String { L10n.tr("30km 內", "Within 30km") }
        @MainActor public static var rollingToast: String { L10n.tr("🎲 正在擲骰挑選距離目前位置 30 km 內最佳路線...", "🎲 Rolling dice for top routes within 30 km...") }
    }
    
    // MARK: - Route Planning
    public struct Route {
        @MainActor public static var origin: String { L10n.tr("起點", "Start") }
        @MainActor public static var destination: String { L10n.tr("終點", "Destination") }
        @MainActor public static var currentLocation: String { L10n.tr("目前位置", "Current Location") }
        @MainActor public static var setDestination: String { L10n.tr("點擊設定目的地", "Set Destination") }
        @MainActor public static var myLocation: String { L10n.tr("現在位置", "My Location") }
        @MainActor public static var importGPX: String { L10n.tr("匯入GPX", "Import GPX") }
        @MainActor public static var routeGuide: String { L10n.tr("路線指引", "Guide") }
        @MainActor public static var elevation: String { L10n.tr("爬升", "Climb") }
        @MainActor public static var supply: String { L10n.tr("補給站", "Supplies") }
        @MainActor public static var addStop: String { L10n.tr("新增中途停靠站", "Add Waypoint") }
        @MainActor public static var offRouteWarning: String { L10n.tr("⚠️ 已偏離路線！點此重新規劃", "⚠️ Off route! Tap to recalculate") }
        @MainActor public static var calculating: String { L10n.tr("規劃中...", "Calculating...") }
        @MainActor public static var recording: String { L10n.tr("運動記錄中", "Recording") }
        @MainActor public static var autoPaused: String { L10n.tr("自動暫停", "Auto Paused") }
    }
    
    // MARK: - Live HUD Dashboard
    public struct HUD {
        @MainActor public static var speed: String { L10n.tr("時速", "Speed") }
        @MainActor public static var heartRate: String { L10n.tr("心率", "Heart Rate") }
        @MainActor public static var cadence: String { L10n.tr("踏頻", "Cadence") }
        @MainActor public static var power: String { L10n.tr("功率", "Power") }
        @MainActor public static var distance: String { L10n.tr("里程", "Distance") }
        @MainActor public static var ascent: String { L10n.tr("爬升", "Climb") }
        @MainActor public static var duration: String { L10n.tr("時間", "Duration") }
        @MainActor public static var avgSpeed: String { L10n.tr("均速", "Avg Speed") }
        @MainActor public static var finishAndSave: String { L10n.tr("結束並儲存", "Finish & Save") }
        @MainActor public static var pause: String { L10n.tr("暫停", "Pause") }
        @MainActor public static var resume: String { L10n.tr("繼續", "Resume") }
    }
    
    // MARK: - My Activities
    public struct Activities {
        @MainActor public static var title: String { L10n.tr("我的運動歷程", "My Activities") }
        @MainActor public static var pastRides: String { L10n.tr("過往活動", "Past Rides") }
        @MainActor public static var careerRecords: String { L10n.tr("生涯榮譽榜", "Records") }
        @MainActor public static var segmentPRs: String { L10n.tr("路段最佳 (PR)", "Segment PRs") }
        @MainActor public static var recentlyDeleted: String { L10n.tr("最近刪除", "Trash") }
        @MainActor public static var editProfile: String { L10n.tr("編輯", "Edit") }
        @MainActor public static var profileTitle: String { L10n.tr("騎士個人檔案", "Athlete Profile") }
        @MainActor public static var relive3D: String { L10n.tr("3D 衛星軌跡", "3D Relive") }
        @MainActor public static var share: String { L10n.tr("分享海報", "Share Card") }
        @MainActor public static var loadRouteToNav: String { L10n.tr("載入至地圖導航", "Load to Navigation") }
        @MainActor public static var exportGPX: String { L10n.tr("匯出 GPX", "Export GPX") }
    }
    
    // MARK: - Common
    public struct Common {
        @MainActor public static var language: String { L10n.tr("語言", "Language") }
        @MainActor public static var languageSettings: String { L10n.tr("切換語言 (Language)", "Language (切換語言)") }
        @MainActor public static var done: String { L10n.tr("完成", "Done") }
        @MainActor public static var cancel: String { L10n.tr("取消", "Cancel") }
        @MainActor public static var close: String { L10n.tr("關閉", "Close") }
        @MainActor public static var save: String { L10n.tr("儲存", "Save") }
        @MainActor public static var delete: String { L10n.tr("刪除", "Delete") }
        @MainActor public static var search: String { L10n.tr("搜尋", "Search") }
        @MainActor public static var confirm: String { L10n.tr("確認", "Confirm") }
        @MainActor public static var kmUnit: String { L10n.tr("公里", "km") }
        @MainActor public static var meterUnit: String { L10n.tr("公尺", "m") }
        @MainActor public static var minUnit: String { L10n.tr("分", "min") }
        @MainActor public static var kmhUnit: String { L10n.tr("km/h", "km/h") }
    }
}

// MARK: - Language Selector UI Components
public struct LanguageSwitcherView: View {
    @ObservedObject var languageManager = AppLanguageManager.shared
    
    public init() {}
    
    public var body: some View {
        Menu {
            ForEach(AppLanguage.allCases) { lang in
                Button {
                    languageManager.setLanguage(lang)
                } label: {
                    HStack {
                        Text("\(lang.flag) \(lang.displayName)")
                        if languageManager.currentLanguage == lang {
                            Image(systemName: "checkmark")
                        }
                    }
                }
            }
        } label: {
            HStack(spacing: 4) {
                Text(languageManager.currentLanguage.flag)
                Text(languageManager.currentLanguage.displayName)
                    .font(.caption.bold())
                Image(systemName: "chevron.up.chevron.down")
                    .font(.system(size: 9, weight: .semibold))
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 5)
            .background(Color(uiColor: .secondarySystemFill), in: Capsule())
        }
    }
}

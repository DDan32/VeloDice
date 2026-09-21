import Combine
import Foundation
import CoreLocation
import MapKit
import SwiftUI

// MARK: - Route Category
public enum VeloRouteCategory: String, CaseIterable, Codable {
    case riverSide = "河濱水岸"
    case mountainClimb = "山道爬坡"
    case coastalBreeze = "海風巡航"
    case culturalOldStreet = "人文老街"
    case scenicLake = "湖光秘境"
    case forestGravel = "森林綠道"
    
    public var icon: String {
        switch self {
        case .riverSide: return "water.waves"
        case .mountainClimb: return "mountain.2.fill"
        case .coastalBreeze: return "wind"
        case .culturalOldStreet: return "building.columns.fill"
        case .scenicLake: return "drop.fill"
        case .forestGravel: return "leaf.fill"
        }
    }
    
    public var themeColor: Color {
        switch self {
        case .riverSide: return .cyan
        case .mountainClimb: return .orange
        case .coastalBreeze: return .blue
        case .culturalOldStreet: return .purple
        case .scenicLake: return .teal
        case .forestGravel: return .green
        }
    }
}

// MARK: - VeloDice Lucky Route Model
public struct VeloDiceLuckyRoute: Identifiable, Equatable {
    public var id = UUID()
    public var title: String
    public var subtitle: String
    public var destinationName: String
    public var category: VeloRouteCategory
    public var estimatedDistanceKm: Double
    public var estimatedAscentMeters: Double
    public var difficulty: String
    public var highlights: [String]
    public var coordinate: CLLocationCoordinate2D
    public var distanceFromUserKm: Double = 0.0
    
    public static func == (lhs: VeloDiceLuckyRoute, rhs: VeloDiceLuckyRoute) -> Bool {
        lhs.id == rhs.id
    }
}

// MARK: - VeloDice Lucky Route Discovery Service
@MainActor
public class VeloDiceLuckyRouteService: ObservableObject {
    public static let shared = VeloDiceLuckyRouteService()
    
    @Published public var currentLuckyRoute: VeloDiceLuckyRoute? = nil
    @Published public var availableNearbyRoutes: [VeloDiceLuckyRoute] = []
    @Published public var isRolling: Bool = false
    @Published public var isSearchingNearby: Bool = false
    
    private let curatedCatalog: [VeloDiceLuckyRoute] = [
        VeloDiceLuckyRoute(
            title: "大稻埕碼頭夕陽水岸",
            subtitle: "大稻埕碼頭貨櫃市集 · 淡水河畔微風悠遊",
            destinationName: "大稻埕碼頭",
            category: .riverSide,
            estimatedDistanceKm: 6.5,
            estimatedAscentMeters: 10.0,
            difficulty: "輕鬆悠活 ⭐",
            highlights: ["夕陽水岸貨櫃市集", "寬闊河濱自行車道", "咖啡甜點補給"],
            coordinate: CLLocationCoordinate2D(latitude: 25.0566, longitude: 121.5075)
        ),
        VeloDiceLuckyRoute(
            title: "美堤彩虹河濱水岸線",
            subtitle: "基隆河左岸 · 遠眺台北101與松山機場飛機起降",
            destinationName: "美堤河濱公園",
            category: .riverSide,
            estimatedDistanceKm: 8.2,
            estimatedAscentMeters: 15.0,
            difficulty: "平路微風 ⭐",
            highlights: ["看飛機降落", "夜景地標101", "平整草皮景觀"],
            coordinate: CLLocationCoordinate2D(latitude: 25.0782, longitude: 121.5540)
        ),
        VeloDiceLuckyRoute(
            title: "劍南山步道眺望線",
            subtitle: "大直美麗華摩天輪夜景 · 短坡敏捷爬升",
            destinationName: "劍南山觀景台",
            category: .mountainClimb,
            estimatedDistanceKm: 7.8,
            estimatedAscentMeters: 195.0,
            difficulty: "短陡爬坡 ⭐⭐",
            highlights: ["美麗華摩天輪全景", "偶像劇取景地", "短程有氧爆發"],
            coordinate: CLLocationCoordinate2D(latitude: 25.0860, longitude: 121.5520)
        ),
        VeloDiceLuckyRoute(
            title: "中和烘爐地求財之巔",
            subtitle: "南山福德宮巨型土地公 · 陡坡熱血拉扯",
            destinationName: "烘爐地南山福德宮",
            category: .mountainClimb,
            estimatedDistanceKm: 11.5,
            estimatedAscentMeters: 280.0,
            difficulty: "陡坡挑戰 ⭐⭐⭐",
            highlights: ["超壯麗大台北夜景", "求財香火鼎盛", "經典爬坡計時考驗"],
            coordinate: CLLocationCoordinate2D(latitude: 24.9702, longitude: 121.5034)
        ),
        VeloDiceLuckyRoute(
            title: "八里觀音山硬漢之巔",
            subtitle: "凌雲路蜿蜒登頂 · 俯瞰淡水河口與台北港",
            destinationName: "觀音山遊客中心",
            category: .mountainClimb,
            estimatedDistanceKm: 16.5,
            estimatedAscentMeters: 360.0,
            difficulty: "硬漢訓練 ⭐⭐⭐",
            highlights: ["俯瞰淡水河入海口", "連續髮夾彎", "車友打卡聖地"],
            coordinate: CLLocationCoordinate2D(latitude: 25.1378, longitude: 121.4172)
        ),
        // Northern Taiwan (Taipei / New Taipei / Keelung / Taoyuan)
        VeloDiceLuckyRoute(
            title: "淡水老街金色水岸",
            subtitle: "淡水河畔 · 夕陽微風 · 專用自行車道",
            destinationName: "淡水老街",
            category: .riverSide,
            estimatedDistanceKm: 21.5,
            estimatedAscentMeters: 45.0,
            difficulty: "休閒入門 ⭐",
            highlights: ["金色夕陽", "平緩無坡", "沿途補給充足"],
            coordinate: CLLocationCoordinate2D(latitude: 25.1698, longitude: 121.4441)
        ),
        VeloDiceLuckyRoute(
            title: "八里左岸十三行風情",
            subtitle: "左岸自行車道 · 渡船頭海風",
            destinationName: "八里左岸公園",
            category: .coastalBreeze,
            estimatedDistanceKm: 23.8,
            estimatedAscentMeters: 35.0,
            difficulty: "休閒水岸 ⭐",
            highlights: ["十三行博物館", "渡船頭景觀", "海口日落"],
            coordinate: CLLocationCoordinate2D(latitude: 25.1610, longitude: 121.4055)
        ),
        VeloDiceLuckyRoute(
            title: "貓空指南宮景觀挑戰",
            subtitle: "文山茶香 · 眺望台北101天際線",
            destinationName: "指南宮",
            category: .mountainClimb,
            estimatedDistanceKm: 15.5,
            estimatedAscentMeters: 380.0,
            difficulty: "進階有氧 ⭐⭐",
            highlights: ["俯瞰大台北", "木柵茶坊", "林蔭山路"],
            coordinate: CLLocationCoordinate2D(latitude: 24.9786, longitude: 121.5878)
        ),
        VeloDiceLuckyRoute(
            title: "風櫃嘴朝聖經典爬坡",
            subtitle: "北部車友朝聖之巔 · 雲海眺望涼亭",
            destinationName: "風櫃嘴觀景台",
            category: .mountainClimb,
            estimatedDistanceKm: 18.2,
            estimatedAscentMeters: 450.0,
            difficulty: "硬派挑戰 ⭐⭐⭐",
            highlights: ["單車聖地", "無敵全景", "連續彎道考驗"],
            coordinate: CLLocationCoordinate2D(latitude: 25.1378, longitude: 121.6022)
        ),
        VeloDiceLuckyRoute(
            title: "中社路晨練計時線",
            subtitle: "外雙溪綠意 · 穩定回轉坡度練習",
            destinationName: "中社路公車迴轉道",
            category: .mountainClimb,
            estimatedDistanceKm: 13.5,
            estimatedAscentMeters: 260.0,
            difficulty: "節奏巡航 ⭐⭐",
            highlights: ["路燈明亮", "晨昏車友聚集", "均勻坡度"],
            coordinate: CLLocationCoordinate2D(latitude: 25.1190, longitude: 121.5833)
        ),
        VeloDiceLuckyRoute(
            title: "碧潭風景區水岸漫遊",
            subtitle: "新店溪自行車道 · 天鵝湖畔吊橋",
            destinationName: "碧潭風景區",
            category: .riverSide,
            estimatedDistanceKm: 12.8,
            estimatedAscentMeters: 30.0,
            difficulty: "輕鬆悠遊 ⭐",
            highlights: ["碧潭吊橋", "河畔水岸咖啡", "平坦綠意廊道"],
            coordinate: CLLocationCoordinate2D(latitude: 24.9535, longitude: 121.5367)
        ),
        VeloDiceLuckyRoute(
            title: "鶯歌陶瓷老街人文巡航",
            subtitle: "大漢溪自行車道 · 陶藝古色小鎮",
            destinationName: "鶯歌陶瓷老街",
            category: .culturalOldStreet,
            estimatedDistanceKm: 26.2,
            estimatedAscentMeters: 65.0,
            difficulty: "平路耐力 ⭐⭐",
            highlights: ["大漢溪綠色走廊", "三鶯藝術村", "陶瓷人文街景"],
            coordinate: CLLocationCoordinate2D(latitude: 24.9525, longitude: 121.3533)
        ),
        VeloDiceLuckyRoute(
            title: "烏來老街溪谷輕騎",
            subtitle: "南勢溪峽谷 · 溫泉小鎮瀑布風光",
            destinationName: "烏來老街",
            category: .forestGravel,
            estimatedDistanceKm: 23.5,
            estimatedAscentMeters: 310.0,
            difficulty: "進階有氧 ⭐⭐",
            highlights: ["高山溪谷流水", "溫泉部落", "烏來瀑布景緻"],
            coordinate: CLLocationCoordinate2D(latitude: 24.8637, longitude: 121.5510)
        ),
        VeloDiceLuckyRoute(
            title: "平溪十分老街鐵道線",
            subtitle: "基隆河谷山林 · 伴隨鐵道靜謐巡航",
            destinationName: "十分老街",
            category: .forestGravel,
            estimatedDistanceKm: 27.8,
            estimatedAscentMeters: 390.0,
            difficulty: "長途耐力 ⭐⭐",
            highlights: ["十分瀑布", "鐵道風情", "幽靜林蔭彎道"],
            coordinate: CLLocationCoordinate2D(latitude: 25.0428, longitude: 121.7766)
        ),
        VeloDiceLuckyRoute(
            title: "社子島濕地雙河匯流",
            subtitle: "基隆河與淡水河交匯處 · 水鳥濕地生態",
            destinationName: "社子島島頭公園",
            category: .riverSide,
            estimatedDistanceKm: 15.6,
            estimatedAscentMeters: 20.0,
            difficulty: "平路入門 ⭐",
            highlights: ["雙河壯闊匯流", "環島自行車專用道", "大屯山倒影"],
            coordinate: CLLocationCoordinate2D(latitude: 25.1098, longitude: 121.4725)
        ),
        VeloDiceLuckyRoute(
            title: "石碇千島湖前哨湖光線",
            subtitle: "北宜公路支線 · 翡翠水庫碧水梯田",
            destinationName: "石碇千島湖觀景台",
            category: .scenicLake,
            estimatedDistanceKm: 26.5,
            estimatedAscentMeters: 460.0,
            difficulty: "爬坡挑戰 ⭐⭐⭐",
            highlights: ["千島湖絕景", "八卦茶園", "翡翠水庫全景"],
            coordinate: CLLocationCoordinate2D(latitude: 24.9360, longitude: 121.6465)
        ),
        VeloDiceLuckyRoute(
            title: "陽明山冷水坑高山線",
            subtitle: "仰德大道接菁山路 · 高山冷霧與火山硫磺",
            destinationName: "冷水坑遊客服務站",
            category: .mountainClimb,
            estimatedDistanceKm: 19.8,
            estimatedAscentMeters: 690.0,
            difficulty: "高強度爬坡 ⭐⭐⭐",
            highlights: ["高山冷霧", "菁山吊橋", "牛奶湖地貌"],
            coordinate: CLLocationCoordinate2D(latitude: 25.1666, longitude: 121.5623)
        ),
        VeloDiceLuckyRoute(
            title: "基隆潮境公園望海線",
            subtitle: "海濱公路巡弋 · 飛天掃帚海天一色",
            destinationName: "潮境公園",
            category: .coastalBreeze,
            estimatedDistanceKm: 25.2,
            estimatedAscentMeters: 180.0,
            difficulty: "中度海風 ⭐⭐",
            highlights: ["基隆嶼遠眺", "濱海浪花", "潮境裝置藝術"],
            coordinate: CLLocationCoordinate2D(latitude: 25.1436, longitude: 121.8028)
        ),
        VeloDiceLuckyRoute(
            title: "萬里野柳岬海角線",
            subtitle: "北海岸碧海藍天 · 奇岩怪石海風馳騁",
            destinationName: "野柳地質公園",
            category: .coastalBreeze,
            estimatedDistanceKm: 28.5,
            estimatedAscentMeters: 220.0,
            difficulty: "中長途耐力 ⭐⭐",
            highlights: ["女王頭地貌", "遼闊海平線", "漁港海產補給"],
            coordinate: CLLocationCoordinate2D(latitude: 25.2066, longitude: 121.6908)
        ),
        VeloDiceLuckyRoute(
            title: "桃園大溪老街大漢溪段",
            subtitle: "大漢溪左岸自行車道 · 巴洛克風大溪橋",
            destinationName: "大溪老街",
            category: .culturalOldStreet,
            estimatedDistanceKm: 24.5,
            estimatedAscentMeters: 120.0,
            difficulty: "休閒長途 ⭐⭐",
            highlights: ["大溪古橋", "豆干美食", "河濱開闊視野"],
            coordinate: CLLocationCoordinate2D(latitude: 24.8845, longitude: 121.2875)
        ),
        VeloDiceLuckyRoute(
            title: "石門水庫楓林環湖段",
            subtitle: "水庫大壩壯闊洩洪口 · 環湖林蔭公路",
            destinationName: "石門水庫大壩",
            category: .scenicLake,
            estimatedDistanceKm: 27.5,
            estimatedAscentMeters: 340.0,
            difficulty: "起伏山路 ⭐⭐",
            highlights: ["水庫洩洪道", "楓林環湖步道", "活魚美食聚集"],
            coordinate: CLLocationCoordinate2D(latitude: 24.8152, longitude: 121.2464)
        ),
        VeloDiceLuckyRoute(
            title: "觀音草漯沙丘海風線",
            subtitle: "台版撒哈拉荒漠秘境 · 巨大白色風車列陣",
            destinationName: "草漯沙丘地質公園",
            category: .coastalBreeze,
            estimatedDistanceKm: 26.8,
            estimatedAscentMeters: 45.0,
            difficulty: "平路海風 ⭐⭐",
            highlights: ["風車海濱", "奇幻沙丘荒漠", "夕陽餘暉"],
            coordinate: CLLocationCoordinate2D(latitude: 25.0682, longitude: 121.1444)
        ),
        VeloDiceLuckyRoute(
            title: "新竹南寮十七公里海岸線",
            subtitle: "伴隨台灣海峽蔚藍海岸 · 彩虹橋地標",
            destinationName: "南寮漁港",
            category: .coastalBreeze,
            estimatedDistanceKm: 19.2,
            estimatedAscentMeters: 30.0,
            difficulty: "平緩放鬆 ⭐",
            highlights: ["藍白地中海建築", "魚鱗天梯", "專用自行車綠廊"],
            coordinate: CLLocationCoordinate2D(latitude: 24.8488, longitude: 120.9272)
        ),
        
        // Central Taiwan
        VeloDiceLuckyRoute(
            title: "台中高美濕地落日風車線",
            subtitle: "清水大排至海口 · 絕美夕陽與風力發電機",
            destinationName: "高美濕地",
            category: .coastalBreeze,
            estimatedDistanceKm: 22.5,
            estimatedAscentMeters: 25.0,
            difficulty: "休閒平路 ⭐",
            highlights: ["木棧道水鳥", "夕陽天空之鏡", "巨大海邊風車"],
            coordinate: CLLocationCoordinate2D(latitude: 24.3120, longitude: 120.5500)
        ),
        VeloDiceLuckyRoute(
            title: "東豐鐵道綠色走廊",
            subtitle: "舊鐵道綠色林蔭隧廊 · 梅子鐵橋景觀",
            destinationName: "東勢客家文化園區",
            category: .forestGravel,
            estimatedDistanceKm: 14.5,
            estimatedAscentMeters: 85.0,
            difficulty: "親子入門 ⭐",
            highlights: ["專用單車綠廊", "九號隧道", "石岡水壩"],
            coordinate: CLLocationCoordinate2D(latitude: 24.2690, longitude: 120.7630)
        ),
        VeloDiceLuckyRoute(
            title: "日月潭向山環潭水上線",
            subtitle: "全球前十最美單車道 · 水上懸臂觀景台",
            destinationName: "向山遊客中心",
            category: .scenicLake,
            estimatedDistanceKm: 28.0,
            estimatedAscentMeters: 320.0,
            difficulty: "丘陵美景 ⭐⭐",
            highlights: ["全球最美單車道", "向山懸臂觀景台", "湖光山色倒影"],
            coordinate: CLLocationCoordinate2D(latitude: 23.8520, longitude: 120.9020)
        ),
        VeloDiceLuckyRoute(
            title: "八卦山139縣道稜線挑戰",
            subtitle: "彰化投縣界山脊道路 · 鳳山寺車友大本營",
            destinationName: "八卦山大佛風景區",
            category: .mountainClimb,
            estimatedDistanceKm: 22.0,
            estimatedAscentMeters: 330.0,
            difficulty: "進階有氧 ⭐⭐",
            highlights: ["稜線微風", "落羽松森林", "車友補給名所"],
            coordinate: CLLocationCoordinate2D(latitude: 24.0320, longitude: 120.6120)
        ),
        
        // Southern Taiwan
        VeloDiceLuckyRoute(
            title: "高雄旗津環島踩風線",
            subtitle: "搭渡輪越海 · 旗後砲台與星空隧道",
            destinationName: "旗津風車公園",
            category: .coastalBreeze,
            estimatedDistanceKm: 17.5,
            estimatedAscentMeters: 15.0,
            difficulty: "海島休閒 ⭐",
            highlights: ["渡輪體驗", "旗後燈塔全景", "海產老街美饌"],
            coordinate: CLLocationCoordinate2D(latitude: 22.5690, longitude: 120.3010)
        ),
        VeloDiceLuckyRoute(
            title: "台南四草台江鹽田綠道",
            subtitle: "四草綠色隧道 · 鹽田夕陽與黑面琵鷺",
            destinationName: "四草綠色隧道",
            category: .riverSide,
            estimatedDistanceKm: 20.5,
            estimatedAscentMeters: 20.0,
            difficulty: "平路自然 ⭐",
            highlights: ["袖珍版亞馬遜", "安平古堡串聯", "鹽田落日"],
            coordinate: CLLocationCoordinate2D(latitude: 23.0180, longitude: 120.1340)
        ),
        VeloDiceLuckyRoute(
            title: "屏東大鵬灣環灣潟湖線",
            subtitle: "跨海大橋日落 · 專用無障礙環灣自行車道",
            destinationName: "大鵬灣國家風景區",
            category: .coastalBreeze,
            estimatedDistanceKm: 13.5,
            estimatedAscentMeters: 15.0,
            difficulty: "輕鬆悠遊 ⭐",
            highlights: ["開合跨海大橋", "全台最大囊狀潟湖", "蚵殼島秘境"],
            coordinate: CLLocationCoordinate2D(latitude: 22.4550, longitude: 120.4850)
        ),
        
        // Eastern Taiwan
        VeloDiceLuckyRoute(
            title: "冬山河親水水岸綠廊",
            subtitle: "利澤簡紅橋倒影 · 宜蘭冬山河自行車道",
            destinationName: "冬山河親水公園",
            category: .riverSide,
            estimatedDistanceKm: 21.0,
            estimatedAscentMeters: 25.0,
            difficulty: "平緩休閒 ⭐",
            highlights: ["冬山河紅橋", "水鳥倒影綠廊", "傳統藝術中心串聯"],
            coordinate: CLLocationCoordinate2D(latitude: 24.6720, longitude: 121.8230)
        ),
        VeloDiceLuckyRoute(
            title: "花蓮七星潭蔚藍太平洋線",
            subtitle: "月牙灣碎石沙灘 · 臨海懸崖自行車步道",
            destinationName: "七星潭風景區",
            category: .coastalBreeze,
            estimatedDistanceKm: 23.5,
            estimatedAscentMeters: 55.0,
            difficulty: "海風舒暢 ⭐⭐",
            highlights: ["月牙灣海岸線", "看海聽浪步道", "花蓮港海風馳騁"],
            coordinate: CLLocationCoordinate2D(latitude: 24.0320, longitude: 121.6290)
        ),
        VeloDiceLuckyRoute(
            title: "台東池上伯朗大道天堂路",
            subtitle: "中央山脈下金黃稻浪 · 無邊際綠野田園",
            destinationName: "伯朗大道金城武樹",
            category: .forestGravel,
            estimatedDistanceKm: 15.2,
            estimatedAscentMeters: 80.0,
            difficulty: "悠活田園 ⭐",
            highlights: ["金黃稻浪畫布", "中央山脈壯麗襯景", "大坡池環湖"],
            coordinate: CLLocationCoordinate2D(latitude: 23.1000, longitude: 121.2180)
        )
    ]
    
    /// 根據使用者目前座標，篩選「距離目前位置 30 公里以內」的熱門路線（路線長短不限）
    public func fetchRoutesNearby(userCoordinate: CLLocationCoordinate2D?) async -> [VeloDiceLuckyRoute] {
        let center = userCoordinate ?? CLLocationCoordinate2D(latitude: 25.0330, longitude: 121.5654)
        let userLoc = CLLocation(latitude: center.latitude, longitude: center.longitude)
        
        var calculatedRoutes = curatedCatalog.map { route -> VeloDiceLuckyRoute in
            var r = route
            let targetLoc = CLLocation(latitude: r.coordinate.latitude, longitude: r.coordinate.longitude)
            r.distanceFromUserKm = userLoc.distance(from: targetLoc) / 1000.0
            return r
        }
        
        // 嚴格篩選：距離目前位置 30 公里以內（路線本身長度不限）
        var filtered = calculatedRoutes.filter { $0.distanceFromUserKm > 0.05 && $0.distanceFromUserKm <= 30.0 }
        
        // 若該範圍內數量偏少，優雅擴充至 35 公里以內，確保使用者總有豐富選擇
        if filtered.count < 3 {
            let expanded = calculatedRoutes.filter { $0.distanceFromUserKm > 0.05 && $0.distanceFromUserKm <= 35.0 }
            if !expanded.isEmpty {
                filtered = expanded
            }
        }
        
        // 若依然沒有（例如在海外或離島），透過 MKLocalSearch 動態探索距離目前位置 30km 內景點
        if filtered.isEmpty {
            let dynamicFound = await searchDynamicNearbySpots(around: center)
            if !dynamicFound.isEmpty {
                filtered = dynamicFound
            } else {
                // 回退至最靠近使用者的 5 條經典路線
                filtered = Array(calculatedRoutes.sorted(by: { $0.distanceFromUserKm < $1.distanceFromUserKm }).prefix(5))
            }
        }
        
        self.availableNearbyRoutes = filtered.sorted(by: { $0.distanceFromUserKm < $1.distanceFromUserKm })
        return self.availableNearbyRoutes
    }
    
    /// 擲骰子：隨機選取一條距離目前位置 30km 內的路線（排除目前正顯示的路線，若有其他選項）
    @discardableResult
    public func rollDice(userCoordinate: CLLocationCoordinate2D?) async -> VeloDiceLuckyRoute? {
        self.isRolling = true
        defer { self.isRolling = false }
        
        if availableNearbyRoutes.isEmpty {
            _ = await fetchRoutesNearby(userCoordinate: userCoordinate)
        }
        
        guard !availableNearbyRoutes.isEmpty else { return nil }
        
        let pool: [VeloDiceLuckyRoute]
        if availableNearbyRoutes.count > 1, let current = currentLuckyRoute {
            let filtered = availableNearbyRoutes.filter { $0.id != current.id }
            pool = filtered.isEmpty ? availableNearbyRoutes : filtered
        } else {
            pool = availableNearbyRoutes
        }
        
        let selected = pool.randomElement() ?? availableNearbyRoutes[0]
        self.currentLuckyRoute = selected
        return selected
    }
    
    /// 動態探索周遭自行車道或風景區 (支援全世界任何城市定位)
    private func searchDynamicNearbySpots(around center: CLLocationCoordinate2D) async -> [VeloDiceLuckyRoute] {
        let queries = ["自行車道", "風景區", "觀景台", "自然公園", "Bike Path"]
        let userLoc = CLLocation(latitude: center.latitude, longitude: center.longitude)
        var dynamicList: [VeloDiceLuckyRoute] = []
        
        for q in queries {
            let req = MKLocalSearch.Request()
            req.naturalLanguageQuery = q
            req.region = MKCoordinateRegion(center: center, latitudinalMeters: 60000, longitudinalMeters: 60000)
            
            do {
                let search = MKLocalSearch(request: req)
                let resp = try await search.start()
                for item in resp.mapItems {
                    guard let name = item.name, !name.isEmpty else { continue }
                    let coord = item.placemark.coordinate
                    let distKm = userLoc.distance(from: CLLocation(latitude: coord.latitude, longitude: coord.longitude)) / 1000.0
                    
                    if distKm > 0.5 && distKm <= 30.0 {
                        let route = VeloDiceLuckyRoute(
                            title: "\(name) 隨機探索線",
                            subtitle: "在地熱門推薦 · 單車探索巡航",
                            destinationName: name,
                            category: .forestGravel,
                            estimatedDistanceKm: round(distKm * 1.15 * 10) / 10,
                            estimatedAscentMeters: 120.0,
                            difficulty: "在地漫遊 ⭐⭐",
                            highlights: ["地圖推薦亮點", "隨機探索驚喜", "專屬客製導航"],
                            coordinate: coord,
                            distanceFromUserKm: distKm
                        )
                        if !dynamicList.contains(where: { $0.destinationName == name }) {
                            dynamicList.append(route)
                        }
                    }
                }
            } catch {
                continue
            }
            if dynamicList.count >= 6 { break }
        }
        
        return dynamicList
    }
}

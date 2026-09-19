import Foundation
import CoreLocation
import SwiftUI

// MARK: - Route Point Model
public struct RoutePoint: Identifiable, Codable, Equatable {
    public var id = UUID()
    public var latitude: Double
    public var longitude: Double
    public var elevation: Double // in meters
    public var timestamp: Date?
    public var heartRate: Int?
    public var cadence: Int?
    public var speedKmh: Double?
    
    public var coordinate: CLLocationCoordinate2D {
        CLLocationCoordinate2D(latitude: latitude, longitude: longitude)
    }
    
    public init(id: UUID = UUID(), latitude: Double, longitude: Double, elevation: Double = 0, timestamp: Date? = nil, heartRate: Int? = nil, cadence: Int? = nil, speedKmh: Double? = nil) {
        self.id = id
        self.latitude = latitude
        self.longitude = longitude
        self.elevation = elevation
        self.timestamp = timestamp
        self.heartRate = heartRate
        self.cadence = cadence
        self.speedKmh = speedKmh
    }
}

// MARK: - Waypoint Model
public struct GPXWaypoint: Identifiable, Codable, Equatable {
    public var id = UUID()
    public var name: String
    public var latitude: Double
    public var longitude: Double
    public var elevation: Double
    public var iconName: String
    
    public var coordinate: CLLocationCoordinate2D {
        CLLocationCoordinate2D(latitude: latitude, longitude: longitude)
    }
    
    public init(id: UUID = UUID(), name: String, latitude: Double, longitude: Double, elevation: Double = 0, iconName: String = "mappin.circle.fill") {
        self.id = id
        self.name = name
        self.latitude = latitude
        self.longitude = longitude
        self.elevation = elevation
        self.iconName = iconName
    }
}

// MARK: - GPX Track Model
public struct GPXTrack: Identifiable, Codable, Equatable {
    public var id = UUID()
    public var title: String
    public var points: [RoutePoint]
    public var waypoints: [GPXWaypoint]
    public var totalDistanceKm: Double
    public var totalAscentMeters: Double
    public var totalDescentMeters: Double
    public var maxElevationMeters: Double
    public var minElevationMeters: Double
    public var avgGradientPercent: Double
    
    public init(title: String, points: [RoutePoint], waypoints: [GPXWaypoint] = []) {
        self.title = title
        self.points = points
        self.waypoints = waypoints
        
        var dist = 0.0
        var uphillDistKm = 0.0
        var maxEle = points.first?.elevation ?? 0.0
        var minEle = points.first?.elevation ?? 0.0
        
        // 1. 計算真實累積里程 (濾除 GPS 定位漂移)
        if points.count > 1 {
            for i in 1..<points.count {
                let p1 = CLLocation(latitude: points[i-1].latitude, longitude: points[i-1].longitude)
                let p2 = CLLocation(latitude: points[i].latitude, longitude: points[i].longitude)
                let stepMeters = p1.distance(from: p2)
                // 排除原地 < 1.0m 微小抖動與 > 300m 異常瞬移雜訊
                if stepMeters >= 0.5 && stepMeters < 300.0 {
                    dist += (stepMeters / 1000.0)
                }
                maxEle = max(maxEle, points[i].elevation)
                minEle = min(minEle, points[i].elevation)
            }
        }
        
        // 2. 專業級海拔濾波 (移動平均 + 自適應遲滯閾值演算法，精確捕捉坡度與爬升，杜絕 0m 誤判)
        var smoothedElevations: [Double] = []
        let windowSize = min(5, max(1, points.count))
        let count = points.count
        for i in 0..<count {
            let start = max(0, i - windowSize / 2)
            let end = min(count - 1, i + windowSize / 2)
            let sub = points[start...end].map(\.elevation)
            let avg = sub.reduce(0.0, +) / Double(sub.count)
            smoothedElevations.append(avg)
        }
        
        var ascent = 0.0
        var descent = 0.0
        if let first = smoothedElevations.first {
            var anchorEle = first
            let threshold = 0.8 // 0.8 公尺爬升門檻，敏銳捕捉坡度變化，防止平緩上坡被誤過濾為 0
            
            for i in 1..<smoothedElevations.count {
                let current = smoothedElevations[i]
                let diff = current - anchorEle
                if diff >= threshold {
                    ascent += diff
                    anchorEle = current
                    
                    // 記錄上坡區段里程
                    let p1 = CLLocation(latitude: points[i-1].latitude, longitude: points[i-1].longitude)
                    let p2 = CLLocation(latitude: points[i].latitude, longitude: points[i].longitude)
                    uphillDistKm += (p1.distance(from: p2) / 1000.0)
                } else if diff <= -threshold {
                    descent += abs(diff)
                    anchorEle = current
                }
            }
        }
        
        // 物理保證：若最高海拔與最低海拔有落差，累計爬升至少應達到高度落差
        let elevationSpan = max(0.0, maxEle - minEle)
        if elevationSpan >= 2.0 && ascent < elevationSpan {
            ascent = max(ascent, elevationSpan)
        }
        
        self.totalDistanceKm = dist
        self.totalAscentMeters = ascent
        self.totalDescentMeters = descent
        self.maxElevationMeters = maxEle
        self.minElevationMeters = minEle
        
        // 坡度計算：以上坡路段真實平均坡度計算，若上坡里程不足則以全段計算
        if uphillDistKm >= 0.1 && ascent > 0.0 {
            self.avgGradientPercent = (ascent / (uphillDistKm * 1000.0)) * 100.0
        } else if dist > 0.05 && ascent > 0.0 {
            self.avgGradientPercent = (ascent / (dist * 1000.0)) * 100.0
        } else {
            self.avgGradientPercent = 0.0
        }
    }
    
    /// 計算每一點沿線的真實累積里程 (單位: km)，用於高程剖面圖保持物理等比例
    public func cumulativeDistances() -> [Double] {
        guard points.count > 1 else { return [0.0] }
        var result: [Double] = [0.0]
        var currentDist = 0.0
        for i in 1..<points.count {
            let p1 = CLLocation(latitude: points[i-1].latitude, longitude: points[i-1].longitude)
            let p2 = CLLocation(latitude: points[i].latitude, longitude: points[i].longitude)
            let stepM = p1.distance(from: p2)
            if stepM < 300.0 {
                currentDist += stepM / 1000.0
            }
            result.append(currentDist)
        }
        return result
    }
}

// MARK: - Supply Point (Convenience Store, Gas Station, Water)
public struct SupplyPoint: Identifiable, Equatable, Hashable {
    public var id = UUID()
    public var name: String
    public var category: SupplyCategory
    public var coordinate: CLLocationCoordinate2D
    public var distanceFromStartKm: Double
    public var note: String
    public var distanceToUserMeters: Double?
    public var distanceToRouteMeters: Double?
    public var isNearestTop5: Bool
    
    public init(
        id: UUID = UUID(),
        name: String,
        category: SupplyCategory,
        coordinate: CLLocationCoordinate2D,
        distanceFromStartKm: Double,
        note: String,
        distanceToUserMeters: Double? = nil,
        distanceToRouteMeters: Double? = nil,
        isNearestTop5: Bool = false
    ) {
        self.id = id
        self.name = name
        self.category = category
        self.coordinate = coordinate
        self.distanceFromStartKm = distanceFromStartKm
        self.note = note
        self.distanceToUserMeters = distanceToUserMeters
        self.distanceToRouteMeters = distanceToRouteMeters
        self.isNearestTop5 = isNearestTop5
    }
    
    public var formattedUserDistance: String {
        guard let d = distanceToUserMeters else {
            return String(format: "約 %.1f km 處", distanceFromStartKm)
        }
        if d < 1000 {
            return "\(Int(d)) 公尺"
        } else {
            return String(format: "%.1f 公里", d / 1000.0)
        }
    }
    
    public var formattedRouteDistance: String {
        guard let d = distanceToRouteMeters else { return "" }
        if d < 500 {
            return "路線旁 \(Int(d))m"
        } else {
            return "離路線 \(Int(d))m"
        }
    }
    
    public static func == (lhs: SupplyPoint, rhs: SupplyPoint) -> Bool {
        lhs.id == rhs.id
    }
    
    public func hash(into hasher: inout Hasher) {
        hasher.combine(id)
    }
    
    public enum SupplyCategory: String, CaseIterable {
        case convenienceStore = "便利商店"
        case gasStation = "加油站"
        case waterStation = "補水點 / 飲水處"
        case bikeShop = "單車補給/維修"
        case restaurant = "餐廳 / 補給站"
        
        public var icon: String {
            switch self {
            case .convenienceStore: return "storefront.fill"
            case .gasStation: return "fuelpump.fill"
            case .waterStation: return "drop.fill"
            case .bikeShop: return "bicycle"
            case .restaurant: return "fork.knife"
            }
        }
        
        public var color: Color {
            switch self {
            case .convenienceStore: return .green
            case .gasStation: return .orange
            case .waterStation: return .blue
            case .bikeShop: return .purple
            case .restaurant: return .red
            }
        }
    }
}

// MARK: - Weather Point Forecast Along Route (沿途路段路過時間與降雨機率預報)
public enum WindRelativeDirection {
    case headwind   // 逆風 (Red)
    case tailwind   // 順風 (Green)
    case crosswind  // 側風 (Orange)
}

public struct RouteWeatherForecast: Identifiable {
    public var id = UUID()
    public var waypointName: String
    public var coordinate: CLLocationCoordinate2D
    public var projectedTime: Date
    public var distanceKm: Double
    public var elevationMeters: Double
    public var temperatureC: Double
    public var rainProbabilityPercent: Int
    public var weatherSymbol: String
    public var weatherCondition: String
    public var windSpeedKmh: Double
    public var windDirectionDegrees: Double
    public var advice: String
    public var isPassed: Bool
    
    public init(
        id: UUID = UUID(),
        waypointName: String,
        coordinate: CLLocationCoordinate2D,
        projectedTime: Date,
        distanceKm: Double,
        elevationMeters: Double = 0.0,
        temperatureC: Double,
        rainProbabilityPercent: Int,
        weatherSymbol: String,
        weatherCondition: String,
        windSpeedKmh: Double,
        windDirectionDegrees: Double = 45.0,
        advice: String = "",
        isPassed: Bool = false
    ) {
        self.id = id
        self.waypointName = waypointName
        self.coordinate = coordinate
        self.projectedTime = projectedTime
        self.distanceKm = distanceKm
        self.elevationMeters = elevationMeters
        self.temperatureC = temperatureC
        self.rainProbabilityPercent = rainProbabilityPercent
        self.weatherSymbol = weatherSymbol
        self.weatherCondition = weatherCondition
        self.windSpeedKmh = windSpeedKmh
        self.windDirectionDegrees = windDirectionDegrees
        self.advice = advice
        self.isPassed = isPassed
    }
    
    // 風向文字描述 (例: 東北風、西南風)
    public var windCompassText: String {
        let deg = Int(windDirectionDegrees) % 360
        switch deg {
        case 338...360, 0...22: return "北風"
        case 23...67: return "東北風"
        case 68...112: return "東風"
        case 113...157: return "東南風"
        case 158...202: return "南風"
        case 203...247: return "西南風"
        case 248...292: return "西風"
        case 293...337: return "西北風"
        default: return "\(deg)°"
        }
    }
    
    // 相對於騎乘前進方向之風向研判：逆風(紅色)、順風(綠色)、側風(黃橘色)
    public func relativeWind(to userHeading: Double?) -> (type: WindRelativeDirection, description: String, color: Color) {
        guard let heading = userHeading, heading >= 0 else {
            return (.crosswind, "\(windCompassText) \(Int(windSpeedKmh)) km/h", .orange)
        }
        
        var diff = abs(heading - windDirectionDegrees).truncatingRemainder(dividingBy: 360)
        if diff > 180 {
            diff = 360 - diff
        }
        
        if diff <= 45 {
            return (.headwind, "正面逆風 (\(windCompassText) \(Int(windSpeedKmh))k)", .red)
        } else if diff >= 135 {
            return (.tailwind, "助力順風 (\(windCompassText) \(Int(windSpeedKmh))k)", .green)
        } else {
            return (.crosswind, "路段側風 (\(windCompassText) \(Int(windSpeedKmh))k)", .orange)
        }
    }
}

// MARK: - Segment & Personal Record (PR)
public struct SegmentRecord: Identifiable, Codable {
    public var id = UUID()
    public var name: String
    public var startCoordinate: RoutePoint
    public var endCoordinate: RoutePoint
    public var distanceKm: Double
    public var elevationGainMeters: Double
    public var avgGradientPercent: Double
    public var personalRecordSeconds: TimeInterval?
    public var latestAttemptSeconds: TimeInterval?
    public var attemptCount: Int
    
    // 最近刪除與 3 個月 (90天) 永久刪除機制
    public var isDeleted: Bool = false
    public var deletedAt: Date? = nil
    
    public init(
        id: UUID = UUID(),
        name: String,
        startCoordinate: RoutePoint,
        endCoordinate: RoutePoint,
        distanceKm: Double,
        elevationGainMeters: Double,
        avgGradientPercent: Double,
        personalRecordSeconds: TimeInterval? = nil,
        latestAttemptSeconds: TimeInterval? = nil,
        attemptCount: Int = 0,
        isDeleted: Bool = false,
        deletedAt: Date? = nil
    ) {
        self.id = id
        self.name = name
        self.startCoordinate = startCoordinate
        self.endCoordinate = endCoordinate
        self.distanceKm = distanceKm
        self.elevationGainMeters = elevationGainMeters
        self.avgGradientPercent = avgGradientPercent
        self.personalRecordSeconds = personalRecordSeconds
        self.latestAttemptSeconds = latestAttemptSeconds
        self.attemptCount = attemptCount
        self.isDeleted = isDeleted
        self.deletedAt = deletedAt
    }
    
    public var isNewPR: Bool {
        guard let pr = personalRecordSeconds, let latest = latestAttemptSeconds else { return false }
        return latest <= pr
    }
    
    public var remainingDaysBeforePermanentDelete: Int {
        guard let delDate = deletedAt else { return 90 }
        let elapsed = Date().timeIntervalSince(delDate)
        let totalSeconds = 90.0 * 86400.0
        return max(0, Int(ceil((totalSeconds - elapsed) / 86400.0)))
    }
    
    public var isExpiredForPermanentDelete: Bool {
        guard let delDate = deletedAt else { return false }
        return Date().timeIntervalSince(delDate) >= (90.0 * 86400.0)
    }
    
    enum CodingKeys: String, CodingKey {
        case id, name, startCoordinate, endCoordinate, distanceKm, elevationGainMeters
        case avgGradientPercent, personalRecordSeconds, latestAttemptSeconds, attemptCount
        case isDeleted, deletedAt
    }
    
    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.id = try container.decodeIfPresent(UUID.self, forKey: .id) ?? UUID()
        self.name = try container.decode(String.self, forKey: .name)
        self.startCoordinate = try container.decode(RoutePoint.self, forKey: .startCoordinate)
        self.endCoordinate = try container.decode(RoutePoint.self, forKey: .endCoordinate)
        self.distanceKm = try container.decode(Double.self, forKey: .distanceKm)
        self.elevationGainMeters = try container.decode(Double.self, forKey: .elevationGainMeters)
        self.avgGradientPercent = try container.decode(Double.self, forKey: .avgGradientPercent)
        self.personalRecordSeconds = try container.decodeIfPresent(TimeInterval.self, forKey: .personalRecordSeconds)
        self.latestAttemptSeconds = try container.decodeIfPresent(TimeInterval.self, forKey: .latestAttemptSeconds)
        self.attemptCount = try container.decodeIfPresent(Int.self, forKey: .attemptCount) ?? 0
        self.isDeleted = try container.decodeIfPresent(Bool.self, forKey: .isDeleted) ?? false
        self.deletedAt = try container.decodeIfPresent(Date.self, forKey: .deletedAt)
    }
}

// MARK: - Milestone Records
public struct MilestoneRecord: Identifiable {
    public var id = UUID()
    public var title: String
    public var type: MilestoneType
    public var targetValue: Double
    public var bestTimeSeconds: TimeInterval?
    public var achievedDate: Date?
    public var isAchievedToday: Bool
    
    public enum MilestoneType {
        case distance
        case elevation
    }
}

// MARK: - Activity Summary
public struct ActivitySummary {
    public var title: String
    public var activityDate: Date
    public var durationSeconds: TimeInterval
    public var distanceKm: Double
    public var elevationGainMeters: Double
    public var avgSpeedKmh: Double
    public var maxSpeedKmh: Double
    public var avgHeartRateBpm: Int
    public var maxHeartRateBpm: Int
    public var avgCadenceRpm: Int
    public var calories: Int
    public var trackPoints: [RoutePoint]
}

// MARK: - Segment Effort (Strava-style Segment Performance in a Workout)
public struct SegmentEffort: Identifiable, Codable, Equatable {
    public var id: UUID
    public var segmentId: UUID?
    public var segmentName: String
    public var distanceKm: Double
    public var elevationGainMeters: Double
    public var avgGradientPercent: Double
    public var timeSeconds: TimeInterval
    public var avgSpeedKmh: Double
    public var date: Date
    public var isPR: Bool
    
    public init(
        id: UUID = UUID(),
        segmentId: UUID? = nil,
        segmentName: String,
        distanceKm: Double,
        elevationGainMeters: Double,
        avgGradientPercent: Double,
        timeSeconds: TimeInterval,
        avgSpeedKmh: Double,
        date: Date = Date(),
        isPR: Bool = false
    ) {
        self.id = id
        self.segmentId = segmentId
        self.segmentName = segmentName
        self.distanceKm = distanceKm
        self.elevationGainMeters = elevationGainMeters
        self.avgGradientPercent = avgGradientPercent
        self.timeSeconds = timeSeconds
        self.avgSpeedKmh = avgSpeedKmh
        self.date = date
        self.isPR = isPR
    }
}

// MARK: - Strava-style Career All-Time Records (歷年最高、最長、極限紀錄)
public struct CareerAllTimeStats: Codable, Equatable {
    public var totalRides: Int = 0
    public var totalDistanceKm: Double = 0.0
    public var totalAscentMeters: Double = 0.0
    public var totalDurationSeconds: TimeInterval = 0.0
    public var longestDistanceKm: Double = 0.0
    public var highestAscentMeters: Double = 0.0
    public var fastestSpeedKmh: Double = 0.0
    public var longestTimeSeconds: TimeInterval = 0.0
    public var fastestAvgSpeedKmh: Double = 0.0
    
    public init(
        totalRides: Int = 0,
        totalDistanceKm: Double = 0.0,
        totalAscentMeters: Double = 0.0,
        totalDurationSeconds: TimeInterval = 0.0,
        longestDistanceKm: Double = 0.0,
        highestAscentMeters: Double = 0.0,
        fastestSpeedKmh: Double = 0.0,
        longestTimeSeconds: TimeInterval = 0.0,
        fastestAvgSpeedKmh: Double = 0.0
    ) {
        self.totalRides = totalRides
        self.totalDistanceKm = totalDistanceKm
        self.totalAscentMeters = totalAscentMeters
        self.totalDurationSeconds = totalDurationSeconds
        self.longestDistanceKm = longestDistanceKm
        self.highestAscentMeters = highestAscentMeters
        self.fastestSpeedKmh = fastestSpeedKmh
        self.longestTimeSeconds = longestTimeSeconds
        self.fastestAvgSpeedKmh = fastestAvgSpeedKmh
    }
}

// MARK: - Saved User Activity (Strava-style Activity Record)
public struct SavedActivity: Identifiable, Codable, Equatable {
    public var id: UUID
    public var title: String
    public var note: String
    public var date: Date
    public var track: GPXTrack
    public var distanceKm: Double
    public var durationSeconds: TimeInterval // 總時間 (包含紅綠燈與休息)
    public var movingDurationSeconds: TimeInterval? // 運動時間 (扣除自動暫停)
    public var avgSpeedKmh: Double
    public var maxSpeedKmh: Double
    public var totalAscentMeters: Double
    public var avgHeartRateBpm: Int?
    public var avgCadenceRpm: Int?
    public var photoDataList: [Data]
    public var segmentEfforts: [SegmentEffort]
    
    // 最近刪除與 3 個月 (90天) 永久刪除機制
    public var isDeleted: Bool = false
    public var deletedAt: Date? = nil
    
    public var remainingDaysBeforePermanentDelete: Int {
        guard let delDate = deletedAt else { return 90 }
        let elapsed = Date().timeIntervalSince(delDate)
        let totalSeconds = 90.0 * 86400.0
        return max(0, Int(ceil((totalSeconds - elapsed) / 86400.0)))
    }
    
    public var isExpiredForPermanentDelete: Bool {
        guard let delDate = deletedAt else { return false }
        return Date().timeIntervalSince(delDate) >= (90.0 * 86400.0)
    }
    
    public var effectiveMovingDuration: TimeInterval {
        if let moving = movingDurationSeconds, moving > 0 {
            return moving
        }
        return durationSeconds
    }
    
    public init(
        id: UUID = UUID(),
        title: String,
        note: String = "",
        date: Date = Date(),
        track: GPXTrack,
        distanceKm: Double,
        durationSeconds: TimeInterval,
        movingDurationSeconds: TimeInterval? = nil,
        avgSpeedKmh: Double,
        maxSpeedKmh: Double,
        totalAscentMeters: Double,
        avgHeartRateBpm: Int? = nil,
        avgCadenceRpm: Int? = nil,
        photoDataList: [Data] = [],
        segmentEfforts: [SegmentEffort] = [],
        isDeleted: Bool = false,
        deletedAt: Date? = nil
    ) {
        self.id = id
        self.title = title
        self.note = note
        self.date = date
        self.track = track
        self.distanceKm = distanceKm
        self.durationSeconds = durationSeconds
        self.movingDurationSeconds = movingDurationSeconds ?? durationSeconds
        self.avgSpeedKmh = avgSpeedKmh
        self.maxSpeedKmh = maxSpeedKmh
        self.totalAscentMeters = totalAscentMeters
        self.avgHeartRateBpm = avgHeartRateBpm
        self.avgCadenceRpm = avgCadenceRpm
        self.photoDataList = photoDataList
        self.segmentEfforts = segmentEfforts
        self.isDeleted = isDeleted
        self.deletedAt = deletedAt
    }
    
    enum CodingKeys: String, CodingKey {
        case id, title, note, date, track, distanceKm, durationSeconds, movingDurationSeconds
        case avgSpeedKmh, maxSpeedKmh, totalAscentMeters, avgHeartRateBpm, avgCadenceRpm
        case photoDataList, segmentEfforts, isDeleted, deletedAt
    }
    
    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.id = try container.decodeIfPresent(UUID.self, forKey: .id) ?? UUID()
        self.title = try container.decode(String.self, forKey: .title)
        self.note = try container.decodeIfPresent(String.self, forKey: .note) ?? ""
        self.date = try container.decode(Date.self, forKey: .date)
        self.track = try container.decode(GPXTrack.self, forKey: .track)
        self.distanceKm = try container.decode(Double.self, forKey: .distanceKm)
        self.durationSeconds = try container.decode(TimeInterval.self, forKey: .durationSeconds)
        self.movingDurationSeconds = try container.decodeIfPresent(TimeInterval.self, forKey: .movingDurationSeconds)
        self.avgSpeedKmh = try container.decode(Double.self, forKey: .avgSpeedKmh)
        self.maxSpeedKmh = try container.decode(Double.self, forKey: .maxSpeedKmh)
        self.totalAscentMeters = try container.decode(Double.self, forKey: .totalAscentMeters)
        self.avgHeartRateBpm = try container.decodeIfPresent(Int.self, forKey: .avgHeartRateBpm)
        self.avgCadenceRpm = try container.decodeIfPresent(Int.self, forKey: .avgCadenceRpm)
        self.photoDataList = try container.decodeIfPresent([Data].self, forKey: .photoDataList) ?? []
        self.segmentEfforts = try container.decodeIfPresent([SegmentEffort].self, forKey: .segmentEfforts) ?? []
        self.isDeleted = try container.decodeIfPresent(Bool.self, forKey: .isDeleted) ?? false
        self.deletedAt = try container.decodeIfPresent(Date.self, forKey: .deletedAt)
    }
}

// MARK: - Standard GPX File Generation Extension (100% Strava, Velodash, Garmin 相容)
extension GPXTrack {
    public func toGPXString() -> String {
        let isoFormatter = ISO8601DateFormatter()
        let trkName = title.isEmpty ? "Activity_Track" : title.replacingOccurrences(of: "<", with: "").replacingOccurrences(of: ">", with: "")
        var xml = """
        <?xml version="1.0" encoding="UTF-8"?>
        <gpx version="1.1" creator="VeloDice 騎跡" xmlns="http://www.topografix.com/GPX/1/1" xmlns:gpxtpx="http://www.garmin.com/xmlschemas/TrackPointExtension/v1">
          <metadata>
            <name>\(trkName)</name>
            <time>\(isoFormatter.string(from: Date()))</time>
          </metadata>\n
        """
        for wpt in waypoints {
            let wptSafeName = wpt.name.replacingOccurrences(of: "<", with: "").replacingOccurrences(of: ">", with: "")
            xml += """
              <wpt lat="\(String(format: "%.6f", wpt.latitude))" lon="\(String(format: "%.6f", wpt.longitude))">
                <name>\(wptSafeName)</name>
              </wpt>\n
            """
        }
        xml += """
          <trk>
            <name>\(trkName)</name>
            <trkseg>\n
        """
        for pt in points {
            let timeStr = pt.timestamp.map { isoFormatter.string(from: $0) } ?? isoFormatter.string(from: Date())
            xml += "      <trkpt lat=\"\(String(format: "%.6f", pt.latitude))\" lon=\"\(String(format: "%.6f", pt.longitude))\">\n"
            xml += "        <ele>\(String(format: "%.1f", pt.elevation))</ele>\n"
            xml += "        <time>\(timeStr)</time>\n"
            if let spd = pt.speedKmh {
                xml += "        <speed>\(String(format: "%.2f", spd / 3.6))</speed>\n"
            }
            if pt.heartRate != nil || pt.cadence != nil {
                xml += "        <extensions>\n          <gpxtpx:TrackPointExtension>\n"
                if let hr = pt.heartRate {
                    xml += "            <gpxtpx:hr>\(hr)</gpxtpx:hr>\n"
                }
                if let cad = pt.cadence {
                    xml += "            <gpxtpx:cad>\(cad)</gpxtpx:cad>\n"
                }
                xml += "          </gpxtpx:TrackPointExtension>\n        </extensions>\n"
            }
            xml += "      </trkpt>\n"
        }
        xml += """
            </trkseg>
          </trk>
        </gpx>
        """
        return xml
    }
}

// MARK: - Native GPX Parser (支援匯入 Velodash、Strava、Garmin、Apple Watch 等過往 GPX 紀錄)
public class GPXParser: NSObject, XMLParserDelegate {
    private var points: [RoutePoint] = []
    private var currentLat: Double = 0.0
    private var currentLon: Double = 0.0
    private var currentEle: Double = 0.0
    private var currentTime: Date?
    private var currentSpeed: Double?
    private var currentHR: Int?
    private var currentCad: Int?
    private var trackTitle: String = ""
    private var metadataTitle: String = ""
    private var isInsideTrk = false
    private var isInsideMetadata = false
    private var isInsidePoint = false
    private var textBuffer = ""
    
    // 多格式相容時間解析器 (支援 Velodash/Garmin 毫秒、標準 ISO8601 與時區)
    private static let isoFormatterFractional: ISO8601DateFormatter = {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return f
    }()
    
    private static let isoFormatterStandard: ISO8601DateFormatter = {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime]
        return f
    }()
    
    private static let fallbackDateFormatter: DateFormatter = {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.dateFormat = "yyyy-MM-dd'T'HH:mm:ssZZZZZ"
        return f
    }()
    
    private static let fallbackDateFormatterNoZone: DateFormatter = {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.dateFormat = "yyyy-MM-dd'T'HH:mm:ss"
        return f
    }()
    
    private func parseDate(_ string: String) -> Date? {
        let trimmed = string.trimmingCharacters(in: .whitespacesAndNewlines)
        if let d = Self.isoFormatterFractional.date(from: trimmed) { return d }
        if let d = Self.isoFormatterStandard.date(from: trimmed) { return d }
        if let d = Self.fallbackDateFormatter.date(from: trimmed) { return d }
        if let d = Self.fallbackDateFormatterNoZone.date(from: trimmed) { return d }
        return nil
    }
    
    public static func parse(data: Data) -> GPXTrack? {
        let parser = GPXParser()
        let xmlParser = XMLParser(data: data)
        xmlParser.delegate = parser
        if xmlParser.parse() && !parser.points.isEmpty {
            let finalTitle = !parser.trackTitle.isEmpty ? parser.trackTitle : (!parser.metadataTitle.isEmpty ? parser.metadataTitle : "已匯入活動紀錄")
            return GPXTrack(title: finalTitle, points: parser.points)
        }
        return nil
    }
    
    public func parser(_ parser: XMLParser, didStartElement elementName: String, namespaceURI: String?, qualifiedName qName: String?, attributes attributeDict: [String : String] = [:]) {
        textBuffer = ""
        let lower = elementName.lowercased()
        
        if lower == "trk" {
            isInsideTrk = true
        } else if lower == "metadata" {
            isInsideMetadata = true
        } else if lower == "trkpt" || lower == "rtept" || lower.hasSuffix(":trkpt") || lower.hasSuffix(":rtept") {
            isInsidePoint = true
            let latStr = attributeDict["lat"] ?? attributeDict["latitude"] ?? ""
            let lonStr = attributeDict["lon"] ?? attributeDict["lng"] ?? attributeDict["longitude"] ?? ""
            currentLat = Double(latStr.replacingOccurrences(of: ",", with: ".")) ?? 0.0
            currentLon = Double(lonStr.replacingOccurrences(of: ",", with: ".")) ?? 0.0
            currentEle = 0.0
            currentTime = nil
            currentSpeed = nil
            currentHR = nil
            currentCad = nil
        }
    }
    
    public func parser(_ parser: XMLParser, foundCharacters string: String) {
        textBuffer += string
    }
    
    public func parser(_ parser: XMLParser, didEndElement elementName: String, namespaceURI: String?, qualifiedName qName: String?) {
        let trimmed = textBuffer.trimmingCharacters(in: .whitespacesAndNewlines)
        let lower = elementName.lowercased()
        
        if lower == "name" {
            if isInsideTrk && trackTitle.isEmpty && !trimmed.isEmpty {
                trackTitle = trimmed
            } else if isInsideMetadata && metadataTitle.isEmpty && !trimmed.isEmpty {
                metadataTitle = trimmed
            }
        } else if lower == "trk" {
            isInsideTrk = false
        } else if lower == "metadata" {
            isInsideMetadata = false
        } else if isInsidePoint {
            if lower == "ele" || lower.hasSuffix(":ele") {
                let cleanStr = trimmed.replacingOccurrences(of: ",", with: ".")
                currentEle = Double(cleanStr) ?? 0.0
            } else if lower == "time" || lower.hasSuffix(":time") {
                if let parsed = parseDate(trimmed) {
                    currentTime = parsed
                }
            } else if lower == "speed" || lower.hasSuffix(":speed") {
                let cleanStr = trimmed.replacingOccurrences(of: ",", with: ".")
                if let ms = Double(cleanStr) {
                    currentSpeed = ms <= 40.0 ? (ms * 3.6) : ms
                }
            } else if lower.hasSuffix("hr") || lower.hasSuffix(":hr") || lower == "heartrate" || lower.hasSuffix(":heartrate") {
                let cleanStr = trimmed.replacingOccurrences(of: ",", with: ".")
                if let d = Double(cleanStr) {
                    currentHR = Int(d)
                }
            } else if lower.hasSuffix("cad") || lower.hasSuffix(":cad") || lower == "cadence" || lower.hasSuffix(":cadence") {
                let cleanStr = trimmed.replacingOccurrences(of: ",", with: ".")
                if let d = Double(cleanStr) {
                    currentCad = Int(d)
                }
            } else if lower == "trkpt" || lower == "rtept" || lower.hasSuffix(":trkpt") || lower.hasSuffix(":rtept") {
                if abs(currentLat) > 0.01 && abs(currentLon) > 0.01 {
                    let pt = RoutePoint(
                        latitude: currentLat,
                        longitude: currentLon,
                        elevation: currentEle,
                        timestamp: currentTime,
                        heartRate: currentHR,
                        cadence: currentCad,
                        speedKmh: currentSpeed
                    )
                    points.append(pt)
                }
                isInsidePoint = false
            }
        }
    }
}

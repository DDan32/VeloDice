import Foundation
import SwiftUI
import Combine

@MainActor
public class ActivityStore: ObservableObject {
    public static let shared = ActivityStore()
    
    @Published public var activities: [SavedActivity] = []
    @Published public var segments: [SegmentRecord] = []
    @Published public var lastDeletedSegment: SegmentRecord? = nil
    
    private let activitiesFileName = "saved_activities_v1.json"
    private let segmentsFileName = "saved_segments_v1.json"
    
    public init() {
        loadActivities()
        loadSegments()
        recalculateAllSegmentPRs()
    }
    
    private var activitiesFileURL: URL {
        let docs = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        return docs.appendingPathComponent(activitiesFileName)
    }
    
    private var segmentsFileURL: URL {
        let docs = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        return docs.appendingPathComponent(segmentsFileName)
    }
    
    // MARK: - Strava-style Career All-Time Records (歷年最高、最長、最快)
    public var careerStats: CareerAllTimeStats {
        guard !activities.isEmpty else {
            return CareerAllTimeStats()
        }
        
        let totalRides = activities.count
        let totalDist = activities.reduce(0.0) { $0 + $1.distanceKm }
        let totalAscent = activities.reduce(0.0) { $0 + $1.totalAscentMeters }
        let totalDuration = activities.reduce(0.0) { $0 + $1.durationSeconds }
        
        let longestDist = activities.map(\.distanceKm).max() ?? 0.0
        let highestAscent = activities.map(\.totalAscentMeters).max() ?? 0.0
        let fastestSpeed = activities.map(\.maxSpeedKmh).max() ?? 0.0
        let longestDuration = activities.map(\.durationSeconds).max() ?? 0.0
        
        // 最快平均時速 (門檻：需大於等於 5 公里，避免原地或短距離造成虛高)
        let meaningfulActivities = activities.filter { $0.distanceKm >= 5.0 }
        let fastestAvgSpeed = meaningfulActivities.map(\.avgSpeedKmh).max() ?? (activities.map(\.avgSpeedKmh).max() ?? 0.0)
        
        return CareerAllTimeStats(
            totalRides: totalRides,
            totalDistanceKm: totalDist,
            totalAscentMeters: totalAscent,
            totalDurationSeconds: totalDuration,
            longestDistanceKm: longestDist,
            highestAscentMeters: highestAscent,
            fastestSpeedKmh: fastestSpeed,
            longestTimeSeconds: longestDuration,
            fastestAvgSpeedKmh: fastestAvgSpeed
        )
    }
    
    // MARK: - Activity Management
    public func loadActivities() {
        guard FileManager.default.fileExists(atPath: activitiesFileURL.path) else { return }
        do {
            let data = try Data(contentsOf: activitiesFileURL)
            let decoded = try JSONDecoder().decode([SavedActivity].self, from: data)
            self.activities = decoded.sorted(by: { $0.date > $1.date })
        } catch {
            print("Failed to load activities: \(error)")
        }
    }
    
    public func saveActivity(_ activity: SavedActivity) {
        var mutableActivity = activity
        
        // 自動比對本次運動是否經過現有路段並評估是否破 PR
        let matchedEfforts = evaluateSegmentEfforts(for: mutableActivity)
        mutableActivity.segmentEfforts = matchedEfforts
        
        self.activities.insert(mutableActivity, at: 0)
        persistActivities()
        persistSegments()
    }
    
    public func deleteActivity(at offsets: IndexSet) {
        self.activities.remove(atOffsets: offsets)
        persistActivities()
        recalculateAllSegmentPRs()
    }
    
    public func deleteActivity(id: UUID) {
        self.activities.removeAll(where: { $0.id == id })
        persistActivities()
        recalculateAllSegmentPRs()
    }
    
    private func persistActivities() {
        do {
            let data = try JSONEncoder().encode(self.activities)
            try data.write(to: activitiesFileURL, options: [.atomic])
        } catch {
            print("Failed to persist activities: \(error)")
        }
    }
    
    // MARK: - Segment Management & Personal Records (PR)
    public func loadSegments() {
        if FileManager.default.fileExists(atPath: segmentsFileURL.path) {
            do {
                let data = try Data(contentsOf: segmentsFileURL)
                let decoded = try JSONDecoder().decode([SegmentRecord].self, from: data)
                self.segments = decoded
                return
            } catch {
                print("Failed to load custom segments: \(error)")
            }
        }
        
        // 預設經典自行車挑戰路段
        self.segments = defaultClassicSegments()
        persistSegments()
    }
    
    // MARK: - Default Classic Segments (經典爬坡路段)
    public func defaultClassicSegments() -> [SegmentRecord] {
        return [
            SegmentRecord(
                name: "風櫃嘴經典計時賽段 (楓林橋至涼亭)",
                startCoordinate: RoutePoint(latitude: 25.1182, longitude: 121.5794, elevation: 185.0),
                endCoordinate: RoutePoint(latitude: 25.1378, longitude: 121.6012, elevation: 597.0),
                distanceKm: 6.4,
                elevationGainMeters: 412.0,
                avgGradientPercent: 6.4,
                personalRecordSeconds: nil,
                latestAttemptSeconds: nil,
                attemptCount: 0
            ),
            SegmentRecord(
                name: "冷水坑爬坡挑戰 (平等里至遊客中心)",
                startCoordinate: RoutePoint(latitude: 25.1311, longitude: 121.5742, elevation: 380.0),
                endCoordinate: RoutePoint(latitude: 25.1662, longitude: 121.5629, elevation: 740.0),
                distanceKm: 7.8,
                elevationGainMeters: 360.0,
                avgGradientPercent: 4.6,
                personalRecordSeconds: nil,
                latestAttemptSeconds: nil,
                attemptCount: 0
            ),
            SegmentRecord(
                name: "中社路晨練計時段 (雙溪橋至公車迴轉道)",
                startCoordinate: RoutePoint(latitude: 25.1054, longitude: 121.5631, elevation: 65.0),
                endCoordinate: RoutePoint(latitude: 25.1190, longitude: 121.5833, elevation: 315.0),
                distanceKm: 4.1,
                elevationGainMeters: 250.0,
                avgGradientPercent: 6.1,
                personalRecordSeconds: nil,
                latestAttemptSeconds: nil,
                attemptCount: 0
            ),
            SegmentRecord(
                name: "巴拉卡公路景觀爬坡段 (興華派出所至二子坪)",
                startCoordinate: RoutePoint(latitude: 25.1952, longitude: 121.5034, elevation: 160.0),
                endCoordinate: RoutePoint(latitude: 25.1856, longitude: 121.5248, elevation: 840.0),
                distanceKm: 10.2,
                elevationGainMeters: 680.0,
                avgGradientPercent: 6.7,
                personalRecordSeconds: nil,
                latestAttemptSeconds: nil,
                attemptCount: 0
            )
        ]
    }
    
    public func addCustomSegment(name: String, distanceKm: Double, elevationGain: Double, avgGradient: Double) {
        let seg = SegmentRecord(
            name: name,
            startCoordinate: RoutePoint(latitude: 25.033, longitude: 121.565, elevation: 20),
            endCoordinate: RoutePoint(latitude: 25.040, longitude: 121.570, elevation: 20 + elevationGain),
            distanceKm: distanceKm,
            elevationGainMeters: elevationGain,
            avgGradientPercent: avgGradient,
            personalRecordSeconds: nil,
            latestAttemptSeconds: nil,
            attemptCount: 0
        )
        self.segments.append(seg)
        persistSegments()
        recalculateAllSegmentPRs()
    }
    
    // MARK: - Delete & Restore Segments (支援刪除、復原與還原預設)
    @discardableResult
    public func deleteSegment(id: UUID) -> SegmentRecord? {
        guard let idx = segments.firstIndex(where: { $0.id == id }) else { return nil }
        let removed = segments.remove(at: idx)
        self.lastDeletedSegment = removed
        
        // 清理活動中對此路段的歷史 effort
        for i in 0..<activities.count {
            activities[i].segmentEfforts.removeAll(where: { $0.segmentId == id })
        }
        persistActivities()
        persistSegments()
        return removed
    }
    
    public func deleteSegment(at offsets: IndexSet) {
        for idx in offsets {
            if segments.indices.contains(idx) {
                let id = segments[idx].id
                deleteSegment(id: id)
            }
        }
    }
    
    @discardableResult
    public func undoLastDeletedSegment() -> SegmentRecord? {
        guard let restored = lastDeletedSegment else { return nil }
        self.segments.append(restored)
        self.lastDeletedSegment = nil
        persistSegments()
        recalculateAllSegmentPRs()
        return restored
    }
    
    @discardableResult
    public func restoreDefaultSegments() -> Int {
        let defaults = defaultClassicSegments()
        var restoredCount = 0
        for d in defaults {
            if !segments.contains(where: { $0.name == d.name }) {
                segments.append(d)
                restoredCount += 1
            }
        }
        if restoredCount > 0 {
            persistSegments()
            recalculateAllSegmentPRs()
        }
        return restoredCount
    }
    
    private func persistSegments() {
        do {
            let data = try JSONEncoder().encode(self.segments)
            try data.write(to: segmentsFileURL, options: [.atomic])
        } catch {
            print("Failed to persist segments: \(error)")
        }
    }
    
    // MARK: - Auto Segment Matching & PR Computation (真實 GPS 空間幾何比對)
    public func evaluateSegmentEfforts(for activity: SavedActivity) -> [SegmentEffort] {
        let pts = activity.track.points
        guard pts.count >= 5, activity.distanceKm >= 0.2 else { return [] }
        
        var efforts: [SegmentEffort] = []
        
        for i in 0..<segments.count {
            let seg = segments[i]
            let startCoord = CLLocation(latitude: seg.startCoordinate.latitude, longitude: seg.startCoordinate.longitude)
            let endCoord = CLLocation(latitude: seg.endCoordinate.latitude, longitude: seg.endCoordinate.longitude)
            
            // 1. 尋找活動軌跡中，最接近路段起點的座標點 (判定門檻放寬至 200 公尺，相容各品牌車錶抽樣頻率與衛星誤差)
            var bestStartIndex: Int? = nil
            var minStartDist = 200.0
            for (idx, pt) in pts.enumerated() {
                let loc = CLLocation(latitude: pt.latitude, longitude: pt.longitude)
                let d = loc.distance(from: startCoord)
                if d < minStartDist {
                    minStartDist = d
                    bestStartIndex = idx
                }
            }
            
            guard let sIdx = bestStartIndex else { continue }
            
            // 2. 從通過起點後的座標中，尋找最接近路段終點的座標點 (判定門檻: 200 公尺內)
            var bestEndIndex: Int? = nil
            var minEndDist = 200.0
            for idx in (sIdx + 1)..<pts.count {
                let loc = CLLocation(latitude: pts[idx].latitude, longitude: pts[idx].longitude)
                let d = loc.distance(from: endCoord)
                if d < minEndDist {
                    minEndDist = d
                    bestEndIndex = idx
                }
            }
            
            guard let eIdx = bestEndIndex, eIdx > sIdx else { continue }
            
            // 3. 計算活動在起點與終點之間的實際騎行里程
            var actualEffortDistKm = 0.0
            for k in sIdx..<eIdx {
                let p1 = CLLocation(latitude: pts[k].latitude, longitude: pts[k].longitude)
                let p2 = CLLocation(latitude: pts[k+1].latitude, longitude: pts[k+1].longitude)
                actualEffortDistKm += p1.distance(from: p2) / 1000.0
            }
            
            // 4. 幾何距離驗證：實際騎行距離落在路段標準里程的 55% ~ 160% 範圍內
            let lowerBound = seg.distanceKm * 0.55
            let upperBound = seg.distanceKm * 1.60
            guard actualEffortDistKm >= lowerBound && actualEffortDistKm <= upperBound else { continue }
            
            // 5. 計算通過該路段所耗費的真實秒數
            var effortDuration: TimeInterval = 0
            if let tStart = pts[sIdx].timestamp, let tEnd = pts[eIdx].timestamp {
                effortDuration = max(1.0, tEnd.timeIntervalSince(tStart))
            } else {
                let fallbackSpeed = max(8.0, activity.avgSpeedKmh)
                effortDuration = max(1.0, (actualEffortDistKm / fallbackSpeed) * 3600.0)
            }
            
            // 速度合規性檢查 (避免瞬移或不合理過慢停滯)
            let effortSpeed = actualEffortDistKm / (effortDuration / 3600.0)
            guard effortSpeed >= 2.0 && effortSpeed <= 90.0 else { continue }
            
            // 6. 計算該路段內的真實累積爬升
            var segAscent = 0.0
            for k in sIdx..<eIdx {
                let diff = pts[k+1].elevation - pts[k].elevation
                if diff > 0.5 { segAscent += diff }
            }
            let effortAscent = segAscent > 0 ? segAscent : seg.elevationGainMeters
            
            // 7. PR 紀錄更新判定
            var isNewPR = false
            if let currentPR = seg.personalRecordSeconds {
                if effortDuration < currentPR {
                    isNewPR = true
                    segments[i].personalRecordSeconds = effortDuration
                }
            } else {
                isNewPR = true
                segments[i].personalRecordSeconds = effortDuration
            }
            
            segments[i].latestAttemptSeconds = effortDuration
            segments[i].attemptCount += 1
            
            let effort = SegmentEffort(
                segmentId: seg.id,
                segmentName: seg.name,
                distanceKm: actualEffortDistKm,
                elevationGainMeters: effortAscent,
                avgGradientPercent: seg.avgGradientPercent,
                timeSeconds: effortDuration,
                avgSpeedKmh: effortSpeed,
                date: activity.date,
                isPR: isNewPR
            )
            efforts.append(effort)
        }
        
        return efforts
    }
    
    // MARK: - Recalculate All Segment PRs (清除錯誤幽靈紀錄並重新比對所有活動)
    public struct RecalculateReport {
        public let scannedActivities: Int
        public let matchedSegmentsCount: Int
        public let newPRCount: Int
        public let matchedDetails: [String]
        public let message: String
    }
    
    @discardableResult
    public func recalculateAllSegmentPRs() -> RecalculateReport {
        // 重設所有路段挑戰紀錄為乾淨狀態
        for i in 0..<segments.count {
            segments[i].personalRecordSeconds = nil
            segments[i].latestAttemptSeconds = nil
            segments[i].attemptCount = 0
        }
        
        // 依日期由舊至新排序重新比對，精準重現真實 PR 推進軌跡
        let sortedActivities = activities.sorted(by: { $0.date < $1.date })
        var totalMatched = 0
        var totalPRs = 0
        var details: [String] = []
        
        for activity in sortedActivities {
            let matched = evaluateSegmentEfforts(for: activity)
            if let actIdx = activities.firstIndex(where: { $0.id == activity.id }) {
                activities[actIdx].segmentEfforts = matched
            }
            for effort in matched {
                totalMatched += 1
                if effort.isPR {
                    totalPRs += 1
                    let mins = Int(effort.timeSeconds) / 60
                    let secs = Int(effort.timeSeconds) % 60
                    details.append("🏆 \(effort.segmentName)：\(String(format: "%02d:%02d", mins, secs)) (\(String(format: "%.1f", effort.avgSpeedKmh)) km/h)")
                }
            }
        }
        
        persistActivities()
        persistSegments()
        
        let msg: String
        if totalMatched > 0 {
            msg = "🎉 路段校正完成！\n\n已掃描 \(activities.count) 筆歷史運動紀錄，成功比對出 \(totalMatched) 次路段挑戰，目前榮獲 \(totalPRs) 項路段最佳 (PR)！\n\n\(details.joined(separator: "\n"))"
        } else {
            msg = "ℹ️ 路段校正完成\n\n已掃描 \(activities.count) 筆歷史運動紀錄。\n目前未偵測到與系統預設經典路段（風櫃嘴、冷水坑、中社路、巴拉卡）重合之軌跡。\n\n💡 提示：若您的騎行紀錄位於其他山路或自選路線，您可在該活動詳情中點選「以此活動建立挑戰路段」，系統會自動提取起終點與坡度並即時計算個人 PR！"
        }
        
        return RecalculateReport(
            scannedActivities: activities.count,
            matchedSegmentsCount: totalMatched,
            newPRCount: totalPRs,
            matchedDetails: details,
            message: msg
        )
    }
    
    // MARK: - Create Custom Segment directly from a Saved Activity
    @discardableResult
    public func createSegment(from activity: SavedActivity, customName: String? = nil) -> SegmentRecord? {
        guard let first = activity.track.points.first, let last = activity.track.points.last, activity.distanceKm >= 0.2 else {
            return nil
        }
        
        let segTitle = (customName?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false)
            ? customName!
            : "\(activity.title) 挑戰段"
        
        let newSeg = SegmentRecord(
            name: segTitle,
            startCoordinate: first,
            endCoordinate: last,
            distanceKm: activity.distanceKm,
            elevationGainMeters: activity.totalAscentMeters,
            avgGradientPercent: activity.track.avgGradientPercent,
            personalRecordSeconds: activity.effectiveMovingDuration,
            latestAttemptSeconds: activity.effectiveMovingDuration,
            attemptCount: 1
        )
        
        self.segments.append(newSeg)
        persistSegments()
        recalculateAllSegmentPRs()
        return newSeg
    }
    
    // MARK: - Import Past Activity Records from GPX File (支援從 Velodash / Strava / Garmin 匯入)
    @discardableResult
    public func importActivityFromGPX(url: URL) throws -> SavedActivity {
        let shouldStopAccess = url.startAccessingSecurityScopedResource()
        defer {
            if shouldStopAccess {
                url.stopAccessingSecurityScopedResource()
            }
        }
        
        let data = try Data(contentsOf: url)
        guard let track = GPXParser.parse(data: data), !track.points.isEmpty else {
            throw NSError(domain: "GPXImportError", code: -1, userInfo: [NSLocalizedDescriptionKey: "無法解析此 GPX 檔案或檔案中沒有座標軌跡點。"])
        }
        
        let fallbackName = url.deletingPathExtension().lastPathComponent
        let title = (track.title.isEmpty || track.title == "已匯入活動紀錄") ? fallbackName : track.title
        let date = track.points.first?.timestamp ?? Date()
        
        var totalElapsed: TimeInterval = 0
        var movingTime: TimeInterval = 0
        var maxSpeed: Double = 0.0
        
        let pts = track.points
        if pts.count > 1 {
            // 1. 計算總時間 (以首尾有效時間戳為準)
            if let firstTime = pts.first?.timestamp, let lastTime = pts.last?.timestamp {
                totalElapsed = max(1.0, lastTime.timeIntervalSince(firstTime))
            }
            
            // 2. 計算動態運動時間 (Moving Time) 與最高時速 (濾除紅綠燈與休息長時間停等)
            for i in 1..<pts.count {
                let p1 = pts[i-1]
                let p2 = pts[i]
                let loc1 = CLLocation(latitude: p1.latitude, longitude: p1.longitude)
                let loc2 = CLLocation(latitude: p2.latitude, longitude: p2.longitude)
                let distM = loc1.distance(from: loc2)
                
                var dt: TimeInterval = 1.0
                var hasValidDt = false
                if let t1 = p1.timestamp, let t2 = p2.timestamp {
                    let diff = t2.timeIntervalSince(t1)
                    if diff > 0.05 {
                        dt = diff
                        hasValidDt = true
                    }
                }
                
                // 計算單點瞬時速度
                var ptSpeedKmh: Double = 0.0
                if let spd = p2.speedKmh, spd > 0 {
                    ptSpeedKmh = spd
                } else if hasValidDt && dt < 60.0 {
                    ptSpeedKmh = (distM / dt) * 3.6
                }
                
                // 排除 > 95 km/h 的 GPS 瞬間漂移假訊號
                if ptSpeedKmh > 0 && ptSpeedKmh <= 95.0 {
                    if ptSpeedKmh > maxSpeed {
                        maxSpeed = ptSpeedKmh
                    }
                }
                
                // 動態時間累加：速度 >= 1.8 km/h 且時間間隔小於 35 秒 (排除長時間停等紅綠燈或休息)
                if hasValidDt {
                    if dt <= 35.0 && (ptSpeedKmh >= 1.8 || distM >= 3.0) {
                        movingTime += dt
                    }
                } else {
                    if distM >= 2.5 {
                        movingTime += 1.0
                    }
                }
            }
        }
        
        // 若完全缺少時間戳，則採用真實平均時速合理推算
        if totalElapsed <= 0 {
            totalElapsed = max(60.0, (track.totalDistanceKm / 22.0) * 3600.0)
        }
        if movingTime <= 0 || movingTime > totalElapsed {
            movingTime = totalElapsed
        }
        
        let effectiveMovingDuration = max(1.0, movingTime)
        let avgSpeed = track.totalDistanceKm / (effectiveMovingDuration / 3600.0)
        
        let hrPoints = track.points.compactMap(\.heartRate).filter { $0 >= 40 && $0 <= 230 }
        let avgHR = hrPoints.isEmpty ? nil : Int(hrPoints.reduce(0, +) / hrPoints.count)
        let cadPoints = track.points.compactMap(\.cadence).filter { $0 > 0 && $0 <= 200 }
        let avgCad = cadPoints.isEmpty ? nil : Int(cadPoints.reduce(0, +) / cadPoints.count)
        
        let importedActivity = SavedActivity(
            title: title,
            note: "從外部 GPX 軌跡匯入 (已精準校正數據與高程)",
            date: date,
            track: track,
            distanceKm: track.totalDistanceKm,
            durationSeconds: totalElapsed,
            movingDurationSeconds: movingTime,
            avgSpeedKmh: avgSpeed,
            maxSpeedKmh: maxSpeed > 0 ? maxSpeed : avgSpeed * 1.3,
            totalAscentMeters: track.totalAscentMeters,
            avgHeartRateBpm: avgHR,
            avgCadenceRpm: avgCad,
            photoDataList: []
        )
        
        self.saveActivity(importedActivity)
        return importedActivity
    }
    
    // MARK: - GPX File Export Utility
    public func exportGPXFile(for activity: SavedActivity) -> URL? {
        let gpxString = activity.track.toGPXString()
        let safeTitle = activity.title
            .replacingOccurrences(of: " ", with: "_")
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: ":", with: "-")
        let fileName = "\(safeTitle).gpx"
        let tempURL = FileManager.default.temporaryDirectory.appendingPathComponent(fileName)
        
        do {
            try gpxString.write(to: tempURL, atomically: true, encoding: .utf8)
            return tempURL
        } catch {
            print("Failed to write GPX export file: \(error)")
            return nil
        }
    }
}

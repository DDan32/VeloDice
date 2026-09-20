import Foundation
import SwiftUI
import Combine
import CoreLocation

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
        cleanupExpiredDeletedItems()
    }
    
    private var activitiesFileURL: URL {
        let docs = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        return docs.appendingPathComponent(activitiesFileName)
    }
    
    private var segmentsFileURL: URL {
        let docs = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        return docs.appendingPathComponent(segmentsFileName)
    }
    
    // MARK: - Filtered Active and Recently Deleted Items
    public var activeActivities: [SavedActivity] {
        activities.filter { !$0.isDeleted }
    }
    
    public var deletedActivities: [SavedActivity] {
        activities.filter { $0.isDeleted }.sorted(by: { ($0.deletedAt ?? Date()) > ($1.deletedAt ?? Date()) })
    }
    
    public var activeSegments: [SegmentRecord] {
        segments.filter { !$0.isDeleted }
    }
    
    public var deletedSegments: [SegmentRecord] {
        segments.filter { $0.isDeleted }.sorted(by: { ($0.deletedAt ?? Date()) > ($1.deletedAt ?? Date()) })
    }
    
    // MARK: - Strava-style Career All-Time Records (歷年最高、最長、最快 - 僅計入有效未刪除活動)
    public var careerStats: CareerAllTimeStats {
        let validActs = activeActivities
        guard !validActs.isEmpty else {
            return CareerAllTimeStats()
        }
        
        let totalRides = validActs.count
        let totalDist = validActs.reduce(0.0) { $0 + $1.distanceKm }
        let totalAscent = validActs.reduce(0.0) { $0 + $1.totalAscentMeters }
        let totalDuration = validActs.reduce(0.0) { $0 + $1.durationSeconds }
        
        let longestDist = validActs.map(\.distanceKm).max() ?? 0.0
        let highestAscent = validActs.map(\.totalAscentMeters).max() ?? 0.0
        let fastestSpeed = validActs.map(\.maxSpeedKmh).max() ?? 0.0
        let longestDuration = validActs.map(\.durationSeconds).max() ?? 0.0
        
        // 最快平均時速 (門檻：需大於等於 5 公里，避免原地或短距離造成虛高)
        let meaningfulActivities = validActs.filter { $0.distanceKm >= 5.0 }
        let fastestAvgSpeed = meaningfulActivities.map(\.avgSpeedKmh).max() ?? (validActs.map(\.avgSpeedKmh).max() ?? 0.0)
        
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
    
    // MARK: - Activity Management (Soft Delete & Restore & 90 Days Retention)
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
        
        self.activities.removeAll(where: { $0.id == mutableActivity.id })
        self.activities.insert(mutableActivity, at: 0)
        persistActivities()
        
        // 同步更新路段的 PR 記錄
        recalculateAllSegmentPRs()
    }
    
    public func softDeleteActivity(id: UUID) {
        if let idx = activities.firstIndex(where: { $0.id == id }) {
            activities[idx].isDeleted = true
            activities[idx].deletedAt = Date()
            persistActivities()
        }
    }
    
    public func restoreActivity(id: UUID) {
        if let idx = activities.firstIndex(where: { $0.id == id }) {
            activities[idx].isDeleted = false
            activities[idx].deletedAt = nil
            persistActivities()
        }
    }
    
    public func permanentlyDeleteActivity(id: UUID) {
        activities.removeAll(where: { $0.id == id })
        persistActivities()
        recalculateAllSegmentPRs()
    }
    
    public func emptyTrashActivities() {
        activities.removeAll(where: { $0.isDeleted })
        persistActivities()
        recalculateAllSegmentPRs()
    }
    
    public func deleteActivity(at offsets: IndexSet) {
        let currentActive = activeActivities
        for idx in offsets {
            if currentActive.indices.contains(idx) {
                softDeleteActivity(id: currentActive[idx].id)
            }
        }
    }
    
    public func exportGPXFile(for activity: SavedActivity) -> URL? {
        let gpxString = activity.track.toGPXString()
        let cleanTitle = activity.title.replacingOccurrences(of: " ", with: "_").replacingOccurrences(of: "/", with: "_")
        let fileName = "\(cleanTitle)_\(activity.date.formatted(date: .numeric, time: .omitted)).gpx"
        let tempURL = FileManager.default.temporaryDirectory.appendingPathComponent(fileName)
        do {
            try gpxString.write(to: tempURL, atomically: true, encoding: .utf8)
            return tempURL
        } catch {
            print("Failed to export GPX: \(error)")
            return nil
        }
    }
    
    private func persistActivities() {
        do {
            let data = try JSONEncoder().encode(self.activities)
            try data.write(to: activitiesFileURL, options: [.atomic])
        } catch {
            print("Failed to persist activities: \(error)")
        }
    }
    
    // MARK: - Segments Management
    public func loadSegments() {
        if FileManager.default.fileExists(atPath: segmentsFileURL.path) {
            do {
                let data = try Data(contentsOf: segmentsFileURL)
                let decoded = try JSONDecoder().decode([SegmentRecord].self, from: data)
                self.segments = decoded
            } catch {
                print("Failed to load segments: \(error)")
                self.segments = defaultClassicSegments()
            }
        } else {
            self.segments = defaultClassicSegments()
            persistSegments()
        }
        recalculateAllSegmentPRs()
    }
    
    public func defaultClassicSegments() -> [SegmentRecord] {
        [
            SegmentRecord(
                name: "風櫃嘴經典爬坡計時段 (楓林橋至頂點涼亭)",
                startCoordinate: RoutePoint(latitude: 25.1186, longitude: 121.5878, elevation: 180.0),
                endCoordinate: RoutePoint(latitude: 25.1378, longitude: 121.6022, elevation: 597.0),
                distanceKm: 6.4,
                elevationGainMeters: 417.0,
                avgGradientPercent: 6.5,
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
    
    /// 智慧歷史路段探勘：自動從用戶的所有歷史運動活動中，分析高爬升（>75m）、距離適中（1.5km~12km）且具代表性的經典路段，自動加入並計算歷次 PR
    @discardableResult
    public func autoDiscoverSegmentsFromHistory() -> Int {
        var discoveredCount = 0
        let validActs = activeActivities.filter { $0.distanceKm >= 2.0 && $0.track.points.count >= 15 }
        
        for act in validActs {
            let pts = act.track.points
            guard pts.count >= 10 else { continue }
            
            var bestStart = 0
            var bestEnd = pts.count - 1
            var maxGain = 0.0
            
            for i in 0..<(pts.count - 5) {
                let pStart = pts[i]
                for j in (i + 5)..<pts.count {
                    let pEnd = pts[j]
                    let gain = pEnd.elevation - pStart.elevation
                    let dist = CLLocation(latitude: pStart.latitude, longitude: pStart.longitude)
                        .distance(from: CLLocation(latitude: pEnd.latitude, longitude: pEnd.longitude)) / 1000.0
                    
                    if gain >= 75.0 && dist >= 1.5 && dist <= 12.0 {
                        if gain > maxGain {
                            maxGain = gain
                            bestStart = i
                            bestEnd = j
                        }
                    }
                }
            }
            
            if maxGain >= 75.0 {
                let pS = pts[bestStart]
                let pE = pts[bestEnd]
                let dist = max(1.5, CLLocation(latitude: pS.latitude, longitude: pS.longitude)
                    .distance(from: CLLocation(latitude: pE.latitude, longitude: pE.longitude)) / 1000.0)
                let grad = (maxGain / (dist * 1000.0)) * 100.0
                
                // 檢查是否與現存路段重複
                let isDuplicate = segments.contains { seg in
                    let sDist = CLLocation(latitude: seg.startCoordinate.latitude, longitude: seg.startCoordinate.longitude)
                        .distance(from: CLLocation(latitude: pS.latitude, longitude: pS.longitude))
                    let eDist = CLLocation(latitude: seg.endCoordinate.latitude, longitude: seg.endCoordinate.longitude)
                        .distance(from: CLLocation(latitude: pE.latitude, longitude: pE.longitude))
                    return sDist < 400.0 && eDist < 400.0
                }
                
                if !isDuplicate {
                    let segName = "\(act.title) · 經典爬坡挑戰段"
                    let newSeg = SegmentRecord(
                        name: segName,
                        startCoordinate: RoutePoint(latitude: pS.latitude, longitude: pS.longitude, elevation: pS.elevation),
                        endCoordinate: RoutePoint(latitude: pE.latitude, longitude: pE.longitude, elevation: pE.elevation),
                        distanceKm: dist,
                        elevationGainMeters: maxGain,
                        avgGradientPercent: grad,
                        personalRecordSeconds: nil,
                        latestAttemptSeconds: nil,
                        attemptCount: 0
                    )
                    self.segments.append(newSeg)
                    discoveredCount += 1
                }
            }
        }
        
        if discoveredCount > 0 {
            persistSegments()
            recalculateAllSegmentPRs()
        }
        return discoveredCount
    }
    
    // MARK: - Delete & Restore Segments (支援軟刪除移至最近刪除、復原與 3 個月永久刪除)
    /// 軟刪除路段（移至「最近刪除路段」，3 個月內可恢復）
    @discardableResult
    public func softDeleteSegment(id: UUID) -> SegmentRecord? {
        guard let idx = segments.firstIndex(where: { $0.id == id }) else { return nil }
        segments[idx].isDeleted = true
        segments[idx].deletedAt = Date()
        let seg = segments[idx]
        self.lastDeletedSegment = seg
        persistSegments()
        return seg
    }
    
    /// 恢復已刪除的路段
    @discardableResult
    public func restoreSegment(id: UUID) -> SegmentRecord? {
        guard let idx = segments.firstIndex(where: { $0.id == id }) else { return nil }
        segments[idx].isDeleted = false
        segments[idx].deletedAt = nil
        let seg = segments[idx]
        persistSegments()
        return seg
    }
    
    /// 立即永久刪除路段
    public func permanentlyDeleteSegment(id: UUID) {
        segments.removeAll(where: { $0.id == id })
        // 清理活動中對此路段的歷史 effort
        for i in 0..<activities.count {
            activities[i].segmentEfforts.removeAll(where: { $0.segmentId == id })
        }
        persistActivities()
        persistSegments()
    }
    
    /// 清空最近刪除的全部路段
    public func emptyTrashSegments() {
        let deletedIDs = Set(segments.filter { $0.isDeleted }.map { $0.id })
        segments.removeAll(where: { $0.isDeleted })
        for i in 0..<activities.count {
            activities[i].segmentEfforts.removeAll(where: {
                if let sid = $0.segmentId {
                    return deletedIDs.contains(sid)
                }
                return false
            })
        }
        persistActivities()
        persistSegments()
    }
    
    @discardableResult
    public func deleteSegment(id: UUID) -> SegmentRecord? {
        return softDeleteSegment(id: id)
    }
    
    public func deleteSegment(at offsets: IndexSet) {
        let currentActive = activeSegments
        for idx in offsets {
            if currentActive.indices.contains(idx) {
                softDeleteSegment(id: currentActive[idx].id)
            }
        }
    }
    
    @discardableResult
    public func undoLastDeletedSegment() -> SegmentRecord? {
        guard let restored = lastDeletedSegment else { return nil }
        return restoreSegment(id: restored.id)
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
        }
        return restoredCount
    }
    
    // MARK: - 3 個月 (90天) 自動永久清理過期已刪除項目
    public func cleanupExpiredDeletedItems() {
        let beforeActCount = activities.count
        activities.removeAll(where: { $0.isExpiredForPermanentDelete })
        if activities.count != beforeActCount {
            persistActivities()
        }
        
        let beforeSegCount = segments.count
        segments.removeAll(where: { $0.isExpiredForPermanentDelete })
        if segments.count != beforeSegCount {
            persistSegments()
        }
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
            
            var actualEffortDistKm = 0.0
            for k in sIdx..<eIdx {
                let p1 = CLLocation(latitude: pts[k].latitude, longitude: pts[k].longitude)
                let p2 = CLLocation(latitude: pts[k+1].latitude, longitude: pts[k+1].longitude)
                actualEffortDistKm += p1.distance(from: p2) / 1000.0
            }
            
            let lowerBound = seg.distanceKm * 0.55
            let upperBound = seg.distanceKm * 1.60
            guard actualEffortDistKm >= lowerBound && actualEffortDistKm <= upperBound else { continue }
            
            var effortDuration: TimeInterval = 0
            if let tStart = pts[sIdx].timestamp, let tEnd = pts[eIdx].timestamp {
                effortDuration = max(1.0, tEnd.timeIntervalSince(tStart))
            } else {
                let fallbackSpeed = max(8.0, activity.avgSpeedKmh)
                effortDuration = max(1.0, (actualEffortDistKm / fallbackSpeed) * 3600.0)
            }
            
            let effortSpeed = actualEffortDistKm / (effortDuration / 3600.0)
            guard effortSpeed >= 2.0 && effortSpeed <= 90.0 else { continue }
            
            let isNewPR: Bool
            if let existingPR = seg.personalRecordSeconds {
                isNewPR = effortDuration < existingPR
            } else {
                isNewPR = true
            }
            
            let effort = SegmentEffort(
                segmentId: seg.id,
                segmentName: seg.name,
                distanceKm: actualEffortDistKm,
                elevationGainMeters: seg.elevationGainMeters,
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
    
    public func recalculateAllSegmentPRs() {
        let validActs = activeActivities.sorted(by: { $0.date < $1.date })
        
        for i in 0..<segments.count {
            let segId = segments[i].id
            var attempts: [(duration: TimeInterval, date: Date)] = []
            
            for act in validActs {
                for effort in act.segmentEfforts where effort.segmentId == segId {
                    attempts.append((effort.timeSeconds, act.date))
                }
            }
            
            if attempts.isEmpty {
                for act in validActs {
                    let matched = evaluateSegmentEfforts(for: act)
                    for effort in matched where effort.segmentId == segId {
                        attempts.append((effort.timeSeconds, act.date))
                    }
                }
            }
            
            segments[i].attemptCount = attempts.count
            segments[i].latestAttemptSeconds = attempts.last?.duration
            segments[i].personalRecordSeconds = attempts.map(\.duration).min()
        }
        
        persistSegments()
    }
    
    public func createSegment(from activity: SavedActivity) -> SegmentRecord? {
        guard let start = activity.track.points.first,
              let end = activity.track.points.last,
              activity.distanceKm >= 0.3 else { return nil }
        
        let grad = activity.totalAscentMeters > 0 ? (activity.totalAscentMeters / (activity.distanceKm * 1000.0)) * 100.0 : 0.0
        let seg = SegmentRecord(
            name: "\(activity.title) 挑戰段",
            startCoordinate: start,
            endCoordinate: end,
            distanceKm: activity.distanceKm,
            elevationGainMeters: activity.totalAscentMeters,
            avgGradientPercent: grad,
            personalRecordSeconds: activity.effectiveMovingDuration > 0 ? activity.effectiveMovingDuration : activity.durationSeconds,
            latestAttemptSeconds: activity.effectiveMovingDuration > 0 ? activity.effectiveMovingDuration : activity.durationSeconds,
            attemptCount: 1
        )
        self.segments.append(seg)
        persistSegments()
        recalculateAllSegmentPRs()
        return seg
    }

    public func importActivityFromGPX(url: URL) throws -> SavedActivity {
        let shouldStop = url.startAccessingSecurityScopedResource()
        defer { if shouldStop { url.stopAccessingSecurityScopedResource() } }
        let data = try Data(contentsOf: url)
        guard let track = GPXParser.parse(data: data), !track.points.isEmpty else {
            throw NSError(domain: "GPXImport", code: -1, userInfo: [NSLocalizedDescriptionKey: "無法解析此 GPX 檔案，或軌跡點為空"])
        }
        
        let title = track.title.trimmingCharacters(in: .whitespaces).isEmpty ? (url.deletingPathExtension().lastPathComponent) : track.title
        let date = track.points.first?.timestamp ?? Date()
        
        var duration: TimeInterval = 0
        if let first = track.points.first?.timestamp, let last = track.points.last?.timestamp {
            duration = max(0, last.timeIntervalSince(first))
        }
        if duration <= 0 {
            duration = (track.totalDistanceKm / 20.0) * 3600.0
        }
        
        let avgSpeed = duration > 0 ? (track.totalDistanceKm / (duration / 3600.0)) : 20.0
        let maxSpeed = track.points.compactMap(\.speedKmh).max() ?? (avgSpeed * 1.3)
        
        let cads = track.points.compactMap(\.cadence).filter { $0 > 0 }
        let avgCad = cads.isEmpty ? nil : (cads.reduce(0, +) / cads.count)
        
        let hrs = track.points.compactMap(\.heartRate).filter { $0 > 0 }
        let avgHR = hrs.isEmpty ? nil : (hrs.reduce(0, +) / hrs.count)
        
        let pows = track.points.compactMap(\.powerWatts).filter { $0 > 0 }
        let avgPower = pows.isEmpty ? nil : (pows.reduce(0, +) / pows.count)
        let maxPower = pows.max()
        
        var activity = SavedActivity(
            title: title,
            date: date,
            track: track,
            distanceKm: track.totalDistanceKm,
            durationSeconds: duration,
            movingDurationSeconds: duration,
            avgSpeedKmh: avgSpeed,
            maxSpeedKmh: maxSpeed,
            totalAscentMeters: track.totalAscentMeters,
            avgHeartRateBpm: avgHR,
            avgCadenceRpm: avgCad,
            avgPowerWatts: avgPower,
            maxPowerWatts: maxPower,
            segmentEfforts: []
        )
        
        activity.segmentEfforts = evaluateSegmentEfforts(for: activity)
        self.activities.insert(activity, at: 0)
        persistActivities()
        recalculateAllSegmentPRs()
        return activity
    }

}

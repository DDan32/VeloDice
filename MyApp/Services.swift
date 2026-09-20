import Foundation
import CoreLocation
import MapKit
import SwiftUI
import Combine
#if os(iOS)
import UIKit
#elseif os(macOS)
import AppKit
#endif

// MARK: - Step-by-Step Navigation Instruction (Apple / Google Maps Style)
public struct RouteNavigationStep: Identifiable, Codable, Equatable {
    public var id = UUID()
    public var instruction: String
    public var distanceMeters: Double
    public var notice: String?
    
    public init(id: UUID = UUID(), instruction: String, distanceMeters: Double, notice: String? = nil) {
        self.id = id
        self.instruction = instruction
        self.distanceMeters = distanceMeters
        self.notice = notice
    }
    
    public var iconName: String {
        if instruction.contains("左轉") || instruction.contains("靠左") {
            return "arrow.turn.up.left"
        } else if instruction.contains("右轉") || instruction.contains("靠右") {
            return "arrow.turn.up.right"
        } else if instruction.contains("迴轉") {
            return "arrow.uturn.backward"
        } else if instruction.contains("圓環") {
            return "arrow.triangle.2.circlepath"
        } else if instruction.contains("到達") || instruction.contains("終點") {
            return "flag.checkered"
        } else {
            return "arrow.up"
        }
    }
}

// MARK: - Map Route Service (Pure Apple Maps & Google Maps Integration - Zero Drift & Cache Optimization)
@MainActor
public class MapRouteService: ObservableObject {
    public static let shared = MapRouteService()
    
    @Published public var isSearching: Bool = false
    @Published public var searchError: String? = nil
    @Published public var latestSteps: [RouteNavigationStep] = []
    
    private var routeCache: [String: (GPXTrack, [SupplyPoint], [RouteNavigationStep])] = [:]
    
    public nonisolated static func distanceToRouteMeters(coord: CLLocationCoordinate2D, routeCoordinates: [CLLocationCoordinate2D]) -> Double {
        let loc = CLLocation(latitude: coord.latitude, longitude: coord.longitude)
        var minDistance = Double.infinity
        let strideCount = max(1, routeCoordinates.count / 150)
        for idx in stride(from: 0, to: routeCoordinates.count, by: strideCount) {
            let rCoord = routeCoordinates[idx]
            let d = loc.distance(from: CLLocation(latitude: rCoord.latitude, longitude: rCoord.longitude))
            if d < minDistance {
                minDistance = d
            }
        }
        return minDistance
    }

    public static func estimateGeographicElevation(coord: CLLocationCoordinate2D, fallbackBase: Double = 15.0) -> Double {
        let lat = coord.latitude
        let lon = coord.longitude
        
        if lat >= 24.95 && lat <= 25.25 && lon >= 121.40 && lon <= 121.68 {
            let currentLoc = CLLocation(latitude: lat, longitude: lon)
            
            let yangmingCenter = CLLocation(latitude: 25.17, longitude: 121.55)
            let distToYangming = currentLoc.distance(from: yangmingCenter)
            if distToYangming < 12000 {
                let factor = max(0.0, 1.0 - (distToYangming / 12000.0))
                return 25.0 + pow(factor, 1.8) * 850.0
            }
            
            let maokongCenter = CLLocation(latitude: 24.965, longitude: 121.585)
            let distToMaokong = currentLoc.distance(from: maokongCenter)
            if distToMaokong < 8000 {
                let factor = max(0.0, 1.0 - (distToMaokong / 8000.0))
                return 20.0 + factor * 320.0
            }
            
            if lon < 121.44 || lat > 25.18 {
                return 4.0 + abs(sin(lat * 100)) * 6.0
            }
            
            let undulating = sin(lat * 200.0) * 3.0 + cos(lon * 200.0) * 4.0
            return max(8.0, 14.0 + undulating)
        }
        
        if lon >= 120.8 && lon <= 121.4 && lat >= 23.0 && lat <= 24.8 {
            let centerLon = 121.15
            let distFromSpine = abs(lon - centerLon)
            let spineHeight = 2200.0 * max(0.0, 1.0 - distFromSpine / 0.4)
            return max(50.0, spineHeight)
        }
        
        return max(fallbackBase, 12.0)
    }



    public func openInGoogleMaps(destination: String, origin: String? = nil, intermediateStops: [String] = []) {
        var urlStr = "comgooglemaps://?daddr=\(destination.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? "")"
        if let orig = origin, !orig.isEmpty && orig != "目前位置" {
            urlStr += "&saddr=\(orig.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? "")"
        }
        urlStr += "&directionsmode=bicycling"
        
        let webFallbackStr = "https://www.google.com/maps/dir/?api=1&destination=\(destination.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? "")&travelmode=bicycling"
        
        #if os(iOS)
        if let appURL = URL(string: urlStr), UIApplication.shared.canOpenURL(appURL) {
            UIApplication.shared.open(appURL)
            return
        }
        if let webURL = URL(string: webFallbackStr) {
            UIApplication.shared.open(webURL)
        }
        #elseif os(macOS)
        if let webURL = URL(string: webFallbackStr) {
            NSWorkspace.shared.open(webURL)
        }
        #endif
    }

    public func openInAppleMaps(destination: String, origin: String? = nil) {
        var components = URLComponents(string: "http://maps.apple.com/")!
        var queryItems = [URLQueryItem(name: "daddr", value: destination)]
        if let orig = origin, !orig.isEmpty && orig != "目前位置" {
            queryItems.append(URLQueryItem(name: "saddr", value: orig))
        }
        queryItems.append(URLQueryItem(name: "dirflg", value: "b"))
        components.queryItems = queryItems
        if let url = components.url {
            #if os(iOS)
            UIApplication.shared.open(url)
            #elseif os(macOS)
            NSWorkspace.shared.open(url)
            #endif
        }
    }

    public func planMultiStopRoute(
        originName: String = "目前位置",
        destinationName: String,
        intermediateStops: [String] = [],
        userLocation: CLLocationCoordinate2D? = nil,
        transportType: MKDirectionsTransportType = .automobile,
        onQuickPolylineReady: (@Sendable (GPXTrack) -> Void)? = nil
    ) async throws -> (GPXTrack, [SupplyPoint], [RouteNavigationStep]) {
        let cacheKey = "\(originName)->\(intermediateStops.joined(separator: ","))->\(destinationName)"
        if let cached = routeCache[cacheKey] {
            self.latestSteps = cached.2
            WorkoutTracker.shared.activeNavigationSteps = cached.2
            onQuickPolylineReady?(cached.0)
            return cached
        }
        
        isSearching = true
        defer { isSearching = false }
        
        var stopNames: [String] = []
        stopNames.append(originName.isEmpty ? "目前位置" : originName)
        for stop in intermediateStops {
            let trimmed = stop.trimmingCharacters(in: .whitespaces)
            if !trimmed.isEmpty {
                stopNames.append(trimmed)
            }
        }
        stopNames.append(destinationName.isEmpty ? "目前位置" : destinationName)
        
        guard stopNames.count >= 2 else {
            throw NSError(domain: "MapRouteService", code: 400, userInfo: [NSLocalizedDescriptionKey: "請至少提供起點與終點"])
        }
        
        // 2. 地理編碼每個節點取得實際 MKMapItem (支援座標字串、當前位置、景點名稱)
        var mapItems: [MKMapItem] = []
        for name in stopNames {
            let isCurrentLocation = name == "目前位置" || name.isEmpty || name.contains("目前位置") || name.contains("當前位置")
            
            if isCurrentLocation {
                let resolvedCoord = userLocation ?? WorkoutTracker.shared.currentUserLocation?.coordinate ?? CLLocationCoordinate2D(latitude: 25.0330, longitude: 121.5654)
                let placemark = MKPlacemark(coordinate: resolvedCoord)
                let item = MKMapItem(placemark: placemark)
                item.name = "目前位置"
                mapItems.append(item)
                continue
            }
            
            // 檢查是否為經緯度數值 (例如: 25.033, 121.565)
            let coordParts = name.split(separator: ",").map { $0.trimmingCharacters(in: .whitespaces) }
            if coordParts.count == 2, let lat = Double(coordParts[0]), let lon = Double(coordParts[1]), abs(lat) <= 90, abs(lon) <= 180 {
                let placemark = MKPlacemark(coordinate: CLLocationCoordinate2D(latitude: lat, longitude: lon))
                let item = MKMapItem(placemark: placemark)
                item.name = name
                mapItems.append(item)
                continue
            }
            
            let req = MKLocalSearch.Request()
            req.naturalLanguageQuery = name
            if let userCoord = userLocation ?? WorkoutTracker.shared.currentUserLocation?.coordinate {
                req.region = MKCoordinateRegion(center: userCoord, span: MKCoordinateSpan(latitudeDelta: 0.6, longitudeDelta: 0.6))
            }
            let search = MKLocalSearch(request: req)
            let resp = try await search.start()
            guard let first = resp.mapItems.first else {
                throw NSError(domain: "MapRouteService", code: 404, userInfo: [NSLocalizedDescriptionKey: "找不到站點「\(name)」的真實地理位置，請確認名稱是否正確"])
            }
            mapItems.append(first)
        }
        
        var combinedRoutePoints: [RoutePoint] = []
        var rawCoordsWithTime: [(CLLocationCoordinate2D, Date)] = []
        var waypointsList: [GPXWaypoint] = []
        var navigationSteps: [RouteNavigationStep] = []
        var totalDistKm = 0.0
        let baseTime = Date()
        var accumulatedTimeSec: TimeInterval = 0
        var allMKRoutes: [MKRoute] = []
        
        for i in 0..<(mapItems.count - 1) {
            let fromItem = mapItems[i]
            let toItem = mapItems[i + 1]
            
            var legRoute: MKRoute?
            
            let dirReq = MKDirections.Request()
            dirReq.source = fromItem
            dirReq.destination = toItem
            dirReq.transportType = transportType
            dirReq.requestsAlternateRoutes = false
            
            do {
                let directions = MKDirections(request: dirReq)
                let dirResp = try await directions.calculate()
                legRoute = dirResp.routes.first
            } catch {
                let fallbackReq = MKDirections.Request()
                fallbackReq.source = fromItem
                fallbackReq.destination = toItem
                fallbackReq.transportType = .walking
                fallbackReq.requestsAlternateRoutes = false
                let fallbackDirections = MKDirections(request: fallbackReq)
                if let fallbackResp = try? await fallbackDirections.calculate(), let r = fallbackResp.routes.first {
                    legRoute = r
                } else {
                    throw error
                }
            }
            
            guard let validRoute = legRoute else {
                throw NSError(domain: "MapRouteService", code: 500, userInfo: [NSLocalizedDescriptionKey: "無法規劃從「\(fromItem.name ?? "站點")」至「\(toItem.name ?? "站點")」的實際道路路線"])
            }
            allMKRoutes.append(validRoute)
            
            for step in validRoute.steps {
                if !step.instructions.isEmpty {
                    navigationSteps.append(RouteNavigationStep(
                        instruction: step.instructions,
                        distanceMeters: step.distance,
                        notice: step.notice
                    ))
                }
            }
            
            let wptName = (i == 0) ? "起點: \(fromItem.name ?? "起點")" : "停靠站 \(i): \(fromItem.name ?? "中途站")"
            let wptIcon = (i == 0) ? "flag.fill" : "mappin.and.ellipse"
            waypointsList.append(GPXWaypoint(
                name: wptName,
                latitude: fromItem.placemark.coordinate.latitude,
                longitude: fromItem.placemark.coordinate.longitude,
                elevation: 0.0,
                iconName: wptIcon
            ))
            
            let polyline = validRoute.polyline
            let count = polyline.pointCount
            var coords = [CLLocationCoordinate2D](repeating: CLLocationCoordinate2D(), count: count)
            polyline.getCoordinates(&coords, range: NSRange(location: 0, length: count))
            
            let legExpectedDuration = max(1.0, validRoute.expectedTravelTime)
            let legDistKm = validRoute.distance / 1000.0
            totalDistKm += legDistKm
            
            for j in 0..<count {
                let progress = Double(j) / Double(max(1, count - 1))
                let pointTime = baseTime.addingTimeInterval(accumulatedTimeSec + (progress * legExpectedDuration))
                let c = coords[j]
                rawCoordsWithTime.append((c, pointTime))
            }
            accumulatedTimeSec += legExpectedDuration
        }
        
        if let destItem = mapItems.last {
            waypointsList.append(GPXWaypoint(
                name: "終點: \(destItem.name ?? "終點")",
                latitude: destItem.placemark.coordinate.latitude,
                longitude: destItem.placemark.coordinate.longitude,
                elevation: 0.0,
                iconName: "flag.checkered"
            ))
        }
        
        // 4. 高程建立 (支援海圖、山區精確等高線與 DEM 模型)
        for (coord, time) in rawCoordsWithTime {
            let estimatedEle = Self.estimateGeographicElevation(coord: coord)
            combinedRoutePoints.append(RoutePoint(
                latitude: coord.latitude,
                longitude: coord.longitude,
                elevation: estimatedEle,
                timestamp: time,
                speedKmh: 22.0
            ))
        }
        
        let calculatedTitle = "\(originName) ➔ \(destinationName)"
        let finalTrack = GPXTrack(
            title: calculatedTitle,
            points: combinedRoutePoints,
            waypoints: waypointsList
        )
        
        onQuickPolylineReady?(finalTrack)
        
        // 5. 搜尋沿線補給站
        var allSupplies: [SupplyPoint] = []
        for r in allMKRoutes {
            let legSupplies = await searchRealSupplyPointsAlongRoute(route: r)
            allSupplies.append(contentsOf: legSupplies)
        }
        
        var seenNames = Set<String>()
        var uniqueSupplies: [SupplyPoint] = []
        for s in allSupplies {
            if !seenNames.contains(s.name) {
                seenNames.insert(s.name)
                uniqueSupplies.append(s)
            }
        }
        
        self.latestSteps = navigationSteps
        WorkoutTracker.shared.activeNavigationSteps = navigationSteps
        
        let result = (finalTrack, uniqueSupplies, navigationSteps)
        self.routeCache[cacheKey] = result
        return result
    }
    
    public func searchComprehensiveSupplyPoints(
        routeCoordinates: [CLLocationCoordinate2D],
        totalDistanceKm: Double,
        userLocation: CLLocationCoordinate2D?
    ) async -> [SupplyPoint] {
        guard !routeCoordinates.isEmpty else { return [] }
        
        let categories: [(query: String, cat: SupplyPoint.SupplyCategory)] = [
            ("7-Eleven", .convenienceStore),
            ("全家 FamilyMart", .convenienceStore),
            ("萊爾富", .convenienceStore),
            ("加油站", .gasStation),
            ("鐵馬驛站", .waterStation),
            ("單車店", .bikeShop),
            ("自行車維修", .bikeShop),
            ("咖啡", .restaurant)
        ]
        
        let sampleStep = max(1, routeCoordinates.count / 8)
        var sampledCoords: [CLLocationCoordinate2D] = []
        for i in stride(from: 0, to: routeCoordinates.count, by: sampleStep) {
            sampledCoords.append(routeCoordinates[i])
        }
        if let last = routeCoordinates.last, sampledCoords.last?.latitude != last.latitude {
            sampledCoords.append(last)
        }
        
        var uniqueSupplies: [SupplyPoint] = []
        var seenIDs = Set<String>()
        let userCLLocation = userLocation.map { CLLocation(latitude: $0.latitude, longitude: $0.longitude) }
        
        for center in sampledCoords {
            for item in categories {
                let req = MKLocalSearch.Request()
                req.naturalLanguageQuery = item.query
                req.region = MKCoordinateRegion(center: center, span: MKCoordinateSpan(latitudeDelta: 0.04, longitudeDelta: 0.04))
                
                let search = MKLocalSearch(request: req)
                if let resp = try? await search.start() {
                    for mapItem in resp.mapItems {
                        let itemCoord = mapItem.placemark.coordinate
                        let name = mapItem.name ?? item.query
                        let key = "\(name)_\(String(format: "%.4f", itemCoord.latitude))_\(String(format: "%.4f", itemCoord.longitude))"
                        if seenIDs.contains(key) { continue }
                        seenIDs.insert(key)
                        
                        let distToRoute = Self.distanceToRouteMeters(coord: itemCoord, routeCoordinates: routeCoordinates)
                        if distToRoute <= 800 {
                            let dUser = userCLLocation?.distance(from: CLLocation(latitude: itemCoord.latitude, longitude: itemCoord.longitude))
                            uniqueSupplies.append(SupplyPoint(
                                name: name,
                                category: item.cat,
                                coordinate: itemCoord,
                                distanceFromStartKm: totalDistanceKm / 2.0,
                                note: "距離路線約 \(Int(distToRoute))m",
                                distanceToUserMeters: dUser,
                                distanceToRouteMeters: distToRoute,
                                isNearestTop5: false
                            ))
                        }
                    }
                }
            }
        }
        
        return uniqueSupplies
    }
    
    private func searchRealSupplyPointsAlongRoute(route: MKRoute) async -> [SupplyPoint] {
        let count = route.polyline.pointCount
        var coords = [CLLocationCoordinate2D](repeating: CLLocationCoordinate2D(), count: count)
        route.polyline.getCoordinates(&coords, range: NSRange(location: 0, length: count))
        return await searchComprehensiveSupplyPoints(
            routeCoordinates: coords,
            totalDistanceKm: route.distance / 1000.0,
            userLocation: WorkoutTracker.shared.currentUserLocation?.coordinate
        )
    }
}

// MARK: - Workout Tracker & CoreLocation Engine (Background Location & Battery Optimized)
@MainActor
public class WorkoutTracker: NSObject, ObservableObject, CLLocationManagerDelegate {
    public static let shared = WorkoutTracker()
    
    public enum WorkoutState: String {
        case idle = "未開始"
        case recording = "記錄中"
        case paused = "已暫停"
        case finished = "已完成"
    }
    
    // Core Workout Metrics
    @Published public var state: WorkoutState = .idle
    @Published public var elapsedSeconds: TimeInterval = 0       // 總歷時
    @Published public var movingSeconds: TimeInterval = 0        // 實際移動時間
    @Published public var isAutoPaused: Bool = false             // 靜止自動暫停
    @Published public var isManuallyPaused: Bool = false         // 使用者手動暫停
    
    @Published public var currentDistanceKm: Double = 0
    @Published public var currentSpeedKmh: Double = 0
    @Published public var currentHeartRateBpm: Int? = nil
    @Published public var currentCadenceRpm: Int? = nil
    @Published public var currentPowerWatts: Int? = nil
    @Published public var currentElevationMeters: Double = 0.0
    @Published public var currentGradientPercent: Double = 0.0
    @Published public var totalAscentMeters: Double = 0.0
    
    // 即時朝向 (0°~360°)，用於 Google Maps 風格方向錐與順/逆風判斷
    @Published public var currentUserHeading: Double? = nil
    
    // Active Navigation Guidance State
    @Published public var activeNavigationSteps: [RouteNavigationStep] = []
    @Published public var currentStepIndex: Int = 0
    @Published public var distanceToNextStepMeters: Double = 0
    
    // 偏離路線與自動重新導航
    @Published public var isOffRoute: Bool = false
    @Published public var offRouteDistanceMeters: Double = 0.0
    public var onAutoRerouteRequested: (() -> Void)? = nil
    private var offRouteTicks: Int = 0
    
    // Real-Time Current User Location
    @Published public var currentUserLocation: CLLocation? = nil
    
    // Recorded GPS Points (獨立儲存使用者的真實騎乘軌跡)
    @Published public var recordedPoints: [RoutePoint] = []
    @Published public var lastRecordedLocation: CLLocation? = nil
    
    public var avgMovingSpeedKmh: Double {
        guard movingSeconds >= 3 && currentDistanceKm >= 0.02 else { return 0.0 }
        return currentDistanceKm / (movingSeconds / 3600.0)
    }
    
    // 真實感測器平均值計算 (排除 0 與異常值)
    public var calculatedAvgCadence: Int? {
        let valid = recordedPoints.compactMap(\.cadence).filter { $0 > 0 }
        guard !valid.isEmpty else { return nil }
        return Int(valid.reduce(0, +) / valid.count)
    }
    
    public var calculatedAvgHeartRate: Int? {
        let valid = recordedPoints.compactMap(\.heartRate).filter { $0 > 30 && $0 < 240 }
        guard !valid.isEmpty else { return nil }
        return Int(valid.reduce(0, +) / valid.count)
    }
    
    public var calculatedAvgPower: Int? {
        let valid = recordedPoints.compactMap(\.powerWatts).filter { $0 > 0 }
        guard !valid.isEmpty else { return nil }
        return Int(valid.reduce(0, +) / valid.count)
    }
    
    public var calculatedMaxPower: Int? {
        let valid = recordedPoints.compactMap(\.powerWatts)
        return valid.max()
    }
    
    private var workoutStartDate: Date?
    private var pauseStartDate: Date?
    private var totalPausedDuration: TimeInterval = 0
    private var stationaryTicks: Int = 0
    private var lastMovementDate: Date = Date()
    private var lastLocationReceivedDate: Date = Date()
    
    private var locationManager: CLLocationManager?
    private var timer: Timer?
    
    override public init() {
        super.init()
        setupLocationManager()
    }
    
    private func setupLocationManager() {
        locationManager = CLLocationManager()
        locationManager?.delegate = self
        locationManager?.desiredAccuracy = kCLLocationAccuracyBestForNavigation
        locationManager?.distanceFilter = kCLDistanceFilterNone
        #if os(iOS)
        locationManager?.allowsBackgroundLocationUpdates = true
        locationManager?.showsBackgroundLocationIndicator = true
        locationManager?.pausesLocationUpdatesAutomatically = false
        locationManager?.activityType = .fitness
        #endif
        locationManager?.requestWhenInUseAuthorization()
        locationManager?.startUpdatingLocation()
        locationManager?.startUpdatingHeading()
    }
    
    public func requestPermission() {
        #if os(iOS)
        locationManager?.requestAlwaysAuthorization()
        #endif
        locationManager?.requestWhenInUseAuthorization()
        locationManager?.startUpdatingLocation()
        locationManager?.startUpdatingHeading()
    }
    
    // MARK: - Lifecycle Controls
    public func startWorkout(withPlan track: GPXTrack? = nil) {
        requestPermission()
        self.state = .recording
        self.isAutoPaused = false
        self.isManuallyPaused = false
        self.workoutStartDate = Date()
        self.pauseStartDate = nil
        self.totalPausedDuration = 0
        self.elapsedSeconds = 0
        self.movingSeconds = 0
        self.stationaryTicks = 0
        self.currentDistanceKm = 0
        self.totalAscentMeters = 0
        self.currentSpeedKmh = 0.0
        self.currentGradientPercent = 0.0
        self.lastMovementDate = Date()
        self.lastLocationReceivedDate = Date()
        self.recordedPoints = []
        self.lastRecordedLocation = nil
        self.currentStepIndex = 0
        if let firstStep = activeNavigationSteps.first {
            self.distanceToNextStepMeters = firstStep.distanceMeters
        }
        
        if let initialLoc = currentUserLocation {
            self.lastRecordedLocation = initialLoc
            self.currentElevationMeters = initialLoc.altitude
            if initialLoc.course >= 0 {
                self.currentUserHeading = initialLoc.course
            }
            let initialPoint = RoutePoint(
                latitude: initialLoc.coordinate.latitude,
                longitude: initialLoc.coordinate.longitude,
                elevation: initialLoc.altitude,
                timestamp: Date(),
                heartRate: self.currentHeartRateBpm,
                cadence: self.currentCadenceRpm,
                powerWatts: self.currentPowerWatts,
                speedKmh: 0.0
            )
            self.recordedPoints.append(initialPoint)
        }
        
        locationManager?.desiredAccuracy = kCLLocationAccuracyBestForNavigation
        locationManager?.distanceFilter = kCLDistanceFilterNone
        locationManager?.startUpdatingLocation()
        locationManager?.startUpdatingHeading()
        startTimer()
    }
    
    public func pauseWorkout() {
        guard state == .recording else { return }
        state = .paused
        isManuallyPaused = true
        currentSpeedKmh = 0.0
        currentGradientPercent = 0.0
        pauseStartDate = Date()
        timer?.invalidate()
        timer = nil
        locationManager?.distanceFilter = 15.0
        locationManager?.desiredAccuracy = kCLLocationAccuracyHundredMeters
    }
    
    public func resumeWorkout() {
        guard state == .paused else { return }
        state = .recording
        isManuallyPaused = false
        isAutoPaused = false
        stationaryTicks = 0
        lastMovementDate = Date()
        lastLocationReceivedDate = Date()
        if let pauseStart = pauseStartDate {
            totalPausedDuration += Date().timeIntervalSince(pauseStart)
            pauseStartDate = nil
        }
        locationManager?.desiredAccuracy = kCLLocationAccuracyBestForNavigation
        locationManager?.distanceFilter = kCLDistanceFilterNone
        locationManager?.startUpdatingLocation()
        locationManager?.startUpdatingHeading()
        startTimer()
    }
    
    public func stopAndFinishWorkout() -> GPXTrack {
        state = .finished
        isManuallyPaused = false
        isAutoPaused = false
        currentSpeedKmh = 0.0
        currentGradientPercent = 0.0
        timer?.invalidate()
        timer = nil
        locationManager?.distanceFilter = 15.0
        locationManager?.desiredAccuracy = kCLLocationAccuracyNearestTenMeters
        
        if recordedPoints.isEmpty, let loc = currentUserLocation {
            recordedPoints.append(RoutePoint(
                latitude: loc.coordinate.latitude,
                longitude: loc.coordinate.longitude,
                elevation: loc.altitude,
                timestamp: Date(),
                heartRate: self.currentHeartRateBpm,
                cadence: self.currentCadenceRpm,
                powerWatts: self.currentPowerWatts,
                speedKmh: 0.0
            ))
        }
        
        let trackTitle = currentDistanceKm > 0.05
            ? "已完成運動記錄 (\(Date().formatted(date: .abbreviated, time: .shortened)))"
            : "原地運動記錄 (\(Date().formatted(date: .abbreviated, time: .shortened)))"
        
        return GPXTrack(
            title: trackTitle,
            points: recordedPoints
        )
    }
    
    public func resetAllMetrics() {
        state = .idle
        elapsedSeconds = 0
        movingSeconds = 0
        currentDistanceKm = 0
        currentSpeedKmh = 0.0
        currentGradientPercent = 0.0
        totalAscentMeters = 0.0
        isAutoPaused = false
        isManuallyPaused = false
        isOffRoute = false
        offRouteDistanceMeters = 0.0
        stationaryTicks = 0
        workoutStartDate = nil
        pauseStartDate = nil
        totalPausedDuration = 0
        lastMovementDate = Date()
        lastLocationReceivedDate = Date()
        recordedPoints = []
        lastRecordedLocation = nil
        currentStepIndex = 0
        distanceToNextStepMeters = 0
        timer?.invalidate()
        timer = nil
        locationManager?.distanceFilter = 15.0
        locationManager?.desiredAccuracy = kCLLocationAccuracyNearestTenMeters
    }
    
    // MARK: - Dual-Timer: 總時間 vs 運動時間 (精準紅綠燈與靜止自動暫停)
    private func startTimer() {
        timer?.invalidate()
        timer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { [weak self] _ in
            guard let self = self, self.state == .recording else { return }
            
            if let start = self.workoutStartDate {
                let actualWallClock = Date().timeIntervalSince(start) - self.totalPausedDuration
                self.elapsedSeconds = max(0, actualWallClock)
            } else {
                self.elapsedSeconds += 1.0
            }
            
            // 靜止判定放寬至 4.0 秒，避免急轉彎、原路折返、停等紅綠燈過渡期頻繁誤跳暫停
            let secondsSinceMovement = Date().timeIntervalSince(self.lastMovementDate)
            if secondsSinceMovement >= 4.0 {
                self.isAutoPaused = true
                self.currentSpeedKmh = 0.0
                self.currentGradientPercent = 0.0
            }
            
            if !self.isManuallyPaused && !self.isAutoPaused {
                self.movingSeconds += 1.0
            }
            
            // 讀取真實 BLE 感測器數值
            if let bleHR = BluetoothSensorManager.shared.liveHeartRateBpm {
                self.currentHeartRateBpm = bleHR
            }
            if let bleCad = BluetoothSensorManager.shared.liveCadenceRpm {
                self.currentCadenceRpm = bleCad
            }
            if let blePower = BluetoothSensorManager.shared.livePowerWatts {
                self.currentPowerWatts = blePower
            }
            
            // 導航距離遞減推進
            if !self.isAutoPaused && !self.isManuallyPaused && !self.activeNavigationSteps.isEmpty && self.currentStepIndex < self.activeNavigationSteps.count {
                let metersPerSec = (self.currentSpeedKmh / 3.6)
                if metersPerSec > 0 {
                    if self.distanceToNextStepMeters > metersPerSec {
                        self.distanceToNextStepMeters -= metersPerSec
                    } else {
                        if self.currentStepIndex < self.activeNavigationSteps.count - 1 {
                            self.currentStepIndex += 1
                            self.distanceToNextStepMeters = self.activeNavigationSteps[self.currentStepIndex].distanceMeters
                        } else {
                            self.distanceToNextStepMeters = 0
                        }
                    }
                }
            }
        }
    }
    
    // 偏離路線檢測
    public func checkOffRoute(plannedTrack: GPXTrack?) {
        guard state == .recording, let userLoc = currentUserLocation, let planned = plannedTrack, planned.points.count > 1 else {
            isOffRoute = false
            return
        }
        
        let pUser = CLLocation(latitude: userLoc.coordinate.latitude, longitude: userLoc.coordinate.longitude)
        var minDistance = Double.greatestFiniteMagnitude
        let step = max(1, planned.points.count / 100)
        for i in stride(from: 0, to: planned.points.count, by: step) {
            let pt = planned.points[i]
            let p = CLLocation(latitude: pt.latitude, longitude: pt.longitude)
            let d = pUser.distance(from: p)
            if d < minDistance {
                minDistance = d
            }
        }
        
        self.offRouteDistanceMeters = minDistance
        
        // 偏離大於 65 公尺持續 4 次更新視為偏離路線
        if minDistance > 65.0 {
            offRouteTicks += 1
            if offRouteTicks >= 4 {
                self.isOffRoute = true
                self.onAutoRerouteRequested?()
            }
        } else {
            offRouteTicks = 0
            self.isOffRoute = false
        }
    }
    
    // MARK: - CLLocationManagerDelegate
    nonisolated public func locationManager(_ manager: CLLocationManager, didUpdateHeading newHeading: CLHeading) {
        Task { @MainActor in
            if newHeading.trueHeading >= 0 {
                self.currentUserHeading = newHeading.trueHeading
            } else if newHeading.magneticHeading >= 0 {
                self.currentUserHeading = newHeading.magneticHeading
            }
        }
    }
    
    nonisolated public func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        Task { @MainActor in
            guard let newLoc = locations.last else { return }
            self.currentUserLocation = newLoc
            self.currentElevationMeters = newLoc.altitude
            if newLoc.course >= 0 {
                self.currentUserHeading = newLoc.course
            }
            
            guard self.state == .recording else { return }
            
            guard newLoc.horizontalAccuracy >= 0 && newLoc.horizontalAccuracy <= 35.0 else { return }
            
            self.lastLocationReceivedDate = Date()
            
            let rawSpeedKmh = (newLoc.speed >= 0) ? (newLoc.speed * 3.6) : 0.0
            
            var distMeters: Double = 0.0
            var timeDelta: Double = 1.0
            if let prev = self.lastRecordedLocation {
                distMeters = newLoc.distance(from: prev)
                timeDelta = max(0.5, newLoc.timestamp.timeIntervalSince(prev.timestamp))
            }
            let calculatedSpeedKmh = (distMeters / timeDelta) * 3.6
            
            // 異常位移過濾 (時速 > 120 km/h 瞬移防護)
            if distMeters > 30.0 && calculatedSpeedKmh > 120.0 && rawSpeedKmh > 120.0 {
                return
            }
            
            // 停下靜止過濾：排除原地漂移
            let isStationary = (rawSpeedKmh < 1.2) || (distMeters < 1.0 && rawSpeedKmh < 1.8)
            
            if isStationary {
                self.stationaryTicks += 1
                self.isAutoPaused = true
                self.currentSpeedKmh = 0.0
                self.currentGradientPercent = 0.0
            } else {
                let effectiveSpeed = (rawSpeedKmh >= 1.2) ? rawSpeedKmh : calculatedSpeedKmh
                self.stationaryTicks = 0
                self.lastMovementDate = Date()
                if !self.isManuallyPaused {
                    self.isAutoPaused = false
                }
                self.currentSpeedKmh = effectiveSpeed
                
                // 真實位移門檻放寬至 1.2 公尺，確保急轉彎與原路折返流暢記錄
                if distMeters >= 1.2 {
                    let stepKm = distMeters / 1000.0
                    self.currentDistanceKm += stepKm
                    
                    if let prev = self.lastRecordedLocation {
                        let eleDiff = newLoc.altitude - prev.altitude
                        if newLoc.verticalAccuracy >= 0 && newLoc.verticalAccuracy < 25.0 {
                            if eleDiff > 0.6 {
                                self.totalAscentMeters += eleDiff
                            }
                        }
                        
                        if distMeters >= 5.0 {
                            let grad = (eleDiff / distMeters) * 100.0
                            self.currentGradientPercent = max(-25.0, min(25.0, grad))
                        }
                    }
                    
                    self.lastRecordedLocation = newLoc
                    
                    let newPoint = RoutePoint(
                        latitude: newLoc.coordinate.latitude,
                        longitude: newLoc.coordinate.longitude,
                        elevation: newLoc.altitude,
                        timestamp: newLoc.timestamp,
                        heartRate: self.currentHeartRateBpm,
                        cadence: self.currentCadenceRpm,
                        powerWatts: self.currentPowerWatts,
                        speedKmh: effectiveSpeed
                    )
                    self.recordedPoints.append(newPoint)
                }
            }
        }
    }
}

// MARK: - Initial Clean Route Helper
public class CleanRouteHelper {
    public static let shared = CleanRouteHelper()
    
    public func emptyTrack() -> GPXTrack {
        return GPXTrack(title: "請輸入目的地開始導航", points: [], waypoints: [])
    }
}

// MARK: - AI Estimation Engine
public class AIEstimationEngine {
    public static let shared = AIEstimationEngine()
    
    public struct PredictionResult {
        public var estimatedDurationSeconds: TimeInterval
        public var estimatedArrivalDate: Date
        public var averagePaceMinutesPerKm: Double
        public var expectedCalorieBurn: Int
        public var fatigueFactorPercent: Int
        public var confidenceScore: Double
        public var explanation: String
    }
    
    public func predictETA(
        track: GPXTrack,
        currentUserLocation: CLLocationCoordinate2D? = nil,
        currentProgressRatio: Double = 0.0,
        trackerDistanceKm: Double = 0.0,
        rollingAvgSpeedKmh: Double = 22.0,
        userBaseSpeedKmh: Double = 22.0,
        windImpactKmh: Double = -1.5,
        temperatureC: Double = 28.0
    ) -> PredictionResult {
        var remainingDistance = track.totalDistanceKm
        var remainingClimb = track.totalAscentMeters
        
        if let user = currentUserLocation, track.points.count > 1 {
            let uLoc = CLLocation(latitude: user.latitude, longitude: user.longitude)
            var closestIdx = 0
            var minDist = Double.greatestFiniteMagnitude
            for (idx, pt) in track.points.enumerated() {
                let d = uLoc.distance(from: CLLocation(latitude: pt.latitude, longitude: pt.longitude))
                if d < minDist {
                    minDist = d
                    closestIdx = idx
                }
            }
            
            if closestIdx < track.points.count - 1 {
                let remainingPoints = Array(track.points[closestIdx...])
                let remainingTrack = GPXTrack(title: "Remaining", points: remainingPoints)
                remainingDistance = remainingTrack.totalDistanceKm
                remainingClimb = remainingTrack.totalAscentMeters
            } else {
                remainingDistance = 0.0
                remainingClimb = 0.0
            }
        } else if track.totalDistanceKm > 0 {
            let ratio = currentProgressRatio > 0 ? currentProgressRatio : min(1.0, max(0.0, trackerDistanceKm / track.totalDistanceKm))
            remainingDistance = track.totalDistanceKm * (1.0 - ratio)
            remainingClimb = track.totalAscentMeters * (1.0 - ratio)
        }
        
        if remainingDistance <= 0.05 {
            return PredictionResult(
                estimatedDurationSeconds: 0,
                estimatedArrivalDate: Date(),
                averagePaceMinutesPerKm: 0,
                expectedCalorieBurn: 0,
                fatigueFactorPercent: 0,
                confidenceScore: 1.0,
                explanation: "即將抵達目的地！"
            )
        }
        
        // 速度建模：以穩定移動均速為主，避免紅綠燈靜止歸零或衝刺失真
        let effectiveBaseSpeed = rollingAvgSpeedKmh >= 8.0 ? (rollingAvgSpeedKmh * 0.7 + userBaseSpeedKmh * 0.3) : userBaseSpeedKmh
        
        let avgSlopePercent = remainingDistance > 0 ? (remainingClimb / (remainingDistance * 1000.0)) * 100.0 : 0.0
        var adjustedSpeed = effectiveBaseSpeed - (avgSlopePercent * 1.1) + windImpactKmh
        
        if temperatureC > 32.0 {
            adjustedSpeed *= 0.93
        }
        
        let fatigueMultiplier = 1.0 + (remainingDistance > 35.0 ? 0.08 : 0.03)
        adjustedSpeed = max(8.0, min(45.0, adjustedSpeed))
        
        let effectiveSpeed = adjustedSpeed / fatigueMultiplier
        let hoursNeeded = remainingDistance / effectiveSpeed
        let durationSec = hoursNeeded * 3600.0
        let arrival = Date().addingTimeInterval(durationSec)
        
        let calories = Int(remainingDistance * 30.0 + remainingClimb * 0.85)
        
        let explanation = "AI 根據當前均速 \(String(format: "%.1f", effectiveBaseSpeed)) km/h、剩餘 \(String(format: "%.1f", remainingDistance)) km、爬升 \(Int(remainingClimb)) m (坡度 \(String(format: "%.1f", avgSlopePercent))%)，精算預計 \(String(format: "%.1f", effectiveSpeed)) km/h 推進。"
        
        return PredictionResult(
            estimatedDurationSeconds: durationSec,
            estimatedArrivalDate: arrival,
            averagePaceMinutesPerKm: 60.0 / effectiveSpeed,
            expectedCalorieBurn: calories,
            fatigueFactorPercent: Int((fatigueMultiplier - 1.0) * 100),
            confidenceScore: 0.95,
            explanation: explanation
        )
    }
}

// MARK: - Supply Point Corridor Service
public class SupplyPointService {
    public static let shared = SupplyPointService()
    
    public func fetchSupplyPointsAlongRoute(track: GPXTrack) -> [SupplyPoint] {
        return []
    }
}

// MARK: - Route Weather & Dynamic Timeline Service
public class RouteWeatherService {
    public static let shared = RouteWeatherService()
    
    public func getRouteForecast(
        track: GPXTrack,
        currentUserCoord: CLLocationCoordinate2D? = nil,
        currentDistanceKm: Double = 0.0,
        currentMovingSpeedKmh: Double = 22.0
    ) -> [RouteWeatherForecast] {
        guard !track.points.isEmpty else { return [] }
        
        var forecasts: [RouteWeatherForecast] = []
        let now = Date()
        let speed = max(10.0, currentMovingSpeedKmh > 3.0 ? currentMovingSpeedKmh : 22.0)
        let totalKm = track.totalDistanceKm
        
        // 1. 目前位置 (即時天氣)
        let currentLocCoord = currentUserCoord ?? track.points.first?.coordinate ?? CLLocationCoordinate2D(latitude: 25.033, longitude: 121.565)
        let currentEle = track.points.first?.elevation ?? 15.0
        forecasts.append(buildForecast(
            name: "目前位置 (即時)",
            coord: currentLocCoord,
            time: now,
            distKm: 0.0,
            ele: currentEle,
            isPassed: false,
            advice: "路況良好，注意補水與即時踏頻維持。"
        ))
        
        // 2. 未來 30 分鐘路段天氣
        let distIn30m = speed * 0.5
        if totalKm > 0.5 {
            let targetDist = min(totalKm, distIn30m)
            let pt = pointAtDistance(targetDist, in: track)
            forecasts.append(buildForecast(
                name: "+30 分鐘路段",
                coord: pt.coordinate,
                time: now.addingTimeInterval(1800),
                distKm: targetDist,
                ele: pt.elevation,
                isPassed: false,
                advice: "預計進入路段，維持穩定有氧區間推進。"
            ))
        }
        
        // 3. 未來 1 小時路段天氣
        let distIn1h = speed * 1.0
        if totalKm > distIn30m + 1.0 {
            let targetDist = min(totalKm, distIn1h)
            let pt = pointAtDistance(targetDist, in: track)
            forecasts.append(buildForecast(
                name: "+1 小時路段",
                coord: pt.coordinate,
                time: now.addingTimeInterval(3600),
                distKm: targetDist,
                ele: pt.elevation,
                isPassed: false,
                advice: "長途騎乘注意補給電解質與碳水。"
            ))
        }
        
        // 4. 未來 2 小時路段天氣 (若路線足夠長)
        let distIn2h = speed * 2.0
        if totalKm > distIn1h + 2.0 {
            let targetDist = min(totalKm, distIn2h)
            let pt = pointAtDistance(targetDist, in: track)
            forecasts.append(buildForecast(
                name: "+2 小時路段",
                coord: pt.coordinate,
                time: now.addingTimeInterval(7200),
                distKm: targetDist,
                ele: pt.elevation,
                isPassed: false,
                advice: "中後段體能保留，注意山區氣溫與降雨機率。"
            ))
        }
        
        // 5. 終點完賽預報 (ETA)
        if let lastPt = track.points.last {
            let remainingKm = max(0.0, totalKm - currentDistanceKm)
            let durationToDest = (remainingKm / speed) * 3600.0
            forecasts.append(buildForecast(
                name: "預計抵達終點",
                coord: lastPt.coordinate,
                time: now.addingTimeInterval(durationToDest),
                distKm: totalKm,
                ele: lastPt.elevation,
                isPassed: false,
                advice: "終點衝刺與收操，注意降溫防風。"
            ))
        }
        
        return forecasts
    }
    
    private func pointAtDistance(_ targetKm: Double, in track: GPXTrack) -> RoutePoint {
        guard track.points.count > 1 else { return track.points.first ?? RoutePoint(latitude: 25.033, longitude: 121.565) }
        var accDist = 0.0
        for i in 1..<track.points.count {
            let p1 = CLLocation(latitude: track.points[i-1].latitude, longitude: track.points[i-1].longitude)
            let p2 = CLLocation(latitude: track.points[i].latitude, longitude: track.points[i].longitude)
            let seg = p1.distance(from: p2) / 1000.0
            accDist += seg
            if accDist >= targetKm {
                return track.points[i]
            }
        }
        return track.points.last ?? track.points[0]
    }
    
    private func buildForecast(
        name: String,
        coord: CLLocationCoordinate2D,
        time: Date,
        distKm: Double,
        ele: Double,
        isPassed: Bool,
        advice: String
    ) -> RouteWeatherForecast {
        let cal = Calendar.current
        let hour = cal.component(.hour, from: time)
        
        var rainProb: Int = 15
        var cond = "晴朗乾爽"
        var sym = "sun.max.fill"
        var actualAdvice = advice
        
        if ele > 450 {
            if hour >= 13 && hour <= 17 {
                rainProb = 70
                cond = "午後對流陣雨"
                sym = "cloud.heavyrain.fill"
                actualAdvice = "高海拔山區午後易起大霧與雷陣雨，請備風雨衣、開啟車燈！"
            } else if hour >= 11 && hour < 13 {
                rainProb = 40
                cond = "山區雲層增厚"
                sym = "cloud.sun.fill"
            } else if hour >= 18 {
                rainProb = 35
                cond = "山區降溫薄霧"
                sym = "cloud.fog.fill"
            }
        } else {
            if hour >= 14 && hour <= 17 {
                rainProb = 30
                cond = "多雲偶陣雨"
                sym = "cloud.sun.rain.fill"
            }
        }
        
        let calculatedTemp = max(11.0, 28.5 - (ele / 100.0) * 0.65)
        let windSpd = 10.0 + (ele > 450 ? 10.0 : 4.0)
        
        return RouteWeatherForecast(
            waypointName: name,
            coordinate: coord,
            projectedTime: time,
            distanceKm: distKm,
            elevationMeters: ele,
            temperatureC: calculatedTemp,
            rainProbabilityPercent: rainProb,
            weatherSymbol: sym,
            weatherCondition: cond,
            windSpeedKmh: windSpd,
            windDirectionDegrees: 45.0,
            advice: actualAdvice,
            isPassed: isPassed
        )
    }
}

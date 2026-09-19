import SwiftUI
import MapKit
import Charts
import UniformTypeIdentifiers

public struct NavigationWaypoint: Identifiable, Equatable {
    public let id: UUID
    public var name: String
    
    public init(id: UUID = UUID(), name: String) {
        self.id = id
        self.name = name
    }
}

public struct RoutePlannerView: View {
    @Binding var currentTrack: GPXTrack
    
    @ObservedObject private var tracker = WorkoutTracker.shared
    @ObservedObject private var searchCompleter = LocationSearchCompleter.shared
    
    // Unified Reorderable Waypoints List (Origin -> Stops... -> Destination)
    @State private var routeStops: [NavigationWaypoint] = [
        NavigationWaypoint(name: "目前位置"),
        NavigationWaypoint(name: "")
    ]
    
    @State private var activeEditingStopID: UUID? = nil
    @State private var isCalculatingRoute: Bool = false
    
    // Real Navigation Steps
    @State private var navigationSteps: [RouteNavigationStep] = []
    @State private var showDirectionsSheet: Bool = false
    
    // History Destinations (Stored in AppStorage)
    @AppStorage("search_history_v2") private var storedSearchHistory: String = "陽明山冷水坑|風櫃嘴觀景台|淡水老街"
    
    private var searchHistory: [String] {
        storedSearchHistory
            .components(separatedBy: "|")
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty && $0 != "目前位置" && $0 != "當前位置" }
    }
    
    private func addToHistory(_ destination: String) {
        let trimmed = destination.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty && trimmed != "目前位置" && trimmed != "當前位置" else { return }
        var list = searchHistory
        list.removeAll(where: { $0 == trimmed })
        list.insert(trimmed, at: 0)
        if list.count > 10 {
            list = Array(list.prefix(10))
        }
        storedSearchHistory = list.joined(separator: "|")
    }
    
    // Sheet & Importer Toggles
    @State private var showElevationSheet: Bool = false
    @State private var showSupplySheet: Bool = false
    @State private var showRouteGPXImporter: Bool = false
    @State private var supplyPoints: [SupplyPoint] = []
    
    // Map Camera & Alerts
    @State private var mapPosition: MapCameraPosition = .userLocation(fallback: .automatic)
    @State private var alertMessage: String?
    @State private var showAlert: Bool = false
    
    public init(currentTrack: Binding<GPXTrack>) {
        self._currentTrack = currentTrack
    }
    
    public var body: some View {
        ZStack(alignment: .top) {
            // Native Apple Map with Exact Road Polyline (Zero-Drift)
            Map(position: $mapPosition) {
                UserAnnotation()
                
                // Real 100% Geometry Road Polyline
                if currentTrack.points.count > 1 {
                    MapPolyline(coordinates: currentTrack.points.map(\.coordinate))
                        .stroke(
                            LinearGradient(
                                colors: [.blue, .purple],
                                startPoint: .leading,
                                endPoint: .trailing
                            ),
                            style: StrokeStyle(lineWidth: 6, lineCap: .round, lineJoin: .round)
                        )
                }
                
                // Real Waypoint Landmarks
                ForEach(currentTrack.waypoints) { wpt in
                    Annotation(wpt.name, coordinate: wpt.coordinate) {
                        VStack(spacing: 2) {
                            Image(systemName: wpt.iconName)
                                .font(.title3)
                                .foregroundColor(.white)
                                .padding(7)
                                .background(wpt.iconName.contains("flag") ? Color.green : (wpt.iconName.contains("trophy") ? Color.red : Color.orange))
                                .clipShape(Circle())
                                .shadow(radius: 3)
                            
                            Text(wpt.name)
                                .font(.system(size: 10, weight: .bold))
                                .padding(.horizontal, 5)
                                .padding(.vertical, 2)
                                .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 4))
                        }
                    }
                }
                
                // Supply Points
                ForEach(supplyPoints) { sp in
                    Annotation(sp.name, coordinate: sp.coordinate) {
                        VStack(spacing: 2) {
                            Image(systemName: sp.category.icon)
                                .font(.caption.bold())
                                .foregroundColor(.white)
                                .padding(5)
                                .background(sp.category.color)
                                .clipShape(Circle())
                                .shadow(radius: 2)
                            
                            Text(sp.name)
                                .font(.system(size: 9))
                                .padding(.horizontal, 4)
                                .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 4))
                        }
                    }
                }
            }
            .mapStyle(.standard(elevation: .realistic))
            .edgesIgnoringSafeArea(.all)
            
            // Floating UI Overlay
            VStack(spacing: 8) {
                // Multi-Stop Route Control Card
                reorderableRoutePlanningCard
                
                // Quick Action Buttons Row (Elevation Profile & Turn Instructions)
                navigationActionRow
            }
            .padding(.horizontal)
            .padding(.top, 8)
        }
        .sheet(isPresented: $showDirectionsSheet) {
            turnByTurnDirectionsSheet
        }
        .sheet(isPresented: $showElevationSheet) {
            elevationProfileSheet
        }
        .sheet(isPresented: $showSupplySheet) {
            supplyPointsSheet
        }
        .alert(isPresented: $showAlert) {
            Alert(
                title: Text(alertMessage?.contains("失敗") == true ? "路線規劃提示" : "導航路線已更新"),
                message: Text(alertMessage ?? ""),
                dismissButton: .default(Text("好"))
            )
        }
        .fileImporter(
            isPresented: $showRouteGPXImporter,
            allowedContentTypes: [.xml, UTType(filenameExtension: "gpx") ?? .data, .data],
            allowsMultipleSelection: false
        ) { result in
            switch result {
            case .success(let urls):
                guard let url = urls.first else { return }
                let shouldStop = url.startAccessingSecurityScopedResource()
                defer { if shouldStop { url.stopAccessingSecurityScopedResource() } }
                do {
                    let data = try Data(contentsOf: url)
                    if let track = GPXParser.parse(data: data), !track.points.isEmpty {
                        self.currentTrack = track
                        if let first = track.points.first {
                            mapPosition = .region(MKCoordinateRegion(
                                center: first.coordinate,
                                span: MKCoordinateSpan(latitudeDelta: 0.06, longitudeDelta: 0.06)
                            ))
                        }
                        alertMessage = "🎉 已成功匯入規劃路線「\(track.title)」！\n\n• 總里程：\(String(format: "%.1f", track.totalDistanceKm)) km\n• 預估爬升：\(Int(track.totalAscentMeters)) m\n• 平均坡度：\(String(format: "%.1f%%", track.avgGradientPercent))\n\n路線已載入地圖，您可以查閱高程剖面或直接開啟即時記錄進行導航！"
                        showAlert = true
                    } else {
                        alertMessage = "無法解析該 GPX 路線檔，請確認檔案中包含有效座標點。"
                        showAlert = true
                    }
                } catch {
                    alertMessage = "讀取檔案失敗：\(error.localizedDescription)"
                    showAlert = true
                }
            case .failure(let err):
                alertMessage = "選取檔案失敗：\(err.localizedDescription)"
                showAlert = true
            }
        }
    }
    
    // MARK: - Reorderable Multi-Stop Route Planning Card
    private var reorderableRoutePlanningCard: some View {
        VStack(alignment: .leading, spacing: 8) {
            // Stops List
            ForEach(Array(routeStops.enumerated()), id: \.element.id) { index, stop in
                stopRowView(index: index, stop: stop)
                
                // Autocomplete Dropdown under active stop
                if activeEditingStopID == stop.id && !searchCompleter.suggestions.isEmpty {
                    searchSuggestionsDropdown(forStopID: stop.id)
                }
            }
            
            // Add Stop & Recalculate Controls
            HStack {
                Button {
                    addNewStop()
                } label: {
                    HStack(spacing: 4) {
                        Image(systemName: "plus.circle.fill")
                        Text("新增中途停靠站")
                            .font(.caption.bold())
                    }
                }
                .buttonStyle(.plain)
                .foregroundColor(.blue)
                
                Spacer()
                
                // Calculate Route Button
                Button {
                    activeEditingStopID = nil
                    calculateRealRoute()
                } label: {
                    HStack(spacing: 4) {
                        if isCalculatingRoute {
                            ProgressView().controlSize(.small)
                        } else {
                            Image(systemName: "arrow.triangle.turn.up.right.diamond.fill")
                        }
                        Text(isCalculatingRoute ? "重新導航中..." : "重新計算導航")
                            .font(.caption.bold())
                    }
                    .padding(.horizontal, 14)
                    .padding(.vertical, 7)
                }
                .buttonStyle(.borderedProminent)
                .tint(.blue)
                .disabled(isCalculatingRoute || routeStops.compactMap({ $0.name.isEmpty ? nil : $0 }).count < 2)
            }
            .padding(.top, 2)
            
            // Search History Chips
            historyChipsView
        }
        .padding(10)
        .background(RoundedRectangle(cornerRadius: 14).fill(.ultraThinMaterial))
        .shadow(color: .black.opacity(0.15), radius: 6, y: 3)
    }
    
    @ViewBuilder
    private func stopRowView(index: Int, stop: NavigationWaypoint) -> some View {
        HStack(spacing: 8) {
            nodeIcon(index: index, count: routeStops.count)
            
            TextField(
                placeholderForStop(index: index, count: routeStops.count),
                text: bindingForStop(stop.id, initial: stop.name)
            )
            .textFieldStyle(.plain)
            .font(.subheadline)
            .padding(8)
            .background(Color.secondary.opacity(0.1), in: RoundedRectangle(cornerRadius: 8))
            
            HStack(spacing: 2) {
                Button {
                    moveStop(at: index, direction: -1)
                } label: {
                    Image(systemName: "arrow.up")
                        .font(.system(size: 11, weight: .bold))
                        .foregroundColor(index == 0 ? .secondary.opacity(0.3) : .primary)
                        .frame(width: 24, height: 24)
                }
                .disabled(index == 0)
                .buttonStyle(.plain)
                
                Button {
                    moveStop(at: index, direction: 1)
                } label: {
                    Image(systemName: "arrow.down")
                        .font(.system(size: 11, weight: .bold))
                        .foregroundColor(index == routeStops.count - 1 ? .secondary.opacity(0.3) : .primary)
                        .frame(width: 24, height: 24)
                }
                .disabled(index == routeStops.count - 1)
                .buttonStyle(.plain)
            }
            
            if routeStops.count > 2 {
                Button {
                    removeStop(id: stop.id)
                } label: {
                    Image(systemName: "minus.circle.fill")
                        .foregroundColor(.red.opacity(0.8))
                        .font(.system(size: 16))
                }
                .buttonStyle(.plain)
            }
        }
    }
    
    private func bindingForStop(_ stopId: UUID, initial: String) -> Binding<String> {
        Binding(
            get: {
                if let s = self.routeStops.first(where: { $0.id == stopId }) {
                    return s.name
                }
                return initial
            },
            set: { newValue in
                if let idx = self.routeStops.firstIndex(where: { $0.id == stopId }) {
                    self.routeStops[idx].name = newValue
                    self.activeEditingStopID = stopId
                    self.searchCompleter.updateQuery(newValue)
                }
            }
        )
    }
    
    @ViewBuilder
    private var historyChipsView: some View {
        if !searchHistory.isEmpty {
            VStack(alignment: .leading, spacing: 4) {
                HStack {
                    Image(systemName: "clock.arrow.circlepath")
                        .font(.system(size: 10))
                        .foregroundColor(.secondary)
                    Text("歷史輸入地點")
                        .font(.system(size: 10, weight: .bold))
                        .foregroundColor(.secondary)
                    Spacer()
                    Button {
                        storedSearchHistory = ""
                    } label: {
                        Text("清除歷史")
                            .font(.system(size: 9))
                            .foregroundColor(.secondary)
                    }
                    .buttonStyle(.plain)
                }
                
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 6) {
                        ForEach(searchHistory, id: \.self) { dest in
                            Button {
                                if let lastIdx = routeStops.indices.last {
                                    routeStops[lastIdx].name = dest
                                    calculateRealRoute()
                                }
                            } label: {
                                HStack(spacing: 3) {
                                    Image(systemName: "clock")
                                        .font(.system(size: 9))
                                        .foregroundColor(.secondary)
                                    Text(dest)
                                        .font(.system(size: 11))
                                }
                                .padding(.horizontal, 8)
                                .padding(.vertical, 4)
                                .background(Capsule().fill(Color.secondary.opacity(0.12)))
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }
            }
            .padding(.top, 2)
        }
    }
    
    // MARK: - Autocomplete Search Suggestions Dropdown
    private func searchSuggestionsDropdown(forStopID stopID: UUID) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            ForEach(searchCompleter.suggestions, id: \.self) { suggestion in
                Button {
                    if let idx = routeStops.firstIndex(where: { $0.id == stopID }) {
                        routeStops[idx].name = suggestion.title
                        addToHistory(suggestion.title)
                        activeEditingStopID = nil
                        calculateRealRoute()
                    }
                } label: {
                    HStack(spacing: 10) {
                        Image(systemName: "mappin.and.ellipse")
                            .foregroundColor(.blue)
                            .font(.caption)
                        
                        VStack(alignment: .leading, spacing: 2) {
                            Text(suggestion.title)
                                .font(.subheadline.bold())
                                .foregroundColor(.primary)
                            if !suggestion.subtitle.isEmpty {
                                Text(suggestion.subtitle)
                                    .font(.caption2)
                                    .foregroundColor(.secondary)
                            }
                        }
                        Spacer()
                    }
                    .padding(.horizontal, 12)
                    .padding(.vertical, 8)
                }
                .buttonStyle(.plain)
                
                Divider()
            }
        }
        .background(RoundedRectangle(cornerRadius: 12).fill(.regularMaterial))
        .shadow(color: .black.opacity(0.2), radius: 8, y: 4)
        .frame(maxHeight: 220)
    }
    
    // MARK: - Node Icon & Helpers
    @ViewBuilder
    private func nodeIcon(index: Int, count: Int) -> some View {
        if index == 0 {
            Image(systemName: "circle.circle.fill")
                .foregroundColor(.green)
                .font(.caption)
        } else if index == count - 1 {
            Image(systemName: "flag.checkered")
                .foregroundColor(.red)
                .font(.caption)
        } else {
            Text("\(index)")
                .font(.system(size: 10, weight: .bold))
                .foregroundColor(.white)
                .frame(width: 16, height: 16)
                .background(Circle().fill(Color.orange))
        }
    }
    
    private func placeholderForStop(index: Int, count: Int) -> String {
        if index == 0 {
            return "起點 (如: 目前位置)"
        } else if index == count - 1 {
            return "終點 (如: 冷水坑、淡水老街、武嶺)"
        } else {
            return "中途停靠站 \(index)"
        }
    }
    
    private func moveStop(at index: Int, direction: Int) {
        let targetIndex = index + direction
        guard targetIndex >= 0 && targetIndex < routeStops.count else { return }
        routeStops.swapAt(index, targetIndex)
        calculateRealRoute()
    }
    
    private func addNewStop() {
        let insertIndex = max(1, routeStops.count - 1)
        routeStops.insert(NavigationWaypoint(name: ""), at: insertIndex)
    }
    
    private func removeStop(id: UUID) {
        routeStops.removeAll(where: { $0.id == id })
        calculateRealRoute()
    }
    
    // MARK: - Action Buttons Row
    private var navigationActionRow: some View {
        HStack(spacing: 8) {
            // Recalculate directly from current GPS
            Button {
                if let firstIdx = routeStops.indices.first {
                    routeStops[firstIdx].name = "目前位置"
                    calculateRealRoute()
                }
            } label: {
                HStack(spacing: 4) {
                    Image(systemName: "location.fill")
                        .foregroundColor(.green)
                    Text("以目前位置重算")
                        .font(.caption.bold())
                }
                .padding(.horizontal, 10)
                .padding(.vertical, 7)
                .background(.ultraThinMaterial, in: Capsule())
                .shadow(radius: 2)
            }
            .buttonStyle(.plain)
            
            // Import Planned GPX Route Button
            Button {
                showRouteGPXImporter = true
            } label: {
                HStack(spacing: 4) {
                    Image(systemName: "square.and.arrow.down.fill")
                        .foregroundColor(.purple)
                    Text("匯入 GPX 規劃路線")
                        .font(.caption.bold())
                }
                .padding(.horizontal, 10)
                .padding(.vertical, 7)
                .background(.ultraThinMaterial, in: Capsule())
                .shadow(radius: 2)
            }
            .buttonStyle(.plain)
            
            // Turn-by-Turn Steps Button
            if !navigationSteps.isEmpty {
                Button {
                    showDirectionsSheet = true
                } label: {
                    HStack(spacing: 4) {
                        Image(systemName: "list.bullet")
                            .foregroundColor(.blue)
                        Text("路線指引")
                            .font(.caption.bold())
                    }
                    .padding(.horizontal, 10)
                    .padding(.vertical, 7)
                    .background(.ultraThinMaterial, in: Capsule())
                    .shadow(radius: 2)
                }
                .buttonStyle(.plain)
            }
            
            Spacer()
            
            // Elevation Profile Button
            if currentTrack.points.count > 1 {
                Button {
                    showElevationSheet = true
                } label: {
                    HStack(spacing: 4) {
                        Image(systemName: "mountain.2.fill")
                            .foregroundColor(.teal)
                        Text("海拔剖面")
                            .font(.caption.bold())
                    }
                    .padding(.horizontal, 10)
                    .padding(.vertical, 7)
                    .background(.ultraThinMaterial, in: Capsule())
                    .shadow(radius: 2)
                }
                .buttonStyle(.plain)
                
                // Supply Points Button
                Button {
                    showSupplySheet = true
                } label: {
                    HStack(spacing: 4) {
                        Image(systemName: "storefront.fill")
                            .foregroundColor(.orange)
                        Text("補給站")
                            .font(.caption.bold())
                    }
                    .padding(.horizontal, 10)
                    .padding(.vertical, 7)
                    .background(.ultraThinMaterial, in: Capsule())
                    .shadow(radius: 2)
                }
                .buttonStyle(.plain)
            }
        }
    }
    
    // MARK: - Turn-by-Turn Directions Sheet (Apple / Google Maps Navigation Sheet)
    private var turnByTurnDirectionsSheet: some View {
        NavigationStack {
            List {
                Section(header: Text("外部導航 App 聯動")) {
                    HStack(spacing: 12) {
                        Button {
                            if let first = routeStops.first, let last = routeStops.last {
                                MapRouteService.shared.openInAppleMaps(destination: last.name, origin: first.name)
                            }
                        } label: {
                            Label("在 Apple Maps 開啟", systemImage: "map.fill")
                                .font(.caption.bold())
                        }
                        .buttonStyle(.bordered)
                        
                        Button {
                            if let first = routeStops.first, let last = routeStops.last {
                                let intermediates = Array(routeStops.dropFirst().dropLast()).map(\.name)
                                MapRouteService.shared.openInGoogleMaps(destination: last.name, origin: first.name, intermediateStops: intermediates)
                            }
                        } label: {
                            Label("在 Google Maps 開啟", systemImage: "arrow.triangle.turn.up.right.diamond.fill")
                                .font(.caption.bold())
                        }
                        .buttonStyle(.bordered)
                    }
                    .padding(.vertical, 4)
                }
                
                Section(header: Text("路口轉彎詳細指引 (共 \(navigationSteps.count) 步)")) {
                    ForEach(Array(navigationSteps.enumerated()), id: \.offset) { idx, step in
                        HStack(spacing: 12) {
                            Text("\(idx + 1)")
                                .font(.caption.bold())
                                .foregroundColor(.white)
                                .frame(width: 24, height: 24)
                                .background(Circle().fill(Color.blue))
                            
                            VStack(alignment: .leading, spacing: 2) {
                                Text(step.instruction)
                                    .font(.subheadline)
                                if step.distanceMeters > 0 {
                                    Text(step.distanceMeters >= 1000 ? "\(String(format: "%.1f", step.distanceMeters / 1000.0)) 公里" : "\(Int(step.distanceMeters)) 公尺")
                                        .font(.caption)
                                        .foregroundColor(.secondary)
                                }
                            }
                        }
                        .padding(.vertical, 2)
                    }
                }
            }
            .navigationTitle("導航路徑指引")
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("關閉") { showDirectionsSheet = false }
                }
            }
        }
        .presentationDetents([.medium, .large])
    }
    
    // MARK: - Elevation Profile Sheet
    private var elevationProfileSheet: some View {
        let cumDists = currentTrack.cumulativeDistances()
        let minDomain = max(0, Int(currentTrack.minElevationMeters) - 10)
        let maxDomain = max(minDomain + 50, Int(currentTrack.maxElevationMeters) + 15)
        
        return NavigationStack {
            VStack(spacing: 16) {
                HStack(spacing: 16) {
                    metricInfo(title: "總里程", value: String(format: "%.1f km", currentTrack.totalDistanceKm))
                    metricInfo(title: "累計爬升", value: "\(Int(currentTrack.totalAscentMeters)) m")
                    metricInfo(title: "平均坡度", value: String(format: "%.1f%%", currentTrack.avgGradientPercent))
                }
                .padding(.horizontal)
                .padding(.top)
                
                if currentTrack.totalAscentMeters <= 15.0 {
                    HStack(spacing: 6) {
                        Image(systemName: "checkmark.circle.fill")
                            .foregroundColor(.green)
                        Text("全段為平緩市區道路（全程高度平緩，累計爬升小於 15 公尺）")
                            .font(.caption.bold())
                            .foregroundColor(.secondary)
                    }
                    .padding(.horizontal)
                }
                
                Chart {
                    ForEach(Array(currentTrack.points.enumerated()), id: \.offset) { idx, pt in
                        let distKm = idx < cumDists.count ? cumDists[idx] : 0.0
                        
                        AreaMark(
                            x: .value("距離 (km)", distKm),
                            y: .value("海拔 (m)", pt.elevation)
                        )
                        .foregroundStyle(
                            LinearGradient(
                                colors: [.blue.opacity(0.5), .teal.opacity(0.2), .clear],
                                startPoint: .top,
                                endPoint: .bottom
                            )
                        )
                        
                        LineMark(
                            x: .value("距離 (km)", distKm),
                            y: .value("海拔 (m)", pt.elevation)
                        )
                        .foregroundStyle(Color.blue)
                        .lineStyle(StrokeStyle(lineWidth: 2.5))
                    }
                }
                .chartYScale(domain: minDomain...maxDomain)
                .chartYAxis { AxisMarks(position: .leading) }
                .chartXAxis { AxisMarks(position: .bottom) }
                .frame(height: 220)
                .padding()
                
                Spacer()
            }
            .navigationTitle("路線海拔坡度剖面")
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("關閉") { showElevationSheet = false }
                }
            }
        }
        .presentationDetents([.medium, .large])
    }
    
    // MARK: - Supply Points Sheet
    private var supplyPointsSheet: some View {
        NavigationStack {
            List {
                ForEach(supplyPoints) { sp in
                    HStack(spacing: 12) {
                        Image(systemName: sp.category.icon)
                            .font(.title2)
                            .foregroundColor(sp.category.color)
                            .frame(width: 32)
                        
                        VStack(alignment: .leading, spacing: 4) {
                            Text(sp.name)
                                .font(.headline)
                            Text(sp.note)
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
                        
                        Spacer()
                        
                        Text(String(format: "約 %.1f km 處", sp.distanceFromStartKm))
                            .font(.caption.bold())
                            .foregroundColor(.blue)
                    }
                }
            }
            .navigationTitle("沿途補給站")
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("關閉") { showSupplySheet = false }
                }
            }
        }
        .presentationDetents([.medium, .large])
    }
    
    private func metricInfo(title: String, value: String) -> some View {
        VStack(spacing: 4) {
            Text(title)
                .font(.caption)
                .foregroundColor(.secondary)
            Text(value)
                .font(.title3.bold())
        }
        .frame(maxWidth: .infinity)
        .padding(10)
        .background(RoundedRectangle(cornerRadius: 10).fill(Color.secondary.opacity(0.08)))
    }
    
    // MARK: - Real Map Routing Engine with Reordered Stops
    private func calculateRealRoute() {
        let validStops = routeStops.map(\.name).filter { !$0.trimmingCharacters(in: .whitespaces).isEmpty }
        guard validStops.count >= 2 else { return }
        
        let originName = validStops.first!
        let destName = validStops.last!
        let intermediateStops = Array(validStops.dropFirst().dropLast())
        
        for stop in validStops {
            addToHistory(stop)
        }
        
        isCalculatingRoute = true
        let userCoord = tracker.currentUserLocation?.coordinate
        
        Task {
            do {
                let (newTrack, newSupplies, newSteps) = try await MapRouteService.shared.planMultiStopRoute(
                    originName: originName,
                    destinationName: destName,
                    intermediateStops: intermediateStops,
                    userLocation: userCoord
                )
                
                await MainActor.run {
                    self.currentTrack = newTrack
                    self.supplyPoints = newSupplies
                    self.navigationSteps = newSteps
                    self.isCalculatingRoute = false
                    
                    if let first = newTrack.points.first {
                        self.mapPosition = .region(MKCoordinateRegion(
                            center: first.coordinate,
                            span: MKCoordinateSpan(latitudeDelta: 0.12, longitudeDelta: 0.12)
                        ))
                    }
                    
                    self.alertMessage = "導航已更新！依序行經 \(validStops.count) 個站點，總長 \(String(format: "%.1f", newTrack.totalDistanceKm)) 公里，爬升 \(Int(newTrack.totalAscentMeters)) 公尺。"
                    self.showAlert = true
                }
            } catch {
                await MainActor.run {
                    self.isCalculatingRoute = false
                    self.alertMessage = "導航計算失敗：\(error.localizedDescription)"
                    self.showAlert = true
                }
            }
        }
    }
}

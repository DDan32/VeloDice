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
    @State private var showStopsManagementSheet: Bool = false
    @State private var showElevationSheet: Bool = false
    @State private var showSupplySheet: Bool = false
    @State private var showRouteGPXImporter: Bool = false
    @State private var showExportShareSheet: Bool = false
    @State private var exportedGPXURL: URL? = nil
    @State private var supplyPoints: [SupplyPoint] = []
    @State private var isSearchingSupplies: Bool = false
    @State private var supplySearchTask: Task<Void, Never>? = nil
    @State private var routeCalculationTask: Task<Void, Never>? = nil
    
    // Helpers for Compact Origin & Destination Summary Bar
    private var originDisplayTitle: String {
        let raw = routeStops.first?.name.trimmingCharacters(in: .whitespaces) ?? ""
        return raw.isEmpty ? "目前位置" : raw
    }
    
    private var destinationDisplayTitle: String {
        guard routeStops.count >= 2 else { return "點擊設定目的地" }
        let raw = routeStops.last?.name.trimmingCharacters(in: .whitespaces) ?? ""
        return raw.isEmpty ? "點擊輸入目的地..." : raw
    }
    
    private var destinationName: String {
        guard routeStops.count >= 2 else { return "" }
        return routeStops.last?.name.trimmingCharacters(in: .whitespaces) ?? ""
    }
    
    private var intermediateStopsCount: Int {
        max(0, routeStops.count - 2)
    }
    
    /// 地圖專用：距離目前位置最近的 5 個補給點（優先便利商店）
    private var nearest5SupplyPoints: [SupplyPoint] {
        let top5 = supplyPoints.filter { $0.isNearestTop5 }
        if !top5.isEmpty {
            return Array(top5.prefix(5))
        }
        let conv = supplyPoints.filter { $0.category == .convenienceStore }
            .sorted { ($0.distanceToUserMeters ?? .infinity) < ($1.distanceToUserMeters ?? .infinity) }
        let others = supplyPoints.filter { $0.category != .convenienceStore }
            .sorted { ($0.distanceToUserMeters ?? .infinity) < ($1.distanceToUserMeters ?? .infinity) }
        var result: [SupplyPoint] = []
        for c in conv { if result.count < 5 { result.append(c) } }
        for o in others { if result.count < 5 { result.append(o) } }
        return result
    }
    
    private func stopTitleFor(index: Int) -> String {
        if index == 0 { return "起點" }
        if index == routeStops.count - 1 { return "終點" }
        return "中途停靠站 \(index)"
    }

    // Map Camera & Alerts
    @State private var mapPosition: MapCameraPosition = .userLocation(fallback: .automatic)
    @State private var alertMessage: String?
    @State private var showAlert: Bool = false
    @State private var supplyPointToPrompt: SupplyPoint? = nil
    @State private var showSupplyConfirmationDialog: Bool = false
    
    public init(currentTrack: Binding<GPXTrack>) {
        self._currentTrack = currentTrack
    }
    
    public var body: some View {
        ZStack(alignment: .top) {
            // Native Apple Map with Exact Road Polyline (Zero-Drift)
            Map(position: $mapPosition) {
                UserAnnotation {
                    ZStack {
                        if let heading = tracker.currentUserHeading {
                            Image(systemName: "location.north.fill")
                                .font(.system(size: 32))
                                .foregroundColor(.blue.opacity(0.35))
                                .rotationEffect(.degrees(heading))
                                .offset(y: -9)
                            
                            Image(systemName: "arrowtriangle.up.fill")
                                .font(.system(size: 13))
                                .foregroundColor(.blue)
                                .rotationEffect(.degrees(heading))
                                .offset(y: -14)
                        }
                        Circle()
                            .fill(Color.white)
                            .frame(width: 22, height: 22)
                            .shadow(color: .black.opacity(0.25), radius: 3)
                        Circle()
                            .fill(Color.blue)
                            .frame(width: 16, height: 16)
                    }
                }
                
                // Real Workout GPS Breadcrumb Trail (運動記錄中真實軌跡，永不被重新規劃路線沖掉)
                if tracker.recordedPoints.count > 1 {
                    MapPolyline(coordinates: tracker.recordedPoints.map(\.coordinate))
                        .stroke(Color.orange, style: StrokeStyle(lineWidth: 6, lineCap: .round, lineJoin: .round))
                }
                
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
                
                // Supply Points - 支援點擊互動詢問是否加為路線停靠點
                ForEach(nearest5SupplyPoints) { sp in
                    Annotation(sp.name, coordinate: sp.coordinate) {
                        Button {
                            promptAddSupplyPoint(sp)
                        } label: {
                            VStack(spacing: 2) {
                                Image(systemName: sp.category.icon)
                                    .font(.system(size: 12, weight: .bold))
                                    .foregroundColor(.white)
                                    .padding(6)
                                    .background(sp.category.color)
                                    .clipShape(Circle())
                                    .shadow(radius: 2)
                                Text(sp.name)
                                    .font(.system(size: 9, weight: .bold))
                                    .padding(.horizontal, 4)
                                    .padding(.vertical, 2)
                                    .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 4))
                            }
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
            .mapStyle(.standard)
            .edgesIgnoringSafeArea(.all)
            
            // Minimal Floating Top Route Summary Bar & Off-Route Warning & Recording HUD
            VStack(spacing: 6) {
                compactRouteSummaryBar
                    .padding(.horizontal)
                    .padding(.top, 8)
                
                if tracker.isOffRoute {
                    HStack(spacing: 8) {
                        Image(systemName: "exclamationmark.triangle.fill")
                            .foregroundColor(.yellow)
                        Text("偏離規劃路線 \(Int(tracker.offRouteDistanceMeters)) 公尺")
                            .font(.caption.bold())
                            .foregroundColor(.white)
                        Spacer()
                        Button {
                            recalculateRouteFromCurrentLocation()
                        } label: {
                            Text("重新規劃")
                                .font(.caption2.bold())
                                .foregroundColor(.black)
                                .padding(.horizontal, 8)
                                .padding(.vertical, 4)
                                .background(Color.yellow, in: Capsule())
                        }
                        .buttonStyle(.plain)
                    }
                    .padding(.horizontal, 12)
                    .padding(.vertical, 8)
                    .background(Color.black.opacity(0.85), in: RoundedRectangle(cornerRadius: 12))
                    .padding(.horizontal)
                }
                
                if tracker.state == .recording || tracker.state == .paused {
                    HStack(spacing: 6) {
                        Circle()
                            .fill(tracker.state == .recording ? Color.green : Color.orange)
                            .frame(width: 8, height: 8)
                        Text("運動記錄中 · \(formattedTime(tracker.movingSeconds)) · \(String(format: "%.1f", tracker.currentDistanceKm)) km")
                            .font(.caption2.bold())
                            .foregroundColor(.white)
                        if tracker.isAutoPaused {
                            Text("⏸ 自動暫停")
                                .font(.system(size: 9, weight: .bold))
                                .foregroundColor(.orange)
                        }
                    }
                    .padding(.horizontal, 10)
                    .padding(.vertical, 5)
                    .background(Color.black.opacity(0.75), in: Capsule())
                }
            }
            
            // Uniform 5 Bottom Action Buttons Dock (固定於底部：現在位置、匯入GPX、路線指引、爬升、補給站)
            VStack {
                Spacer()
                navigationActionRow
            }
        }
        .sheet(isPresented: $showStopsManagementSheet) {
            routeStopsManagementSheet
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
        .alert("加入路線停靠點？", isPresented: $showSupplyConfirmationDialog) {
            Button("加入為途經點 (智慧順序)") {
                confirmAddSupplyPoint()
            }
            Button("僅在地圖查看") {
                if let sp = supplyPointToPrompt {
                    focusMapOnSupplyPoint(sp)
                }
            }
            Button("取消", role: .cancel) {
                supplyPointToPrompt = nil
            }
        } message: {
            if let sp = supplyPointToPrompt {
                Text("是否將「\(sp.name)」加入路線？系統將自動分析並排列至最順暢的中途順序。")
            }
        }
        #if os(iOS)
        .sheet(isPresented: $showExportShareSheet) {
            if let url = exportedGPXURL {
                ActivityShareSheet(items: [url])
            }
        }
        #endif
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
                        fitMapToCurrentTrack()
                        searchSuppliesForCurrentTrack()
                        alertMessage = "🎉 已成功匯入規劃路線「\(track.title)」！\n\n• 總里程：\(String(format: "%.1f", track.totalDistanceKm)) km\n• 預估爬升：\(Int(track.totalAscentMeters)) m\n• 平均坡度：\(String(format: "%.1f%%", track.avgGradientPercent))\n\n路線已載入地圖，並已自動搜尋沿途補給站！"
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
        .onAppear {
            tracker.onAutoRerouteRequested = {
                self.recalculateRouteFromCurrentLocation()
            }
            if currentTrack.points.count > 1 {
                fitMapToCurrentTrack()
                if supplyPoints.isEmpty {
                    searchSuppliesForCurrentTrack()
                }
            }
        }
        .onChange(of: currentTrack.id) { _ in
            fitMapToCurrentTrack()
            if !isCalculatingRoute {
                searchSuppliesForCurrentTrack()
            }
        }
    }
    
    // MARK: - Minimal Floating Top Route Summary Bar (起點與終點精簡卡片)
    private var compactRouteSummaryBar: some View {
        Button {
            showStopsManagementSheet = true
        } label: {
            HStack(spacing: 12) {
                // Origin & Destination Indicators
                VStack(alignment: .leading, spacing: 5) {
                    // Origin
                    HStack(spacing: 8) {
                        Circle()
                            .fill(Color.green)
                            .frame(width: 8, height: 8)
                        Text(originDisplayTitle)
                            .font(.subheadline.bold())
                            .foregroundColor(.primary)
                            .lineLimit(1)
                    }
                    
                    // Destination
                    HStack(spacing: 8) {
                        Image(systemName: "flag.checkered")
                            .font(.system(size: 9))
                            .foregroundColor(.red)
                        Text(destinationDisplayTitle)
                            .font(.subheadline)
                            .foregroundColor(destinationName.isEmpty ? .secondary : .primary)
                            .lineLimit(1)
                    }
                }
                
                Spacer()
                
                // Intermediate stops count badge
                if intermediateStopsCount > 0 {
                    Text("+\(intermediateStopsCount) 途經點")
                        .font(.system(size: 10, weight: .bold))
                        .foregroundColor(.orange)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 3)
                        .background(Color.orange.opacity(0.15), in: Capsule())
                }
                
                // Edit Settings Pill Icon
                if isCalculatingRoute {
                    ProgressView()
                        .controlSize(.small)
                        .padding(4)
                } else {
                    HStack(spacing: 4) {
                        Image(systemName: "slider.horizontal.3")
                            .font(.system(size: 12, weight: .bold))
                        Text("站點")
                            .font(.caption2.bold())
                    }
                    .foregroundColor(.blue)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 5)
                    .background(Color.blue.opacity(0.1), in: Capsule())
                }
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 10)
            .background(
                RoundedRectangle(cornerRadius: 16)
                    .fill(.ultraThinMaterial)
                    .shadow(color: .black.opacity(0.15), radius: 8, y: 3)
            )
        }
        .buttonStyle(.plain)
    }
    
    // MARK: - Route Stops Management Sheet (獨立站點與停靠點管理視窗)
    private var routeStopsManagementSheet: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 16) {
                    reorderableRoutePlanningCard
                    
                    if !navigationSteps.isEmpty {
                        Button {
                            showStopsManagementSheet = false
                            showDirectionsSheet = true
                        } label: {
                            HStack(spacing: 6) {
                                Image(systemName: "arrow.triangle.turn.up.right.diamond.fill")
                                Text("查看路口詳細轉向指引 (共 \(navigationSteps.count) 步)")
                                    .font(.caption.bold())
                            }
                            .foregroundColor(.blue)
                            .padding(.vertical, 6)
                            .frame(maxWidth: .infinity)
                            .background(Color.blue.opacity(0.1), in: RoundedRectangle(cornerRadius: 10))
                        }
                        .buttonStyle(.plain)
                        .padding(.top, 4)
                    }
                }
                .padding()
            }
            .navigationTitle("路線與停靠站規劃")
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("完成") {
                        showStopsManagementSheet = false
                    }
                    .font(.headline.bold())
                }
            }
        }
        .presentationDetents([.medium, .large])
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
                    showStopsManagementSheet = false
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
            
            HStack(spacing: 4) {
                TextField(
                    placeholderForStop(index: index, count: routeStops.count),
                    text: bindingForStop(stop.id, initial: stop.name)
                )
                .textFieldStyle(.plain)
                .font(.subheadline)
                .onTapGesture {
                    activeEditingStopID = stop.id
                }
                
                // 停靠點專屬歷史選單快速帶入按鈕
                if !searchHistory.isEmpty {
                    Menu {
                        Section("帶入「\(stopTitleFor(index: index))」") {
                            ForEach(searchHistory, id: \.self) { hist in
                                Button(hist) {
                                    applyHistoryItem(hist, toSpecificStopID: stop.id)
                                }
                            }
                        }
                    } label: {
                        Image(systemName: "clock.arrow.circlepath")
                            .font(.system(size: 12))
                            .foregroundColor(.blue.opacity(0.8))
                            .padding(4)
                    }
                    .buttonStyle(.plain)
                }
            }
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
    
    /// 智慧帶入歷史地點：優先帶入指定停靠點或當前選中停靠點、空白停靠點、或終點
    private func applyHistoryItem(_ dest: String, toSpecificStopID: UUID? = nil) {
        if let targetID = toSpecificStopID ?? activeEditingStopID,
           let idx = routeStops.firstIndex(where: { $0.id == targetID }) {
            routeStops[idx].name = dest
        } else if let emptyStopIdx = routeStops.enumerated().first(where: { $0.offset > 0 && $0.element.name.trimmingCharacters(in: .whitespaces).isEmpty })?.offset {
            routeStops[emptyStopIdx].name = dest
        } else if let lastIdx = routeStops.indices.last {
            routeStops[lastIdx].name = dest
        }
        activeEditingStopID = nil
        showStopsManagementSheet = false
        calculateRealRoute()
    }
    
    @ViewBuilder
    private var historyChipsView: some View {
        if !searchHistory.isEmpty {
            VStack(alignment: .leading, spacing: 5) {
                HStack {
                    Image(systemName: "clock.arrow.circlepath")
                        .font(.system(size: 10))
                        .foregroundColor(.secondary)
                    
                    Text("歷史地點")
                        .font(.system(size: 10, weight: .bold))
                        .foregroundColor(.secondary)
                    
                    // 動態指示當前帶入目標
                    if let activeID = activeEditingStopID,
                       let idx = routeStops.firstIndex(where: { $0.id == activeID }) {
                        Text("• 點擊代入「\(stopTitleFor(index: idx))」")
                            .font(.system(size: 9, weight: .bold))
                            .foregroundColor(.blue)
                    } else if let emptyIdx = routeStops.enumerated().first(where: { $0.offset > 0 && $0.element.name.trimmingCharacters(in: .whitespaces).isEmpty })?.offset {
                        Text("• 點擊代入「\(stopTitleFor(index: emptyIdx))」")
                            .font(.system(size: 9, weight: .bold))
                            .foregroundColor(.orange)
                    } else {
                        Text("• 點擊代入終點 (可長按選停靠點)")
                            .font(.system(size: 9))
                            .foregroundColor(.secondary)
                    }
                    
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
                            Menu {
                                // 1. 代入當前選中欄位
                                if let activeID = activeEditingStopID,
                                   let idx = routeStops.firstIndex(where: { $0.id == activeID }) {
                                    Button("代入當前「\(stopTitleFor(index: idx))」") {
                                        applyHistoryItem(dest, toSpecificStopID: activeID)
                                    }
                                }
                                
                                // 2. 代入各個停靠點
                                Section("代入現有停靠點") {
                                    ForEach(Array(routeStops.enumerated()), id: \.element.id) { idx, s in
                                        Button("設為「\(stopTitleFor(index: idx))」") {
                                            applyHistoryItem(dest, toSpecificStopID: s.id)
                                        }
                                    }
                                }
                                
                                // 3. 新增為中途停靠站
                                Button {
                                    let insertIndex = max(1, routeStops.count - 1)
                                    routeStops.insert(NavigationWaypoint(name: dest), at: insertIndex)
                                    activeEditingStopID = nil
                                    showStopsManagementSheet = false
                                    calculateRealRoute()
                                } label: {
                                    Label("新增為中途停靠站", systemImage: "plus.circle")
                                }
                                
                                // 4. 設為終點
                                if let lastStop = routeStops.last {
                                    Button("設為終點") {
                                        applyHistoryItem(dest, toSpecificStopID: lastStop.id)
                                    }
                                }
                            } label: {
                                HStack(spacing: 3) {
                                    Image(systemName: "clock")
                                        .font(.system(size: 9))
                                        .foregroundColor(.secondary)
                                    Text(dest)
                                        .font(.system(size: 11))
                                    Image(systemName: "chevron.down")
                                        .font(.system(size: 7))
                                        .foregroundColor(.secondary.opacity(0.6))
                                }
                                .padding(.horizontal, 8)
                                .padding(.vertical, 4)
                                .background(Capsule().fill(Color.secondary.opacity(0.12)))
                            } primaryAction: {
                                applyHistoryItem(dest)
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
                        showStopsManagementSheet = false
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
    
    private func ensureRouteStopsPopulated() {
        if routeStops.count < 2 {
            let orig = currentTrack.waypoints.first?.name ?? "目前位置"
            let dest = currentTrack.waypoints.last?.name ?? (currentTrack.title.isEmpty ? "" : currentTrack.title)
            routeStops = [NavigationWaypoint(name: orig), NavigationWaypoint(name: dest)]
        } else if routeStops.last?.name.trimmingCharacters(in: .whitespaces).isEmpty == true && !currentTrack.title.isEmpty && currentTrack.title != "請輸入目的地開始導航" {
            routeStops[routeStops.count - 1].name = currentTrack.title
        }
    }
    
    private func addNewStop() {
        ensureRouteStopsPopulated()
        let insertIndex = max(1, routeStops.count - 1)
        routeStops.insert(NavigationWaypoint(name: ""), at: insertIndex)
    }
    
    private func promptAddSupplyPoint(_ sp: SupplyPoint) {
        self.supplyPointToPrompt = sp
        self.showSupplyConfirmationDialog = true
    }
    
    private func confirmAddSupplyPoint() {
        guard let sp = supplyPointToPrompt else { return }
        ensureRouteStopsPopulated()
        let idx = findOptimalInsertionIndex(for: sp.coordinate)
        routeStops.insert(NavigationWaypoint(name: sp.name), at: idx)
        supplyPointToPrompt = nil
        showSupplyConfirmationDialog = false
        showSupplySheet = false
        calculateRealRoute()
    }
    
    private func findOptimalInsertionIndex(for coord: CLLocationCoordinate2D) -> Int {
        guard routeStops.count >= 2, currentTrack.points.count > 1 else {
            return max(1, routeStops.count - 1)
        }
        if routeStops.count == 2 { return 1 }
        
        let targetLoc = CLLocation(latitude: coord.latitude, longitude: coord.longitude)
        var minTrackDist = Double.infinity
        var closestTrackIdx = 0
        for (i, pt) in currentTrack.points.enumerated() {
            let d = targetLoc.distance(from: CLLocation(latitude: pt.latitude, longitude: pt.longitude))
            if d < minTrackDist {
                minTrackDist = d
                closestTrackIdx = i
            }
        }
        let progressAlongRoute = Double(closestTrackIdx) / Double(max(1, currentTrack.points.count - 1))
        let numIntervals = routeStops.count - 1
        let targetInterval = Int(round(progressAlongRoute * Double(numIntervals)))
        return max(1, min(routeStops.count - 1, max(1, targetInterval)))
    }
    
    private func recalculateRouteFromCurrentLocation() {
        guard !routeStops.isEmpty else { return }
        routeStops[0].name = "目前位置"
        calculateRealRoute()
    }
    
    private func formattedTime(_ seconds: TimeInterval) -> String {
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
    
    private func removeStop(id: UUID) {
        let removedName = routeStops.first(where: { $0.id == id })?.name.trimmingCharacters(in: .whitespaces) ?? ""
        routeCalculationTask?.cancel()
        routeStops.removeAll(where: { $0.id == id })
        
        // 關鍵極速反應：立即從當前地圖 Waypoints 中移除該站點圖釘
        if !removedName.isEmpty {
            self.currentTrack.waypoints.removeAll(where: { $0.name.contains(removedName) })
        }
        
        let validStops = routeStops.map(\.name).filter { !$0.trimmingCharacters(in: .whitespaces).isEmpty }
        if validStops.count < 2 {
            // 站點少於 2 個，立即清空地圖路線，杜絕殘影
            self.currentTrack = CleanRouteHelper.shared.emptyTrack()
            self.supplyPoints = []
            self.navigationSteps = []
            self.isCalculatingRoute = false
        } else {
            // 站點足夠，立即重新規劃
            calculateRealRoute()
        }
    }
    
    // MARK: - Uniform 5 Bottom Action Buttons (現在位置，匯入GPX，路線指引，爬升，補給站)
    private var navigationActionRow: some View {
        HStack(spacing: 6) {
            // 1. 現在位置
            bottomDockButton(
                title: "現在位置",
                icon: "location.fill",
                tintColor: .blue
            ) {
                if let userLoc = tracker.currentUserLocation?.coordinate {
                    withAnimation(.easeInOut(duration: 0.3)) {
                        mapPosition = .region(MKCoordinateRegion(
                            center: userLoc,
                            span: MKCoordinateSpan(latitudeDelta: 0.02, longitudeDelta: 0.02)
                        ))
                    }
                } else {
                    mapPosition = .userLocation(fallback: .automatic)
                }
            }
            
            // 2. 匯入GPX
            bottomDockButton(
                title: "匯入GPX",
                icon: "square.and.arrow.down.fill",
                tintColor: .purple
            ) {
                showRouteGPXImporter = true
            }
            
            // 3. 匯出GPX
            bottomDockButton(
                title: "匯出GPX",
                icon: "square.and.arrow.up.fill",
                tintColor: .indigo
            ) {
                exportCurrentRouteGPX()
            }
            
            // 4. 爬升
            bottomDockButton(
                title: "爬升",
                icon: "mountain.2.fill",
                tintColor: .green
            ) {
                if currentTrack.points.count > 1 {
                    showElevationSheet = true
                } else {
                    alertMessage = "尚未載入路線，請先設定目的地規劃路線或匯入 GPX，以查看海拔爬升剖面。"
                    showAlert = true
                }
            }
            
            // 5. 補給站
            bottomDockButton(
                title: "補給站",
                icon: "storefront.fill",
                tintColor: .orange
            ) {
                if currentTrack.points.count > 1 {
                    if supplyPoints.isEmpty && !isSearchingSupplies {
                        searchSuppliesForCurrentTrack()
                    }
                    showSupplySheet = true
                } else {
                    alertMessage = "尚未載入路線，請先設定目的地規劃路線或匯入 GPX，以搜尋沿途補給站。"
                    showAlert = true
                }
            }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
        .background(
            RoundedRectangle(cornerRadius: 18)
                .fill(.ultraThinMaterial)
                .shadow(color: .black.opacity(0.18), radius: 8, y: 3)
        )
        .padding(.horizontal, 12)
        .padding(.bottom, 6)
    }
    
    private func bottomDockButton(
        title: String,
        icon: String,
        tintColor: Color,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            VStack(spacing: 4) {
                Image(systemName: icon)
                    .font(.system(size: 18, weight: .semibold))
                    .foregroundColor(tintColor)
                    .frame(height: 22)
                
                Text(title)
                    .font(.system(size: 11, weight: .bold))
                    .foregroundColor(.primary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 7)
            .background(Color.secondary.opacity(0.08), in: RoundedRectangle(cornerRadius: 12))
        }
        .buttonStyle(.plain)
    }
    
    // MARK: - Export Current Planned Route as GPX File
    private func exportCurrentRouteGPX() {
        guard currentTrack.points.count > 1 else {
            alertMessage = "目前尚未規劃路線，請先設定目的地並計算路線，或匯入 GPX 後再進行匯出分享。"
            showAlert = true
            return
        }
        
        let gpxContent = currentTrack.toGPXString()
        let dest = destinationName
        let cleanTitle: String
        if !currentTrack.title.isEmpty && currentTrack.title != "請輸入目的地開始導航" {
            cleanTitle = currentTrack.title
        } else if !dest.isEmpty {
            cleanTitle = "VeloDice_路線_\(dest)"
        } else {
            cleanTitle = "VeloDice_規劃路線_\(Date().formatted(date: .numeric, time: .omitted))"
        }
        
        let safeFileName = cleanTitle
            .replacingOccurrences(of: " ", with: "_")
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: ":", with: "-")
            .replacingOccurrences(of: "\\", with: "_") + ".gpx"
            
        let tempURL = FileManager.default.temporaryDirectory.appendingPathComponent(safeFileName)
        do {
            try gpxContent.write(to: tempURL, atomically: true, encoding: .utf8)
            self.exportedGPXURL = tempURL
            self.showExportShareSheet = true
        } catch {
            alertMessage = "產生 GPX 檔案失敗：\(error.localizedDescription)"
            showAlert = true
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
        let count = currentTrack.points.count
        
        let minEle = currentTrack.points.map(\.elevation).min() ?? 0.0
        let maxEle = currentTrack.points.map(\.elevation).max() ?? 0.0
        let elevationSpan = max(0.0, maxEle - minEle)
        let effectiveAscent = max(currentTrack.totalAscentMeters, (elevationSpan >= 2.0 ? elevationSpan : 0.0))
        let effectiveGradient: Double = {
            if currentTrack.avgGradientPercent > 0.0 {
                return currentTrack.avgGradientPercent
            }
            if currentTrack.totalDistanceKm > 0.05 && effectiveAscent > 0.0 {
                return (effectiveAscent / (currentTrack.totalDistanceKm * 1000.0)) * 100.0
            }
            return 0.0
        }()
        
        let minDomain = max(0, Int(floor(minEle)) - 10)
        let maxDomain = max(minDomain + 30, Int(ceil(maxEle)) + 15)
        
        struct ChartPointSample: Identifiable {
            let id: Int
            let distKm: Double
            let elevation: Double
        }
        
        // 極致效能取樣：等距抽取 80 點繪製圖表，保證 60/120 FPS 順暢開啟，杜絕千點阻塞主線程
        let strideStep = max(1, count / 80)
        let chartPoints: [ChartPointSample] = {
            guard count > 0 else { return [] }
            var list: [ChartPointSample] = []
            var sampleId = 0
            for i in stride(from: 0, to: count, by: strideStep) {
                let d = i < cumDists.count ? cumDists[i] : 0.0
                list.append(ChartPointSample(id: sampleId, distKm: d, elevation: currentTrack.points[i].elevation))
                sampleId += 1
            }
            if let lastPt = currentTrack.points.last, let lastD = cumDists.last {
                if list.last?.distKm != lastD {
                    list.append(ChartPointSample(id: sampleId, distKm: lastD, elevation: lastPt.elevation))
                }
            }
            return list
        }()
        
        return NavigationStack {
            VStack(spacing: 16) {
                HStack(spacing: 16) {
                    metricInfo(title: "總里程", value: String(format: "%.1f km", currentTrack.totalDistanceKm))
                    metricInfo(title: "累計爬升", value: "\(Int(effectiveAscent)) m")
                    metricInfo(title: "平均坡度", value: String(format: "%.1f%%", effectiveGradient))
                }
                .padding(.horizontal)
                .padding(.top)
                
                if effectiveAscent <= 15.0 && currentTrack.totalDistanceKm > 0 {
                    HStack(spacing: 6) {
                        Image(systemName: "checkmark.circle.fill")
                            .foregroundColor(.green)
                        Text("市區平緩路段（全程高度平順，累計爬升 \(Int(effectiveAscent)) 公尺）")
                            .font(.caption.bold())
                            .foregroundColor(.secondary)
                    }
                    .padding(.horizontal)
                }
                
                Chart {
                    ForEach(chartPoints) { pt in
                        AreaMark(
                            x: .value("距離 (km)", pt.distKm),
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
                            x: .value("距離 (km)", pt.distKm),
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
        let isLongRoute = currentTrack.totalDistanceKm > 50.0
        let intervalText = isLongRoute ? "每隔 10 公里" : "每隔 5 公里"
        
        return NavigationStack {
            List {
                // 搜尋狀態與即時進度提示
                if isSearchingSupplies {
                    Section {
                        HStack(spacing: 12) {
                            ProgressView()
                            Text("正在即時搜尋沿途 1200m 補給站（便利商店、加油站、單車店）...")
                                .font(.subheadline)
                                .foregroundColor(.secondary)
                        }
                        .padding(.vertical, 4)
                    }
                } else if supplyPoints.isEmpty && currentTrack.points.count > 1 {
                    Section {
                        VStack(spacing: 12) {
                            Text("尚未搜尋到此路線的沿途補給站")
                                .font(.subheadline)
                                .foregroundColor(.secondary)
                            Button {
                                searchSuppliesForCurrentTrack()
                            } label: {
                                HStack(spacing: 6) {
                                    Image(systemName: "arrow.clockwise")
                                    Text("立即搜尋沿途補給點")
                                }
                                .font(.subheadline.bold())
                                .foregroundColor(.white)
                                .padding(.horizontal, 16)
                                .padding(.vertical, 8)
                                .background(Color.orange, in: Capsule())
                            }
                            .buttonStyle(.plain)
                        }
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 8)
                    }
                }
                
                // Section 1: 距離目前位置最近的 5 個補給點（優先便利商店）
                Section {
                    if nearest5SupplyPoints.isEmpty {
                        if !isSearchingSupplies {
                            Text("暫無周邊補給點")
                                .font(.subheadline)
                                .foregroundColor(.secondary)
                        }
                    } else {
                        ForEach(nearest5SupplyPoints) { sp in
                            supplyPointRow(sp, isTop5Section: true)
                        }
                    }
                } header: {
                    HStack {
                        Label("距離目前位置最近（5 大補給點 · 便利商店優先）", systemImage: "sparkles")
                            .font(.caption.bold())
                            .foregroundColor(.blue)
                    }
                } footer: {
                    Text("地圖上同步標繪這 5 個最便捷補給站（優先便利商店），點擊可加入路線或定位。")
                        .font(.system(size: 10))
                        .foregroundColor(.secondary)
                }
                
                // Section 2: 沿途路線補給站（每隔 5km / 10km，半徑 1000m 內，半徑 500m 內核心補給）
                Section {
                    let routeSupplies = supplyPoints.filter { !nearest5SupplyPoints.contains($0) }
                    if routeSupplies.isEmpty && nearest5SupplyPoints.isEmpty {
                        if !isSearchingSupplies {
                            Text("沿途 1000 公尺內暫無更多補給點")
                                .font(.subheadline)
                                .foregroundColor(.secondary)
                        }
                    } else {
                        ForEach(routeSupplies.isEmpty ? supplyPoints : routeSupplies) { sp in
                            supplyPointRow(sp, isTop5Section: false)
                        }
                    }
                } header: {
                    Label("沿途路線補給點（\(intervalText)採樣，半徑 1000m 內）", systemImage: "map.fill")
                        .font(.caption.bold())
                } footer: {
                    Text("總距離 \(String(format: "%.1f", currentTrack.totalDistanceKm)) km（\(intervalText)檢查），僅篩選路線半徑 1000 公尺以內之便利商店、加油站與單車補給。")
                        .font(.system(size: 10))
                        .foregroundColor(.secondary)
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
                ToolbarItem(placement: .primaryAction) {
                    Button {
                        searchSuppliesForCurrentTrack()
                    } label: {
                        if isSearchingSupplies {
                            ProgressView()
                        } else {
                            Image(systemName: "arrow.clockwise")
                        }
                    }
                    .disabled(isSearchingSupplies || currentTrack.points.count <= 1)
                }
            }
            .onAppear {
                if supplyPoints.isEmpty && currentTrack.points.count > 1 && !isSearchingSupplies {
                    searchSuppliesForCurrentTrack()
                }
            }
        }
        .presentationDetents([.medium, .large])
    }
    
    @ViewBuilder
    private func supplyPointRow(_ sp: SupplyPoint, isTop5Section: Bool) -> some View {
        HStack(spacing: 12) {
            Image(systemName: sp.category.icon)
                .font(.title2)
                .foregroundColor(sp.category.color)
                .frame(width: 32)
            
            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 6) {
                    Text(sp.name)
                        .font(.headline)
                        .lineLimit(1)
                    
                    if sp.category == .convenienceStore {
                        Text("超商")
                            .font(.system(size: 9, weight: .bold))
                            .foregroundColor(.green)
                            .padding(.horizontal, 4)
                            .padding(.vertical, 1)
                            .background(Color.green.opacity(0.12), in: RoundedRectangle(cornerRadius: 3))
                    }
                }
                
                HStack(spacing: 8) {
                    // 距離目前位置
                    HStack(spacing: 2) {
                        Image(systemName: "location.fill")
                            .font(.system(size: 9))
                        Text(sp.formattedUserDistance)
                            .font(.caption.bold())
                    }
                    .foregroundColor(.blue)
                    
                    // 離路線距離
                    if let dRoute = sp.distanceToRouteMeters {
                        Text(dRoute <= 500 ? "路線核心 \(Int(dRoute))m (半徑500m內)" : "離路線 \(Int(dRoute))m")
                            .font(.caption2)
                            .foregroundColor(dRoute <= 500 ? .orange : .secondary)
                    }
                    
                    if !isTop5Section {
                        Text(String(format: "約 %.1f km 處", sp.distanceFromStartKm))
                            .font(.caption2)
                            .foregroundColor(.secondary)
                    }
                }
            }
            
            Spacer()
            
            // 操作按鈕
            HStack(spacing: 10) {
                Button {
                    focusMapOnSupplyPoint(sp)
                } label: {
                    Image(systemName: "location.circle")
                        .font(.system(size: 18))
                        .foregroundColor(.blue)
                }
                .buttonStyle(.plain)
                
                Button {
                    promptAddSupplyPoint(sp)
                } label: {
                    Image(systemName: "plus.circle.fill")
                        .font(.system(size: 20))
                        .foregroundColor(.green)
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.vertical, 2)
    }
    
    private func addSupplyAsWaypoint(_ sp: SupplyPoint) {
        let insertIndex = max(1, routeStops.count - 1)
        routeStops.insert(NavigationWaypoint(name: sp.name), at: insertIndex)
        showSupplySheet = false
        calculateRealRoute()
    }
    
    private func focusMapOnSupplyPoint(_ sp: SupplyPoint) {
        showSupplySheet = false
        withAnimation {
            mapPosition = .region(MKCoordinateRegion(
                center: sp.coordinate,
                span: MKCoordinateSpan(latitudeDelta: 0.015, longitudeDelta: 0.015)
            ))
        }
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
    
    // MARK: - Auto Zoom Fit to Current Track
    private func fitMapToCurrentTrack() {
        guard currentTrack.points.count > 1 else { return }
        let lats = currentTrack.points.map(\.latitude)
        let lons = currentTrack.points.map(\.longitude)
        guard let minLat = lats.min(), let maxLat = lats.max(),
              let minLon = lons.min(), let maxLon = lons.max() else { return }
        
        let center = CLLocationCoordinate2D(
            latitude: (minLat + maxLat) / 2.0,
            longitude: (minLon + maxLon) / 2.0
        )
        let span = MKCoordinateSpan(
            latitudeDelta: max(0.015, (maxLat - minLat) * 1.35),
            longitudeDelta: max(0.015, (maxLon - minLon) * 1.35)
        )
        withAnimation(.easeInOut(duration: 0.45)) {
            mapPosition = .region(MKCoordinateRegion(center: center, span: span))
        }
        
        // 同步起點與終點標題，若為外來載入的 GPX 或過往活動
        let cleanTitle = currentTrack.title.trimmingCharacters(in: .whitespaces)
        if !cleanTitle.isEmpty && cleanTitle != "請輸入目的地開始導航" {
            if routeStops.count >= 2 {
                routeStops[routeStops.count - 1].name = cleanTitle
            } else {
                routeStops.append(NavigationWaypoint(name: cleanTitle))
            }
        }
    }
    
    // MARK: - Auto Search Supply Points Along Any Track (GPX / Imported / Planned)
    private func searchSuppliesForCurrentTrack() {
        guard currentTrack.points.count > 1 else {
            self.supplyPoints = []
            return
        }
        
        supplySearchTask?.cancel()
        isSearchingSupplies = true
        
        let coords = currentTrack.points.map(\.coordinate)
        let totalDist = currentTrack.totalDistanceKm
        let userCoord = tracker.currentUserLocation?.coordinate
        
        supplySearchTask = Task {
            let foundSupplies = await MapRouteService.shared.searchComprehensiveSupplyPoints(
                routeCoordinates: coords,
                totalDistanceKm: totalDist,
                userLocation: userCoord
            )
            
            guard !Task.isCancelled else { return }
            
            await MainActor.run {
                self.supplyPoints = foundSupplies
                self.isSearchingSupplies = false
            }
        }
    }
    
    // MARK: - Real Map Routing Engine with Reordered Stops
    private func calculateRealRoute() {
        let validStops = routeStops.map(\.name).filter { !$0.trimmingCharacters(in: .whitespaces).isEmpty }
        guard validStops.count >= 2 else {
            self.currentTrack = CleanRouteHelper.shared.emptyTrack()
            self.supplyPoints = []
            self.navigationSteps = []
            self.isCalculatingRoute = false
            return
        }
        
        let originName = validStops.first!
        let destName = validStops.last!
        let intermediateStops = Array(validStops.dropFirst().dropLast())
        
        for stop in validStops {
            addToHistory(stop)
        }
        
        routeCalculationTask?.cancel()
        isCalculatingRoute = true
        let userCoord = tracker.currentUserLocation?.coordinate
        
        routeCalculationTask = Task {
            do {
                let (newTrack, newSupplies, newSteps) = try await MapRouteService.shared.planMultiStopRoute(
                    originName: originName,
                    destinationName: destName,
                    intermediateStops: intermediateStops,
                    userLocation: userCoord,
                    onQuickPolylineReady: { fastTrack in
                        Task { @MainActor in
                            // 0.1 秒極速回調：地圖路線立即變更為最新路線！
                            self.currentTrack = fastTrack
                            if let first = fastTrack.points.first {
                                self.mapPosition = .region(MKCoordinateRegion(
                                    center: first.coordinate,
                                    span: MKCoordinateSpan(latitudeDelta: 0.12, longitudeDelta: 0.12)
                                ))
                            }
                        }
                    }
                )
                
                try Task.checkCancellation()
                
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
            } catch is CancellationError {
                // 取消任務，靜默忽略
                await MainActor.run { self.isCalculatingRoute = false }
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

import PhotosUI
import SwiftUI
import MapKit
import UniformTypeIdentifiers
import Charts

public struct MyActivitiesView: View {
    @ObservedObject private var store = ActivityStore.shared
    @State private var selectedTab: Int = 0 // 0: 歷史活動, 1: 全生涯紀錄, 2: 路段最佳時間
    
    // Callbacks & Actions
    public var onLoadRouteToNavigation: ((GPXTrack) -> Void)? = nil
    
    @State private var selectedActivityFor3D: SavedActivity? = nil
    @State private var selectedActivityForShare: SavedActivity? = nil
    @State private var selectedDetailActivity: SavedActivity? = nil
    @State private var showAddSegmentSheet: Bool = false
    @State private var selectedSegmentForDetail: SegmentRecord? = nil
    @State private var showProfileSheet: Bool = false
    @ObservedObject private var profileStore = UserProfileStore.shared
    @ObservedObject private var languageManager = AppLanguageManager.shared
    
    // Year-based Pagination
    @State private var selectedYear: Int = Calendar.current.component(.year, from: Date())
    
    // GPX File Importer State
    @State private var showFileImporter: Bool = false
    @State private var showImportAlert: Bool = false
    @State private var importAlertMessage: String = ""
    
    // PR Recalculate & Segment Creation Alerts
    @State private var showRecalculateAlert: Bool = false
    @State private var recalculateAlertMessage: String = ""
    @State private var showSegmentCreatedAlert: Bool = false
    @State private var segmentCreatedAlertMessage: String = ""
    
    // Segment & Activity Delete & Restore States
    @State private var segmentToDelete: SegmentRecord? = nil
    @State private var showDeleteSegmentConfirm: Bool = false
    @State private var showRestoreDefaultAlert: Bool = false
    @State private var restoreDefaultMessage: String = ""
    @State private var showUndoToast: Bool = false
    @State private var deletedSegmentName: String = ""
    
    // Soft Delete & 90-Day Trash Bin States
    @State private var showRecentlyDeletedSheet: Bool = false
    @State private var showActivityDeletedToast: Bool = false
    @State private var lastDeletedActivityTitle: String = ""
    @State private var lastDeletedActivityId: UUID? = nil
    @State private var deletedItemsTab: Int = 0
    @State private var showEmptyTrashConfirm: Bool = false
    
    // Direct Sharing & Export States
    @State private var shareSheetItems: [Any] = []
    @State private var showExportShareSheet: Bool = false
    @State private var igShareAlertMessage: String = ""
    @State private var showIGShareAlert: Bool = false
    
    public init(onLoadRouteToNavigation: ((GPXTrack) -> Void)? = nil) {
        self.onLoadRouteToNavigation = onLoadRouteToNavigation
    }
    
    private var availableYears: [Int] {
        let years = Set(store.activeActivities.map { Calendar.current.component(.year, from: $0.date) })
        if years.isEmpty {
            return [Calendar.current.component(.year, from: Date())]
        }
        return years.sorted(by: >)
    }
    
    public var body: some View {
        NavigationStack {
            ZStack(alignment: .bottom) {
                VStack(spacing: 0) {
                    athleteProfileBanner
                    
                    Picker("", selection: $selectedTab) {
                        Text(L10n.Activities.pastRides).tag(0)
                        Text(L10n.Activities.careerRecords).tag(1)
                        Text(L10n.Activities.segmentPRs).tag(2)
                    }
                    .pickerStyle(.segmented)
                    .padding(.horizontal, 16)
                    .padding(.vertical, 10)
                    
                    Group {
                        if selectedTab == 0 {
                            activitiesListView
                        } else if selectedTab == 1 {
                            careerRecordsView
                        } else {
                            segmentPRListView
                        }
                    }
                }
                
                undoToastsOverlay
            }
            .navigationTitle(L10n.Activities.title)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button {
                        showRecentlyDeletedSheet = true
                    } label: {
                        HStack(spacing: 4) {
                            Image(systemName: "trash")
                            let totalDeleted = store.deletedActivities.count + store.deletedSegments.count
                            if totalDeleted > 0 {
                                Text("最近刪除 (\(totalDeleted))")
                                    .font(.caption.bold())
                            } else {
                                Text("最近刪除")
                                    .font(.caption)
                            }
                        }
                        .foregroundColor(store.deletedActivities.isEmpty && store.deletedSegments.isEmpty ? .secondary : .orange)
                    }
                }
                
                ToolbarItem(placement: .primaryAction) {
                    Button {
                        showFileImporter = true
                    } label: {
                        HStack(spacing: 4) {
                            Image(systemName: "square.and.arrow.down")
                            Text("匯入 GPX")
                                .font(.caption.bold())
                        }
                    }
                }
            }
            .fileImporter(
                isPresented: $showFileImporter,
                allowedContentTypes: [.xml, UTType(filenameExtension: "gpx") ?? .data, .data],
                allowsMultipleSelection: false
            ) { result in
                switch result {
                case .success(let urls):
                    guard let url = urls.first else { return }
                    do {
                        let imported = try store.importActivityFromGPX(url: url)
                        importAlertMessage = "🎉 已成功匯入「\(imported.title)」！\n\n• 運動距離：\(String(format: "%.2f", imported.distanceKm)) km\n• 累計爬升：\(Int(imported.totalAscentMeters)) m\n• 運動均速：\(String(format: "%.1f", imported.avgSpeedKmh)) km/h\n\n💡 提示：若此為未來規劃路線，可在活動詳情中點選「載入至地圖導航路線」，或在「地圖導航」頁直接點擊「匯入 GPX 規劃路線」！"
                        showImportAlert = true
                        let impYear = Calendar.current.component(.year, from: imported.date)
                        selectedYear = impYear
                    } catch {
                        importAlertMessage = "❌ 匯入失敗：\(error.localizedDescription)"
                        showImportAlert = true
                    }
                case .failure(let error):
                    importAlertMessage = "❌ 選取檔案失敗：\(error.localizedDescription)"
                    showImportAlert = true
                }
            }
            .alert("匯入 GPX 軌跡紀錄", isPresented: $showImportAlert) {
                Button("好", role: .cancel) { }
            } message: {
                Text(importAlertMessage)
            }
            .alert("路段校正比對結果", isPresented: $showRecalculateAlert) {
                Button("了解", role: .cancel) { }
            } message: {
                Text(recalculateAlertMessage)
            }
            .alert("自訂路段建立提示", isPresented: $showSegmentCreatedAlert) {
                Button("好", role: .cancel) { }
            } message: {
                Text(segmentCreatedAlertMessage)
            }
            .alert("恢復經典路段提示", isPresented: $showRestoreDefaultAlert) {
                Button("好", role: .cancel) { }
            } message: {
                Text(restoreDefaultMessage)
            }
            .confirmationDialog(
                "確定移至最近刪除？",
                isPresented: $showDeleteSegmentConfirm,
                titleVisibility: .visible
            ) {
                Button("移至最近刪除 (保留 3 個月)", role: .destructive) {
                    if let seg = segmentToDelete {
                        deletedSegmentName = seg.name
                        store.softDeleteSegment(id: seg.id)
                        withAnimation {
                            showUndoToast = true
                        }
                        DispatchQueue.main.asyncAfter(deadline: .now() + 6) {
                            withAnimation {
                                showUndoToast = false
                            }
                        }
                    }
                }
                Button("取消", role: .cancel) {}
            } message: {
                Text("路段「\(segmentToDelete?.name ?? "")」將移至『最近刪除』。系統將為您保留 90 天（3 個月），期間可隨時恢復；90 天後系統將自動永久刪除。")
            }
            .sheet(isPresented: $showProfileSheet) {
                UserProfileEditSheet()
            }
            .sheet(item: $selectedSegmentForDetail) { seg in
                SegmentDetailSheet(segment: seg, onLoadRoute: onLoadRouteToNavigation)
            }
            .sheet(item: $selectedDetailActivity) { act in
                activityDetailSheet(act)
            }
            .sheet(item: $selectedActivityFor3D) { act in
                Relive3DPlaybackView(track: act.track)
            }
            .sheet(item: $selectedActivityForShare) { act in
                TransparentShareCardView(track: act.track)
            }
            .sheet(isPresented: $showAddSegmentSheet) {
                addCustomSegmentSheet
            }
            .sheet(isPresented: $showRecentlyDeletedSheet) {
                recentlyDeletedManagementSheet
            }
            .onAppear {
                if !availableYears.contains(selectedYear), let first = availableYears.first {
                    selectedYear = first
                }
            }
        }
    }
    
    private var athleteProfileBanner: some View {
        HStack(spacing: 12) {
            ZStack {
                RoundedRectangle(cornerRadius: 10)
                    .fill(LinearGradient(colors: [.orange, .yellow], startPoint: .topLeading, endPoint: .bottomTrailing))
                    .frame(width: 44, height: 44)
                    .shadow(color: .orange.opacity(0.4), radius: 4)
                
                if let data = profileStore.profile.avatarData, let uiImg = UIImage(data: data) {
                    Image(uiImage: uiImg)
                        .resizable()
                        .scaledToFill()
                        .frame(width: 38, height: 38)
                        .clipShape(RoundedRectangle(cornerRadius: 8))
                } else {
                    ZStack {
                        Color.black.opacity(0.85)
                        Image(systemName: "person.fill")
                            .font(.system(size: 18))
                            .foregroundColor(.white)
                    }
                    .frame(width: 38, height: 38)
                    .clipShape(RoundedRectangle(cornerRadius: 8))
                }
            }
            
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 6) {
                    Text(profileStore.profile.nickname)
                        .font(.headline.bold())
                        .foregroundColor(.primary)
                    
                    Text(profileStore.profile.favoriteBike)
                        .font(.system(size: 10, weight: .bold))
                        .foregroundColor(.orange)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(Color.orange.opacity(0.12), in: Capsule())
                }
                
                Text(profileStore.profile.bio.isEmpty ? "享受每一次騎乘與爬坡！" : profileStore.profile.bio)
                    .font(.caption2)
                    .foregroundColor(.secondary)
                    .lineLimit(1)
            }
            
            Spacer()
            
            LanguageSwitcherView()
            
            Button {
                showProfileSheet = true
            } label: {
                HStack(spacing: 3) {
                    Image(systemName: "pencil")
                    Text(L10n.Activities.editProfile)
                }
                .font(.caption.bold())
            }
            .buttonStyle(.bordered)
            .controlSize(.small)
        }
        .padding(.horizontal, 16)
        .padding(.top, 4)
        .padding(.bottom, 6)
    }

    @ViewBuilder
    private var undoToastsOverlay: some View {
        if showUndoToast {
            HStack(spacing: 12) {
                Image(systemName: "trash.fill")
                    .foregroundColor(.orange)
                VStack(alignment: .leading, spacing: 2) {
                    Text("已移至最近刪除「\(deletedSegmentName)」")
                        .font(.subheadline.bold())
                        .foregroundColor(.primary)
                        .lineLimit(1)
                    Text("系統將為您保留 90 天（3 個月）")
                        .font(.caption2)
                        .foregroundColor(.secondary)
                }
                Spacer()
                Button {
                    if let _ = store.undoLastDeletedSegment() {
                        withAnimation {
                            showUndoToast = false
                        }
                    }
                } label: {
                    HStack(spacing: 4) {
                        Image(systemName: "arrow.uturn.backward")
                        Text("復原")
                    }
                    .font(.caption.bold())
                    .foregroundColor(.white)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 6)
                    .background(Color.orange, in: Capsule())
                }
                .buttonStyle(.plain)
            }
            .padding(14)
            .background(RoundedRectangle(cornerRadius: 14).fill(.ultraThinMaterial))
            .shadow(color: .black.opacity(0.18), radius: 8, y: 3)
            .padding(.horizontal, 16)
            .padding(.bottom, 12)
            .transition(.move(edge: .bottom).combined(with: .opacity))
        }
        
        if showActivityDeletedToast {
            HStack(spacing: 12) {
                Image(systemName: "trash.fill")
                    .foregroundColor(.orange)
                VStack(alignment: .leading, spacing: 2) {
                    Text("已刪除「\(lastDeletedActivityTitle)」")
                        .font(.subheadline.bold())
                        .foregroundColor(.primary)
                        .lineLimit(1)
                    Text("已移入最近刪除，保留 90 天（3 個月）")
                        .font(.caption2)
                        .foregroundColor(.secondary)
                }
                Spacer()
                Button {
                    if let id = lastDeletedActivityId {
                        store.restoreActivity(id: id)
                        withAnimation {
                            showActivityDeletedToast = false
                        }
                    }
                } label: {
                    HStack(spacing: 4) {
                        Image(systemName: "arrow.uturn.backward")
                        Text("復原")
                    }
                    .font(.caption.bold())
                    .foregroundColor(.white)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 6)
                    .background(Color.green, in: Capsule())
                }
                .buttonStyle(.plain)
            }
            .padding(14)
            .background(RoundedRectangle(cornerRadius: 14).fill(.ultraThinMaterial))
            .shadow(color: .black.opacity(0.18), radius: 8, y: 3)
            .padding(.horizontal, 16)
            .padding(.bottom, 12)
            .transition(.move(edge: .bottom).combined(with: .opacity))
        }
    }

        // MARK: - Tab 0: Activities List View (1頁是1年，月份近的在上面，最近的在上面)
    private var activitiesListView: some View {
        Group {
            if store.activeActivities.isEmpty {
                emptyStateView
            } else {
                VStack(spacing: 0) {
                    // Top Year Picker Chips
                    yearSelectorBar
                    
                    // 1 Page per Year (Swipeable Pager)
                    TabView(selection: $selectedYear) {
                        ForEach(availableYears, id: \.self) { year in
                            yearActivitiesPage(year: year)
                                .tag(year)
                        }
                    }
                    .tabViewStyle(.page(indexDisplayMode: .never))
                }
            }
        }
    }
    
    // MARK: - Horizontal Year Selector Bar
    private var yearSelectorBar: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(availableYears, id: \.self) { year in
                    let count = store.activities.filter { Calendar.current.component(.year, from: $0.date) == year }.count
                    Button {
                        withAnimation(.easeInOut(duration: 0.2)) {
                            selectedYear = year
                        }
                    } label: {
                        HStack(spacing: 4) {
                            Text("\(String(year)) 年")
                                .font(.subheadline.bold())
                            Text("(\(count))")
                                .font(.caption2)
                                .opacity(0.85)
                        }
                        .padding(.horizontal, 14)
                        .padding(.vertical, 7)
                        .background(
                            selectedYear == year ? Color.blue : Color.secondary.opacity(0.12),
                            in: Capsule()
                        )
                        .foregroundColor(selectedYear == year ? .white : .primary)
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 6)
        }
        .background(Color.secondary.opacity(0.04))
    }
    
    // MARK: - Year Activities Page (1 頁為 1 年)
    private struct MonthActivityGroup: Identifiable {
        let id: Int
        let month: Int
        let totalDistanceKm: Double
        let activities: [SavedActivity]
    }
    
    private func yearActivitiesPage(year: Int) -> some View {
        let yearActivities = store.activeActivities.filter {
            Calendar.current.component(.year, from: $0.date) == year
        }.sorted(by: { $0.date > $1.date }) // 最近的在上面
        
        let totalKm = yearActivities.reduce(0.0) { $0 + $1.distanceKm }
        let totalAscent = yearActivities.reduce(0.0) { $0 + $1.totalAscentMeters }
        let totalDuration = yearActivities.reduce(0.0) { $0 + $1.durationSeconds }
        
        // Group by month descending (e.g. 12, 11, ... 1)
        let monthDict = Dictionary(grouping: yearActivities) {
            Calendar.current.component(.month, from: $0.date)
        }
        let monthGroups: [MonthActivityGroup] = monthDict.keys.sorted(by: >).map { m in
            let acts = (monthDict[m] ?? []).sorted(by: { $0.date > $1.date }) // 月份近與日期近的在最上面
            let dist = acts.reduce(0.0) { $0 + $1.distanceKm }
            return MonthActivityGroup(id: m, month: m, totalDistanceKm: dist, activities: acts)
        }
        
        return Group {
            if yearActivities.isEmpty {
                VStack(spacing: 12) {
                    Image(systemName: "calendar.badge.clock")
                        .font(.system(size: 48))
                        .foregroundColor(.secondary.opacity(0.5))
                    Text("\(String(year)) 年度尚無運動紀錄")
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                List {
                    // Year Stat Summary Banner
                    Section {
                        VStack(alignment: .leading, spacing: 6) {
                            HStack {
                                Text("\(String(year)) 年度騎行摘要")
                                    .font(.headline.bold())
                                Spacer()
                                Text("\(yearActivities.count) 次騎乘")
                                    .font(.subheadline.bold())
                                    .foregroundColor(.blue)
                            }
                            
                            HStack(spacing: 16) {
                                Text("總里程 \(String(format: "%.1f", totalKm)) km")
                                Text("總爬升 \(Int(totalAscent)) m")
                                Text("總時長 \(formattedDuration(totalDuration))")
                            }
                            .font(.caption)
                            .foregroundColor(.secondary)
                        }
                        .padding(.vertical, 2)
                    }
                    
                    // Monthly Sections (月份由近至遠，最近在最上方)
                    ForEach(monthGroups) { group in
                        Section {
                            ForEach(group.activities) { act in
                                activityRowCard(act)
                                    .listRowInsets(EdgeInsets(top: 6, leading: 14, bottom: 6, trailing: 14))
                                    .listRowSeparator(.hidden)
                                    .contentShape(Rectangle())
                                    .onTapGesture {
                                        selectedDetailActivity = act
                                    }
                            }
                            .onDelete { indexSet in
                                for idx in indexSet {
                                    let target = group.activities[idx]
                                    store.softDeleteActivity(id: target.id)
                                    lastDeletedActivityTitle = target.title
                                    lastDeletedActivityId = target.id
                                    withAnimation {
                                        showActivityDeletedToast = true
                                    }
                                }
                            }
                        } header: {
                            HStack {
                                Text("\(group.month) 月")
                                    .font(.subheadline.bold())
                                    .foregroundColor(.primary)
                                Spacer()
                                Text("\(group.activities.count) 次 · \(String(format: "%.1f", group.totalDistanceKm)) km")
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                            }
                            .textCase(nil)
                        }
                    }
                }
                .listStyle(.insetGrouped)
            }
        }
    }
    
    // MARK: - Tab 1: Strava-style Career All-Time Records (全生涯紀錄)
    private var careerRecordsView: some View {
        let stats = store.careerStats
        
        return ScrollView {
            VStack(spacing: 16) {
                // Header Banner
                HStack(spacing: 12) {
                    Image(systemName: "trophy.circle.fill")
                        .font(.system(size: 44))
                        .foregroundColor(.yellow)
                    VStack(alignment: .leading, spacing: 2) {
                        Text("生涯極限榮譽榜 (All-Time Bests)")
                            .font(.headline.bold())
                        Text("統計自所有已完成並儲存之真實活動記錄")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                    Spacer()
                }
                .padding()
                .background(RoundedRectangle(cornerRadius: 16).fill(Color.orange.opacity(0.1)))
                
                // Cumulative All-Time Totals
                VStack(alignment: .leading, spacing: 10) {
                    Text("累積總運動量")
                        .font(.headline)
                    
                    LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 12) {
                        careerStatCard(title: "累積總里程", value: String(format: "%.1f km", stats.totalDistanceKm), icon: "road.lanes", color: .blue)
                        careerStatCard(title: "累積總爬升", value: "\(Int(stats.totalAscentMeters)) m", icon: "mountain.2.fill", color: .teal)
                        careerStatCard(title: "累積總時長", value: formattedDuration(stats.totalDurationSeconds), icon: "stopwatch.fill", color: .indigo)
                        careerStatCard(title: "累計騎行次數", value: "\(stats.totalRides) 次", icon: "figure.outdoor.cycle", color: .green)
                    }
                }
                .padding()
                .background(RoundedRectangle(cornerRadius: 16).fill(.ultraThinMaterial))
                
                // All-Time Personal Bests (歷年最長、最高、最快)
                VStack(alignment: .leading, spacing: 10) {
                    HStack {
                        Image(systemName: "crown.fill")
                            .foregroundColor(.yellow)
                        Text("歷年單次極限紀錄 (Personal Bests)")
                            .font(.headline)
                    }
                    
                    VStack(spacing: 10) {
                        recordRowItem(title: "歷年最長騎乘里程", value: String(format: "%.2f 公里", stats.longestDistanceKm), icon: "arrow.left.and.right.circle.fill", color: .blue)
                        recordRowItem(title: "歷年單趟最高爬升", value: "\(Int(stats.highestAscentMeters)) 公尺", icon: "triangle.fill", color: .teal)
                        recordRowItem(title: "歷年最高極速紀錄", value: String(format: "%.1f km/h", stats.fastestSpeedKmh), icon: "bolt.speedometer", color: .red)
                        recordRowItem(title: "最快單次平均時速", value: stats.fastestAvgSpeedKmh > 0 ? String(format: "%.1f km/h", stats.fastestAvgSpeedKmh) : "--", icon: "speedometer", color: .orange)
                        recordRowItem(title: "單趟最長運動時間", value: formattedDuration(stats.longestTimeSeconds), icon: "timer", color: .purple)
                    }
                }
                .padding()
                .background(RoundedRectangle(cornerRadius: 16).fill(.ultraThinMaterial))
                
                // All-Time Distance PRs (1, 5, 10, 50, 100, 300 公里最快)
                VStack(alignment: .leading, spacing: 12) {
                    HStack {
                        Image(systemName: "flag.checkered.circle.fill")
                            .foregroundColor(.yellow)
                            .font(.title3)
                        Text("里程極速榮譽榜 (Distance Bests)")
                            .font(.headline.bold())
                        Spacer()
                        Text("歷史活動自動比對")
                            .font(.caption2)
                            .foregroundColor(.secondary)
                    }
                    
                    let targetDists: [Double] = [1.0, 5.0, 10.0, 50.0, 100.0, 300.0]
                    VStack(spacing: 8) {
                        ForEach(targetDists, id: \.self) { targetKm in
                            let record = store.bestEfforts.first(where: { abs($0.targetDistanceKm - targetKm) < 0.1 })
                            distanceBestRow(targetKm: targetKm, record: record)
                        }
                    }
                }
                .padding()
                .background(RoundedRectangle(cornerRadius: 16).fill(.ultraThinMaterial))
            }
            .padding(16)
        }
    }
    
    private func careerStatCard(title: String, value: String, icon: String, color: Color) -> some View {
        HStack(spacing: 12) {
            Image(systemName: icon)
                .font(.title2)
                .foregroundColor(color)
                .frame(width: 38, height: 38)
                .background(color.opacity(0.15), in: RoundedRectangle(cornerRadius: 10))
            
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.caption)
                    .foregroundColor(.secondary)
                Text(value)
                    .font(.subheadline.bold())
            }
            Spacer()
        }
        .padding(10)
        .background(RoundedRectangle(cornerRadius: 12).fill(Color.secondary.opacity(0.06)))
    }
    

    private func distanceBestRow(targetKm: Double, record: BestEffortRecord?) -> some View {
        HStack(spacing: 12) {
            ZStack {
                Circle()
                    .fill(record != nil ? Color.orange.opacity(0.18) : Color.secondary.opacity(0.1))
                    .frame(width: 40, height: 40)
                Image(systemName: record != nil ? "trophy.fill" : "flag.slash")
                    .font(.subheadline.bold())
                    .foregroundColor(record != nil ? .orange : .secondary)
            }
            
            VStack(alignment: .leading, spacing: 2) {
                Text(targetKm < 1.0 ? "\(Int(targetKm * 1000)) 公尺最快" : "\(Int(targetKm)) 公里最快")
                    .font(.subheadline.bold())
                if let rec = record {
                    Text("\(rec.activityTitle) · \(rec.activityDate.formatted(date: .abbreviated, time: .omitted))")
                        .font(.caption2)
                        .foregroundColor(.secondary)
                        .lineLimit(1)
                } else {
                    Text("尚未達成（單次騎行達 \(Int(targetKm))km 自動比對）")
                        .font(.caption2)
                        .foregroundColor(.secondary)
                }
            }
            
            Spacer()
            
            if let rec = record {
                VStack(alignment: .trailing, spacing: 2) {
                    Text(formattedDuration(rec.bestTimeSeconds))
                        .font(.subheadline.bold())
                        .foregroundColor(.purple)
                    Text(String(format: "%.1f km/h", rec.avgSpeedKmh))
                        .font(.caption2.bold())
                        .foregroundColor(.secondary)
                }
            } else {
                Text("--:--")
                    .font(.subheadline)
                    .foregroundColor(.secondary)
            }
        }
        .padding(10)
        .background(RoundedRectangle(cornerRadius: 12).fill(Color.secondary.opacity(0.06)))
    }

    private func recordRowItem(title: String, value: String, icon: String, color: Color) -> some View {
        HStack {
            Image(systemName: icon)
                .foregroundColor(color)
                .font(.headline)
                .frame(width: 28)
            Text(title)
                .font(.subheadline)
                .foregroundColor(.secondary)
            Spacer()
            Text(value)
                .font(.subheadline.bold())
                .foregroundColor(.primary)
        }
        .padding(.vertical, 4)
    }
    
    // MARK: - Tab 2: Segment PRs List View (Strava-style 路段計時)
    private var segmentPRListView: some View {
        ScrollView {
            VStack(spacing: 16) {
                // Header & Action Bar
                VStack(spacing: 10) {
                    HStack {
                        VStack(alignment: .leading, spacing: 2) {
                            Text("經典爬坡與計時賽段 (Segments)")
                                .font(.headline.bold())
                            Text("每次完成運動將自動比對並記錄個人最佳成績 (PR)")
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
                        Spacer()
                    }
                    
                    HStack(spacing: 8) {
                        // Recalculate PRs Button
                        Button {
                            store.recalculateAllSegmentPRs()
                            recalculateAlertMessage = "🎉 已成功校正並重新比對所有路段 PR 紀錄！"
                            showRecalculateAlert = true
                        } label: {
                            HStack(spacing: 4) {
                                Image(systemName: "arrow.triangle.2.circlepath")
                                Text("校正比對")
                            }
                            .font(.caption.bold())
                        }
                        .buttonStyle(.bordered)
                        .controlSize(.small)
                        
                        // AI Auto Discover Segments from History Button
                        Button {
                            let count = store.autoDiscoverSegmentsFromHistory()
                            if count > 0 {
                                restoreDefaultMessage = "🎉 已成功從您的歷史活動中探勘出 \(count) 個經典挑戰路段，並已自動結算歷代 PR 紀錄！"
                            } else {
                                restoreDefaultMessage = "已掃描歷史活動，未發現新的代表性爬坡段（爬升>75m、長度>1.5km），或已有對應路段存在。"
                            }
                            showRestoreDefaultAlert = true
                        } label: {
                            HStack(spacing: 4) {
                                Image(systemName: "sparkles")
                                Text("AI 探勘歷史路段")
                            }
                            .font(.caption)
                        }
                        .buttonStyle(.bordered)
                        .controlSize(.small)
                        
                        // Restore Default Segments Button
                        Button {
                            let count = store.restoreDefaultSegments()
                            if count > 0 {
                                restoreDefaultMessage = "🎉 已成功為您恢復 \(count) 個預設經典路段（風櫃嘴、冷水坑、中社路、巴拉卡公路）！"
                            } else {
                                restoreDefaultMessage = "系統預設的 4 個經典路段均已在清單中，無缺失項目。"
                            }
                            showRestoreDefaultAlert = true
                        } label: {
                            HStack(spacing: 4) {
                                Image(systemName: "arrow.counterclockwise")
                                Text("恢復經典預設")
                            }
                            .font(.caption)
                        }
                        .buttonStyle(.bordered)
                        .controlSize(.small)
                        
                        Spacer()
                        
                        // Add Custom Segment Button
                        Button {
                            showAddSegmentSheet = true
                        } label: {
                            HStack(spacing: 4) {
                                Image(systemName: "plus.circle.fill")
                                Text("新增路段")
                            }
                            .font(.caption.bold())
                        }
                        .buttonStyle(.borderedProminent)
                        .controlSize(.small)
                    }
                }
                .padding(.horizontal, 16)
                .padding(.top, 8)
                
                if store.activeSegments.isEmpty {
                    VStack(spacing: 12) {
                        Image(systemName: "flag.slash")
                            .font(.system(size: 40))
                            .foregroundColor(.secondary)
                        Text("目前尚無計時路段")
                            .font(.headline)
                        Text("您可以點擊上方「恢復經典預設」，或自訂屬於自己的爬坡路段。")
                            .font(.caption)
                            .foregroundColor(.secondary)
                            .multilineTextAlignment(.center)
                        Button("一鍵恢復預設經典路段") {
                            store.restoreDefaultSegments()
                        }
                        .buttonStyle(.borderedProminent)
                    }
                    .padding(32)
                } else {
                    ForEach(store.activeSegments) { seg in
                        segmentCard(seg)
                    }
                }
            }
            .padding(.bottom, 60)
        }
    }
    
    private func segmentCard(_ seg: SegmentRecord) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 4) {
                    Text(seg.name)
                        .font(.subheadline.bold())
                        .foregroundColor(.primary)
                    
                    HStack(spacing: 12) {
                        Text("\(String(format: "%.1f", seg.distanceKm)) km")
                        Text("爬升 \(Int(seg.elevationGainMeters)) m")
                        Text("均坡 \(String(format: "%.1f%%", seg.avgGradientPercent))")
                    }
                    .font(.caption)
                    .foregroundColor(.secondary)
                }
                
                Spacer()
                
                // PR Medal Badge
                if let pr = seg.personalRecordSeconds {
                    VStack(alignment: .trailing, spacing: 2) {
                        HStack(spacing: 3) {
                            Image(systemName: "medal.fill")
                                .foregroundColor(.yellow)
                            Text("個人最佳 PR")
                                .font(.system(size: 10, weight: .bold))
                                .foregroundColor(.orange)
                        }
                        Text(formattedDuration(pr))
                            .font(.subheadline.bold())
                            .foregroundColor(.purple)
                        let prSpeed = seg.distanceKm / (pr / 3600.0)
                        Text(String(format: "%.1f km/h", prSpeed))
                            .font(.system(size: 9))
                            .foregroundColor(.secondary)
                    }
                    .padding(6)
                    .background(Color.yellow.opacity(0.12), in: RoundedRectangle(cornerRadius: 8))
                } else {
                    Text("尚未挑戰")
                        .font(.caption2)
                        .foregroundColor(.secondary)
                        .padding(6)
                        .background(Color.secondary.opacity(0.1), in: RoundedRectangle(cornerRadius: 8))
                }
                
                // Delete Segment Button
                Button(role: .destructive) {
                    segmentToDelete = seg
                    showDeleteSegmentConfirm = true
                } label: {
                    Image(systemName: "trash")
                        .font(.system(size: 13))
                        .foregroundColor(.secondary)
                        .padding(7)
                        .background(Color.secondary.opacity(0.12), in: Circle())
                }
                .buttonStyle(.plain)
            }
            
            Divider()
            
            HStack {
                Text("累計挑戰次數: \(seg.attemptCount) 次")
                    .font(.caption2)
                    .foregroundColor(.secondary)
                
                Spacer()
                
                if let latest = seg.latestAttemptSeconds {
                    Text("最近一次用時: \(formattedDuration(latest))")
                        .font(.caption2.bold())
                        .foregroundColor(.secondary)
                }
            }
        }
        .padding(14)
        .background(RoundedRectangle(cornerRadius: 14).fill(.ultraThinMaterial))
        .padding(.horizontal, 16)
        .shadow(color: .black.opacity(0.04), radius: 3, y: 1)
    }
    
    // MARK: - Add Custom Segment Sheet
    @State private var newSegName: String = ""
    @State private var newSegDistText: String = "5.0"
    @State private var newSegClimbText: String = "250"
    @State private var newSegGradeText: String = "5.0"
    
    private var addCustomSegmentSheet: some View {
        NavigationStack {
            Form {
                Section(header: Text("自訂路段基本資料")) {
                    TextField("路段名稱 (例: 劍中劍挑戰段)", text: $newSegName)
                    TextField("距離 (公里)", text: $newSegDistText)
                        #if os(iOS)
                        .keyboardType(.decimalPad)
                        #endif
                    TextField("累積爬升 (公尺)", text: $newSegClimbText)
                        #if os(iOS)
                        .keyboardType(.numberPad)
                        #endif
                    TextField("平均坡度 (%)", text: $newSegGradeText)
                        #if os(iOS)
                        .keyboardType(.decimalPad)
                        #endif
                }
            }
            .navigationTitle("建立新路段")
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("取消") { showAddSegmentSheet = false }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("儲存") {
                        let dist = max(0.1, Double(newSegDistText) ?? 5.0)
                        let climb = max(0.0, Double(newSegClimbText) ?? 250.0)
                        let grade = Double(newSegGradeText) ?? 5.0
                        let title = newSegName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                            ? "自訂路段 (\(String(format: "%.1f", dist)) km)"
                            : newSegName
                        store.addCustomSegment(name: title, distanceKm: dist, elevationGain: climb, avgGradient: grade)
                        showAddSegmentSheet = false
                    }
                    .disabled(newSegName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
            }
        }
    }
    
    // MARK: - Empty State View
    private var emptyStateView: some View {
        VStack(spacing: 16) {
            Image(systemName: "figure.outdoor.cycle")
                .font(.system(size: 64))
                .foregroundColor(.secondary.opacity(0.6))
            
            Text("尚無已儲存的活動記錄")
                .font(.title3.bold())
            
            Text("前往「即時記錄」開啟導航並記錄您的戶外騎行或健行。\n或從其他運動 App 匯入過往的 GPX 軌跡紀錄，系統將自動比對經典路段並建立個人榮譽榜！")
                .font(.subheadline)
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 32)
            
            Button {
                showFileImporter = true
            } label: {
                HStack(spacing: 8) {
                    Image(systemName: "square.and.arrow.down.fill")
                    Text("匯入其他 App 的 GPX 紀錄")
                }
                .font(.subheadline.bold())
                .foregroundColor(.white)
                .padding(.horizontal, 20)
                .padding(.vertical, 12)
                .background(Color.purple, in: RoundedRectangle(cornerRadius: 12))
            }
            .buttonStyle(.plain)
            .padding(.top, 8)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
    
    // MARK: - Activity Row Card
    private func activityRowCard(_ act: SavedActivity) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    HStack(spacing: 6) {
                        Text(act.title)
                            .font(.headline.bold())
                        
                        // New PR Badge on card if broken any record
                        if act.segmentEfforts.contains(where: { $0.isPR }) {
                            HStack(spacing: 2) {
                                Image(systemName: "medal.fill")
                                Text("新 PR")
                            }
                            .font(.system(size: 9, weight: .bold))
                            .padding(.horizontal, 5)
                            .padding(.vertical, 2)
                            .background(Color.yellow, in: Capsule())
                            .foregroundColor(.black)
                        }
                    }
                    
                    Text(act.date.formatted(date: .abbreviated, time: .shortened))
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                
                Spacer()
                
                // Fast 3D & Share shortcuts
                HStack(spacing: 8) {
                    Button {
                        selectedActivityFor3D = act
                    } label: {
                        Image(systemName: "video.fill")
                            .font(.caption.bold())
                            .foregroundColor(.orange)
                            .padding(8)
                            .background(Color.orange.opacity(0.15), in: Circle())
                    }
                    .buttonStyle(.plain)
                    
                    Button {
                        selectedActivityForShare = act
                    } label: {
                        Image(systemName: "square.and.arrow.up.fill")
                            .font(.caption.bold())
                            .foregroundColor(.blue)
                            .padding(8)
                            .background(Color.blue.opacity(0.15), in: Circle())
                    }
                    .buttonStyle(.plain)
                }
            }
            
            if !act.note.isEmpty {
                Text(act.note)
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .lineLimit(2)
            }
            
            // Photo Thumbnail strip if photos attached
            if !act.photoDataList.isEmpty {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 6) {
                        ForEach(Array(act.photoDataList.prefix(4).enumerated()), id: \.offset) { _, data in
                            #if os(macOS)
                            if let nsImage = NSImage(data: data) {
                                Image(nsImage: nsImage)
                                    .resizable()
                                    .scaledToFill()
                                    .frame(width: 54, height: 54)
                                    .clipShape(RoundedRectangle(cornerRadius: 8))
                            }
                            #else
                            if let uiImage = UIImage(data: data) {
                                Image(uiImage: uiImage)
                                    .resizable()
                                    .scaledToFill()
                                    .frame(width: 54, height: 54)
                                    .clipShape(RoundedRectangle(cornerRadius: 8))
                            }
                            #endif
                        }
                    }
                }
            }
            
            Divider()
            
            // Key Metrics
            HStack(spacing: 16) {
                metricItem(title: "距離", value: String(format: "%.2f km", act.distanceKm))
                metricItem(title: "時間", value: formattedDuration(act.effectiveMovingDuration))
                metricItem(title: "均速", value: String(format: "%.1f km/h", act.avgSpeedKmh))
                metricItem(title: "爬升", value: "\(Int(act.totalAscentMeters)) m")
            }
        }
        .padding(14)
        .background(RoundedRectangle(cornerRadius: 14).fill(.ultraThinMaterial))
        .shadow(color: .black.opacity(0.08), radius: 4, y: 2)
    }
    
    private func metricItem(title: String, value: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(title)
                .font(.system(size: 10))
                .foregroundColor(.secondary)
            Text(value)
                .font(.caption.bold())
        }
    }
    
    // MARK: - Activity Detail Sheet
    private func activityDetailSheet(_ act: SavedActivity) -> some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    // Title & Date
                    VStack(alignment: .leading, spacing: 4) {
                        Text(act.title)
                            .font(.title2.bold())
                        Text(act.date.formatted(date: .complete, time: .shortened))
                            .font(.subheadline)
                            .foregroundColor(.secondary)
                    }
                    
                    // Action Buttons (3D Playback & Transparent Share Card)
                    HStack(spacing: 12) {
                        Button {
                            let target = act
                            selectedDetailActivity = nil
                            DispatchQueue.main.asyncAfter(deadline: .now() + 0.28) {
                                selectedActivityFor3D = target
                            }
                        } label: {
                            HStack {
                                Image(systemName: "video.fill")
                                Text("3D 路線重播")
                            }
                            .font(.headline.bold())
                            .foregroundColor(.white)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 12)
                            .background(Color.orange, in: RoundedRectangle(cornerRadius: 12))
                        }
                        .buttonStyle(.plain)
                        
                        Button {
                            let target = act
                            selectedDetailActivity = nil
                            DispatchQueue.main.asyncAfter(deadline: .now() + 0.28) {
                                selectedActivityForShare = target
                            }
                        } label: {
                            HStack {
                                Image(systemName: "square.and.arrow.up.fill")
                                Text("分享")
                            }
                            .font(.headline.bold())
                            .foregroundColor(.white)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 12)
                            .background(Color.blue, in: RoundedRectangle(cornerRadius: 12))
                        }
                        .buttonStyle(.plain)
                    }
                    
                    // Extra Quick Route & Segment Tools
                    VStack(spacing: 10) {
                        // Load into Route Navigation
                        if let loadHandler = onLoadRouteToNavigation {
                            Button {
                                loadHandler(act.track)
                                selectedDetailActivity = nil
                            } label: {
                                HStack {
                                    Image(systemName: "map.fill")
                                    Text("載入至「地圖導航」作為未來規劃路線")
                                }
                                .font(.subheadline.bold())
                                .foregroundColor(.blue)
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 10)
                                .background(Color.blue.opacity(0.12), in: RoundedRectangle(cornerRadius: 10))
                            }
                            .buttonStyle(.plain)
                        }
                        
                        // Create Segment from this Activity
                        Button {
                            if let newSeg = store.createSegment(from: act) {
                                segmentCreatedAlertMessage = "🎉 已成功將「\(act.title)」建立為新挑戰路段「\(newSeg.name)」！\n\n• 里程：\(String(format: "%.1f", newSeg.distanceKm)) km\n• 爬升：\(Int(newSeg.elevationGainMeters)) m\n• 個人最佳 PR：\(formattedDuration(newSeg.personalRecordSeconds ?? 0))\n\n未來只要有騎行經過此路線，App 都會自動比對並記錄 PR！"
                                showSegmentCreatedAlert = true
                            }
                        } label: {
                            HStack {
                                Image(systemName: "plus.diamond.fill")
                                Text("以此路線建立挑戰路段 (PR)")
                            }
                            .font(.subheadline.bold())
                            .foregroundColor(.orange)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 10)
                            .background(Color.orange.opacity(0.12), in: RoundedRectangle(cornerRadius: 10))
                        }
                        .buttonStyle(.plain)
                    }
                    
                    // Native GPX File Export ShareLink (Strava / Velodash 相容)
                    if let gpxURL = store.exportGPXFile(for: act) {
                        HStack(spacing: 10) {
                            ShareLink(item: gpxURL) {
                                HStack(spacing: 6) {
                                    Image(systemName: "arrow.triangle.swap")
                                    Text("匯出至 Strava / Velodash (GPX)")
                                }
                                .font(.subheadline.bold())
                                .foregroundColor(.white)
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 10)
                                .background(Color(red: 0.99, green: 0.35, blue: 0.08), in: RoundedRectangle(cornerRadius: 10))
                            }
                        }
                    }
                    
                    // Soft Delete Activity Button (移至最近刪除，保留 90 天)
                    Button(role: .destructive) {
                        store.softDeleteActivity(id: act.id)
                        lastDeletedActivityTitle = act.title
                        lastDeletedActivityId = act.id
                        selectedDetailActivity = nil
                        withAnimation {
                            showActivityDeletedToast = true
                        }
                    } label: {
                        HStack(spacing: 6) {
                            Image(systemName: "trash")
                            Text("刪除此活動 (移至最近刪除，保留 3 個月)")
                        }
                        .font(.subheadline.bold())
                        .foregroundColor(.red)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 10)
                        .background(Color.red.opacity(0.1), in: RoundedRectangle(cornerRadius: 10))
                    }
                    .buttonStyle(.plain)
                    
                    // Segment Efforts Section (Strava-style PRs)
                    if !act.segmentEfforts.isEmpty {
                        VStack(alignment: .leading, spacing: 8) {
                            HStack {
                                Image(systemName: "flag.checkered")
                                    .foregroundColor(.orange)
                                Text("本次挑戰路段成績 (Segment Efforts)")
                                    .font(.headline)
                            }
                            
                            VStack(spacing: 8) {
                                ForEach(act.segmentEfforts) { effort in
                                    HStack {
                                        VStack(alignment: .leading, spacing: 2) {
                                            HStack(spacing: 6) {
                                                Text(effort.segmentName)
                                                    .font(.subheadline.bold())
                                                
                                                if effort.isPR {
                                                    HStack(spacing: 2) {
                                                        Image(systemName: "medal.fill")
                                                        Text("新 PR!")
                                                    }
                                                    .font(.system(size: 9, weight: .bold))
                                                    .padding(.horizontal, 5)
                                                    .padding(.vertical, 2)
                                                    .background(Color.yellow, in: Capsule())
                                                    .foregroundColor(.black)
                                                }
                                            }
                                            
                                            Text("\(String(format: "%.1f", effort.distanceKm)) km · 爬升 \(Int(effort.elevationGainMeters)) m · 坡度 \(String(format: "%.1f%%", effort.avgGradientPercent))")
                                                .font(.caption2)
                                                .foregroundColor(.secondary)
                                        }
                                        
                                        Spacer()
                                        
                                        VStack(alignment: .trailing, spacing: 2) {
                                            Text(formattedDuration(effort.timeSeconds))
                                                .font(.subheadline.bold())
                                                .foregroundColor(effort.isPR ? .purple : .primary)
                                            Text(String(format: "%.1f km/h", effort.avgSpeedKmh))
                                                .font(.caption)
                                                .foregroundColor(.secondary)
                                        }
                                    }
                                    .padding(10)
                                    .background(RoundedRectangle(cornerRadius: 10).fill(Color.secondary.opacity(0.06)))
                                }
                            }
                        }
                    }
                    
                    // Route Polyline Map
                    if act.track.points.count > 1 {
                        Map {
                            MapPolyline(coordinates: act.track.points.map(\.coordinate))
                                .stroke(Color.blue, lineWidth: 5)
                            
                            if let first = act.track.points.first {
                                Annotation("起點", coordinate: first.coordinate) {
                                    Image(systemName: "flag.circle.fill")
                                        .foregroundColor(.green)
                                        .background(Circle().fill(.white))
                                }
                            }
                            if let last = act.track.points.last {
                                Annotation("終點", coordinate: last.coordinate) {
                                    Image(systemName: "trophy.circle.fill")
                                        .foregroundColor(.red)
                                        .background(Circle().fill(.white))
                                }
                            }
                        }
                        .frame(height: 220)
                        .clipShape(RoundedRectangle(cornerRadius: 14))
                    }
                    
                    // Real Multi-Metric Profile Charts (Elevation, Gradient, Speed, Cadence, HR, Power)
                    if act.track.points.count > 1 {
                        detailedMultiMetricCharts(act)
                    }
                    
                    // Note / Story
                    if !act.note.isEmpty {
                        VStack(alignment: .leading, spacing: 6) {
                            Text("心得與描述")
                                .font(.headline)
                            Text(act.note)
                                .font(.body)
                                .padding(12)
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .background(RoundedRectangle(cornerRadius: 10).fill(Color.secondary.opacity(0.08)))
                        }
                    }
                    
                    // Metrics Grid
                    VStack(alignment: .leading, spacing: 10) {
                        Text("運動統計數據")
                            .font(.headline)
                        
                        LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 12) {
                            detailMetricBox(title: "總里程", value: String(format: "%.2f km", act.distanceKm))
                            detailMetricBox(title: "運動時間", value: formattedDuration(act.effectiveMovingDuration))
                            detailMetricBox(title: "總歷時 (含紅綠燈)", value: formattedDuration(act.durationSeconds))
                            detailMetricBox(title: "運動均速", value: String(format: "%.1f km/h", act.avgSpeedKmh))
                            detailMetricBox(title: "最高時速", value: String(format: "%.1f km/h", act.maxSpeedKmh))
                            detailMetricBox(title: "累計爬升", value: "\(Int(act.totalAscentMeters)) m")
                            detailMetricBox(title: "平均心率", value: act.avgHeartRateBpm != nil ? "\(act.avgHeartRateBpm!) bpm" : "--")
                            detailMetricBox(title: "平均踏頻", value: act.avgCadenceRpm != nil ? "\(act.avgCadenceRpm!) rpm" : "--")
                            detailMetricBox(title: "平均功率", value: act.avgPowerWatts != nil ? "\(act.avgPowerWatts!) W" : "--")
                            detailMetricBox(title: "最大功率", value: act.maxPowerWatts != nil ? "\(act.maxPowerWatts!) W" : "--")
                        }
                    }
                    
                    // Photos
                    if !act.photoDataList.isEmpty {
                        VStack(alignment: .leading, spacing: 8) {
                            Text("活動照片 (共 \(act.photoDataList.count) 張)")
                                .font(.headline)
                            
                            ScrollView(.horizontal, showsIndicators: false) {
                                HStack(spacing: 10) {
                                    ForEach(Array(act.photoDataList.enumerated()), id: \.offset) { _, data in
                                        #if os(macOS)
                                        if let nsImage = NSImage(data: data) {
                                            Image(nsImage: nsImage)
                                                .resizable()
                                                .scaledToFill()
                                                .frame(width: 140, height: 140)
                                                .clipShape(RoundedRectangle(cornerRadius: 12))
                                        }
                                        #else
                                        if let uiImage = UIImage(data: data) {
                                            Image(uiImage: uiImage)
                                                .resizable()
                                                .scaledToFill()
                                                .frame(width: 140, height: 140)
                                                .clipShape(RoundedRectangle(cornerRadius: 12))
                                        }
                                        #endif
                                    }
                                }
                            }
                        }
                    }
                }
                .padding()
            }
            .navigationTitle("活動詳細內容")
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("關閉") { selectedDetailActivity = nil }
                }
            }
        }
    }
    
    private func detailMetricBox(title: String, value: String) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title)
                .font(.caption)
                .foregroundColor(.secondary)
            Text(value)
                .font(.title3.bold())
        }
        .padding(10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: 10).fill(Color.secondary.opacity(0.08)))
    }
    
    private func formattedDuration(_ seconds: TimeInterval) -> String {
        let s = Int(seconds)
        let hrs = s / 3600
        let mins = (s % 3600) / 60
        let secs = s % 60
        if hrs > 0 {
            return String(format: "%d小時%02d分%02d秒", hrs, mins, secs)
        } else {
            return String(format: "%02d分%02d秒", mins, secs)
        }
    }
    
    // MARK: - Recently Deleted Management Sheet (保留 90 天 / 3 個月，支援恢復與自動永久銷毀)
    private var recentlyDeletedManagementSheet: some View {
        NavigationStack {
            VStack(spacing: 12) {
                // Warning / Retention Notice Banner (醒目備註通知)
                VStack(alignment: .leading, spacing: 6) {
                    HStack(spacing: 6) {
                        Image(systemName: "exclamationmark.shield.fill")
                            .foregroundColor(.orange)
                        Text("⚠️ 備註說明：90 天自動清理機制")
                            .font(.subheadline.bold())
                            .foregroundColor(.primary)
                    }
                    Text("您刪除的過往活動與路段最佳（PR）將安全保留 90 天（3 個月）。在此期間內，您可以隨時一鍵「恢復」。超過 90 天後，系統將自動永久銷毀以釋放儲存空間並保障隱私。")
                        .font(.caption)
                        .foregroundColor(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .padding(12)
                .background(Color.orange.opacity(0.12), in: RoundedRectangle(cornerRadius: 12))
                .padding(.horizontal)
                .padding(.top, 8)
                
                // Segmented Tab (已刪除活動 vs 已刪除路段)
                Picker("", selection: $deletedItemsTab) {
                    Text("已刪除活動 (\(store.deletedActivities.count))").tag(0)
                    Text("已刪除路段 (\(store.deletedSegments.count))").tag(1)
                }
                .pickerStyle(.segmented)
                .padding(.horizontal)
                
                if deletedItemsTab == 0 {
                    // 已刪除活動列表
                    if store.deletedActivities.isEmpty {
                        VStack(spacing: 12) {
                            Spacer()
                            Image(systemName: "trash.slash")
                                .font(.system(size: 48))
                                .foregroundColor(.secondary)
                            Text("沒有已刪除的活動")
                                .font(.headline)
                                .foregroundColor(.secondary)
                            Text("所有刪除的活動將在此處暫存 90 天")
                                .font(.caption)
                                .foregroundColor(.secondary.opacity(0.8))
                            Spacer()
                        }
                    } else {
                        List {
                            ForEach(store.deletedActivities) { act in
                                VStack(alignment: .leading, spacing: 8) {
                                    HStack(alignment: .top) {
                                        VStack(alignment: .leading, spacing: 3) {
                                            Text(act.title)
                                                .font(.headline)
                                                .foregroundColor(.primary)
                                            Text(act.date.formatted(date: .abbreviated, time: .shortened))
                                                .font(.caption)
                                                .foregroundColor(.secondary)
                                        }
                                        Spacer()
                                        
                                        // 剩餘天數標籤
                                        HStack(spacing: 3) {
                                            Image(systemName: "hourglass")
                                            Text("剩餘 \(act.remainingDaysBeforePermanentDelete) 天")
                                        }
                                        .font(.caption2.bold())
                                        .padding(.horizontal, 8)
                                        .padding(.vertical, 4)
                                        .background(Color.orange.opacity(0.15), in: Capsule())
                                        .foregroundColor(.orange)
                                    }
                                    
                                    HStack {
                                        Text("\(String(format: "%.1f", act.distanceKm)) km · \(formattedDuration(act.durationSeconds)) · 爬升 \(Int(act.totalAscentMeters)) m")
                                            .font(.caption2)
                                            .foregroundColor(.secondary)
                                        Spacer()
                                        
                                        // 恢復按鈕
                                        Button {
                                            withAnimation {
                                                store.restoreActivity(id: act.id)
                                            }
                                        } label: {
                                            HStack(spacing: 4) {
                                                Image(systemName: "arrow.uturn.backward.circle.fill")
                                                Text("恢復")
                                            }
                                            .font(.caption.bold())
                                            .foregroundColor(.green)
                                            .padding(.horizontal, 10)
                                            .padding(.vertical, 5)
                                            .background(Color.green.opacity(0.12), in: Capsule())
                                        }
                                        .buttonStyle(.plain)
                                        
                                        // 永久刪除按鈕
                                        Button(role: .destructive) {
                                            withAnimation {
                                                store.permanentlyDeleteActivity(id: act.id)
                                            }
                                        } label: {
                                            Image(systemName: "trash")
                                                .font(.caption)
                                                .foregroundColor(.red)
                                                .padding(6)
                                                .background(Color.red.opacity(0.1), in: Circle())
                                        }
                                        .buttonStyle(.plain)
                                    }
                                }
                                .padding(.vertical, 4)
                            }
                        }
                        .listStyle(.insetGrouped)
                    }
                } else {
                    // 已刪除路段列表
                    if store.deletedSegments.isEmpty {
                        VStack(spacing: 12) {
                            Spacer()
                            Image(systemName: "flag.slash")
                                .font(.system(size: 48))
                                .foregroundColor(.secondary)
                            Text("沒有已刪除的路段")
                                .font(.headline)
                                .foregroundColor(.secondary)
                            Text("所有刪除的路段將在此處暫存 90 天")
                                .font(.caption)
                                .foregroundColor(.secondary.opacity(0.8))
                            Spacer()
                        }
                    } else {
                        List {
                            ForEach(store.deletedSegments) { seg in
                                VStack(alignment: .leading, spacing: 8) {
                                    HStack(alignment: .top) {
                                        VStack(alignment: .leading, spacing: 3) {
                                            Text(seg.name)
                                                .font(.headline)
                                                .foregroundColor(.primary)
                                            Text("\(String(format: "%.1f", seg.distanceKm)) km · 爬升 \(Int(seg.elevationGainMeters)) m · 坡度 \(String(format: "%.1f%%", seg.avgGradientPercent))")
                                                .font(.caption)
                                                .foregroundColor(.secondary)
                                        }
                                        Spacer()
                                        
                                        // 剩餘天數標籤
                                        HStack(spacing: 3) {
                                            Image(systemName: "hourglass")
                                            Text("剩餘 \(seg.remainingDaysBeforePermanentDelete) 天")
                                        }
                                        .font(.caption2.bold())
                                        .padding(.horizontal, 8)
                                        .padding(.vertical, 4)
                                        .background(Color.orange.opacity(0.15), in: Capsule())
                                        .foregroundColor(.orange)
                                    }
                                    
                                    HStack {
                                        if let pr = seg.personalRecordSeconds {
                                            Text("歷史最佳 PR: \(formattedDuration(pr))")
                                                .font(.caption2.bold())
                                                .foregroundColor(.purple)
                                        } else {
                                            Text("尚未建立 PR")
                                                .font(.caption2)
                                                .foregroundColor(.secondary)
                                        }
                                        Spacer()
                                        
                                        // 恢復按鈕
                                        Button {
                                            withAnimation {
                                                store.restoreSegment(id: seg.id)
                                            }
                                        } label: {
                                            HStack(spacing: 4) {
                                                Image(systemName: "arrow.uturn.backward.circle.fill")
                                                Text("恢復")
                                            }
                                            .font(.caption.bold())
                                            .foregroundColor(.green)
                                            .padding(.horizontal, 10)
                                            .padding(.vertical, 5)
                                            .background(Color.green.opacity(0.12), in: Capsule())
                                        }
                                        .buttonStyle(.plain)
                                        
                                        // 永久刪除按鈕
                                        Button(role: .destructive) {
                                            withAnimation {
                                                store.permanentlyDeleteSegment(id: seg.id)
                                            }
                                        } label: {
                                            Image(systemName: "trash")
                                                .font(.caption)
                                                .foregroundColor(.red)
                                                .padding(6)
                                                .background(Color.red.opacity(0.1), in: Circle())
                                        }
                                        .buttonStyle(.plain)
                                    }
                                }
                                .padding(.vertical, 4)
                            }
                        }
                        .listStyle(.insetGrouped)
                    }
                }
            }
            .navigationTitle("最近刪除 (保留90天)")
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    if (deletedItemsTab == 0 && !store.deletedActivities.isEmpty) || (deletedItemsTab == 1 && !store.deletedSegments.isEmpty) {
                        Button("清空此回收筒", role: .destructive) {
                            showEmptyTrashConfirm = true
                        }
                        .foregroundColor(.red)
                    }
                }
                
                ToolbarItem(placement: .confirmationAction) {
                    Button("完成") {
                        showRecentlyDeletedSheet = false
                    }
                }
            }
            .confirmationDialog("確定清空回收筒？", isPresented: $showEmptyTrashConfirm, titleVisibility: .visible) {
                Button("永久刪除所有項目", role: .destructive) {
                    if deletedItemsTab == 0 {
                        store.emptyTrashActivities()
                    } else {
                        store.emptyTrashSegments()
                    }
                }
                Button("取消", role: .cancel) {}
            } message: {
                Text("此操作將立即永久刪除所有回收筒中的項目，無法再恢復。")
            }
        }
    }

    // MARK: - Multi-Metric Profile Charts (真實 GPS 空間幾何與感測器數據)
    @ViewBuilder
    private func detailedMultiMetricCharts(_ act: SavedActivity) -> some View {
        let samples = buildChartSamples(from: act.track.points)
        if !samples.isEmpty {
            VStack(alignment: .leading, spacing: 14) {
                HStack(spacing: 6) {
                    Image(systemName: "chart.xyaxis.line")
                        .foregroundColor(.blue)
                    Text("多元運動趨勢圖表")
                        .font(.headline)
                }
                
                // 1. 海拔高度剖面圖
                chartCard(title: "海拔高度變化 (m)", icon: "mountain.2.fill", tint: .blue) {
                    Chart(samples) { s in
                        AreaMark(
                            x: .value("距離 (km)", s.distKm),
                            y: .value("海拔", s.elevation)
                        )
                        .foregroundStyle(
                            LinearGradient(
                                colors: [Color.blue.opacity(0.6), Color.cyan.opacity(0.1)],
                                startPoint: .top,
                                endPoint: .bottom
                            )
                        )
                        LineMark(
                            x: .value("距離 (km)", s.distKm),
                            y: .value("海拔", s.elevation)
                        )
                        .foregroundStyle(Color.blue)
                        .lineStyle(StrokeStyle(lineWidth: 2))
                    }
                    .chartYScale(domain: max(0, (samples.map(\.elevation).min() ?? 0) - 15) ... (samples.map(\.elevation).max() ?? 100) + 20)
                }
                
                // 2. 坡度變化圖
                chartCard(title: "路段坡度變化 (%)", icon: "triangle.fill", tint: .orange) {
                    Chart(samples) { s in
                        LineMark(
                            x: .value("距離 (km)", s.distKm),
                            y: .value("坡度", s.gradient)
                        )
                        .foregroundStyle(Color.orange)
                        .lineStyle(StrokeStyle(lineWidth: 2))
                        
                        RuleMark(y: .value("水平基準線", 0.0))
                            .lineStyle(StrokeStyle(lineWidth: 1, dash: [4, 4]))
                            .foregroundStyle(Color.secondary.opacity(0.4))
                    }
                }
                
                // 3. 即時速度圖
                chartCard(title: "即時時速變化 (km/h)", icon: "speedometer", tint: .yellow) {
                    Chart(samples) { s in
                        LineMark(
                            x: .value("距離 (km)", s.distKm),
                            y: .value("時速", s.speedKmh)
                        )
                        .foregroundStyle(Color.yellow)
                        .lineStyle(StrokeStyle(lineWidth: 2))
                    }
                }
                
                // 4. 踏頻變化圖 (若有感測器數據)
                if samples.contains(where: { ($0.cadence ?? 0.0) > 0.0 }) {
                    chartCard(title: "踏頻節奏變化 (RPM)", icon: "arrow.triangle.2.circlepath", tint: .green) {
                        Chart(samples.filter { $0.cadence != nil }) { s in
                            LineMark(
                                x: .value("距離 (km)", s.distKm),
                                y: .value("踏頻", s.cadence ?? 0.0)
                            )
                            .foregroundStyle(Color.green)
                            .lineStyle(StrokeStyle(lineWidth: 2))
                        }
                    }
                }
                
                // 5. 心率變化圖 (若有感測器數據)
                if samples.contains(where: { ($0.heartRate ?? 0.0) > 0.0 }) {
                    chartCard(title: "心率脈搏變化 (BPM)", icon: "heart.fill", tint: .red) {
                        Chart(samples.filter { $0.heartRate != nil }) { s in
                            LineMark(
                                x: .value("距離 (km)", s.distKm),
                                y: .value("心率", s.heartRate ?? 0.0)
                            )
                            .foregroundStyle(Color.red)
                            .lineStyle(StrokeStyle(lineWidth: 2))
                        }
                    }
                }
                
                // 6. 功率變化圖 (若有感測器數據)
                if samples.contains(where: { ($0.power ?? 0.0) > 0.0 }) {
                    chartCard(title: "輸出功率變化 (Watts)", icon: "bolt.fill", tint: .purple) {
                        Chart(samples.filter { $0.power != nil }) { s in
                            AreaMark(
                                x: .value("距離 (km)", s.distKm),
                                y: .value("功率", s.power ?? 0.0)
                            )
                            .foregroundStyle(Color.purple.opacity(0.35))
                            LineMark(
                                x: .value("距離 (km)", s.distKm),
                                y: .value("功率", s.power ?? 0.0)
                            )
                            .foregroundStyle(Color.purple)
                            .lineStyle(StrokeStyle(lineWidth: 2))
                        }
                    }
                }
            }
        }
    }
    
    private func chartCard<Content: View>(title: String, icon: String, tint: Color, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 6) {
                Image(systemName: icon)
                    .foregroundColor(tint)
                    .font(.caption.bold())
                Text(title)
                    .font(.subheadline.bold())
            }
            content()
                .frame(height: 130)
        }
        .padding(12)
        .background(RoundedRectangle(cornerRadius: 12).fill(Color.secondary.opacity(0.06)))
    }
    
    private func buildChartSamples(from points: [RoutePoint]) -> [ActivityChartSample] {
        guard points.count >= 2 else { return [] }
        let cumDists = calculateCumulativeDistances(points)
        let totalCount = points.count
        let step = max(1, totalCount / 60)
        
        var samples: [ActivityChartSample] = []
        var id = 0
        for i in stride(from: 0, to: totalCount, by: step) {
            let p0 = points[i]
            let distKm = cumDists[i]
            let nextIdx = min(i + 1, totalCount - 1)
            let pNext = points[nextIdx]
            let dLoc = CLLocation(latitude: p0.latitude, longitude: p0.longitude)
                .distance(from: CLLocation(latitude: pNext.latitude, longitude: pNext.longitude))
            let grad = (dLoc > 5.0) ? ((pNext.elevation - p0.elevation) / dLoc) * 100.0 : 0.0
            
            samples.append(ActivityChartSample(
                id: id,
                distKm: distKm,
                elevation: p0.elevation,
                gradient: min(25.0, max(-25.0, grad)),
                speedKmh: p0.speedKmh ?? 0.0,
                cadence: p0.cadence != nil ? Double(p0.cadence!) : nil,
                heartRate: p0.heartRate != nil ? Double(p0.heartRate!) : nil,
                power: p0.powerWatts != nil ? Double(p0.powerWatts!) : nil
            ))
            id += 1
        }
        return samples
    }
    
    private func calculateCumulativeDistances(_ points: [RoutePoint]) -> [Double] {
        var dists = [0.0]
        var total = 0.0
        for i in 1..<points.count {
            let p0 = points[i-1]
            let p1 = points[i]
            let d = CLLocation(latitude: p0.latitude, longitude: p0.longitude)
                .distance(from: CLLocation(latitude: p1.latitude, longitude: p1.longitude)) / 1000.0
            total += d
            dists.append(total)
        }
        return dists
    }
}

public struct ActivityChartSample: Identifiable {
    public let id: Int
    public let distKm: Double
    public let elevation: Double
    public let gradient: Double
    public let speedKmh: Double
    public let cadence: Double?
    public let heartRate: Double?
    public let power: Double?
}


// MARK: - Segment Detail Interactive Map & Attempts Sheet
public struct SegmentDetailSheet: View {
    let segment: SegmentRecord
    var onLoadRoute: ((GPXTrack) -> Void)?
    @Environment(\.dismiss) private var dismiss
    @ObservedObject private var store = ActivityStore.shared
    
    @State private var mapPosition: MapCameraPosition = .automatic
    
    private var attempts: [(date: Date, duration: TimeInterval, speed: Double, activityTitle: String, isPR: Bool)] {
        var list: [(date: Date, duration: TimeInterval, speed: Double, activityTitle: String, isPR: Bool)] = []
        for act in store.activeActivities {
            for effort in act.segmentEfforts where effort.segmentId == segment.id {
                let spd = effort.avgSpeedKmh > 0 ? effort.avgSpeedKmh : (segment.distanceKm / (effort.timeSeconds / 3600.0))
                list.append((date: act.date, duration: effort.timeSeconds, speed: spd, activityTitle: act.title, isPR: effort.isPR))
            }
        }
        return list.sorted(by: { $0.date > $1.date })
    }
    
    public var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 16) {
                    // Segment Interactive Map
                    ZStack(alignment: .bottomTrailing) {
                        Map(position: $mapPosition) {
                            MapPolyline(coordinates: [
                                segment.startCoordinate.coordinate,
                                segment.endCoordinate.coordinate
                            ])
                            .stroke(
                                LinearGradient(colors: [.orange, .yellow], startPoint: .leading, endPoint: .trailing),
                                style: StrokeStyle(lineWidth: 5, lineCap: .round)
                            )
                            
                            Annotation("起點", coordinate: segment.startCoordinate.coordinate) {
                                VStack(spacing: 2) {
                                    Image(systemName: "flag.fill")
                                        .font(.caption.bold())
                                        .foregroundColor(.white)
                                        .padding(6)
                                        .background(Circle().fill(Color.green))
                                        .shadow(radius: 2)
                                    Text("起點")
                                        .font(.system(size: 9, weight: .bold))
                                        .foregroundColor(.white)
                                        .padding(.horizontal, 4)
                                        .background(Color.black.opacity(0.7), in: Capsule())
                                }
                            }
                            
                            Annotation("終點", coordinate: segment.endCoordinate.coordinate) {
                                VStack(spacing: 2) {
                                    Image(systemName: "flag.checkered")
                                        .font(.caption.bold())
                                        .foregroundColor(.white)
                                        .padding(6)
                                        .background(Circle().fill(Color.orange))
                                        .shadow(radius: 2)
                                    Text("終點")
                                        .font(.system(size: 9, weight: .bold))
                                        .foregroundColor(.white)
                                        .padding(.horizontal, 4)
                                        .background(Color.black.opacity(0.7), in: Capsule())
                                }
                            }
                        }
                        .frame(height: 240)
                        .clipShape(RoundedRectangle(cornerRadius: 16))
                        .shadow(radius: 4)
                    }
                    .padding(.horizontal, 16)
                    
                    // Segment Stats Grid
                    LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible()), GridItem(.flexible())], spacing: 12) {
                        segmentStatPill(title: "長度", value: String(format: "%.1f km", segment.distanceKm), icon: "road.lanes", color: .blue)
                        segmentStatPill(title: "總爬升", value: "\(Int(segment.elevationGainMeters)) m", icon: "mountain.2.fill", color: .teal)
                        segmentStatPill(title: "平均坡度", value: String(format: "%.1f%%", segment.avgGradientPercent), icon: "triangle.fill", color: .orange)
                    }
                    .padding(.horizontal, 16)
                    
                    // PR Banner
                    if let pr = segment.personalRecordSeconds {
                        let prSpeed = segment.distanceKm / (pr / 3600.0)
                        HStack(spacing: 14) {
                            Image(systemName: "trophy.fill")
                                .font(.system(size: 32))
                                .foregroundColor(.yellow)
                            VStack(alignment: .leading, spacing: 2) {
                                Text("個人最佳成績 (PR)")
                                    .font(.caption.bold())
                                    .foregroundColor(.orange)
                                HStack(alignment: .firstTextBaseline, spacing: 8) {
                                    Text(formattedDuration(pr))
                                        .font(.title2.bold())
                                    Text(String(format: "均速 %.1f km/h", prSpeed))
                                        .font(.subheadline)
                                        .foregroundColor(.secondary)
                                }
                            }
                            Spacer()
                        }
                        .padding(14)
                        .background(Color.yellow.opacity(0.12), in: RoundedRectangle(cornerRadius: 14))
                        .padding(.horizontal, 16)
                    }
                    
                    // Action: Load to Navigation
                    if let load = onLoadRoute {
                        Button {
                            let track = GPXTrack(
                                title: "\(segment.name) 挑戰",
                                points: [segment.startCoordinate, segment.endCoordinate],
                                waypoints: [
                                    GPXWaypoint(name: "\(segment.name) 起點", latitude: segment.startCoordinate.latitude, longitude: segment.startCoordinate.longitude, elevation: segment.startCoordinate.elevation, iconName: "flag.fill"),
                                    GPXWaypoint(name: "\(segment.name) 終點", latitude: segment.endCoordinate.latitude, longitude: segment.endCoordinate.longitude, elevation: segment.endCoordinate.elevation, iconName: "flag.checkered")
                                ]
                            )
                            load(track)
                            dismiss()
                        } label: {
                            HStack {
                                Image(systemName: "map.fill")
                                Text("載入此路段至地圖導航")
                            }
                            .font(.headline)
                            .foregroundColor(.white)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 14)
                            .background(
                                LinearGradient(colors: [.orange, .red], startPoint: .leading, endPoint: .trailing),
                                in: RoundedRectangle(cornerRadius: 12)
                            )
                        }
                        .padding(.horizontal, 16)
                    }
                    
                    // Past Attempts List
                    VStack(alignment: .leading, spacing: 10) {
                        Text("歷次挑戰紀錄 (\(attempts.count) 次)")
                            .font(.headline)
                            .padding(.horizontal, 16)
                        
                        if attempts.isEmpty {
                            Text("尚無挑戰紀錄，騎行經過此路段將自動記錄並結算成績。")
                                .font(.caption)
                                .foregroundColor(.secondary)
                                .padding(.horizontal, 16)
                        } else {
                            VStack(spacing: 8) {
                                ForEach(attempts.indices, id: \.self) { idx in
                                    let att = attempts[idx]
                                    HStack {
                                        if att.isPR {
                                            Image(systemName: "medal.fill")
                                                .foregroundColor(.yellow)
                                        } else {
                                            Text("#\(attempts.count - idx)")
                                                .font(.caption.bold())
                                                .foregroundColor(.secondary)
                                                .frame(width: 24)
                                        }
                                        VStack(alignment: .leading, spacing: 2) {
                                            Text(att.activityTitle)
                                                .font(.subheadline.bold())
                                            Text(att.date.formatted(date: .abbreviated, time: .shortened))
                                                .font(.caption2)
                                                .foregroundColor(.secondary)
                                        }
                                        Spacer()
                                        VStack(alignment: .trailing, spacing: 2) {
                                            Text(formattedDuration(att.duration))
                                                .font(.subheadline.bold())
                                            Text(String(format: "%.1f km/h", att.speed))
                                                .font(.caption2)
                                                .foregroundColor(.secondary)
                                        }
                                    }
                                    .padding(10)
                                    .background(Color.secondary.opacity(0.06), in: RoundedRectangle(cornerRadius: 10))
                                }
                            }
                            .padding(.horizontal, 16)
                        }
                    }
                }
                .padding(.vertical, 16)
            }
            .navigationTitle(segment.name)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("關閉") { dismiss() }
                }
            }
            .onAppear {
                let minLat = min(segment.startCoordinate.latitude, segment.endCoordinate.latitude)
                let maxLat = max(segment.startCoordinate.latitude, segment.endCoordinate.latitude)
                let minLon = min(segment.startCoordinate.longitude, segment.endCoordinate.longitude)
                let maxLon = max(segment.startCoordinate.longitude, segment.endCoordinate.longitude)
                let center = CLLocationCoordinate2D(latitude: (minLat + maxLat) / 2.0, longitude: (minLon + maxLon) / 2.0)
                let span = MKCoordinateSpan(latitudeDelta: max(0.015, (maxLat - minLat) * 1.8), longitudeDelta: max(0.015, (maxLon - minLon) * 1.8))
                mapPosition = .region(MKCoordinateRegion(center: center, span: span))
            }
        }
    }
    
    private func segmentStatPill(title: String, value: String, icon: String, color: Color) -> some View {
        VStack(spacing: 4) {
            Image(systemName: icon)
                .foregroundColor(color)
            Text(title)
                .font(.caption2)
                .foregroundColor(.secondary)
            Text(value)
                .font(.subheadline.bold())
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 8)
        .background(color.opacity(0.1), in: RoundedRectangle(cornerRadius: 10))
    }
    
    private func formattedDuration(_ sec: TimeInterval) -> String {
        let total = Int(sec)
        let m = (total % 3600) / 60
        let s = total % 60
        let h = total / 3600
        if h > 0 {
            return String(format: "%d小時%02d分%02d秒", h, m, s)
        } else {
            return String(format: "%d分%02d秒", m, s)
        }
    }
}

// MARK: - User Profile Edit Sheet (Square Avatar, Nickname, Bio, Bike)
public struct UserProfileEditSheet: View {
    @ObservedObject private var profileStore = UserProfileStore.shared
    @Environment(\.dismiss) private var dismiss
    
    @State private var nickname: String = ""
    @State private var bio: String = ""
    @State private var favoriteBike: String = ""
    @State private var avatarData: Data? = nil
    @State private var selectedPhotoItem: PhotosPickerItem? = nil
    
    public init() {}
    
    public var body: some View {
        NavigationStack {
            Form {
                Section {
                    HStack {
                        Spacer()
                        VStack(spacing: 10) {
                            ZStack {
                                RoundedRectangle(cornerRadius: 16)
                                    .fill(LinearGradient(colors: [.orange, .yellow], startPoint: .topLeading, endPoint: .bottomTrailing))
                                    .frame(width: 88, height: 88)
                                    .shadow(color: .orange.opacity(0.4), radius: 6)
                                
                                if let data = avatarData, let uiImg = UIImage(data: data) {
                                    Image(uiImage: uiImg)
                                        .resizable()
                                        .scaledToFill()
                                        .frame(width: 80, height: 80)
                                        .clipShape(RoundedRectangle(cornerRadius: 12))
                                } else {
                                    ZStack {
                                        Color.black.opacity(0.8)
                                        Image(systemName: "person.crop.square.fill")
                                            .font(.system(size: 44))
                                            .foregroundColor(.white)
                                    }
                                    .frame(width: 80, height: 80)
                                    .clipShape(RoundedRectangle(cornerRadius: 12))
                                }
                            }
                            
                            PhotosPicker(selection: $selectedPhotoItem, matching: .images) {
                                HStack(spacing: 4) {
                                    Image(systemName: "photo.badge.plus")
                                    Text("更換方頭像")
                                }
                                .font(.caption.bold())
                                .foregroundColor(.orange)
                            }
                            .onChange(of: selectedPhotoItem) { newItem in
                                Task {
                                    if let data = try? await newItem?.loadTransferable(type: Data.self) {
                                        self.avatarData = data
                                    }
                                }
                            }
                        }
                        Spacer()
                    }
                    .padding(.vertical, 8)
                } header: {
                    Text("騎乘者個人形象 (3D 單車視角連動)")
                }
                
                Section("騎士基本資料") {
                    TextField("騎士暱稱 (例如：風櫃嘴破風手)", text: $nickname)
                    TextField("自我介紹 (例如：永不放棄，享受爬坡！)", text: $bio)
                    TextField("主要愛車 (例如：公路車 / Tarmac SL8)", text: $favoriteBike)
                }
                
                Section(header: Text(L10n.Common.languageSettings)) {
                    Picker(L10n.Common.language, selection: Binding(
                        get: { AppLanguageManager.shared.currentLanguage },
                        set: { AppLanguageManager.shared.setLanguage($0) }
                    )) {
                        ForEach(AppLanguage.allCases) { lang in
                            Text("\(lang.flag) \(lang.displayName)").tag(lang)
                        }
                    }
                    .pickerStyle(.segmented)
                }
                
                Section {
                    Text("💡 提示：設定的暱稱與方頭像將即時連動至「3D 全景巡航重播」中，成為您在山道地圖上的個人專屬騎乘者頭銜！")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
            }
            .navigationTitle("編輯個人檔案")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("取消") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("儲存") {
                        profileStore.update(
                            nickname: nickname,
                            bio: bio,
                            avatarData: avatarData,
                            favoriteBike: favoriteBike
                        )
                        dismiss()
                    }
                    .bold()
                }
            }
            .onAppear {
                self.nickname = profileStore.profile.nickname
                self.bio = profileStore.profile.bio
                self.favoriteBike = profileStore.profile.favoriteBike
                self.avatarData = profileStore.profile.avatarData
            }
        }
    }
}

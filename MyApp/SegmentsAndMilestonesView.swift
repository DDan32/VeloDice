import SwiftUI

public struct SegmentsAndMilestonesView: View {
    @State private var segments: [SegmentRecord] = []
    @State private var distanceMilestones: [MilestoneRecord] = []
    @State private var elevationMilestones: [MilestoneRecord] = []
    
    @State private var selectedTab: Int = 0
    @State private var showCreateSegmentSheet: Bool = false
    @State private var newSegmentName: String = ""
    @State private var newSegmentDistance: String = "5.0"
    @State private var newSegmentClimb: String = "250"
    
    public init() {}
    
    public var body: some View {
        VStack(spacing: 0) {
            Picker("分類", selection: $selectedTab) {
                Text("路段 PR 挑戰 (Segments)").tag(0)
                Text("距離里程碑").tag(1)
                Text("爬升里程碑").tag(2)
            }
            .pickerStyle(.segmented)
            .padding()
            
            if selectedTab == 0 {
                if segments.isEmpty {
                    emptyStateView(
                        icon: "trophy",
                        title: "目前尚無路段挑戰記錄",
                        description: "當您在「即時數據」中完成一次運動記錄後，系統將自動為您統計各爬坡路段的成績與破紀錄 (PR) 時間！",
                        showAddButton: true
                    )
                } else {
                    segmentsListView
                }
            } else if selectedTab == 1 {
                if distanceMilestones.isEmpty {
                    emptyStateView(
                        icon: "figure.outdoor.cycle",
                        title: "目前尚無距離里程碑記錄",
                        description: "只要完成 10km、30km、50km 或 100km 的騎行或健行，系統便會在此為您解鎖專屬勳章與最佳花費時間。",
                        showAddButton: false
                    )
                } else {
                    milestoneGridView(items: distanceMilestones, unit: "km")
                }
            } else {
                if elevationMilestones.isEmpty {
                    emptyStateView(
                        icon: "mountain.2.fill",
                        title: "目前尚無爬升里程碑記錄",
                        description: "累計爬升達到 100m、500m、1000m 時，系統將在此記錄您的登頂時間與極限攀爬紀錄。",
                        showAddButton: false
                    )
                } else {
                    milestoneGridView(items: elevationMilestones, unit: "m 爬升")
                }
            }
        }
        .sheet(isPresented: $showCreateSegmentSheet) {
            createSegmentSheet
        }
    }
    
    // MARK: - Empty State View
    private func emptyStateView(icon: String, title: String, description: String, showAddButton: Bool) -> some View {
        VStack(spacing: 16) {
            Spacer()
            Image(systemName: icon)
                .font(.system(size: 60))
                .foregroundColor(.secondary.opacity(0.6))
            
            Text(title)
                .font(.title3.bold())
            
            Text(description)
                .font(.subheadline)
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 40)
            
            if showAddButton {
                Button {
                    showCreateSegmentSheet = true
                } label: {
                    Label("建立自訂挑戰路段", systemImage: "plus.circle.fill")
                        .font(.headline)
                        .padding(.horizontal, 16)
                        .padding(.vertical, 8)
                }
                .buttonStyle(.borderedProminent)
                .tint(.blue)
                .padding(.top, 8)
            }
            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
    
    // MARK: - Segments List
    private var segmentsListView: some View {
        List {
            ForEach(segments) { seg in
                VStack(alignment: .leading, spacing: 10) {
                    HStack {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(seg.name)
                                .font(.headline.bold())
                            HStack(spacing: 8) {
                                Text("\(String(format: "%.1f", seg.distanceKm)) km")
                                Text("爬升 \(Int(seg.elevationGainMeters)) m")
                                Text("平均 \(String(format: "%.1f", seg.avgGradientPercent))%")
                                Text("挑戰 \(seg.attemptCount) 次")
                            }
                            .font(.caption)
                            .foregroundColor(.secondary)
                        }
                        
                        Spacer()
                        
                        if seg.isNewPR {
                            VStack(spacing: 2) {
                                Image(systemName: "crown.fill")
                                    .foregroundColor(.yellow)
                                Text("NEW PR!")
                                    .font(.caption2.bold())
                                    .foregroundColor(.yellow)
                            }
                            .padding(6)
                            .background(Color.yellow.opacity(0.15), in: RoundedRectangle(cornerRadius: 6))
                        }
                    }
                    
                    Divider()
                    
                    HStack {
                        VStack(alignment: .leading, spacing: 2) {
                            Text("個人最佳 (PR)")
                                .font(.caption2)
                                .foregroundColor(.secondary)
                            Text(formattedDuration(seg.personalRecordSeconds))
                                .font(.title3.bold())
                                .foregroundColor(.purple)
                        }
                        
                        Spacer()
                        
                        VStack(alignment: .trailing, spacing: 2) {
                            Text("最近一次成績")
                                .font(.caption2)
                                .foregroundColor(.secondary)
                            Text(formattedDuration(seg.latestAttemptSeconds))
                                .font(.headline)
                        }
                    }
                }
                .padding(.vertical, 6)
            }
            .onDelete { indexSet in
                segments.remove(atOffsets: indexSet)
            }
        }
        .listStyle(.insetGrouped)
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button {
                    showCreateSegmentSheet = true
                } label: {
                    Image(systemName: "plus")
                }
            }
        }
    }
    
    // MARK: - Milestones Grid
    private func milestoneGridView(items: [MilestoneRecord], unit: String) -> some View {
        ScrollView {
            LazyVGrid(columns: [GridItem(.adaptive(minimum: 160), spacing: 16)], spacing: 16) {
                ForEach(items) { ms in
                    VStack(spacing: 10) {
                        Image(systemName: ms.isAchievedToday ? "star.circle.fill" : "medal.fill")
                            .font(.system(size: 38))
                            .foregroundColor(ms.isAchievedToday ? .yellow : .orange)
                        
                        Text(ms.title)
                            .font(.headline)
                            .multilineTextAlignment(.center)
                        
                        Divider()
                        
                        VStack(spacing: 2) {
                            Text("最快完成時間")
                                .font(.caption2)
                                .foregroundColor(.secondary)
                            Text(formattedDuration(ms.bestTimeSeconds))
                                .font(.title3.bold())
                                .foregroundColor(.blue)
                        }
                    }
                    .padding()
                    .frame(maxWidth: .infinity)
                    .background(RoundedRectangle(cornerRadius: 16).fill(.ultraThinMaterial))
                    .shadow(radius: 2)
                }
            }
            .padding()
        }
    }
    
    // MARK: - Create Custom Segment Sheet
    private var createSegmentSheet: some View {
        NavigationStack {
            Form {
                Section("路段資訊") {
                    TextField("路段名稱 (例如: 風櫃嘴楓林橋至涼亭)", text: $newSegmentName)
                    TextField("路段長度 (km)", text: $newSegmentDistance)
                    TextField("累計爬升 (m)", text: $newSegmentClimb)
                }
            }
            .navigationTitle("新增挑戰路段")
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("取消") { showCreateSegmentSheet = false }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("儲存") {
                        if !newSegmentName.isEmpty {
                            let dist = Double(newSegmentDistance) ?? 5.0
                            let climb = Double(newSegmentClimb) ?? 200.0
                            let grade = dist > 0 ? (climb / (dist * 1000.0)) * 100.0 : 0.0
                            let newSeg = SegmentRecord(
                                name: newSegmentName,
                                startCoordinate: RoutePoint(latitude: 25.0, longitude: 121.5, elevation: 0),
                                endCoordinate: RoutePoint(latitude: 25.05, longitude: 121.55, elevation: climb),
                                distanceKm: dist,
                                elevationGainMeters: climb,
                                avgGradientPercent: grade,
                                personalRecordSeconds: nil,
                                latestAttemptSeconds: nil,
                                attemptCount: 0
                            )
                            segments.append(newSeg)
                            newSegmentName = ""
                            showCreateSegmentSheet = false
                        }
                    }
                    .disabled(newSegmentName.isEmpty)
                }
            }
        }
    }
    
    private func formattedDuration(_ seconds: TimeInterval?) -> String {
        guard let s = seconds, s > 0 else { return "--:--" }
        let total = Int(s)
        let m = total / 60
        let sec = total % 60
        return String(format: "%02d:%02d", m, sec)
    }
}

import SwiftUI
import PhotosUI

public struct SaveWorkoutSheet: View {
    let finishedTrack: GPXTrack
    let durationSeconds: TimeInterval       // 總時間 (包含紅綠燈等待)
    let movingDurationSeconds: TimeInterval // 實際運動踩踏時間
    let distanceKm: Double
    let totalAscentMeters: Double
    let avgHeartRate: Int?
    let avgCadence: Int?
    
    var onSaved: ((SavedActivity) -> Void)?
    var onDismiss: (() -> Void)?
    
    @State private var activityTitle: String = ""
    @State private var activityNote: String = ""
    @State private var selectedPhotos: [PhotosPickerItem] = []
    @State private var loadedPhotoDataList: [Data] = []
    @State private var showDiscardConfirm: Bool = false
    
    public init(
        finishedTrack: GPXTrack,
        durationSeconds: TimeInterval,
        movingDurationSeconds: TimeInterval? = nil,
        distanceKm: Double,
        totalAscentMeters: Double,
        avgHeartRate: Int? = nil,
        avgCadence: Int? = nil,
        onSaved: ((SavedActivity) -> Void)? = nil,
        onDismiss: (() -> Void)? = nil
    ) {
        self.finishedTrack = finishedTrack
        self.durationSeconds = durationSeconds
        self.movingDurationSeconds = movingDurationSeconds ?? durationSeconds
        self.distanceKm = distanceKm
        self.totalAscentMeters = totalAscentMeters
        self.avgHeartRate = avgHeartRate
        self.avgCadence = avgCadence
        self.onSaved = onSaved
        self.onDismiss = onDismiss
        
        let hour = Calendar.current.component(.hour, from: Date())
        let timePeriod = hour < 12 ? "早晨" : (hour < 18 ? "午後" : "夜間")
        _activityTitle = State(initialValue: "\(timePeriod)運動 · \(Date().formatted(date: .abbreviated, time: .omitted))")
    }
    
    public var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 20) {
                    // Strava-style Stat Summary Header
                    statSummaryHeader
                    
                    // Title & Description Inputs
                    VStack(alignment: .leading, spacing: 12) {
                        Text("活動標題")
                            .font(.subheadline.bold())
                            .foregroundColor(.secondary)
                        
                        TextField("例如：風櫃嘴計時挑戰、晨間咖啡騎行", text: $activityTitle)
                            .textFieldStyle(.roundedBorder)
                            .font(.headline)
                        
                        Text("心得與路線描述")
                            .font(.subheadline.bold())
                            .foregroundColor(.secondary)
                        
                        TextField("寫下今天的路況、風向、爬坡體感或補給點...", text: $activityNote, axis: .vertical)
                            .textFieldStyle(.roundedBorder)
                            .lineLimit(4...6)
                    }
                    .padding()
                    .background(RoundedRectangle(cornerRadius: 14).fill(.ultraThinMaterial))
                    
                    // Photos Picker Section
                    VStack(alignment: .leading, spacing: 12) {
                        HStack {
                            Text("活動照片")
                                .font(.subheadline.bold())
                                .foregroundColor(.secondary)
                            Spacer()
                            PhotosPicker(
                                selection: $selectedPhotos,
                                maxSelectionCount: 6,
                                matching: .images
                            ) {
                                Label("新增照片", systemImage: "photo.badge.plus")
                                    .font(.caption.bold())
                            }
                        }
                        
                        if !loadedPhotoDataList.isEmpty {
                            ScrollView(.horizontal, showsIndicators: false) {
                                HStack(spacing: 10) {
                                    ForEach(Array(loadedPhotoDataList.enumerated()), id: \.offset) { idx, data in
                                        ZStack(alignment: .topTrailing) {
                                            #if os(macOS)
                                            if let img = NSImage(data: data) {
                                                Image(nsImage: img)
                                                    .resizable()
                                                    .scaledToFill()
                                                    .frame(width: 90, height: 90)
                                                    .clipShape(RoundedRectangle(cornerRadius: 10))
                                            }
                                            #else
                                            if let img = UIImage(data: data) {
                                                Image(uiImage: img)
                                                    .resizable()
                                                    .scaledToFill()
                                                    .frame(width: 90, height: 90)
                                                    .clipShape(RoundedRectangle(cornerRadius: 10))
                                            }
                                            #endif
                                            
                                            Button {
                                                loadedPhotoDataList.remove(at: idx)
                                            } label: {
                                                Image(systemName: "xmark.circle.fill")
                                                    .foregroundColor(.white)
                                                    .background(Circle().fill(Color.black.opacity(0.6)))
                                            }
                                            .padding(4)
                                        }
                                    }
                                }
                            }
                        } else {
                            Text("上傳今天拍的沿途美景，照片將整合至過往活動與去背分享中。")
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
                    }
                    .padding()
                    .background(RoundedRectangle(cornerRadius: 14).fill(.ultraThinMaterial))
                    
                    // Save & Discard Buttons
                    VStack(spacing: 12) {
                        Button {
                            saveAndFinish()
                        } label: {
                            Text("儲存活動並歸檔")
                                .font(.headline.bold())
                                .foregroundColor(.white)
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 14)
                                .background(Color.orange, in: RoundedRectangle(cornerRadius: 12))
                        }
                        .buttonStyle(.plain)
                        
                        Button {
                            showDiscardConfirm = true
                        } label: {
                            Text("捨棄本次活動")
                                .font(.caption.bold())
                                .foregroundColor(.red)
                        }
                        .buttonStyle(.plain)
                    }
                    .padding(.top, 8)
                }
                .padding()
            }
            .navigationTitle("編輯與儲存活動")
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("取消") { onDismiss?() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("儲存") { saveAndFinish() }
                        .bold()
                }
            }
            .onChange(of: selectedPhotos) { newItems in
                Task {
                    var photos: [Data] = []
                    for item in newItems {
                        if let data = try? await item.loadTransferable(type: Data.self) {
                            #if os(iOS)
                            if let uiImg = UIImage(data: data), let compressed = uiImg.jpegData(compressionQuality: 0.7) {
                                photos.append(compressed)
                                continue
                            }
                            #endif
                            photos.append(data)
                        }
                    }
                    await MainActor.run {
                        self.loadedPhotoDataList = photos
                    }
                }
            }
            .confirmationDialog("確定要捨棄本次運動記錄嗎？", isPresented: $showDiscardConfirm, titleVisibility: .visible) {
                Button("捨棄記錄", role: .destructive) {
                    onDismiss?()
                }
                Button("繼續編輯", role: .cancel) { }
            }
        }
    }
    
    // MARK: - Stat Summary Header
    private var statSummaryHeader: some View {
        VStack(spacing: 14) {
            HStack {
                VStack(alignment: .leading) {
                    Text("距離")
                        .font(.caption)
                        .foregroundColor(.secondary)
                    Text(String(format: "%.2f", distanceKm))
                        .font(.system(size: 38, weight: .heavy, design: .rounded))
                    + Text(" km").font(.subheadline.bold()).foregroundColor(.secondary)
                }
                
                Spacer()
                
                VStack(alignment: .trailing) {
                    Text("運動時間")
                        .font(.caption)
                        .foregroundColor(.secondary)
                    Text(formattedTime(movingDurationSeconds))
                        .font(.system(size: 38, weight: .heavy, design: .rounded))
                }
            }
            
            Divider()
            
            let avgSpeed = (distanceKm >= 0.03 && movingDurationSeconds >= 3) ? (distanceKm / (movingDurationSeconds / 3600.0)) : 0.0
            LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 10) {
                summarySubMetric(title: "總歷時 (含紅綠燈)", value: formattedTime(durationSeconds))
                summarySubMetric(title: "運動均速", value: String(format: "%.1f km/h", avgSpeed))
                summarySubMetric(title: "累計爬升", value: "\(Int(totalAscentMeters)) m")
                if let hr = avgHeartRate {
                    summarySubMetric(title: "平均心率", value: "\(hr) bpm")
                } else if let cad = avgCadence {
                    summarySubMetric(title: "平均踏頻", value: "\(cad) rpm")
                }
            }
        }
        .padding()
        .background(RoundedRectangle(cornerRadius: 14).fill(.ultraThinMaterial))
    }
    
    private func summarySubMetric(title: String, value: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(title)
                .font(.system(size: 10))
                .foregroundColor(.secondary)
            Text(value)
                .font(.caption.bold())
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
    
    private func saveAndFinish() {
        let avgSpeed = (distanceKm >= 0.03 && movingDurationSeconds >= 3) ? (distanceKm / (movingDurationSeconds / 3600.0)) : 0.0
        let maxSpd = finishedTrack.points.compactMap(\.speedKmh).filter({ $0 > 0 }).max() ?? 0.0
        
        let defaultTitle = distanceKm >= 0.05 ? "我的運動記錄" : "原地運動記錄"
        let finalTitle = activityTitle.trimmingCharacters(in: .whitespaces).isEmpty ? defaultTitle : activityTitle
        
        let newActivity = SavedActivity(
            title: finalTitle,
            note: activityNote,
            date: Date(),
            track: finishedTrack,
            distanceKm: distanceKm,
            durationSeconds: durationSeconds,
            movingDurationSeconds: movingDurationSeconds,
            avgSpeedKmh: avgSpeed,
            maxSpeedKmh: maxSpd,
            totalAscentMeters: totalAscentMeters,
            avgHeartRateBpm: avgHeartRate,
            avgCadenceRpm: avgCadence,
            photoDataList: loadedPhotoDataList
        )
        
        ActivityStore.shared.saveActivity(newActivity)
        onSaved?(newActivity)
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
}

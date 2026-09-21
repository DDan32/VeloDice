import SwiftUI
import MapKit
import CoreLocation

public struct VeloDiceLuckyRouteSheet: View {
    @ObservedObject var diceService = VeloDiceLuckyRouteService.shared
    @ObservedObject var languageManager = AppLanguageManager.shared
    let userLocation: CLLocationCoordinate2D?
    let onConfirmRoute: (VeloDiceLuckyRoute) -> Void
    
    @Environment(\.dismiss) private var dismiss
    @State private var diceRotation: Double = 0
    @State private var diceScale: CGFloat = 1.0
    @State private var currentDiceFaceIndex: Int = 5
    @State private var isAnimatingRoll: Bool = false
    
    private let diceFaceIcons = [
        "die.face.1.fill",
        "die.face.2.fill",
        "die.face.3.fill",
        "die.face.4.fill",
        "die.face.5.fill",
        "die.face.6.fill"
    ]
    
    public init(
        userLocation: CLLocationCoordinate2D?,
        onConfirmRoute: @escaping (VeloDiceLuckyRoute) -> Void
    ) {
        self.userLocation = userLocation
        self.onConfirmRoute = onConfirmRoute
    }
    
    public var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 20) {
                    // Top Dice Rolling Interactive Area
                    diceHeaderSection
                    
                    // Selected Route Card
                    if let route = diceService.currentLuckyRoute {
                        routeDetailCard(route)
                    } else if diceService.isSearchingNearby || diceService.isRolling {
                        loadingRouteCard
                    } else {
                        emptyStateCard
                    }
                }
                .padding(.horizontal, 18)
                .padding(.vertical, 16)
            }
            .background(Color(uiColor: .systemGroupedBackground))
            .navigationTitle(L10n.VeloDice.luckyRoute)
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    LanguageSwitcherView()
                }
                ToolbarItem(placement: .cancellationAction) {
                    Button(L10n.Common.close) {
                        dismiss()
                    }
                }
            }
            .safeAreaInset(edge: .bottom) {
                bottomActionButtons
            }
        }
        .presentationDetents([.large])
        .task {
            if diceService.currentLuckyRoute == nil {
                await triggerDiceRoll(haptic: false)
            }
        }
    }
    
    // MARK: - Dice Header & Animation
    private var diceHeaderSection: some View {
        VStack(spacing: 12) {
            Button {
                Task {
                    await triggerDiceRoll(haptic: true)
                }
            } label: {
                ZStack {
                    RoundedRectangle(cornerRadius: 24, style: .continuous)
                        .fill(
                            LinearGradient(
                                colors: [Color.purple.opacity(0.85), Color.blue.opacity(0.9)],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            )
                        )
                        .frame(width: 88, height: 88)
                        .shadow(color: Color.purple.opacity(0.35), radius: 12, y: 6)
                    
                    Image(systemName: diceFaceIcons[currentDiceFaceIndex])
                        .font(.system(size: 46, weight: .bold))
                        .foregroundColor(.white)
                        .rotationEffect(.degrees(diceRotation))
                        .scaleEffect(diceScale)
                }
            }
            .buttonStyle(.plain)
            .disabled(isAnimatingRoll)
            
            VStack(spacing: 4) {
                Text(L10n.VeloDice.rollTitle)
                    .font(.title3.bold())
                Text(L10n.VeloDice.rollSubtitle)
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .multilineTextAlignment(.center)
            }
        }
        .padding(.top, 4)
    }
    
    // MARK: - Route Detail Card
    private func routeDetailCard(_ route: VeloDiceLuckyRoute) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            // Category & Distance Badge
            HStack {
                Label(route.category.rawValue, systemImage: route.category.icon)
                    .font(.caption.bold())
                    .foregroundColor(route.category.themeColor)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 5)
                    .background(route.category.themeColor.opacity(0.12), in: Capsule())
                
                Spacer()
                
                HStack(spacing: 4) {
                    Image(systemName: "location.fill")
                        .font(.system(size: 11))
                    Text("\(L10n.VeloDice.fromYou) \(String(format: "%.1f", route.distanceFromUserKm)) km（\(L10n.VeloDice.within30km)）")
                        .font(.caption.bold())
                }
                .foregroundColor(.orange)
                .padding(.horizontal, 10)
                .padding(.vertical, 5)
                .background(Color.orange.opacity(0.12), in: Capsule())
            }
            
            // Title & Subtitle
            VStack(alignment: .leading, spacing: 4) {
                Text(route.title)
                    .font(.title2.bold())
                    .foregroundColor(.primary)
                
                Text(route.subtitle)
                    .font(.subheadline)
                    .foregroundColor(.secondary)
            }
            
            Divider()
            
            // Metrics Row
            HStack(spacing: 16) {
                metricItem(
                    icon: "bicycle",
                    value: "\(String(format: "%.1f", route.estimatedDistanceKm))",
                    unit: "km",
                    label: L10n.VeloDice.estDistance,
                    color: .blue
                )
                
                metricItem(
                    icon: "mountain.2.fill",
                    value: "\(Int(route.estimatedAscentMeters))",
                    unit: "m",
                    label: L10n.VeloDice.estAscent,
                    color: .green
                )
                
                metricItem(
                    icon: "clock.fill",
                    value: "\(Int(route.estimatedDistanceKm / 19.0 * 60))",
                    unit: L10n.Common.minUnit,
                    label: L10n.VeloDice.estTime,
                    color: .purple
                )
                
                metricItem(
                    icon: "gauge.medium",
                    value: route.difficulty.replacingOccurrences(of: " ⭐", with: ""),
                    unit: "",
                    label: L10n.VeloDice.difficulty,
                    color: .orange
                )
            }
            .padding(.vertical, 4)
            
            // Highlights Tags
            if !route.highlights.isEmpty {
                VStack(alignment: .leading, spacing: 6) {
                    Text(L10n.VeloDice.highlights)
                        .font(.caption.bold())
                        .foregroundColor(.secondary)
                    
                    HStack(spacing: 6) {
                        ForEach(route.highlights, id: \.self) { hl in
                            HStack(spacing: 4) {
                                Image(systemName: "sparkles")
                                    .font(.system(size: 10))
                                Text(hl)
                                    .font(.caption2.bold())
                            }
                            .foregroundColor(.primary)
                            .padding(.horizontal, 8)
                            .padding(.vertical, 4)
                            .background(Color(uiColor: .tertiarySystemFill), in: Capsule())
                        }
                    }
                }
            }
            
            // Mini Map Snapshot Preview
            miniMapSection(route: route)
        }
        .padding(18)
        .background(
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .fill(Color(uiColor: .secondarySystemGroupedBackground))
                .shadow(color: .black.opacity(0.06), radius: 10, y: 4)
        )
    }
    
    // MARK: - Mini Map Preview
    private func miniMapSection(route: VeloDiceLuckyRoute) -> some View {
        Map(initialPosition: .region(MKCoordinateRegion(
            center: route.coordinate,
            span: MKCoordinateSpan(latitudeDelta: 0.08, longitudeDelta: 0.08)
        ))) {
            Annotation(route.destinationName, coordinate: route.coordinate) {
                VStack(spacing: 2) {
                    Image(systemName: "flag.checkered.circle.fill")
                        .font(.title2)
                        .foregroundColor(.red)
                        .background(Color.white.clipShape(Circle()))
                    Text(route.destinationName)
                        .font(.system(size: 10, weight: .bold))
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(.ultraThinMaterial, in: Capsule())
                }
            }
            
            if let user = userLocation {
                Annotation(L10n.Route.currentLocation, coordinate: user) {
                    Circle()
                        .fill(Color.blue)
                        .frame(width: 14, height: 14)
                        .overlay(Circle().stroke(Color.white, lineWidth: 2))
                }
            }
        }
        .frame(height: 140)
        .clipShape(RoundedRectangle(cornerRadius: 14))
        .disabled(true)
    }
    
    // MARK: - Metric Item
    private func metricItem(icon: String, value: String, unit: String, label: String, color: Color) -> some View {
        VStack(spacing: 3) {
            Image(systemName: icon)
                .font(.system(size: 13, weight: .bold))
                .foregroundColor(color)
            
            HStack(alignment: .lastTextBaseline, spacing: 1) {
                Text(value)
                    .font(.subheadline.bold())
                if !unit.isEmpty {
                    Text(unit)
                        .font(.system(size: 9))
                        .foregroundColor(.secondary)
                }
            }
            .lineLimit(1)
            .minimumScaleFactor(0.8)
            
            Text(label)
                .font(.system(size: 10))
                .foregroundColor(.secondary)
        }
        .frame(maxWidth: .infinity)
    }
    
    // MARK: - Loading & Empty States
    private var loadingRouteCard: some View {
        VStack(spacing: 12) {
            ProgressView()
                .controlSize(.large)
            Text(L10n.VeloDice.rollingToast)
                .font(.subheadline)
                .foregroundColor(.secondary)
        }
        .frame(maxWidth: .infinity)
        .frame(height: 220)
        .background(Color(uiColor: .secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 20))
    }
    
    private var emptyStateCard: some View {
        VStack(spacing: 12) {
            Image(systemName: "dice.fill")
                .font(.system(size: 40))
                .foregroundColor(.secondary)
            Text(L10n.VeloDice.rollSubtitle)
                .font(.subheadline)
                .foregroundColor(.secondary)
        }
        .frame(maxWidth: .infinity)
        .frame(height: 180)
        .background(Color(uiColor: .secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 20))
    }
    
    // MARK: - Bottom Action Buttons
    private var bottomActionButtons: some View {
        VStack(spacing: 10) {
            // Confirm & Navigate Button
            Button {
                if let route = diceService.currentLuckyRoute {
                    #if os(iOS)
                    let generator = UINotificationFeedbackGenerator()
                    generator.notificationOccurred(.success)
                    #endif
                    onConfirmRoute(route)
                    dismiss()
                }
            } label: {
                HStack(spacing: 8) {
                    Image(systemName: "location.north.line.fill")
                        .font(.headline)
                    Text(L10n.VeloDice.confirmNavigate)
                        .font(.headline.bold())
                }
                .foregroundColor(.white)
                .frame(maxWidth: .infinity)
                .frame(height: 52)
                .background(
                    LinearGradient(
                        colors: [Color.blue, Color.purple],
                        startPoint: .leading,
                        endPoint: .trailing
                    ),
                    in: RoundedRectangle(cornerRadius: 16)
                )
                .shadow(color: Color.blue.opacity(0.3), radius: 8, y: 4)
            }
            .buttonStyle(.plain)
            .disabled(diceService.currentLuckyRoute == nil || isAnimatingRoll)
            
            // Re-roll Button
            Button {
                Task {
                    await triggerDiceRoll(haptic: true)
                }
            } label: {
                HStack(spacing: 6) {
                    Image(systemName: "arrow.triangle.2.circlepath")
                        .font(.subheadline.bold())
                    Text(L10n.VeloDice.reRoll)
                        .font(.subheadline.bold())
                }
                .foregroundColor(.purple)
                .frame(maxWidth: .infinity)
                .frame(height: 44)
                .background(Color.purple.opacity(0.12), in: RoundedRectangle(cornerRadius: 14))
            }
            .buttonStyle(.plain)
            .disabled(isAnimatingRoll)
        }
        .padding(.horizontal, 18)
        .padding(.vertical, 12)
        .background(
            Color(uiColor: .systemBackground)
                .shadow(color: .black.opacity(0.08), radius: 10, y: -4)
        )
    }
    
    // MARK: - Roll Animation & Logic
    private func triggerDiceRoll(haptic: Bool) async {
        guard !isAnimatingRoll else { return }
        isAnimatingRoll = true
        
        #if os(iOS)
        if haptic {
            let impact = UIImpactFeedbackGenerator(style: .medium)
            impact.impactOccurred()
        }
        #endif
        
        // Fast face rotation simulation
        for i in 0..<8 {
            withAnimation(.easeInOut(duration: 0.06)) {
                diceRotation += 45
                diceScale = (i % 2 == 0) ? 1.15 : 0.95
                currentDiceFaceIndex = Int.random(in: 0..<6)
            }
            try? await Task.sleep(nanoseconds: 60_000_000)
        }
        
        _ = await diceService.rollDice(userCoordinate: userLocation)
        
        withAnimation(.spring(response: 0.35, dampingFraction: 0.6)) {
            diceRotation = 360
            diceScale = 1.0
            currentDiceFaceIndex = Int.random(in: 0..<6)
        }
        
        #if os(iOS)
        if haptic {
            let impact = UIImpactFeedbackGenerator(style: .heavy)
            impact.impactOccurred()
        }
        #endif
        
        try? await Task.sleep(nanoseconds: 100_000_000)
        diceRotation = 0
        isAnimatingRoll = false
    }
}

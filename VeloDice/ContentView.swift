import SwiftUI

public enum AppNavigationTab: String, CaseIterable, Identifiable {
    case routePlanning = "地圖導航"
    case liveHUD = "即時記錄"
    case myActivities = "我的活動"
    
    public var id: String { rawValue }
    
    public var icon: String {
        switch self {
        case .routePlanning: return "map.fill"
        case .liveHUD: return "speedometer"
        case .myActivities: return "figure.outdoor.cycle"
        }
    }
}

public struct ContentView: View {
    @State private var selectedTab: AppNavigationTab = .routePlanning
    @State private var currentTrack: GPXTrack = CleanRouteHelper.shared.emptyTrack()
    
    public init() {}
    
    public var body: some View {
        #if os(macOS)
        // Mac: NavigationSplitView with 3 primary items
        NavigationSplitView {
            List(AppNavigationTab.allCases, selection: $selectedTab) { tab in
                NavigationLink(value: tab) {
                    Label(tab.rawValue, systemImage: tab.icon)
                        .font(.headline)
                        .padding(.vertical, 6)
                }
            }
            .navigationTitle(AppConstants.appName)
            .listStyle(.sidebar)
            .frame(minWidth: 220)
        } detail: {
            detailView(for: selectedTab)
                .navigationTitle(selectedTab.rawValue)
        }
        .frame(minWidth: 960, minHeight: 640)
        #else
        // iOS: Native Clean 3-Tab Bar
        TabView(selection: $selectedTab) {
            RoutePlannerView(currentTrack: $currentTrack)
                .tabItem {
                    Label("地圖導航", systemImage: "map.fill")
                }
                .tag(AppNavigationTab.routePlanning)
            
            LiveHUDDashboardView(track: currentTrack) { finishedTrack in
                // 停止記錄並儲存後，清空正在地圖導航的規劃路線
                self.currentTrack = CleanRouteHelper.shared.emptyTrack()
                self.selectedTab = .myActivities
            }
            .tabItem {
                Label("即時記錄", systemImage: "speedometer")
            }
            .tag(AppNavigationTab.liveHUD)
            
            MyActivitiesView(onLoadRouteToNavigation: { track in
                self.currentTrack = track
                self.selectedTab = .routePlanning
            })
            .tabItem {
                Label("我的活動", systemImage: "figure.outdoor.cycle")
            }
            .tag(AppNavigationTab.myActivities)
        }
        #endif
    }
    
    @ViewBuilder
    private func detailView(for tab: AppNavigationTab) -> some View {
        switch tab {
        case .routePlanning:
            RoutePlannerView(currentTrack: $currentTrack)
        case .liveHUD:
            LiveHUDDashboardView(track: currentTrack) { finishedTrack in
                self.currentTrack = CleanRouteHelper.shared.emptyTrack()
                self.selectedTab = .myActivities
            }
        case .myActivities:
            MyActivitiesView(onLoadRouteToNavigation: { track in
                self.currentTrack = track
                self.selectedTab = .routePlanning
            })
        }
    }
}

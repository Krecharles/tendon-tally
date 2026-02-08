import SwiftUI
import AppKit

/// Main dashboard view with sidebar navigation and comprehensive metrics display.
struct FullDashboardView: View {
    @ObservedObject var viewModel: MetricsViewModel
    @AppStorage("selectedTab") private var selectedTabRawValue: String = Tab.today.rawValue

    private var selectedTab: Tab {
        Tab(rawValue: selectedTabRawValue) ?? .today
    }

    enum Tab: String {
        case today
        case history
        case settings
        case kui
    }

    var body: some View {
        HStack(spacing: 0) {
            sidebar

            Divider()
                .frame(width: 1)

            Group {
                switch selectedTab {
                case .today:
                    TodayTabView(viewModel: viewModel)
                case .history:
                    HistoryTabView(viewModel: viewModel)
                case .settings:
                    SettingsView(viewModel: viewModel)
                case .kui:
                    KUITabView(viewModel: viewModel)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .frame(minWidth: 800, minHeight: 600)
        .background(Color(NSColor.windowBackgroundColor))
    }

    private var sidebar: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 12) {
                Image("app-icon")
                    .resizable()
                    .aspectRatio(contentMode: .fit)
                    .frame(width: 32, height: 32)
                Text("TendonTally")
                    .font(.system(size: 20, weight: .semibold))
                    .foregroundColor(.primary)
            }
            .padding(.horizontal, 20)
            .padding(.top, 24)
            .padding(.bottom, 32)

            VStack(alignment: .leading, spacing: 4) {
                SidebarButton(
                    title: "Today",
                    icon: "sun.max.fill",
                    isSelected: selectedTab == .today
                ) {
                    withAnimation(.easeInOut(duration: 0.2)) {
                        selectedTabRawValue = Tab.today.rawValue
                    }
                }

                SidebarButton(
                    title: "History",
                    icon: "chart.bar.fill",
                    isSelected: selectedTab == .history
                ) {
                    withAnimation(.easeInOut(duration: 0.2)) {
                        selectedTabRawValue = Tab.history.rawValue
                    }
                }

                SidebarButton(
                    title: "Settings",
                    icon: "gearshape.fill",
                    isSelected: selectedTab == .settings
                ) {
                    withAnimation(.easeInOut(duration: 0.2)) {
                        selectedTabRawValue = Tab.settings.rawValue
                    }
                }

                SidebarButton(
                    title: "KUI",
                    icon: "function",
                    isSelected: selectedTab == .kui
                ) {
                    withAnimation(.easeInOut(duration: 0.2)) {
                        selectedTabRawValue = Tab.kui.rawValue
                    }
                }
            }
            .padding(.horizontal, 12)

            Spacer()
        }
        .frame(width: 220)
        .background(Color(NSColor.controlBackgroundColor))
    }
}

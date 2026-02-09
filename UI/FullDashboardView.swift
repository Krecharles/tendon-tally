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
        case permissions
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
                case .permissions:
                    PermissionsTabView(message: viewModel.permissionIssueMessage ?? "")
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .frame(width: 1000, height: 600)
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
            .padding(.bottom, viewModel.permissionIssueMessage != nil ? 16 : 32)

            if viewModel.permissionIssueMessage != nil {
                VStack(spacing: 0) {
                    Button(action: {
                        withAnimation(.easeInOut(duration: 0.2)) {
                            selectedTabRawValue = Tab.permissions.rawValue
                        }
                    }) {
                        HStack(spacing: 10) {
                            Image(systemName: "exclamationmark.triangle.fill")
                                .font(.system(size: 14, weight: .medium))
                                .foregroundColor(selectedTab == .permissions ? .red : .red.opacity(0.8))
                                .frame(width: 20)

                            Text("Permissions")
                                .font(.system(size: 14, weight: selectedTab == .permissions ? .semibold : .medium))
                                .foregroundColor(selectedTab == .permissions ? .red : .red.opacity(0.8))

                            Spacer()
                        }
                        .padding(.horizontal, 12)
                        .padding(.vertical, 10)
                        .background(
                            RoundedRectangle(cornerRadius: 8)
                                .fill(selectedTab == .permissions ? Color.red.opacity(0.12) : Color.red.opacity(0.06))
                        )
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .padding(.horizontal, 12)

                    Divider()
                        .padding(.horizontal, 12)
                        .padding(.top, 12)
                        .padding(.bottom, 8)
                }
            }

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

            VStack(spacing: 0) {
                Divider()
                    .padding(.horizontal, 12)
                    .padding(.bottom, 8)

                SidebarButton(
                    title: "Settings",
                    icon: "gearshape.fill",
                    isSelected: selectedTab == .settings
                ) {
                    withAnimation(.easeInOut(duration: 0.2)) {
                        selectedTabRawValue = Tab.settings.rawValue
                    }
                }
                .padding(.horizontal, 12)
                .padding(.bottom, 16)
            }
        }
        .frame(width: 220)
        .background(Color(NSColor.controlBackgroundColor))
    }
}

import SwiftUI

struct MainTabView: View {
    @ObservedObject var viewModel: MetricsViewModel
    @State private var selectedTab: Tab = .dashboard
    
    enum Tab {
        case dashboard
        case settings
    }
    
    var body: some View {
        VStack(spacing: 0) {
            // Custom tab bar
            HStack(spacing: 0) {
                TabButton(
                    title: "Dashboard",
                    isSelected: selectedTab == .dashboard
                ) {
                    selectedTab = .dashboard
                }
                
                TabButton(
                    title: "Settings",
                    isSelected: selectedTab == .settings
                ) {
                    selectedTab = .settings
                }
            }
            .padding(.horizontal, 8)
            .padding(.top, 8)
            
            Divider()
            
            // Content
            Group {
                switch selectedTab {
                case .dashboard:
                    DashboardView(viewModel: viewModel)
                case .settings:
                    SettingsView(viewModel: viewModel)
                }
            }
        }
        .frame(width: 400, height: 500)
    }
}

fileprivate struct TabButton: View {
    let title: String
    let isSelected: Bool
    let action: () -> Void
    
    var body: some View {
        Button(action: action) {
            Text(title)
                .font(.subheadline)
                .foregroundColor(isSelected ? .primary : .secondary)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 8)
                .background(
                    Rectangle()
                        .fill(isSelected ? Color.gray.opacity(0.1) : Color.clear)
                )
        }
        .buttonStyle(.plain)
    }
}

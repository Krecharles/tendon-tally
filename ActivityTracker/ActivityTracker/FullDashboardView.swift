import SwiftUI

struct FullDashboardView: View {
    @ObservedObject var viewModel: MetricsViewModel
    @State private var selectedTab: Tab = .dashboard
    
    enum Tab {
        case dashboard
        case settings
    }
    
    private var aggregatedMetrics: AggregatedMetrics {
        viewModel.aggregatedMetrics(for: viewModel.selectedTimeFrame, filters: viewModel.activeMetricFilters)
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
                    dashboardContent
                case .settings:
                    SettingsView(viewModel: viewModel)
                }
            }
        }
        .frame(minWidth: 600, minHeight: 500)
    }
    
    private var dashboardContent: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                header
                timeFrameSelector
                metricTotals
                metricFilterPills
                
                // Bar Chart
                BarChartView(
                    dataPoints: viewModel.timeSeriesData(
                        for: viewModel.selectedTimeFrame,
                        filters: viewModel.activeMetricFilters
                    ),
                    filters: viewModel.activeMetricFilters,
                    timeFrame: viewModel.selectedTimeFrame
                )
                
                permissionBannerIfNeeded
                footerHint
            }
            .padding(16)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }
    
    private var header: some View {
        Text("Dashboard")
            .font(.headline)
    }
    
    private var timeFrameSelector: some View {
        Picker("Time Frame", selection: $viewModel.selectedTimeFrame) {
            ForEach(TimeFrame.allCases, id: \.self) { timeFrame in
                Text(timeFrame.rawValue).tag(timeFrame)
            }
        }
        .pickerStyle(.segmented)
    }
    
    private var metricTotals: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Totals")
                .font(.subheadline)
                .foregroundColor(.secondary)
            
            VStack(alignment: .leading, spacing: 8) {
                HStack(spacing: 8) {
                    metricTotalTile(title: "Keys", value: aggregatedMetrics.keyPressCount)
                    metricTotalTile(title: "Clicks", value: aggregatedMetrics.mouseClickCount)
                }
                HStack(spacing: 8) {
                    metricTotalTile(title: "Scroll kTicks", value: aggregatedMetrics.scrollTicks / 1_000)
                    metricTotalTile(title: "Mouse kPx", value: Int(aggregatedMetrics.mouseDistance / 1_000))
                    let total = aggregatedMetrics.keyPressCount + 
                               aggregatedMetrics.mouseClickCount + 
                               aggregatedMetrics.scrollTicks / 1_000 + 
                               Int(aggregatedMetrics.mouseDistance / 1_000)
                    metricTotalTile(title: "Total", value: total)
                }
            }
        }
    }
    
    private func metricTotalTile(title: String, value: Int) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title)
                .font(.caption)
                .foregroundColor(.secondary)
            Text("\(value)")
                .font(.body.monospacedDigit())
        }
        .padding(8)
        .background(Color.gray.opacity(0.08))
        .cornerRadius(8)
    }
    
    @ViewBuilder
    private var permissionBannerIfNeeded: some View {
        if let message = viewModel.permissionIssueMessage {
            VStack(alignment: .leading, spacing: 6) {
                Text("Permissions Required")
                    .font(.subheadline).bold()
                Text("\(message) Open System Settings → Privacy & Security → Accessibility / Input Monitoring and enable this app.")
                    .font(.caption2)
                    .lineLimit(nil)
                    .multilineTextAlignment(.leading)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            .padding(8)
            .background(Color.red.opacity(0.08))
            .cornerRadius(8)
        } else {
            EmptyView()
        }
    }
    
    private var metricFilterPills: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Metrics")
                .font(.subheadline)
                .foregroundColor(.secondary)
            
            HStack(spacing: 8) {
                ForEach(MetricType.allCases, id: \.self) { metricType in
                    MetricPill(
                        title: metricType.rawValue,
                        metricType: metricType,
                        isSelected: viewModel.activeMetricFilters.contains(metricType)
                    ) {
                        if viewModel.activeMetricFilters.contains(metricType) {
                            viewModel.activeMetricFilters.remove(metricType)
                        } else {
                            viewModel.activeMetricFilters.insert(metricType)
                        }
                    }
                }
            }
        }
    }
    
    private var footerHint: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text("Data stays on your Mac.")
            Text("Only counts and distances are stored, never which keys.")
        }
        .font(.caption2)
        .foregroundColor(.secondary)
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

struct MetricPill: View {
    let title: String
    let metricType: MetricType?
    let isSelected: Bool
    let action: () -> Void
    
    private func color(for metricType: MetricType?) -> Color {
        guard let metricType = metricType else { return .purple }
        switch metricType {
        case .keys:
            return .blue
        case .clicks:
            return .red
        case .scroll:
            return .green
        case .mouseDistance:
            return .orange
        case .aggregate:
            return .purple
        }
    }
    
    var body: some View {
        Button(action: action) {
            Text(title)
                .font(.caption)
                .padding(.horizontal, 12)
                .padding(.vertical, 6)
                .background(isSelected ? color(for: metricType) : Color.gray.opacity(0.1))
                .foregroundColor(isSelected ? .white : .primary)
                .cornerRadius(16)
        }
        .buttonStyle(.plain)
    }
}

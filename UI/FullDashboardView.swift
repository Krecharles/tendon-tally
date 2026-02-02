import SwiftUI
import AppKit

/// Main dashboard view with sidebar navigation and comprehensive metrics display.
struct FullDashboardView: View {
    @ObservedObject var viewModel: MetricsViewModel
    @State private var selectedTab: Tab = .dashboard
    
    enum Tab {
        case dashboard
        case settings
    }
    
    private var todayMetrics: AggregatedMetrics {
        viewModel.todayMetrics()
    }
    
    private var chartMetrics: AggregatedMetrics {
        viewModel.aggregatedMetrics(for: viewModel.selectedTimeFrame, offset: viewModel.timeFrameOffset, filters: viewModel.activeMetricFilters)
    }
    
    var body: some View {
        HStack(spacing: 0) {
            // Left Sidebar
            sidebar
            
            Divider()
                .frame(width: 1)
            
            // Main Content Area
            Group {
                switch selectedTab {
                case .dashboard:
                    dashboardContent
                case .settings:
                    SettingsView(viewModel: viewModel)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .frame(minWidth: 800, minHeight: 600)
        .background(Color(NSColor.windowBackgroundColor))
    }
    
    private var sidebar: some View {
        VStack(alignment: .leading, spacing: 0) {
            // App Title/Header (draggable area)
            VStack(alignment: .leading, spacing: 4) {
                Text("Activity Tracker")
                    .font(.system(size: 20, weight: .semibold))
                    .foregroundColor(.primary)
                Text("Computer Usage")
                    .font(.system(size: 12))
                    .foregroundColor(.secondary)
            }
            .padding(.horizontal, 20)
            .padding(.top, 24)
            .padding(.bottom, 32)
            
            // Navigation Buttons
            VStack(alignment: .leading, spacing: 4) {
                SidebarButton(
                    title: "Dashboard",
                    icon: "chart.bar.fill",
                    isSelected: selectedTab == .dashboard
                ) {
                    withAnimation(.easeInOut(duration: 0.2)) {
                        selectedTab = .dashboard
                    }
                }
                
                SidebarButton(
                    title: "Settings",
                    icon: "gearshape.fill",
                    isSelected: selectedTab == .settings
                ) {
                    withAnimation(.easeInOut(duration: 0.2)) {
                        selectedTab = .settings
                    }
                }
            }
            .padding(.horizontal, 12)
            
            Spacer()
        }
        .frame(width: 220)
        .background(Color(NSColor.controlBackgroundColor))
    }
    
    private var dashboardContent: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                // Custom Title Bar Area
                header
                
                // Today's Totals (always shown, independent of chart time frame)
                todayTotalsSection
                
                Divider()
                
                // Chart Section
                chartSection
                
                permissionBannerIfNeeded
                footerHint
            }
            .padding(24)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }
    
    private var header: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("Dashboard")
                .font(.system(size: 28, weight: .bold))
                .foregroundColor(.primary)
            Text("View your computer usage statistics")
                .font(.system(size: 14))
                .foregroundColor(.secondary)
        }
    }
    
    
    private var todayTotalsSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("Today")
                    .font(.system(size: 20, weight: .bold))
                    .foregroundColor(.primary)
                Spacer()
            }
            
            Grid(alignment: .leading, horizontalSpacing: 12, verticalSpacing: 12) {
                // First row: 3 items (full row)
                GridRow {
                    metricTotalTile(title: "Keys", value: todayMetrics.keyPressCount, icon: "keyboard.fill", color: .blue)
                    metricTotalTile(title: "Clicks", value: todayMetrics.mouseClickCount, icon: "cursorarrow.click", color: .red)
                    metricTotalTile(title: "Scroll kTicks", value: todayMetrics.scrollTicks / 1_000, icon: "arrow.up.arrow.down", color: .green)
                }
                // Second row: 2 items aligned with first two columns
                GridRow {
                    metricTotalTile(title: "Mouse kPx", value: Int(todayMetrics.mouseDistance / 1_000), icon: "arrow.up.left.and.arrow.down.right", color: .orange)
                    let total = todayMetrics.keyPressCount + 
                               todayMetrics.mouseClickCount + 
                               todayMetrics.scrollTicks / 1_000 + 
                               Int(todayMetrics.mouseDistance / 1_000)
                    metricTotalTile(title: "Total", value: total, icon: "chart.bar.fill", color: .purple)
                }
            }
        }
    }
    
    private var chartSection: some View {
        VStack(alignment: .leading, spacing: 16) {
            // Chart Header with Controls
            HStack {
                Text("Activity Over Time")
                    .font(.system(size: 20, weight: .bold))
                    .foregroundColor(.primary)
                Spacer()
            }
            
            // Time Frame Picker and Navigation
            chartControls
            
            // Metric Filter Pills
            metricFilterPills
            
            // Chart Container
            chartContainer
        }
    }
    
    private var chartControls: some View {
        VStack(alignment: .leading, spacing: 12) {
            // Time Frame Picker (no label)
            Picker("", selection: $viewModel.selectedTimeFrame) {
                ForEach(TimeFrame.allCases, id: \.self) { timeFrame in
                    Text(timeFrame.rawValue).tag(timeFrame)
                }
            }
            .pickerStyle(.segmented)
            .onChange(of: viewModel.selectedTimeFrame) { _, _ in
                withAnimation(.easeInOut(duration: 0.2)) {
                    viewModel.timeFrameOffset = 0
                }
            }
            
            // Navigation and Date Range
            HStack(spacing: 12) {
                // Previous period button
                Button(action: {
                    withAnimation(.easeInOut(duration: 0.2)) {
                        viewModel.timeFrameOffset -= 1
                    }
                }) {
                    Image(systemName: "chevron.left")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundColor(.primary)
                        .frame(width: 28, height: 28)
                        .background(Color(NSColor.controlBackgroundColor))
                        .clipShape(RoundedRectangle(cornerRadius: 6))
                }
                .buttonStyle(.plain)
                .help("Previous period")
                
                // Date Range Display
                dateRangeLabel
                    .frame(maxWidth: .infinity)
                
                // Next period button
                Button(action: {
                    withAnimation(.easeInOut(duration: 0.2)) {
                        viewModel.timeFrameOffset += 1
                        if viewModel.timeFrameOffset > 0 {
                            viewModel.timeFrameOffset = 0
                        }
                    }
                }) {
                    Image(systemName: "chevron.right")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundColor(viewModel.timeFrameOffset >= 0 ? .secondary : .primary)
                        .frame(width: 28, height: 28)
                        .background(Color(NSColor.controlBackgroundColor))
                        .clipShape(RoundedRectangle(cornerRadius: 6))
                }
                .buttonStyle(.plain)
                .disabled(viewModel.timeFrameOffset >= 0)
                .help("Next period")
            }
        }
    }
    
    private var dateRangeLabel: some View {
        let (startDate, endDate) = viewModel.selectedTimeFrame.dateRange(offset: viewModel.timeFrameOffset)
        let calendar = Calendar.current
        let formatter = DateFormatter()
        
        let rangeText: String
        if viewModel.timeFrameOffset == 0 {
            switch viewModel.selectedTimeFrame {
            case .today:
                rangeText = "Today"
            case .lastWeek:
                rangeText = "Last 7 Days"
            case .lastMonth:
                rangeText = "Last Month"
            }
        } else {
            formatter.dateFormat = "MMM d"
            let startStr = formatter.string(from: startDate)
            
            // For past periods, format end date appropriately
            switch viewModel.selectedTimeFrame {
            case .today:
                // Past days: show the date
                formatter.dateFormat = "EEEE, MMM d"
                rangeText = formatter.string(from: startDate)
            case .lastWeek:
                // Past weeks: show date range
                formatter.dateFormat = "MMM d"
                let endStr = formatter.string(from: endDate)
                let startYear = calendar.component(.year, from: startDate)
                let endYear = calendar.component(.year, from: endDate)
                if startYear == endYear {
                    rangeText = "\(startStr) - \(endStr)"
                } else {
                    formatter.dateFormat = "MMM d, yyyy"
                    let endStrWithYear = formatter.string(from: endDate)
                    rangeText = "\(startStr) - \(endStrWithYear)"
                }
            case .lastMonth:
                // Past months: show month and year
                formatter.dateFormat = "MMMM yyyy"
                rangeText = formatter.string(from: startDate)
            }
        }
        
        return Text(rangeText)
            .font(.system(size: 13, weight: .medium))
            .foregroundColor(.secondary)
            .multilineTextAlignment(.center)
    }
    
    private var chartContainer: some View {
        let dataPoints = viewModel.timeSeriesData(
            for: viewModel.selectedTimeFrame,
            offset: viewModel.timeFrameOffset,
            filters: viewModel.activeMetricFilters
        )
        
        // Calculate consistent width based on time frame type
        // This prevents jarring resizes when navigating between periods
        // Use expected maximum buckets for each time frame type
        let expectedBuckets: Int = {
            switch viewModel.selectedTimeFrame {
            case .today:
                return 12 // 24 hours / 2-hour intervals
            case .lastWeek:
                return 7 // 7 days
            case .lastMonth:
                return 15 // ~30 days / 2-day intervals
            }
        }()
        
        let bucketWidth: CGFloat = 50
        let minChartWidth = CGFloat(expectedBuckets) * bucketWidth
        
        return GeometryReader { geometry in
            let availableWidth = geometry.size.width - 32 // Account for horizontal padding
            let chartWidth = max(availableWidth, minChartWidth)
            
            ScrollView(.horizontal, showsIndicators: true) {
                BarChartView(
                    dataPoints: dataPoints,
                    filters: viewModel.activeMetricFilters,
                    timeFrame: viewModel.selectedTimeFrame
                )
                .frame(
                    width: chartWidth,
                    height: 400
                )
                .padding(.vertical, 16)
                .padding(.horizontal, 16)
            }
        }
        .frame(height: 432) // 400 + 32 padding
        .background(Color(NSColor.controlBackgroundColor))
        .clipShape(RoundedRectangle(cornerRadius: 12))
    }
    
    private func metricTotalTile(title: String, value: Int, icon: String, color: Color) -> some View {
        HStack(spacing: 12) {
            Image(systemName: icon)
                .font(.system(size: 20))
                .foregroundColor(color)
                .frame(width: 32, height: 32)
                .background(color.opacity(0.1))
                .clipShape(RoundedRectangle(cornerRadius: 8))
            
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.system(size: 12))
                    .foregroundColor(.secondary)
                Text("\(value)")
                    .font(.system(size: 18, weight: .semibold, design: .monospaced))
                    .foregroundColor(.primary)
            }
            
            Spacer()
        }
        .padding(12)
        .background(Color(NSColor.controlBackgroundColor))
        .clipShape(RoundedRectangle(cornerRadius: 12))
    }
    
    @ViewBuilder
    private var permissionBannerIfNeeded: some View {
        if let message = viewModel.permissionIssueMessage {
            HStack(alignment: .top, spacing: 12) {
                Image(systemName: "exclamationmark.triangle.fill")
                    .font(.system(size: 18))
                    .foregroundColor(.red)
                
                VStack(alignment: .leading, spacing: 4) {
                    Text("Permissions Required")
                        .font(.system(size: 14, weight: .semibold))
                    Text("\(message) Open System Settings → Privacy & Security → Accessibility / Input Monitoring and enable this app.")
                        .font(.system(size: 12))
                        .lineLimit(nil)
                        .multilineTextAlignment(.leading)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            .padding(16)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Color.red.opacity(0.1))
            .clipShape(RoundedRectangle(cornerRadius: 12))
        } else {
            EmptyView()
        }
    }
    
    private var metricFilterPills: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Metrics")
                .font(.system(size: 16, weight: .semibold))
                .foregroundColor(.primary)
            
            HStack(spacing: 10) {
                ForEach(MetricType.allCases, id: \.self) { metricType in
                    MetricPill(
                        title: metricType.rawValue,
                        metricType: metricType,
                        isSelected: viewModel.activeMetricFilters.contains(metricType)
                    ) {
                        withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) {
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
    }
    
    private var footerHint: some View {
        HStack(spacing: 8) {
            Image(systemName: "lock.shield.fill")
                .font(.system(size: 12))
                .foregroundColor(.secondary)
            VStack(alignment: .leading, spacing: 2) {
                Text("Data stays on your Mac.")
                Text("Only counts and distances are stored, never which keys.")
            }
            .font(.system(size: 11))
            .foregroundColor(.secondary)
        }
        .padding(.top, 8)
    }
}

/// Sidebar navigation button component.
struct SidebarButton: View {
    let title: String
    let icon: String
    let isSelected: Bool
    let action: () -> Void
    
    var body: some View {
        Button(action: action) {
            HStack(spacing: 10) {
                Image(systemName: icon)
                    .font(.system(size: 14, weight: .medium))
                    .foregroundColor(isSelected ? .accentColor : .secondary)
                    .frame(width: 20)
                
                Text(title)
                    .font(.system(size: 14, weight: isSelected ? .semibold : .regular))
                    .foregroundColor(isSelected ? .primary : .secondary)
                
                Spacer()
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 10)
            .background(
                RoundedRectangle(cornerRadius: 8)
                    .fill(isSelected ? Color.accentColor.opacity(0.1) : Color.clear)
            )
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}

/// Metric filter pill button component.
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
                .font(.system(size: 13, weight: isSelected ? .semibold : .regular))
                .padding(.horizontal, 14)
                .padding(.vertical, 8)
                .background(
                    RoundedRectangle(cornerRadius: 20)
                        .fill(isSelected ? color(for: metricType) : Color(NSColor.controlBackgroundColor))
                )
                .foregroundColor(isSelected ? .white : .primary)
                .overlay(
                    RoundedRectangle(cornerRadius: 20)
                        .stroke(isSelected ? Color.clear : Color(NSColor.separatorColor), lineWidth: 1)
                )
        }
        .buttonStyle(.plain)
    }
}

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
                case .today:
                    todayContent
                case .history:
                    historyContent
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
            }
            .padding(.horizontal, 20)
            .padding(.top, 24)
            .padding(.bottom, 32)
            
            // Navigation Buttons
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
            }
            .padding(.horizontal, 12)
            
            Spacer()
        }
        .frame(width: 220)
        .background(Color(NSColor.controlBackgroundColor))
    }
    
    private var todayContent: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                // Custom Title Bar Area
                VStack(alignment: .leading, spacing: 4) {
                    Text("Today")
                        .font(.system(size: 28, weight: .bold))
                        .foregroundColor(.primary)
                }
                
                // Today's Totals
                todayTotalsSection
                
                permissionBannerIfNeeded
                unitsExplanation
            }
            .padding(24)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }
    
    private var historyContent: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                // Header Section
                headerSection
                    .padding(.bottom, 24)
                
                // Controls Card
                controlsCard
                
                // Chart Section
                chartSection
                    .padding(.bottom, 20)
                
                permissionBannerIfNeeded
                    .padding(.bottom, 12)
                
                unitsExplanation
                    .padding(.top, 4)
            }
            .padding(24)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }
    
    private var headerSection: some View {
        HStack(alignment: .firstTextBaseline, spacing: 16) {
            Text("History")
                .font(.system(size: 32, weight: .bold))
                .foregroundColor(.primary)
            
            Spacer()
        }
    }
    
    private var controlsCard: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Compact horizontal layout: Time controls on left, Metrics on right
            GeometryReader { geometry in
                HStack(alignment: .top, spacing: 20) {
                    // Time Period & Date Range - Combined compact control
                    timeAndDateControls
                        .frame(maxWidth: .infinity, alignment: .leading)
                    
                    Divider()
                        .frame(height: geometry.size.height)
                    
                    // Metric Filters - Compact grid layout
                    metricFilterSection
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
            }
            .frame(minHeight: 80)
        }
        .padding(.top, 16)
        .padding(.trailing, 16)
        .padding(.bottom, 16)
        .background(Color(NSColor.controlBackgroundColor))
        .clipShape(RoundedRectangle(cornerRadius: 12))
    }
    
    private var metricFilterSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Metrics")
                .font(.system(size: 10, weight: .semibold))
                .foregroundColor(.secondary)
                .textCase(.uppercase)
                .tracking(0.5)
                .frame(height: 14, alignment: .top)
            
            // Compact grid: optimized for 5 items (3+2 layout)
            LazyVGrid(columns: [
                GridItem(.flexible(minimum: 60), spacing: 6),
                GridItem(.flexible(minimum: 60), spacing: 6),
                GridItem(.flexible(minimum: 60), spacing: 6)
            ], alignment: .leading, spacing: 6) {
                ForEach(MetricType.allCases, id: \.self) { metricType in
                    MetricPill(
                        title: metricType.rawValue,
                        metricType: metricType,
                        isSelected: viewModel.activeMetricFilters.contains(metricType)
                    ) {
                        withAnimation(.spring(response: 0.25, dampingFraction: 0.7)) {
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
    
    private var timeAndDateControls: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Time Period")
                .font(.system(size: 10, weight: .semibold))
                .foregroundColor(.secondary)
                .textCase(.uppercase)
                .tracking(0.5)
                .frame(height: 14, alignment: .top)
            
            // Compact time period selector with integrated date navigation
            VStack(spacing: 8) {
                // Time frame selector - compact segmented style
                HStack(spacing: 4) {
                    ForEach(TimeFrame.allCases, id: \.self) { timeFrame in
                        Button(action: {
                            withAnimation(.spring(response: 0.25, dampingFraction: 0.7)) {
                                viewModel.selectedTimeFrame = timeFrame
                                viewModel.timeFrameOffset = 0
                            }
                        }) {
                            Text(timeFrame.rawValue)
                                .font(.system(size: 12, weight: viewModel.selectedTimeFrame == timeFrame ? .semibold : .regular))
                                .foregroundColor(viewModel.selectedTimeFrame == timeFrame ? .white : .primary)
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 6)
                                .background(
                                    RoundedRectangle(cornerRadius: 6)
                                        .fill(viewModel.selectedTimeFrame == timeFrame ? Color.accentColor : Color(NSColor.windowBackgroundColor))
                                )
                                .overlay(
                                    RoundedRectangle(cornerRadius: 6)
                                        .stroke(viewModel.selectedTimeFrame == timeFrame ? Color.clear : Color(NSColor.separatorColor), lineWidth: 1)
                                )
                        }
                        .buttonStyle(.plain)
                    }
                }
                
                // Compact date range navigator
                HStack(spacing: 6) {
                    Button(action: {
                        withAnimation(.spring(response: 0.25, dampingFraction: 0.7)) {
                            viewModel.timeFrameOffset -= 1
                        }
                    }) {
                        Image(systemName: "chevron.left")
                            .font(.system(size: 11, weight: .semibold))
                            .foregroundColor(.primary)
                            .frame(width: 28, height: 28)
                            .background(Color(NSColor.windowBackgroundColor))
                            .clipShape(RoundedRectangle(cornerRadius: 6))
                    }
                    .buttonStyle(.plain)
                    .help("Previous period")
                    
                    Text(dateRangeLabelText)
                        .font(.system(size: 12, weight: .medium))
                        .foregroundColor(.primary)
                        .frame(maxWidth: .infinity)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 6)
                        .background(Color(NSColor.windowBackgroundColor))
                        .clipShape(RoundedRectangle(cornerRadius: 6))
                        .lineLimit(1)
                        .minimumScaleFactor(0.8)
                    
                    Button(action: {
                        withAnimation(.spring(response: 0.25, dampingFraction: 0.7)) {
                            viewModel.timeFrameOffset += 1
                            if viewModel.timeFrameOffset > 0 {
                                viewModel.timeFrameOffset = 0
                            }
                        }
                    }) {
                        Image(systemName: "chevron.right")
                            .font(.system(size: 11, weight: .semibold))
                            .foregroundColor(viewModel.timeFrameOffset >= 0 ? .secondary : .primary)
                            .frame(width: 28, height: 28)
                            .background(Color(NSColor.windowBackgroundColor))
                            .clipShape(RoundedRectangle(cornerRadius: 6))
                    }
                    .buttonStyle(.plain)
                    .disabled(viewModel.timeFrameOffset >= 0)
                    .help("Next period")
                }
            }
        }
    }
    
    private var chartSection: some View {
        VStack(alignment: .leading, spacing: 0) {
            chartContainer
        }
    }
    
    
    private var todayTotalsSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            
            Grid(alignment: .leading, horizontalSpacing: 12, verticalSpacing: 12) {
                // First row: 3 items (full row)
                GridRow {
                    metricTotalTile(title: "Keys", value: todayMetrics.keyPressCount, icon: "keyboard.fill", color: .blue)
                    metricTotalTile(title: "Clicks", value: todayMetrics.mouseClickCount, icon: "cursorarrow.click", color: .red)
                    metricTotalTile(title: "Scroll ticks (100s)", value: todayMetrics.scrollTicks / 100, icon: "arrow.up.arrow.down", color: .green)
                }
                // Second row: 2 items aligned with first two columns
                GridRow {
                    metricTotalTile(title: "Mouse pixels (1000s)", value: Int(todayMetrics.mouseDistance / 1_000), icon: "arrow.up.left.and.arrow.down.right", color: .orange)
                    let total = todayMetrics.keyPressCount + 
                               todayMetrics.mouseClickCount + 
                               todayMetrics.scrollTicks / 100 + 
                               Int(todayMetrics.mouseDistance / 1_000)
                    metricTotalTile(title: "Total", value: total, icon: "chart.bar.fill", color: .purple)
                }
            }
        }
    }
    
    private var unitsExplanation: some View {
        Text("Units are scaled so typical values are of a similar magnitude for an average user (scroll ticks in 100s, mouse distance in 1000s of pixels).")
            .font(.caption2)
            .foregroundColor(.secondary)
            .fixedSize(horizontal: false, vertical: true)
    }
    
    
    private var dateRangeLabelText: String {
        let (startDate, endDate) = viewModel.selectedTimeFrame.dateRange(offset: viewModel.timeFrameOffset)
        let calendar = Calendar.current
        let formatter = DateFormatter()
        
        if viewModel.timeFrameOffset == 0 {
            switch viewModel.selectedTimeFrame {
            case .today:
                return "Today"
            case .lastWeek:
                return "Last 7 days"
            case .lastMonth:
                return "Last 30 days"
            }
        } else {
            // For past periods, show formatted date range
            switch viewModel.selectedTimeFrame {
            case .today:
                formatter.dateFormat = "EEEE, MMM d"
                return formatter.string(from: startDate)
            case .lastWeek:
                formatter.dateFormat = "MMM d"
                let startStr = formatter.string(from: startDate)
                let endStr = formatter.string(from: endDate)
                let startYear = calendar.component(.year, from: startDate)
                let endYear = calendar.component(.year, from: endDate)
                if startYear == endYear {
                    return "\(startStr) - \(endStr)"
                } else {
                    formatter.dateFormat = "MMM d, yyyy"
                    let endStrWithYear = formatter.string(from: endDate)
                    return "\(startStr) - \(endStrWithYear)"
                }
            case .lastMonth:
                formatter.dateFormat = "MMMM yyyy"
                return formatter.string(from: startDate)
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
            .multilineTextAlignment(.center)
    }
    
    private var chartContainer: some View {
        let dataPoints = viewModel.timeSeriesData(
            for: viewModel.selectedTimeFrame,
            offset: viewModel.timeFrameOffset,
            filters: viewModel.activeMetricFilters
        )
        
        return VStack(alignment: .leading, spacing: 0) {
            GeometryReader { geometry in
                let availableWidth = geometry.size.width
                
                BarChartView(
                    dataPoints: dataPoints,
                    filters: viewModel.activeMetricFilters,
                    timeFrame: viewModel.selectedTimeFrame
                )
                .frame(
                    width: availableWidth,
                    height: 400
                )
                .padding(.vertical, 20)
            }
            .frame(height: 440) // 400 + 40 padding
        }
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

/// Metric filter pill button component - compact version.
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
                .font(.system(size: 11, weight: isSelected ? .semibold : .regular))
                .lineLimit(1)
                .minimumScaleFactor(0.8)
                .padding(.horizontal, 10)
                .padding(.vertical, 5)
                .frame(maxWidth: .infinity)
                .background(
                    RoundedRectangle(cornerRadius: 6)
                        .fill(isSelected ? color(for: metricType) : Color(NSColor.windowBackgroundColor))
                )
                .foregroundColor(isSelected ? .white : .primary)
                .overlay(
                    RoundedRectangle(cornerRadius: 6)
                        .stroke(isSelected ? Color.clear : Color(NSColor.separatorColor), lineWidth: 1)
                )
        }
        .buttonStyle(.plain)
    }
}

/// Period selection pill button component.
struct PeriodPill: View {
    let title: String
    let timeFrame: TimeFrame
    let isSelected: Bool
    let viewModel: MetricsViewModel
    
    var body: some View {
        Button(action: {
            withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) {
                viewModel.selectedTimeFrame = timeFrame
                viewModel.timeFrameOffset = 0
            }
        }) {
            Text(title)
                .font(.system(size: 13, weight: isSelected ? .semibold : .regular))
                .padding(.horizontal, 14)
                .padding(.vertical, 8)
                .background(
                    RoundedRectangle(cornerRadius: 20)
                        .fill(isSelected ? Color.accentColor : Color(NSColor.controlBackgroundColor))
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

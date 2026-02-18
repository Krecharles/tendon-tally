import SwiftUI

struct HistoryTabView: View {
    @ObservedObject var viewModel: MetricsViewModel

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                headerSection
                    .padding(.bottom, 20)

                HStack(spacing: 12) {
                    timeFrameSelector
                    dateNavigation
                }
                .padding(.bottom, 12)

                metricFilters
                    .padding(.bottom, 20)

                summaryCard
                chartCard
            }
            .padding(.horizontal, 24)
            .padding(.bottom, 24)
            .padding(.top, 8)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }

    private var headerSection: some View {
        Text("History")
            .font(.system(size: 28, weight: .bold))
            .foregroundColor(.primary)
    }

    // MARK: - Time Frame Selector

    private var timeFrameSelector: some View {
        HStack(spacing: 2) {
            ForEach(TimeFrame.allCases, id: \.self) { timeFrame in
                let isSelected = viewModel.selectedTimeFrame == timeFrame
                Button(action: {
                    withAnimation(.easeInOut(duration: 0.15)) {
                        viewModel.selectedTimeFrame = timeFrame
                        viewModel.timeFrameOffset = 0
                    }
                }) {
                    Text(timeFrame.rawValue)
                        .font(.system(size: 12, weight: isSelected ? .semibold : .regular))
                        .foregroundColor(isSelected ? .white : .secondary)
                        .padding(.horizontal, 16)
                        .padding(.vertical, 7)
                        .background(
                            RoundedRectangle(cornerRadius: 6)
                                .fill(isSelected ? Color.accentColor : Color.clear)
                        )
                }
                .buttonStyle(.plain)
            }
        }
        .padding(3)
        .background(
            RoundedRectangle(cornerRadius: 8)
                .fill(Color(NSColor.windowBackgroundColor).opacity(0.5))
                .overlay(
                    RoundedRectangle(cornerRadius: 8)
                        .stroke(Color(NSColor.separatorColor).opacity(0.3), lineWidth: 1)
                )
        )
    }

    // MARK: - Date Navigation

    private var dateNavigation: some View {
        HStack(spacing: 8) {
            Button(action: {
                withAnimation(.easeInOut(duration: 0.15)) {
                    viewModel.timeFrameOffset -= 1
                }
            }) {
                Image(systemName: "chevron.left")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundColor(.secondary)
                    .frame(width: 36, height: 36)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)

            Text(dateRangeLabelText)
                .font(.system(size: 13, weight: .medium))
                .foregroundColor(.primary)

            Button(action: {
                withAnimation(.easeInOut(duration: 0.15)) {
                    viewModel.timeFrameOffset += 1
                    if viewModel.timeFrameOffset > 0 {
                        viewModel.timeFrameOffset = 0
                    }
                }
            }) {
                Image(systemName: "chevron.right")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundColor(viewModel.timeFrameOffset >= 0 ? .secondary.opacity(0.3) : .secondary)
                    .frame(width: 36, height: 36)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .disabled(viewModel.timeFrameOffset >= 0)

            if viewModel.timeFrameOffset != 0 {
                Button(action: {
                    withAnimation(.easeInOut(duration: 0.15)) {
                        viewModel.timeFrameOffset = 0
                    }
                }) {
                    Text("Today")
                        .font(.system(size: 11, weight: .medium))
                        .foregroundColor(.white)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 5)
                        .background(Capsule().fill(Color.accentColor))
                }
                .buttonStyle(.plain)
                .transition(.opacity.combined(with: .scale))
            }
        }
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
                    return "\(startStr) \u{2013} \(endStr)"
                } else {
                    formatter.dateFormat = "MMM d, yyyy"
                    let endStrWithYear = formatter.string(from: endDate)
                    return "\(startStr) \u{2013} \(endStrWithYear)"
                }
            case .lastMonth:
                formatter.dateFormat = "MMM d"
                let startStr = formatter.string(from: startDate)
                let endStr = formatter.string(from: endDate)
                let startYear = calendar.component(.year, from: startDate)
                let endYear = calendar.component(.year, from: endDate)
                if startYear == endYear {
                    return "\(startStr) \u{2013} \(endStr)"
                } else {
                    formatter.dateFormat = "MMM d, yyyy"
                    let endStrWithYear = formatter.string(from: endDate)
                    return "\(startStr) \u{2013} \(endStrWithYear)"
                }
            }
        }
    }

    // MARK: - Chart Card (chart + summary footer)

    private var chartCard: some View {
        let dataPoints = viewModel.timeSeriesData(
            for: viewModel.selectedTimeFrame,
            offset: viewModel.timeFrameOffset
        )

        return BarChartView(
            dataPoints: dataPoints,
            selectedMetric: viewModel.selectedMetric,
            timeFrame: viewModel.selectedTimeFrame,
            totalConfig: viewModel.effectiveTotalConfig,
            hasAnyData: hasAnyData
        )
        .frame(height: 340)
        .padding(.horizontal, 12)
        .padding(.vertical, 12)
        .background(Color(NSColor.controlBackgroundColor))
        .clipShape(UnevenRoundedRectangle(topLeadingRadius: 0, bottomLeadingRadius: 12, bottomTrailingRadius: 12, topTrailingRadius: 0))
    }

    private var hasAnyData: Bool {
        let allData = viewModel.timeSeriesData(for: .lastMonth, offset: 0)
        return allData.contains { $0.keyPressCount > 0 || $0.mouseClickCount > 0 || $0.scrollTicks > 0 || $0.mouseDistance > 0 }
    }

    // MARK: - Metric Filters

    private var metricFilters: some View {
        HStack(spacing: 6) {
            ForEach(MetricType.allCases, id: \.self) { metricType in
                MetricPill(
                    title: metricType.rawValue,
                    metricType: metricType,
                    isSelected: viewModel.selectedMetric == metricType
                ) {
                    withAnimation(.easeInOut(duration: 0.15)) {
                        viewModel.selectedMetric = metricType
                    }
                }
            }

            Spacer()
        }
    }

    // MARK: - Summary Stats

    @State private var showingChangeInfo = false

    private var summaryCard: some View {
        let stats = viewModel.comparisonStats(
            for: viewModel.selectedTimeFrame,
            offset: viewModel.timeFrameOffset
        )

        return HStack(alignment: .firstTextBaseline, spacing: 8) {
            Circle()
                .fill(viewModel.selectedMetric.color)
                .frame(width: 8, height: 8)

            Text("\(formattedTotal(stats.currentTotal)) \(viewModel.selectedMetric.unitLabel)")
                .font(.system(size: 13, weight: .medium))
                .foregroundColor(.primary)

            Text("this period")
                .font(.system(size: 12))
                .foregroundColor(.secondary)

            if let pct = stats.percentageChange {
                let changeColor: Color = abs(pct) > 20 ? .red : .green

                HStack(spacing: 4) {
                    Text(formattedPercentage(pct))
                        .font(.system(size: 12, weight: .medium))
                        .foregroundColor(changeColor)

                    Button(action: { showingChangeInfo.toggle() }) {
                        Image(systemName: "questionmark.circle")
                            .font(.system(size: 11))
                            .foregroundColor(.secondary.opacity(0.6))
                    }
                    .buttonStyle(.plain)
                    .popover(isPresented: $showingChangeInfo, arrowEdge: .bottom) {
                        Text("This shows how your activity changed compared to the previous period. Many users aim to keep increases within 20% to gradually adapt to workload changes and reduce the risk of repetitive strain.")
                            .font(.system(size: 12))
                            .foregroundColor(.primary)
                            .frame(width: 240)
                            .padding(12)
                    }
                }
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color(NSColor.controlBackgroundColor))
        .clipShape(UnevenRoundedRectangle(topLeadingRadius: 12, bottomLeadingRadius: 0, bottomTrailingRadius: 0, topTrailingRadius: 12))
    }

    private func formattedTotal(_ value: Double) -> String {
        if value >= 1000 {
            let formatter = NumberFormatter()
            formatter.numberStyle = .decimal
            formatter.maximumFractionDigits = 0
            return formatter.string(from: NSNumber(value: value)) ?? String(format: "%.0f", value)
        }
        switch viewModel.selectedMetric {
        case .keys, .clicks:
            return String(format: "%.0f", value)
        case .scroll, .mouseDistance, .aggregate:
            return String(format: "%.1f", value)
        }
    }

    private func formattedPercentage(_ pct: Double) -> String {
        let sign = pct > 0 ? "+" : ""
        return "\(sign)\(String(format: "%.0f", pct))%"
    }
}

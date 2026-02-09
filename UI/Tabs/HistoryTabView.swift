import SwiftUI

struct HistoryTabView: View {
    @ObservedObject var viewModel: MetricsViewModel

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                headerSection
                    .padding(.bottom, 20)

                timeFrameSelector
                    .padding(.bottom, 12)

                dateNavigation
                    .padding(.bottom, 20)

                chartSection

                metricFilters
                    .padding(.top, 14)

                unitsExplanation
                    .padding(.top, 16)
            }
            .padding(24)
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
                Button(action: {
                    withAnimation(.easeInOut(duration: 0.15)) {
                        viewModel.selectedTimeFrame = timeFrame
                        viewModel.timeFrameOffset = 0
                    }
                }) {
                    Text(timeFrame.rawValue)
                        .font(.system(size: 12, weight: viewModel.selectedTimeFrame == timeFrame ? .semibold : .regular))
                        .foregroundColor(viewModel.selectedTimeFrame == timeFrame ? .primary : .secondary)
                        .padding(.horizontal, 16)
                        .padding(.vertical, 7)
                        .background(
                            RoundedRectangle(cornerRadius: 6)
                                .fill(viewModel.selectedTimeFrame == timeFrame ? Color(NSColor.controlBackgroundColor) : Color.clear)
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
                    .frame(width: 28, height: 28)
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
                    .frame(width: 28, height: 28)
            }
            .buttonStyle(.plain)
            .disabled(viewModel.timeFrameOffset >= 0)

            Spacer()
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
                formatter.dateFormat = "MMMM yyyy"
                return formatter.string(from: startDate)
            }
        }
    }

    // MARK: - Chart

    private var chartSection: some View {
        let dataPoints = viewModel.timeSeriesData(
            for: viewModel.selectedTimeFrame,
            offset: viewModel.timeFrameOffset,
            filters: viewModel.activeMetricFilters
        )

        return BarChartView(
            dataPoints: dataPoints,
            filters: viewModel.activeMetricFilters,
            timeFrame: viewModel.selectedTimeFrame,
            kuiConfig: viewModel.kuiConfig
        )
        .frame(height: 340)
        .padding(16)
        .background(Color(NSColor.controlBackgroundColor))
        .clipShape(RoundedRectangle(cornerRadius: 12))
    }

    // MARK: - Metric Filters

    private var metricFilters: some View {
        HStack(spacing: 6) {
            ForEach(MetricType.allCases, id: \.self) { metricType in
                MetricPill(
                    title: metricType.rawValue,
                    metricType: metricType,
                    isSelected: viewModel.activeMetricFilters.contains(metricType)
                ) {
                    withAnimation(.easeInOut(duration: 0.15)) {
                        if viewModel.activeMetricFilters.contains(metricType) {
                            viewModel.activeMetricFilters.remove(metricType)
                        } else {
                            viewModel.activeMetricFilters.insert(metricType)
                        }
                    }
                }
            }

            Spacer()
        }
    }

    private var unitsExplanation: some View {
        Text("Scroll ticks in 100s, mouse distance in 1000s of pixels. KUI uses weights from the KUI tab.")
            .font(.system(size: 11))
            .foregroundColor(.secondary)
    }
}

import SwiftUI

struct HistoryTabView: View {
    @ObservedObject var viewModel: MetricsViewModel

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                headerSection
                    .padding(.bottom, 24)

                controlsCard

                chartSection
                    .padding(.bottom, 20)

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
            GeometryReader { geometry in
                HStack(alignment: .top, spacing: 20) {
                    timeAndDateControls
                        .frame(maxWidth: .infinity, alignment: .leading)

                    Divider()
                        .frame(height: geometry.size.height)

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

            VStack(spacing: 8) {
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

    private var chartSection: some View {
        VStack(alignment: .leading, spacing: 0) {
            chartContainer
        }
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
                    timeFrame: viewModel.selectedTimeFrame,
                    kuiConfig: viewModel.kuiConfig
                )
                .frame(
                    width: availableWidth,
                    height: 400
                )
                .padding(.vertical, 20)
            }
            .frame(height: 440)
        }
        .background(Color(NSColor.controlBackgroundColor))
        .clipShape(RoundedRectangle(cornerRadius: 12))
    }

    private var unitsExplanation: some View {
        Text("Units are scaled so typical values are of a similar magnitude for an average user (scroll ticks in 100s, mouse distance in 1000s of pixels). KUI uses your configured weights from the KUI tab.")
            .font(.caption2)
            .foregroundColor(.secondary)
            .fixedSize(horizontal: false, vertical: true)
    }
}

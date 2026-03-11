import SwiftUI
import Charts

struct BarChartView: View {
    let dataPoints: [TimeSeriesDataPoint]
    let selectedMetric: MetricType
    let timeFrame: TimeFrame
    let monthAggregation: MonthAggregation
    let totalConfig: TotalConfig
    let hasAnyData: Bool

    @State private var hoveredBarTime: Date?

    private struct WeeklyAverageSegment: Identifiable {
        let weekStart: Date
        let visibleStart: Date
        let visibleEndExclusive: Date
        let average: Double

        var id: Date { weekStart }
    }

    private var isWeeklyOverlayMode: Bool {
        timeFrame == .lastMonth && monthAggregation == .week
    }

    private func value(for point: TimeSeriesDataPoint) -> Double {
        switch selectedMetric {
        case .keys:
            return Double(point.keyPressCount)
        case .clicks:
            return Double(point.mouseClickCount)
        case .scroll:
            return Double(point.scrollTicks) / 100.0
        case .mouseDistance:
            return point.mouseDistance / 1000.0
        case .aggregate:
            let metrics = AggregatedMetrics(
                keyPressCount: point.keyPressCount,
                mouseClickCount: point.mouseClickCount,
                scrollTicks: point.scrollTicks,
                mouseDistance: point.mouseDistance
            )
            return totalConfig.apply(to: metrics)
        }
    }

    private func formatValue(_ value: Double) -> String {
        switch selectedMetric {
        case .keys, .clicks:
            return String(format: "%.0f", value)
        case .scroll, .mouseDistance, .aggregate:
            return String(format: "%.1f", value)
        }
    }

    private func formattedOverlayValue(_ value: Double) -> String {
        String(format: "%.0f", value)
    }

    private var averageValue: Double? {
        guard timeFrame != .today else { return nil }
        guard !isWeeklyOverlayMode else { return nil }
        let values = dataPoints.map { value(for: $0) }
        let nonZero = values.filter { $0 > 0 }
        guard !nonZero.isEmpty else { return nil }
        return nonZero.reduce(0, +) / Double(nonZero.count)
    }

    private var weeklyAverageSegments: [WeeklyAverageSegment] {
        guard isWeeklyOverlayMode else { return [] }

        let calendar = Calendar.current
        let grouped = Dictionary(grouping: dataPoints) { isoWeekStart(for: $0.time) }

        return grouped
            .keys
            .sorted()
            .compactMap { weekStart in
                guard let points = grouped[weekStart]?.sorted(by: { $0.time < $1.time }),
                      let first = points.first,
                      let last = points.last else {
                    return nil
                }

                let values = points.map { value(for: $0) }
                let average = values.reduce(0, +) / Double(values.count)
                let endExclusive = calendar.date(byAdding: .day, value: 1, to: last.time) ?? last.time

                return WeeklyAverageSegment(
                    weekStart: weekStart,
                    visibleStart: first.time,
                    visibleEndExclusive: endExclusive,
                    average: average
                )
            }
    }

    private var verticalBarStyle: AnyShapeStyle {
        if isWeeklyOverlayMode {
            return AnyShapeStyle(Color.secondary.opacity(0.28))
        }
        return AnyShapeStyle(selectedMetric.color.gradient)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            if dataPoints.isEmpty {
                emptyState
            } else {
                chartView
            }
        }
        .padding(0)
    }

    private var emptyState: some View {
        VStack(spacing: 8) {
            Image(systemName: "chart.bar.xaxis")
                .font(.system(size: 28))
                .foregroundColor(.secondary.opacity(0.5))
            Text(hasAnyData ? "No data for this period" : "No data recorded yet")
                .font(.caption)
                .foregroundColor(.secondary)
            if !hasAnyData {
                Text("Start using your keyboard and mouse to see activity here.")
                    .font(.caption2)
                    .foregroundColor(.secondary.opacity(0.7))
            }
        }
        .frame(maxWidth: .infinity, alignment: .center)
        .padding(.vertical, 40)
    }

    private var hoveredPoint: TimeSeriesDataPoint? {
        guard let hoveredTime = hoveredBarTime else { return nil }
        guard let point = selectedDataPoint(for: hoveredTime) else { return nil }
        guard value(for: point) > 0 else { return nil }
        return point
    }

    private var chartView: some View {
        Chart {
            ForEach(dataPoints) { point in
                BarMark(
                    x: .value("Time", point.time, unit: timeUnit),
                    y: .value("Value", value(for: point))
                )
                .foregroundStyle(verticalBarStyle)
                .opacity(hoveredPoint != nil && !isSameBucket(point.time, hoveredPoint!.time) ? 0.4 : 1.0)
            }

            ForEach(weeklyAverageSegments) { segment in
                RuleMark(
                    xStart: .value("Week Start", segment.visibleStart),
                    xEnd: .value("Week End", segment.visibleEndExclusive),
                    y: .value("Weekly Average", segment.average)
                )
                .lineStyle(StrokeStyle(lineWidth: 6, lineCap: .round, lineJoin: .round))
                .foregroundStyle(selectedMetric.color)
                .annotation(position: .top, alignment: .trailing) {
                    Text(formattedOverlayValue(segment.average))
                        .font(.caption2)
                        .fontWeight(.semibold)
                        .foregroundColor(selectedMetric.color)
                        .padding(.horizontal, 4)
                        .padding(.vertical, 2)
                        .background(Color(NSColor.controlBackgroundColor).opacity(0.9))
                        .cornerRadius(4)
                }
            }

            if let avg = averageValue {
                RuleMark(y: .value("Average", avg))
                    .lineStyle(StrokeStyle(lineWidth: 1, dash: [5, 3]))
                    .foregroundStyle(selectedMetric.color.opacity(0.5))
                    .annotation(position: .top, alignment: .trailing) {
                        Text("Avg: \(formatValue(avg))")
                            .font(.caption2)
                            .foregroundColor(selectedMetric.color.opacity(0.7))
                            .padding(.horizontal, 4)
                            .padding(.vertical, 2)
                            .background(Color(NSColor.controlBackgroundColor).opacity(0.8))
                            .cornerRadius(3)
                    }
            }
        }
        .chartLegend(.hidden)
        .chartXAxis {
            AxisMarks(values: .stride(by: strideComponent, count: strideCount)) { value in
                AxisGridLine()
                AxisTick()
                if let date = value.as(Date.self) {
                    AxisValueLabel {
                        Text(formatHourLabel(date))
                            .font(.caption2)
                            .lineLimit(1)
                            .minimumScaleFactor(0.5)
                    }
                }
            }
        }
        .chartYAxis {
            AxisMarks(position: .leading) { value in
                AxisGridLine()
                AxisTick()
                AxisValueLabel {
                    if let intValue = value.as(Int.self) {
                        Text("\(intValue)")
                            .font(.caption2)
                    } else if let doubleValue = value.as(Double.self) {
                        Text("\(doubleValue, specifier: "%.1f")")
                            .font(.caption2)
                    }
                }
            }
        }
        .frame(maxWidth: .infinity, minHeight: 300, idealHeight: 350)
        .padding(.vertical, 8)
        .chartOverlay { proxy in
            GeometryReader { geometry in
                let plotFrame = geometry[proxy.plotFrame!]

                Color.clear
                    .contentShape(Rectangle())
                    .onContinuousHover { phase in
                        switch phase {
                        case .active(let location):
                            let plotX = location.x - plotFrame.origin.x
                            hoveredBarTime = proxy.value(atX: plotX, as: Date.self)
                        case .ended:
                            hoveredBarTime = nil
                        }
                    }
                    .overlay {
                        if let point = hoveredPoint {
                            let barValue = value(for: point)
                            let barStartX = proxy.position(forX: point.time) ?? 0
                            let nextTime = Calendar.current.date(byAdding: timeUnit, value: 1, to: point.time) ?? point.time
                            let barEndX = proxy.position(forX: nextTime) ?? barStartX
                            let centerX = plotFrame.origin.x + (barStartX + barEndX) / 2.0
                            let topY = plotFrame.origin.y + (proxy.position(forY: barValue) ?? 0)
                            let clampedX = min(max(centerX, 60), geometry.size.width - 60)
                            let tooltipY = max(topY - 20, 12)

                            tooltipContent(for: point)
                                .position(x: clampedX, y: tooltipY)
                                .allowsHitTesting(false)
                        }
                    }
            }
        }
    }

    private func selectedDataPoint(for time: Date) -> TimeSeriesDataPoint? {
        dataPoints.first(where: { isSameBucket($0.time, time) })
    }

    @ViewBuilder
    private func tooltipContent(for point: TimeSeriesDataPoint) -> some View {
        HStack(spacing: 6) {
            Circle()
                .fill(selectedMetric.color)
                .frame(width: 8, height: 8)
            Text(formatValue(value(for: point)))
                .font(.caption2)
                .fontWeight(.semibold)
            Text(selectedMetric.unitLabel)
                .font(.caption2)
                .foregroundColor(.secondary)
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 6)
        .background(Color(NSColor.controlBackgroundColor))
        .cornerRadius(6)
        .shadow(color: .black.opacity(0.1), radius: 4, x: 0, y: 2)
    }

    private var timeUnit: Calendar.Component {
        switch timeFrame {
        case .today:
            return .hour
        case .lastWeek, .lastMonth:
            return .day
        }
    }

    private var strideComponent: Calendar.Component {
        switch timeFrame {
        case .today:
            return .hour
        case .lastWeek, .lastMonth:
            return .day
        }
    }

    private var strideCount: Int {
        switch timeFrame {
        case .today:
            return 1
        case .lastWeek:
            return 1
        case .lastMonth:
            return 5
        }
    }

    private func formatHourLabel(_ date: Date) -> String {
        switch timeFrame {
        case .today:
            let formatter = DateFormatter()
            formatter.dateFormat = "HH"
            return formatter.string(from: date)
        case .lastWeek, .lastMonth:
            let formatter = DateFormatter()
            formatter.dateFormat = "MMM d"
            return formatter.string(from: date)
        }
    }

    private func isoWeekStart(for date: Date) -> Date {
        var isoCalendar = Calendar(identifier: .iso8601)
        isoCalendar.timeZone = TimeZone.current
        let normalizedDate = Calendar.current.startOfDay(for: date)
        return isoCalendar.dateInterval(of: .weekOfYear, for: normalizedDate)?.start ?? normalizedDate
    }

    private func isSameBucket(_ lhs: Date, _ rhs: Date) -> Bool {
        return Calendar.current.isDate(lhs, equalTo: rhs, toGranularity: timeUnit)
    }
}

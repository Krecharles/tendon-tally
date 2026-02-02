import SwiftUI
import Charts

struct ChartDataPoint: Identifiable {
    let id = UUID()
    let time: Date
    let metricType: MetricType
    let value: Double
    let isPartial: Bool
}

struct BarChartView: View {
    let dataPoints: [TimeSeriesDataPoint]
    let filters: Set<MetricType>
    let timeFrame: TimeFrame
    
    @State private var hoveredBarTime: Date?
    
    // Colors for each metric type
    private func color(for metricType: MetricType) -> Color {
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
    
    private var activeMetrics: [MetricType] {
        MetricType.individualMetrics.filter { filters.contains($0) }
    }
    
    private var showAggregate: Bool {
        filters.contains(.aggregate)
    }
    
    private func value(for point: TimeSeriesDataPoint, metricType: MetricType) -> Double {
        switch metricType {
        case .keys:
            return Double(point.keyPressCount)
        case .clicks:
            return Double(point.mouseClickCount)
        case .scroll:
            return Double(point.scrollTicks) / 1000.0
        case .mouseDistance:
            return point.mouseDistance / 1000.0
        case .aggregate:
            return aggregateValue(for: point)
        }
    }
    
    private func aggregateValue(for point: TimeSeriesDataPoint) -> Double {
        // Always sum all metrics regardless of filter selection
        return Double(point.keyPressCount) + 
               Double(point.mouseClickCount) + 
               Double(point.scrollTicks) / 1000.0 + 
               point.mouseDistance / 1000.0
    }
    
    private var chartData: [ChartDataPoint] {
        var data: [ChartDataPoint] = []
        
        for point in dataPoints {
            // Add individual metric data points
            for metricType in activeMetrics {
                data.append(ChartDataPoint(
                    time: point.time,
                    metricType: metricType,
                    value: value(for: point, metricType: metricType),
                    isPartial: point.isPartial
                ))
            }
            
            // Add aggregate data point if enabled
            if showAggregate {
                data.append(ChartDataPoint(
                    time: point.time,
                    metricType: .aggregate,
                    value: aggregateValue(for: point),
                    isPartial: point.isPartial
                ))
            }
        }
        
        return data
    }
    
    private func formatValue(_ value: Double, for metricType: MetricType) -> String {
        switch metricType {
        case .keys, .clicks:
            return String(format: "%.0f", value)
        case .scroll, .mouseDistance, .aggregate:
            return String(format: "%.1f", value)
        }
    }
    
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            if dataPoints.isEmpty || (filters.isEmpty || (activeMetrics.isEmpty && !showAggregate)) {
                Text("No data to display")
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .frame(maxWidth: .infinity, alignment: .center)
                    .padding(.vertical, 40)
            } else {
                chartView
            }
        }
        .padding(.top, 12)
        .padding(.leading, 12)
        .padding(.trailing, 12)
        .padding(.bottom, 12)
        .background(Color.gray.opacity(0.05))
        .cornerRadius(8)
    }
    
    private var chartView: some View {
        Chart(chartData) { dataPoint in
            BarMark(
                x: .value("Time", dataPoint.time, unit: timeUnit),
                y: .value("Value", dataPoint.value)
            )
            .foregroundStyle(by: .value("Metric", dataPoint.metricType.rawValue))
            .position(by: .value("Metric", dataPoint.metricType.rawValue))
        }
        .chartForegroundStyleScale(domain: chartLegendItems, range: chartColors)
        .chartLegend(.hidden)
        .chartXSelection(value: $hoveredBarTime)
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
        .overlay(alignment: .top) {
            hoverTooltip
        }
    }
    
    @ViewBuilder
    private var hoverTooltip: some View {
        if let hoveredTime = hoveredBarTime,
           let selectedPoint = selectedDataPoint(for: hoveredTime),
           hasNonZeroDataForTime(hoveredTime) {
            // Show tooltip with all metrics for the selected time period
            tooltipContent(for: selectedPoint)
        }
    }
    
    private func selectedDataPoint(for time: Date) -> TimeSeriesDataPoint? {
        dataPoints.first(where: { Calendar.current.isDate($0.time, equalTo: time, toGranularity: timeUnit) })
    }
    
    private func hasNonZeroDataForTime(_ time: Date) -> Bool {
        // Check if there are any non-zero bars (chart data points) for this time period
        let barsForTime = chartData.filter { dataPoint in
            Calendar.current.isDate(dataPoint.time, equalTo: time, toGranularity: timeUnit)
        }
        // Return true if at least one bar has a non-zero value
        return barsForTime.contains { $0.value > 0 }
    }
    
    @ViewBuilder
    private func tooltipContent(for point: TimeSeriesDataPoint) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            ForEach(activeMetrics, id: \.self) { metricType in
                if filters.contains(metricType) {
                    tooltipRow(metricType: metricType, point: point)
                }
            }
            if showAggregate {
                tooltipAggregateRow(point: point)
            }
        }
        .padding(8)
        .background(Color(NSColor.controlBackgroundColor))
        .cornerRadius(6)
        .shadow(color: .black.opacity(0.1), radius: 4, x: 0, y: 2)
        .padding(.top, 8)
    }
    
    private func tooltipRow(metricType: MetricType, point: TimeSeriesDataPoint) -> some View {
        HStack(spacing: 6) {
            Circle()
                .fill(color(for: metricType))
                .frame(width: 8, height: 8)
            Text(metricType.rawValue)
                .font(.caption2)
            Spacer()
            Text(formatValue(value(for: point, metricType: metricType), for: metricType))
                .font(.caption2)
                .fontWeight(.semibold)
        }
    }
    
    private func tooltipAggregateRow(point: TimeSeriesDataPoint) -> some View {
        HStack(spacing: 6) {
            Circle()
                .fill(color(for: .aggregate))
                .frame(width: 8, height: 8)
            Text("Total")
                .font(.caption2)
            Spacer()
            Text(formatValue(aggregateValue(for: point), for: .aggregate))
                .font(.caption2)
                .fontWeight(.semibold)
        }
    }
    
    private var chartLegendItems: [String] {
        var items: [String] = []
        for metric in activeMetrics {
            items.append(metric.rawValue)
        }
        if showAggregate {
            items.append("Total")
        }
        return items
    }
    
    private var chartColors: [Color] {
        var colors: [Color] = []
        for metric in activeMetrics {
            colors.append(color(for: metric))
        }
        if showAggregate {
            colors.append(color(for: .aggregate))
        }
        return colors
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
            return 1 // Data is grouped in 1-hour intervals
        case .lastWeek:
            return 1
        case .lastMonth:
            return 2 // Data is grouped in 2-day intervals
        }
    }
    
    private var dateFormat: Date.FormatStyle {
        switch timeFrame {
        case .today:
            return .dateTime.hour().minute()
        case .lastWeek, .lastMonth:
            return .dateTime.month().day()
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
}

struct LegendView: View {
    let activeMetrics: [MetricType]
    let showAggregate: Bool
    let color: (MetricType) -> Color
    
    var body: some View {
        HStack(spacing: 12) {
            ForEach(activeMetrics, id: \.self) { metricType in
                HStack(spacing: 4) {
                    Circle()
                        .fill(color(metricType))
                        .frame(width: 8, height: 8)
                    Text(metricType.rawValue)
                        .font(.caption2)
                }
            }
            if showAggregate {
                HStack(spacing: 4) {
                    Circle()
                        .fill(color(.aggregate))
                        .frame(width: 8, height: 8)
                    Text("Total")
                        .font(.caption2)
                }
            }
        }
        .padding(.top, 8)
    }
}

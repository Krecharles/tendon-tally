import SwiftUI
import Charts

struct ChartDataPoint: Identifiable {
    let id = UUID()
    let time: Date
    let metricType: MetricType
    let value: Double
}

struct BarChartView: View {
    let dataPoints: [TimeSeriesDataPoint]
    let filters: Set<MetricType>
    let timeFrame: TimeFrame
    
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
                    value: value(for: point, metricType: metricType)
                ))
            }
            
            // Add aggregate data point if enabled
            if showAggregate {
                data.append(ChartDataPoint(
                    time: point.time,
                    metricType: .aggregate,
                    value: aggregateValue(for: point)
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
            Text("Usage Over Time")
                .font(.subheadline)
                .foregroundColor(.secondary)
            
            if dataPoints.isEmpty || (filters.isEmpty || (activeMetrics.isEmpty && !showAggregate)) {
                Text("No data to display")
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .frame(maxWidth: .infinity, alignment: .center)
                    .padding(.vertical, 40)
            } else {
                Chart(chartData) { dataPoint in
                    BarMark(
                        x: .value("Time", dataPoint.time, unit: timeUnit),
                        y: .value("Value", dataPoint.value)
                    )
                    .foregroundStyle(by: .value("Metric", dataPoint.metricType.rawValue))
                    .position(by: .value("Metric", dataPoint.metricType.rawValue))
                }
                .chartForegroundStyleScale(domain: chartLegendItems, range: chartColors)
                .chartXAxis {
                    AxisMarks(values: .stride(by: strideComponent, count: strideCount)) { value in
                        AxisGridLine()
                        AxisTick()
                        if let date = value.as(Date.self) {
                            AxisValueLabel {
                                Text(date, format: dateFormat)
                                    .font(.caption2)
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
                .chartLegend {
                    LegendView(activeMetrics: activeMetrics, showAggregate: showAggregate, color: color)
                }
                .frame(maxWidth: .infinity, minHeight: 300, idealHeight: 350)
                .padding(.vertical, 8)
            }
        }
        .padding(12)
        .background(Color.gray.opacity(0.05))
        .cornerRadius(8)
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
        case .last24Hours:
            return .hour
        case .lastWeek, .lastMonth:
            return .day
        }
    }
    
    private var strideComponent: Calendar.Component {
        switch timeFrame {
        case .last24Hours:
            return .hour
        case .lastWeek, .lastMonth:
            return .day
        }
    }
    
    private var strideCount: Int {
        switch timeFrame {
        case .last24Hours:
            return 2 // Data is grouped in 2-hour intervals
        case .lastWeek:
            return 1
        case .lastMonth:
            return 2 // Data is grouped in 2-day intervals
        }
    }
    
    private var dateFormat: Date.FormatStyle {
        switch timeFrame {
        case .last24Hours:
            return .dateTime.hour().minute()
        case .lastWeek, .lastMonth:
            return .dateTime.month().day()
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

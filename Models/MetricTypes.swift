import Foundation

/// Time frame options for viewing metrics.
enum TimeFrame: String, CaseIterable {
    case today = "Today"
    case lastWeek = "Week"
    case lastMonth = "Month"
    
    func dateRange(offset: Int = 0) -> (start: Date, end: Date) {
        let now = Date()
        let calendar = Calendar.current
        
        switch self {
        case .today:
            // For offset 0: start of today to now
            // For offset -1: start of yesterday to end of yesterday
            // For offset -2: start of day before yesterday to end of that day
            let targetDate = calendar.date(byAdding: .day, value: offset, to: now) ?? now
            let startOfDay = calendar.startOfDay(for: targetDate)
            
            if offset == 0 {
                // Current day: start of today to now
                return (start: startOfDay, end: now)
            } else {
                // Past days: full day (start to end of that day)
                let endOfDay = calendar.date(byAdding: .day, value: 1, to: startOfDay) ?? startOfDay
                return (start: startOfDay, end: endOfDay)
            }
        case .lastWeek:
            // For offset 0: last 7 days ending now
            // For offset -1: previous 7 days (7-14 days ago)
            // For offset -2: 7 days before that (14-21 days ago)
            let daysOffset = offset * 7
            let endDate: Date
            if offset == 0 {
                endDate = now
            } else {
                // For past weeks, end at the end of that 7-day period
                endDate = calendar.date(byAdding: .day, value: daysOffset, to: now) ?? now
            }
            let startDate = calendar.date(byAdding: .day, value: -7, to: endDate) ?? endDate
            return (start: startDate, end: endDate)
        case .lastMonth:
            // For offset 0: last month ending now
            // For offset -1: previous month
            // For offset -2: month before that
            let monthsOffset = offset
            let endDate: Date
            if offset == 0 {
                endDate = now
            } else {
                // For past months, end at the end of that month
                let monthStart = calendar.date(byAdding: .month, value: monthsOffset, to: now) ?? now
                let monthStartDay = calendar.startOfDay(for: monthStart)
                let monthComponents = calendar.dateComponents([.year, .month], from: monthStartDay)
                if let firstDayOfMonth = calendar.date(from: monthComponents),
                   let lastDayOfMonth = calendar.date(byAdding: DateComponents(month: 1, day: -1), to: firstDayOfMonth) {
                    endDate = calendar.date(bySettingHour: 23, minute: 59, second: 59, of: lastDayOfMonth) ?? lastDayOfMonth
                } else {
                    endDate = monthStart
                }
            }
            if let startDate = calendar.date(byAdding: .month, value: -1, to: endDate) {
                return (start: startDate, end: endDate)
            }
            return (start: endDate.addingTimeInterval(-30 * 24 * 60 * 60), end: endDate)
        }
    }
}

/// Types of metrics that can be tracked and displayed.
enum MetricType: String, CaseIterable, Hashable {
    case keys = "Keys Pressed"
    case clicks = "Mouse Clicks"
    case scroll = "Scroll Distance"
    case mouseDistance = "Mouse Distance"
    case aggregate = "Total"
    
    static var individualMetrics: [MetricType] {
        [.keys, .clicks, .scroll, .mouseDistance]
    }
}

/// Aggregated metrics for a time period.
struct AggregatedMetrics {
    let keyPressCount: Int
    let mouseClickCount: Int
    let scrollTicks: Int
    let mouseDistance: Double
}

/// A single data point in a time series chart.
struct TimeSeriesDataPoint: Identifiable {
    let id = UUID()
    let time: Date
    let keyPressCount: Int
    let mouseClickCount: Int
    let scrollTicks: Int
    let mouseDistance: Double
    let isPartial: Bool // True if this time period is incomplete (e.g., current hour/day)
    
    init(time: Date, keyPressCount: Int, mouseClickCount: Int, scrollTicks: Int, mouseDistance: Double, isPartial: Bool = false) {
        self.time = time
        self.keyPressCount = keyPressCount
        self.mouseClickCount = mouseClickCount
        self.scrollTicks = scrollTicks
        self.mouseDistance = mouseDistance
        self.isPartial = isPartial
    }
}

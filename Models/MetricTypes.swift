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
            // Rolling 30-day windows.
            // offset 0: [now-30d, now]
            // offset -1: previous 30-day window
            let windowDays = 30
            let windowSeconds = TimeInterval(windowDays * 24 * 60 * 60)
            let shiftedEnd = now.addingTimeInterval(TimeInterval(offset * windowDays) * 24 * 60 * 60)
            return (start: shiftedEnd.addingTimeInterval(-windowSeconds), end: shiftedEnd)
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

    var unitLabel: String {
        switch self {
        case .keys: return "keys"
        case .clicks: return "clicks"
        case .scroll: return "scroll movement"
        case .mouseDistance: return "mouse movement"
        case .aggregate: return "total"
        }
    }
}

/// Aggregated metrics for a time period.
struct AggregatedMetrics {
    let keyPressCount: Int
    let mouseClickCount: Int
    let scrollTicks: Int
    let mouseDistance: Double
}

/// Configuration for the Total metric.
///
/// By default, Total is the simple sum of the existing factors:
/// - Keys pressed
/// - Mouse clicks
/// - Scroll ticks (scaled to 100s)
/// - Mouse distance (scaled to 1000s of pixels)
///
/// In advanced mode, users can apply custom weights to emphasize specific factors.
struct TotalConfig: Codable, Equatable {
    var keysWeight: Double
    var clicksWeight: Double
    var scrollTicksWeight: Double
    var mouseDistanceWeight: Double
    
    /// Recommended default configuration: treat all inputs as equally important.
    static let `default` = TotalConfig(
        keysWeight: 1.0,
        clicksWeight: 1.0,
        scrollTicksWeight: 1.0,
        mouseDistanceWeight: 1.0
    )
    
    /// Apply this configuration to aggregated metrics to compute the Total value.
    ///
    /// Scaling matches the units shown in the dashboard tiles:
    /// - Scroll ticks are counted in 100s
    /// - Mouse distance is counted in 1000s of pixels
    func apply(to metrics: AggregatedMetrics) -> Double {
        let keysTerm = keysWeight * Double(metrics.keyPressCount)
        let clicksTerm = clicksWeight * Double(metrics.mouseClickCount)
        let scrollTerm = scrollTicksWeight * (Double(metrics.scrollTicks) / 100.0)
        let mouseTerm = mouseDistanceWeight * (metrics.mouseDistance / 1000.0)
        
        return keysTerm + clicksTerm + scrollTerm + mouseTerm
    }
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

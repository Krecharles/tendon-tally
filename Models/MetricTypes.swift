import Foundation

enum HistoryPreset: String, CaseIterable, Codable, Hashable {
    case day = "Day"
    case week = "Week"
    case month = "Month"
    case year = "Year"

    var rollingDays: Int {
        switch self {
        case .day:
            return 1
        case .week:
            return 7
        case .month:
            return 30
        case .year:
            return 365
        }
    }
}

enum HistoryRangeMode: String, Codable, Hashable {
    case preset
    case custom
}

enum AggregationGranularity: String, CaseIterable, Codable, Hashable {
    case hour = "Hour"
    case day = "Day"
    case week = "Week"
    case month = "Month"

    var calendarComponent: Calendar.Component {
        switch self {
        case .hour:
            return .hour
        case .day:
            return .day
        case .week:
            return .weekOfYear
        case .month:
            return .month
        }
    }

    var nextCoarser: AggregationGranularity? {
        switch self {
        case .hour:
            return .day
        case .day:
            return .week
        case .week:
            return .month
        case .month:
            return nil
        }
    }

    func alignedStart(for date: Date, calendar: Calendar = .current) -> Date {
        switch self {
        case .hour:
            let components = calendar.dateComponents([.year, .month, .day, .hour], from: date)
            return calendar.date(from: components) ?? date
        case .day:
            return calendar.startOfDay(for: date)
        case .week:
            var isoCalendar = Calendar(identifier: .iso8601)
            isoCalendar.timeZone = calendar.timeZone
            let normalized = calendar.startOfDay(for: date)
            return isoCalendar.dateInterval(of: .weekOfYear, for: normalized)?.start ?? normalized
        case .month:
            let components = calendar.dateComponents([.year, .month], from: date)
            return calendar.date(from: components) ?? date
        }
    }

    func addingOneStep(to date: Date, calendar: Calendar = .current) -> Date {
        calendar.date(byAdding: calendarComponent, value: 1, to: date) ?? date
    }
}

struct HistorySelection: Codable, Hashable {
    var mode: HistoryRangeMode
    var preset: HistoryPreset
    var customStartDate: Date
    var customEndDate: Date
    var offset: Int
    var manualAggregation: AggregationGranularity?

    static func `default`(now: Date = Date(), calendar: Calendar = .current) -> HistorySelection {
        let todayStart = calendar.startOfDay(for: now)
        return HistorySelection(
            mode: .preset,
            preset: .day,
            customStartDate: todayStart,
            customEndDate: todayStart,
            offset: 0,
            manualAggregation: nil
        )
    }

    var isCustom: Bool { mode == .custom }

    func normalized(now: Date = Date(), calendar: Calendar = .current) -> HistorySelection {
        var copy = self
        let safeNow: Date
        if now.timeIntervalSinceReferenceDate.isFinite {
            safeNow = now
        } else {
            safeNow = Date()
        }
        let today = calendar.startOfDay(for: safeNow)

        var normalizedStart = calendar.startOfDay(for: customStartDate)
        var normalizedEnd = calendar.startOfDay(for: customEndDate)

        if normalizedEnd > today {
            normalizedEnd = today
        }
        if normalizedStart > normalizedEnd {
            normalizedStart = normalizedEnd
        }

        let inclusiveSpan = (calendar.dateComponents([.day], from: normalizedStart, to: normalizedEnd).day ?? 0) + 1
        if inclusiveSpan > 365 {
            normalizedStart = calendar.date(byAdding: .day, value: -364, to: normalizedEnd) ?? normalizedStart
        }

        copy.customStartDate = normalizedStart
        copy.customEndDate = normalizedEnd

        if copy.mode == .preset {
            copy.offset = min(0, copy.offset)
        }

        let allowed = HistoryAggregationPolicy.allowedGranularitiesAssumingNormalized(copy)
        if let manual = copy.manualAggregation, !allowed.contains(manual) {
            copy.manualAggregation = nil
        }

        return copy
    }

    var customSpanDays: Int {
        let calendar = Calendar.current
        let start = calendar.startOfDay(for: customStartDate)
        let end = calendar.startOfDay(for: customEndDate)
        let span = (calendar.dateComponents(
            [.day],
            from: min(start, end),
            to: max(start, end)
        ).day ?? 0) + 1
        return max(1, span)
    }

    var navigationStepDays: Int {
        switch mode {
        case .preset:
            return preset.rollingDays
        case .custom:
            return customSpanDays
        }
    }

    func dateInterval(now: Date = Date(), calendar: Calendar = .current) -> DateInterval {
        let normalized = normalized(now: now, calendar: calendar)
        switch normalized.mode {
        case .preset:
            if normalized.preset == .day {
                let startOfToday = calendar.startOfDay(for: now)
                if normalized.offset == 0 {
                    return DateInterval(start: startOfToday, end: now)
                }

                let dayStart = calendar.date(byAdding: .day, value: normalized.offset, to: startOfToday) ?? startOfToday
                let dayEnd = calendar.date(byAdding: .day, value: 1, to: dayStart) ?? dayStart
                return DateInterval(start: dayStart, end: dayEnd)
            }

            let spanDays = normalized.preset.rollingDays
            let shiftDays = normalized.offset * spanDays
            let shiftedEnd = calendar.date(byAdding: .day, value: shiftDays, to: now) ?? now
            let shiftedStart = calendar.date(byAdding: .day, value: -spanDays, to: shiftedEnd) ?? shiftedEnd
            return DateInterval(start: shiftedStart, end: shiftedEnd)
        case .custom:
            let baseStart = calendar.startOfDay(for: normalized.customStartDate)
            let baseEndExclusive = calendar.date(byAdding: .day, value: 1, to: calendar.startOfDay(for: normalized.customEndDate)) ?? baseStart
            let spanDays = normalized.customSpanDays
            let shiftDays = normalized.offset * spanDays
            let shiftedStart = calendar.date(byAdding: .day, value: shiftDays, to: baseStart) ?? baseStart
            let shiftedEnd = calendar.date(byAdding: .day, value: shiftDays, to: baseEndExclusive) ?? baseEndExclusive
            return DateInterval(start: shiftedStart, end: shiftedEnd)
        }
    }

    func canNavigateForward(now: Date = Date(), calendar: Calendar = .current) -> Bool {
        offset < 0
    }
}

enum HistoryAggregationPolicy {
    static let maxBarsBeforeEscalation = 100

    static func autoGranularity(
        for selection: HistorySelection,
        now: Date = Date(),
        calendar: Calendar = .current
    ) -> AggregationGranularity {
        let normalized = selection.normalized(now: now, calendar: calendar)
        return autoGranularityAssumingNormalized(normalized)
    }

    static func autoGranularityAssumingNormalized(
        _ normalized: HistorySelection
    ) -> AggregationGranularity {
        if normalized.mode == .preset, normalized.preset == .year {
            // Year view is explicitly weekly by default.
            return .week
        }

        let spanDays = normalized.mode == .preset ? normalized.preset.rollingDays : normalized.customSpanDays
        // Start from the finest meaningful granularity for history and escalate only when
        // that level would exceed the configured max bar count.
        let hourlyBars = spanDays * 24
        if hourlyBars <= maxBarsBeforeEscalation {
            return .hour
        }
        if spanDays <= maxBarsBeforeEscalation {
            return .day
        }

        let spanWeeks = Int(ceil(Double(spanDays) / 7.0))
        if spanWeeks <= maxBarsBeforeEscalation {
            return .week
        }
        return .month
    }

    static func allowedGranularities(
        for selection: HistorySelection,
        now: Date = Date(),
        calendar: Calendar = .current
    ) -> [AggregationGranularity] {
        let normalized = selection.normalized(now: now, calendar: calendar)
        return allowedGranularitiesAssumingNormalized(normalized)
    }

    static func allowedGranularitiesAssumingNormalized(
        _ normalized: HistorySelection
    ) -> [AggregationGranularity] {
        [autoGranularityAssumingNormalized(normalized)]
    }

    static func resolvedGranularity(
        for selection: HistorySelection,
        now: Date = Date(),
        calendar: Calendar = .current
    ) -> AggregationGranularity {
        let normalized = selection.normalized(now: now, calendar: calendar)
        let allowed = allowedGranularitiesAssumingNormalized(normalized)
        if let manual = normalized.manualAggregation, allowed.contains(manual) {
            return manual
        }
        return autoGranularityAssumingNormalized(normalized)
    }
}

/// Time frame options for viewing metrics.
/// Legacy enum kept for migration compatibility.
enum TimeFrame: String, CaseIterable {
    case today = "Today"
    case lastWeek = "Week"
    case lastMonth = "Month"
    case lastYear = "Year"
    
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
        case .lastYear:
            // Rolling 365-day windows.
            // offset 0: [now-365d, now]
            // offset -1: previous 365-day window
            let windowDays = 365
            let windowSeconds = TimeInterval(windowDays * 24 * 60 * 60)
            let shiftedEnd = now.addingTimeInterval(TimeInterval(offset * windowDays) * 24 * 60 * 60)
            return (start: shiftedEnd.addingTimeInterval(-windowSeconds), end: shiftedEnd)
        }
    }
}

/// Aggregation options for month history charts.
/// Legacy enum kept for migration compatibility.
enum MonthAggregation: String, CaseIterable, Hashable {
    case day = "Day"
    case week = "Week"
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

/// Day options for quick exports.
enum DailyExportDay: String, CaseIterable, Hashable {
    case today = "Today"
    case yesterday = "Yesterday"

    var offset: Int {
        switch self {
        case .today: return 0
        case .yesterday: return -1
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
    let time: Date
    let keyPressCount: Int
    let mouseClickCount: Int
    let scrollTicks: Int
    let mouseDistance: Double
    let isPartial: Bool // True if this time period is incomplete (e.g., current hour/day)

    var id: Date { time }
    
    init(time: Date, keyPressCount: Int, mouseClickCount: Int, scrollTicks: Int, mouseDistance: Double, isPartial: Bool = false) {
        self.time = time
        self.keyPressCount = keyPressCount
        self.mouseClickCount = mouseClickCount
        self.scrollTicks = scrollTicks
        self.mouseDistance = mouseDistance
        self.isPartial = isPartial
    }
}

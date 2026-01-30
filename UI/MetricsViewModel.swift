import Foundation
import Combine

enum TimeFrame: String, CaseIterable {
    case last24Hours = "24 Hours"
    case lastWeek = "Week"
    case lastMonth = "Month"
    
    var dateRange: (start: Date, end: Date) {
        let now = Date()
        let calendar = Calendar.current
        
        switch self {
        case .last24Hours:
            return (start: now.addingTimeInterval(-24 * 60 * 60), end: now)
        case .lastWeek:
            return (start: now.addingTimeInterval(-7 * 24 * 60 * 60), end: now)
        case .lastMonth:
            if let monthAgo = calendar.date(byAdding: .month, value: -1, to: now) {
                return (start: monthAgo, end: now)
            }
            return (start: now.addingTimeInterval(-30 * 24 * 60 * 60), end: now)
        }
    }
}

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

struct AggregatedMetrics {
    let keyPressCount: Int
    let mouseClickCount: Int
    let scrollTicks: Int
    let mouseDistance: Double
}

struct TimeSeriesDataPoint: Identifiable {
    let id = UUID()
    let time: Date
    let keyPressCount: Int
    let mouseClickCount: Int
    let scrollTicks: Int
    let mouseDistance: Double
}

@MainActor
final class MetricsViewModel: ObservableObject {
    @Published var currentSample: UsageSample
    @Published var recentHistory: [UsageSample] = []
    @Published var todayTotals: UsageSample
    @Published var permissionIssueMessage: String?
    @Published var selectedTimeFrame: TimeFrame = .last24Hours
    @Published var activeMetricFilters: Set<MetricType> = Set(MetricType.individualMetrics + [.aggregate])

    private let aggregator: MetricsAggregator

    init(aggregator: MetricsAggregator) {
        self.aggregator = aggregator
        self.currentSample = aggregator.currentSample
        self.todayTotals = MetricsViewModel.computeTodayTotals(current: aggregator.currentSample,
                                                               history: aggregator.history)

        aggregator.onUpdate = { [weak self] current, history in
            Task { @MainActor in
                guard let self else { return }
                self.currentSample = current
                self.recentHistory = Array(history.prefix(12)) // up to 1 hour of 5‑min windows
                self.todayTotals = MetricsViewModel.computeTodayTotals(current: current, history: history)
            }
        }

        aggregator.onPermissionOrTapFailure = { [weak self] message in
            Task { @MainActor in
                self?.permissionIssueMessage = message
            }
        }
    }

    private static func computeTodayTotals(current: UsageSample, history: [UsageSample]) -> UsageSample {
        let calendar = Calendar.current
        let now = Date()
        let startOfDay = calendar.startOfDay(for: now)

        var totalKeys = 0
        var totalClicks = 0
        var totalScrollTicks = 0
        var totalMouseDistance = 0.0

        // Include finalized windows from today.
        for sample in history where sample.start >= startOfDay {
            totalKeys += sample.keyPressCount
            totalClicks += sample.mouseClickCount
            totalScrollTicks += sample.scrollTicks
            totalMouseDistance += sample.mouseDistance
        }

        // Include the current in‑progress window if it's from today.
        if current.start >= startOfDay {
            totalKeys += current.keyPressCount
            totalClicks += current.mouseClickCount
            totalScrollTicks += current.scrollTicks
            totalMouseDistance += current.mouseDistance
        }

        return UsageSample(
            id: UUID(),
            start: startOfDay,
            end: now,
            keyPressCount: totalKeys,
            mouseClickCount: totalClicks,
            scrollTicks: totalScrollTicks,
            scrollDistance: 0, // not used anymore
            mouseDistance: totalMouseDistance
        )
    }
    
    func aggregatedMetrics(for timeFrame: TimeFrame, filters: Set<MetricType>) -> AggregatedMetrics {
        let (startDate, endDate) = timeFrame.dateRange
        let allSamples = aggregator.history + [aggregator.currentSample]
        
        // Always calculate all metrics regardless of filters (for totals display)
        var totalKeys = 0
        var totalClicks = 0
        var totalScrollTicks = 0
        var totalMouseDistance = 0.0
        
        for sample in allSamples {
            // Check if sample overlaps with the time frame
            if sample.end >= startDate && sample.start <= endDate {
                // Always sum all metrics for totals
                totalKeys += sample.keyPressCount
                totalClicks += sample.mouseClickCount
                totalScrollTicks += sample.scrollTicks
                totalMouseDistance += sample.mouseDistance
            }
        }
        
        return AggregatedMetrics(
            keyPressCount: totalKeys,
            mouseClickCount: totalClicks,
            scrollTicks: totalScrollTicks,
            mouseDistance: totalMouseDistance
        )
    }
    
    func reloadHistory() {
        aggregator.reloadHistory()
    }
    
    func timeSeriesData(for timeFrame: TimeFrame, filters: Set<MetricType>) -> [TimeSeriesDataPoint] {
        let (startDate, endDate) = timeFrame.dateRange
        let allSamples = aggregator.history + [aggregator.currentSample]
        
        let calendar = Calendar.current
        
        // Determine grouping interval based on time frame
        // Target ~12 bars for better readability
        let (component, value): (Calendar.Component, Int)
        switch timeFrame {
        case .last24Hours:
            // 24 hours / 12 bars = 2-hour intervals
            component = .hour
            value = 2
        case .lastWeek:
            // 7 days = daily intervals
            component = .day
            value = 1
        case .lastMonth:
            // ~30 days, target ~15 bars = 2-day intervals
            component = .day
            value = 2
        }
        
        // Create time buckets - include current time to ensure current window is included
        let now = Date()
        let effectiveEndDate = max(endDate, now)
        var buckets: [Date: (keys: Int, clicks: Int, scroll: Int, mouse: Double)] = [:]
        
        // Calculate the bucket key for the current time to ensure it's included
        let currentBucketKey: Date
        if component == .hour {
            let hour = calendar.component(.hour, from: now)
            let roundedHour = (hour / value) * value
            currentBucketKey = calendar.date(bySettingHour: roundedHour, minute: 0, second: 0, of: now) ?? now
        } else {
            let daysSinceStart = calendar.dateComponents([.day], from: startDate, to: now).day ?? 0
            let roundedDays = (daysSinceStart / value) * value
            let roundedDate = calendar.date(byAdding: .day, value: roundedDays, to: startDate) ?? now
            currentBucketKey = calendar.startOfDay(for: roundedDate)
        }
        
        // Ensure current bucket exists
        buckets[currentBucketKey] = (0, 0, 0, 0.0)
        
        // Create buckets from start to current time (ensure we include current bucket)
        var current = startDate
        while current <= now {
            let bucketKey: Date
            if component == .hour {
                // Round down to the hour (or multiple hours)
                let hour = calendar.component(.hour, from: current)
                let roundedHour = (hour / value) * value
                bucketKey = calendar.date(bySettingHour: roundedHour, minute: 0, second: 0, of: current) ?? current
            } else {
                // For days: calculate days since start and round
                let daysSinceStart = calendar.dateComponents([.day], from: startDate, to: current).day ?? 0
                let roundedDays = (daysSinceStart / value) * value
                let roundedDate = calendar.date(byAdding: .day, value: roundedDays, to: startDate) ?? current
                // Round to start of that day
                bucketKey = calendar.startOfDay(for: roundedDate)
            }
            
            if buckets[bucketKey] == nil {
                buckets[bucketKey] = (0, 0, 0, 0.0)
            }
            
            // Move to next interval
            if let next = calendar.date(byAdding: component, value: value, to: current) {
                current = next
            } else {
                break
            }
        }
        
        // Ensure we have the bucket for the current time period (in case loop didn't reach it)
        if buckets[currentBucketKey] == nil {
            buckets[currentBucketKey] = (0, 0, 0, 0.0)
        }
        
        // Aggregate samples into buckets
        for sample in allSamples {
            // Check if sample overlaps with the time frame (include current sample even if it extends beyond endDate)
            let sampleEnd = sample.end
            let effectiveEnd = max(endDate, now)
            if sampleEnd >= startDate && sample.start <= effectiveEnd {
                // For current sample (end time in future), use current time to determine bucket
                // For finalized samples, use sample start
                let isCurrentSample = sampleEnd > now
                let timeForBucket = isCurrentSample ? now : sample.start
                
                let bucketKey: Date
                if component == .hour {
                    let hour = calendar.component(.hour, from: timeForBucket)
                    let roundedHour = (hour / value) * value
                    bucketKey = calendar.date(bySettingHour: roundedHour, minute: 0, second: 0, of: timeForBucket) ?? timeForBucket
                } else {
                    // For days: calculate days since start and round
                    let daysSinceStart = calendar.dateComponents([.day], from: startDate, to: timeForBucket).day ?? 0
                    let roundedDays = (daysSinceStart / value) * value
                    let roundedDate = calendar.date(byAdding: .day, value: roundedDays, to: startDate) ?? timeForBucket
                    bucketKey = calendar.startOfDay(for: roundedDate)
                }
                
                if var bucket = buckets[bucketKey] {
                    // Always aggregate all metrics regardless of filters (for totals and aggregate bar)
                    bucket.keys += sample.keyPressCount
                    bucket.clicks += sample.mouseClickCount
                    bucket.scroll += sample.scrollTicks
                    bucket.mouse += sample.mouseDistance
                    buckets[bucketKey] = bucket
                }
            }
        }
        
        // Convert buckets to data points, sorted by time
        return buckets.sorted { $0.key < $1.key }.map { time, values in
            TimeSeriesDataPoint(
                time: time,
                keyPressCount: values.keys,
                mouseClickCount: values.clicks,
                scrollTicks: values.scroll,
                mouseDistance: values.mouse
            )
        }
    }
}


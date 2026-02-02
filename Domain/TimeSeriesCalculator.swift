import Foundation

/// Helper for calculating time series data points from usage samples.
struct TimeSeriesCalculator {
    /// Calculate time series data points for a given time frame and offset.
    /// - Parameters:
    ///   - samples: All usage samples to aggregate
    ///   - currentSample: The current in-progress sample (only included if offset is 0)
    ///   - timeFrame: The time frame to aggregate
    ///   - offset: Time frame offset (0 = current, -1 = previous, etc.)
    ///   - now: Current date/time
    /// - Returns: Array of time series data points sorted by time
    static func calculateTimeSeries(
        samples: [UsageSample],
        currentSample: UsageSample?,
        timeFrame: TimeFrame,
        offset: Int,
        now: Date = Date()
    ) -> [TimeSeriesDataPoint] {
        let (startDate, endDate) = timeFrame.dateRange(offset: offset)
        
        // For past periods, exclude current sample if it's not in that period
        // For current period, include current sample
        let allSamples: [UsageSample]
        if offset == 0, let current = currentSample {
            allSamples = samples + [current]
        } else {
            // For past periods, only include finalized samples
            allSamples = samples
        }
        
        let calendar = Calendar.current
        
        // Determine grouping interval based on time frame
        // Target ~12 bars for better readability
        let (component, value): (Calendar.Component, Int)
        switch timeFrame {
        case .today:
            // Today / 12 bars = 2-hour intervals
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
        
        // Create time buckets - for current period (offset 0), include current time
        // For past periods, use the end date of that period
        let effectiveEndDate = offset == 0 ? max(endDate, now) : endDate
        var buckets: [Date: (keys: Int, clicks: Int, scroll: Int, mouse: Double)] = [:]
        
        // Only calculate current bucket key for offset 0 (current period)
        let currentBucketKey: Date?
        if offset == 0 {
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
        } else {
            currentBucketKey = nil
        }
        
        // Ensure current bucket exists only for current period
        if let currentBucketKey = currentBucketKey {
            buckets[currentBucketKey] = (0, 0, 0, 0.0)
        }
        
        // Create buckets from start to end date
        let bucketEndDate = offset == 0 ? max(endDate, now) : endDate
        var current = startDate
        while current <= bucketEndDate {
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
        
        // Ensure we have the bucket for the current time period (only for offset 0)
        if let currentBucketKey = currentBucketKey, buckets[currentBucketKey] == nil {
            buckets[currentBucketKey] = (0, 0, 0, 0.0)
        }
        
        // Aggregate samples into buckets
        for sample in allSamples {
            // For past periods (offset < 0), strictly enforce the endDate boundary
            // For current period (offset 0), include current sample even if it extends beyond endDate
            let sampleEnd = sample.end
            let effectiveEnd = offset == 0 ? max(endDate, now) : endDate
            
            // Check if sample overlaps with the time frame
            // For past periods, sample must be entirely within the period
            // For current period, allow samples that extend into the future (current sample)
            let sampleOverlaps: Bool
            if offset == 0 {
                // Current period: include if sample overlaps with period
                sampleOverlaps = sampleEnd >= startDate && sample.start <= effectiveEnd
            } else {
                // Past period: sample must be within the period boundaries
                sampleOverlaps = sample.start >= startDate && sample.end <= effectiveEnd
            }
            
            if sampleOverlaps {
                // For current sample (end time in future) in current period, use current time to determine bucket
                // For finalized samples or past periods, use sample start
                let isCurrentSample = offset == 0 && sampleEnd > now
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
        // Filter to only include buckets within the period range
        return buckets
            .filter { bucketEntry in
                bucketEntry.key >= startDate && bucketEntry.key <= effectiveEndDate
            }
            .sorted { $0.key < $1.key }
            .map { time, values in
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

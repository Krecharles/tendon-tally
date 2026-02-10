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
        // Always use 1-hour intervals for today view, daily for weeks, 2-day for months
        let (component, value): (Calendar.Component, Int)
        switch timeFrame {
        case .today:
            // Always use 1-hour intervals (24 bars for full day, fewer for incomplete day)
            component = .hour
            value = 1
        case .lastWeek:
            // 7 days = daily intervals
            component = .day
            value = 1
        case .lastMonth:
            // ~30 days = daily intervals (one bar per day)
            component = .day
            value = 1
        }
        
        // Create time buckets - for current period (offset 0), include current time
        // For past periods, use the end date of that period
        let effectiveEndDate = offset == 0 ? max(endDate, now) : endDate
        
        // Round start date down to the interval boundary
        let roundedStartDate: Date
        if component == .hour {
            let hour = calendar.component(.hour, from: startDate)
            let roundedHour = (hour / value) * value
            roundedStartDate = calendar.date(bySettingHour: roundedHour, minute: 0, second: 0, of: startDate) ?? startDate
        } else {
            roundedStartDate = calendar.startOfDay(for: startDate)
        }
        
        // Generate ALL buckets in the range to ensure no gaps
        var buckets: [Date: (keys: Int, clicks: Int, scroll: Int, mouse: Double, isPartial: Bool)] = [:]
        var currentBucket = roundedStartDate
        
        // Determine the current/incomplete bucket for offset 0
        let currentBucketKey: Date?
        if offset == 0 {
            if component == .hour {
                let hour = calendar.component(.hour, from: now)
                let roundedHour = (hour / value) * value
                currentBucketKey = calendar.date(bySettingHour: roundedHour, minute: 0, second: 0, of: now) ?? now
            } else {
                // For days: calculate days since rounded start and round
                let daysSinceStart = calendar.dateComponents([.day], from: roundedStartDate, to: now).day ?? 0
                let roundedDays = (daysSinceStart / value) * value
                let roundedDate = calendar.date(byAdding: .day, value: roundedDays, to: roundedStartDate) ?? now
                currentBucketKey = calendar.startOfDay(for: roundedDate)
            }
        } else {
            currentBucketKey = nil
        }
        
        // Generate all buckets from start to end
        while currentBucket <= effectiveEndDate {
            let bucketKey: Date
            if component == .hour {
                // Round down to the hour boundary
                let hour = calendar.component(.hour, from: currentBucket)
                let roundedHour = (hour / value) * value
                bucketKey = calendar.date(bySettingHour: roundedHour, minute: 0, second: 0, of: currentBucket) ?? currentBucket
            } else {
                // For days: calculate days since start and round
                let daysSinceStart = calendar.dateComponents([.day], from: roundedStartDate, to: currentBucket).day ?? 0
                let roundedDays = (daysSinceStart / value) * value
                let roundedDate = calendar.date(byAdding: .day, value: roundedDays, to: roundedStartDate) ?? currentBucket
                bucketKey = calendar.startOfDay(for: roundedDate)
            }
            
            // Mark as partial if this is the current incomplete bucket
            let isPartial = offset == 0 && bucketKey == currentBucketKey
            
            // Only create bucket if it's within the effective range
            if bucketKey >= roundedStartDate && bucketKey <= effectiveEndDate {
                buckets[bucketKey] = (0, 0, 0, 0.0, isPartial)
            }
            
            // Move to next interval
            if let next = calendar.date(byAdding: component, value: value, to: currentBucket) {
                currentBucket = next
            } else {
                break
            }
        }
        
        // Ensure we have the bucket for the current time period (only for offset 0)
        if let currentBucketKey = currentBucketKey, buckets[currentBucketKey] == nil {
            buckets[currentBucketKey] = (0, 0, 0, 0.0, true)
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
                    let daysSinceStart = calendar.dateComponents([.day], from: roundedStartDate, to: timeForBucket).day ?? 0
                    let roundedDays = (daysSinceStart / value) * value
                    let roundedDate = calendar.date(byAdding: .day, value: roundedDays, to: roundedStartDate) ?? timeForBucket
                    bucketKey = calendar.startOfDay(for: roundedDate)
                }
                
                if var bucket = buckets[bucketKey] {
                    // Always aggregate all metrics regardless of filters (for totals and aggregate bar)
                    bucket.keys += sample.keyPressCount
                    bucket.clicks += sample.mouseClickCount
                    bucket.scroll += sample.scrollTicks
                    bucket.mouse += sample.mouseDistance
                    // Preserve isPartial flag
                    let isPartial = bucket.isPartial
                    buckets[bucketKey] = (bucket.keys, bucket.clicks, bucket.scroll, bucket.mouse, isPartial)
                }
            }
        }
        
        // Convert buckets to data points, sorted by time
        // Filter to only include buckets within the period range
        return buckets
            .filter { bucketEntry in
                bucketEntry.key >= roundedStartDate && bucketEntry.key <= effectiveEndDate
            }
            .sorted { $0.key < $1.key }
            .map { time, values in
                TimeSeriesDataPoint(
                    time: time,
                    keyPressCount: values.keys,
                    mouseClickCount: values.clicks,
                    scrollTicks: values.scroll,
                    mouseDistance: values.mouse,
                    isPartial: values.isPartial
                )
            }
    }
}

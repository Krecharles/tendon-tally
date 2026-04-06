import Foundation

/// Helper for calculating time series data points from usage samples.
struct TimeSeriesCalculator {
    /// Calculate time series data points for a specific date interval and granularity.
    /// - Parameters:
    ///   - samples: Finalized usage samples to aggregate.
    ///   - currentSample: Current in-progress sample.
    ///   - dateInterval: Interval to aggregate.
    ///   - granularity: Bucket granularity.
    ///   - includeCurrentSample: Whether currentSample should be included.
    ///   - now: Current date/time.
    /// - Returns: Array of time series data points sorted by time.
    static func calculateTimeSeries(
        samples: [UsageSample],
        currentSample: UsageSample?,
        dateInterval: DateInterval,
        granularity: AggregationGranularity,
        includeCurrentSample: Bool,
        now: Date = Date()
    ) -> [TimeSeriesDataPoint] {
        let startDate = dateInterval.start
        let endDate = dateInterval.end
        let calendar = Calendar.current

        let containsNow = now >= startDate && now <= endDate
        let baseRangeEnd = containsNow ? max(endDate, now) : endDate
        let rangeEndExclusive = containsNow ? baseRangeEnd.addingTimeInterval(.ulpOfOne) : baseRangeEnd
        guard rangeEndExclusive > startDate else {
            return []
        }

        let allSamples: [UsageSample]
        if includeCurrentSample, let currentSample {
            allSamples = samples + [currentSample]
        } else {
            allSamples = samples
        }

        let roundedStartDate = granularity.alignedStart(for: startDate, calendar: calendar)
        let currentBucketKey = containsNow ? granularity.alignedStart(for: now, calendar: calendar) : nil

        var buckets: [Date: (keys: Int, clicks: Int, scroll: Int, mouse: Double, isPartial: Bool)] = [:]
        var currentBucket = roundedStartDate

        while currentBucket < rangeEndExclusive {
            let bucketKey = granularity.alignedStart(for: currentBucket, calendar: calendar)
            let isPartial = bucketKey == currentBucketKey
            if bucketKey >= roundedStartDate && bucketKey < rangeEndExclusive {
                buckets[bucketKey] = (0, 0, 0, 0.0, isPartial)
            }

            let next = granularity.addingOneStep(to: currentBucket, calendar: calendar)
            if next <= currentBucket {
                break
            }
            currentBucket = next
        }

        if let currentBucketKey, buckets[currentBucketKey] == nil {
            buckets[currentBucketKey] = (0, 0, 0, 0.0, true)
        }

        for sample in allSamples {
            guard sample.end > startDate, sample.start < rangeEndExclusive else {
                continue
            }

            let isCurrentSample = containsNow && includeCurrentSample && sample.end > now
            let bucketTime = isCurrentSample ? now : sample.start
            let bucketKey = granularity.alignedStart(for: bucketTime, calendar: calendar)
            guard bucketKey >= roundedStartDate, bucketKey < rangeEndExclusive else {
                continue
            }

            guard var bucket = buckets[bucketKey] else {
                continue
            }

            bucket.keys += sample.keyPressCount
            bucket.clicks += sample.mouseClickCount
            bucket.scroll += sample.scrollTicks
            bucket.mouse += sample.mouseDistance
            buckets[bucketKey] = bucket
        }

        return buckets
            .filter { $0.key >= roundedStartDate && $0.key < rangeEndExclusive }
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

    /// Legacy adapter for older call sites.
    static func calculateTimeSeries(
        samples: [UsageSample],
        currentSample: UsageSample?,
        timeFrame: TimeFrame,
        offset: Int,
        now: Date = Date()
    ) -> [TimeSeriesDataPoint] {
        let range = timeFrame.dateRange(offset: offset)
        let granularity: AggregationGranularity
        switch timeFrame {
        case .today:
            granularity = .hour
        case .lastWeek, .lastMonth:
            granularity = .day
        case .lastYear:
            granularity = .week
        }
        return calculateTimeSeries(
            samples: samples,
            currentSample: currentSample,
            dateInterval: DateInterval(start: range.start, end: range.end),
            granularity: granularity,
            includeCurrentSample: offset == 0,
            now: now
        )
    }
}

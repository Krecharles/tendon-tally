// Minimal type definitions for tests.
// These mirror the production types but are compiled independently so we can
// test without importing the executable target.

import Foundation

struct UsageSample: Identifiable, Codable {
    let id: UUID
    let start: Date
    let end: Date
    let keyPressCount: Int
    let mouseClickCount: Int
    let scrollTicks: Int
    let scrollDistance: Double
    let mouseDistance: Double
}

enum TimeFrame: String, CaseIterable {
    case today = "Today"
    case lastWeek = "Week"
    case lastMonth = "Month"

    func dateRange(offset: Int = 0) -> (start: Date, end: Date) {
        let now = Date()
        let calendar = Calendar.current

        switch self {
        case .today:
            let targetDate = calendar.date(byAdding: .day, value: offset, to: now) ?? now
            let startOfDay = calendar.startOfDay(for: targetDate)
            if offset == 0 {
                return (start: startOfDay, end: now)
            } else {
                let endOfDay = calendar.date(byAdding: .day, value: 1, to: startOfDay) ?? startOfDay
                return (start: startOfDay, end: endOfDay)
            }
        case .lastWeek:
            let daysOffset = offset * 7
            let endDate: Date
            if offset == 0 {
                endDate = now
            } else {
                endDate = calendar.date(byAdding: .day, value: daysOffset, to: now) ?? now
            }
            let startDate = calendar.date(byAdding: .day, value: -7, to: endDate) ?? endDate
            return (start: startDate, end: endDate)
        case .lastMonth:
            let monthsOffset = offset
            let endDate: Date
            if offset == 0 {
                endDate = now
            } else {
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

struct KUIConfig: Codable, Equatable {
    var keysWeight: Double
    var clicksWeight: Double
    var scrollTicksWeight: Double
    var mouseDistanceWeight: Double

    static let `default` = KUIConfig(
        keysWeight: 1.0,
        clicksWeight: 1.0,
        scrollTicksWeight: 1.0,
        mouseDistanceWeight: 1.0
    )

    func apply(to metrics: AggregatedMetrics) -> Double {
        let keysTerm = keysWeight * Double(metrics.keyPressCount)
        let clicksTerm = clicksWeight * Double(metrics.mouseClickCount)
        let scrollTerm = scrollTicksWeight * (Double(metrics.scrollTicks) / 100.0)
        let mouseTerm = mouseDistanceWeight * (metrics.mouseDistance / 1000.0)
        return keysTerm + clicksTerm + scrollTerm + mouseTerm
    }
}

struct TimeSeriesDataPoint: Identifiable {
    let id = UUID()
    let time: Date
    let keyPressCount: Int
    let mouseClickCount: Int
    let scrollTicks: Int
    let mouseDistance: Double
    let isPartial: Bool

    init(time: Date, keyPressCount: Int, mouseClickCount: Int, scrollTicks: Int, mouseDistance: Double, isPartial: Bool = false) {
        self.time = time
        self.keyPressCount = keyPressCount
        self.mouseClickCount = mouseClickCount
        self.scrollTicks = scrollTicks
        self.mouseDistance = mouseDistance
        self.isPartial = isPartial
    }
}

struct TimeSeriesCalculator {
    static func calculateTimeSeries(
        samples: [UsageSample],
        currentSample: UsageSample?,
        timeFrame: TimeFrame,
        offset: Int,
        now: Date = Date()
    ) -> [TimeSeriesDataPoint] {
        let (startDate, endDate) = timeFrame.dateRange(offset: offset)

        let allSamples: [UsageSample]
        if offset == 0, let current = currentSample {
            allSamples = samples + [current]
        } else {
            allSamples = samples
        }

        let calendar = Calendar.current

        let (component, value): (Calendar.Component, Int)
        switch timeFrame {
        case .today:
            component = .hour
            value = 1
        case .lastWeek:
            component = .day
            value = 1
        case .lastMonth:
            component = .day
            value = 2
        }

        let effectiveEndDate = offset == 0 ? max(endDate, now) : endDate

        let roundedStartDate: Date
        if component == .hour {
            let hour = calendar.component(.hour, from: startDate)
            let roundedHour = (hour / value) * value
            roundedStartDate = calendar.date(bySettingHour: roundedHour, minute: 0, second: 0, of: startDate) ?? startDate
        } else {
            roundedStartDate = calendar.startOfDay(for: startDate)
        }

        var buckets: [Date: (keys: Int, clicks: Int, scroll: Int, mouse: Double, isPartial: Bool)] = [:]
        var currentBucket = roundedStartDate

        let currentBucketKey: Date?
        if offset == 0 {
            if component == .hour {
                let hour = calendar.component(.hour, from: now)
                let roundedHour = (hour / value) * value
                currentBucketKey = calendar.date(bySettingHour: roundedHour, minute: 0, second: 0, of: now) ?? now
            } else {
                let daysSinceStart = calendar.dateComponents([.day], from: roundedStartDate, to: now).day ?? 0
                let roundedDays = (daysSinceStart / value) * value
                let roundedDate = calendar.date(byAdding: .day, value: roundedDays, to: roundedStartDate) ?? now
                currentBucketKey = calendar.startOfDay(for: roundedDate)
            }
        } else {
            currentBucketKey = nil
        }

        while currentBucket <= effectiveEndDate {
            let bucketKey: Date
            if component == .hour {
                let hour = calendar.component(.hour, from: currentBucket)
                let roundedHour = (hour / value) * value
                bucketKey = calendar.date(bySettingHour: roundedHour, minute: 0, second: 0, of: currentBucket) ?? currentBucket
            } else {
                let daysSinceStart = calendar.dateComponents([.day], from: roundedStartDate, to: currentBucket).day ?? 0
                let roundedDays = (daysSinceStart / value) * value
                let roundedDate = calendar.date(byAdding: .day, value: roundedDays, to: roundedStartDate) ?? currentBucket
                bucketKey = calendar.startOfDay(for: roundedDate)
            }

            let isPartial = offset == 0 && bucketKey == currentBucketKey

            if bucketKey >= roundedStartDate && bucketKey <= effectiveEndDate {
                buckets[bucketKey] = (0, 0, 0, 0.0, isPartial)
            }

            if let next = calendar.date(byAdding: component, value: value, to: currentBucket) {
                currentBucket = next
            } else {
                break
            }
        }

        if let currentBucketKey = currentBucketKey, buckets[currentBucketKey] == nil {
            buckets[currentBucketKey] = (0, 0, 0, 0.0, true)
        }

        for sample in allSamples {
            let sampleEnd = sample.end
            let effectiveEnd = offset == 0 ? max(endDate, now) : endDate

            let sampleOverlaps: Bool
            if offset == 0 {
                sampleOverlaps = sampleEnd >= startDate && sample.start <= effectiveEnd
            } else {
                sampleOverlaps = sample.start >= startDate && sample.end <= effectiveEnd
            }

            if sampleOverlaps {
                let isCurrentSample = offset == 0 && sampleEnd > now
                let timeForBucket = isCurrentSample ? now : sample.start

                let bucketKey: Date
                if component == .hour {
                    let hour = calendar.component(.hour, from: timeForBucket)
                    let roundedHour = (hour / value) * value
                    bucketKey = calendar.date(bySettingHour: roundedHour, minute: 0, second: 0, of: timeForBucket) ?? timeForBucket
                } else {
                    let daysSinceStart = calendar.dateComponents([.day], from: roundedStartDate, to: timeForBucket).day ?? 0
                    let roundedDays = (daysSinceStart / value) * value
                    let roundedDate = calendar.date(byAdding: .day, value: roundedDays, to: roundedStartDate) ?? timeForBucket
                    bucketKey = calendar.startOfDay(for: roundedDate)
                }

                if var bucket = buckets[bucketKey] {
                    bucket.keys += sample.keyPressCount
                    bucket.clicks += sample.mouseClickCount
                    bucket.scroll += sample.scrollTicks
                    bucket.mouse += sample.mouseDistance
                    let isPartial = bucket.isPartial
                    buckets[bucketKey] = (bucket.keys, bucket.clicks, bucket.scroll, bucket.mouse, isPartial)
                }
            }
        }

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

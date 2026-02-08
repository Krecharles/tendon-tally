import XCTest

final class TimeSeriesCalculatorTests: XCTestCase {

    private let calendar = Calendar.current

    private func makeSample(
        start: Date,
        durationMinutes: Int = 5,
        keys: Int = 0,
        clicks: Int = 0,
        scroll: Int = 0,
        mouse: Double = 0.0
    ) -> UsageSample {
        UsageSample(
            id: UUID(),
            start: start,
            end: start.addingTimeInterval(TimeInterval(durationMinutes * 60)),
            keyPressCount: keys,
            mouseClickCount: clicks,
            scrollTicks: scroll,
            scrollDistance: 0,
            mouseDistance: mouse
        )
    }

    // MARK: - Empty Data

    func testEmptyDataReturnsEmptyBuckets() {
        // Use a past day to avoid current-period logic
        let result = TimeSeriesCalculator.calculateTimeSeries(
            samples: [],
            currentSample: nil,
            timeFrame: .today,
            offset: -1
        )

        // Should have 24-25 hourly buckets for a full past day (boundary rounding may add one)
        XCTAssertGreaterThanOrEqual(result.count, 24)
        XCTAssertLessThanOrEqual(result.count, 25)
        for point in result {
            XCTAssertEqual(point.keyPressCount, 0)
            XCTAssertEqual(point.mouseClickCount, 0)
            XCTAssertEqual(point.scrollTicks, 0)
            XCTAssertEqual(point.mouseDistance, 0.0, accuracy: 0.001)
        }
    }

    // MARK: - Hourly Bucketing

    func testHourlyBucketingAggregatesSamplesInSameHour() {
        let now = Date()
        let startOfDay = calendar.startOfDay(for: calendar.date(byAdding: .day, value: -1, to: now)!)

        // Create two samples in the same hour (hour 10)
        let hour10 = calendar.date(bySettingHour: 10, minute: 0, second: 0, of: startOfDay)!
        let s1 = makeSample(start: hour10, keys: 50, clicks: 10)
        let s2 = makeSample(start: hour10.addingTimeInterval(300), keys: 30, clicks: 5)

        let result = TimeSeriesCalculator.calculateTimeSeries(
            samples: [s1, s2],
            currentSample: nil,
            timeFrame: .today,
            offset: -1
        )

        // Find the bucket for hour 10
        let hour10Bucket = result.first { point in
            calendar.component(.hour, from: point.time) == 10
        }

        XCTAssertNotNil(hour10Bucket)
        XCTAssertEqual(hour10Bucket?.keyPressCount, 80) // 50 + 30
        XCTAssertEqual(hour10Bucket?.mouseClickCount, 15) // 10 + 5
    }

    func testHourlyBucketingSeparatesDifferentHours() {
        let now = Date()
        let startOfDay = calendar.startOfDay(for: calendar.date(byAdding: .day, value: -1, to: now)!)

        let hour9 = calendar.date(bySettingHour: 9, minute: 0, second: 0, of: startOfDay)!
        let hour11 = calendar.date(bySettingHour: 11, minute: 0, second: 0, of: startOfDay)!

        let s1 = makeSample(start: hour9, keys: 100)
        let s2 = makeSample(start: hour11, keys: 200)

        let result = TimeSeriesCalculator.calculateTimeSeries(
            samples: [s1, s2],
            currentSample: nil,
            timeFrame: .today,
            offset: -1
        )

        let bucket9 = result.first { calendar.component(.hour, from: $0.time) == 9 }
        let bucket11 = result.first { calendar.component(.hour, from: $0.time) == 11 }

        XCTAssertEqual(bucket9?.keyPressCount, 100)
        XCTAssertEqual(bucket11?.keyPressCount, 200)
    }

    // MARK: - Partial Bucket

    func testCurrentPeriodHasPartialBucket() {
        let now = Date()
        let currentHour = calendar.component(.hour, from: now)
        let startOfCurrentHour = calendar.date(bySettingHour: currentHour, minute: 0, second: 0, of: now)!

        let sample = makeSample(start: startOfCurrentHour, keys: 42)

        let result = TimeSeriesCalculator.calculateTimeSeries(
            samples: [sample],
            currentSample: nil,
            timeFrame: .today,
            offset: 0,
            now: now
        )

        // The bucket for the current hour should be marked as partial
        let currentBucket = result.first { calendar.component(.hour, from: $0.time) == currentHour }
        XCTAssertNotNil(currentBucket)
        XCTAssertTrue(currentBucket?.isPartial ?? false)
    }

    func testPastPeriodHasNoPartialBuckets() {
        let result = TimeSeriesCalculator.calculateTimeSeries(
            samples: [],
            currentSample: nil,
            timeFrame: .today,
            offset: -1
        )

        for point in result {
            XCTAssertFalse(point.isPartial)
        }
    }

    // MARK: - Weekly Bucketing

    func testWeeklyBucketingUsesDayGranularity() {
        let now = Date()
        let twoDaysAgo = calendar.date(byAdding: .day, value: -2, to: now)!
        let threeDaysAgo = calendar.date(byAdding: .day, value: -3, to: now)!

        let s1 = makeSample(start: calendar.startOfDay(for: twoDaysAgo).addingTimeInterval(3600), keys: 100)
        let s2 = makeSample(start: calendar.startOfDay(for: threeDaysAgo).addingTimeInterval(3600), keys: 200)

        let result = TimeSeriesCalculator.calculateTimeSeries(
            samples: [s1, s2],
            currentSample: nil,
            timeFrame: .lastWeek,
            offset: 0,
            now: now
        )

        // Should have 7+ daily buckets
        XCTAssertGreaterThanOrEqual(result.count, 7)

        // Total keys across all buckets should equal 300
        let totalKeys = result.reduce(0) { $0 + $1.keyPressCount }
        XCTAssertEqual(totalKeys, 300)
    }

    // MARK: - All Metrics Tracked

    func testAllMetricsAreAggregated() {
        let now = Date()
        let startOfDay = calendar.startOfDay(for: calendar.date(byAdding: .day, value: -1, to: now)!)
        let hour5 = calendar.date(bySettingHour: 5, minute: 0, second: 0, of: startOfDay)!

        let sample = makeSample(start: hour5, keys: 10, clicks: 20, scroll: 300, mouse: 4000.0)

        let result = TimeSeriesCalculator.calculateTimeSeries(
            samples: [sample],
            currentSample: nil,
            timeFrame: .today,
            offset: -1
        )

        let bucket = result.first { calendar.component(.hour, from: $0.time) == 5 }
        XCTAssertNotNil(bucket)
        XCTAssertEqual(bucket?.keyPressCount, 10)
        XCTAssertEqual(bucket?.mouseClickCount, 20)
        XCTAssertEqual(bucket?.scrollTicks, 300)
        XCTAssertEqual(bucket?.mouseDistance ?? 0, 4000.0, accuracy: 0.001)
    }

    // MARK: - Results Sorted

    func testResultsAreSortedByTime() {
        let now = Date()
        let startOfDay = calendar.startOfDay(for: calendar.date(byAdding: .day, value: -1, to: now)!)

        let hour15 = calendar.date(bySettingHour: 15, minute: 0, second: 0, of: startOfDay)!
        let hour3 = calendar.date(bySettingHour: 3, minute: 0, second: 0, of: startOfDay)!

        // Insert in reverse order
        let s1 = makeSample(start: hour15, keys: 1)
        let s2 = makeSample(start: hour3, keys: 2)

        let result = TimeSeriesCalculator.calculateTimeSeries(
            samples: [s1, s2],
            currentSample: nil,
            timeFrame: .today,
            offset: -1
        )

        for i in 1..<result.count {
            XCTAssertLessThanOrEqual(result[i - 1].time, result[i].time)
        }
    }
}

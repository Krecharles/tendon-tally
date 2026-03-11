import XCTest
@testable import TendonTally

final class MetricTypesTests: XCTestCase {

    // MARK: - TimeFrame.dateRange

    func testTodayDateRangeOffset0() {
        let (start, end) = TimeFrame.today.dateRange(offset: 0)
        let calendar = Calendar.current
        let now = Date()

        XCTAssertEqual(calendar.startOfDay(for: start), calendar.startOfDay(for: now))
        // end should be approximately now
        XCTAssertLessThan(abs(end.timeIntervalSince(now)), 1.0)
    }

    func testTodayDateRangeOffsetNeg1() {
        let (start, end) = TimeFrame.today.dateRange(offset: -1)
        let calendar = Calendar.current
        let now = Date()

        let yesterday = calendar.date(byAdding: .day, value: -1, to: now)!
        XCTAssertEqual(start, calendar.startOfDay(for: yesterday))

        // end should be start of today (full day)
        let startOfToday = calendar.startOfDay(for: now)
        XCTAssertEqual(end, startOfToday)
    }

    func testWeekDateRangeOffset0() {
        let (start, end) = TimeFrame.lastWeek.dateRange(offset: 0)
        let now = Date()

        // Should span 7 days
        let span = end.timeIntervalSince(start)
        XCTAssertEqual(span, 7 * 24 * 60 * 60, accuracy: 2.0)
        XCTAssertLessThan(abs(end.timeIntervalSince(now)), 1.0)
    }

    func testMonthDateRangeOffset0() {
        let (start, end) = TimeFrame.lastMonth.dateRange(offset: 0)
        let now = Date()

        // Should span approximately 30 days
        let span = end.timeIntervalSince(start)
        XCTAssertEqual(span, 30 * 24 * 60 * 60, accuracy: 1.0)
        XCTAssertLessThan(abs(end.timeIntervalSince(now)), 1.0)
    }

    func testMonthDateRangeOffsetNeg1IsPreviousRollingWindow() {
        let (currentStart, _) = TimeFrame.lastMonth.dateRange(offset: 0)
        let (_, previousEnd) = TimeFrame.lastMonth.dateRange(offset: -1)
        XCTAssertEqual(
            currentStart.timeIntervalSinceReferenceDate,
            previousEnd.timeIntervalSinceReferenceDate,
            accuracy: 1.0
        )
    }

    // MARK: - TotalConfig

    func testTotalConfigDefaultWeights() {
        let config = TotalConfig.default
        XCTAssertEqual(config.keysWeight, 1.0)
        XCTAssertEqual(config.clicksWeight, 1.0)
        XCTAssertEqual(config.scrollTicksWeight, 1.0)
        XCTAssertEqual(config.mouseDistanceWeight, 1.0)
    }

    func testTotalConfigApplyDefaultWeights() {
        let config = TotalConfig.default
        let metrics = AggregatedMetrics(
            keyPressCount: 100,
            mouseClickCount: 50,
            scrollTicks: 200,
            mouseDistance: 3000.0
        )

        let result = config.apply(to: metrics)
        // 100*1 + 50*1 + (200/100)*1 + (3000/1000)*1 = 100 + 50 + 2 + 3 = 155
        XCTAssertEqual(result, 155.0, accuracy: 0.001)
    }

    func testTotalConfigApplyCustomWeights() {
        let config = TotalConfig(
            keysWeight: 2.0,
            clicksWeight: 0.5,
            scrollTicksWeight: 0.0,
            mouseDistanceWeight: -1.0
        )
        let metrics = AggregatedMetrics(
            keyPressCount: 100,
            mouseClickCount: 50,
            scrollTicks: 200,
            mouseDistance: 3000.0
        )

        let result = config.apply(to: metrics)
        // 100*2 + 50*0.5 + (200/100)*0 + (3000/1000)*(-1) = 200 + 25 + 0 - 3 = 222
        XCTAssertEqual(result, 222.0, accuracy: 0.001)
    }

    func testTotalConfigApplyZeroMetrics() {
        let config = TotalConfig.default
        let metrics = AggregatedMetrics(
            keyPressCount: 0,
            mouseClickCount: 0,
            scrollTicks: 0,
            mouseDistance: 0.0
        )

        let result = config.apply(to: metrics)
        XCTAssertEqual(result, 0.0, accuracy: 0.001)
    }

    // MARK: - MetricType

    func testMetricTypeIndividualMetrics() {
        let individual = MetricType.individualMetrics
        XCTAssertEqual(individual.count, 4)
        XCTAssertTrue(individual.contains(.keys))
        XCTAssertTrue(individual.contains(.clicks))
        XCTAssertTrue(individual.contains(.scroll))
        XCTAssertTrue(individual.contains(.mouseDistance))
        XCTAssertFalse(individual.contains(.aggregate))
    }

    func testMetricTypeAllCases() {
        XCTAssertEqual(MetricType.allCases.count, 5)
    }

    // MARK: - Daily Export

    func testDailyExportDayOffsets() {
        XCTAssertEqual(DailyExportDay.today.offset, 0)
        XCTAssertEqual(DailyExportDay.yesterday.offset, -1)
    }

    // MARK: - TotalConfig Codable

    func testTotalConfigCodableRoundTrip() throws {
        let config = TotalConfig(keysWeight: 1.5, clicksWeight: 2.0, scrollTicksWeight: 0.5, mouseDistanceWeight: 3.0)
        let data = try JSONEncoder().encode(config)
        let decoded = try JSONDecoder().decode(TotalConfig.self, from: data)
        XCTAssertEqual(config, decoded)
    }

    // MARK: - BreaksConfig

    func testBreaksConfigNormalizationEnforcesTwoMinuteReminderLead() {
        let config = BreaksConfig(
            lookbackMinutes: 10,
            requiredBreakMinutes: 9,
            remindersEnabled: true
        )

        let normalized = config.normalized()
        XCTAssertEqual(
            normalized.lookbackMinutes - normalized.requiredBreakMinutes,
            BreaksConfig.minTimeBeforeReminderMinutes
        )
    }

    func testBreaksConfigNormalizationKeepsValidReminderLead() {
        let config = BreaksConfig(
            lookbackMinutes: 30,
            requiredBreakMinutes: 5,
            remindersEnabled: true
        )

        let normalized = config.normalized()
        XCTAssertEqual(normalized.lookbackMinutes, 30)
        XCTAssertEqual(normalized.requiredBreakMinutes, 5)
    }

    func testBreaksConfigNormalizationAllowsTwoMinuteLeadWithFiveMinuteBreak() {
        let config = BreaksConfig(
            lookbackMinutes: 7,
            requiredBreakMinutes: 5,
            remindersEnabled: true
        )

        let normalized = config.normalized()
        XCTAssertEqual(normalized.lookbackMinutes, 7)
        XCTAssertEqual(normalized.requiredBreakMinutes, 5)
        XCTAssertEqual(normalized.lookbackMinutes - normalized.requiredBreakMinutes, 2)
    }
}

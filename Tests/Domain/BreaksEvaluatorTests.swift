import XCTest
@testable import TendonTally

final class BreaksEvaluatorTests: XCTestCase {
    private let defaultConfig = BreaksConfig.default // 30m lookback, 5m break

    // MARK: - Phase determination

    func testWorkPhaseWhenWithinWorkWindow() {
        let now = Date()
        let breakEndedAt = now.addingTimeInterval(-10 * 60) // 10 min ago
        let lastActivity = now.addingTimeInterval(-5) // 5s ago

        let eval = BreaksEvaluator.evaluate(
            lastBreakEndedAt: breakEndedAt,
            lastActivityAt: lastActivity,
            config: defaultConfig,
            now: now
        )

        XCTAssertEqual(eval.phase, .work)
    }

    func testDuePhaseWhenWorkWindowExceeded() {
        let now = Date()
        let breakEndedAt = now.addingTimeInterval(-30 * 60) // 30 min ago (exceeds 25m work window)
        let lastActivity = now.addingTimeInterval(-5) // 5s ago

        let eval = BreaksEvaluator.evaluate(
            lastBreakEndedAt: breakEndedAt,
            lastActivityAt: lastActivity,
            config: defaultConfig,
            now: now
        )

        XCTAssertEqual(eval.phase, .due)
    }

    func testDuePhaseWhenNoBreakRecorded() {
        let now = Date()
        let lastActivity = now.addingTimeInterval(-5)

        let eval = BreaksEvaluator.evaluate(
            lastBreakEndedAt: nil,
            lastActivityAt: lastActivity,
            config: defaultConfig,
            now: now
        )

        XCTAssertEqual(eval.phase, .due)
    }

    func testOnBreakPhaseWhenIdleLongEnough() {
        let now = Date()
        let lastActivity = now.addingTimeInterval(-6 * 60) // 6 min idle (>= 5m required)

        let eval = BreaksEvaluator.evaluate(
            lastBreakEndedAt: nil,
            lastActivityAt: lastActivity,
            config: defaultConfig,
            now: now
        )

        XCTAssertEqual(eval.phase, .onBreak)
        XCTAssertEqual(eval.currentIdleSeconds, 6 * 60, accuracy: 1)
    }

    func testOnBreakPhaseAtExactBoundary() {
        let now = Date()
        let lastActivity = now.addingTimeInterval(-5 * 60) // exactly 5m

        let eval = BreaksEvaluator.evaluate(
            lastBreakEndedAt: nil,
            lastActivityAt: lastActivity,
            config: defaultConfig,
            now: now
        )

        XCTAssertEqual(eval.phase, .onBreak)
    }

    // MARK: - Idle duration

    func testIdleDurationComputedFromLastActivity() {
        let now = Date()
        let lastActivity = now.addingTimeInterval(-120) // 2 min ago

        let eval = BreaksEvaluator.evaluate(
            lastBreakEndedAt: now,
            lastActivityAt: lastActivity,
            config: defaultConfig,
            now: now
        )

        XCTAssertEqual(eval.currentIdleSeconds, 120, accuracy: 1)
    }

    func testIdleDurationZeroWhenNoLastActivity() {
        let now = Date()

        let eval = BreaksEvaluator.evaluate(
            lastBreakEndedAt: nil,
            lastActivityAt: nil,
            config: defaultConfig,
            now: now
        )

        XCTAssertEqual(eval.currentIdleSeconds, 0)
    }

    // MARK: - Config normalization

    func testWorkWindowComputedFromConfig() {
        let now = Date()
        let eval = BreaksEvaluator.evaluate(
            lastBreakEndedAt: now,
            lastActivityAt: now,
            config: defaultConfig,
            now: now
        )

        // 30m lookback - 5m break = 25m work window
        XCTAssertEqual(eval.workWindowSeconds, 25 * 60, accuracy: 1)
        XCTAssertEqual(eval.requiredBreakSeconds, 5 * 60, accuracy: 1)
    }

    func testWorkWindowEnforcesMinimum() {
        let config = BreaksConfig(
            lookbackMinutes: 3, // very small
            requiredBreakMinutes: 1,
            remindersEnabled: true
        )
        let now = Date()
        let eval = BreaksEvaluator.evaluate(
            lastBreakEndedAt: now,
            lastActivityAt: now,
            config: config,
            now: now
        )

        XCTAssertGreaterThanOrEqual(eval.workWindowSeconds, TimeInterval(BreaksConfig.minTimeBeforeReminderMinutes * 60))
    }

    // MARK: - Transition detection

    func testTransitionTrackerDetectsBreakToActive() {
        let now = Date()
        var tracker = BreakTransitionTracker()
        let config = defaultConfig

        // Tick while on break (idle >= 5m)
        let duringBreak = now.addingTimeInterval(-6 * 60) // last activity 6m ago
        tracker.update(lastActivityAt: duringBreak, config: config, now: now)

        // Tick after resuming activity (idle < 5m)
        let afterResume = now.addingTimeInterval(1)
        let resumed = now.addingTimeInterval(0.5) // activity just happened
        let transitioned = tracker.update(lastActivityAt: resumed, config: config, now: afterResume)

        XCTAssertTrue(transitioned)
        XCTAssertNotNil(tracker.lastBreakEndedAt)
        XCTAssertEqual(tracker.lastBreakEndedAt!, afterResume)
    }

    func testTransitionTrackerNoTransitionDuringContinuousWork() {
        let now = Date()
        var tracker = BreakTransitionTracker()
        let config = defaultConfig

        // Multiple ticks with recent activity (never on break)
        for i in 0..<5 {
            let tick = now.addingTimeInterval(TimeInterval(i))
            let activity = tick.addingTimeInterval(-1)
            let transitioned = tracker.update(lastActivityAt: activity, config: config, now: tick)
            XCTAssertFalse(transitioned)
        }

        XCTAssertNil(tracker.lastBreakEndedAt)
    }

    // MARK: - Startup restoration

    func testStartupRestorationWithLongAbsence() {
        let now = Date()
        var tracker = BreakTransitionTracker()

        let lastActivity = now.addingTimeInterval(-10 * 60) // 10m ago, >= 5m required
        tracker.restoreFromStartup(
            persistedLastActivityAt: lastActivity,
            persistedLastBreakEndedAt: nil,
            config: defaultConfig,
            now: now
        )

        XCTAssertNotNil(tracker.lastBreakEndedAt)
        XCTAssertEqual(tracker.lastBreakEndedAt!, now)
    }

    func testStartupRestorationWithShortAbsence() {
        let now = Date()
        var tracker = BreakTransitionTracker()

        let lastActivity = now.addingTimeInterval(-2 * 60) // 2m ago, < 5m required
        let persistedBreakEnd = now.addingTimeInterval(-20 * 60)
        tracker.restoreFromStartup(
            persistedLastActivityAt: lastActivity,
            persistedLastBreakEndedAt: persistedBreakEnd,
            config: defaultConfig,
            now: now
        )

        XCTAssertEqual(tracker.lastBreakEndedAt, persistedBreakEnd)
    }

    func testStartupRestorationWithNoPersistedActivity() {
        let now = Date()
        var tracker = BreakTransitionTracker()

        let persistedBreakEnd = now.addingTimeInterval(-15 * 60)
        tracker.restoreFromStartup(
            persistedLastActivityAt: nil,
            persistedLastBreakEndedAt: persistedBreakEnd,
            config: defaultConfig,
            now: now
        )

        XCTAssertEqual(tracker.lastBreakEndedAt, persistedBreakEnd)
    }

    // MARK: - Snooze options

    func testSnoozeOptionFiveMinutesAddsExpectedInterval() {
        let now = Date(timeIntervalSince1970: 1_700_000_000)
        let until = BreakReminderSnoozeOption.fiveMinutes.snoozedUntil(from: now)
        XCTAssertEqual(until.timeIntervalSince(now), 5 * 60, accuracy: 0.1)
    }

    func testSnoozeOptionUntilTomorrowUsesNextMidnight() {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        let now = calendar.date(from: DateComponents(
            year: 2026,
            month: 2,
            day: 16,
            hour: 18,
            minute: 30,
            second: 0
        ))!

        let until = BreakReminderSnoozeOption.untilTomorrow.snoozedUntil(from: now, calendar: calendar)
        let expected = calendar.date(from: DateComponents(
            year: 2026,
            month: 2,
            day: 17,
            hour: 0,
            minute: 0,
            second: 0
        ))!

        XCTAssertEqual(until, expected)
    }
}

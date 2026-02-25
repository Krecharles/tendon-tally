import XCTest
@testable import TendonTally

final class BetaAccessPolicyTests: XCTestCase {
    func testNotExpiredBeforeAprilFirst2026() {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        let now = calendar.date(from: DateComponents(
            year: 2026,
            month: 3,
            day: 31,
            hour: 23,
            minute: 59,
            second: 59
        ))!

        XCTAssertFalse(BetaAccessPolicy.isExpired(now: now, calendar: calendar))
    }

    func testExpiredAtAprilFirst2026Midnight() {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        let now = calendar.date(from: DateComponents(
            year: 2026,
            month: 4,
            day: 1,
            hour: 0,
            minute: 0,
            second: 0
        ))!

        XCTAssertTrue(BetaAccessPolicy.isExpired(now: now, calendar: calendar))
    }
}

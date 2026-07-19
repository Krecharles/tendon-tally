import XCTest
@testable import TendonTally

final class DashboardToggleActionTests: XCTestCase {
    func testHidesWhenDashboardIsVisibleAndApplicationIsActive() {
        XCTAssertEqual(
            DashboardToggleAction.resolve(
                isDashboardVisible: true,
                isApplicationActive: true
            ),
            .hide
        )
    }

    func testShowsWhenDashboardIsBehindAnotherApplication() {
        XCTAssertEqual(
            DashboardToggleAction.resolve(
                isDashboardVisible: true,
                isApplicationActive: false
            ),
            .show
        )
    }

    func testShowsWhenDashboardIsNotVisible() {
        XCTAssertEqual(
            DashboardToggleAction.resolve(
                isDashboardVisible: false,
                isApplicationActive: true
            ),
            .show
        )
    }
}

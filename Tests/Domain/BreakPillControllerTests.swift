import XCTest
@testable import TendonTally

@MainActor
final class BreakPillControllerTests: XCTestCase {
    func testCompletedBreakStaysVisibleUntilInputResumesWork() {
        let controller = BreakPillController(presentPanels: false)
        let config = BreaksConfig(
            lookbackMinutes: 30,
            requiredBreakMinutes: 5,
            remindersEnabled: true
        )
        let now = Date()

        let dueEvaluation = BreaksEvaluation(
            phase: .due,
            lastBreakEndedAt: now.addingTimeInterval(-(25 * 60)),
            currentIdleSeconds: 120,
            workWindowSeconds: 25 * 60,
            requiredBreakSeconds: 5 * 60
        )
        controller.update(evaluation: dueEvaluation, config: config)
        XCTAssertTrue(controller.isVisible)

        let onBreakEvaluation = BreaksEvaluation(
            phase: .onBreak,
            lastBreakEndedAt: dueEvaluation.lastBreakEndedAt,
            currentIdleSeconds: 360,
            workWindowSeconds: 25 * 60,
            requiredBreakSeconds: 5 * 60
        )
        controller.update(evaluation: onBreakEvaluation, config: config)

        XCTAssertEqual(controller.phase, .onBreak)
        XCTAssertTrue(controller.isVisible)
        XCTAssertEqual(controller.primaryText, "5m 00s")
        XCTAssertEqual(controller.progress, 1.0, accuracy: 0.001)
        XCTAssertTrue(controller.showCelebration)
        XCTAssertFalse(controller.showResetWarning)

        let backToWorkEvaluation = BreaksEvaluation(
            phase: .work,
            lastBreakEndedAt: now,
            currentIdleSeconds: 0,
            workWindowSeconds: 25 * 60,
            requiredBreakSeconds: 5 * 60
        )
        controller.update(evaluation: backToWorkEvaluation, config: config)

        XCTAssertEqual(controller.phase, .work)
        XCTAssertFalse(controller.isVisible)
        XCTAssertFalse(controller.showCelebration)
    }

    func testEarlyBreakDuringWorkStaysSilent() {
        let controller = BreakPillController(presentPanels: false)
        let config = BreaksConfig(
            lookbackMinutes: 30,
            requiredBreakMinutes: 5,
            remindersEnabled: true
        )
        let now = Date()

        let workEvaluation = BreaksEvaluation(
            phase: .work,
            lastBreakEndedAt: now,
            currentIdleSeconds: 10,
            workWindowSeconds: 25 * 60,
            requiredBreakSeconds: 5 * 60
        )
        controller.update(evaluation: workEvaluation, config: config)
        XCTAssertFalse(controller.isVisible)

        let onBreakEvaluation = BreaksEvaluation(
            phase: .onBreak,
            lastBreakEndedAt: now,
            currentIdleSeconds: 360,
            workWindowSeconds: 25 * 60,
            requiredBreakSeconds: 5 * 60
        )
        controller.update(evaluation: onBreakEvaluation, config: config)

        XCTAssertEqual(controller.phase, .onBreak)
        XCTAssertFalse(controller.isVisible)
        XCTAssertFalse(controller.showCelebration)
    }
}

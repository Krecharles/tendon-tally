import XCTest
@testable import TendonTally

final class MetricsAggregatorTests: XCTestCase {
    private final class MockEventTapManager: EventTapping {
        var onPermissionOrTapFailure: ((String) -> Void)?
        var onPermissionGranted: (() -> Void)?

        var snapshotValue = RawActivitySnapshot()

        func start() {}
        func stop() {}
        func snapshot() -> RawActivitySnapshot { snapshotValue }
        func resetCounters() { snapshotValue = RawActivitySnapshot() }

        func emitPermissionFailure(_ message: String) {
            onPermissionOrTapFailure?(message)
        }

        func emitPermissionGranted() {
            onPermissionGranted?()
        }
    }

    private final class MockPersistence: MetricsPersisting {
        var storedSamples: [UsageSample] = []
        var storedCurrentSample: UsageSample?

        var finalizedSyncSaves: [UsageSample] = []
        var currentSyncSaves: [UsageSample] = []
        var deletedCurrentSample = false

        func loadSamples() -> (samples: [UsageSample], currentSample: UsageSample?) {
            (storedSamples, storedCurrentSample)
        }

        func saveFinalizedSample(_ sample: UsageSample) {}

        func saveFinalizedSampleSync(_ sample: UsageSample) {
            finalizedSyncSaves.append(sample)
        }

        func saveCurrentSample(_ currentSample: UsageSample) {}

        func saveCurrentSampleSync(_ currentSample: UsageSample) {
            currentSyncSaves.append(currentSample)
        }

        func deleteCurrentSample() {
            deletedCurrentSample = true
            storedCurrentSample = nil
        }
    }

    private func sample(start: Date, end: Date, keys: Int = 0) -> UsageSample {
        UsageSample(
            id: UUID(),
            start: start,
            end: end,
            keyPressCount: keys,
            mouseClickCount: 0,
            scrollTicks: 0,
            scrollDistance: 0,
            mouseDistance: 0
        )
    }

    func testInitFinalizesExpiredRestoredCurrentSample() {
        let now = Date(timeIntervalSince1970: 1_705_000_000)
        let expired = sample(
            start: now.addingTimeInterval(-120),
            end: now.addingTimeInterval(-60),
            keys: 42
        )

        let persistence = MockPersistence()
        persistence.storedCurrentSample = expired
        let eventTap = MockEventTapManager()

        let aggregator = MetricsAggregator(
            eventTapManager: eventTap,
            persistence: persistence,
            now: now
        )

        XCTAssertEqual(aggregator.history.count, 1)
        XCTAssertEqual(aggregator.history.first?.id, expired.id)
        XCTAssertEqual(persistence.finalizedSyncSaves.count, 1)
        XCTAssertEqual(persistence.finalizedSyncSaves.first?.id, expired.id)
        XCTAssertTrue(persistence.deletedCurrentSample)
    }

    func testPermissionCallbacksPropagateFromEventTap() {
        let persistence = MockPersistence()
        let eventTap = MockEventTapManager()
        let aggregator = MetricsAggregator(eventTapManager: eventTap, persistence: persistence)

        let failureExpectation = expectation(description: "Failure callback forwarded")
        let grantedExpectation = expectation(description: "Granted callback forwarded")

        aggregator.onPermissionOrTapFailure = { message in
            XCTAssertEqual(message, "Missing permissions")
            failureExpectation.fulfill()
        }
        aggregator.onPermissionGranted = {
            grantedExpectation.fulfill()
        }

        eventTap.emitPermissionFailure("Missing permissions")
        eventTap.emitPermissionGranted()

        wait(for: [failureExpectation, grantedExpectation], timeout: 1.0)
    }

    @MainActor
    func testMetricsViewModelPermissionMessageClearsAfterGrant() async {
        let persistence = MockPersistence()
        let eventTap = MockEventTapManager()
        let aggregator = MetricsAggregator(eventTapManager: eventTap, persistence: persistence)
        let viewModel = MetricsViewModel(
            aggregator: aggregator,
            breakPillController: BreakPillController()
        )

        eventTap.emitPermissionFailure("Input Monitoring permission is required to count keyboard activity.")

        let failureExpectation = expectation(description: "View model receives permission failure")
        Task { @MainActor in
            while viewModel.permissionIssueMessage == nil {
                await Task.yield()
            }
            failureExpectation.fulfill()
        }
        await fulfillment(of: [failureExpectation], timeout: 1.0)
        XCTAssertEqual(viewModel.permissionIssueMessage, "Input Monitoring permission is required to count keyboard activity.")

        eventTap.emitPermissionGranted()
        let grantedExpectation = expectation(description: "View model clears permission message")
        Task { @MainActor in
            while viewModel.permissionIssueMessage != nil {
                await Task.yield()
            }
            grantedExpectation.fulfill()
        }
        await fulfillment(of: [grantedExpectation], timeout: 1.0)
        XCTAssertNil(viewModel.permissionIssueMessage)
    }
}

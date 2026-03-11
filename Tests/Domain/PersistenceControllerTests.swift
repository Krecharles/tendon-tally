import XCTest
@testable import TendonTally

final class PersistenceControllerTests: XCTestCase {
    private var tempDirectory: URL!

    override func setUpWithError() throws {
        let base = URL(fileURLWithPath: NSTemporaryDirectory(), isDirectory: true)
        tempDirectory = base.appendingPathComponent("TendonTallyTests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: tempDirectory, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        if let tempDirectory {
            try? FileManager.default.removeItem(at: tempDirectory)
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

    func testDeleteAllSamplesSyncRemovesFinalizedAndCurrentData() {
        let controller = PersistenceController(dataDirectory: tempDirectory)
        let now = Date(timeIntervalSince1970: 1_705_000_000)

        let finalized = sample(start: now.addingTimeInterval(-120), end: now.addingTimeInterval(-60), keys: 10)
        let current = sample(start: now.addingTimeInterval(-30), end: now.addingTimeInterval(30), keys: 3)

        controller.saveFinalizedSampleSync(finalized)
        controller.saveCurrentSampleSync(current)

        let beforeDelete = controller.loadSamples()
        XCTAssertEqual(beforeDelete.samples.count, 1)
        XCTAssertNotNil(beforeDelete.currentSample)

        controller.deleteAllSamplesSync()

        let afterDelete = controller.loadSamples()
        XCTAssertTrue(afterDelete.samples.isEmpty)
        XCTAssertNil(afterDelete.currentSample)
    }

    func testDeleteAllSamplesCompletionRunsAfterDataIsGone() {
        let controller = PersistenceController(dataDirectory: tempDirectory)
        let now = Date(timeIntervalSince1970: 1_705_000_000)
        let finalized = sample(start: now.addingTimeInterval(-120), end: now.addingTimeInterval(-60), keys: 10)
        let current = sample(start: now.addingTimeInterval(-30), end: now.addingTimeInterval(30), keys: 3)

        controller.saveFinalizedSampleSync(finalized)
        controller.saveCurrentSampleSync(current)

        let completionExpectation = expectation(description: "Delete completion called")
        controller.deleteAllSamples {
            let reloaded = controller.loadSamples()
            XCTAssertTrue(reloaded.samples.isEmpty)
            XCTAssertNil(reloaded.currentSample)
            completionExpectation.fulfill()
        }

        wait(for: [completionExpectation], timeout: 1.0)
    }

}

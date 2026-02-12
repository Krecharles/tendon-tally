import Foundation
import os.log

/// Aggregates raw activity counts from EventTapManager into fixed 5-minute UsageSample windows.
///
/// This class manages the rolling window system, periodically finalizing completed windows
/// and starting new ones. It also handles persistence of historical data.
final class MetricsAggregator {
    private var eventTapManager: EventTapping
    private let persistence: MetricsPersisting
    private let logger = Logger(subsystem: "com.tendontally", category: "MetricsAggregator")

    private let windowLength: TimeInterval = 1 * 60
    private var windowStart: Date = Date()
    private(set) var lastActivityAt: Date?

    private(set) var currentSample: UsageSample
    private(set) var history: [UsageSample] = []

    private var timer: Timer?
    private var saveTimer: Timer?

    /// Called on the main thread whenever currentSample or history changes.
    var onUpdate: ((UsageSample, [UsageSample]) -> Void)?

    /// Called when there is a permission or event tap problem.
    var onPermissionOrTapFailure: ((String) -> Void)? {
        get { eventTapManager.onPermissionOrTapFailure }
        set { eventTapManager.onPermissionOrTapFailure = newValue }
    }

    /// Called when the event tap is successfully created (permissions granted).
    var onPermissionGranted: (() -> Void)? {
        get { eventTapManager.onPermissionGranted }
        set { eventTapManager.onPermissionGranted = newValue }
    }

    init(
        eventTapManager: EventTapping = EventTapManager(),
        persistence: MetricsPersisting = PersistenceController.shared,
        restoredLastActivityAt: Date? = nil,
        now: Date = Date()
    ) {
        self.eventTapManager = eventTapManager
        self.persistence = persistence
        self.lastActivityAt = restoredLastActivityAt

        let (stored, savedCurrent) = persistence.loadSamples()
        self.history = stored.sorted { $0.start > $1.start }
        logger.info("Initialized with \(self.history.count) historical samples")

        if let saved = savedCurrent {
            if saved.end > now {
                // Window is still active — resume it.
                self.currentSample = saved
                self.windowStart = saved.start
                let formatter = ISO8601DateFormatter()
                logger.info("Restored current sample from \(formatter.string(from: saved.start)) with \(saved.keyPressCount) keys, \(saved.mouseClickCount) clicks")
            } else {
                // Window has expired — finalize it into history so no data is lost.
                self.history.insert(saved, at: 0)
                persistence.saveFinalizedSampleSync(saved)
                persistence.deleteCurrentSample()
                let formatter = ISO8601DateFormatter()
                logger.info("Finalized expired restored sample from \(formatter.string(from: saved.start)) with \(saved.keyPressCount) keys, \(saved.mouseClickCount) clicks")

                // Start a fresh window.
                let end = now.addingTimeInterval(windowLength)
                self.currentSample = UsageSample(
                    id: UUID(),
                    start: now,
                    end: end,
                    keyPressCount: 0,
                    mouseClickCount: 0,
                    scrollTicks: 0,
                    scrollDistance: 0,
                    mouseDistance: 0
                )
                self.windowStart = now
            }
        } else {
            let end = now.addingTimeInterval(windowLength)
            self.currentSample = UsageSample(
                id: UUID(),
                start: now,
                end: end,
                keyPressCount: 0,
                mouseClickCount: 0,
                scrollTicks: 0,
                scrollDistance: 0,
                mouseDistance: 0
            )
            self.windowStart = now
            let formatter = ISO8601DateFormatter()
            logger.info("Started new current sample window at \(formatter.string(from: now))")
        }
    }

    func start() {
        logger.info("Starting metrics aggregation")
        eventTapManager.start()
        startTimer()
        startSaveTimer()
        pushUpdate()
    }

    func stop() {
        logger.info("Stopping metrics aggregation - saving final state")
        timer?.invalidate()
        timer = nil
        saveTimer?.invalidate()
        saveTimer = nil
        eventTapManager.stop()

        // Refresh from the latest event counts before saving.
        refreshCurrentSample(end: currentSample.end)

        // Synchronous save so the write completes before the process exits.
        persistence.saveCurrentSampleSync(self.currentSample)
        logger.info("Final save completed: \(self.history.count) samples, current sample has \(self.currentSample.keyPressCount) keys, \(self.currentSample.mouseClickCount) clicks")
    }

    /// Reload history from persistence (useful after data deletion).
    func reloadHistory() {
        let (stored, savedCurrent) = persistence.loadSamples()
        self.history = stored.sorted { $0.start > $1.start }
        if let saved = savedCurrent, saved.end > Date() {
            self.currentSample = saved
            self.windowStart = saved.start
        }
        pushUpdate()
    }

    // MARK: - Timer & Windowing

    private func startTimer() {
        timer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { [weak self] _ in
            self?.tick()
        }
        RunLoop.main.add(timer!, forMode: .common)
    }

    private func startSaveTimer() {
        saveTimer = Timer.scheduledTimer(withTimeInterval: 10.0, repeats: true) { [weak self] _ in
            self?.saveCurrentSample()
        }
        RunLoop.main.add(saveTimer!, forMode: .common)
    }

    private func saveCurrentSample() {
        refreshCurrentSample(end: self.currentSample.end)
        persistence.saveCurrentSample(self.currentSample)
        logger.debug("Periodic save: current sample has \(self.currentSample.keyPressCount) keys, \(self.currentSample.mouseClickCount) clicks, \(self.currentSample.scrollTicks) scroll ticks")
    }

    private func tick() {
        let now = Date()
        if now.timeIntervalSince(windowStart) >= windowLength {
            rollWindow(to: now)
        } else {
            refreshCurrentSample(end: currentSample.end)
        }
    }

    private func rollWindow(to now: Date) {
        // Finalize current window with now as the end time.
        refreshCurrentSample(end: now)

        let finalizedSample = self.currentSample
        self.history.insert(finalizedSample, at: 0)
        logger.info("Rolled window: finalized sample with \(finalizedSample.keyPressCount) keys, \(finalizedSample.mouseClickCount) clicks, \(finalizedSample.scrollTicks) scroll ticks")

        persistence.saveFinalizedSample(finalizedSample)

        // Reset counters synchronously so the next snapshot reads zero.
        eventTapManager.resetCounters()

        // Start a new window.
        self.windowStart = now
        let newEnd = now.addingTimeInterval(windowLength)

        self.currentSample = UsageSample(
            id: UUID(),
            start: now,
            end: newEnd,
            keyPressCount: 0,
            mouseClickCount: 0,
            scrollTicks: 0,
            scrollDistance: 0,
            mouseDistance: 0
        )
        persistence.saveCurrentSample(self.currentSample)
        let formatter = ISO8601DateFormatter()
        logger.info("Started new window at \(formatter.string(from: now))")
        pushUpdate()
    }

    private func refreshCurrentSample(end: Date) {
        let raw = eventTapManager.snapshot()
        if let rawLastActivity = raw.lastActivityAt {
            lastActivityAt = rawLastActivity
        }
        currentSample = UsageSample(
            id: currentSample.id,
            start: windowStart,
            end: end,
            keyPressCount: raw.keyPressCount,
            mouseClickCount: raw.mouseClickCount,
            scrollTicks: raw.scrollTicks,
            scrollDistance: 0,
            mouseDistance: raw.mouseDistance
        )
        pushUpdate()
    }

    private func pushUpdate() {
        let sample = currentSample
        let historyCopy = history
        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            self.onUpdate?(sample, historyCopy)
        }
    }
}

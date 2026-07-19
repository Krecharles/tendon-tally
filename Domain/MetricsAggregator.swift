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

    private let windowLength: TimeInterval = 5 * 60
    private var windowStart: Date = Date()
    private(set) var lastActivityAt: Date?

    private(set) var currentSample: UsageSample
    private(set) var history: [UsageSample] = []

    private var windowTimer: Timer?
    private var saveTimer: Timer?
    private var hasUnsavedChanges = false
    private var baseKeyPressCount = 0
    private var baseMouseClickCount = 0
    private var baseScrollTicks = 0
    private var baseMouseDistance = 0.0

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
            if saved.start > now {
                // System time may have moved backwards since the sample was persisted.
                // Discard future-dated current sample so live "today" metrics can recover.
                persistence.deleteCurrentSample()
                let formatter = ISO8601DateFormatter()
                logger.warning("Discarded future-dated restored sample from \(formatter.string(from: saved.start)); starting new window")

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
            } else if saved.end > now {
                // Window is still active — resume it.
                let normalizedEnd = max(saved.end, saved.start.addingTimeInterval(windowLength))
                self.currentSample = UsageSample(
                    id: saved.id,
                    start: saved.start,
                    end: normalizedEnd,
                    keyPressCount: saved.keyPressCount,
                    mouseClickCount: saved.mouseClickCount,
                    scrollTicks: saved.scrollTicks,
                    scrollDistance: saved.scrollDistance,
                    mouseDistance: saved.mouseDistance
                )
                self.windowStart = saved.start
                let formatter = ISO8601DateFormatter()
                logger.info("Restored current sample from \(formatter.string(from: saved.start)) with \(saved.keyPressCount) keys, \(saved.mouseClickCount) clicks")
            } else {
                // Window has expired — finalize it into history so no data is lost.
                if Self.sampleHasActivity(saved) {
                    self.history.insert(saved, at: 0)
                    persistence.saveFinalizedSampleSync(saved)
                }
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

        baseKeyPressCount = currentSample.keyPressCount
        baseMouseClickCount = currentSample.mouseClickCount
        baseScrollTicks = currentSample.scrollTicks
        baseMouseDistance = currentSample.mouseDistance

        self.eventTapManager.onActivity = { [weak self] in
            self?.activityObserved()
        }
    }

    func start() {
        logger.info("Starting metrics aggregation")
        eventTapManager.start()
        scheduleWindowTimer()
        pushUpdate()
    }

    func stop() {
        logger.info("Stopping metrics aggregation - saving final state")
        windowTimer?.invalidate()
        windowTimer = nil
        saveTimer?.invalidate()
        saveTimer = nil

        // Refresh from the latest event counts before saving.
        refreshCurrentSample(end: currentSample.end, publish: false)
        eventTapManager.stop()

        // Synchronous save so the write completes before the process exits.
        persistence.saveCurrentSampleSync(self.currentSample)
        logger.info("Final save completed: \(self.history.count) samples, current sample has \(self.currentSample.keyPressCount) keys, \(self.currentSample.mouseClickCount) clicks")
    }

    /// Reload history from persistence (useful after data deletion).
    func reloadHistory() {
        let (stored, _) = persistence.loadSamples()
        self.history = stored.sorted { $0.start > $1.start }
        pushUpdate()
    }

    // MARK: - Timer & Windowing

    private func scheduleWindowTimer(now: Date = Date()) {
        windowTimer?.invalidate()
        let interval = max(1, currentSample.end.timeIntervalSince(now))
        let timer = Timer.scheduledTimer(withTimeInterval: interval, repeats: false) { [weak self] _ in
            guard let self else { return }
            self.rollWindow(to: Date())
        }
        timer.tolerance = min(15, max(1, interval * 0.05))
        windowTimer = timer
        RunLoop.main.add(timer, forMode: .common)
    }

    private func startSaveTimer() {
        guard saveTimer == nil else { return }
        let timer = Timer.scheduledTimer(withTimeInterval: 60, repeats: false) { [weak self] _ in
            guard let self else { return }
            self.saveTimer = nil
            self.saveCurrentSample()
        }
        timer.tolerance = 15
        saveTimer = timer
        RunLoop.main.add(timer, forMode: .common)
    }

    private func saveCurrentSample() {
        refreshCurrentSample(end: self.currentSample.end)
        guard hasUnsavedChanges else { return }
        persistence.saveCurrentSample(self.currentSample)
        hasUnsavedChanges = false
        logger.debug("Periodic save: current sample has \(self.currentSample.keyPressCount) keys, \(self.currentSample.mouseClickCount) clicks, \(self.currentSample.scrollTicks) scroll ticks")
    }

    private func activityObserved() {
        let now = Date()
        if now.timeIntervalSince(windowStart) >= windowLength {
            rollWindow(to: now)
        } else {
            if refreshCurrentSample(end: currentSample.end) {
                startSaveTimer()
            }
        }
    }

    private func rollWindow(to now: Date) {
        // Finalize current window with now as the end time.
        refreshCurrentSample(end: now)

        let finalizedSample = self.currentSample
        if Self.sampleHasActivity(finalizedSample) {
            self.history.insert(finalizedSample, at: 0)
            logger.info("Rolled window: finalized sample with \(finalizedSample.keyPressCount) keys, \(finalizedSample.mouseClickCount) clicks, \(finalizedSample.scrollTicks) scroll ticks")
            persistence.saveFinalizedSample(finalizedSample)
        } else {
            logger.debug("Rolled window with no activity; skipping persistence")
        }

        // Reset counters synchronously so the next snapshot reads zero.
        eventTapManager.resetCounters()
        baseKeyPressCount = 0
        baseMouseClickCount = 0
        baseScrollTicks = 0
        baseMouseDistance = 0

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
        saveTimer?.invalidate()
        saveTimer = nil
        persistence.saveCurrentSample(self.currentSample)
        hasUnsavedChanges = false
        let formatter = ISO8601DateFormatter()
        logger.info("Started new window at \(formatter.string(from: now))")
        pushUpdate()
        scheduleWindowTimer(now: now)
    }

    @discardableResult
    private func refreshCurrentSample(end: Date, publish: Bool = true) -> Bool {
        let raw = eventTapManager.snapshot()
        if let rawLastActivity = raw.lastActivityAt {
            lastActivityAt = rawLastActivity
        }
        let refreshed = UsageSample(
            id: currentSample.id,
            start: windowStart,
            end: end,
            keyPressCount: baseKeyPressCount + raw.keyPressCount,
            mouseClickCount: baseMouseClickCount + raw.mouseClickCount,
            scrollTicks: baseScrollTicks + raw.scrollTicks,
            scrollDistance: 0,
            mouseDistance: baseMouseDistance + raw.mouseDistance
        )
        let changed = refreshed.keyPressCount != currentSample.keyPressCount ||
            refreshed.mouseClickCount != currentSample.mouseClickCount ||
            refreshed.scrollTicks != currentSample.scrollTicks ||
            refreshed.mouseDistance != currentSample.mouseDistance ||
            refreshed.end != currentSample.end
        guard changed else { return false }
        currentSample = refreshed
        hasUnsavedChanges = true
        if publish {
            pushUpdate()
        }
        return true
    }

    /// Flushes activity and suspends periodic work before system sleep. Event monitors remain
    /// registered; macOS delivers no input events while asleep and they resume without losing
    /// the current window's raw counters.
    func prepareForSleep() {
        windowTimer?.invalidate()
        windowTimer = nil
        saveTimer?.invalidate()
        saveTimer = nil
        refreshCurrentSample(end: currentSample.end, publish: false)
        persistence.saveCurrentSampleSync(currentSample)
        hasUnsavedChanges = false
    }

    /// Reconciles an expired window after wake and restores energy-tolerant scheduling.
    func resumeAfterWake(now: Date = Date()) {
        if now.timeIntervalSince(windowStart) >= windowLength {
            rollWindow(to: now)
        } else {
            scheduleWindowTimer(now: now)
            pushUpdate()
        }
    }

    private func pushUpdate() {
        let sample = currentSample
        let historyCopy = history
        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            self.onUpdate?(sample, historyCopy)
        }
    }

    private static func sampleHasActivity(_ sample: UsageSample) -> Bool {
        sample.keyPressCount > 0 ||
        sample.mouseClickCount > 0 ||
        sample.scrollTicks > 0 ||
        sample.mouseDistance > 0
    }
}

import Foundation
import os.log

/// Aggregates raw activity counts into fixed 5‑minute UsageSample windows.
final class MetricsAggregator {
    private let eventTapManager = EventTapManager()
    private let persistence = PersistenceController.shared
    private let logger = Logger(subsystem: "com.activitytracker", category: "MetricsAggregator")

    private let windowLength: TimeInterval = 5 * 60
    private var windowStart: Date = Date()

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

    init(now: Date = Date()) {
        // Load persisted history and current sample if valid.
        let (stored, savedCurrent) = persistence.loadSamples()
        // Keep newest first for convenience.
        self.history = stored.sorted { $0.start > $1.start }
        logger.info("Initialized with \(self.history.count) historical samples")

        // If we have a valid saved current sample, use it; otherwise start fresh.
        if let saved = savedCurrent, saved.end > now {
            self.currentSample = saved
            self.windowStart = saved.start
            let formatter = ISO8601DateFormatter()
            logger.info("Restored current sample from \(formatter.string(from: saved.start)) with \(saved.keyPressCount) keys, \(saved.mouseClickCount) clicks")
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
        // Persist any history and current sample accumulated during this run.
        persistence.saveSamples(self.history, currentSample: self.currentSample)
        logger.info("Final save completed: \(self.history.count) samples, current sample has \(self.currentSample.keyPressCount) keys, \(self.currentSample.mouseClickCount) clicks")
    }
    
    /// Reload history from persistence (useful after data deletion).
    func reloadHistory() {
        let (stored, savedCurrent) = persistence.loadSamples()
        self.history = stored.sorted { $0.start > $1.start }
        // Only restore current sample if it's still valid
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
        // Save current sample every 10 seconds
        saveTimer = Timer.scheduledTimer(withTimeInterval: 10.0, repeats: true) { [weak self] _ in
            self?.saveCurrentSample()
        }
        RunLoop.main.add(saveTimer!, forMode: .common)
    }
    
    private func saveCurrentSample() {
        // Refresh current sample before saving
        refreshCurrentSample(end: self.currentSample.end)
        // Persist history and current sample
        persistence.saveSamples(self.history, currentSample: self.currentSample)
        logger.debug("Periodic save: current sample has \(self.currentSample.keyPressCount) keys, \(self.currentSample.mouseClickCount) clicks, \(self.currentSample.scrollTicks) scroll ticks")
    }

    private func tick() {
        let now = Date()
        if now.timeIntervalSince(windowStart) >= windowLength {
            rollWindow(to: now)
        } else {
            // Just refresh the current sample from the raw snapshot.
            refreshCurrentSample(end: currentSample.end)
        }
    }

    private func rollWindow(to now: Date) {
        // Finalize current window with now as the end time.
        refreshCurrentSample(end: now)
        
        let finalizedKeys = self.currentSample.keyPressCount
        let finalizedClicks = self.currentSample.mouseClickCount
        let finalizedScroll = self.currentSample.scrollTicks

        self.history.insert(self.currentSample, at: 0)
        logger.info("Rolled window: finalized sample with \(finalizedKeys) keys, \(finalizedClicks) clicks, \(finalizedScroll) scroll ticks")
        persistence.saveSamples(self.history, currentSample: nil) // No current sample yet for new window

        // Start a new window.
        self.windowStart = now
        let newEnd = now.addingTimeInterval(windowLength)
        eventTapManager.resetCounters()

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
        // Save the new current sample immediately
        persistence.saveSamples(self.history, currentSample: self.currentSample)
        let formatter = ISO8601DateFormatter()
        logger.info("Started new window at \(formatter.string(from: now))")
        pushUpdate()
    }

    private func refreshCurrentSample(end: Date) {
        let raw = eventTapManager.snapshot()
        currentSample = UsageSample(
            id: currentSample.id,
            start: windowStart,
            end: end,
            keyPressCount: raw.keyPressCount,
            mouseClickCount: raw.mouseClickCount,
            scrollTicks: raw.scrollTicks,
            scrollDistance: raw.scrollDistance,
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


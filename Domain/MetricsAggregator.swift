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
        now: Date = Date()
    ) {
        self.eventTapManager = eventTapManager
        self.persistence = persistence
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
        // Persist current sample
        persistence.saveCurrentSample(self.currentSample)
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
        // Persist current sample only (finalized samples are saved separately)
        persistence.saveCurrentSample(self.currentSample)
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

        let finalizedSample = self.currentSample
        self.history.insert(finalizedSample, at: 0)
        logger.info("Rolled window: finalized sample with \(finalizedKeys) keys, \(finalizedClicks) clicks, \(finalizedScroll) scroll ticks")
        
        // Save the finalized sample to its daily file
        persistence.saveFinalizedSample(finalizedSample)

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
        persistence.saveCurrentSample(self.currentSample)
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
            scrollDistance: 0, // deprecated field, kept for Codable backward compat
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


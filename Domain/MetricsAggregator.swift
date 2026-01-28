import Foundation

/// Aggregates raw activity counts into fixed 5‑minute UsageSample windows.
final class MetricsAggregator {
    private let eventTapManager = EventTapManager()
    private let persistence = PersistenceController.shared

    private let windowLength: TimeInterval = 5 * 60
    private var windowStart: Date = Date()

    private(set) var currentSample: UsageSample
    private(set) var history: [UsageSample] = []

    private var timer: Timer?

    /// Called on the main thread whenever currentSample or history changes.
    var onUpdate: ((UsageSample, [UsageSample]) -> Void)?

    /// Called when there is a permission or event tap problem.
    var onPermissionOrTapFailure: ((String) -> Void)? {
        get { eventTapManager.onPermissionOrTapFailure }
        set { eventTapManager.onPermissionOrTapFailure = newValue }
    }

    init(now: Date = Date()) {
        // Load persisted history (finalized 5‑minute windows).
        let stored = persistence.loadSamples()
        // Keep newest first for convenience.
        self.history = stored.sorted { $0.start > $1.start }

        let end = now.addingTimeInterval(windowLength)
        currentSample = UsageSample(
            id: UUID(),
            start: now,
            end: end,
            keyPressCount: 0,
            mouseClickCount: 0,
            scrollTicks: 0,
            scrollDistance: 0,
            mouseDistance: 0
        )
        windowStart = now
    }

    func start() {
        eventTapManager.start()
        startTimer()
        pushUpdate()
    }

    func stop() {
        timer?.invalidate()
        timer = nil
        eventTapManager.stop()
        // Persist any history accumulated during this run.
        persistence.saveSamples(history)
    }

    // MARK: - Timer & Windowing

    private func startTimer() {
        timer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { [weak self] _ in
            self?.tick()
        }
        RunLoop.main.add(timer!, forMode: .common)
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

        history.insert(currentSample, at: 0)
        persistence.saveSamples(history)

        // Start a new window.
        windowStart = now
        let newEnd = now.addingTimeInterval(windowLength)
        eventTapManager.resetCounters()

        currentSample = UsageSample(
            id: UUID(),
            start: now,
            end: newEnd,
            keyPressCount: 0,
            mouseClickCount: 0,
            scrollTicks: 0,
            scrollDistance: 0,
            mouseDistance: 0
        )
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


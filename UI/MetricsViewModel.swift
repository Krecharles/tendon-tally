import Foundation
import Combine

/// View model that manages metrics display state and provides computed metrics for the UI.
@MainActor
final class MetricsViewModel: ObservableObject {
    @Published var currentSample: UsageSample
    @Published var recentHistory: [UsageSample] = []
    @Published var todayTotals: UsageSample
    @Published var permissionIssueMessage: String?
    @Published var selectedTimeFrame: TimeFrame {
        didSet {
            AppPreferences.shared.selectedTimeFrame = selectedTimeFrame
        }
    }
    @Published var timeFrameOffset: Int = 0
    @Published var selectedMetric: MetricType {
        didSet {
            AppPreferences.shared.selectedMetric = selectedMetric
        }
    }
    @Published var kuiConfig: KUIConfig {
        didSet {
            AppPreferences.shared.kuiConfig = kuiConfig
        }
    }
    @Published private(set) var breaksConfig: BreaksConfig
    @Published private(set) var breaksEvaluation: BreaksEvaluation
    @Published private(set) var breakResetWarning: Bool = false
    private let aggregator: MetricsAggregator
    private let breakPillController: BreakPillController
    private var breakTransitionTracker: BreakTransitionTracker
    private var hasReceivedFirstAggregatorUpdate = false
    private let launchDate: Date
    private var hasObservedPostLaunchActivity = false
    private var previousBreakIdleSeconds: TimeInterval = 0
    private var breakResetWarningCountdown: Int = 0
    private var breakRemindersSnoozedUntil: Date?

    init(
        aggregator: MetricsAggregator,
        breakPillController: BreakPillController = BreakPillController()
    ) {
        self.aggregator = aggregator
        self.breakPillController = breakPillController
        self.currentSample = aggregator.currentSample
        self.todayTotals = MetricsViewModel.computeTodayTotals(
            current: aggregator.currentSample,
            history: aggregator.history
        )

        let prefs = AppPreferences.shared
        self.selectedTimeFrame = prefs.selectedTimeFrame
        self.selectedMetric = prefs.selectedMetric
        self.kuiConfig = prefs.kuiConfig
        self.breaksConfig = prefs.breaksConfig.normalized()
        self.breakRemindersSnoozedUntil = prefs.breakRemindersSnoozedUntil
        self.launchDate = Date()

        // Restore transition tracker from persisted state
        var tracker = BreakTransitionTracker()
        tracker.restoreFromStartup(
            persistedLastActivityAt: aggregator.lastActivityAt ?? prefs.breakLastActivityAt,
            persistedLastBreakEndedAt: prefs.breakLastBreakEndedAt,
            config: prefs.breaksConfig.normalized()
        )
        self.breakTransitionTracker = tracker

        self.breaksEvaluation = BreaksEvaluator.evaluate(
            lastBreakEndedAt: tracker.lastBreakEndedAt,
            lastActivityAt: aggregator.lastActivityAt ?? prefs.breakLastActivityAt,
            config: prefs.breaksConfig.normalized()
        )

        self.breakPillController.onSnoozeRequested = { [weak self] option in
            self?.startBreakReminderSnooze(option)
        }

        aggregator.onUpdate = { [weak self] current, history in
            Task { @MainActor in
                guard let self else { return }
                self.hasReceivedFirstAggregatorUpdate = true
                self.currentSample = current
                self.recentHistory = Array(history.prefix(12))
                self.todayTotals = MetricsViewModel.computeTodayTotals(current: current, history: history)
                self.evaluateBreaksAndHandleReminder()
            }
        }

        aggregator.onPermissionOrTapFailure = { [weak self] message in
            Task { @MainActor in
                self?.permissionIssueMessage = message
            }
        }

        aggregator.onPermissionGranted = { [weak self] in
            Task { @MainActor in
                self?.permissionIssueMessage = nil
            }
        }

        evaluateBreaksAndHandleReminder()
    }

    private static func computeTodayTotals(current: UsageSample, history: [UsageSample]) -> UsageSample {
        let calendar = Calendar.current
        let now = Date()
        let startOfDay = calendar.startOfDay(for: now)

        var totalKeys = 0
        var totalClicks = 0
        var totalScrollTicks = 0
        var totalMouseDistance = 0.0

        for sample in history where sample.start >= startOfDay {
            totalKeys += sample.keyPressCount
            totalClicks += sample.mouseClickCount
            totalScrollTicks += sample.scrollTicks
            totalMouseDistance += sample.mouseDistance
        }

        if current.start >= startOfDay {
            totalKeys += current.keyPressCount
            totalClicks += current.mouseClickCount
            totalScrollTicks += current.scrollTicks
            totalMouseDistance += current.mouseDistance
        }

        return UsageSample(
            id: UUID(),
            start: startOfDay,
            end: now,
            keyPressCount: totalKeys,
            mouseClickCount: totalClicks,
            scrollTicks: totalScrollTicks,
            scrollDistance: 0,
            mouseDistance: totalMouseDistance
        )
    }

    func todayMetrics() -> AggregatedMetrics {
        let (startDate, endDate) = TimeFrame.today.dateRange(offset: 0)
        let now = Date()
        let allSamples = aggregator.history + [aggregator.currentSample]

        var totalKeys = 0
        var totalClicks = 0
        var totalScrollTicks = 0
        var totalMouseDistance = 0.0

        for sample in allSamples {
            let effectiveEnd = max(endDate, now)
            if sample.end >= startDate && sample.start <= effectiveEnd {
                totalKeys += sample.keyPressCount
                totalClicks += sample.mouseClickCount
                totalScrollTicks += sample.scrollTicks
                totalMouseDistance += sample.mouseDistance
            }
        }

        return AggregatedMetrics(
            keyPressCount: totalKeys,
            mouseClickCount: totalClicks,
            scrollTicks: totalScrollTicks,
            mouseDistance: totalMouseDistance
        )
    }

    func aggregatedMetrics(for timeFrame: TimeFrame, offset: Int) -> AggregatedMetrics {
        let (startDate, endDate) = timeFrame.dateRange(offset: offset)
        let now = Date()

        let allSamples: [UsageSample]
        if offset == 0 {
            allSamples = aggregator.history + [aggregator.currentSample]
        } else {
            allSamples = aggregator.history
        }

        var totalKeys = 0
        var totalClicks = 0
        var totalScrollTicks = 0
        var totalMouseDistance = 0.0

        for sample in allSamples {
            let sampleOverlaps: Bool
            if offset == 0 {
                let effectiveEnd = max(endDate, now)
                sampleOverlaps = sample.end >= startDate && sample.start <= effectiveEnd
            } else {
                sampleOverlaps = sample.start >= startDate && sample.end <= endDate
            }

            if sampleOverlaps {
                totalKeys += sample.keyPressCount
                totalClicks += sample.mouseClickCount
                totalScrollTicks += sample.scrollTicks
                totalMouseDistance += sample.mouseDistance
            }
        }

        return AggregatedMetrics(
            keyPressCount: totalKeys,
            mouseClickCount: totalClicks,
            scrollTicks: totalScrollTicks,
            mouseDistance: totalMouseDistance
        )
    }

    func reloadHistory() {
        aggregator.reloadHistory()
        evaluateBreaksAndHandleReminder()
    }

    func updateBreaksConfig(_ config: BreaksConfig) {
        let normalized = config.normalized()
        guard normalized != breaksConfig else { return }
        breaksConfig = normalized
        AppPreferences.shared.breaksConfig = normalized
        evaluateBreaksAndHandleReminder()
    }

    func startBreakReminderSnooze(_ option: BreakReminderSnoozeOption) {
        let snoozedUntil = option.snoozedUntil()
        breakRemindersSnoozedUntil = snoozedUntil
        AppPreferences.shared.breakRemindersSnoozedUntil = snoozedUntil
        breakPillController.suppressForSnooze()
    }

    func cancelBreakReminderSnooze() {
        breakRemindersSnoozedUntil = nil
        AppPreferences.shared.breakRemindersSnoozedUntil = nil
        evaluateBreaksAndHandleReminder()
    }

    func comparisonStats(for timeFrame: TimeFrame, offset: Int) -> (currentTotal: Double, percentageChange: Double?, hasPriorData: Bool) {
        let current = aggregatedMetrics(for: timeFrame, offset: offset)
        let prior = aggregatedMetrics(for: timeFrame, offset: offset - 1)

        let currentValue = metricValue(from: current, for: selectedMetric)
        let priorValue = metricValue(from: prior, for: selectedMetric)

        let hasPriorData = priorValue > 0
        let percentageChange: Double?
        if hasPriorData {
            percentageChange = ((currentValue - priorValue) / priorValue) * 100.0
        } else {
            percentageChange = nil
        }

        return (currentTotal: currentValue, percentageChange: percentageChange, hasPriorData: hasPriorData)
    }

    private func metricValue(from metrics: AggregatedMetrics, for metric: MetricType) -> Double {
        switch metric {
        case .keys:
            return Double(metrics.keyPressCount)
        case .clicks:
            return Double(metrics.mouseClickCount)
        case .scroll:
            return Double(metrics.scrollTicks) / 100.0
        case .mouseDistance:
            return metrics.mouseDistance / 1000.0
        case .aggregate:
            return kuiConfig.apply(to: metrics)
        }
    }

    func timeSeriesData(for timeFrame: TimeFrame, offset: Int) -> [TimeSeriesDataPoint] {
        return TimeSeriesCalculator.calculateTimeSeries(
            samples: aggregator.history,
            currentSample: offset == 0 ? aggregator.currentSample : nil,
            timeFrame: timeFrame,
            offset: offset
        )
    }

    var breakCardPhase: BreakPhase {
        breaksEvaluation.phase
    }

    var breakRemindersAreSnoozed: Bool {
        activeBreakReminderSnoozedUntil() != nil
    }

    var breakReminderSnoozeStatusText: String? {
        guard let snoozedUntil = activeBreakReminderSnoozedUntil() else { return nil }
        return "Reminders snoozed until \(formattedClockTime(snoozedUntil))."
    }

    var breakLastQualifyingBreakText: String {
        if let lastBreak = breaksEvaluation.lastBreakEndedAt {
            return "Last qualifying break ended at \(formattedClockTime(lastBreak))."
        }
        return "No completed break has been recorded yet."
    }

    var breakCardPrimaryLabel: String {
        switch breaksEvaluation.phase {
        case .work:
            return "Next break in"
        case .due:
            return "Break remaining"
        case .onBreak:
            return "Break complete"
        }
    }

    var breakCardPrimaryValue: String {
        switch breaksEvaluation.phase {
        case .work:
            return breakTimeUntilDueDisplay
        case .due:
            let remaining = max(0, breaksEvaluation.requiredBreakSeconds - breaksEvaluation.currentIdleSeconds)
            return formattedDurationEmphasized(remaining)
        case .onBreak:
            return formattedDurationEmphasized(breaksEvaluation.requiredBreakSeconds)
        }
    }

    var breakCardProgressValue: Double {
        switch breaksEvaluation.phase {
        case .work:
            guard let untilDue = breakTimeUntilDueSeconds else { return 0 }
            return clampedProgress(untilDue / breaksEvaluation.workWindowSeconds)
        case .due:
            return clampedProgress(breaksEvaluation.currentIdleSeconds / breaksEvaluation.requiredBreakSeconds)
        case .onBreak:
            return 1.0
        }
    }

    var breakCardProgressText: String {
        switch breaksEvaluation.phase {
        case .work:
            guard let untilDue = breakTimeUntilDueSeconds else { return "" }
            let elapsed = max(0, breaksEvaluation.workWindowSeconds - untilDue)
            return "\(formattedDuration(elapsed)) of \(formattedDuration(breaksEvaluation.workWindowSeconds)) work cycle used"
        case .due:
            return breakDueProgressText
        case .onBreak:
            return "Well done! The timer resets when you return."
        }
    }

    var breakDueProgressText: String {
        let elapsed = min(breaksEvaluation.requiredBreakSeconds, breaksEvaluation.currentIdleSeconds)
        let base = "\(formattedDuration(elapsed)) of \(formattedDuration(breaksEvaluation.requiredBreakSeconds)) break completed"
        if breakResetWarning {
            return base + " — any input resets the timer"
        }
        return base
    }

    var breakTimeUntilDueDisplay: String {
        guard let seconds = breakTimeUntilDueSeconds else { return "--" }
        return formattedDurationEmphasized(seconds)
    }

    var breakTimeUntilDueSeconds: TimeInterval? {
        guard breaksEvaluation.phase == .work else { return nil }
        guard let dueDate = breakNextDueDate else { return nil }
        return max(0, dueDate.timeIntervalSinceNow)
    }

    private func evaluateBreaksAndHandleReminder(now: Date = Date()) {
        breakTransitionTracker.update(
            lastActivityAt: aggregator.lastActivityAt,
            config: breaksConfig,
            now: now
        )

        let evaluation = BreaksEvaluator.evaluate(
            lastBreakEndedAt: breakTransitionTracker.lastBreakEndedAt,
            lastActivityAt: aggregator.lastActivityAt,
            config: breaksConfig,
            now: now
        )
        breaksEvaluation = evaluation

        // Track idle drops to show reset warning only when user provides input
        if evaluation.phase == .due {
            if evaluation.currentIdleSeconds < previousBreakIdleSeconds - 1 {
                breakResetWarningCountdown = 5
            }
            previousBreakIdleSeconds = evaluation.currentIdleSeconds
            breakResetWarning = breakResetWarningCountdown > 0
            if breakResetWarningCountdown > 0 { breakResetWarningCountdown -= 1 }
        } else {
            previousBreakIdleSeconds = 0
            breakResetWarningCountdown = 0
            breakResetWarning = false
        }

        AppPreferences.shared.breakLastActivityAt = aggregator.lastActivityAt
        AppPreferences.shared.breakLastBreakEndedAt = breakTransitionTracker.lastBreakEndedAt

        // Start pill updates only after actual post-launch input has been observed.
        // On startup, restored activity timestamps can briefly produce stale
        // .onBreak/.due transitions and startup sounds.
        if let lastActivityAt = aggregator.lastActivityAt, lastActivityAt >= launchDate {
            hasObservedPostLaunchActivity = true
        }

        if hasReceivedFirstAggregatorUpdate && hasObservedPostLaunchActivity {
            if isBreakReminderSnoozed(now: now) {
                breakPillController.suppressForSnooze()
            } else {
                breakPillController.update(evaluation: evaluation, config: breaksConfig)
            }
        }
    }

    private func isBreakReminderSnoozed(now: Date) -> Bool {
        activeBreakReminderSnoozedUntil(now: now) != nil
    }

    private func activeBreakReminderSnoozedUntil(now: Date = Date()) -> Date? {
        guard let snoozedUntil = breakRemindersSnoozedUntil else { return nil }
        guard now < snoozedUntil else {
            breakRemindersSnoozedUntil = nil
            AppPreferences.shared.breakRemindersSnoozedUntil = nil
            return nil
        }
        return snoozedUntil
    }

    private func formattedClockTime(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.timeStyle = .short
        formatter.dateStyle = .none
        return formatter.string(from: date)
    }

    private func formattedDuration(_ seconds: TimeInterval) -> String {
        let total = max(0, Int(seconds.rounded()))
        let minutes = total / 60
        let remainingSeconds = total % 60
        if minutes == 0 {
            return "\(remainingSeconds)s"
        }
        return "\(minutes)m \(remainingSeconds)s"
    }

    private func clampedProgress(_ value: TimeInterval) -> Double {
        min(1.0, max(0.0, value))
    }

    private var breakNextDueDate: Date? {
        guard let lastBreak = breaksEvaluation.lastBreakEndedAt else { return nil }
        return lastBreak.addingTimeInterval(breaksEvaluation.workWindowSeconds)
    }

    private func formattedDurationEmphasized(_ seconds: TimeInterval) -> String {
        let total = max(0, Int(seconds.rounded()))
        let hours = total / 3600
        let minutes = (total % 3600) / 60
        let remainingSeconds = total % 60

        if hours > 0 {
            return String(format: "%dh %02dm", hours, minutes)
        }
        if minutes > 0 {
            return String(format: "%dm %02ds", minutes, remainingSeconds)
        }
        return "\(remainingSeconds)s"
    }
}

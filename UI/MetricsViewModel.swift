import Foundation
import Combine
import AppKit

/// View model that manages metrics display state and provides computed metrics for the UI.
@MainActor
final class MetricsViewModel: ObservableObject {
    private struct DailyExportSnapshot {
        let date: Date
        let metrics: AggregatedMetrics
        let total: Double
    }

    private struct TimeSeriesCacheKey: Hashable {
        let selection: HistorySelection
        let granularity: AggregationGranularity
    }

    private struct IntervalSeriesCacheKey: Hashable {
        let start: Date
        let end: Date
        let granularity: AggregationGranularity
        let includeCurrentSample: Bool
    }

    private struct AggregatedMetricsCacheKey: Hashable {
        let start: Date
        let end: Date
        let includeCurrentSample: Bool
    }

    @Published var currentSample: UsageSample
    @Published var recentHistory: [UsageSample] = []
    @Published var todayTotals: UsageSample
    @Published var permissionIssueMessage: String?
    @Published private(set) var historySelection: HistorySelection
    @Published var selectedMetric: MetricType {
        didSet {
            AppPreferences.shared.selectedMetric = selectedMetric
        }
    }
    @Published var totalConfig: TotalConfig {
        didSet {
            AppPreferences.shared.totalConfig = totalConfig
        }
    }
    @Published var advancedTotalCalculationEnabled: Bool {
        didSet {
            AppPreferences.shared.advancedTotalCalculationEnabled = advancedTotalCalculationEnabled
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
    private var timeSeriesCache: [TimeSeriesCacheKey: [TimeSeriesDataPoint]] = [:]
    private var intervalSeriesCache: [IntervalSeriesCacheKey: [TimeSeriesDataPoint]] = [:]
    private var aggregatedMetricsCache: [AggregatedMetricsCacheKey: AggregatedMetrics] = [:]

    init(
        aggregator: MetricsAggregator,
        breakPillController: BreakPillController? = nil
    ) {
        self.aggregator = aggregator
        self.breakPillController = breakPillController ?? BreakPillController()
        self.currentSample = aggregator.currentSample
        self.todayTotals = MetricsViewModel.computeTodayTotals(
            current: aggregator.currentSample,
            history: aggregator.history
        )

        let prefs = AppPreferences.shared
        self.historySelection = prefs.historySelection.normalized()
        self.selectedMetric = prefs.selectedMetric
        self.totalConfig = prefs.totalConfig
        self.advancedTotalCalculationEnabled = prefs.advancedTotalCalculationEnabled
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
                self.invalidateHistoryDerivedCaches()
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

        for sample in history where sample.end >= startOfDay && sample.start <= now {
            totalKeys += sample.keyPressCount
            totalClicks += sample.mouseClickCount
            totalScrollTicks += sample.scrollTicks
            totalMouseDistance += sample.mouseDistance
        }

        if current.end >= startOfDay && current.start <= now {
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

    var resolvedHistoryAggregation: AggregationGranularity {
        HistoryAggregationPolicy.resolvedGranularity(for: historySelection, now: Date())
    }

    var allowedHistoryAggregations: [AggregationGranularity] {
        HistoryAggregationPolicy.allowedGranularities(for: historySelection, now: Date())
    }

    var historyUsesAutoAggregation: Bool {
        historySelection.manualAggregation == nil
    }

    var historyDateInterval: DateInterval {
        historySelection.normalized().dateInterval(now: Date())
    }

    var canShiftHistoryForward: Bool {
        historySelection.canNavigateForward(now: Date())
    }

    func selectHistoryPreset(_ preset: HistoryPreset) {
        var next = historySelection
        next.mode = .preset
        next.preset = preset
        next.offset = 0
        applyHistorySelection(next)
    }

    func activateCustomRange() {
        var next = historySelection
        next.mode = .custom
        next.offset = 0
        applyHistorySelection(next)
    }

    func updateCustomRange(start: Date, end: Date) {
        var next = historySelection
        next.mode = .custom
        next.customStartDate = start
        next.customEndDate = end
        next.offset = 0
        applyHistorySelection(next)
    }

    func setHistoryAggregation(_ manualAggregation: AggregationGranularity?) {
        var next = historySelection
        next.manualAggregation = manualAggregation
        applyHistorySelection(next)
    }

    func shiftHistoryBackward() {
        var next = historySelection
        next.offset -= 1
        applyHistorySelection(next)
    }

    func shiftHistoryForward() {
        guard canShiftHistoryForward else { return }
        var next = historySelection
        next.offset += 1
        applyHistorySelection(next)
    }

    func resetHistoryToToday() {
        applyHistorySelection(HistorySelection.default())
    }

    func aggregatedMetrics(for selection: HistorySelection) -> AggregatedMetrics {
        let now = Date()
        let normalized = selection.normalized(now: now)
        let interval = normalized.dateInterval(now: now)
        let includeCurrent = now >= interval.start && now <= interval.end
        return aggregatedMetrics(for: interval, includeCurrentSample: includeCurrent, now: now)
    }

    func aggregatedMetrics(for timeFrame: TimeFrame, offset: Int) -> AggregatedMetrics {
        let now = Date()
        let range = timeFrame.dateRange(offset: offset)
        let includeCurrent = offset == 0
        return aggregatedMetrics(
            for: DateInterval(start: range.start, end: range.end),
            includeCurrentSample: includeCurrent,
            now: now
        )
    }

    func reloadHistory() {
        invalidateHistoryDerivedCaches()
        aggregator.reloadHistory()
        evaluateBreaksAndHandleReminder()
    }

    func updateBreaksConfig(_ config: BreaksConfig) {
        let normalized = config.normalized()
        guard normalized != breaksConfig else { return }
        let wasRemindersEnabled = breaksConfig.remindersEnabled
        breaksConfig = normalized
        AppPreferences.shared.breaksConfig = normalized
        if normalized.remindersEnabled && !wasRemindersEnabled {
            breakTransitionTracker.seedFirstWorkCycle()
            AppPreferences.shared.breakLastBreakEndedAt = breakTransitionTracker.lastBreakEndedAt
        }
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

    var effectiveTotalConfig: TotalConfig {
        advancedTotalCalculationEnabled ? totalConfig : .default
    }

    func totalValue(for metrics: AggregatedMetrics) -> Double {
        effectiveTotalConfig.apply(to: metrics)
    }

    func dailyMetricsExportText(for day: DailyExportDay) -> String {
        let snapshot = dailyExportSnapshot(for: day)
        let dateString = formatDate(snapshot.date)

        struct Payload: Codable {
            let date: String
            let keysPressed: Int
            let mouseClicks: Int
            let scrollSteps: Double
            let mouseDistanceKpx: Double
            let total: Double
        }

        let payload = Payload(
            date: dateString,
            keysPressed: snapshot.metrics.keyPressCount,
            mouseClicks: snapshot.metrics.mouseClickCount,
            scrollSteps: Double(snapshot.metrics.scrollTicks) / 100.0,
            mouseDistanceKpx: snapshot.metrics.mouseDistance / 1_000.0,
            total: snapshot.total
        )

        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        guard let data = try? encoder.encode(payload),
              let json = String(data: data, encoding: .utf8) else {
            return "{}"
        }
        return json
    }

    @discardableResult
    func copyDailyMetricsToClipboard(for day: DailyExportDay) -> String? {
        let output = dailyMetricsExportText(for: day)
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        guard pasteboard.setString(output, forType: .string) else {
            return nil
        }
        return "Copied \(day.rawValue)"
    }

    func timeSeriesData(for selection: HistorySelection) -> [TimeSeriesDataPoint] {
        let now = Date()
        let normalized = selection.normalized(now: now)
        let granularity = HistoryAggregationPolicy.resolvedGranularity(for: normalized, now: now)
        let cacheKey = TimeSeriesCacheKey(selection: normalized, granularity: granularity)
        if let cached = timeSeriesCache[cacheKey] {
            return cached
        }

        let interval = normalized.dateInterval(now: now)
        let includeCurrent = now >= interval.start && now <= interval.end
        let result = timeSeriesData(
            for: interval,
            granularity: granularity,
            includeCurrentSample: includeCurrent,
            now: now
        )
        timeSeriesCache[cacheKey] = result
        return result
    }

    /// Legacy adapter for callers still using TimeFrame/offset.
    func timeSeriesData(for timeFrame: TimeFrame, offset: Int) -> [TimeSeriesDataPoint] {
        var selection = HistorySelection.default()
        selection.mode = .preset
        selection.offset = offset
        switch timeFrame {
        case .today:
            selection.preset = .day
        case .lastWeek:
            selection.preset = .week
        case .lastMonth:
            selection.preset = .month
        case .lastYear:
            selection.preset = .year
        }
        return timeSeriesData(for: selection)
    }

    func overlaySourceDataPoints(for selection: HistorySelection) -> [TimeSeriesDataPoint] {
        let now = Date()
        let normalized = selection.normalized(now: now)
        let baseGranularity = HistoryAggregationPolicy.resolvedGranularity(for: normalized, now: now)
        guard let overlayGranularity = baseGranularity.nextCoarser else {
            return []
        }

        let visible = timeSeriesData(for: normalized)
        guard let firstVisible = visible.first?.time,
              let lastVisible = visible.last?.time else {
            return []
        }

        let calendar = Calendar.current
        let overlayStart = overlayGranularity.alignedStart(for: firstVisible, calendar: calendar)
        let trailingOverlayStart = overlayGranularity.alignedStart(for: lastVisible, calendar: calendar)
        let overlayEndExclusive = overlayGranularity.addingOneStep(to: trailingOverlayStart, calendar: calendar)
        let interval = DateInterval(start: overlayStart, end: overlayEndExclusive)
        let includeCurrent = now >= interval.start && now <= interval.end

        return timeSeriesData(
            for: interval,
            granularity: baseGranularity,
            includeCurrentSample: includeCurrent,
            now: now
        )
    }

    func hasAnyHistoryData() -> Bool {
        let allData = timeSeriesData(for: historySelection)
        return allData.contains {
            $0.keyPressCount > 0 ||
            $0.mouseClickCount > 0 ||
            $0.scrollTicks > 0 ||
            $0.mouseDistance > 0
        }
    }

    /// Legacy adapter for callers still using TimeFrame.
    func hasAnyHistoryData(for timeFrame: TimeFrame) -> Bool {
        var selection = HistorySelection.default()
        selection.mode = .preset
        selection.offset = 0
        switch timeFrame {
        case .today:
            selection.preset = .day
        case .lastWeek:
            selection.preset = .week
        case .lastMonth:
            selection.preset = .month
        case .lastYear:
            selection.preset = .year
        }
        let allData = timeSeriesData(for: selection)
        return allData.contains {
            $0.keyPressCount > 0 ||
            $0.mouseClickCount > 0 ||
            $0.scrollTicks > 0 ||
            $0.mouseDistance > 0
        }
    }

    private func invalidateHistoryDerivedCaches() {
        timeSeriesCache.removeAll(keepingCapacity: true)
        intervalSeriesCache.removeAll(keepingCapacity: true)
        aggregatedMetricsCache.removeAll(keepingCapacity: true)
    }

    private func applyHistorySelection(_ selection: HistorySelection) {
        let normalized = selection.normalized()
        guard normalized != historySelection else { return }
        historySelection = normalized
        AppPreferences.shared.historySelection = normalized
    }

    private func timeSeriesData(
        for interval: DateInterval,
        granularity: AggregationGranularity,
        includeCurrentSample: Bool,
        now: Date
    ) -> [TimeSeriesDataPoint] {
        let key = IntervalSeriesCacheKey(
            start: interval.start,
            end: interval.end,
            granularity: granularity,
            includeCurrentSample: includeCurrentSample
        )
        if let cached = intervalSeriesCache[key] {
            return cached
        }

        let result = TimeSeriesCalculator.calculateTimeSeries(
            samples: aggregator.history,
            currentSample: includeCurrentSample ? aggregator.currentSample : nil,
            dateInterval: interval,
            granularity: granularity,
            includeCurrentSample: includeCurrentSample,
            now: now
        )
        intervalSeriesCache[key] = result
        return result
    }

    private func aggregatedMetrics(
        for interval: DateInterval,
        includeCurrentSample: Bool,
        now: Date
    ) -> AggregatedMetrics {
        let cacheKey = AggregatedMetricsCacheKey(
            start: interval.start,
            end: interval.end,
            includeCurrentSample: includeCurrentSample
        )
        if let cached = aggregatedMetricsCache[cacheKey] {
            return cached
        }

        let allSamples: [UsageSample]
        if includeCurrentSample {
            allSamples = aggregator.history + [aggregator.currentSample]
        } else {
            allSamples = aggregator.history
        }

        var totalKeys = 0
        var totalClicks = 0
        var totalScrollTicks = 0
        var totalMouseDistance = 0.0
        let effectiveEnd = includeCurrentSample ? max(interval.end, now) : interval.end

        for sample in allSamples where sample.end >= interval.start && sample.start <= effectiveEnd {
            totalKeys += sample.keyPressCount
            totalClicks += sample.mouseClickCount
            totalScrollTicks += sample.scrollTicks
            totalMouseDistance += sample.mouseDistance
        }

        let result = AggregatedMetrics(
            keyPressCount: totalKeys,
            mouseClickCount: totalClicks,
            scrollTicks: totalScrollTicks,
            mouseDistance: totalMouseDistance
        )
        aggregatedMetricsCache[cacheKey] = result
        return result
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

    private func dailyExportSnapshot(for day: DailyExportDay) -> DailyExportSnapshot {
        let metrics = aggregatedMetrics(for: .today, offset: day.offset)
        let total = totalValue(for: metrics)
        let (startDate, _) = TimeFrame.today.dateRange(offset: day.offset)
        return DailyExportSnapshot(date: startDate, metrics: metrics, total: total)
    }

    private func formatDate(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone.current
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter.string(from: date)
    }

}

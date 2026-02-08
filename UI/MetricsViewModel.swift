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
    @Published var activeMetricFilters: Set<MetricType> {
        didSet {
            AppPreferences.shared.activeMetricFilters = activeMetricFilters
        }
    }
    @Published var kuiConfig: KUIConfig {
        didSet {
            AppPreferences.shared.kuiConfig = kuiConfig
        }
    }

    private let aggregator: MetricsAggregator

    init(aggregator: MetricsAggregator) {
        self.aggregator = aggregator
        self.currentSample = aggregator.currentSample
        self.todayTotals = MetricsViewModel.computeTodayTotals(
            current: aggregator.currentSample,
            history: aggregator.history
        )

        let prefs = AppPreferences.shared
        self.selectedTimeFrame = prefs.selectedTimeFrame
        self.activeMetricFilters = prefs.activeMetricFilters
        self.kuiConfig = prefs.kuiConfig

        aggregator.onUpdate = { [weak self] current, history in
            Task { @MainActor in
                guard let self else { return }
                self.currentSample = current
                self.recentHistory = Array(history.prefix(12))
                self.todayTotals = MetricsViewModel.computeTodayTotals(current: current, history: history)
            }
        }

        aggregator.onPermissionOrTapFailure = { [weak self] message in
            Task { @MainActor in
                self?.permissionIssueMessage = message
            }
        }
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

    func aggregatedMetrics(for timeFrame: TimeFrame, offset: Int, filters: Set<MetricType>) -> AggregatedMetrics {
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
    }

    func timeSeriesData(for timeFrame: TimeFrame, offset: Int, filters: Set<MetricType>) -> [TimeSeriesDataPoint] {
        return TimeSeriesCalculator.calculateTimeSeries(
            samples: aggregator.history,
            currentSample: offset == 0 ? aggregator.currentSample : nil,
            timeFrame: timeFrame,
            offset: offset
        )
    }
}

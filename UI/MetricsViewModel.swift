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
            UserDefaults.standard.set(selectedTimeFrame.rawValue, forKey: "selectedTimeFrame")
        }
    }
    @Published var timeFrameOffset: Int = 0 // 0 = current period, -1 = previous, -2 = before that, etc. (NOT persisted - always starts at 0)
    @Published var activeMetricFilters: Set<MetricType> {
        didSet {
            let filterStrings = activeMetricFilters.map { $0.rawValue }
            UserDefaults.standard.set(filterStrings, forKey: "activeMetricFilters")
        }
    }

    private let aggregator: MetricsAggregator
    private let userDefaults = UserDefaults.standard

    init(aggregator: MetricsAggregator) {
        self.aggregator = aggregator
        self.currentSample = aggregator.currentSample
        self.todayTotals = MetricsViewModel.computeTodayTotals(current: aggregator.currentSample,
                                                               history: aggregator.history)
        
        // Load persisted preferences
        if let savedTimeFrameString = userDefaults.string(forKey: "selectedTimeFrame"),
           let savedTimeFrame = TimeFrame(rawValue: savedTimeFrameString) {
            self.selectedTimeFrame = savedTimeFrame
        } else {
            self.selectedTimeFrame = .today
        }
        
        if let savedFilterStrings = userDefaults.array(forKey: "activeMetricFilters") as? [String] {
            let savedFilters = Set(savedFilterStrings.compactMap { MetricType(rawValue: $0) })
            if !savedFilters.isEmpty {
                self.activeMetricFilters = savedFilters
            } else {
                self.activeMetricFilters = Set(MetricType.individualMetrics + [.aggregate])
            }
        } else {
            self.activeMetricFilters = Set(MetricType.individualMetrics + [.aggregate])
        }

        aggregator.onUpdate = { [weak self] current, history in
            Task { @MainActor in
                guard let self else { return }
                self.currentSample = current
                self.recentHistory = Array(history.prefix(12)) // up to 1 hour of 5‑min windows
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

        // Include finalized windows from today.
        for sample in history where sample.start >= startOfDay {
            totalKeys += sample.keyPressCount
            totalClicks += sample.mouseClickCount
            totalScrollTicks += sample.scrollTicks
            totalMouseDistance += sample.mouseDistance
        }

        // Include the current in‑progress window if it's from today.
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
            scrollDistance: 0, // not used anymore
            mouseDistance: totalMouseDistance
        )
    }
    
    func todayMetrics() -> AggregatedMetrics {
        // Always return today's metrics, independent of selected time frame
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
        
        // For past periods, exclude current sample if it's not in that period
        // For current period, include current sample
        let allSamples: [UsageSample]
        if offset == 0 {
            allSamples = aggregator.history + [aggregator.currentSample]
        } else {
            // For past periods, only include finalized samples
            allSamples = aggregator.history
        }
        
        // Always calculate all metrics regardless of filters (for totals display)
        var totalKeys = 0
        var totalClicks = 0
        var totalScrollTicks = 0
        var totalMouseDistance = 0.0
        
        for sample in allSamples {
            // For past periods (offset < 0), strictly enforce the endDate boundary
            // For current period (offset 0), include samples that overlap
            let sampleOverlaps: Bool
            if offset == 0 {
                // Current period: include if sample overlaps with period
                let effectiveEnd = max(endDate, now)
                sampleOverlaps = sample.end >= startDate && sample.start <= effectiveEnd
            } else {
                // Past period: sample must be within the period boundaries
                sampleOverlaps = sample.start >= startDate && sample.end <= endDate
            }
            
            if sampleOverlaps {
                // Always sum all metrics for totals
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
    
    /// Calculate time series data points for the chart.
    /// - Parameters:
    ///   - timeFrame: The time frame to aggregate
    ///   - offset: Time frame offset (0 = current, -1 = previous, etc.)
    ///   - filters: Active metric filters (not used in calculation, but kept for API consistency)
    /// - Returns: Array of time series data points sorted by time
    func timeSeriesData(for timeFrame: TimeFrame, offset: Int, filters: Set<MetricType>) -> [TimeSeriesDataPoint] {
        return TimeSeriesCalculator.calculateTimeSeries(
            samples: aggregator.history,
            currentSample: offset == 0 ? aggregator.currentSample : nil,
            timeFrame: timeFrame,
            offset: offset
        )
    }
}


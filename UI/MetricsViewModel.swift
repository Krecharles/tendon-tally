import Foundation
import Combine

@MainActor
final class MetricsViewModel: ObservableObject {
    @Published var currentSample: UsageSample
    @Published var recentHistory: [UsageSample] = []
    @Published var todayTotals: UsageSample
    @Published var permissionIssueMessage: String?

    private let aggregator: MetricsAggregator

    init(aggregator: MetricsAggregator) {
        self.aggregator = aggregator
        self.currentSample = aggregator.currentSample
        self.todayTotals = MetricsViewModel.computeTodayTotals(current: aggregator.currentSample,
                                                               history: aggregator.history)

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
}


import Foundation
import Combine

@MainActor
final class MetricsViewModel: ObservableObject {
    @Published var currentSample: UsageSample
    @Published var recentHistory: [UsageSample] = []
    @Published var permissionIssueMessage: String?

    private let aggregator: MetricsAggregator

    init(aggregator: MetricsAggregator) {
        self.aggregator = aggregator
        self.currentSample = aggregator.currentSample

        aggregator.onUpdate = { [weak self] current, history in
            Task { @MainActor in
                self?.currentSample = current
                self?.recentHistory = Array(history.prefix(12)) // up to 1 hour of 5‑min windows
            }
        }

        aggregator.onPermissionOrTapFailure = { [weak self] message in
            Task { @MainActor in
                self?.permissionIssueMessage = message
            }
        }
    }
}


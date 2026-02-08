import Foundation

protocol MetricsAggregating {
    var currentSample: UsageSample { get }
    var history: [UsageSample] { get }
    var onUpdate: ((UsageSample, [UsageSample]) -> Void)? { get set }
    var onPermissionOrTapFailure: ((String) -> Void)? { get set }
    func start()
    func stop()
    func reloadHistory()
}

extension MetricsAggregator: MetricsAggregating {}

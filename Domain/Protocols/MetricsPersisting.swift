import Foundation

protocol MetricsPersisting {
    func loadSamples() -> (samples: [UsageSample], currentSample: UsageSample?)
    func saveFinalizedSample(_ sample: UsageSample)
    func saveCurrentSample(_ currentSample: UsageSample)
}

extension PersistenceController: MetricsPersisting {}

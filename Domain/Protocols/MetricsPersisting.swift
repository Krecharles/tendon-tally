import Foundation

protocol MetricsPersisting {
    func loadSamples() -> (samples: [UsageSample], currentSample: UsageSample?)
    func saveFinalizedSample(_ sample: UsageSample)
    func saveFinalizedSampleSync(_ sample: UsageSample)
    func saveCurrentSample(_ currentSample: UsageSample)
    func saveCurrentSampleSync(_ currentSample: UsageSample)
    func deleteCurrentSample()
}

extension PersistenceController: MetricsPersisting {}

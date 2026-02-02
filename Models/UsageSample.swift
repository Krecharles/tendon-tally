import Foundation

/// Represents aggregated usage metrics for a fixed time window (e.g. 5 minutes).
struct UsageSample: Identifiable, Codable {
    let id: UUID
    let start: Date
    let end: Date
    let keyPressCount: Int
    let mouseClickCount: Int
    let scrollTicks: Int
    let scrollDistance: Double
    let mouseDistance: Double
}

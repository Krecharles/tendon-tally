import Foundation

/// Simple value-type snapshot of the raw counts coming from the event tap.
struct RawActivitySnapshot {
    var keyPressCount: Int = 0
    var mouseClickCount: Int = 0
    var scrollTicks: Int = 0
    var scrollDistance: Double = 0
    var mouseDistance: Double = 0
}

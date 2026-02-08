import SwiftUI

extension MetricType {
    var color: Color {
        switch self {
        case .keys: return .blue
        case .clicks: return .red
        case .scroll: return .green
        case .mouseDistance: return .orange
        case .aggregate: return .purple
        }
    }
}

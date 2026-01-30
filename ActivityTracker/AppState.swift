import Foundation
import Combine

@MainActor
final class AppState: ObservableObject {
    static let shared = AppState()
    
    @Published var viewModel: MetricsViewModel?
    
    private init() {}
    
    func setViewModel(_ viewModel: MetricsViewModel) {
        self.viewModel = viewModel
    }
}

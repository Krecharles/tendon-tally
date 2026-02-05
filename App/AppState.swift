import Foundation
import Combine

/// Shared application state that holds the main view model.
///
/// This singleton provides a way for the AppDelegate to share the MetricsViewModel
/// with the main window's WindowGroup.
@MainActor
final class AppState: ObservableObject {
    static let shared = AppState()
    
    @Published var viewModel: MetricsViewModel?
    
    /// Notification name for opening the dashboard window
    static let openDashboardNotification = Notification.Name("openDashboard")
    
    private init() {}
    
    func setViewModel(_ viewModel: MetricsViewModel) {
        self.viewModel = viewModel
    }
}

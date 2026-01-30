import SwiftUI
import AppKit

@main
struct ActivityTrackerApp: App {
    /// Shared app delegate to manage NSStatusItem and AppKit integration.
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate
    @StateObject private var appState = AppState.shared

    /// Root SwiftUI scene. Main window shows the full dashboard with tabs and filters.
    var body: some Scene {
        WindowGroup {
            if let viewModel = appState.viewModel {
                FullDashboardView(viewModel: viewModel)
            } else {
                ProgressView("Loading...")
                    .frame(width: 200, height: 200)
            }
        }
        .windowStyle(.automatic)
        .defaultSize(width: 600, height: 500)
    }
}

/// AppKit delegate responsible for setting up the status bar item and popover.
final class AppDelegate: NSObject, NSApplicationDelegate {
    private var statusItemController: StatusItemController?
    private var aggregator: MetricsAggregator?

    func applicationDidFinishLaunching(_ notification: Notification) {
        // Apply dock visibility setting on launch
        let settingsManager = SettingsManager.shared
        let showInDock = settingsManager.getShowInDock()
        settingsManager.setShowInDock(showInDock) // This applies the setting
        
        let aggregator = MetricsAggregator()
        self.aggregator = aggregator
        let viewModel = MetricsViewModel(aggregator: aggregator)
        
        // Share viewModel with the main window
        AppState.shared.setViewModel(viewModel)

        statusItemController = StatusItemController(viewModel: viewModel)
        statusItemController?.setupStatusItem()

        // Start capturing events and metrics aggregation.
        aggregator.start()
    }

    func applicationWillTerminate(_ notification: Notification) {
        // Stop aggregator (this will save current sample)
        aggregator?.stop()
        statusItemController?.tearDown()
    }
}


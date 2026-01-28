import SwiftUI
import AppKit

@main
struct ActivityTrackerApp: App {
    /// Shared app delegate to manage NSStatusItem and AppKit integration.
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate

    /// Root SwiftUI scene. We keep the main window hidden and primarily use a menu bar popover.
    var body: some Scene {
        // A minimal, hidden window scene that can be used later for a full dashboard window if desired.
        WindowGroup {
            EmptyView()
        }
        .windowStyle(.hiddenTitleBar)
    }
}

/// AppKit delegate responsible for setting up the status bar item and popover.
final class AppDelegate: NSObject, NSApplicationDelegate {
    private var statusItemController: StatusItemController?

    func applicationDidFinishLaunching(_ notification: Notification) {
        let aggregator = MetricsAggregator()
        let viewModel = MetricsViewModel(aggregator: aggregator)

        statusItemController = StatusItemController(viewModel: viewModel)
        statusItemController?.setupStatusItem()

        // Start capturing events and metrics aggregation.
        aggregator.start()
    }

    func applicationWillTerminate(_ notification: Notification) {
        statusItemController?.tearDown()
    }
}


import SwiftUI
import AppKit

@main
struct TendonTallyApp: App {
    /// Shared app delegate to manage NSStatusItem and AppKit integration.
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate
    @StateObject private var appState = AppState.shared

    /// Root SwiftUI scene. Main window shows the full dashboard with tabs and filters.
    /// Using Window instead of WindowGroup for single-instance utility window that can be reopened.
    var body: some Scene {
        Window("Dashboard", id: "main-dashboard") {
            if appState.isBetaExpired {
                BetaExpiredView()
            } else if let viewModel = appState.viewModel {
                FullDashboardView(viewModel: viewModel)
            } else {
                ProgressView("Loading...")
                    .frame(width: 200, height: 200)
            }
        }
        .windowStyle(.hiddenTitleBar)
        .windowToolbarStyle(.unifiedCompact)
        .defaultSize(width: 1000, height: 600)
        .windowResizability(.contentSize)
    }
}

/// AppKit delegate responsible for setting up the status bar item and popover.
final class AppDelegate: NSObject, NSApplicationDelegate {
    private var statusItemController: StatusItemController?
    private var aggregator: MetricsAggregator?
    private var breakPillController: BreakPillController?

    func applicationDidFinishLaunching(_ notification: Notification) {
        if BetaAccessPolicy.isExpired() {
            AppState.shared.setBetaExpired(true)
            NSApplication.shared.activate(ignoringOtherApps: true)
            return
        }

        // Apply dock visibility setting on launch
        let settingsManager = SettingsManager.shared
        let showInDock = settingsManager.getShowInDock()
        settingsManager.setShowInDock(showInDock) // This applies the setting

        let pillController = BreakPillController()
        self.breakPillController = pillController

        let aggregator = MetricsAggregator(
            restoredLastActivityAt: AppPreferences.shared.breakLastActivityAt
        )
        self.aggregator = aggregator
        let viewModel = MetricsViewModel(
            aggregator: aggregator,
            breakPillController: pillController
        )
        
        // Share viewModel with the main window
        AppState.shared.setViewModel(viewModel)

        statusItemController = StatusItemController(viewModel: viewModel)
        statusItemController?.setupStatusItem()

        // Start capturing events and metrics aggregation.
        aggregator.start()

        // Bring app to foreground on launch
        NSApplication.shared.activate(ignoringOtherApps: true)
    }

    func applicationWillTerminate(_ notification: Notification) {
        // Stop aggregator (this will save current sample)
        aggregator?.stop()
        statusItemController?.tearDown()
    }
    
    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        if AppState.shared.isBetaExpired {
            return true
        }
        // Menu bar apps should keep running when the window is closed
        return false
    }

    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        // If there are no visible windows, activate the app
        // The Window scene will be opened by SwiftUI automatically
        if !flag {
            NSApplication.shared.activate(ignoringOtherApps: true)
        }
        return true
    }
}

enum BetaAccessPolicy {
    static func isExpired(now: Date = Date(), calendar: Calendar = .current) -> Bool {
        guard let cutoffDate = calendar.date(from: DateComponents(year: 2026, month: 3, day: 1)) else {
            return false
        }
        return now >= cutoffDate
    }
}

private struct BetaExpiredView: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("TendonTally Beta Has Ended")
                .font(.system(size: 28, weight: .bold))

            Text("This beta ended on March 1, 2026. Thanks for testing TendonTally.")
                .font(.system(size: 15))
                .foregroundStyle(.secondary)

            Text("For release details and next steps, visit:")
                .font(.system(size: 14))
                .foregroundStyle(.secondary)

            Link("tendontally.com", destination: URL(string: "https://tendontally.com")!)
                .font(.system(size: 15, weight: .semibold))
        }
        .padding(28)
        .frame(minWidth: 560, minHeight: 260, alignment: .topLeading)
    }
}

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
        .commands {
            AppCommandMenu()
        }
    }
}

@MainActor
private struct AppCommandMenu: Commands {
    @Environment(\.openWindow) private var openWindow

    var body: some Commands {
        FileMenuCleanupCommands()
        EditMenuCleanupCommands()
        ViewMenuCleanupCommands()
        WindowHelpCleanupCommands()

        CommandGroup(replacing: .appSettings) {
            Button("Settings...") {
                selectDashboardTab(.settings)
            }
            .keyboardShortcut(",", modifiers: .command)
        }

        // Put app navigation shortcuts into the built-in View menu.
        CommandGroup(replacing: .sidebar) {
            Button("Today") {
                selectDashboardTab(.today)
            }
            .keyboardShortcut("1", modifiers: .command)

            Button("History") {
                selectDashboardTab(.history)
            }
            .keyboardShortcut("2", modifiers: .command)

            Button("Total") {
                selectDashboardTab(.totalCalculation)
            }
            .keyboardShortcut("3", modifiers: .command)

            Button("Breaks") {
                selectDashboardTab(.breaks)
            }
            .keyboardShortcut("4", modifiers: .command)

            Button("Permissions") {
                selectDashboardTab(.permissions)
            }
            .keyboardShortcut("5", modifiers: .command)
        }

        CommandMenu("Metrics") {
            Button("Copy Today's Metrics") {
                copyMetrics(for: .today)
            }
            .keyboardShortcut("c", modifiers: [.command, .shift])

            Button("Copy Yesterday's Metrics") {
                copyMetrics(for: .yesterday)
            }
            .keyboardShortcut("c", modifiers: [.command, .option])
        }
    }

    private func selectDashboardTab(_ tab: FullDashboardView.Tab) {
        UserDefaults.standard.set(tab.rawValue, forKey: "selectedTab")
        NSApplication.shared.activate(ignoringOtherApps: true)
        openWindow(id: "main-dashboard")
    }

    private func copyMetrics(for day: DailyExportDay) {
        guard let viewModel = AppState.shared.viewModel,
              viewModel.copyDailyMetricsToClipboard(for: day) != nil else {
            NSSound.beep()
            return
        }
    }
}

private struct FileMenuCleanupCommands: Commands {
    var body: some Commands {
        CommandGroup(replacing: .newItem) {}
        CommandGroup(replacing: .saveItem) {}
        CommandGroup(replacing: .importExport) {}
        CommandGroup(replacing: .printItem) {}
    }
}

private struct EditMenuCleanupCommands: Commands {
    var body: some Commands {
        CommandGroup(replacing: .undoRedo) {}
        CommandGroup(replacing: .pasteboard) {}
        CommandGroup(replacing: .textEditing) {}
        CommandGroup(replacing: .textFormatting) {}
    }
}

private struct ViewMenuCleanupCommands: Commands {
    var body: some Commands {
        CommandGroup(replacing: .toolbar) {}
        CommandGroup(replacing: .windowSize) {}
    }
}

private struct WindowHelpCleanupCommands: Commands {
    var body: some Commands {
        CommandGroup(replacing: .windowArrangement) {}
        CommandGroup(replacing: .help) {}
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
        sanitizeMainMenu()
        DispatchQueue.main.async { [weak self] in
            self?.sanitizeMainMenu()
        }
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
            sanitizeMainMenu()
        }
        return true
    }

    func applicationDidBecomeActive(_ notification: Notification) {
        sanitizeMainMenu()
    }

    private func sanitizeMainMenu() {
        guard let mainMenu = NSApp.mainMenu else { return }

        if let formatItem = mainMenu.items.first(where: { $0.title == "Format" }) {
            mainMenu.removeItem(formatItem)
        }

        removeMenuItems(titled: "Enter Full Screen", in: mainMenu)
        removeMenuItems(titled: "Exit Full Screen", in: mainMenu)
    }

    private func removeMenuItems(titled title: String, in menu: NSMenu) {
        for index in stride(from: menu.items.count - 1, through: 0, by: -1) {
            let item = menu.items[index]
            if item.title == title {
                menu.removeItem(at: index)
                continue
            }
            if let submenu = item.submenu {
                removeMenuItems(titled: title, in: submenu)
            }
        }
    }
}

enum BetaAccessPolicy {
    static func isExpired(now: Date = Date(), calendar: Calendar = .current) -> Bool {
        guard let cutoffDate = calendar.date(from: DateComponents(year: 2026, month: 4, day: 1)) else {
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

            Text("This beta ended on April 1, 2026. Thanks for testing TendonTally.")
                .font(.system(size: 15))
                .foregroundStyle(.secondary)

            Text("For release details and next steps, visit:")
                .font(.system(size: 14))
                .foregroundStyle(.secondary)

            Link(
                "tendontally.com",
                destination: URL(
                    string: "https://tendontally.com/?utm_source=tendontally_app&utm_medium=beta_wall&utm_campaign=beta_end_apr_2026"
                )!
            )
                .font(.system(size: 15, weight: .semibold))
        }
        .padding(28)
        .frame(minWidth: 560, minHeight: 260, alignment: .topLeading)
    }
}

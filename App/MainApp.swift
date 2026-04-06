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
            if let viewModel = appState.viewModel {
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

        CommandGroup(after: .appSettings) {
            Button("Check for Updates...") {
                Task {
                    await AppUpdateChecker.shared.checkForUpdates(trigger: .manual)
                }
            }
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

        Task {
            await AppUpdateChecker.shared.checkForUpdates(trigger: .automatic)
        }
    }

    func applicationWillTerminate(_ notification: Notification) {
        // Stop aggregator (this will save current sample)
        aggregator?.stop()
        statusItemController?.tearDown()
    }
    
    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
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

@MainActor
final class AppUpdateChecker {
    enum Trigger {
        case automatic
        case manual
    }

    static let shared = AppUpdateChecker()

    private static let repositoryOwner = "Krecharles"
    private static let repositoryName = "tendon-tally"
    private static let automaticCheckInterval: TimeInterval = 7 * 24 * 60 * 60

    private let session: URLSession
    private let now: () -> Date
    private let preferences: AppPreferences
    private var isChecking = false

    init(
        session: URLSession = .shared,
        now: @escaping () -> Date = Date.init,
        preferences: AppPreferences = .shared
    ) {
        self.session = session
        self.now = now
        self.preferences = preferences
    }

    func checkForUpdates(trigger: Trigger) async {
        guard !isChecking else { return }
        if trigger == .automatic, !shouldPerformAutomaticCheck() {
            return
        }

        isChecking = true
        defer {
            isChecking = false
        }

        let outcome: CheckOutcome
        do {
            let latestRelease = try await fetchLatestRelease()
            let currentVersion = currentAppVersion
            guard let latestVersion = parseVersion(latestRelease.tagName),
                  let installedVersion = parseVersion(currentVersion) else {
                throw CheckError.invalidVersionData(current: currentVersion, latest: latestRelease.tagName)
            }

            if compareVersions(latestVersion, installedVersion) == .orderedDescending {
                outcome = .updateAvailable(
                    latestVersionLabel: latestRelease.tagName,
                    currentVersionLabel: currentVersion,
                    releaseURL: latestRelease.url
                )
            } else {
                outcome = .upToDate
            }

            preferences.lastUpdateCheckAt = now()
        } catch {
            outcome = .failed(error.localizedDescription)
        }
        handle(outcome, for: trigger)
    }

    private func shouldPerformAutomaticCheck() -> Bool {
        guard let lastCheckAt = preferences.lastUpdateCheckAt else {
            return true
        }
        return now().timeIntervalSince(lastCheckAt) >= Self.automaticCheckInterval
    }

    private var currentAppVersion: String {
        let bundle = Bundle.main
        let marketingVersion = bundle.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String
        let buildVersion = bundle.object(forInfoDictionaryKey: "CFBundleVersion") as? String
        return marketingVersion ?? buildVersion ?? "0.0.0"
    }

    private func fetchLatestRelease() async throws -> ReleaseDescriptor {
        guard let url = URL(string: "https://api.github.com/repos/\(Self.repositoryOwner)/\(Self.repositoryName)/releases/latest") else {
            throw CheckError.invalidAPIURL
        }

        var request = URLRequest(url: url)
        request.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
        request.setValue("TendonTally-Updater", forHTTPHeaderField: "User-Agent")

        let (data, response) = try await session.data(for: request)
        guard let httpResponse = response as? HTTPURLResponse else {
            throw CheckError.invalidResponse
        }
        guard (200...299).contains(httpResponse.statusCode) else {
            throw CheckError.httpStatus(httpResponse.statusCode)
        }

        let payload = try JSONDecoder().decode(GitHubReleasePayload.self, from: data)
        guard let releaseURL = URL(string: payload.htmlURL) else {
            throw CheckError.invalidReleaseURL(payload.htmlURL)
        }
        return ReleaseDescriptor(tagName: payload.tagName, url: releaseURL)
    }

    private func parseVersion(_ raw: String) -> [Int]? {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }

        let withoutPrefix = trimmed.hasPrefix("v") ? String(trimmed.dropFirst()) : trimmed
        let core = withoutPrefix.split(separator: "-", maxSplits: 1).first.map(String.init) ?? withoutPrefix
        let components = core.split(separator: ".", omittingEmptySubsequences: false)
        guard !components.isEmpty else { return nil }

        var parsed: [Int] = []
        for component in components {
            guard let value = Int(component), value >= 0 else { return nil }
            parsed.append(value)
        }
        return parsed
    }

    private func compareVersions(_ lhs: [Int], _ rhs: [Int]) -> ComparisonResult {
        let count = max(lhs.count, rhs.count)
        for index in 0..<count {
            let left = index < lhs.count ? lhs[index] : 0
            let right = index < rhs.count ? rhs[index] : 0
            if left < right { return .orderedAscending }
            if left > right { return .orderedDescending }
        }
        return .orderedSame
    }

    private func handle(_ outcome: CheckOutcome, for trigger: Trigger) {
        switch outcome {
        case let .updateAvailable(latestVersionLabel, currentVersionLabel, releaseURL):
            presentUpdateAvailableAlert(
                latestVersionLabel: latestVersionLabel,
                currentVersionLabel: currentVersionLabel,
                releaseURL: releaseURL
            )
        case .upToDate:
            if trigger == .manual {
                presentUpToDateAlert()
            }
        case let .failed(message):
            if trigger == .manual {
                presentFailedCheckAlert(message: message)
            }
        }
    }

    private func presentUpdateAvailableAlert(
        latestVersionLabel: String,
        currentVersionLabel: String,
        releaseURL: URL
    ) {
        let alert = NSAlert()
        alert.alertStyle = .informational
        alert.messageText = "Update Available"
        alert.informativeText = "TendonTally \(latestVersionLabel) is available. You're currently running \(currentVersionLabel)."
        alert.addButton(withTitle: "Download")
        alert.addButton(withTitle: "Later")

        if alert.runModal() == .alertFirstButtonReturn {
            NSWorkspace.shared.open(releaseURL)
        }
    }

    private func presentUpToDateAlert() {
        let alert = NSAlert()
        alert.alertStyle = .informational
        alert.messageText = "You're Up to Date"
        alert.informativeText = "You're running the latest version of TendonTally."
        alert.addButton(withTitle: "OK")
        alert.runModal()
    }

    private func presentFailedCheckAlert(message: String) {
        let alert = NSAlert()
        alert.alertStyle = .warning
        alert.messageText = "Couldn't Check for Updates"
        alert.informativeText = "TendonTally couldn't check the latest release right now.\n\n\(message)"
        alert.addButton(withTitle: "Open Releases Page")
        alert.addButton(withTitle: "OK")

        if alert.runModal() == .alertFirstButtonReturn,
           let releasesURL = URL(string: "https://github.com/\(Self.repositoryOwner)/\(Self.repositoryName)/releases/latest") {
            NSWorkspace.shared.open(releasesURL)
        }
    }
}

private extension AppUpdateChecker {
    struct GitHubReleasePayload: Decodable {
        let tagName: String
        let htmlURL: String

        private enum CodingKeys: String, CodingKey {
            case tagName = "tag_name"
            case htmlURL = "html_url"
        }
    }

    struct ReleaseDescriptor {
        let tagName: String
        let url: URL
    }

    enum CheckOutcome {
        case updateAvailable(latestVersionLabel: String, currentVersionLabel: String, releaseURL: URL)
        case upToDate
        case failed(String)
    }

    enum CheckError: LocalizedError {
        case invalidAPIURL
        case invalidResponse
        case httpStatus(Int)
        case invalidReleaseURL(String)
        case invalidVersionData(current: String, latest: String)

        var errorDescription: String? {
            switch self {
            case .invalidAPIURL:
                return "The update API URL is invalid."
            case .invalidResponse:
                return "The update server returned an invalid response."
            case let .httpStatus(statusCode):
                return "The update server responded with status code \(statusCode)."
            case let .invalidReleaseURL(rawURL):
                return "The latest release URL is invalid: \(rawURL)"
            case let .invalidVersionData(current, latest):
                return "Could not compare installed version \(current) with latest release \(latest)."
            }
        }
    }
}

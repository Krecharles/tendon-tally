import Foundation
import AppKit
import ServiceManagement

/// Manages application settings including launch at login and dock visibility preferences.
final class SettingsManager {
    static let shared = SettingsManager()
    
    private let userDefaults = UserDefaults.standard
    private let launchAtLoginKey = "launchAtLogin"
    private let showInDockKey = "showInDock"
    
    private init() {}
    
    // MARK: - Launch at Login
    
    func getLaunchAtLogin() -> Bool {
        return userDefaults.bool(forKey: launchAtLoginKey)
    }
    
    func setLaunchAtLogin(_ enabled: Bool) {
        userDefaults.set(enabled, forKey: launchAtLoginKey)

        let service = SMAppService.mainApp
        do {
            if enabled {
                try service.register()
            } else {
                try service.unregister()
            }
        } catch {
            // Log or handle error as needed
        }
    }
    
    // MARK: - Show in Dock
    
    func getShowInDock() -> Bool {
        // Default to enabled for first-time users when no preference has been saved yet.
        if userDefaults.object(forKey: showInDockKey) == nil {
            return true
        }
        return userDefaults.bool(forKey: showInDockKey)
    }
    
    func setShowInDock(_ enabled: Bool) {
        userDefaults.set(enabled, forKey: showInDockKey)
        applyShowInDockPreference(preserveVisibleWindows: true)
    }

    func applySavedDockVisibility() {
        applyShowInDockPreference(preserveVisibleWindows: false)
    }

    private func applyShowInDockPreference(preserveVisibleWindows: Bool) {
        let desiredPolicy: NSApplication.ActivationPolicy = getShowInDock() ? .regular : .accessory
        guard NSApp.activationPolicy() != desiredPolicy else { return }

        let visibleWindows = preserveVisibleWindows
            ? NSApp.dashboardWindows.filter(\.isVisible)
            : []

        NSApp.setActivationPolicy(desiredPolicy)

        if !visibleWindows.isEmpty {
            // Changing activation policy can deactivate the app and move its windows
            // behind other applications. Restore the dashboard the user was editing.
            DispatchQueue.main.async {
                NSApp.activate(ignoringOtherApps: true)
                visibleWindows.forEach { window in
                    window.makeKeyAndOrderFront(nil)
                }
            }
        }
    }
}

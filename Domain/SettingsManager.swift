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
        return userDefaults.bool(forKey: showInDockKey)
    }
    
    func setShowInDock(_ enabled: Bool) {
        userDefaults.set(enabled, forKey: showInDockKey)

        // Set activation policy based on preference
        if enabled {
            NSApp.setActivationPolicy(.regular)
        } else {
            NSApp.setActivationPolicy(.accessory)
        }

        // Re-activate the app so the current window stays visible and focused
        // (changing activation policy can cause macOS to deactivate the app)
        DispatchQueue.main.async {
            NSApp.activate(ignoringOtherApps: true)
        }
    }
}

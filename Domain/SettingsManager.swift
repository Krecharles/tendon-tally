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
        
        // Use ServiceManagement framework to set login item
        // Note: This requires the app bundle identifier to be registered
        // For a production app, you may need a helper app
        if #available(macOS 13.0, *) {
            // Use the new SMAppService API on macOS 13+
            let service = SMAppService.loginItem(identifier: Bundle.main.bundleIdentifier ?? "com.activitytracker")
            do {
                if enabled {
                    try service.register()
                } else {
                    try service.unregister()
                }
            } catch {
                // Fall back to deprecated API if new one fails
                let bundleIdentifier = Bundle.main.bundleIdentifier ?? "com.activitytracker"
                SMLoginItemSetEnabled(bundleIdentifier as CFString, enabled)
            }
        } else {
            // Use deprecated API for older macOS versions
            let bundleIdentifier = Bundle.main.bundleIdentifier ?? "com.activitytracker"
            SMLoginItemSetEnabled(bundleIdentifier as CFString, enabled)
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
    }
}

import Foundation

/// Centralizes all UserDefaults access for the application.
final class AppPreferences {
    static let shared = AppPreferences()

    private let defaults = UserDefaults.standard

    private init() {}

    // MARK: - Keys

    private enum Keys {
        static let selectedTab = "selectedTab"
        static let selectedTimeFrame = "selectedTimeFrame"
        static let selectedMetric = "selectedMetric"
        static let kuiConfig = "kuiConfig"
        static let launchAtLogin = "launchAtLogin"
        static let showInDock = "showInDock"
    }

    // MARK: - Time Frame

    var selectedTimeFrame: TimeFrame {
        get {
            if let raw = defaults.string(forKey: Keys.selectedTimeFrame),
               let tf = TimeFrame(rawValue: raw) {
                return tf
            }
            return .today
        }
        set {
            defaults.set(newValue.rawValue, forKey: Keys.selectedTimeFrame)
        }
    }

    // MARK: - Selected Metric

    var selectedMetric: MetricType {
        get {
            if let raw = defaults.string(forKey: Keys.selectedMetric),
               let metric = MetricType(rawValue: raw) {
                return metric
            }
            return .keys
        }
        set {
            defaults.set(newValue.rawValue, forKey: Keys.selectedMetric)
        }
    }

    // MARK: - KUI Config

    var kuiConfig: KUIConfig {
        get {
            if let data = defaults.data(forKey: Keys.kuiConfig),
               let config = try? JSONDecoder().decode(KUIConfig.self, from: data) {
                return config
            }
            return .default
        }
        set {
            if let data = try? JSONEncoder().encode(newValue) {
                defaults.set(data, forKey: Keys.kuiConfig)
            }
        }
    }

    // MARK: - Launch at Login

    var launchAtLogin: Bool {
        get { defaults.bool(forKey: Keys.launchAtLogin) }
        set { defaults.set(newValue, forKey: Keys.launchAtLogin) }
    }

    // MARK: - Show in Dock

    var showInDock: Bool {
        get { defaults.bool(forKey: Keys.showInDock) }
        set { defaults.set(newValue, forKey: Keys.showInDock) }
    }
}

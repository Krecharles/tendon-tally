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
        static let totalConfig = "totalConfig"
        static let advancedTotalCalculationEnabled = "advancedTotalCalculationEnabled"
        static let launchAtLogin = "launchAtLogin"
        static let showInDock = "showInDock"
        static let breaksConfig = "breaksConfig"
        static let breakLastActivityAt = "breakLastActivityAt"
        static let breakLastBreakEndedAt = "breakLastBreakEndedAt"
        static let breakRemindersSnoozedUntil = "breakRemindersSnoozedUntil"
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
            if let raw = defaults.string(forKey: Keys.selectedMetric) {
                if let metric = MetricType(rawValue: raw) {
                    return metric
                }
                // Preserve prior aggregate selections from older labels.
                return .aggregate
            }
            return .keys
        }
        set {
            defaults.set(newValue.rawValue, forKey: Keys.selectedMetric)
        }
    }

    // MARK: - Total Config

    var totalConfig: TotalConfig {
        get {
            if let data = defaults.data(forKey: Keys.totalConfig),
               let config = try? JSONDecoder().decode(TotalConfig.self, from: data) {
                return config
            }
            return .default
        }
        set {
            if let data = try? JSONEncoder().encode(newValue) {
                defaults.set(data, forKey: Keys.totalConfig)
            }
        }
    }

    // MARK: - Advanced Total Calculation

    var advancedTotalCalculationEnabled: Bool {
        get { defaults.bool(forKey: Keys.advancedTotalCalculationEnabled) }
        set { defaults.set(newValue, forKey: Keys.advancedTotalCalculationEnabled) }
    }

    // MARK: - Launch at Login

    var launchAtLogin: Bool {
        get { defaults.bool(forKey: Keys.launchAtLogin) }
        set { defaults.set(newValue, forKey: Keys.launchAtLogin) }
    }

    // MARK: - Show in Dock

    var showInDock: Bool {
        get {
            if defaults.object(forKey: Keys.showInDock) == nil {
                return true
            }
            return defaults.bool(forKey: Keys.showInDock)
        }
        set { defaults.set(newValue, forKey: Keys.showInDock) }
    }

    // MARK: - Breaks Config

    var breaksConfig: BreaksConfig {
        get {
            if let data = defaults.data(forKey: Keys.breaksConfig),
               let config = try? JSONDecoder().decode(BreaksConfig.self, from: data) {
                return config.normalized()
            }
            return .default
        }
        set {
            let normalized = newValue.normalized()
            if let data = try? JSONEncoder().encode(normalized) {
                defaults.set(data, forKey: Keys.breaksConfig)
            }
        }
    }

    // MARK: - Break Runtime State

    var breakLastActivityAt: Date? {
        get { defaults.object(forKey: Keys.breakLastActivityAt) as? Date }
        set { defaults.set(newValue, forKey: Keys.breakLastActivityAt) }
    }

    var breakLastBreakEndedAt: Date? {
        get { defaults.object(forKey: Keys.breakLastBreakEndedAt) as? Date }
        set { defaults.set(newValue, forKey: Keys.breakLastBreakEndedAt) }
    }

    var breakRemindersSnoozedUntil: Date? {
        get { defaults.object(forKey: Keys.breakRemindersSnoozedUntil) as? Date }
        set { defaults.set(newValue, forKey: Keys.breakRemindersSnoozedUntil) }
    }
}

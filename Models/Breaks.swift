import Foundation

/// User-configurable break reminder settings.
struct BreaksConfig: Codable, Equatable {
    static let defaultLookbackMinutes = 30
    static let defaultRequiredBreakMinutes = 5
    static let minRequiredBreakMinutes = 1
    static let maxRequiredBreakMinutes = 60
    static let minTimeBeforeReminderMinutes = 1

    static let minLookbackMinutes = minRequiredBreakMinutes + minTimeBeforeReminderMinutes
    static let maxLookbackMinutes = 180

    var lookbackMinutes: Int
    var requiredBreakMinutes: Int
    var remindersEnabled: Bool

    static let `default` = BreaksConfig(
        lookbackMinutes: defaultLookbackMinutes,
        requiredBreakMinutes: defaultRequiredBreakMinutes,
        remindersEnabled: false
    )

    /// Clamps values to product bounds and enforces at least `minTimeBeforeReminderMinutes` before reminders.
    func normalized() -> BreaksConfig {
        let clampedLookback = min(max(lookbackMinutes, Self.minLookbackMinutes), Self.maxLookbackMinutes)
        let maxRequiredForLookback = max(
            Self.minRequiredBreakMinutes,
            clampedLookback - Self.minTimeBeforeReminderMinutes
        )
        let clampedRequired = min(
            max(requiredBreakMinutes, Self.minRequiredBreakMinutes),
            min(Self.maxRequiredBreakMinutes, maxRequiredForLookback)
        )
        return BreaksConfig(
            lookbackMinutes: clampedLookback,
            requiredBreakMinutes: clampedRequired,
            remindersEnabled: remindersEnabled
        )
    }
}

/// The current phase of the break cycle.
enum BreakPhase: Equatable {
    /// User is working within the allowed work window.
    case work
    /// A break is due (work window exceeded without a qualifying break).
    case due
    /// User is currently on a qualifying break (idle long enough).
    case onBreak
}

/// Current computed break state using simple date math.
struct BreaksEvaluation: Equatable {
    let phase: BreakPhase
    let lastBreakEndedAt: Date?
    let currentIdleSeconds: TimeInterval
    let workWindowSeconds: TimeInterval
    let requiredBreakSeconds: TimeInterval
}

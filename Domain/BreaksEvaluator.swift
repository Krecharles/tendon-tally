import Foundation

/// Pure function that computes break state from two dates and config.
enum BreaksEvaluator {
    static func evaluate(
        lastBreakEndedAt: Date?,
        lastActivityAt: Date?,
        config: BreaksConfig,
        now: Date = Date()
    ) -> BreaksEvaluation {
        let normalized = config.normalized()
        let requiredBreakSeconds = TimeInterval(normalized.requiredBreakMinutes * 60)
        let workWindowSeconds = TimeInterval(
            max(BreaksConfig.minTimeBeforeReminderMinutes, normalized.lookbackMinutes - normalized.requiredBreakMinutes) * 60
        )

        let idleDuration: TimeInterval
        if let lastActivity = lastActivityAt {
            idleDuration = max(0, now.timeIntervalSince(lastActivity))
        } else {
            idleDuration = 0
        }

        let isOnQualifyingBreak = idleDuration >= requiredBreakSeconds

        let phase: BreakPhase
        if isOnQualifyingBreak {
            phase = .onBreak
        } else if let breakEnd = lastBreakEndedAt {
            let timeSinceBreak = now.timeIntervalSince(breakEnd)
            phase = timeSinceBreak >= workWindowSeconds ? .due : .work
        } else {
            phase = .due
        }

        return BreaksEvaluation(
            phase: phase,
            lastBreakEndedAt: lastBreakEndedAt,
            currentIdleSeconds: idleDuration,
            workWindowSeconds: workWindowSeconds,
            requiredBreakSeconds: requiredBreakSeconds
        )
    }
}

/// Tracks the break-to-active transition to capture `lastBreakEndedAt` exactly once.
struct BreakTransitionTracker {
    private(set) var lastBreakEndedAt: Date?
    private var previouslyOnQualifyingBreak: Bool = false

    init(lastBreakEndedAt: Date? = nil) {
        self.lastBreakEndedAt = lastBreakEndedAt
    }

    /// Call each tick with current idle state. Returns true if a transition was detected.
    @discardableResult
    mutating func update(lastActivityAt: Date?, config: BreaksConfig, now: Date = Date()) -> Bool {
        let requiredBreakSeconds = TimeInterval(config.normalized().requiredBreakMinutes * 60)
        let idleDuration: TimeInterval
        if let lastActivity = lastActivityAt {
            idleDuration = max(0, now.timeIntervalSince(lastActivity))
        } else {
            idleDuration = 0
        }

        let isOnQualifyingBreak = idleDuration >= requiredBreakSeconds

        var transitioned = false
        if previouslyOnQualifyingBreak && !isOnQualifyingBreak {
            lastBreakEndedAt = now
            transitioned = true
        }
        previouslyOnQualifyingBreak = isOnQualifyingBreak
        return transitioned
    }

    /// Restore state on app startup. If the user was away long enough, treat it as a completed break.
    mutating func restoreFromStartup(
        persistedLastActivityAt: Date?,
        persistedLastBreakEndedAt: Date?,
        config: BreaksConfig,
        now: Date = Date()
    ) {
        let requiredBreakSeconds = TimeInterval(config.normalized().requiredBreakMinutes * 60)

        if let lastActivity = persistedLastActivityAt {
            let idleSinceLastActivity = now.timeIntervalSince(lastActivity)
            if idleSinceLastActivity >= requiredBreakSeconds {
                // User was away long enough — treat as a completed break
                lastBreakEndedAt = now
                previouslyOnQualifyingBreak = false
            } else {
                lastBreakEndedAt = persistedLastBreakEndedAt
                previouslyOnQualifyingBreak = false
            }
        } else {
            lastBreakEndedAt = persistedLastBreakEndedAt
            previouslyOnQualifyingBreak = false
        }
    }
}

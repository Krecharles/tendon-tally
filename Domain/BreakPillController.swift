import AppKit
import Combine

enum BreakReminderSnoozeOption: CaseIterable {
    case fiveMinutes
    case oneHour
    case untilTomorrow

    var title: String {
        switch self {
        case .fiveMinutes:
            return "5 minutes"
        case .oneHour:
            return "1 hour"
        case .untilTomorrow:
            return "Until tomorrow"
        }
    }

    func snoozedUntil(from now: Date = Date(), calendar: Calendar = .current) -> Date {
        switch self {
        case .fiveMinutes:
            return now.addingTimeInterval(5 * 60)
        case .oneHour:
            return now.addingTimeInterval(60 * 60)
        case .untilTomorrow:
            let startOfToday = calendar.startOfDay(for: now)
            return calendar.date(byAdding: .day, value: 1, to: startOfToday) ?? now.addingTimeInterval(24 * 60 * 60)
        }
    }
}

/// Controls the floating break pill panel lifecycle and publishes state for the SwiftUI view.
/// Always called from @MainActor MetricsViewModel, so all access is on the main thread.
final class BreakPillController: ObservableObject {
    @Published var phase: BreakPhase = .work
    @Published var primaryText: String = ""
    @Published var progress: Double = 0.0
    @Published var showResetWarning: Bool = false
    @Published var showCelebration: Bool = false
    var onSnoozeRequested: (@MainActor (BreakReminderSnoozeOption) -> Void)?

    private let presentPanels: Bool
    private var panels: [BreakPillPanel] = []
    private(set) var isVisible = false
    private var previousPhase: BreakPhase?
    private var previousIdleSeconds: TimeInterval = 0
    private var resetWarningCountdown: Int = 0

    init(presentPanels: Bool = true) {
        self.presentPanels = presentPanels
    }

    @MainActor
    func update(evaluation: BreaksEvaluation, config: BreaksConfig) {
        let oldPhase = previousPhase
        phase = evaluation.phase
        previousPhase = evaluation.phase

        guard config.remindersEnabled else {
            hide()
            return
        }

        switch evaluation.phase {
        case .work:
            showCelebration = false
            hide()
            return

        case .due:
            if oldPhase != .due {
                playSound(.tink)
            }
            let remaining = max(0, evaluation.requiredBreakSeconds - evaluation.currentIdleSeconds)
            primaryText = "\(formattedDuration(remaining)) left"
            progress = min(1.0, evaluation.currentIdleSeconds / evaluation.requiredBreakSeconds)

            // Show warning when idle time drops — the user just provided input that reset the break timer.
            if evaluation.currentIdleSeconds < previousIdleSeconds - 1 {
                resetWarningCountdown = 5
                playSound(.reset)
            }
            previousIdleSeconds = evaluation.currentIdleSeconds
            if resetWarningCountdown > 0 {
                resetWarningCountdown -= 1
                showResetWarning = true
            } else {
                showResetWarning = false
            }

        case .onBreak:
            // Only surface completion when a break was actually due.
            // Early breaks taken during work should remain silent.
            let shouldShowCompletedPill = oldPhase == .due || (oldPhase == .onBreak && isVisible)
            guard shouldShowCompletedPill else {
                showCelebration = false
                hide()
                return
            }

            // Keep the completed-due state visible until input resumes work.
            // This state is intentionally silent.
            previousIdleSeconds = 0
            resetWarningCountdown = 0
            showResetWarning = false
            showCelebration = true
            primaryText = formattedDuration(evaluation.requiredBreakSeconds)
            progress = 1.0
        }

        show()
    }

    @MainActor
    private func show() {
        if !presentPanels {
            isVisible = true
            return
        }
        syncPanelsToScreens()
        guard !isVisible else { return }
        isVisible = true
        for panel in panels {
            panel.showPill()
        }
    }

    @MainActor
    private func hide() {
        guard isVisible else { return }
        if !presentPanels {
            isVisible = false
            return
        }
        isVisible = false
        for panel in panels {
            panel.hidePill()
        }
    }

    @MainActor
    func requestSnooze(_ option: BreakReminderSnoozeOption) {
        onSnoozeRequested?(option)
        suppressForSnooze()
    }

    @MainActor
    func suppressForSnooze() {
        previousIdleSeconds = 0
        resetWarningCountdown = 0
        showResetWarning = false
        showCelebration = false
        hide()
    }

    @MainActor
    private func syncPanelsToScreens() {
        let screens = NSScreen.screens
        if panels.count != screens.count {
            for panel in panels {
                panel.orderOut(nil)
            }
            panels = screens.map { BreakPillPanel(controller: self, screen: $0) }
        }
    }

    private func playSound(_ name: NSSound.Name) {
        if let sound = NSSound(named: name) {
            sound.play()
        }
    }

    private func formattedDuration(_ seconds: TimeInterval) -> String {
        let total = max(0, Int(seconds.rounded()))
        let hours = total / 3600
        let minutes = (total % 3600) / 60
        let secs = total % 60

        if hours > 0 {
            return String(format: "%dh %02dm", hours, minutes)
        }
        if minutes > 0 {
            return String(format: "%dm %02ds", minutes, secs)
        }
        return "\(secs)s"
    }
}

private extension NSSound.Name {
    static let tink = NSSound.Name("Tink")
    static let reset = NSSound.Name("Ping")
}

import AppKit
import Combine

/// Controls the floating break pill panel lifecycle and publishes state for the SwiftUI view.
/// Always called from @MainActor MetricsViewModel, so all access is on the main thread.
final class BreakPillController: ObservableObject {
    @Published var phase: BreakPhase = .work
    @Published var primaryText: String = ""
    @Published var progress: Double = 0.0
    @Published var showResetWarning: Bool = false
    @Published var showCelebration: Bool = false

    private var panels: [BreakPillPanel] = []
    private var isVisible = false
    private var previousPhase: BreakPhase?
    private var previousIdleSeconds: TimeInterval = 0
    private var resetWarningCountdown: Int = 0

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
            // If the user becomes idle for the required break time while still in the
            // normal work phase, don't show the "break complete" pill.
            if oldPhase == .work {
                previousIdleSeconds = 0
                resetWarningCountdown = 0
                showResetWarning = false
                showCelebration = false
                hide()
                return
            }
            if oldPhase == .due {
                showCelebration = true
            }
            if oldPhase != .onBreak {
                playSound(.hero)
            }
            previousIdleSeconds = 0
            resetWarningCountdown = 0
            showResetWarning = false
            primaryText = "Done"
            progress = 1.0
        }

        show()
    }

    @MainActor
    private func show() {
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
        isVisible = false
        for panel in panels {
            panel.hidePill()
        }
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
    static let hero = NSSound.Name("Hero")
    static let reset = NSSound.Name("Ping")
}

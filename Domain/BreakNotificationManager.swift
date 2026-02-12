import Foundation
import UserNotifications

/// Handles break reminder notification permissions and delivery.
final class BreakNotificationManager {
    private let center: UNUserNotificationCenter
    private var previousPhase: BreakPhase?
    private var lastNotifiedAt: Date?

    /// Optional status text for UI when notifications cannot be delivered.
    private(set) var statusMessage: String?

    init(center: UNUserNotificationCenter = .current()) {
        self.center = center
    }

    func handleEvaluation(_ evaluation: BreaksEvaluation, config: BreaksConfig) {
        guard config.remindersEnabled else {
            previousPhase = nil
            lastNotifiedAt = nil
            statusMessage = nil
            clearNotifications()
            return
        }

        let phase = evaluation.phase

        // Break complete: transition from .onBreak -> .work
        if previousPhase == .onBreak && phase == .work {
            let nextBreakMinutes = Int(evaluation.workWindowSeconds / 60)
            Task { [weak self] in
                await self?.deliverBreakComplete(nextBreakMinutes: nextBreakMinutes)
            }
        }

        if phase == .due {
            let interval = reminderInterval(evaluation: evaluation)
            if lastNotifiedAt == nil || Date().timeIntervalSince(lastNotifiedAt!) >= interval {
                Task { [weak self] in
                    await self?.deliverReminder(evaluation: evaluation, config: config)
                }
                lastNotifiedAt = Date()
            }
        } else {
            if lastNotifiedAt != nil {
                lastNotifiedAt = nil
                clearNotifications()
            }
        }

        previousPhase = phase
    }

    // MARK: - Reminder interval

    private func reminderInterval(evaluation: BreaksEvaluation) -> TimeInterval {
        // Time when the break became due
        let dueAt: Date
        if let lastEnd = evaluation.lastBreakEndedAt {
            dueAt = lastEnd.addingTimeInterval(evaluation.workWindowSeconds)
        } else {
            // No recorded break — use a fallback so the first notification fires immediately
            dueAt = Date.distantPast
        }

        let overdueSeconds = Date().timeIntervalSince(dueAt)
        // First 15 minutes overdue: every 5 min. After that: every 10 min.
        return overdueSeconds <= 15 * 60 ? 5 * 60 : 10 * 60
    }

    // MARK: - Delivery

    private func deliverReminder(evaluation: BreaksEvaluation, config: BreaksConfig) async {
        let settings = await center.notificationSettings()
        switch settings.authorizationStatus {
        case .authorized, .provisional, .ephemeral:
            await setStatusMessage(nil)
            await sendBreakReminder(evaluation: evaluation, config: config)
        case .notDetermined:
            do {
                let granted = try await center.requestAuthorization(options: [.alert, .sound])
                if granted {
                    await setStatusMessage(nil)
                    await sendBreakReminder(evaluation: evaluation, config: config)
                } else {
                    await setStatusMessage("Break reminders are disabled because notification permission was denied.")
                }
            } catch {
                await setStatusMessage("Break reminders are unavailable due to a notification error.")
            }
        case .denied:
            await setStatusMessage("Break reminders are disabled because notification permission is denied in macOS settings.")
        @unknown default:
            await setStatusMessage("Break reminders are unavailable due to unknown notification settings.")
        }
    }

    private func sendBreakReminder(evaluation: BreaksEvaluation, config: BreaksConfig) async {
        let workMinutes = minutesSinceLastBreak(evaluation: evaluation)
        let breakMinutes = config.requiredBreakMinutes

        let content = UNMutableNotificationContent()
        content.title = "Time to take a break"
        content.body = "You've been working for \(workMinutes)m. Step away for \(breakMinutes)m."
        content.sound = .default
        content.interruptionLevel = .timeSensitive

        let request = UNNotificationRequest(
            identifier: "break-reminder",
            content: content,
            trigger: nil
        )

        do {
            try await center.add(request)
        } catch {
            await setStatusMessage("Break reminder could not be delivered.")
        }
    }

    private func deliverBreakComplete(nextBreakMinutes: Int) async {
        let settings = await center.notificationSettings()
        guard case .authorized = settings.authorizationStatus else { return }

        // Clear any lingering due reminder
        center.removeDeliveredNotifications(withIdentifiers: ["break-reminder"])

        let content = UNMutableNotificationContent()
        content.title = "Break complete"
        content.body = "Nice work — your next break is in \(nextBreakMinutes)m."
        content.sound = .default
        content.interruptionLevel = .timeSensitive

        let request = UNNotificationRequest(
            identifier: "break-complete",
            content: content,
            trigger: nil
        )

        try? await center.add(request)
    }

    // MARK: - Helpers

    private func minutesSinceLastBreak(evaluation: BreaksEvaluation) -> Int {
        guard let lastEnd = evaluation.lastBreakEndedAt else {
            return Int(evaluation.workWindowSeconds / 60)
        }
        return max(1, Int(Date().timeIntervalSince(lastEnd) / 60))
    }

    private func clearNotifications() {
        center.removeDeliveredNotifications(withIdentifiers: ["break-reminder"])
        center.removePendingNotificationRequests(withIdentifiers: ["break-reminder"])
    }

    @MainActor
    private func setStatusMessage(_ message: String?) {
        statusMessage = message
    }
}

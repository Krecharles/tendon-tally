import SwiftUI
import AppKit

struct BreaksTabView: View {
    @ObservedObject var viewModel: MetricsViewModel
    @FocusState private var focusedInput: BreaksInputField?

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                Text("Breaks")
                    .font(.system(size: 28, weight: .bold))
                    .foregroundColor(.primary)

                explanationCard
                remindersToggleRow
                if viewModel.breaksConfig.remindersEnabled {
                    managedSection
                }
            }
            .padding(.horizontal, 24)
            .padding(.bottom, 24)
            .padding(.top, 8)
            .contentShape(Rectangle())
            .simultaneousGesture(
                TapGesture().onEnded { dismissInputFocus() },
                including: .gesture
            )
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }

    private var topStatusCard: some View {
        let phase = viewModel.breakCardPhase
        let color: Color = phase == .onBreak ? .blue : (phase == .due ? .red : .green)
        let symbol = phase == .onBreak ? "pause.circle.fill" : (phase == .due ? "bell.badge.fill" : "checkmark.circle.fill")

        return VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 8) {
                Image(systemName: symbol)
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundColor(color)
                    .frame(width: 24, height: 24)
                    .background(color.opacity(0.12))
                    .clipShape(RoundedRectangle(cornerRadius: 6))

                Text(viewModel.breakCardPrimaryLabel)
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundColor(.secondary)
                    .textCase(.uppercase)
                    .tracking(0.4)
            }

            Text(viewModel.breakCardPrimaryValue)
                .font(.system(size: 42, weight: .bold, design: .rounded))
                .foregroundColor(.primary)

            ProgressView(value: viewModel.breakCardProgressValue)
                .tint(color)

            Text(viewModel.breakLastQualifyingBreakText)
                .font(.system(size: 12))
                .foregroundColor(.secondary)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 14)
        .frame(maxWidth: 560, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(Color(NSColor.controlBackgroundColor))
        )
        .clipShape(RoundedRectangle(cornerRadius: 12))
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .fill(color.opacity(0.05))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .stroke(color.opacity(0.28), lineWidth: 1)
        )
    }

    private var explanationCard: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                Image(systemName: "info.circle.fill")
                    .font(.system(size: 12))
                    .foregroundColor(.blue)
                Text("How Break Reminders Work")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundColor(.primary)
            }

            Text("You set how long you can work and how long your break should be. After working too long, you'll get a reminder. Stop using your computer for the full break length to reset the timer.")
                .font(.system(size: 12))
                .foregroundColor(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
        .frame(maxWidth: 560, alignment: .leading)
        .background(Color(NSColor.controlBackgroundColor))
        .clipShape(RoundedRectangle(cornerRadius: 10))
        .overlay(
            RoundedRectangle(cornerRadius: 10)
                .stroke(Color(NSColor.separatorColor).opacity(0.4), lineWidth: 1)
        )
    }

    private var managedSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            topStatusCard

            if let notificationMessage = viewModel.breakNotificationStatusMessage,
               viewModel.breakCardPhase == .due {
                Text(notificationMessage)
                    .font(.system(size: 11))
                    .foregroundColor(.secondary)
                    .frame(maxWidth: 560, alignment: .leading)
            }

            Text("Break Rules")
                .font(.system(size: 10, weight: .semibold))
                .foregroundColor(.secondary)
                .textCase(.uppercase)
                .tracking(0.5)
                .padding(.leading, 4)

            VStack(spacing: 6) {
                BreakConfigRow(
                    title: "Time Before Break Reminder",
                    value: workTimeBeforeReminderMinutes,
                    range: BreaksConfig.minTimeBeforeReminderMinutes...max(
                        BreaksConfig.minTimeBeforeReminderMinutes,
                        BreaksConfig.maxLookbackMinutes - viewModel.breaksConfig.requiredBreakMinutes
                    ),
                    field: .timeBeforeReminder,
                    focusedInput: $focusedInput,
                    unit: "min"
                ) { value in
                    updateWorkTimeBeforeReminder(value)
                }

                BreakConfigRow(
                    title: "Break Length",
                    value: viewModel.breaksConfig.requiredBreakMinutes,
                    range: BreaksConfig.minRequiredBreakMinutes...min(
                        BreaksConfig.maxRequiredBreakMinutes,
                        max(
                            BreaksConfig.minRequiredBreakMinutes,
                            BreaksConfig.maxLookbackMinutes - workTimeBeforeReminderMinutes
                        )
                    ),
                    field: .breakLength,
                    focusedInput: $focusedInput,
                    unit: "min"
                ) { value in
                    let preservedWorkTime = workTimeBeforeReminderMinutes
                    var updated = viewModel.breaksConfig
                    updated.requiredBreakMinutes = value
                    updated.lookbackMinutes = min(
                        BreaksConfig.maxLookbackMinutes,
                        max(BreaksConfig.minLookbackMinutes, value + preservedWorkTime)
                    )
                    viewModel.updateBreaksConfig(updated)
                }
            }
            .frame(maxWidth: 560)
        }
        .frame(maxWidth: 560, alignment: .leading)
    }

    private var workTimeBeforeReminderMinutes: Int {
        max(
            BreaksConfig.minTimeBeforeReminderMinutes,
            viewModel.breaksConfig.lookbackMinutes - viewModel.breaksConfig.requiredBreakMinutes
        )
    }

    private func updateWorkTimeBeforeReminder(_ minutes: Int) {
        var updated = viewModel.breaksConfig
        updated.lookbackMinutes = min(
            BreaksConfig.maxLookbackMinutes,
            max(BreaksConfig.minLookbackMinutes, minutes + updated.requiredBreakMinutes)
        )
        viewModel.updateBreaksConfig(updated)
    }

    private func dismissInputFocus() {
        focusedInput = nil
        NSApp.keyWindow?.makeFirstResponder(nil)
    }

    private var remindersToggleRow: some View {
        HStack(spacing: 0) {
            HStack(spacing: 10) {
                Image(systemName: "bell.badge")
                    .font(.system(size: 12))
                    .foregroundColor(.blue)
                    .frame(width: 24, height: 24)
                    .background(Color.blue.opacity(0.12))
                    .clipShape(RoundedRectangle(cornerRadius: 6))

                VStack(alignment: .leading, spacing: 2) {
                    Text("Enable Break Reminders")
                        .font(.system(size: 13, weight: .medium))
                        .foregroundColor(.primary)
                    Text("Send a local notification when no qualifying break is found.")
                        .font(.system(size: 11))
                        .foregroundColor(.secondary)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            Toggle("", isOn: Binding(
                get: { viewModel.breaksConfig.remindersEnabled },
                set: { enabled in
                    var updated = viewModel.breaksConfig
                    updated.remindersEnabled = enabled
                    viewModel.updateBreaksConfig(updated)
                }
            ))
            .labelsHidden()
            .toggleStyle(.switch)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .background(Color(NSColor.controlBackgroundColor))
        .clipShape(RoundedRectangle(cornerRadius: 10))
        .overlay(
            RoundedRectangle(cornerRadius: 10)
                .stroke(Color(NSColor.separatorColor).opacity(0.4), lineWidth: 1)
        )
        .frame(maxWidth: 560)
    }

}

private enum BreaksInputField: Hashable {
    case timeBeforeReminder
    case breakLength
}

private struct BreakConfigRow: View {
    let title: String
    let value: Int
    let range: ClosedRange<Int>
    let field: BreaksInputField
    let focusedInput: FocusState<BreaksInputField?>.Binding
    let unit: String
    let onChange: (Int) -> Void

    @State private var textValue: String = ""
    @State private var isInvalid = false

    var body: some View {
        HStack(spacing: 0) {
            Text(title)
                .font(.system(size: 13, weight: .medium))
                .foregroundColor(.primary)
            .frame(maxWidth: .infinity, alignment: .leading)

            HStack(spacing: 4) {
                TextField("", text: $textValue)
                    .frame(width: 54)
                    .textFieldStyle(.roundedBorder)
                    .font(.system(size: 12, design: .monospaced))
                    .foregroundColor(isInvalid ? .red : .primary)
                    .multilineTextAlignment(.center)
                    .focused(focusedInput, equals: field)
                    .onSubmit { applyTextChange() }
                    .onChange(of: focusedInput.wrappedValue) { _, newValue in
                        if newValue != field { applyTextChange() }
                    }
                    .onChange(of: textValue) { _, _ in
                        isInvalid = Int(textValue) == nil
                    }
                    .onChange(of: value) { _, newValue in
                        textValue = "\(newValue)"
                        isInvalid = false
                    }
                    .onAppear {
                        textValue = "\(value)"
                    }

                Text(unit)
                    .font(.system(size: 11))
                    .foregroundColor(.secondary)

                Stepper("", value: Binding(get: { value }, set: onChange), in: range)
                    .labelsHidden()
                    .controlSize(.small)
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .background(Color(NSColor.controlBackgroundColor))
        .clipShape(RoundedRectangle(cornerRadius: 10))
        .overlay(
            RoundedRectangle(cornerRadius: 10)
                .stroke(Color(NSColor.separatorColor).opacity(0.4), lineWidth: 1)
        )
    }

    private func applyTextChange() {
        if let parsed = Int(textValue) {
            let clamped = min(max(parsed, range.lowerBound), range.upperBound)
            onChange(clamped)
            textValue = "\(clamped)"
            isInvalid = false
        } else {
            textValue = "\(value)"
            isInvalid = true
        }
    }
}

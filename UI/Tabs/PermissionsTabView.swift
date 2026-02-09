import SwiftUI

struct PermissionsTabView: View {
    let message: String

    var body: some View {
        VStack(spacing: 0) {
            Spacer()

            VStack(spacing: 32) {
                // Icon and title
                VStack(spacing: 16) {
                    Image(systemName: "lock.shield")
                        .font(.system(size: 48, weight: .light))
                        .foregroundStyle(.red.opacity(0.8))

                    Text("Permissions Required")
                        .font(.system(size: 24, weight: .bold))
                        .foregroundColor(.primary)

                    Text(message)
                        .font(.system(size: 13))
                        .foregroundColor(.secondary)
                        .multilineTextAlignment(.center)
                        .frame(maxWidth: 360)
                }

                // Steps card
                VStack(alignment: .leading, spacing: 0) {
                    ForEach(Array(steps.enumerated()), id: \.offset) { index, step in
                        HStack(spacing: 14) {
                            Image(systemName: step.icon)
                                .font(.system(size: 14))
                                .foregroundColor(step.color)
                                .frame(width: 32, height: 32)
                                .background(step.color.opacity(0.1))
                                .clipShape(RoundedRectangle(cornerRadius: 8))

                            Text(LocalizedStringKey(step.text))
                                .font(.system(size: 13))
                                .foregroundColor(.primary)

                            Spacer()
                        }
                        .padding(.horizontal, 16)
                        .padding(.vertical, 12)

                        if index < steps.count - 1 {
                            Divider()
                                .padding(.leading, 62)
                        }
                    }
                }
                .background(Color(NSColor.controlBackgroundColor))
                .clipShape(RoundedRectangle(cornerRadius: 12))
                .overlay(
                    RoundedRectangle(cornerRadius: 12)
                        .stroke(Color(NSColor.separatorColor), lineWidth: 0.5)
                )
                .frame(maxWidth: 400)

                // Action buttons
                VStack(spacing: 10) {
                    Button(action: openAccessibilitySettings) {
                        Text("Open System Settings")
                            .font(.system(size: 13, weight: .medium))
                            .frame(width: 200)
                            .padding(.vertical, 8)
                            .background(Color.accentColor)
                            .foregroundColor(.white)
                            .clipShape(RoundedRectangle(cornerRadius: 8))
                    }
                    .buttonStyle(.plain)

                    Text("You may need to restart the app after granting permissions.")
                        .font(.system(size: 11))
                        .foregroundStyle(.tertiary)
                }
            }

            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var steps: [(icon: String, text: String, color: Color)] {
        [
            ("gear", "Open **System Settings**", .gray),
            ("lock.shield", "Go to **Privacy & Security**", .blue),
            ("hand.raised.fill", "Enable TendonTally under **Accessibility**", .orange),
            ("keyboard.fill", "Enable TendonTally under **Input Monitoring**", .purple),
        ]
    }

    private func openAccessibilitySettings() {
        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility") {
            NSWorkspace.shared.open(url)
        }
    }
}

import SwiftUI
import AppKit
import Combine

struct PermissionsTabView: View {
    let message: String
    @State private var accessibilityGranted = EventTapManager.isAccessibilityGranted()
    @State private var inputMonitoringGranted = EventTapManager.isInputMonitoringGranted()

    private let timer = Timer.publish(every: 2, on: .main, in: .common).autoconnect()

    var body: some View {
        ScrollView {
            VStack(spacing: 0) {
                Spacer()
                    .frame(height: 8)

                VStack(spacing: 32) {
                    // Header
                    VStack(spacing: 12) {
                        Image(systemName: "shield.lefthalf.filled")
                            .font(.system(size: 44, weight: .light))
                            .foregroundStyle(.blue.opacity(0.8))

                        Text("Permissions")
                            .font(.system(size: 26, weight: .bold))
                            .foregroundColor(.primary)

                        Text("TendonTally needs two permissions to count your keyboard and mouse activity across all apps.")
                            .font(.system(size: 13))
                            .foregroundColor(.secondary)
                            .multilineTextAlignment(.center)
                            .frame(maxWidth: 420)

                        if !message.isEmpty {
                            Text(message)
                                .font(.system(size: 12, weight: .medium))
                                .foregroundColor(.red)
                                .multilineTextAlignment(.center)
                                .frame(maxWidth: 420)
                        }
                    }

                    // Permission cards
                    VStack(spacing: 12) {
                        permissionCard(
                            icon: "hand.raised.fill",
                            iconColor: .orange,
                            title: "Accessibility",
                            description: "Allows TendonTally to detect mouse clicks, scroll events, and mouse movement system-wide.",
                            isGranted: accessibilityGranted,
                            action: openAccessibilitySettings
                        )

                        permissionCard(
                            icon: "keyboard.fill",
                            iconColor: .purple,
                            title: "Input Monitoring",
                            description: "Allows TendonTally to count keystrokes across all apps. Only the number of key presses is recorded, never which keys you type.",
                            isGranted: inputMonitoringGranted,
                            action: openInputMonitoringSettings
                        )

                        if !accessibilityGranted || !inputMonitoringGranted {
                            HStack(spacing: 8) {
                                Image(systemName: "arrow.clockwise")
                                    .font(.system(size: 11))
                                    .foregroundColor(.secondary)

                                Text("Permission status is rechecked automatically every few seconds.")
                                    .font(.system(size: 12, weight: .medium))
                                    .foregroundColor(.secondary)
                            }
                            .padding(.top, 4)
                        }
                    }
                    .frame(maxWidth: 460)

                    // Privacy footer
                    HStack(spacing: 8) {
                        Image(systemName: "lock.fill")
                            .font(.system(size: 11))
                            .foregroundColor(.secondary)

                        Text("Keystroke and mouse data stays on your Mac. Only counts and distances are stored, never which keys you press.")
                            .font(.system(size: 11))
                            .foregroundColor(.secondary)
                    }
                }

                Spacer()
                    .frame(height: 48)
            }
            .frame(maxWidth: .infinity)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .onReceive(timer) { _ in
            refreshPermissionStatus()
        }
        .onAppear {
            refreshPermissionStatus()
        }
    }

    private func permissionCard(
        icon: String,
        iconColor: Color,
        title: String,
        description: String,
        isGranted: Bool,
        action: @escaping () -> Void
    ) -> some View {
        HStack(spacing: 14) {
            Image(systemName: icon)
                .font(.system(size: 18))
                .foregroundColor(iconColor)
                .frame(width: 40, height: 40)
                .background(iconColor.opacity(0.1))
                .clipShape(RoundedRectangle(cornerRadius: 10))

            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 8) {
                    Text(title)
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundColor(.primary)

                    if isGranted {
                        HStack(spacing: 4) {
                            Image(systemName: "checkmark.circle.fill")
                                .font(.system(size: 11))
                            Text("Granted")
                                .font(.system(size: 11, weight: .medium))
                        }
                        .foregroundColor(.green)
                    }
                }

                Text(description)
                    .font(.system(size: 12))
                    .foregroundColor(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Spacer()

            if !isGranted {
                Button(action: action) {
                    Text("Grant")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundColor(.white)
                        .padding(.horizontal, 16)
                        .padding(.vertical, 7)
                        .background(iconColor)
                        .clipShape(RoundedRectangle(cornerRadius: 7))
                }
                .buttonStyle(.plain)
            }
        }
        .padding(16)
        .background(Color(NSColor.controlBackgroundColor))
        .clipShape(RoundedRectangle(cornerRadius: 12))
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .stroke(Color(NSColor.separatorColor).opacity(0.4), lineWidth: 1)
        )
    }

    private func refreshPermissionStatus() {
        let status = EventTapManager.probePermissionStatus()
        accessibilityGranted = status.accessibilityGranted
        inputMonitoringGranted = status.inputMonitoringGranted
    }

    private func openAccessibilitySettings() {
        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility") {
            NSWorkspace.shared.open(url)
        }
    }

    private func openInputMonitoringSettings() {
        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_ListenEvent") {
            NSWorkspace.shared.open(url)
        }
    }
}

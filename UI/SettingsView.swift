import SwiftUI

struct SettingsView: View {
    var viewModel: MetricsViewModel?
    private let settingsManager = SettingsManager.shared
    @State private var launchAtLogin: Bool
    @State private var showInDock: Bool
    @State private var showDeleteConfirmation = false

    init(viewModel: MetricsViewModel? = nil) {
        self.viewModel = viewModel
        let manager = SettingsManager.shared
        _launchAtLogin = State(initialValue: manager.getLaunchAtLogin())
        _showInDock = State(initialValue: manager.getShowInDock())
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                Text("Settings")
                    .font(.system(size: 28, weight: .bold))
                    .foregroundColor(.primary)

                // General
                settingsCard(title: "General") {
                    VStack(spacing: 0) {
                        toggleRow(label: "Open at Login", isOn: $launchAtLogin) { newValue in
                            settingsManager.setLaunchAtLogin(newValue)
                        }

                        Divider()
                            .padding(.leading, 14)

                        toggleRow(label: "Show in Dock", isOn: $showInDock) { newValue in
                            settingsManager.setShowInDock(newValue)
                        }
                    }
                }

                // Data
                settingsCard(title: "Data") {
                    HStack {
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Delete All Data")
                                .font(.system(size: 13))
                                .foregroundColor(.primary)
                            Text("Permanently remove all stored usage data")
                                .font(.system(size: 11))
                                .foregroundColor(.secondary)
                        }

                        Spacer()

                        Button(action: {
                            showDeleteConfirmation = true
                        }) {
                            Text("Delete")
                                .font(.system(size: 12, weight: .medium))
                                .foregroundColor(.red)
                                .padding(.horizontal, 14)
                                .padding(.vertical, 6)
                                .background(Color.red.opacity(0.1))
                                .clipShape(RoundedRectangle(cornerRadius: 6))
                                .overlay(
                                    RoundedRectangle(cornerRadius: 6)
                                        .stroke(Color.red.opacity(0.2), lineWidth: 1)
                                )
                        }
                        .buttonStyle(.plain)
                        .confirmationDialog(
                            "Delete All Data",
                            isPresented: $showDeleteConfirmation,
                            titleVisibility: .visible
                        ) {
                            Button("Delete", role: .destructive) {
                                PersistenceController.shared.deleteAllSamples()
                                viewModel?.reloadHistory()
                            }
                            Button("Cancel", role: .cancel) {}
                        } message: {
                            Text("This will permanently delete all stored usage data. This action cannot be undone.")
                        }
                    }
                    .padding(.horizontal, 14)
                    .padding(.vertical, 12)
                }

                // Privacy
                HStack(spacing: 8) {
                    Image(systemName: "lock.fill")
                        .font(.system(size: 11))
                        .foregroundColor(.secondary)

                    Text("All data stays on your Mac. Only counts and distances are stored, never which keys you press.")
                        .font(.system(size: 11))
                        .foregroundColor(.secondary)
                }
                .padding(.top, 4)
            }
            .padding(24)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }

    private func toggleRow(label: String, isOn: Binding<Bool>, onChange: @escaping (Bool) -> Void) -> some View {
        HStack {
            Text(label)
                .font(.system(size: 13))
                .foregroundColor(.primary)

            Spacer()

            Toggle("", isOn: isOn)
                .labelsHidden()
                .toggleStyle(.switch)
                .onChange(of: isOn.wrappedValue) { _, newValue in
                    onChange(newValue)
                }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
    }

    private func settingsCard<Content: View>(title: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title)
                .font(.system(size: 10, weight: .semibold))
                .foregroundColor(.secondary)
                .textCase(.uppercase)
                .tracking(0.5)
                .padding(.leading, 4)

            content()
                .background(Color(NSColor.controlBackgroundColor))
                .clipShape(RoundedRectangle(cornerRadius: 10))
                .overlay(
                    RoundedRectangle(cornerRadius: 10)
                        .stroke(Color(NSColor.separatorColor).opacity(0.4), lineWidth: 1)
                )
        }
        .frame(maxWidth: 400)
    }
}

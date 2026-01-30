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
        VStack(alignment: .leading, spacing: 20) {
            Text("Settings")
                .font(.headline)
                .padding(.bottom, 4)
            
            VStack(alignment: .leading, spacing: 16) {
                // Launch at Login
                Toggle("Open at Login", isOn: $launchAtLogin)
                    .onChange(of: launchAtLogin) { _, newValue in
                        settingsManager.setLaunchAtLogin(newValue)
                    }
                
                // Show in Dock
                Toggle("Show in Dock", isOn: $showInDock)
                    .onChange(of: showInDock) { _, newValue in
                        settingsManager.setShowInDock(newValue)
                    }
            }
            
            Divider()
            
            // Data Management
            VStack(alignment: .leading, spacing: 8) {
                Text("Data Management")
                    .font(.subheadline)
                    .foregroundColor(.secondary)
                
                HStack(spacing: 8) {
                    Button(action: {
                        PersistenceController.shared.generateTestData()
                        viewModel?.reloadHistory()
                    }) {
                        Text("Generate Test Data")
                    }
                    .buttonStyle(.bordered)
                    
                    Button(action: {
                        showDeleteConfirmation = true
                    }) {
                        Text("Delete All Data")
                            .foregroundColor(.red)
                    }
                    .buttonStyle(.bordered)
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
                
                Text("Test data includes 5-minute intervals for the last 4 days")
                    .font(.caption2)
                    .foregroundColor(.secondary)
            }
            
            Spacer()
        }
        .padding(16)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }
}

import SwiftUI
import AppKit

struct DashboardView: View {
    @ObservedObject var viewModel: MetricsViewModel

    private var timeRemainingDescription: String {
        let now = Date()
        let remaining = max(0, viewModel.currentSample.end.timeIntervalSince(now))
        let minutes = Int(remaining) / 60
        let seconds = Int(remaining) % 60
        return String(format: "%02dm %02ds", minutes, seconds)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            todayHeader
            todayTotalsSection
            permissionBannerIfNeeded
            Spacer()
            openDashboardButton
            footerHint
        }
        .padding(12)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var todayHeader: some View {
        HStack {
            VStack(alignment: .leading, spacing: 4) {
                Text("Today")
                    .font(.headline)
            }
            Spacer()
        }
    }
    
    private var openDashboardButton: some View {
        Button(action: openDashboard) {
            HStack {
                Image(systemName: "chart.bar.fill")
                    .font(.system(size: 12))
                Text("Open Dashboard")
                    .font(.subheadline)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 8)
            .background(Color.accentColor)
            .foregroundColor(.white)
            .cornerRadius(8)
        }
        .buttonStyle(.plain)
    }
    
    private func openDashboard() {
        // Activate the application
        NSApplication.shared.activate(ignoringOtherApps: true)
        
        // Find and show the main window
        // Look for any visible window first, then any window
        if let window = NSApplication.shared.windows.first(where: { $0.isVisible }) {
            window.makeKeyAndOrderFront(nil)
            window.orderFrontRegardless()
        } else if let window = NSApplication.shared.windows.first {
            window.makeKeyAndOrderFront(nil)
            window.orderFrontRegardless()
        } else {
            // If no window exists, trigger SwiftUI to create one
            // This works by activating the app, which should cause WindowGroup to create a window
            DispatchQueue.main.async {
                if let window = NSApplication.shared.windows.first {
                    window.makeKeyAndOrderFront(nil)
                }
            }
        }
    }

    @ViewBuilder
    private var permissionBannerIfNeeded: some View {
        if let message = viewModel.permissionIssueMessage {
            VStack(alignment: .leading, spacing: 6) {
                Text("Permissions Required")
                    .font(.subheadline).bold()
                Text("\(message) Open System Settings → Privacy & Security → Accessibility / Input Monitoring and enable this app.")
                    .font(.caption2)
                    .lineLimit(nil)
                    .multilineTextAlignment(.leading)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            .padding(8)
            .background(Color.red.opacity(0.08))
            .cornerRadius(8)
        } else {
            EmptyView()
        }
    }

    private var todayTotalsSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                metricTile(title: "Keys", value: viewModel.todayTotals.keyPressCount)
                metricTile(title: "Clicks", value: viewModel.todayTotals.mouseClickCount)
            }
            HStack {
                metricTile(title: "Scroll kTicks", value: viewModel.todayTotals.scrollTicks / 1_000)
                metricTile(title: "Mouse kPx", value: Int(viewModel.todayTotals.mouseDistance / 1_000))
            }
            HStack {
                let total = viewModel.todayTotals.keyPressCount +
                           viewModel.todayTotals.mouseClickCount +
                           viewModel.todayTotals.scrollTicks / 1_000 +
                           Int(viewModel.todayTotals.mouseDistance / 1_000)
                metricTile(title: "Total", value: total)
            }
        }
    }

    private func metricTile(title: String, value: Int) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title)
                .font(.caption)
                .foregroundColor(.secondary)
            Text("\(value)")
                .font(.body.monospacedDigit())
        }
        .padding(8)
        .background(Color.gray.opacity(0.08))
        .cornerRadius(8)
    }

    private var footerHint: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text("Data stays on your Mac.")
            Text("Only counts and distances are stored, never which keys.")
        }
        .font(.caption2)
        .foregroundColor(.secondary)
    }
}

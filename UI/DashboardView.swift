import SwiftUI

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
            header
            permissionBannerIfNeeded
            currentWindowSection
            Divider()
            historySection
            Spacer()
            footerHint
        }
        .padding(12)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var header: some View {
        HStack {
            VStack(alignment: .leading, spacing: 4) {
                Text("Last 5 Minutes")
                    .font(.headline)
                Text("Time left in window: \(timeRemainingDescription)")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
            Spacer()
        }
    }

    @ViewBuilder
    private var permissionBannerIfNeeded: some View {
        if let message = viewModel.permissionIssueMessage {
            VStack(alignment: .leading, spacing: 6) {
                Text("Permissions Required")
                    .font(.subheadline).bold()
                Text(message)
                    .font(.caption)
                Text("Go to System Settings → Privacy & Security → Accessibility / Input Monitoring and enable this app.")
                    .font(.caption2)
            }
            .padding(8)
            .background(Color.red.opacity(0.08))
            .cornerRadius(8)
        } else {
            EmptyView()
        }
    }

    private var currentWindowSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                metricTile(title: "Keys", value: viewModel.currentSample.keyPressCount)
                metricTile(title: "Clicks", value: viewModel.currentSample.mouseClickCount)
            }
            HStack {
                metricTile(title: "Scroll ticks", value: viewModel.currentSample.scrollTicks)
                metricTile(title: "Scroll px", value: Int(viewModel.currentSample.scrollDistance))
            }
            HStack {
                metricTile(title: "Mouse px", value: Int(viewModel.currentSample.mouseDistance))
                Spacer()
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

    private var historySection: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("Recent Windows")
                .font(.subheadline)
            if viewModel.recentHistory.isEmpty {
                Text("History will appear here as you keep using your Mac.")
                    .font(.caption)
                    .foregroundColor(.secondary)
            } else {
                ScrollView {
                    VStack(spacing: 6) {
                        ForEach(viewModel.recentHistory) { sample in
                            historyRow(sample)
                        }
                    }
                }
                .frame(maxHeight: 160)
            }
        }
    }

    private func historyRow(_ sample: UsageSample) -> some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text(sample.start, style: .time)
                    .font(.caption).bold()
                Text("Keys \(sample.keyPressCount) • Clicks \(sample.mouseClickCount) • Scroll \(sample.scrollTicks)")
                    .font(.caption2)
                    .foregroundColor(.secondary)
            }
            Spacer()
        }
        .padding(6)
        .background(Color.gray.opacity(0.04))
        .cornerRadius(6)
    }

    private var footerHint: some View {
        Text("Data stays on your Mac. Only counts and distances are stored, never which keys you press.")
            .font(.caption2)
            .foregroundColor(.secondary)
    }
}


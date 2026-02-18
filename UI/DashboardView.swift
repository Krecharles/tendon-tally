import SwiftUI
import AppKit

struct DashboardView: View {
    @ObservedObject var viewModel: MetricsViewModel
    @Environment(\.openWindow) private var openWindow

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 10) {
                Image("app-icon")
                    .resizable()
                    .aspectRatio(contentMode: .fit)
                    .frame(width: 22, height: 22)
                Text("TendonTally")
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundColor(.primary)

                Spacer()

                Text("Today")
                    .font(.system(size: 11))
                    .foregroundColor(.secondary)
            }

            metricsGrid

            if viewModel.breaksConfig.remindersEnabled {
                popoverBreakStatusCard
            }

            if let message = viewModel.permissionIssueMessage {
                PermissionBanner(message: message)
            }

            Button(action: openDashboard) {
                Text("Open Dashboard")
                    .font(.system(size: 12, weight: .medium))
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 7)
                    .foregroundColor(.accentColor)
                    .background(Color.accentColor.opacity(0.1))
                    .clipShape(RoundedRectangle(cornerRadius: 8))
                    .overlay(
                        RoundedRectangle(cornerRadius: 8)
                            .stroke(Color.accentColor.opacity(0.25), lineWidth: 1)
                    )
            }
            .buttonStyle(.plain)
        }
        .padding(16)
        .frame(width: 340)
    }

    private var metricsGrid: some View {
        let total = viewModel.totalValue(for: AggregatedMetrics(
            keyPressCount: viewModel.todayTotals.keyPressCount,
            mouseClickCount: viewModel.todayTotals.mouseClickCount,
            scrollTicks: viewModel.todayTotals.scrollTicks,
            mouseDistance: viewModel.todayTotals.mouseDistance
        ))

        return VStack(spacing: 8) {
            HStack(spacing: 8) {
                popoverTile(title: "Keys", value: viewModel.todayTotals.keyPressCount, icon: "keyboard.fill", color: .blue)
                popoverTile(title: "Clicks", value: viewModel.todayTotals.mouseClickCount, icon: "cursorarrow.click", color: .red)
            }
            HStack(spacing: 8) {
                popoverTile(title: "Scroll", value: viewModel.todayTotals.scrollTicks / 100, icon: "arrow.up.arrow.down", color: .green)
                popoverTile(title: "Mouse", value: Int(viewModel.todayTotals.mouseDistance / 1_000), icon: "arrow.up.left.and.arrow.down.right", color: .orange)
            }
            HStack(spacing: 8) {
                popoverTile(title: "Total", value: Int(total), icon: "chart.bar.fill", color: .purple)
            }
        }
    }

    private func popoverTile(title: String, value: Int, icon: String, color: Color) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 6) {
                Image(systemName: icon)
                    .font(.system(size: 11))
                    .foregroundColor(color)
                    .frame(width: 22, height: 22)
                    .background(color.opacity(0.12))
                    .clipShape(RoundedRectangle(cornerRadius: 6))

                Text(title)
                    .font(.system(size: 11))
                    .foregroundColor(.secondary)
            }

            Text("\(value)")
                .font(.system(size: 18, weight: .semibold, design: .rounded))
                .foregroundColor(.primary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(10)
        .background(Color(NSColor.controlBackgroundColor))
        .clipShape(RoundedRectangle(cornerRadius: 8))
    }

    private var popoverBreakStatusCard: some View {
        let phase = viewModel.breakCardPhase
        let color: Color = phase == .onBreak ? .blue : (phase == .due ? .red : .green)
        let symbol = phase == .onBreak ? "pause.circle.fill" : (phase == .due ? "bell.badge.fill" : "checkmark.circle.fill")

        return VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                Image(systemName: symbol)
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundColor(color)
                    .frame(width: 20, height: 20)
                    .background(color.opacity(0.12))
                    .clipShape(RoundedRectangle(cornerRadius: 5))

                Text("Breaks")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundColor(.primary)

                Spacer()

                Text(viewModel.breakCardPrimaryLabel)
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundColor(.secondary)
                    .textCase(.uppercase)
            }

            Text(viewModel.breakCardPrimaryValue)
                .font(.system(size: 24, weight: .bold, design: .rounded))
                .foregroundColor(.primary)

            ProgressView(value: viewModel.breakCardProgressValue)
                .tint(color)

            Text(viewModel.breakLastQualifyingBreakText)
                .font(.system(size: 11))
                .foregroundColor(.secondary)
                .lineLimit(2)

            if let statusText = viewModel.breakReminderSnoozeStatusText {
                Divider()
                HStack(spacing: 8) {
                    Text(statusText)
                        .font(.system(size: 11))
                        .foregroundColor(.secondary)
                    Spacer()
                    Button("Resume now") {
                        viewModel.cancelBreakReminderSnooze()
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                }
            }
        }
        .padding(10)
        .background(Color(NSColor.controlBackgroundColor))
        .clipShape(RoundedRectangle(cornerRadius: 8))
        .overlay(
            RoundedRectangle(cornerRadius: 8)
                .stroke(color.opacity(0.24), lineWidth: 1)
        )
    }

    private func openDashboard() {
        NSApplication.shared.activate(ignoringOtherApps: true)
        openWindow(id: "main-dashboard")
    }
}

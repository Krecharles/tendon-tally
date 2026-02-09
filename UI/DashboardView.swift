import SwiftUI
import AppKit

struct DashboardView: View {
    @ObservedObject var viewModel: MetricsViewModel
    @Environment(\.openWindow) private var openWindow

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(spacing: 12) {
                Image("app-icon")
                    .resizable()
                    .aspectRatio(contentMode: .fit)
                    .frame(width: 24, height: 24)
                Text("Today's usage")
                    .font(.system(size: 20, weight: .bold))
                    .foregroundColor(.primary)
            }

            todayTotalsSection

            if let message = viewModel.permissionIssueMessage {
                PermissionBanner(message: message)
            }

            openDashboardButton
        }
        .padding(24)
        .frame(width: 400)
    }

    private var todayTotalsSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Grid(alignment: .leading, horizontalSpacing: 12, verticalSpacing: 12) {
                GridRow {
                    MetricTile(title: "Keys", value: viewModel.todayTotals.keyPressCount, icon: "keyboard.fill", color: .blue)
                    MetricTile(title: "Clicks", value: viewModel.todayTotals.mouseClickCount, icon: "cursorarrow.click", color: .red)
                }
                GridRow {
                    MetricTile(title: "Scroll ticks", value: viewModel.todayTotals.scrollTicks / 100, icon: "arrow.up.arrow.down", color: .green)
                    MetricTile(title: "Mouse pixels", value: Int(viewModel.todayTotals.mouseDistance / 1_000), icon: "arrow.up.left.and.arrow.down.right", color: .orange)
                }
                GridRow {
                    let kui = viewModel.kuiConfig.apply(to: AggregatedMetrics(
                        keyPressCount: viewModel.todayTotals.keyPressCount,
                        mouseClickCount: viewModel.todayTotals.mouseClickCount,
                        scrollTicks: viewModel.todayTotals.scrollTicks,
                        mouseDistance: viewModel.todayTotals.mouseDistance
                    ))
                    MetricTile(title: "KUI", value: Int(kui), icon: "chart.bar.fill", color: .purple)
                    Rectangle().fill(Color.clear).frame(height: 0)
                }
            }
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
        NSApplication.shared.activate(ignoringOtherApps: true)
        openWindow(id: "main-dashboard")
    }
}

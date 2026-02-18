import SwiftUI
import AppKit

struct TodayTabView: View {
    @ObservedObject var viewModel: MetricsViewModel

    private var todayMetrics: AggregatedMetrics {
        viewModel.todayMetrics()
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                Text("Today")
                    .font(.system(size: 28, weight: .bold))
                    .foregroundColor(.primary)

                if viewModel.breaksConfig.remindersEnabled {
                    breakStatusCard
                }

                let totalValue = viewModel.totalValue(for: todayMetrics)

                LazyVGrid(columns: [
                    GridItem(.flexible(), spacing: 10),
                    GridItem(.flexible(), spacing: 10),
                    GridItem(.flexible(), spacing: 10)
                ], spacing: 10) {
                    MetricTile(title: "Keys", value: todayMetrics.keyPressCount, icon: "keyboard.fill", color: .blue)
                    MetricTile(title: "Clicks", value: todayMetrics.mouseClickCount, icon: "cursorarrow.click", color: .red)
                    MetricTile(title: "Scroll", value: todayMetrics.scrollTicks / 100, icon: "arrow.up.arrow.down", color: .green)
                    MetricTile(title: "Mouse", value: Int(todayMetrics.mouseDistance / 1_000), icon: "arrow.up.left.and.arrow.down.right", color: .orange)
                    MetricTile(title: "Total", value: Int(totalValue.rounded()), icon: "chart.bar.fill", color: .purple)
                }
            }
            .padding(.horizontal, 24)
            .padding(.bottom, 24)
            .padding(.top, 8)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }

    private var breakStatusCard: some View {
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
}

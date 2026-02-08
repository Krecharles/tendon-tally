import SwiftUI

struct KUITabView: View {
    @ObservedObject var viewModel: MetricsViewModel

    private var todayMetrics: AggregatedMetrics {
        viewModel.todayMetrics()
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                VStack(alignment: .leading, spacing: 8) {
                    Text("Key Usage Indicator (KUI)")
                        .font(.system(size: 28, weight: .bold))
                        .foregroundColor(.primary)
                }

                VStack(alignment: .leading, spacing: 8) {
                    kuiExplanationSection
                    kuiConfigurationSection
                }
                .frame(maxWidth: 600, alignment: .leading)
            }
            .padding(24)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }

    private var kuiExplanationSection: some View {
        Text("KUI is a single number that combines keys, clicks, scrolling and mouse movement into one \u{201C}how much did my hands work?\u{201D} score. Use it as the one metric you try to nudge up over time (for example 10\u{2013}20% per week), instead of watching raw computer time.")
            .font(.caption)
            .foregroundColor(.secondary)
    }

    private var kuiConfigurationSection: some View {
        let keysValue = todayMetrics.keyPressCount
        let clicksValue = todayMetrics.mouseClickCount
        let scrollValue = todayMetrics.scrollTicks / 100
        let mouseValue = Int(todayMetrics.mouseDistance / 1_000)

        let keysTerm = Double(keysValue) * viewModel.kuiConfig.keysWeight
        let clicksTerm = Double(clicksValue) * viewModel.kuiConfig.clicksWeight
        let scrollTerm = Double(scrollValue) * viewModel.kuiConfig.scrollTicksWeight
        let mouseTerm = Double(mouseValue) * viewModel.kuiConfig.mouseDistanceWeight
        let totalKUI = keysTerm + clicksTerm + scrollTerm + mouseTerm

        return VStack(alignment: .leading, spacing: 12) {
            VStack(alignment: .leading, spacing: 8) {
                KUIWeightRow(
                    title: "Keys",
                    icon: "keyboard.fill",
                    color: .blue,
                    currentValue: keysValue,
                    contribution: keysTerm,
                    weight: $viewModel.kuiConfig.keysWeight,
                    showLeadingPlus: false
                )
                KUIWeightRow(
                    title: "Clicks",
                    icon: "cursorarrow.click",
                    color: .red,
                    currentValue: clicksValue,
                    contribution: clicksTerm,
                    weight: $viewModel.kuiConfig.clicksWeight,
                    showLeadingPlus: true
                )
                KUIWeightRow(
                    title: "Scroll (per 100 ticks)",
                    icon: "arrow.up.arrow.down",
                    color: .green,
                    currentValue: scrollValue,
                    contribution: scrollTerm,
                    weight: $viewModel.kuiConfig.scrollTicksWeight,
                    showLeadingPlus: true
                )
                KUIWeightRow(
                    title: "Mouse distance (per 1000 px)",
                    icon: "arrow.up.left.and.arrow.down.right",
                    color: .orange,
                    currentValue: mouseValue,
                    contribution: mouseTerm,
                    weight: $viewModel.kuiConfig.mouseDistanceWeight,
                    showLeadingPlus: true
                )
            }

            Divider()

            HStack(spacing: 12) {
                Text("=")
                    .font(.system(size: 20, weight: .semibold))
                    .frame(width: 20, alignment: .center)

                HStack(spacing: 8) {
                    Image(systemName: "chart.bar.fill")
                        .font(.system(size: 16))
                        .foregroundColor(.purple)
                        .frame(width: 24, height: 24)
                        .background(Color.purple.opacity(0.12))
                        .clipShape(RoundedRectangle(cornerRadius: 6))

                    Text("Total KUI")
                        .font(.subheadline)
                }

                Spacer()

                HStack {
                    Spacer()
                    Text(String(format: "%.1f", totalKUI))
                        .font(.system(size: 18, weight: .semibold, design: .monospaced))
                        .frame(width: 70, alignment: .trailing)
                }
                .frame(width: 260, alignment: .center)
            }
        }
        .padding(16)
        .background(Color(NSColor.controlBackgroundColor))
        .clipShape(RoundedRectangle(cornerRadius: 12))
    }
}

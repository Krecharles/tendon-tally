import SwiftUI

struct TodayTabView: View {
    @ObservedObject var viewModel: MetricsViewModel

    private var todayMetrics: AggregatedMetrics {
        viewModel.todayMetrics()
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Today")
                        .font(.system(size: 28, weight: .bold))
                        .foregroundColor(.primary)
                }

                todayTotalsSection

                unitsExplanation
            }
            .padding(24)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }

    private var todayTotalsSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Grid(alignment: .leading, horizontalSpacing: 12, verticalSpacing: 12) {
                GridRow {
                    MetricTile(title: "Keys", value: todayMetrics.keyPressCount, icon: "keyboard.fill", color: .blue)
                    MetricTile(title: "Clicks", value: todayMetrics.mouseClickCount, icon: "cursorarrow.click", color: .red)
                    MetricTile(title: "Scroll ticks (100s)", value: todayMetrics.scrollTicks / 100, icon: "arrow.up.arrow.down", color: .green)
                }
                GridRow {
                    MetricTile(title: "Mouse pixels (1000s)", value: Int(todayMetrics.mouseDistance / 1_000), icon: "arrow.up.left.and.arrow.down.right", color: .orange)
                    let kuiValue = viewModel.kuiConfig.apply(to: todayMetrics)
                    MetricTile(title: "KUI", value: Int(kuiValue.rounded()), icon: "chart.bar.fill", color: .purple)
                }
            }
        }
    }

    private var unitsExplanation: some View {
        Text("Units are scaled so typical values are of a similar magnitude for an average user (scroll ticks in 100s, mouse distance in 1000s of pixels).")
            .font(.caption2)
            .foregroundColor(.secondary)
            .fixedSize(horizontal: false, vertical: true)
    }
}

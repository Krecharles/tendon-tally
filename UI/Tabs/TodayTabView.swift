import SwiftUI

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

                let kuiValue = viewModel.kuiConfig.apply(to: todayMetrics)

                LazyVGrid(columns: [
                    GridItem(.flexible(), spacing: 10),
                    GridItem(.flexible(), spacing: 10),
                    GridItem(.flexible(), spacing: 10)
                ], spacing: 10) {
                    MetricTile(title: "Keys", value: todayMetrics.keyPressCount, icon: "keyboard.fill", color: .blue)
                    MetricTile(title: "Clicks", value: todayMetrics.mouseClickCount, icon: "cursorarrow.click", color: .red)
                    MetricTile(title: "Scroll (100s)", value: todayMetrics.scrollTicks / 100, icon: "arrow.up.arrow.down", color: .green)
                    MetricTile(title: "Mouse (1000px)", value: Int(todayMetrics.mouseDistance / 1_000), icon: "arrow.up.left.and.arrow.down.right", color: .orange)
                    MetricTile(title: "KUI", value: Int(kuiValue.rounded()), icon: "chart.bar.fill", color: .purple)
                }

                Text("Scroll ticks in 100s, mouse distance in 1000s of pixels.")
                    .font(.system(size: 11))
                    .foregroundColor(.secondary)
            }
            .padding(.horizontal, 24)
            .padding(.bottom, 24)
            .padding(.top, 8)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }
}

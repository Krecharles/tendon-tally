import SwiftUI

struct KUITabView: View {
    @ObservedObject var viewModel: MetricsViewModel

    private var todayMetrics: AggregatedMetrics {
        viewModel.todayMetrics()
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                Text("KUI")
                    .font(.system(size: 28, weight: .bold))
                    .foregroundColor(.primary)

                Text("The Key Usage Indicator combines your input metrics into a single score. Adjust the weights to prioritise what matters to you.")
                    .font(.system(size: 12))
                    .foregroundColor(.secondary)
                    .fixedSize(horizontal: false, vertical: true)

                weightsSection

                totalSection
            }
            .padding(.horizontal, 24)
            .padding(.bottom, 24)
            .padding(.top, 8)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .onTapGesture {
            NSApp.keyWindow?.makeFirstResponder(nil)
        }
    }

    private var weightsSection: some View {
        let keysValue = todayMetrics.keyPressCount
        let clicksValue = todayMetrics.mouseClickCount
        let scrollValue = todayMetrics.scrollTicks / 100
        let mouseValue = Int(todayMetrics.mouseDistance / 1_000)

        return VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("Metric")
                    .frame(maxWidth: .infinity, alignment: .leading)
                Text("Weight")
                    .frame(width: 110, alignment: .center)
                Text("Score")
                    .frame(width: 70, alignment: .trailing)
            }
            .font(.system(size: 10, weight: .semibold))
            .foregroundColor(.secondary)
            .textCase(.uppercase)
            .tracking(0.5)
            .padding(.horizontal, 14)

            VStack(spacing: 6) {
                KUIWeightRow(
                    title: "Keys",
                    icon: "keyboard.fill",
                    color: .blue,
                    currentValue: keysValue,
                    contribution: Double(keysValue) * viewModel.kuiConfig.keysWeight,
                    weight: $viewModel.kuiConfig.keysWeight
                )
                KUIWeightRow(
                    title: "Clicks",
                    icon: "cursorarrow.click",
                    color: .red,
                    currentValue: clicksValue,
                    contribution: Double(clicksValue) * viewModel.kuiConfig.clicksWeight,
                    weight: $viewModel.kuiConfig.clicksWeight
                )
                KUIWeightRow(
                    title: "Scroll (per 100)",
                    icon: "arrow.up.arrow.down",
                    color: .green,
                    currentValue: scrollValue,
                    contribution: Double(scrollValue) * viewModel.kuiConfig.scrollTicksWeight,
                    weight: $viewModel.kuiConfig.scrollTicksWeight
                )
                KUIWeightRow(
                    title: "Mouse (per 1000px)",
                    icon: "arrow.up.left.and.arrow.down.right",
                    color: .orange,
                    currentValue: mouseValue,
                    contribution: Double(mouseValue) * viewModel.kuiConfig.mouseDistanceWeight,
                    weight: $viewModel.kuiConfig.mouseDistanceWeight
                )
            }
        }
        .frame(maxWidth: 560)
    }

    private var totalSection: some View {
        let totalKUI = viewModel.kuiConfig.apply(to: todayMetrics)

        return HStack(spacing: 10) {
            Image(systemName: "chart.bar.fill")
                .font(.system(size: 13))
                .foregroundColor(.purple)
                .frame(width: 26, height: 26)
                .background(Color.purple.opacity(0.12))
                .clipShape(RoundedRectangle(cornerRadius: 7))

            Text("Total KUI")
                .font(.system(size: 14, weight: .semibold))
                .foregroundColor(.primary)

            Spacer()

            Text(String(format: "%.1f", totalKUI))
                .font(.system(size: 20, weight: .bold, design: .rounded))
                .foregroundColor(.purple)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
        .frame(maxWidth: 560)
        .background(Color.purple.opacity(0.08))
        .clipShape(RoundedRectangle(cornerRadius: 10))
        .overlay(
            RoundedRectangle(cornerRadius: 10)
                .stroke(Color.purple.opacity(0.2), lineWidth: 1)
        )
    }
}

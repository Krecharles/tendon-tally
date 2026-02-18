import SwiftUI
import AppKit

struct TotalCalculationTabView: View {
    @ObservedObject var viewModel: MetricsViewModel

    private var todayMetrics: AggregatedMetrics {
        viewModel.todayMetrics()
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                Text("Total")
                    .font(.system(size: 28, weight: .bold))
                    .foregroundColor(.primary)

                explanationCard

                advancedToggleCard

                if viewModel.advancedTotalCalculationEnabled {
                    weightsSection
                }

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

    private var explanationCard: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                Image(systemName: "info.circle.fill")
                    .font(.system(size: 12))
                    .foregroundColor(.blue)
                Text("How Total Is Calculated")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundColor(.primary)
            }

            Text("By default, Total is a simple sum of Keys, Clicks, Scroll, and Mouse. Advanced mode lets you set custom weights so Total can reflect what is harder on your body, like giving Scroll more impact than Keys if scrolling is more painful for you.")
                .font(.system(size: 12))
                .foregroundColor(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
        .frame(maxWidth: 560, alignment: .leading)
        .background(Color(NSColor.controlBackgroundColor))
        .clipShape(RoundedRectangle(cornerRadius: 10))
        .overlay(
            RoundedRectangle(cornerRadius: 10)
                .stroke(Color(NSColor.separatorColor).opacity(0.4), lineWidth: 1)
        )
    }

    private var advancedToggleCard: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("Enable Advanced Total Calculation")
                    .font(.system(size: 13, weight: .medium))
                    .foregroundColor(.primary)

                Spacer()

                Toggle("", isOn: $viewModel.advancedTotalCalculationEnabled)
                    .labelsHidden()
                    .toggleStyle(.switch)
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
        .frame(maxWidth: 560, alignment: .leading)
        .background(Color(NSColor.controlBackgroundColor))
        .clipShape(RoundedRectangle(cornerRadius: 10))
        .overlay(
            RoundedRectangle(cornerRadius: 10)
                .stroke(Color(NSColor.separatorColor).opacity(0.4), lineWidth: 1)
        )
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
                Text("Contribution")
                    .frame(width: 70, alignment: .trailing)
            }
            .font(.system(size: 10, weight: .semibold))
            .foregroundColor(.secondary)
            .textCase(.uppercase)
            .tracking(0.5)
            .padding(.horizontal, 14)

            VStack(spacing: 6) {
                TotalWeightRow(
                    title: "Keys",
                    icon: "keyboard.fill",
                    color: .blue,
                    currentValue: keysValue,
                    contribution: Double(keysValue) * viewModel.totalConfig.keysWeight,
                    weight: $viewModel.totalConfig.keysWeight
                )
                TotalWeightRow(
                    title: "Clicks",
                    icon: "cursorarrow.click",
                    color: .red,
                    currentValue: clicksValue,
                    contribution: Double(clicksValue) * viewModel.totalConfig.clicksWeight,
                    weight: $viewModel.totalConfig.clicksWeight
                )
                TotalWeightRow(
                    title: "Scroll (per 100)",
                    icon: "arrow.up.arrow.down",
                    color: .green,
                    currentValue: scrollValue,
                    contribution: Double(scrollValue) * viewModel.totalConfig.scrollTicksWeight,
                    weight: $viewModel.totalConfig.scrollTicksWeight
                )
                TotalWeightRow(
                    title: "Mouse (per 1000px)",
                    icon: "arrow.up.left.and.arrow.down.right",
                    color: .orange,
                    currentValue: mouseValue,
                    contribution: Double(mouseValue) * viewModel.totalConfig.mouseDistanceWeight,
                    weight: $viewModel.totalConfig.mouseDistanceWeight
                )
            }
        }
        .frame(maxWidth: 560)
    }

    private var totalSection: some View {
        let totalValue = viewModel.totalValue(for: todayMetrics)

        return HStack(spacing: 10) {
            Image(systemName: "chart.bar.fill")
                .font(.system(size: 13))
                .foregroundColor(.purple)
                .frame(width: 26, height: 26)
                .background(Color.purple.opacity(0.12))
                .clipShape(RoundedRectangle(cornerRadius: 7))

            Text("Today's Total")
                .font(.system(size: 14, weight: .semibold))
                .foregroundColor(.primary)

            Spacer()

            Text(String(format: "%.1f", totalValue))
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

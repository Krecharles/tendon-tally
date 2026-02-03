import SwiftUI
import AppKit

struct DashboardView: View {
    @ObservedObject var viewModel: MetricsViewModel

    var body: some View {
        VStack(alignment: .leading, spacing: 24) {
            // Custom Title Bar Area
            VStack(alignment: .leading, spacing: 4) {
                Text("Today")
                    .font(.system(size: 28, weight: .bold))
                    .foregroundColor(.primary)
            }
            
            // Today's Totals
            todayTotalsSection
            
            permissionBannerIfNeeded
        }
        .padding(24)
        .frame(width: 400)
    }
    

    @ViewBuilder
    private var permissionBannerIfNeeded: some View {
        if let message = viewModel.permissionIssueMessage {
            HStack(alignment: .top, spacing: 12) {
                Image(systemName: "exclamationmark.triangle.fill")
                    .font(.system(size: 18))
                    .foregroundColor(.red)
                
                VStack(alignment: .leading, spacing: 4) {
                    Text("Permissions Required")
                        .font(.system(size: 14, weight: .semibold))
                    Text("\(message) Open System Settings → Privacy & Security → Accessibility / Input Monitoring and enable this app.")
                        .font(.system(size: 12))
                        .lineLimit(nil)
                        .multilineTextAlignment(.leading)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            .padding(16)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Color.red.opacity(0.1))
            .clipShape(RoundedRectangle(cornerRadius: 12))
        } else {
            EmptyView()
        }
    }

    private var todayTotalsSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Grid(alignment: .leading, horizontalSpacing: 12, verticalSpacing: 12) {
                // First row: 2 items
                GridRow {
                    metricTotalTile(title: "Keys", value: viewModel.todayTotals.keyPressCount, icon: "keyboard.fill", color: .blue)
                    metricTotalTile(title: "Clicks", value: viewModel.todayTotals.mouseClickCount, icon: "cursorarrow.click", color: .red)
                }
                // Second row: 2 items
                GridRow {
                    metricTotalTile(title: "Scroll ticks (100s)", value: viewModel.todayTotals.scrollTicks / 100, icon: "arrow.up.arrow.down", color: .green)
                    metricTotalTile(title: "Mouse pixels (1000s)", value: Int(viewModel.todayTotals.mouseDistance / 1_000), icon: "arrow.up.left.and.arrow.down.right", color: .orange)
                }
                // Third row: Total tile (same size as others)
                GridRow {
                    let total = viewModel.todayTotals.keyPressCount + 
                               viewModel.todayTotals.mouseClickCount + 
                               viewModel.todayTotals.scrollTicks / 100 + 
                               Int(viewModel.todayTotals.mouseDistance / 1_000)
                    metricTotalTile(title: "Total", value: total, icon: "chart.bar.fill", color: .purple)
                    Rectangle().fill(Color.clear).frame(height: 0) // Empty cell to keep grid alignment
                }
            }
        }
    }
    
    private func metricTotalTile(title: String, value: Int, icon: String, color: Color) -> some View {
        HStack(spacing: 12) {
            Image(systemName: icon)
                .font(.system(size: 20))
                .foregroundColor(color)
                .frame(width: 32, height: 32)
                .background(color.opacity(0.1))
                .clipShape(RoundedRectangle(cornerRadius: 8))
            
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.system(size: 12))
                    .foregroundColor(.secondary)
                Text("\(value)")
                    .font(.system(size: 18, weight: .semibold, design: .monospaced))
                    .foregroundColor(.primary)
            }
            
            Spacer()
        }
        .padding(12)
        .background(Color(NSColor.controlBackgroundColor))
        .clipShape(RoundedRectangle(cornerRadius: 12))
    }

}

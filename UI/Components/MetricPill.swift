import SwiftUI

struct MetricPill: View {
    let title: String
    let metricType: MetricType?
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 5) {
                Circle()
                    .fill(isSelected ? pillColor : pillColor.opacity(0.4))
                    .frame(width: 8, height: 8)

                Text(title)
                    .font(.system(size: 11, weight: isSelected ? .medium : .regular))
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .background(
                RoundedRectangle(cornerRadius: 6)
                    .fill(isSelected ? pillColor.opacity(0.12) : Color.clear)
            )
            .foregroundColor(isSelected ? .primary : .secondary)
            .overlay(
                RoundedRectangle(cornerRadius: 6)
                    .stroke(isSelected ? pillColor.opacity(0.3) : Color(NSColor.separatorColor).opacity(0.5), lineWidth: 1)
            )
        }
        .buttonStyle(.plain)
    }

    private var pillColor: Color {
        metricType?.color ?? .purple
    }
}

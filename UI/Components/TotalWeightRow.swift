import SwiftUI

struct TotalWeightRow: View {
    let title: String
    let icon: String
    let color: Color
    let currentValue: Int
    let contribution: Double
    @Binding var weight: Double

    @State private var textValue: String = ""
    @State private var isInvalid: Bool = false
    @FocusState private var isFieldFocused: Bool

    var body: some View {
        HStack(spacing: 0) {
            // Metric info
            HStack(spacing: 10) {
                Image(systemName: icon)
                    .font(.system(size: 12))
                    .foregroundColor(color)
                    .frame(width: 24, height: 24)
                    .background(color.opacity(0.12))
                    .clipShape(RoundedRectangle(cornerRadius: 6))

                VStack(alignment: .leading, spacing: 2) {
                    Text(title)
                        .font(.system(size: 13, weight: .medium))
                        .foregroundColor(.primary)
                    Text("\(currentValue) today")
                        .font(.system(size: 11))
                        .foregroundColor(.secondary)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            // Weight control
            HStack(spacing: 4) {
                TextField("0", text: $textValue)
                    .frame(width: 50)
                    .textFieldStyle(.roundedBorder)
                    .font(.system(size: 12, design: .monospaced))
                    .foregroundColor(isInvalid ? .red : .primary)
                    .multilineTextAlignment(.center)
                    .focused($isFieldFocused)
                    .onSubmit { applyTextChange() }
                    .onChange(of: isFieldFocused) { _, focused in
                        if !focused { applyTextChange() }
                    }
                    .onChange(of: textValue) { _, _ in
                        validateText()
                    }
                    .onAppear {
                        textValue = formatted(weight)
                    }

                Stepper("", value: $weight, in: -1000...1000, step: 0.5)
                    .labelsHidden()
                    .controlSize(.small)
                    .onChange(of: weight) { _, newValue in
                        textValue = formatted(newValue)
                        isInvalid = false
                    }
            }

            // Contribution
            Text(String(format: "%.1f", contribution))
                .font(.system(size: 14, weight: .semibold, design: .monospaced))
                .foregroundColor(.primary)
                .frame(width: 70, alignment: .trailing)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .background(Color(NSColor.controlBackgroundColor))
        .clipShape(RoundedRectangle(cornerRadius: 10))
        .overlay(
            RoundedRectangle(cornerRadius: 10)
                .stroke(Color(NSColor.separatorColor).opacity(0.4), lineWidth: 1)
        )
    }

    private func formatted(_ value: Double) -> String {
        if value == floor(value) {
            return String(format: "%.0f", value)
        } else {
            return String(format: "%.2f", value)
        }
    }

    private func validateText() {
        isInvalid = Double(textValue) == nil
    }

    private func applyTextChange() {
        if let newValue = Double(textValue) {
            let clamped = max(-10_000, min(10_000, newValue))
            weight = clamped
            textValue = formatted(clamped)
            isInvalid = false
        } else {
            textValue = formatted(weight)
            isInvalid = true
        }
    }
}

import SwiftUI

struct KUIWeightRow: View {
    let title: String
    let icon: String
    let color: Color
    let currentValue: Int
    let contribution: Double
    @Binding var weight: Double
    let showLeadingPlus: Bool

    @State private var textValue: String = ""
    @State private var isInvalid: Bool = false

    var body: some View {
        HStack(alignment: .center, spacing: 12) {
            Text(showLeadingPlus ? "+" : " ")
                .font(.system(size: 20, weight: .semibold))
                .frame(width: 20, alignment: .center)
                .foregroundColor(.primary)

            HStack(spacing: 8) {
                Image(systemName: icon)
                    .font(.system(size: 16))
                    .foregroundColor(color)
                    .frame(width: 24, height: 24)
                    .background(color.opacity(0.12))
                    .clipShape(RoundedRectangle(cornerRadius: 6))

                VStack(alignment: .leading, spacing: 2) {
                    Text(title)
                        .font(.subheadline)
                    Text("\(currentValue)")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
            }

            Spacer()

            HStack(spacing: 6) {
                Text("\u{00D7}")
                    .font(.system(size: 20, weight: .semibold))
                    .foregroundColor(.primary)

                TextField("0.0", text: $textValue, onCommit: applyTextChange)
                    .frame(width: 70)
                    .textFieldStyle(.roundedBorder)
                    .foregroundColor(isInvalid ? .red : .primary)
                    .onChange(of: textValue) { _, _ in
                        validateText()
                    }
                    .onAppear {
                        textValue = formatted(weight)
                    }

                Stepper("", value: $weight, in: -1000...1000, step: 0.5)
                    .labelsHidden()
                    .onChange(of: weight) { _, newValue in
                        textValue = formatted(newValue)
                        isInvalid = false
                    }

                Spacer()

                Text("=")
                    .font(.system(size: 20, weight: .semibold))
                    .foregroundColor(.primary)

                Text(String(format: "%.1f", contribution))
                    .font(.system(size: 14, weight: .semibold, design: .monospaced))
                    .frame(width: 70, alignment: .trailing)
            }
            .frame(width: 260, alignment: .center)
        }
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

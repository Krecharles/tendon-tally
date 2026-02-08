import SwiftUI

struct PermissionBanner: View {
    let message: String

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: "exclamationmark.triangle.fill")
                .font(.system(size: 18))
                .foregroundColor(.red)

            VStack(alignment: .leading, spacing: 4) {
                Text("Permissions Required")
                    .font(.system(size: 14, weight: .semibold))
                Text("\(message) Open System Settings \u{2192} Privacy & Security \u{2192} Accessibility / Input Monitoring and enable this app.")
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
    }
}

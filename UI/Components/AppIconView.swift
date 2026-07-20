import SwiftUI

struct AppIconView: View {
    let size: CGFloat

    private var assetName: String {
        size <= 32 ? "LiquidGlassAppIconSmall" : "LiquidGlassAppIcon"
    }

    var body: some View {
        Image(assetName, bundle: .appResources)
            .resizable()
            .interpolation(.high)
            .aspectRatio(contentMode: .fit)
            .frame(width: size, height: size)
            .accessibilityHidden(true)
    }
}

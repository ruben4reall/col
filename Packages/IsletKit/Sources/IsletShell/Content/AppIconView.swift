import IsletCore
import SwiftUI

/// An app's own icon, as the Dock shows it. When the app is not on this Mac, its symbol on a tile in its colour, drawn
/// to the same grid as app icons so that rows line up either way.
struct AppIconView: View {
    let icon: AppIcon
    var size: CGFloat = 28
    @Environment(\.displayScale) private var scale

    var body: some View {
        if let image = AppIcons.image(for: icon, side: size, scale: scale) {
            Image(decorative: image, scale: scale)
                .resizable()
                .interpolation(.high)
                .frame(width: size, height: size)
        } else {
            // App icons fill about 80% of their square, with corners of about a fifth of their side.
            RoundedRectangle(cornerRadius: size * 0.18, style: .continuous)
                .fill(LinearGradient(colors: [icon.tint.lightened(0.22).color, icon.tint.color], startPoint: .top, endPoint: .bottom))
                .overlay {
                    Image(systemName: icon.symbol)
                        .font(.system(size: size * 0.38, weight: .semibold))
                        .foregroundStyle(.white)
                }
                .padding(size * 0.1)
                .frame(width: size, height: size)
        }
    }
}

extension RGBA {
    /// The colour mixed with white, for the light side of a gradient.
    func lightened(_ amount: Double) -> RGBA {
        RGBA(red: red + (1 - red) * amount, green: green + (1 - green) * amount, blue: blue + (1 - blue) * amount, alpha: alpha)
    }
}

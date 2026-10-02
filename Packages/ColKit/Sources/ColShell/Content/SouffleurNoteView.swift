import ColCore
import SwiftUI

/// What the island says the first time Col closes Souffleur: the prompter's former app, shown with its own icon, is
/// part of Col now and can go to the Trash.
struct SouffleurNoteView: View {
    private static let icon = AppIcon(bundleIdentifiers: [Souffleur.bundleIdentifier], name: "Souffleur", symbol: "text.aligncenter", tint: .orange)

    var body: some View {
        HStack(spacing: 18) {
            AppIconView(icon: Self.icon, size: 64)
            VStack(alignment: .leading, spacing: 4) {
                Text("Souffleur is now part of Col", bundle: .module)
                    .font(.system(size: 17, weight: .semibold))
                    .foregroundStyle(.white)
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
                Text("Col closed it, so your shortcuts drive only one prompter. Souffleur can go to the Trash.", bundle: .module)
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(Theme.secondaryText)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 8)
        .frame(maxHeight: .infinity)
    }
}

import AppKit
import SwiftUI

/// What the island shows once after Col updates to a new major version: the version's name and what it brings, in a
/// row of tiles that arrive one after the other, with a link to the full list.
struct WhatsNewView: View {
    struct Item: Identifiable {
        let symbol: String
        let tint: Color
        let title: LocalizedStringKey
        var id: String { symbol }
    }

    /// Col 3.2, in five tiles.
    static let items: [Item] = [
        Item(symbol: "sparkles", tint: .purple, title: "An intro when Col opens"),
        Item(symbol: "menubar.rectangle", tint: .indigo, title: "Drawers, redrawn"),
        Item(symbol: "rectangle.topthird.inset.filled", tint: .teal, title: "Your menu bar in the island"),
        Item(symbol: "wrench.and.screwdriver.fill", tint: .orange, title: "Fixes all around"),
        Item(symbol: "pc", tint: .green, title: "On Windows and Linux too"),
    ]

    static let releaseURL = URL(string: "https://github.com/ruben4reall/col/releases/tag/v3.2.0")!
    @State private var drawers = MenuBarDrawers.shared

    @State private var shown = false
    private var still: Bool { NSWorkspace.shared.accessibilityDisplayShouldReduceMotion }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .firstTextBaseline) {
                Text("What’s new in Col 3.2", bundle: .module)
                    .font(.system(size: 17, weight: .semibold))
                    .foregroundStyle(.white)
                Spacer(minLength: 8)
                // The drawers are this version's news: one click turns them on.
                if drawers.isSupportedHere, drawers.status == .off {
                    Button {
                        drawers.setEnabled(true)
                        IslandController.shared?.closeIsland()
                    } label: {
                        Text("Tidy My Menu Bar", bundle: .module)
                    }
                    .buttonStyle(IslandCapsuleStyle())
                }
                Link(destination: Self.releaseURL) {
                    HStack(spacing: 3) {
                        Text("See Everything", bundle: .module)
                        Image(systemName: "chevron.right").font(.system(size: 10, weight: .bold))
                    }
                    .font(Theme.Font.body)
                    .foregroundStyle(Theme.accent)
                }
                .buttonStyle(.plain)
            }
            HStack(spacing: 8) {
                ForEach(Array(Self.items.enumerated()), id: \.element.id) { index, item in
                    tile(item)
                        .opacity(shown ? 1 : 0)
                        .scaleEffect(shown || still ? 1 : 0.86)
                        .offset(y: shown || still ? 0 : 8)
                        .animation(still ? .easeOut(duration: 0.2) : .spring(duration: 0.5, bounce: 0.25).delay(0.08 * Double(index) + 0.15), value: shown)
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .onAppear { shown = true }
        .onDisappear { shown = false }
    }

    private func tile(_ item: Item) -> some View {
        VStack(spacing: 5) {
            Image(systemName: item.symbol)
                .font(.system(size: 19, weight: .semibold))
                .foregroundStyle(item.tint)
                .frame(height: 22)
            Text(item.title, bundle: .module)
                .font(.system(size: 10.5, weight: .semibold))
                .foregroundStyle(.white)
                .multilineTextAlignment(.center)
                // Some languages need three lines for a title: the tile keeps them whole rather than cut them.
                .lineLimit(3)
                .minimumScaleFactor(0.8)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(.horizontal, 6)
        .frame(maxWidth: .infinity, minHeight: 72, maxHeight: .infinity)
        .background(RoundedRectangle(cornerRadius: Theme.innerRadius + 4, style: .continuous).fill(Theme.fill))
    }
}

/// Remembers which edition the island last introduced: a major version, or a minor one that brings something worth
/// a card (3.2).
@MainActor
enum WhatsNew {
    private static let majorKey = "whatsNewShownForMajor"
    private static let editionKey = "whatsNewShownForEdition"
    /// The edition the card describes.
    static let edition = "3.2"

    /// The major version of the running app.
    static var currentMajor: Int {
        let version = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "0"
        return Int(version.split(separator: ".").first ?? "0") ?? 0
    }

    /// Due once per edition, for someone who already used an earlier one (the island asks only once the welcome is
    /// done): a new install has the welcome instead, which marks the edition as introduced. Col 3.0 and 3.1 noted only
    /// the major version they introduced, so they never saw this edition.
    static var isDue: Bool {
        guard currentMajor >= 3 else { return false }
        guard let shown = UserDefaults.standard.string(forKey: editionKey) else { return true }
        return shown.compare(edition, options: .numeric) == .orderedAscending
    }

    static func markShown() {
        UserDefaults.standard.set(currentMajor, forKey: majorKey)
        UserDefaults.standard.set(edition, forKey: editionKey)
    }
}

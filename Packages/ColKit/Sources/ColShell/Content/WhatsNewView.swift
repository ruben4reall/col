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

    /// Col 3, in five tiles.
    static let items: [Item] = [
        Item(symbol: "capsule.fill", tint: .indigo, title: "A pill on every Mac"),
        Item(symbol: "quote.bubble.fill", tint: .pink, title: "Lyrics on the Lock Screen"),
        Item(symbol: "cloud.sun.fill", tint: .cyan, title: "Weather and Focus"),
        Item(symbol: "dot.radiowaves.up.forward", tint: .orange, title: "Col Connect"),
        Item(symbol: "pc", tint: .green, title: "On Windows and Linux"),
    ]

    static let releaseURL = URL(string: "https://github.com/ruben4reall/col/releases/tag/v3.0.0")!

    @State private var shown = false
    private var still: Bool { NSWorkspace.shared.accessibilityDisplayShouldReduceMotion }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .firstTextBaseline) {
                Text("What’s new in Col 3", bundle: .module)
                    .font(.system(size: 17, weight: .semibold))
                    .foregroundStyle(.white)
                Spacer(minLength: 8)
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
        VStack(spacing: 7) {
            Image(systemName: item.symbol)
                .font(.system(size: 19, weight: .semibold))
                .foregroundStyle(item.tint)
                .frame(height: 22)
            Text(item.title, bundle: .module)
                .font(.system(size: 10.5, weight: .semibold))
                .foregroundStyle(.white)
                .multilineTextAlignment(.center)
                .lineLimit(2)
                .minimumScaleFactor(0.85)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(.horizontal, 6)
        .frame(maxWidth: .infinity, minHeight: 72, maxHeight: .infinity)
        .background(RoundedRectangle(cornerRadius: Theme.innerRadius + 4, style: .continuous).fill(Theme.fill))
    }
}

/// Remembers which major version the island last introduced.
@MainActor
enum WhatsNew {
    private static let key = "whatsNewShownForMajor"

    /// The major version of the running app.
    static var currentMajor: Int {
        let version = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "0"
        return Int(version.split(separator: ".").first ?? "0") ?? 0
    }

    /// Due once per major version from 3 on, for someone who already used an earlier one: a new install has the
    /// welcome instead, and marks the version as introduced.
    static var isDue: Bool {
        currentMajor >= 3 && UserDefaults.standard.integer(forKey: key) < currentMajor
    }

    static func markShown() {
        UserDefaults.standard.set(currentMajor, forKey: key)
    }
}

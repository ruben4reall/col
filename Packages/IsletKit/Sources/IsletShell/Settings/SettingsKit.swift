import AppKit
import IsletCore
import SwiftUI

/// The pieces every settings pane is built from, so all panes read alike: a fixed header, then a grouped form that
/// scrolls under nothing.

/// A pane: its header stays put and the form scrolls below it. A hairline appears under the header once the form has
/// scrolled, the way a toolbar separates itself from content in macOS.
struct PaneScaffold<Content: View>: View {
    let pane: SettingsPane
    @ViewBuilder let content: () -> Content
    @State private var scrolled = false

    var body: some View {
        VStack(spacing: 0) {
            PaneHeader(pane: pane)
            Rectangle()
                .fill(Color.primary.opacity(0.1))
                .frame(height: 1)
                .opacity(scrolled ? 1 : 0)
                .animation(.easeOut(duration: 0.15), value: scrolled)
            Form { content() }
                .formStyle(.grouped)
                .contentMargins(.top, 2, for: .scrollContent)
                .modifier(ScrollReport(scrolled: $scrolled))
        }
    }
}

/// Reports whether a scroll view has left its top. macOS 15 and later; earlier, the hairline simply stays hidden.
private struct ScrollReport: ViewModifier {
    @Binding var scrolled: Bool

    func body(content: Content) -> some View {
        if #available(macOS 15.0, *) {
            content.onScrollGeometryChange(for: Bool.self) { geometry in
                geometry.contentOffset.y + geometry.contentInsets.top > 2
            } action: { _, value in
                scrolled = value
            }
        } else {
            content
        }
    }
}

/// The icon, the name and one sentence about the pane.
struct PaneHeader: View {
    let pane: SettingsPane

    var body: some View {
        HStack(spacing: 14) {
            IconTile(symbol: pane.symbol, tint: pane.tint, size: 38)
            VStack(alignment: .leading, spacing: 2) {
                Text(pane.title)
                    .font(.system(size: 19, weight: .bold))
                Text(pane.summary)
                    .font(.system(size: 12.5))
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 28)
        .padding(.top, 10)
        .padding(.bottom, 14)
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

/// A white symbol on a rounded square of colour, as System Settings draws its panes.
struct IconTile: View {
    let symbol: String
    let tint: Color
    var size: CGFloat = 26

    var body: some View {
        Image(systemName: symbol)
            .font(.system(size: size * 0.46, weight: .semibold))
            .foregroundStyle(.white)
            .frame(width: size, height: size)
            .background(RoundedRectangle(cornerRadius: size * 0.27, style: .continuous).fill(tint.gradient))
    }
}

/// An app's own icon, or a tile when the app is not on this Mac.
struct AppIconTile: View {
    let icon: AppIcon
    var size: CGFloat = 28
    @Environment(\.displayScale) private var scale

    var body: some View {
        // App icons keep a margin around their tile: drawn a little larger, they line up with the settings' tiles.
        if let image = AppIcons.image(for: icon, side: size + 4, scale: scale) {
            Image(decorative: image, scale: scale)
                .resizable()
                .interpolation(.high)
                .frame(width: size + 4, height: size + 4)
                .padding(-2)
        } else {
            IconTile(symbol: icon.symbol, tint: icon.tint.color, size: size)
        }
    }
}

/// A switch with an icon, a name and a line saying what it does.
struct IconToggle: View {
    let symbol: String
    let tint: Color
    let title: LocalizedStringKey
    var detail: LocalizedStringKey?
    @Binding var isOn: Bool

    var body: some View {
        Toggle(isOn: $isOn) {
            HStack(spacing: 12) {
                IconTile(symbol: symbol, tint: tint)
                VStack(alignment: .leading, spacing: 1) {
                    Text(title, bundle: .module)
                    if let detail {
                        Text(detail, bundle: .module)
                            .font(.callout)
                            .foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
            }
        }
    }
}

/// A row with an icon and a description, and any control on the right.
struct IconRow<Accessory: View>: View {
    let symbol: String
    let tint: Color
    let title: Text
    var detail: Text?
    @ViewBuilder var accessory: () -> Accessory

    var body: some View {
        HStack(spacing: 12) {
            IconTile(symbol: symbol, tint: tint)
            VStack(alignment: .leading, spacing: 1) {
                title
                if let detail {
                    detail
                        .font(.callout)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            Spacer(minLength: 12)
            accessory()
        }
    }
}

/// Keys drawn as key caps: ⌃ ⌥ ⌘ I.
struct KeyCaps: View {
    let keys: [String]

    var body: some View {
        HStack(spacing: 3) {
            ForEach(Array(keys.enumerated()), id: \.offset) { _, key in
                Text(key)
                    .font(.system(size: 12, weight: .medium, design: .rounded))
                    .frame(minWidth: 22, minHeight: 22)
                    .padding(.horizontal, key.count > 1 ? 6 : 0)
                    .background(
                        RoundedRectangle(cornerRadius: 5, style: .continuous)
                            .fill(Color.primary.opacity(0.06))
                            .shadow(color: .black.opacity(0.18), radius: 0, y: 1)
                    )
                    .overlay(RoundedRectangle(cornerRadius: 5, style: .continuous).strokeBorder(Color.primary.opacity(0.12)))
            }
        }
    }
}

/// "Allowed" in green, or the button that asks.
struct PermissionBadge: View {
    let granted: Bool
    var label: LocalizedStringKey = "Allow…"
    let action: () -> Void

    var body: some View {
        if granted {
            Label { Text("Allowed", bundle: .module) } icon: { Image(systemName: "checkmark.circle.fill") }
                .foregroundStyle(.green)
                .font(.callout.weight(.medium))
                .fixedSize()
        } else {
            Button(action: action) { Text(label, bundle: .module) }
        }
    }
}

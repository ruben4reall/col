import AppKit
import SwiftUI
import TiroirCore

/// A card on the dark windows: a faint fill and a hairline edge.
public struct CardBackground: ViewModifier {
    var radius: CGFloat = Theme.cardRadius

    public func body(content: Content) -> some View {
        content
            .background(Theme.cardFill, in: RoundedRectangle(cornerRadius: radius, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: radius, style: .continuous).strokeBorder(Theme.cardStroke))
    }
}

extension View {
    public func card(radius: CGFloat = Theme.cardRadius) -> some View {
        modifier(CardBackground(radius: radius))
    }
}

/// A capsule button: white for the main action (the way Pli and Islet do it), glass for the others.
public struct PillButtonStyle: ButtonStyle {
    public enum Kind { case primary, secondary, destructive }
    var kind: Kind

    public init(_ kind: Kind = .secondary) { self.kind = kind }

    public func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 13, weight: .semibold))
            .padding(.horizontal, 16)
            .frame(height: 30)
            .foregroundStyle(foreground)
            .background(background, in: Capsule())
            .overlay(Capsule().strokeBorder(Color.white.opacity(kind == .primary ? 0 : 0.12)))
            .opacity(configuration.isPressed ? 0.78 : 1)
            .contentShape(Capsule())
    }

    private var foreground: Color {
        switch kind {
        case .primary: Color(Theme.night)
        case .secondary: Theme.text
        case .destructive: Color(red: 1, green: 0.42, blue: 0.38)
        }
    }

    private var background: Color {
        switch kind {
        case .primary: Color(Theme.rice)
        case .secondary, .destructive: Color.white.opacity(0.08)
        }
    }
}

/// One icon in a drawer, search or the layout editor: the app's icon and its name.
public struct IconTile: View {
    let row: IconRow
    var size: CGFloat = 36
    var isSelected = false
    var showsSubtitle = true
    @State private var isHovering = false

    public init(row: IconRow, size: CGFloat = 36, isSelected: Bool = false, showsSubtitle: Bool = true) {
        self.row = row
        self.size = size
        self.isSelected = isSelected
        self.showsSubtitle = showsSubtitle
    }

    public var body: some View {
        VStack(spacing: 5) {
            Image(nsImage: row.appIcon)
                .resizable()
                .interpolation(.high)
                .frame(width: size, height: size)
                .shadow(color: .black.opacity(0.25), radius: 3, y: 1)
                .opacity(row.isRunning ? 1 : 0.45)
            Text(verbatim: row.name)
                .font(.system(size: 11, weight: .medium))
                .lineLimit(1)
                .truncationMode(.tail)
                .foregroundStyle(.primary)
            if showsSubtitle, let subtitle = row.subtitle {
                Text(verbatim: subtitle)
                    .font(.system(size: 10))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
        }
        .frame(width: size + 44)
        .padding(.vertical, 8)
        .background(
            RoundedRectangle(cornerRadius: Theme.radius, style: .continuous)
                .fill(isSelected ? Theme.selection : (isHovering ? Theme.hover : .clear)))
        .overlay(
            RoundedRectangle(cornerRadius: Theme.radius, style: .continuous)
                .strokeBorder(isSelected ? Theme.accent.opacity(0.8) : .clear, lineWidth: 1.5))
        .contentShape(RoundedRectangle(cornerRadius: Theme.radius, style: .continuous))
        .onHover { isHovering = $0 }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text(verbatim: row.subtitle.map { "\(row.name), \($0)" } ?? row.name))
        .accessibilityAddTraits(.isButton)
    }
}

/// A small caption above a group of controls.
public struct SectionTitle: View {
    let text: String
    public init(_ text: String) { self.text = text }
    public var body: some View {
        Text(verbatim: text)
            .font(.system(size: 11, weight: .semibold))
            .foregroundStyle(Theme.tertiaryText)
            .textCase(.uppercase)
            .tracking(0.6)
    }
}

/// The last points of a scrolling area fade out, so a card cut by the edge reads as more to scroll, not as a mistake.
struct ScrollFade: View {
    var body: some View {
        VStack(spacing: 0) {
            Color.black
            LinearGradient(colors: [.black, .clear], startPoint: .top, endPoint: .bottom).frame(height: 28)
        }
    }
}

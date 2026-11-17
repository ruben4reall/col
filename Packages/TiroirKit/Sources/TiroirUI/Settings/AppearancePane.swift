import AppKit
import SwiftUI
import TiroirCore

/// Settings, Appearance (spec 6.3): the shape Tiroir gives the menu bar, its tint, hairline and shadow, and a look of its
/// own for Dark Mode if the person wants one, with a live preview.
struct AppearancePane: View {
    @Bindable var model: InterfaceModel
    /// The look the controls edit while Dark Mode has its own.
    @State private var editing: Mode = .light
    /// A dark look turned off during this visit, so turning it back on brings it back.
    @State private var setAside: Appearance.Look?

    /// The system's appearance a look is for.
    enum Mode: Hashable { case light, dark }

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            TintPreview(shape: appearance.shape, look: look, isDark: appearance.darkLook == nil || isEditingDark,
                        marks: model.settings.layout.drawers.prefix(4).map(\.mark), hasNotch: model.hasNotch)
            SettingsGroup {
                SettingRow(title: Strings.shape, note: appearance.shape == .split ? Strings.splitNote : nil) {
                    // Names only: SwiftUI's segmented picker on macOS shows a segment's title or its picture, never
                    // both, and the preview above already draws the shape.
                    Picker(Strings.shape, selection: shape) {
                        ForEach(Appearance.Shape.allCases, id: \.self) { option in
                            Text(verbatim: Strings.shapeName(option)).tag(option)
                        }
                    }
                    .pickerStyle(.segmented)
                    .labelsHidden()
                    .fixedSize()
                }
            }
            SettingsGroup {
                SettingRow(title: Strings.differentLookInDarkMode) {
                    Toggle(Strings.differentLookInDarkMode, isOn: hasDarkLook).labelsHidden().toggleStyle(.switch)
                }
                if appearance.darkLook != nil {
                    SettingRow(title: Strings.look) {
                        Picker(Strings.look, selection: $editing) {
                            Text(verbatim: Strings.lightMode).tag(Mode.light)
                            Text(verbatim: Strings.darkMode).tag(Mode.dark)
                        }
                        .pickerStyle(.segmented)
                        .labelsHidden()
                        .fixedSize()
                    }
                }
                SettingRow(title: Strings.menuBarTint) {
                    Picker(Strings.menuBarTint, selection: binding(\.tint)) {
                        Text(verbatim: Strings.tintNone).tag(Appearance.Tint.none)
                        Text(verbatim: Strings.tintColor).tag(Appearance.Tint.color)
                        Text(verbatim: Strings.tintGradient).tag(Appearance.Tint.gradient)
                    }
                    .pickerStyle(.segmented)
                    .labelsHidden()
                    .fixedSize()
                }
                if look.tint != .none {
                    SettingRow(title: Strings.tintColor) {
                        ColorPicker(Strings.tintColor, selection: color(\.color), supportsOpacity: false).labelsHidden()
                    }
                    if look.tint == .gradient {
                        SettingRow(title: Strings.gradientEnd) {
                            ColorPicker(Strings.gradientEnd, selection: color(\.gradientEnd), supportsOpacity: false).labelsHidden()
                        }
                    }
                    SettingRow(title: Strings.strength) {
                        Slider(value: binding(\.opacity), in: 0.05...1)
                            .frame(width: 220)
                            .accessibilityLabel(Text(verbatim: Strings.strength))
                    }
                }
                SettingRow(title: Strings.hairlineBorder) {
                    Toggle(Strings.hairlineBorder, isOn: binding(\.border)).labelsHidden().toggleStyle(.switch)
                }
                SettingRow(title: Strings.softShadow) {
                    Toggle(Strings.softShadow, isOn: binding(\.shadow)).labelsHidden().toggleStyle(.switch)
                }
            }
            Text(verbatim: Strings.tintNote).font(.system(size: 11)).foregroundStyle(Theme.tertiaryText)
        }
        .onAppear {
            // With a look for each mode, the pane opens on the one the menu bar shows now.
            editing = TintOverlay.systemIsDark ? .dark : .light
        }
    }

    private var appearance: Appearance { model.settings.appearance }

    private var isEditingDark: Bool { editing == .dark && appearance.darkLook != nil }

    /// The look the controls show and edit.
    private var look: Appearance.Look { appearance.look(inDarkMode: isEditingDark) }

    private var shape: Binding<Appearance.Shape> {
        Binding(get: { appearance.shape }, set: { shape in model.update { $0.appearance.shape = shape } })
    }

    /// One value of the look being edited.
    private func binding<Value>(_ keyPath: WritableKeyPath<Appearance.Look, Value>) -> Binding<Value> {
        Binding(get: { look[keyPath: keyPath] }, set: { value in
            let dark = isEditingDark
            model.update { settings in
                if dark {
                    settings.appearance.darkLook?[keyPath: keyPath] = value
                } else {
                    settings.appearance.look[keyPath: keyPath] = value
                }
            }
        })
    }

    private func color(_ keyPath: WritableKeyPath<Appearance.Look, RGBA>) -> Binding<Color> {
        Binding(get: { Color(look[keyPath: keyPath]) }, set: { color in
            guard let rgb = NSColor(color).usingColorSpace(.sRGB) else { return }
            binding(keyPath).wrappedValue = RGBA(red: rgb.redComponent, green: rgb.greenComponent, blue: rgb.blueComponent)
        })
    }

    /// On, Dark Mode gets a look of its own, first the same as the main one, and the controls edit it. Off, the main
    /// look serves in both modes again.
    private var hasDarkLook: Binding<Bool> {
        Binding(get: { appearance.darkLook != nil }, set: { isOn in
            if isOn {
                let dark = setAside ?? appearance.look
                model.update { $0.appearance.darkLook = dark }
                editing = .dark
            } else {
                setAside = appearance.darkLook
                model.update { $0.appearance.darkLook = nil }
                editing = .light
            }
        })
    }
}

/// The menu bar in miniature over a desktop, dressed as it will be: the shape, and the tint, hairline and shadow of the
/// look being edited, over a dark desktop or, for the Light Mode look, a light one. The pieces come from the same
/// geometry as the real tint, measured on the miniature's menus and icons.
struct TintPreview: View {
    let shape: Appearance.Shape
    let look: Appearance.Look
    let isDark: Bool
    let marks: [DrawerMark]
    let hasNotch: Bool
    @State private var menusEnd: CGFloat?
    @State private var statusStart: CGFloat?

    static let barHeight: CGFloat = 30
    static let notchWidth: CGFloat = 110
    /// The widths of the app menus, drawn as bars: the app's name, then three menus.
    static let menuWidths: [CGFloat] = [30, 22, 26, 20]
    nonisolated private static let space = "tintPreview"

    var body: some View {
        GeometryReader { proxy in
            let pieces = pieces(width: proxy.size.width)
            ZStack(alignment: .top) {
                Canvas { context, size in draw(pieces, in: &context, size: size) }
                bar
                if hasNotch { notch }
            }
        }
        .coordinateSpace(.named(Self.space))
        .frame(height: 110)
        .background(desktop)
        .clipShape(RoundedRectangle(cornerRadius: Theme.cardRadius, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: Theme.cardRadius, style: .continuous).strokeBorder(Theme.cardStroke))
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text(verbatim: Strings.preview))
    }

    /// The pieces on a miniature screen as wide as the preview, its notch in the middle.
    private func pieces(width: CGFloat) -> TintGeometry.Pieces {
        let side = (width - Self.notchWidth) / 2
        return TintGeometry.pieces(
            for: shape, screen: CGRect(x: 0, y: 0, width: width, height: Self.barHeight), menuBarHeight: Self.barHeight,
            notchLeft: hasNotch ? CGRect(x: 0, y: 0, width: side, height: Self.barHeight) : nil,
            notchRight: hasNotch ? CGRect(x: width - side, y: 0, width: side, height: Self.barHeight) : nil,
            menusEnd: menusEnd, statusStart: statusStart)
    }

    /// The app menus on the left, the icons on the right, in the colors of the mode's menu bar.
    private var bar: some View {
        HStack(spacing: 12) {
            HStack(spacing: 12) {
                ForEach(Array(Self.menuWidths.enumerated()), id: \.offset) { index, width in
                    Capsule().frame(width: width, height: index == 0 ? 6 : 5).opacity(index == 0 ? 1 : 0.75)
                }
            }
            .padding(.leading, 16)
            .onGeometryChange(for: CGFloat.self) { $0.frame(in: .named(Self.space)).maxX } action: { menusEnd = $0 }
            Spacer(minLength: 0)
            HStack(spacing: 12) {
                ForEach(Array(marks.enumerated()), id: \.offset) { _, mark in MarkView(mark, size: 13) }
                Image(systemName: "wifi").font(.system(size: 12, weight: .semibold))
                Image(systemName: "battery.75percent").font(.system(size: 13))
                Text(verbatim: "9:41").font(.system(size: 12, weight: .semibold)).monospacedDigit()
            }
            .padding(.trailing, 14)
            .onGeometryChange(for: CGFloat.self) { $0.frame(in: .named(Self.space)).minX } action: { statusStart = $0 }
        }
        .foregroundStyle(isDark ? Color.white : Color.black.opacity(0.82))
        .frame(height: Self.barHeight)
    }

    private var notch: some View {
        UnevenRoundedRectangle(bottomLeadingRadius: 8, bottomTrailingRadius: 8, style: .continuous)
            .fill(Color.black)
            .frame(width: Self.notchWidth, height: Self.barHeight)
    }

    private var desktop: LinearGradient {
        isDark
            ? LinearGradient(colors: [Color(red: 0.36, green: 0.22, blue: 0.1), Color(red: 0.1, green: 0.07, blue: 0.05)],
                             startPoint: .topLeading, endPoint: .bottomTrailing)
            : LinearGradient(colors: [Color(red: 0.98, green: 0.9, blue: 0.77), Color(red: 0.87, green: 0.69, blue: 0.5)],
                             startPoint: .topLeading, endPoint: .bottomTrailing)
    }

    /// The tint as the overlay draws it: edge to edge with a hairline along the bottom and a shade below, or rounded
    /// pieces with the hairline and the shadow following them.
    private func draw(_ pieces: TintGeometry.Pieces, in context: inout GraphicsContext, size: CGSize) {
        guard let bar = pieces.rects.first else { return }
        let hairline = Color.white.opacity(0.18)
        let colors = [Color(look.color), Color(look.gradientEnd)].map { $0.opacity(look.opacity) }
        let tint: GraphicsContext.Shading? = switch look.tint {
        case .none: nil
        case .color: .color(colors[0])
        case .gradient: .linearGradient(Gradient(colors: colors), startPoint: .zero, endPoint: CGPoint(x: size.width, y: 0))
        }
        if pieces.shape == .full {
            if let tint { context.fill(Path(bar), with: tint) }
            if look.border { context.fill(Path(CGRect(x: bar.minX, y: bar.maxY - 1, width: bar.width, height: 1)), with: .color(hairline)) }
            if look.shadow {
                let shade = CGRect(x: bar.minX, y: bar.maxY, width: bar.width, height: 12)
                context.fill(Path(shade), with: .linearGradient(Gradient(colors: [Color.black.opacity(0.22), .clear]),
                                                                startPoint: CGPoint(x: 0, y: shade.minY), endPoint: CGPoint(x: 0, y: shade.maxY)))
            }
            return
        }
        let outline = pieces.outline()
        if look.shadow {
            // Around the pieces only, as on the menu bar.
            var shade = context
            var outside = Path(CGRect(origin: .zero, size: size))
            outside.addPath(outline)
            shade.clip(to: outside, style: FillStyle(eoFill: true))
            shade.addFilter(.shadow(color: .black.opacity(0.3), radius: 4, x: 0, y: 2))
            shade.fill(outline, with: .color(.black))
        }
        if let tint { context.fill(outline, with: tint) }
        if look.border { context.stroke(pieces.outline(inset: 0.5), with: .color(hairline), lineWidth: 1) }
    }
}

import AppKit
import SwiftUI

/// The outline of a drawer opened from the menu bar, the way Col's island hangs from the notch: a neck over the
/// drawer's own item, as tall as the menu bar, that flows into the panel below with two concave curves.
///
/// `progress` opens it: at 0 the panel has gone back into the neck, at 1 it has its full size. A spring may carry it a
/// little past 1, and the panel then swells a touch before it settles. With no neck (search), the panel floats under
/// the menu bar with four round corners.
@available(macOS 26, *)
struct DropShape: Shape {
    /// The drawer's item in the menu bar, in the shape's space; empty for a panel with no neck.
    var neck: CGRect
    /// The panel's frame once open, in the shape's space.
    var panel: CGRect
    var progress: CGFloat

    static let fillet: CGFloat = 9
    static let ear: CGFloat = 5
    static let topRadius: CGFloat = 18
    static let bottomRadius: CGFloat = 26

    var animatableData: CGFloat {
        get { progress }
        set { progress = newValue }
    }

    /// The panel's frame at `progress`: it grows out of the neck, wider and taller, its top edge kept in place.
    static func panelFrame(neck: CGRect, panel: CGRect, progress: CGFloat) -> CGRect {
        let p = max(progress, 0)
        let origin = neck.isEmpty ? CGRect(x: panel.midX - panel.width * 0.4, y: panel.minY, width: panel.width * 0.8, height: 0)
            : CGRect(x: neck.minX, y: panel.minY, width: neck.width, height: 0)
        let width = origin.width + (panel.width - origin.width) * p
        let midX = origin.midX + (panel.midX - origin.midX) * min(p, 1)
        let height = panel.height * p
        return CGRect(x: midX - width / 2, y: panel.minY, width: max(width, 0), height: max(height, 0))
    }

    func path(in rect: CGRect) -> Path {
        let body = Self.panelFrame(neck: neck, panel: panel, progress: progress)
        var path = Path()
        guard !neck.isEmpty else {
            guard body.height > 0.5 else { return path }
            path.addRoundedRect(in: body, cornerSize: CGSize(width: min(Self.bottomRadius, body.height / 2), height: min(Self.bottomRadius, body.height / 2)),
                                style: .continuous)
            return path
        }
        // The neck alone while the panel is still inside it.
        guard body.height > 0.5 else {
            path.addRoundedRect(in: neck, cornerSize: CGSize(width: 6, height: 6), style: .continuous)
            return path
        }
        let top = body.minY
        let bottom = body.maxY
        // The neck meets the top of the screen as the island meets it: with two small concave ears.
        let ear = min(Self.ear, neck.height / 3)
        // The concave curves need room on each side of the neck, and some height below it.
        let left = min(body.minX, neck.minX)
        let right = max(body.maxX, neck.maxX)
        let filletLeft = max(0, min(Self.fillet, neck.minX - left, body.height / 2))
        let filletRight = max(0, min(Self.fillet, right - neck.maxX, body.height / 2))
        let topRadius = max(0, min(Self.topRadius, body.height / 2, neck.minX - left - filletLeft, right - neck.maxX - filletRight))
        let bottomRadius = max(0, min(Self.bottomRadius, body.height / 2, (right - left) / 2))
        let k: CGFloat = 0.45

        path.move(to: CGPoint(x: neck.minX - ear, y: neck.minY))
        path.addLine(to: CGPoint(x: neck.maxX + ear, y: neck.minY))
        path.addQuadCurve(to: CGPoint(x: neck.maxX, y: neck.minY + ear), control: CGPoint(x: neck.maxX, y: neck.minY))
        path.addLine(to: CGPoint(x: neck.maxX, y: top - filletRight))
        path.addQuadCurve(to: CGPoint(x: neck.maxX + filletRight, y: top), control: CGPoint(x: neck.maxX, y: top))
        path.addLine(to: CGPoint(x: right - topRadius, y: top))
        path.addCurve(to: CGPoint(x: right, y: top + topRadius),
                      control1: CGPoint(x: right - topRadius * k, y: top), control2: CGPoint(x: right, y: top + topRadius * k))
        path.addLine(to: CGPoint(x: right, y: bottom - bottomRadius))
        path.addCurve(to: CGPoint(x: right - bottomRadius, y: bottom),
                      control1: CGPoint(x: right, y: bottom - bottomRadius * k), control2: CGPoint(x: right - bottomRadius * k, y: bottom))
        path.addLine(to: CGPoint(x: left + bottomRadius, y: bottom))
        path.addCurve(to: CGPoint(x: left, y: bottom - bottomRadius),
                      control1: CGPoint(x: left + bottomRadius * k, y: bottom), control2: CGPoint(x: left, y: bottom - bottomRadius * k))
        path.addLine(to: CGPoint(x: left, y: top + topRadius))
        path.addCurve(to: CGPoint(x: left + topRadius, y: top),
                      control1: CGPoint(x: left, y: top + topRadius * k), control2: CGPoint(x: left + topRadius * k, y: top))
        path.addLine(to: CGPoint(x: neck.minX - filletLeft, y: top))
        path.addQuadCurve(to: CGPoint(x: neck.minX, y: top - filletLeft), control: CGPoint(x: neck.minX, y: top))
        path.addLine(to: CGPoint(x: neck.minX, y: neck.minY + ear))
        path.addQuadCurve(to: CGPoint(x: neck.minX - ear, y: neck.minY), control: CGPoint(x: neck.minX, y: neck.minY))
        path.closeSubpath()
        return path
    }
}

/// A drawer's panel as it opens: the black drop, the drawer's own mark lit in the neck, and the content below, which
/// comes in once the panel has room for it. Its controller opens it once the window shows; closing runs the other way,
/// then the window goes.
@available(macOS 26, *)
struct DropPanel<Content: View, Mark: View>: View {
    let neck: CGRect
    let panel: CGRect
    let size: CGSize
    let mark: Mark
    let content: Content
    /// Set by the panel's controller to open and to close it.
    @Bindable var state: DropState
    /// The neck lies over the drawer's item: a click on it closes the drawer, as a click on the item would.
    var onNeckClick: () -> Void = {}
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        let shape = DropShape(neck: neck, panel: panel, progress: state.progress)
        ZStack(alignment: .topLeading) {
            shape
                .fill(Color(white: 0.035))
                .shadow(color: .black.opacity(0.45 * min(state.progress, 1)), radius: 18, y: 8)
            if !neck.isEmpty {
                mark
                    .foregroundStyle(.white)
                    .frame(width: neck.width, height: neck.height)
                    .contentShape(Rectangle())
                    .onTapGesture(perform: onNeckClick)
                    .padding(.leading, neck.minX)
                    .padding(.top, neck.minY)
                    .frame(width: size.width, height: size.height, alignment: .topLeading)
            }
            content
                .frame(width: panel.width, height: panel.height, alignment: .topLeading)
                .padding(.leading, panel.minX)
                .padding(.top, panel.minY)
                .frame(width: size.width, height: size.height, alignment: .topLeading)
                .opacity(contentOpacity)
                .mask(shape)
        }
        .frame(width: size.width, height: size.height, alignment: .topLeading)
        .environment(\.colorScheme, .dark)
    }

    /// Never quite 0: SwiftUI skips drawing what has no opacity, and would draw the drawer's icons for the first time
    /// halfway through the drop, holding it; drawn with the first frame, the drop runs smoothly.
    private var contentOpacity: Double {
        let p = Double(min(max(state.progress, 0), 1))
        return max(0.001, reduceMotion ? p : (p - 0.45) / 0.55)
    }
}

/// How far a drop is open, for its panel to animate in and out.
@available(macOS 26, *)
@Observable
@MainActor
final class DropState {
    var progress: CGFloat = 0
}

/// A drawer's item drawn in white in the neck of its drop, where it sits in the menu bar: its mark, and its name and
/// count when the menu bar shows them; Tiroir's own icon for the All drawer.
@available(macOS 26, *)
public struct NeckMark: View {
    let model: InterfaceModel
    let target: StatusItemsController.Target

    public init(model: InterfaceModel, target: StatusItemsController.Target) {
        self.model = model
        self.target = target
    }

    public var body: some View {
        switch target {
        case .all:
            Image(nsImage: TiroirGlyph.image(.open)).renderingMode(.template)
        case .drawer(let id):
            if let drawer = model.drawer(id) {
                HStack(spacing: 4) {
                    MarkView(drawer.mark, size: 15)
                    if drawer.showsName { Text(verbatim: drawer.name) }
                    if drawer.showsCount { Text(verbatim: "\(model.members(of: id).count)") }
                }
                .font(.system(size: NSFont.menuBarFont(ofSize: 0).pointSize, weight: .medium))
                .lineLimit(1)
            }
        }
    }
}

/// Tiroir's items as the menu bar shows them, in white: Tiroir's icon and each drawer's mark, at their places. For the
/// pictures of demo mode, which see Col's windows and not the menu bar, where macOS draws the items.
@available(macOS 26, *)
public struct MenuBarItemsPicture: View {
    public struct Item: Identifiable {
        public let target: StatusItemsController.Target
        /// In the picture's space, from its top left corner.
        public let frame: CGRect
        public var id: StatusItemsController.Target { target }

        public init(target: StatusItemsController.Target, frame: CGRect) {
            self.target = target
            self.frame = frame
        }
    }

    let model: InterfaceModel
    let items: [Item]

    public init(model: InterfaceModel, items: [Item]) {
        self.model = model
        self.items = items
    }

    public var body: some View {
        ZStack(alignment: .topLeading) {
            ForEach(items) { item in
                Group {
                    if item.target == .all {
                        Image(nsImage: TiroirGlyph.image(.closed)).renderingMode(.template)
                    } else {
                        NeckMark(model: model, target: item.target)
                    }
                }
                .foregroundStyle(.white)
                .frame(width: item.frame.width, height: item.frame.height)
                .offset(x: item.frame.minX, y: item.frame.minY)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .allowsHitTesting(false)
    }
}

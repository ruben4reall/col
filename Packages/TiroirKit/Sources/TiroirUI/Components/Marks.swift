import AppKit
import SwiftUI
import TiroirCore

/// A drawer's mark, drawn in a window.
public struct MarkView: View {
    let mark: DrawerMark
    let size: CGFloat

    public init(_ mark: DrawerMark, size: CGFloat = 18) {
        self.mark = mark
        self.size = size
    }

    public var body: some View {
        switch mark {
        case .emoji(let emoji):
            Text(verbatim: emoji).font(.system(size: size))
        case .symbol(let name):
            Image(systemName: name).font(.system(size: size * 0.86, weight: .medium)).symbolRenderingMode(.hierarchical)
        case .text(let text):
            Text(verbatim: text).font(.system(size: size * 0.72, weight: .semibold, design: .rounded))
        }
    }
}

/// A drawer's mark in the menu bar: an emoji in color, a symbol as a template image that follows the menu bar's
/// appearance like the system's own icons, or a few letters.
@MainActor
public enum StatusMark {
    public static func apply(_ drawer: Drawer, count: Int, to button: NSStatusBarButton) {
        let font = NSFont.menuBarFont(ofSize: 0)
        var suffix = ""
        if drawer.showsName { suffix += " " + drawer.name }
        if drawer.showsCount { suffix += " \(count)" }
        switch drawer.mark {
        case .emoji(let emoji):
            button.image = nil
            let title = NSMutableAttributedString(string: emoji, attributes: [.font: NSFont.systemFont(ofSize: font.pointSize + 1.5), .baselineOffset: -0.5])
            if !suffix.isEmpty { title.append(NSAttributedString(string: suffix, attributes: [.font: font])) }
            button.attributedTitle = title
            button.imagePosition = .noImage
        case .symbol(let name):
            let configuration = NSImage.SymbolConfiguration(pointSize: font.pointSize, weight: .medium)
            let image = NSImage(systemSymbolName: name, accessibilityDescription: drawer.name)?.withSymbolConfiguration(configuration)
            image?.isTemplate = true
            button.image = image
            button.attributedTitle = NSAttributedString(string: suffix, attributes: [.font: font])
            button.imagePosition = suffix.isEmpty ? .imageOnly : .imageLeading
        case .text(let text):
            button.image = nil
            let rounded = NSFont.systemFont(ofSize: font.pointSize, weight: .semibold)
            let descriptor = rounded.fontDescriptor.withDesign(.rounded) ?? rounded.fontDescriptor
            let title = NSMutableAttributedString(string: text, attributes: [.font: NSFont(descriptor: descriptor, size: font.pointSize) ?? rounded])
            if !suffix.isEmpty { title.append(NSAttributedString(string: suffix, attributes: [.font: font])) }
            button.attributedTitle = title
            button.imagePosition = .noImage
        }
        button.setAccessibilityLabel(Strings.drawerAccessibilityLabel(drawer.name))
    }
}

/// The emoji the mark picker offers first; the system's Character Viewer has every other emoji.
public enum MarkLibrary {
    public static let emoji: [String] = [
        "☁️", "📁", "🗂️", "🗄️", "📦", "🔒", "🔐", "🛡️", "🔑", "💬", "✉️", "📨", "📞", "✨", "🤖", "🧠", "🛠️", "🧰", "⚙️",
        "🔧", "🧪", "💻", "🖥️", "⌨️", "🖱️", "🎧", "🎵", "🎬", "📷", "🎙️", "🎨", "✏️", "📝", "🗓️", "⏰", "⏱️", "📊", "📈",
        "🔋", "⚡️", "🌐", "📡", "🛰️", "🏠", "🧭", "🗺️", "🎮", "🕹️", "🎲", "🌙", "☀️", "🌿", "🍵", "☕️", "🔥", "💡",
        "⭐️", "❤️", "🧡", "💛", "💚", "💙", "💜", "🖤", "🏷️", "📌", "🧩", "🪄", "🚀", "🐙", "🦊", "🐝",
    ]

}

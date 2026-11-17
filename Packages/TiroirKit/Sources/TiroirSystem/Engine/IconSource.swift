import ApplicationServices
import CoreGraphics
import Foundation
import TiroirCore

/// One icon as its app describes it, with the way to press it.
public struct FoundIcon: Sendable {
    public var app: RunningApp
    public var frame: CGRect
    public var identifier: String?
    public var label: String?
    /// Presses the icon as a click would; false when the app refused.
    public var press: @Sendable () -> Bool

    public init(app: RunningApp, frame: CGRect, identifier: String? = nil, label: String? = nil, press: @escaping @Sendable () -> Bool = { false }) {
        self.app = app
        self.frame = frame
        self.identifier = identifier
        self.label = label
        self.press = press
    }
}

/// Where engines learn which app owns which icon. The system implementation asks every app over Accessibility.
@MainActor
public protocol IconSource: AnyObject {
    var isTrusted: Bool { get }
    func find() async -> [FoundIcon]
}

@MainActor
public final class AccessibilityIconSource: IconSource {
    private let reader: ExtrasReader

    public init(reader: ExtrasReader = ExtrasReader()) {
        self.reader = reader
    }

    public var isTrusted: Bool { AXIsProcessTrusted() }

    public func find() async -> [FoundIcon] {
        guard isTrusted else { return [] }
        let items = await reader.read(ExtrasReader.candidates())
        return items.map { item in
            let element = item.element
            return FoundIcon(app: item.app, frame: item.frame, identifier: item.identifier, label: item.label, press: { element.press() })
        }
    }
}

/// Turns what apps say about their icons into menu bar icons with stable identities (spec 4.3, Discovery).
public enum IconAssembly {
    /// Identity, kind and label of each found icon, before any window is known.
    public static func identify(_ found: [FoundIcon]) -> [(found: FoundIcon, id: IconID)] {
        var result: [(FoundIcon, IconID)] = []
        for (bundleID, icons) in Dictionary(grouping: found, by: \.app.bundleID) {
            let ordered = icons.sorted { $0.frame.midX > $1.frame.midX }
            for (index, icon) in ordered.enumerated() {
                let id = IconIdentity.make(bundleID: bundleID, identifier: icon.identifier, indexFromRight: index, countForApp: ordered.count)
                result.append((icon, id))
            }
        }
        return result
    }

    /// Whether an icon belongs to macOS.
    public static func kind(of bundleID: String) -> IconKind {
        bundleID.hasPrefix("com.apple.") ? .system : .app
    }

    /// Control Center describes its modules at length ("Wi-Fi, connected, 3 bars"): the part before the first comma
    /// names them.
    public static func displayLabel(_ label: String?, kind: IconKind) -> String? {
        guard let label, !label.isEmpty else { return nil }
        guard kind == .system, let comma = label.firstIndex(of: ",") else { return label }
        let head = label[..<comma].trimmingCharacters(in: .whitespaces)
        return head.isEmpty ? label : head
    }
}

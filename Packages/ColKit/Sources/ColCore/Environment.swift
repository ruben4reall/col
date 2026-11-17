import CoreGraphics
import Foundation

/// Decides whether an app covers the notch's screen in full screen, from the on-screen window list.
public enum FullScreen {
    public struct Window: Equatable, Sendable {
        public var layer: Int
        public var bounds: CGRect
        public var ownerPID: Int32

        public init(layer: Int, bounds: CGRect, ownerPID: Int32) {
            self.layer = layer
            self.bounds = bounds
            self.ownerPID = ownerPID
        }
    }

    /// True when the frontmost app has a normal window exactly covering the screen, menu bar included: that is a
    /// full-screen Space or a presentation, where the island should step aside.
    public static func isActive(windows: [Window], screen: CGRect, frontmostPID: Int32?) -> Bool {
        guard let frontmostPID else { return false }
        return windows.contains { window in
            window.layer == 0 && window.ownerPID == frontmostPID
                && abs(window.bounds.width - screen.width) < 1 && abs(window.bounds.height - screen.height) < 1
                && abs(window.bounds.minX - screen.minX) < 1
        }
    }
}

/// Follows downloads in progress from the names in a folder: browsers write `.download`, `.crdownload` or `.part`
/// files, then rename them when they finish.
public struct DownloadTracker: Sendable, Equatable {
    public enum Event: Equatable, Sendable {
        case started(String)
        case finished(String)
        case cancelled(String)
    }

    public static let partialExtensions = ["download", "crdownload", "part", "partial"]
    private(set) public var inProgress: Set<String> = []

    public init() {}

    /// The final name of a partial file: "Report.pdf.download" gives "Report.pdf".
    public static func finalName(of partial: String) -> String? {
        let url = URL(fileURLWithPath: partial)
        guard partialExtensions.contains(url.pathExtension.lowercased()) else { return nil }
        return url.deletingPathExtension().lastPathComponent
    }

    /// Compares a new listing of the folder with the downloads seen so far.
    public mutating func update(listing: Set<String>) -> [Event] {
        let partial = Set(listing.filter { Self.finalName(of: $0) != nil })
        var events: [Event] = []
        for name in partial.subtracting(inProgress).sorted() {
            events.append(.started(Self.finalName(of: name)!))
        }
        for name in inProgress.subtracting(partial).sorted() {
            let final = Self.finalName(of: name)!
            events.append(listing.contains(final) ? .finished(final) : .cancelled(final))
        }
        inProgress = partial
        return events
    }
}

/// Battery levels an accessory reports, from 0 to 100, missing when unknown.
public struct AccessoryBattery: Equatable, Sendable {
    public var left: Int?
    public var right: Int?
    public var caseLevel: Int?
    public var single: Int?

    public init(left: Int? = nil, right: Int? = nil, caseLevel: Int? = nil, single: Int? = nil) {
        self.left = left
        self.right = right
        self.caseLevel = caseLevel
        self.single = single
    }

    /// Accessories report 0 for a part they cannot see; that is unknown, not empty.
    public static func level(_ raw: Int?) -> Int? {
        guard let raw, raw > 0, raw <= 100 else { return nil }
        return raw
    }

    public var isEmpty: Bool { left == nil && right == nil && caseLevel == nil && single == nil }

    /// The lowest earbud, for a single figure in the wing.
    public var summary: Int? {
        [left, right].compactMap { $0 }.min() ?? single
    }
}

/// How wide the wings may grow without covering the menu bar: the app's menus on the left of the camera, the
/// status items on its right.
public enum WingBudget {
    /// Space kept clear between the island and the nearest menu or icon.
    public static let margin: CGFloat = 8
    /// Below this, a wing cannot hold even an icon; the activity then waits in the open island.
    public static let minimum: CGFloat = 30
    /// Without Accessibility Col cannot see the menu bar. Under a notch the activity then goes beneath the camera; the
    /// pill, which cannot, assumes this much room on each side, enough for an icon.
    public static let unknownRoom: CGFloat = 42

    /// Room on one side, from the edge of the notch to the nearest item less the margin, or nil when unknown.
    public static func free(notchEdge: CGFloat, nearestItem: CGFloat?, leftSide: Bool) -> CGFloat? {
        guard let nearestItem else { return nil }
        return max(0, (leftSide ? notchEdge - nearestItem : nearestItem - notchEdge) - margin)
    }

    /// The wings that fit: the requested width on both sides, capped by the tighter one. When a long menu leaves no
    /// room on one side, the other keeps a wing of its own; only when neither side holds an icon does the activity
    /// wait in the open island. Unknown sides do not limit it.
    ///
    /// `overhang` is how far the island reaches past its wings: its concave ears, and the swell under the pointer.
    /// A wing that filled the room would leave them over the first menu or icon.
    public static func allowed(requested: CGFloat, left: CGFloat?, right: CGFloat?, overhang: CGFloat = 0) -> Wings {
        guard requested > 0 else { return .none }
        func fit(_ room: CGFloat?) -> CGFloat {
            let wing = min(requested, room.map { $0 - overhang } ?? .greatestFiniteMagnitude)
            return wing < minimum ? 0 : wing
        }
        let leading = fit(left), trailing = fit(right)
        guard leading > 0, trailing > 0 else { return Wings(leading: leading, trailing: trailing) }
        return Wings(min(leading, trailing))
    }

    /// The wings that fit when each side asks for its own width: an icon's wing stays an icon's width beside a line
    /// of text, so the island is no wider than what it shows. A side whose item does not fit gives up its wing; when
    /// neither fits, the wider request takes whichever side holds it, the roomier first, as a single wing.
    public static func allowed(leading requestedLeading: CGFloat, trailing requestedTrailing: CGFloat,
                               left: CGFloat?, right: CGFloat?, overhang: CGFloat = 0) -> Wings {
        guard requestedLeading > 0 || requestedTrailing > 0 else { return .none }
        func fit(_ requested: CGFloat, _ room: CGFloat?) -> CGFloat {
            guard requested > 0 else { return 0 }
            let wing = min(requested, room.map { $0 - overhang } ?? .greatestFiniteMagnitude)
            return wing < minimum ? 0 : wing
        }
        let leading = fit(requestedLeading, left), trailing = fit(requestedTrailing, right)
        if leading > 0 || trailing > 0 { return Wings(leading: leading, trailing: trailing) }
        let single = max(requestedLeading, requestedTrailing)
        let onLeft = fit(single, left), onRight = fit(single, right)
        if onLeft > 0, onRight > 0 {
            return (left ?? .greatestFiniteMagnitude) >= (right ?? .greatestFiniteMagnitude)
                ? Wings(leading: onLeft, trailing: 0) : Wings(leading: 0, trailing: onRight)
        }
        return Wings(leading: onLeft, trailing: onRight)
    }

    /// Where an activity goes on an island that shares the menu bar. Beside the camera when the menu bar leaves room
    /// for a wing; beneath it when it leaves none, when it cannot be read at all (`readable` false: no Accessibility),
    /// or when the user asked for it, so an activity never covers a menu or an icon and never vanishes. A side that
    /// could not be measured (nil) does not limit its wing, as in `allowed`. An island that cannot hang beneath (the
    /// pill) keeps a narrow wing on each side when the menu bar cannot be read.
    public static func placement(
        leading requestedLeading: CGFloat,
        trailing requestedTrailing: CGFloat,
        beneath: Wings,
        left: CGFloat?,
        right: CGFloat?,
        readable: Bool = true,
        overhang: CGFloat = 0,
        canHangBeneath: Bool,
        prefersBeneath: Bool = false
    ) -> Wings {
        guard requestedLeading > 0 || requestedTrailing > 0 else { return .none }
        guard canHangBeneath else {
            if readable {
                return allowed(leading: requestedLeading, trailing: requestedTrailing, left: left, right: right, overhang: overhang)
            }
            return allowed(leading: requestedLeading, trailing: requestedTrailing, left: unknownRoom, right: unknownRoom, overhang: overhang)
        }
        if prefersBeneath || !readable { return beneath }
        let beside = allowed(leading: requestedLeading, trailing: requestedTrailing, left: left, right: right, overhang: overhang)
        return beside.isEmpty ? beneath : beside
    }
}

/// Which headphones connected, from the Bluetooth product ID Apple's accessories report, with the device's name as a
/// fallback for others. Decides the picture and the animation of the card that opens.
public enum HeadphoneModel: String, Sendable, Equatable, CaseIterable {
    case airpods, airpods3, airpods4, airpodsPro, airpodsPro2, airpodsPro3, airpodsMax, beatsHeadphones, beatsEarbuds
    case headphones, earbuds

    /// Apple's product IDs, from the table macOS keeps for its own accessory pictures.
    public init?(productID: Int) {
        switch productID {
        case 0x2002, 0x200F: self = .airpods
        case 0x2013: self = .airpods3
        case 0x2019, 0x201B: self = .airpods4
        case 0x200E: self = .airpodsPro
        case 0x2014, 0x2024: self = .airpodsPro2
        case 0x2027: self = .airpodsPro3
        case 0x200A, 0x201F, 0x202D: self = .airpodsMax
        case 0x2006, 0x2009, 0x2017, 0x2025, 0x200C: self = .beatsHeadphones
        case 0x2003, 0x2005, 0x200B, 0x200D, 0x2010, 0x2011, 0x2012, 0x2016, 0x201D, 0x2026, 0x202F: self = .beatsEarbuds
        default: return nil
        }
    }

    /// For devices without a known product ID: the name usually says it.
    public init?(name: String) {
        let name = name.lowercased()
        if name.contains("airpods max") { self = .airpodsMax }
        else if name.contains("airpods pro") { self = .airpodsPro2 }
        else if name.contains("airpods") { self = .airpods }
        else if name.contains("beats") { self = .beatsHeadphones }
        else { return nil }
    }

    /// The SF Symbol drawn for the model, newest names first, falling back when the system does not have them.
    public var symbols: [String] {
        switch self {
        case .airpods: ["airpods"]
        case .airpods3: ["airpods.gen3", "airpods"]
        case .airpods4: ["airpods.gen4", "airpods.gen3", "airpods"]
        case .airpodsPro, .airpodsPro2, .airpodsPro3: ["airpods.pro", "airpodspro"]
        case .airpodsMax: ["airpods.max", "airpodsmax"]
        case .beatsHeadphones: ["beats.headphones", "headphones"]
        case .beatsEarbuds: ["beats.earphones", "earbuds"]
        case .headphones: ["headphones"]
        case .earbuds: ["earbuds"]
        }
    }

    /// Over-ear headphones turn on themselves; earbuds turn as a pair.
    public var isOverEar: Bool { self == .airpodsMax || self == .beatsHeadphones || self == .headphones }
}

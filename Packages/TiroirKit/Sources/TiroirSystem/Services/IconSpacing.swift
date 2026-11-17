import CoreFoundation

/// The room macOS leaves between menu bar icons, for every app (Settings, Layout). macOS keeps it in two preferences of
/// the global domain for this Mac, NSStatusItemSpacing and NSStatusItemSelectionPadding (16 points each by default),
/// and each app reads them when it starts: a change shows as apps open, and everywhere after logging out and back in.
public enum IconSpacing: String, CaseIterable, Sendable {
    case standard, snug, compact, tight

    static var spacingKey: CFString { "NSStatusItemSpacing" as CFString }
    static var paddingKey: CFString { "NSStatusItemSelectionPadding" as CFString }

    /// Spacing and selection padding in points; nil leaves macOS's own.
    public var values: (spacing: Int, padding: Int)? {
        switch self {
        case .standard: nil
        case .snug: (12, 10)
        case .compact: (8, 8)
        case .tight: (6, 6)
        }
    }

    /// The step closest to what this Mac uses now.
    public static func current() -> IconSpacing {
        let spacing = read(spacingKey)
        let padding = read(paddingKey)
        guard spacing != nil || padding != nil else { return .standard }
        return closest(spacing: spacing ?? 16, padding: padding ?? 16)
    }

    static func closest(spacing: Int, padding: Int) -> IconSpacing {
        allCases.min { lhs, rhs in
            distance(lhs, spacing, padding) < distance(rhs, spacing, padding)
        } ?? .standard
    }

    private static func distance(_ step: IconSpacing, _ spacing: Int, _ padding: Int) -> Int {
        let values = step.values ?? (16, 16)
        return abs(values.spacing - spacing) + abs(values.padding - padding)
    }

    /// Writes this step for every app of this Mac; `.standard` removes both preferences.
    public func apply() {
        let host = kCFPreferencesCurrentHost
        if let values {
            CFPreferencesSetValue(Self.spacingKey, values.spacing as CFNumber, kCFPreferencesAnyApplication, kCFPreferencesCurrentUser, host)
            CFPreferencesSetValue(Self.paddingKey, values.padding as CFNumber, kCFPreferencesAnyApplication, kCFPreferencesCurrentUser, host)
        } else {
            CFPreferencesSetValue(Self.spacingKey, nil, kCFPreferencesAnyApplication, kCFPreferencesCurrentUser, host)
            CFPreferencesSetValue(Self.paddingKey, nil, kCFPreferencesAnyApplication, kCFPreferencesCurrentUser, host)
        }
        CFPreferencesSynchronize(kCFPreferencesAnyApplication, kCFPreferencesCurrentUser, host)
    }

    private static func read(_ key: CFString) -> Int? {
        CFPreferencesCopyValue(key, kCFPreferencesAnyApplication, kCFPreferencesCurrentUser, kCFPreferencesCurrentHost) as? Int
    }
}

import SwiftUI

/// The springs and durations every surface shares (spec 7).
public enum Motion {
    /// A drawer drops under its emoji.
    public static let drawer = Animation.spring(response: 0.32, dampingFraction: 0.86)
    /// A short fade, used instead of every movement when Reduce Motion is on.
    public static let fade = Animation.easeOut(duration: 0.16)
}

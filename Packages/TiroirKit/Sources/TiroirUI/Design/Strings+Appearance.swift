import Foundation
import TiroirCore

/// The words of Settings, Appearance about the menu bar's shape and its look in Dark Mode.
extension Strings {
    // MARK: Shape

    public static let shape = String(localized: "Shape", bundle: .module)

    public static func shapeName(_ shape: Appearance.Shape) -> String {
        switch shape {
        case .full: String(localized: "Full Width", bundle: .module)
        case .floating: String(localized: "Floating", bundle: .module)
        case .split: String(localized: "Split", bundle: .module)
        }
    }

    public static let splitNote = String(localized: "On a display without a notch, Split follows the app menus and the icons. Until Tiroir can measure them, the bar floats.", bundle: .module)

    // MARK: Dark Mode

    public static let differentLookInDarkMode = String(localized: "Different look in Dark Mode", bundle: .module)
    public static let look = String(localized: "Look", bundle: .module)
    public static let lightMode = String(localized: "Light", bundle: .module)
    public static let darkMode = String(localized: "Dark", bundle: .module)
}

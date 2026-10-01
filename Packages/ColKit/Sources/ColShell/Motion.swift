import AppKit
import ColCore

/// How the island moves between states. Opening overshoots a little, like something with weight; closing settles
/// without a bounce so the island tucks back into the notch cleanly.
@MainActor
enum Motion {
    static func animation(toward state: IslandState) -> CABasicAnimation {
        if NSWorkspace.shared.accessibilityDisplayShouldReduceMotion {
            let fade = CABasicAnimation()
            fade.duration = 0.2
            fade.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
            return fade
        }
        let factor = Preferences.motionStyle.factor
        let spring = switch state {
        case .expanded: CASpringAnimation(perceptualDuration: 0.5 * factor, bounce: 0.22)
        case .peek: CASpringAnimation(perceptualDuration: 0.35 * factor, bounce: 0.3)
        case .collapsed: CASpringAnimation(perceptualDuration: 0.38 * factor, bounce: 0)
        }
        spring.duration = spring.settlingDuration
        return spring
    }

    /// Pointer rest before a peeking island opens by itself.
    static var hoverDwell: Duration { .milliseconds(Int(Preferences.hoverDelay * 1000)) }
    /// Time the pointer may spend off the open island before it closes.
    static let exitGrace: Duration = .milliseconds(220)
}

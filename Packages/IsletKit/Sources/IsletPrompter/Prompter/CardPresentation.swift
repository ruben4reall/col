import AppKit
import IsletCore
import SwiftUI

/// The prompter as a card: floating glass anywhere on screen, or a whole display in black for a camera rig or an
/// external monitor.
@MainActor
final class CardPresentation: PrompterPresentation {
    let text = ScriptTextView()
    private let state: PrompterState
    private let fullScreen: Bool
    private let panel: PrompterPanel
    private let container = HoverView()
    private var background: NSView?
    private let glowView = GlowView()
    private var overlay: PassthroughHostingView<PrompterOverlay>?
    var onKey: ((NSEvent) -> Bool)? {
        didSet { panel.onKey = onKey }
    }

    init(state: PrompterState, fullScreen: Bool) {
        self.state = state
        self.fullScreen = fullScreen
        panel = PrompterPanel(movable: !fullScreen)
        panel.takesKeyboard = fullScreen
        if !fullScreen { panel.setFrameAutosaveName("IsletFloatingPrompter") }
        panel.contentView = container
        container.wantsLayer = true
        container.onHover = { [weak state] inside in state?.isHovering = inside }
    }

    func refresh() {
        panel.sharingType = PrompterPreferences.hiddenFromCapture ? .none : .readOnly
        let style = PrompterStyle.current(fullScreen: fullScreen)
        if fullScreen {
            guard let screen = Screens.fullScreen else { return }
            panel.level = NSWindow.Level(rawValue: NSWindow.Level.screenSaver.rawValue)
            panel.setFrame(screen.frame, display: false)
        } else {
            let size = PrompterPreferences.floatingSize
            var frame = panel.frame
            let visible = NSScreen.screens.contains { $0.visibleFrame.intersects(frame.insetBy(dx: 40, dy: 40)) }
            if frame.width < 10 || !visible, let screen = Screens.notch {
                // First time: centred just under the menu bar, as close to the camera as a window can be.
                frame = NSRect(x: screen.frame.midX - size.width / 2, y: screen.visibleFrame.maxY - size.height - 8, width: size.width, height: size.height)
            } else {
                frame.origin.y += frame.height - size.height
                frame.size = size
            }
            panel.setFrame(frame, display: false)
        }
        container.frame = NSRect(origin: .zero, size: panel.frame.size)
        installBackground()
        let bounds = container.bounds
        let top: CGFloat = fullScreen ? bounds.height * 0.08 : 34
        let bottom: CGFloat = fullScreen ? bounds.height * 0.06 : 8
        text.frame = NSRect(x: 0, y: bottom, width: bounds.width, height: bounds.height - top - bottom)
        text.horizontalInset = fullScreen ? bounds.width * 0.08 : 24
        text.readingInset = fullScreen ? text.frame.height * 0.3 : style.lineHeight * 0.9
        text.fadeTop = fullScreen ? text.readingInset * 0.8 : 18
        text.fadeBottom = fullScreen ? 80 : 30
        text.showsBand = fullScreen
        if text.superview == nil { container.addSubview(text) }
        if !fullScreen {
            // The stage light rises inside the card from its lower edge, as in the notch.
            if glowView.superview == nil { container.addSubview(glowView, positioned: .above, relativeTo: background) }
            glowView.frame = bounds
            glowView.configure(body: bounds)
            glowView.setColors(PrompterPreferences.stageLight)
            glowView.outline.path = CGPath(roundedRect: bounds, cornerWidth: 26, cornerHeight: 26, transform: nil)
        }
        installOverlay(bounds: bounds)
        container.trackedRect = bounds
    }

    private func installBackground() {
        background?.removeFromSuperview()
        let view: NSView
        if fullScreen {
            view = NSView()
            view.wantsLayer = true
            view.layer?.backgroundColor = StageTheme.palette(PrompterPreferences.theme).background.cgColor
        } else if #available(macOS 26, *) {
            let glass = NSGlassEffectView()
            glass.cornerRadius = 26
            glass.tintColor = NSColor.black.withAlphaComponent(PrompterPreferences.theme == .paper ? 0 : 0.62)
            view = glass
        } else {
            let effect = NSVisualEffectView()
            effect.material = .hudWindow
            effect.blendingMode = .behindWindow
            effect.state = .active
            effect.wantsLayer = true
            effect.layer?.cornerRadius = 26
            effect.layer?.masksToBounds = true
            view = effect
        }
        if !fullScreen, PrompterPreferences.theme == .paper {
            view.wantsLayer = true
            view.layer?.backgroundColor = StageTheme.palette(.paper).background.cgColor
            view.layer?.cornerRadius = 26
        }
        view.frame = container.bounds
        view.autoresizingMask = [.width, .height]
        container.addSubview(view, positioned: .below, relativeTo: nil)
        background = view
    }

    private func installOverlay(bounds: NSRect) {
        overlay?.removeFromSuperview()
        let overlay = PassthroughHostingView(rootView: PrompterOverlay(state: state, showsStatusRow: true, scale: fullScreen ? 1.6 : 1))
        overlay.sizingOptions = []
        overlay.frame = bounds
        let state = self.state
        let scale: CGFloat = fullScreen ? 1.6 : 1
        overlay.interactiveRects = { [weak overlay] in
            guard let overlay else { return [] }
            if state.failure != nil || state.summary != nil { return [overlay.bounds] }
            guard state.isHovering else { return [] }
            // The hosting view is flipped: the controls sit along its bottom edge, at the largest y.
            return [NSRect(x: overlay.bounds.midX - 110 * scale, y: overlay.bounds.maxY - 60 * scale, width: 220 * scale, height: 60 * scale)]
        }
        container.addSubview(overlay)
        self.overlay = overlay
    }

    func present() {
        refresh()
        panel.alphaValue = 0
        if fullScreen {
            panel.makeKeyAndOrderFront(nil)
            NSApp.activate()
        } else {
            panel.orderFrontRegardless()
        }
        NSAnimationContext.runAnimationGroup { context in
            context.duration = 0.25
            panel.animator().alphaValue = 1
        }
    }

    func glow(_ intensity: CGFloat) {
        guard !fullScreen else { return }
        glowView.setIntensity(intensity)
    }

    func closeNow() {
        state.isHovering = false
        panel.orderOut(nil)
        text.halt()
    }

    func dismiss(completion: @escaping @MainActor () -> Void) {
        state.isHovering = false
        NSAnimationContext.runAnimationGroup { context in
            context.duration = 0.2
            panel.animator().alphaValue = 0
        } completionHandler: {
            // Held until the fade ends: the controller has already let go of this presentation.
            MainActor.assumeIsolated {
                self.panel.orderOut(nil)
                self.text.halt()
                completion()
            }
        }
    }
}

/// Reports the pointer entering and leaving the card.
final class HoverView: NSView {
    var onHover: ((Bool) -> Void)?
    var trackedRect: NSRect = .zero {
        didSet {
            if let area { removeTrackingArea(area) }
            let area = NSTrackingArea(rect: trackedRect, options: [.mouseEnteredAndExited, .activeAlways], owner: self)
            addTrackingArea(area)
            self.area = area
        }
    }
    private var area: NSTrackingArea?

    override func mouseEntered(with event: NSEvent) { onHover?(true) }
    override func mouseExited(with event: NSEvent) { onHover?(false) }
}

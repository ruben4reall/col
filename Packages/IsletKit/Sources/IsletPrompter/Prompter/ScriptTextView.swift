import AppKit
import IsletCore

/// How the prompter's text looks.
struct PrompterStyle: Equatable {
    var font: PrompterFont
    var size: CGFloat
    var spacing: CGFloat
    var theme: PrompterTheme
    var centered: Bool
    var dimsReadWords: Bool
    var mirror: MirrorMode
    var light: StageLight

    /// The style from Settings. In the notch the prompter stays black like the notch it hangs from, so Paper, a
    /// light page, reads as Night there.
    @MainActor static func current(fullScreen: Bool = false, notch: Bool = false) -> PrompterStyle {
        PrompterStyle(
            font: PrompterPreferences.font,
            size: fullScreen ? PrompterPreferences.fullScreenFontSize : PrompterPreferences.fontSize,
            spacing: PrompterPreferences.lineSpacing,
            theme: notch && PrompterPreferences.theme == .paper ? .night : PrompterPreferences.theme,
            centered: PrompterPreferences.centersText,
            dimsReadWords: PrompterPreferences.dimsReadWords,
            mirror: PrompterPreferences.mirror,
            light: PrompterPreferences.stageLight
        )
    }

    var bodyFont: NSFont { font.font(size: size, weight: .medium) }

    /// Height of one line of body text, spacing included.
    @MainActor var lineHeight: CGFloat { Self.lineHeight(font: font, size: size, spacing: spacing) }

    @MainActor private static let measurer = NSLayoutManager()

    @MainActor private static var lineHeights: [String: CGFloat] = [:]

    /// Measured once per font, size and spacing: the voice asks for it twenty times a second.
    @MainActor static func lineHeight(font: PrompterFont, size: CGFloat, spacing: CGFloat) -> CGFloat {
        let key = "\(font.rawValue) \(size) \(spacing)"
        if let known = lineHeights[key] { return known }
        let value = measurer.defaultLineHeight(for: font.font(size: size, weight: .medium)) * spacing
        lineHeights[key] = value
        return value
    }
}

/// The script on the prompter: laid out once with TextKit, then scrolled by moving the clip view, frame by frame,
/// while something moves it. Words already read and the next word are temporary attributes: colouring them never
/// lays the text out again.
@MainActor
final class ScriptTextView: NSView {
    private let scrollView = NSScrollView()
    private let clipView = FreeClipView()
    private let textView: InertTextView
    private let band = CALayer()
    private let fade = CAGradientLayer()

    private(set) var script = Script("")
    private(set) var style = PrompterStyle.current()
    /// Where the line being read sits, in points from the top of the view.
    var readingInset: CGFloat = 8 { didSet { needsLayout = true } }
    var horizontalInset: CGFloat = 26 { didSet { needsLayout = true } }
    /// Height of the fades at the top and bottom edges.
    var fadeTop: CGFloat = 6
    /// A band at the top where nothing shows at all, so a line already read never peeks out under the camera.
    var hiddenTop: CGFloat = 0
    var fadeBottom: CGFloat = 28
    var showsBand = false { didSet { band.isHidden = !showsBand } }

    /// Two fingers moved the text by this many points (positive: further into the script).
    var onNudge: ((CGFloat) -> Void)?
    var onNudgeEnded: (() -> Void)?
    var onClick: (() -> Void)?
    /// The text moved; called at most once per frame.
    var onOffsetChanged: ((CGFloat) -> Void)?
    /// A follow motion or rolling reached its end.
    var onSettled: (() -> Void)?

    private var link: CADisplayLink?
    private var lastTimestamp: CFTimeInterval = 0
    private(set) var offset: CGFloat = 0
    private var target: CGFloat?
    private var velocity: CGFloat = 0
    /// Points per second while rolling; zero when still.
    var speed: CGFloat = 0 {
        didSet { if speed != 0 { run() } }
    }
    /// A speed to ease towards, for rolling that starts and stops with the voice.
    private var easedTarget: CGFloat?

    func setSpeed(_ value: CGFloat, eased: Bool) {
        // Silence after silence: nothing to change, and no display link to start.
        if value == speed, easedTarget == nil { return }
        if eased, easedTarget == value { return }
        if eased {
            easedTarget = value
            run()
        } else {
            easedTarget = nil
            speed = value
        }
    }
    private var readLocation = 0
    private var nextWordRange: NSRange?

    override init(frame frameRect: NSRect) {
        let storage = NSTextStorage()
        let manager = NSLayoutManager()
        storage.addLayoutManager(manager)
        let container = NSTextContainer(size: NSSize(width: 400, height: CGFloat.greatestFiniteMagnitude))
        container.widthTracksTextView = true
        container.lineFragmentPadding = 0
        manager.addTextContainer(container)
        manager.allowsNonContiguousLayout = true
        textView = InertTextView(frame: .zero, textContainer: container)
        super.init(frame: frameRect)
        wantsLayer = true
        // Since macOS 14 views draw outside their bounds unless told otherwise; the text must stay in its area.
        clipsToBounds = true
        layer?.masksToBounds = true

        textView.isEditable = false
        textView.isSelectable = false
        textView.drawsBackground = false
        textView.isVerticallyResizable = true
        textView.isHorizontallyResizable = false
        textView.autoresizingMask = [.width]

        scrollView.contentView = clipView
        scrollView.drawsBackground = false
        scrollView.hasVerticalScroller = false
        scrollView.hasHorizontalScroller = false
        scrollView.verticalScrollElasticity = .none
        scrollView.documentView = textView
        clipView.drawsBackground = false
        addSubview(scrollView)

        band.cornerRadius = 10
        band.isHidden = true
        layer?.addSublayer(band)

        fade.colors = [NSColor.clear.cgColor, NSColor.clear.cgColor, NSColor.black.cgColor, NSColor.black.cgColor, NSColor.clear.cgColor]

        layer?.mask = fade
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }

    override var isFlipped: Bool { true }

    // MARK: Content

    func load(_ script: Script, style: PrompterStyle) {
        self.script = script
        self.style = style
        textView.textStorage?.setAttributedString(Self.attributed(script, style: style))
        readLocation = 0
        nextWordRange = nil
        band.backgroundColor = StageTheme.palette(style.theme).band.cgColor
        applyMirror()
        needsLayout = true
        layoutSubtreeIfNeeded()
        setOffset(0)
    }

    static func attributed(_ script: Script, style: PrompterStyle) -> NSAttributedString {
        let palette = StageTheme.palette(style.theme)
        let paragraph = NSMutableParagraphStyle()
        paragraph.lineHeightMultiple = style.spacing
        paragraph.paragraphSpacing = style.size * 0.8
        paragraph.alignment = style.centered ? .center : .natural
        let text = NSMutableAttributedString(string: script.display, attributes: [
            .font: style.bodyFont,
            .foregroundColor: palette.text,
            .paragraphStyle: paragraph,
        ])
        let small = style.font.font(size: max(11, style.size * 0.56), weight: .semibold)
        for run in script.styles {
            switch run.kind {
            case .heading:
                text.addAttributes([.font: small, .foregroundColor: palette.heading, .kern: 1.4], range: run.range)
            case .cue:
                text.addAttributes([.font: small, .foregroundColor: palette.cue, .kern: 0.9], range: run.range)
            case .emphasis:
                text.addAttributes([.font: style.font.font(size: style.size, weight: .heavy)], range: run.range)
            }
        }
        return text
    }

    override func layout() {
        super.layout()
        cachedWordsPerLine = nil
        scrollView.frame = bounds
        textView.textContainerInset = NSSize(width: horizontalInset, height: readingInset)
        textView.frame.size.width = bounds.width
        textView.layoutManager?.ensureLayout(for: textView.textContainer!)
        textView.sizeToFit()
        band.frame = CGRect(x: 10, y: readingInset - 3, width: bounds.width - 20, height: style.lineHeight + 4)
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        fade.frame = bounds
        let height = max(bounds.height, 1)
        let hidden = min(hiddenTop, height / 2)
        fade.locations = [0, NSNumber(value: Double(hidden / height)), NSNumber(value: Double((hidden + fadeTop) / height)),
                          NSNumber(value: Double(1 - fadeBottom / height)), 1]
        CATransaction.commit()
        applyMirror()
    }

    // MARK: Positions

    /// The offset that puts the line holding a character on the reading line.
    func offset(forCharacter location: Int) -> CGFloat {
        guard let manager = textView.layoutManager, let container = textView.textContainer,
              textView.textStorage?.length ?? 0 > 0 else { return 0 }
        let clamped = min(max(location, 0), (textView.textStorage?.length ?? 1) - 1)
        let glyph = manager.glyphIndexForCharacter(at: clamped)
        let line = manager.lineFragmentRect(forGlyphAt: glyph, effectiveRange: nil)
        _ = container
        return line.minY
    }

    func offset(forWord index: Int) -> CGFloat {
        guard !script.words.isEmpty else { return 0 }
        if index >= script.words.count { return endOffset }
        return offset(forCharacter: script.words[max(0, index)].range.location)
    }

    /// The offset at which the last line sits on the reading line.
    var endOffset: CGFloat {
        guard let length = textView.textStorage?.length, length > 0 else { return 0 }
        return offset(forCharacter: length - 1)
    }

    /// The first character of the line on the reading line at an offset.
    func character(atOffset offset: CGFloat) -> Int {
        guard let manager = textView.layoutManager, let container = textView.textContainer,
              let length = textView.textStorage?.length, length > 0 else { return 0 }
        let point = CGPoint(x: 1, y: offset + style.lineHeight * 0.5)
        let glyph = manager.glyphIndex(for: point, in: container)
        var range = NSRange()
        _ = manager.lineFragmentRect(forGlyphAt: glyph, effectiveRange: &range)
        return manager.characterIndexForGlyph(at: range.location)
    }

    /// Index of the first word on the reading line at an offset.
    func word(atOffset offset: CGFloat) -> Int {
        let location = character(atOffset: offset)
        return script.words.firstIndex { $0.range.location >= location } ?? script.words.count
    }

    /// The text of the line on the reading line.
    func currentLine() -> String {
        guard let manager = textView.layoutManager, let container = textView.textContainer,
              let storage = textView.textStorage, storage.length > 0 else { return "" }
        let glyph = manager.glyphIndex(for: CGPoint(x: 1, y: offset + style.lineHeight * 0.5), in: container)
        var range = NSRange()
        _ = manager.lineFragmentRect(forGlyphAt: glyph, effectiveRange: &range)
        let characters = manager.characterRange(forGlyphRange: range, actualGlyphRange: nil)
        return (storage.string as NSString).substring(with: characters).trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// Average number of spoken words on a line, for turning a pace into a scrolling speed. Counted once per layout.
    var wordsPerLine: Double {
        if let cachedWordsPerLine { return cachedWordsPerLine }
        guard let manager = textView.layoutManager, !script.words.isEmpty else { return 8 }
        var lines = 0
        manager.enumerateLineFragments(forGlyphRange: NSRange(location: 0, length: manager.numberOfGlyphs)) { _, _, _, _, _ in lines += 1 }
        let value = max(1, Double(script.words.count) / Double(max(lines, 1)))
        cachedWordsPerLine = value
        return value
    }
    private var cachedWordsPerLine: Double?

    // MARK: Colours of the words

    /// Dims everything before `location` and lights the word in `next`.
    func mark(readUpTo location: Int, next: NSRange?) {
        guard let manager = textView.layoutManager, let length = textView.textStorage?.length else { return }
        let palette = StageTheme.palette(style.theme)
        let clamped = min(max(location, 0), length)
        guard clamped != readLocation || next != nextWordRange else { return }
        let all = NSRange(location: 0, length: length)
        manager.removeTemporaryAttribute(.foregroundColor, forCharacterRange: all)
        if style.dimsReadWords, clamped > 0 {
            manager.addTemporaryAttribute(.foregroundColor, value: palette.read, forCharacterRange: NSRange(location: 0, length: clamped))
        }
        if let next, NSMaxRange(next) <= length {
            manager.addTemporaryAttribute(.foregroundColor, value: StageTheme.highlight(style.light), forCharacterRange: next)
        }
        readLocation = clamped
        nextWordRange = next
    }

    // MARK: Motion

    /// Glides to an offset with a spring, like a hand moving the page.
    func glide(to newTarget: CGFloat) {
        target = max(0, min(newTarget, endOffset))

        run()
    }

    /// Jumps without motion.
    func setOffset(_ value: CGFloat) {
        target = nil
        velocity = 0
        offset = max(0, min(value, endOffset))
        clipView.setBoundsOrigin(NSPoint(x: 0, y: offset))
        onOffsetChanged?(offset)
    }

    var isAtEnd: Bool { offset >= endOffset - 0.5 }

    private func run() {
        guard link == nil, window != nil else { return }
        let link = displayLink(target: self, selector: #selector(step(_:)))
        link.add(to: .main, forMode: .common)
        self.link = link
        lastTimestamp = 0
    }

    func halt() {
        link?.invalidate()
        link = nil
        easedTarget = nil
        speed = 0
        target = nil
        velocity = 0
    }

    @objc private func step(_ link: CADisplayLink) {
        let now = link.timestamp
        let dt = lastTimestamp == 0 ? 1.0 / 60 : min(now - lastTimestamp, 1.0 / 20)
        lastTimestamp = now
        var next = offset
        if let easedTarget {
            speed += (easedTarget - speed) * min(1, CGFloat(dt) * 7)
            if abs(easedTarget - speed) < 0.5 {
                speed = easedTarget
                self.easedTarget = nil
            }
        }
        if speed != 0 {
            next += speed * dt
            // A glide asked for while the text rolls (a line back, a line on) rides along with it: the spring settles on
            // the moving line instead of holding the text still against the rolling.
            if let target { self.target = min(target + speed * dt, endOffset) }
        }
        if let target {
            // A critically damped spring: quick, and never overshoots the line.
            let omega: CGFloat = 10
            let distance = next - target
            let acceleration = -omega * omega * distance - 2 * omega * velocity
            velocity += acceleration * dt
            next += velocity * dt
            if abs(next - target) < 0.25, abs(velocity) < 3 {
                next = target
                velocity = 0
                self.target = nil
            }
        }
        let end = endOffset
        if next >= end, speed > 0 {
            next = end
            speed = 0
            onSettled?()
        }
        next = max(0, min(next, end))
        if next != offset {
            offset = next
            clipView.setBoundsOrigin(NSPoint(x: 0, y: offset))
            onOffsetChanged?(offset)
        }
        if target == nil, speed == 0, easedTarget == nil {
            link.invalidate()
            self.link = nil
        }
    }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        if window == nil { halt() }
    }

    // MARK: Mirror

    private func applyMirror() {
        guard let layer = scrollView.layer ?? { scrollView.wantsLayer = true; return scrollView.layer }() else { return }
        let width = bounds.width, height = bounds.height
        var transform = CGAffineTransform.identity
        if style.mirror == .horizontal || style.mirror == .both {
            transform = transform.translatedBy(x: width, y: 0).scaledBy(x: -1, y: 1)
        }
        if style.mirror == .vertical || style.mirror == .both {
            transform = transform.translatedBy(x: 0, y: height).scaledBy(x: 1, y: -1)
        }
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        layer.anchorPoint = .zero
        layer.setAffineTransform(transform)
        CATransaction.commit()
    }

    // MARK: Pointer

    override func hitTest(_ point: NSPoint) -> NSView? {
        frame.contains(point) ? self : nil
    }

    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

    override func mouseUp(with event: NSEvent) {
        if event.clickCount == 1 { onClick?() }
    }

    override func scrollWheel(with event: NSEvent) {
        guard event.momentumPhase.isEmpty || event.momentumPhase == .changed else { return }
        let delta = event.hasPreciseScrollingDeltas ? event.scrollingDeltaY : event.scrollingDeltaY * 12
        // The deltas already follow the scroll direction chosen in System Settings: like any scroll view, the text
        // moves with the fingers under natural scrolling.
        onNudge?(-delta)
        if event.phase == .ended || event.momentumPhase == .ended || (event.phase.isEmpty && event.momentumPhase.isEmpty) {
            onNudgeEnded?()
        }
    }
}

/// A clip view that lets the text scroll past its end, so the last line can reach the reading line.
private final class FreeClipView: NSClipView {
    override func constrainBoundsRect(_ proposedBounds: NSRect) -> NSRect { proposedBounds }
    override var isFlipped: Bool { true }
}

/// The text view never takes the pointer: the prompter handles clicks and gestures itself.
private final class InertTextView: NSTextView {
    override func hitTest(_ point: NSPoint) -> NSView? { nil }
}

import AppKit
import IsletCore

/// Renders what the prompter shows, for the website: the whole script laid out exactly as the prompter lays it out,
/// in one tall transparent picture that a page can scroll behind a capture of the empty prompter.
@MainActor
public enum DemoRenderer {
    /// Writes the script as the notch prompter draws it: its font, spacing, alignment and colours, `width` points
    /// wide, at twice the resolution.
    public static func renderStrip(of text: String, width: CGFloat, to url: URL) throws {
        let style = PrompterStyle.current(notch: true)
        let script = Script(text)
        let attributed = ScriptTextView.attributed(script, style: style)
        let storage = NSTextStorage(attributedString: attributed)
        let manager = NSLayoutManager()
        storage.addLayoutManager(manager)
        let inset: CGFloat = 18
        let container = NSTextContainer(size: NSSize(width: width - inset * 2, height: .greatestFiniteMagnitude))
        container.lineFragmentPadding = 0
        manager.addTextContainer(container)
        manager.ensureLayout(for: container)
        let height = ceil(manager.usedRect(for: container).height)
        let scale: CGFloat = 2
        guard let bitmap = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: Int(width * scale), pixelsHigh: Int(height * scale),
                                            bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
                                            colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0) else { return }
        bitmap.size = NSSize(width: width, height: height)
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: bitmap)
        // TextKit draws top down: flip the context.
        let context = NSGraphicsContext.current!.cgContext
        context.translateBy(x: 0, y: height)
        context.scaleBy(x: 1, y: -1)
        NSGraphicsContext.current = NSGraphicsContext(cgContext: context, flipped: true)
        manager.drawGlyphs(forGlyphRange: manager.glyphRange(for: container), at: NSPoint(x: inset, y: 0))
        NSGraphicsContext.restoreGraphicsState()
        try bitmap.representation(using: .png, properties: [:])?.write(to: url)
    }
}

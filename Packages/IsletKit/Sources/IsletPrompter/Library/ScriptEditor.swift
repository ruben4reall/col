import AppKit
import SwiftUI

/// The script editor: a plain text view that shows the light markup as you type (headings, cues, emphasis), in a
/// comfortable column.
struct ScriptEditor: NSViewRepresentable {
    let documentID: String
    @Binding var text: String
    /// Documents dropped on the script: imported as new scripts, as anywhere else in the window.
    var onDropFiles: ([URL]) -> Bool = { _ in false }

    func makeCoordinator() -> Coordinator { Coordinator(self) }

    func makeNSView(context: Context) -> NSScrollView {
        let storage = NSTextStorage()
        let manager = NSLayoutManager()
        storage.addLayoutManager(manager)
        let container = NSTextContainer(size: NSSize(width: 600, height: CGFloat.greatestFiniteMagnitude))
        container.widthTracksTextView = true
        manager.addTextContainer(container)
        let editor = ColumnTextView(frame: NSRect(x: 0, y: 0, width: 600, height: 400), textContainer: container)
        editor.minSize = NSSize(width: 0, height: 0)
        editor.maxSize = NSSize(width: CGFloat.greatestFiniteMagnitude, height: CGFloat.greatestFiniteMagnitude)
        editor.isVerticallyResizable = true
        editor.isHorizontallyResizable = false
        editor.autoresizingMask = [.width]
        editor.isRichText = false
        editor.allowsUndo = true
        editor.usesFindBar = true
        editor.isIncrementalSearchingEnabled = true
        editor.isAutomaticQuoteSubstitutionEnabled = false
        editor.isAutomaticDashSubstitutionEnabled = false
        editor.isAutomaticTextReplacementEnabled = false
        editor.drawsBackground = false
        editor.font = Markup.body
        editor.textColor = .labelColor
        editor.insertionPointColor = StageTheme.accentNS
        editor.typingAttributes = Markup.baseAttributes
        editor.delegate = context.coordinator
        editor.onDropFiles = onDropFiles
        editor.string = text
        Markup.apply(to: editor)

        let scrollView = NSScrollView()
        scrollView.drawsBackground = false
        scrollView.hasVerticalScroller = true
        scrollView.autohidesScrollers = true
        scrollView.documentView = editor
        context.coordinator.textView = editor
        DispatchQueue.main.async { editor.window?.makeFirstResponder(editor) }
        return scrollView
    }

    func updateNSView(_ scrollView: NSScrollView, context: Context) {
        guard let editor = scrollView.documentView as? NSTextView else { return }
        context.coordinator.parent = self
        if context.coordinator.documentID != documentID {
            context.coordinator.documentID = documentID
            editor.string = text
            Markup.apply(to: editor)
            editor.undoManager?.removeAllActions()
            editor.setSelectedRange(NSRange(location: 0, length: 0))
            editor.scrollToBeginningOfDocument(nil)
        } else if editor.string != text, !context.coordinator.isEditing {
            editor.string = text
            Markup.apply(to: editor)
        }
    }

    @MainActor
    final class Coordinator: NSObject, NSTextViewDelegate {
        var parent: ScriptEditor
        var documentID: String
        weak var textView: NSTextView?
        var isEditing = false

        init(_ parent: ScriptEditor) {
            self.parent = parent
            documentID = parent.documentID
        }

        func textDidChange(_ notification: Notification) {
            guard let textView else { return }
            isEditing = true
            Markup.apply(to: textView)
            parent.text = textView.string
            isEditing = false
        }
    }
}

/// Keeps the text in a readable column, centred in wide windows, and flowing around the play button in the top
/// right corner of the panel.
final class ColumnTextView: NSTextView {
    static let column: CGFloat = 720
    var onDropFiles: (([URL]) -> Bool)?

    /// A file dropped on the text is imported, not written into the script as a path; dropped text is inserted.
    override func performDragOperation(_ sender: NSDraggingInfo) -> Bool {
        let files = sender.draggingPasteboard.readObjects(forClasses: [NSURL.self], options: [.urlReadingFileURLsOnly: true]) as? [URL] ?? []
        if !files.isEmpty, let onDropFiles { return onDropFiles(files) }
        return super.performDragOperation(sender)
    }
    /// The corner the play button covers, in points from the top right of the panel.
    static let buttonCorner = CGSize(width: 124, height: 118)

    override func setFrameSize(_ newSize: NSSize) {
        super.setFrameSize(newSize)
        let side = max(26, (newSize.width - Self.column) / 2)
        if textContainerInset.width != side { textContainerInset = NSSize(width: side, height: 24) }
        guard let container = textContainer else { return }
        // In the container's space: its right edge sits `side` points in from the panel's.
        let reach = max(0, Self.buttonCorner.width - side)
        let corner = NSRect(x: container.size.width - reach, y: 0, width: reach, height: Self.buttonCorner.height - 24)
        let exclusion = reach > 0 ? [NSBezierPath(rect: corner)] : []
        if container.exclusionPaths != exclusion { container.exclusionPaths = exclusion }
    }
}

/// How the editor shows the markup.
@MainActor
enum Markup {
    static let body = NSFont.systemFont(ofSize: 15, weight: .regular)
    static var paragraph: NSParagraphStyle {
        let style = NSMutableParagraphStyle()
        style.lineHeightMultiple = 1.35
        style.paragraphSpacing = 6
        return style
    }
    static var baseAttributes: [NSAttributedString.Key: Any] {
        [.font: body, .foregroundColor: NSColor.labelColor, .paragraphStyle: paragraph]
    }

    private static let heading = try! NSRegularExpression(pattern: "^[ \\t]*#{1,6}[ \\t].*$", options: [.anchorsMatchLines])
    private static let cue = try! NSRegularExpression(pattern: "\\[[^\\]\\n]+\\]")
    private static let emphasis = try! NSRegularExpression(pattern: "\\*\\*[^*\\n]+\\*\\*")
    static let cueColor = NSColor(name: nil) { appearance in
        appearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua ? StageTheme.highlightNS : NSColor(srgbRed: 0.82, green: 0.32, blue: 0.2, alpha: 1)
    }

    static func apply(to textView: NSTextView) {
        guard let storage = textView.textStorage else { return }
        let text = storage.string as NSString
        let all = NSRange(location: 0, length: text.length)
        storage.beginEditing()
        storage.setAttributes(baseAttributes, range: all)
        heading.enumerateMatches(in: storage.string, range: all) { match, _, _ in
            guard let range = match?.range else { return }
            storage.addAttributes([.font: NSFont.systemFont(ofSize: 19, weight: .bold)], range: range)
            let marks = text.range(of: "^[ \\t]*#{1,6}", options: .regularExpression, range: range)
            if marks.location != NSNotFound { storage.addAttribute(.foregroundColor, value: NSColor.tertiaryLabelColor, range: marks) }
        }
        cue.enumerateMatches(in: storage.string, range: all) { match, _, _ in
            guard let range = match?.range else { return }
            storage.addAttributes([.foregroundColor: cueColor, .font: NSFont.systemFont(ofSize: 13, weight: .semibold)], range: range)
        }
        emphasis.enumerateMatches(in: storage.string, range: all) { match, _, _ in
            guard let range = match?.range else { return }
            storage.addAttribute(.font, value: NSFont.systemFont(ofSize: 15, weight: .bold), range: range)
            storage.addAttribute(.foregroundColor, value: NSColor.tertiaryLabelColor, range: NSRange(location: range.location, length: 2))
            storage.addAttribute(.foregroundColor, value: NSColor.tertiaryLabelColor, range: NSRange(location: NSMaxRange(range) - 2, length: 2))
        }
        storage.endEditing()
        textView.typingAttributes = baseAttributes
    }
}

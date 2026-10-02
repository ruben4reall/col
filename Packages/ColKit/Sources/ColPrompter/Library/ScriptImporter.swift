import AppKit
import PDFKit
import UniformTypeIdentifiers

/// Reads the text of a document dropped on the prompter's library or opened with Col.
public enum ScriptImporter {
    public static let contentTypes: [UTType] = [
        .plainText, .utf8PlainText, .text, .rtf, .rtfd, .pdf, .html,
        UTType("net.daringfireball.markdown") ?? .plainText,
        UTType("org.openxmlformats.wordprocessingml.document") ?? .data,
        UTType("org.openxmlformats.presentationml.presentation") ?? .data,
        UTType("com.microsoft.word.doc") ?? .data,
        UTType("org.oasis-open.opendocument.text") ?? .data,
    ]

    public enum Failure: LocalizedError {
        case unreadable(String)
        case empty(String)

        public var errorDescription: String? {
            switch self {
            case .unreadable(let name): String(localized: "Col can't read the text of “\(name)”.", bundle: .module)
            case .empty(let name): String(localized: "“\(name)” has no text to prompt.", bundle: .module)
            }
        }
    }

    public static func text(from url: URL) throws -> String {
        let name = url.lastPathComponent
        let text: String?
        switch url.pathExtension.lowercased() {
        case "pdf":
            text = PDFDocument(url: url)?.string
        case "pptx":
            text = try presentationNotes(url)
        case "txt", "md", "markdown", "text", "":
            text = (try? String(contentsOf: url, encoding: .utf8)) ?? (try? String(contentsOf: url, encoding: .isoLatin1))
        default:
            text = (try? NSAttributedString(url: url, options: [:], documentAttributes: nil))?.string
        }
        guard let text else { throw Failure.unreadable(name) }
        let cleaned = text.replacingOccurrences(of: "\u{2028}", with: "\n").replacingOccurrences(of: "\u{00A0}", with: " ")
        guard !cleaned.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { throw Failure.empty(name) }
        return cleaned
    }

    /// The speaker notes of a PowerPoint file, slide after slide, each under a "Slide n" heading. A .pptx is a zip
    /// archive; the system's unzip reads each notes page without extracting anything to disk.
    private static func presentationNotes(_ url: URL) throws -> String {
        let listing = try run("/usr/bin/zipinfo", ["-1", url.path])
        let pages = listing.split(separator: "\n").map(String.init)
            .filter { $0.hasPrefix("ppt/notesSlides/notesSlide") && $0.hasSuffix(".xml") }
            .sorted { number(in: $0) < number(in: $1) }
        var sections: [String] = []
        for page in pages {
            let xml = try run("/usr/bin/unzip", ["-p", url.path, page])
            let paragraphs = NotesParser.paragraphs(in: Data(xml.utf8)).filter { !$0.isEmpty }
            guard !paragraphs.isEmpty else { continue }
            sections.append("# " + String(localized: "Slide \(number(in: page))", bundle: .module) + "\n" + paragraphs.joined(separator: "\n"))
        }
        return sections.joined(separator: "\n\n")
    }

    private static func number(in path: String) -> Int {
        Int(path.filter(\.isNumber)) ?? 0
    }

    private static func run(_ tool: String, _ arguments: [String]) throws -> String {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: tool)
        process.arguments = arguments
        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = FileHandle.nullDevice
        try process.run()
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()
        return String(decoding: data, as: UTF8.self)
    }
}

/// Collects the text of each paragraph of a notes page, leaving out fields such as the slide number.
private final class NotesParser: NSObject, XMLParserDelegate {
    private var paragraphs: [String] = []
    private var current = ""
    private var inText = false
    private var fieldDepth = 0

    static func paragraphs(in data: Data) -> [String] {
        let delegate = NotesParser()
        let parser = XMLParser(data: data)
        parser.delegate = delegate
        parser.parse()
        return delegate.paragraphs.map { $0.trimmingCharacters(in: .whitespaces) }
    }

    func parser(_ parser: XMLParser, didStartElement name: String, namespaceURI: String?, qualifiedName: String?, attributes: [String: String] = [:]) {
        switch name {
        case "a:fld": fieldDepth += 1
        case "a:t": inText = fieldDepth == 0
        default: break
        }
    }

    func parser(_ parser: XMLParser, didEndElement name: String, namespaceURI: String?, qualifiedName: String?) {
        switch name {
        case "a:fld": fieldDepth -= 1
        case "a:t": inText = false
        case "a:p":
            paragraphs.append(current)
            current = ""
        default: break
        }
    }

    func parser(_ parser: XMLParser, foundCharacters string: String) {
        if inText { current += string }
    }
}

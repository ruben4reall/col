import Foundation

/// The command, file or address of a permission request, the way the Allow card shows it: whole, never cut, with
/// every character that could hide part of it from the reader made visible. What Allow approves is what the card
/// shows; a command too long to check there is left to the terminal, which shows it whole.
public struct RequestDetail: Equatable, Sendable {
    /// The text to show: each line break marked ⏎, tabs ⇥, runs of spaces as ␣ (counted past three), control
    /// characters as their symbols, and invisible or blank ones (zero-width, joiners, variation selectors, fillers,
    /// direction marks, unusual spaces) by their code.
    public let shown: String
    /// Whether the card shows it all at once. When it does not, Allow is off and the request is answered in the
    /// terminal.
    public let fitsCard: Bool

    /// Characters on a line of the card's monospaced text in the smallest island: 11-point SF Mono advances 6.8
    /// points, and the compact island's card has 360 points for it (PermissionCardLayout).
    public static let columns = 52
    /// Lines the card shows before it would have to scroll.
    public static let lines = 3

    public init(_ text: String) {
        shown = Self.visible(text)
        fitsCard = Self.lineCount(shown, columns: Self.columns) <= Self.lines
    }

    static func visible(_ text: String) -> String {
        var shown = ""
        var spaces = 0
        func flushSpaces() {
            switch spaces {
            case 0: break
            case 1: shown += " "
            case 2, 3: shown += String(repeating: "␣", count: spaces)
            default: shown += "␣×\(spaces)"
            }
            spaces = 0
        }
        // Scalar by scalar: a carriage return before a line break is a character of its own here, not part of it.
        for scalar in text.unicodeScalars {
            if scalar == " " {
                spaces += 1
                continue
            }
            flushSpaces()
            shown += scalar == "\n" ? "⏎\n" : visible(scalar)
        }
        flushSpaces()
        // A command that ends with a line break shows the mark, not an empty line after it.
        if shown.hasSuffix("⏎\n") { shown.removeLast() }
        return shown
    }

    private static func visible(_ scalar: Unicode.Scalar) -> String {
        switch scalar.value {
        case 0x09: return "⇥"
        // Other C0 controls and DEL as their Control Pictures: ␍, ␛ and the like.
        case 0x00...0x1F: return Unicode.Scalar(0x2400 + scalar.value).map(String.init) ?? "?"
        case 0x7F: return "␡"
        default: break
        }
        let code = "‹U+\(String(format: "%04X", scalar.value))›"
        // Drawn as nothing, or as a blank: a combining grapheme joiner or a variation selector inside a word, a Hangul
        // filler or a blank Braille pattern standing for a space.
        if scalar.properties.isDefaultIgnorableCodePoint || blanks.contains(scalar.value) { return code }
        switch scalar.properties.generalCategory {
        case .control, .format, .lineSeparator, .paragraphSeparator, .spaceSeparator, .privateUse, .unassigned:
            return code
        default:
            return String(scalar)
        }
    }

    /// Letters and symbols drawn blank: the Hangul fillers (default-ignorable too, named here all the same) and the
    /// blank Braille pattern.
    private static let blanks: Set<UInt32> = [0x115F, 0x1160, 0x3164, 0xFFA0, 0x2800]

    /// Lines the text takes at `columns` characters, broken at spaces as the card breaks it; a run with no space
    /// wider than a line takes as many as it needs. Wide characters count twice.
    static func lineCount(_ text: String, columns: Int) -> Int {
        text.split(separator: "\n", omittingEmptySubsequences: false).reduce(0) { total, line in
            var rows = 1
            var used = 0
            for word in line.split(separator: " ", omittingEmptySubsequences: false) {
                var width = word.reduce(0) { $0 + (isWide($1) ? 2 : 1) }
                let needed = used == 0 ? width : used + 1 + width
                if needed <= columns {
                    used = needed
                    continue
                }
                if used > 0 { rows += 1 }
                while width > columns {
                    rows += 1
                    width -= columns
                }
                used = width
            }
            return total + rows
        }
    }

    /// East Asian wide characters and emoji, which take two columns of monospaced text.
    private static let wideRanges: [ClosedRange<UInt32>] = [
        0x1100...0x115F, 0x2E80...0xA4CF, 0xAC00...0xD7A3, 0xF900...0xFAFF, 0xFE30...0xFE4F, 0xFF00...0xFF60,
        0xFFE0...0xFFE6, 0x1F300...0x1FAFF, 0x20000...0x3FFFD,
    ]

    private static func isWide(_ character: Character) -> Bool {
        guard let value = character.unicodeScalars.first?.value else { return false }
        return wideRanges.contains { $0.contains(value) }
    }
}

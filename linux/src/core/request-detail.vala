/* The command, file or address of a permission request, the way the Allow card shows it: whole, never cut, with every
 * character that could hide part of it from the reader made visible. What Allow approves is what the card shows; a
 * command too long to check there is left to the terminal. The same rules as ColCore's RequestDetail.swift. */

namespace Col {
    public class RequestDetail {
        /* The text to show: line breaks marked ⏎, tabs ⇥, runs of spaces as ␣, control characters as their symbols, and
         * invisible or blank ones by their code. */
        public string shown;
        /* Whether the card shows it all at once. When it does not, Allow is off and the request is answered in the
         * terminal. */
        public bool fits_card;

        /* Characters on a line of the card's monospaced text, and lines it shows before it would have to scroll. */
        public const int COLUMNS = 52;
        public const int LINES = 3;

        public RequestDetail (string text) {
            shown = visible (text);
            fits_card = line_count (shown, COLUMNS) <= LINES;
        }

        public static string visible (string text) {
            var shown = new StringBuilder ();
            int spaces = 0;
            int index = 0;
            unichar c;
            while (text.get_next_char (ref index, out c)) {
                if (c == ' ') {
                    spaces++;
                    continue;
                }
                flush_spaces (shown, ref spaces);
                if (c == '\n') {
                    shown.append ("⏎\n");
                } else {
                    shown.append (visible_char (c));
                }
            }
            flush_spaces (shown, ref spaces);
            var result = shown.str;
            // A command that ends with a line break shows the mark, not an empty line after it.
            if (result.has_suffix ("⏎\n")) {
                result = result.substring (0, result.length - 1);
            }
            return result;
        }

        static void flush_spaces (StringBuilder shown, ref int spaces) {
            switch (spaces) {
            case 0:
                break;
            case 1:
                shown.append (" ");
                break;
            case 2:
            case 3:
                for (int i = 0; i < spaces; i++) {
                    shown.append ("␣");
                }
                break;
            default:
                shown.append ("␣×%d".printf (spaces));
                break;
            }
            spaces = 0;
        }

        static string visible_char (unichar c) {
            if (c == '\t') {
                return "⇥";
            }
            if (c < 0x20) {
                // C0 controls as their Control Pictures: ␍, ␛ and the like.
                return ((unichar) (0x2400 + c)).to_string ();
            }
            if (c == 0x7f) {
                return "␡";
            }
            string code = "‹U+%04X›".printf ((uint) c);
            if (is_default_ignorable (c) || c == 0x115F || c == 0x1160 || c == 0x3164 || c == 0xFFA0 || c == 0x2800) {
                return code;
            }
            switch (c.type ()) {
            case UnicodeType.CONTROL:
            case UnicodeType.FORMAT:
            case UnicodeType.LINE_SEPARATOR:
            case UnicodeType.PARAGRAPH_SEPARATOR:
            case UnicodeType.SPACE_SEPARATOR:
            case UnicodeType.PRIVATE_USE:
            case UnicodeType.UNASSIGNED:
            case UnicodeType.SURROGATE:
                return code;
            default:
                return c.to_string ();
            }
        }

        /* Unicode's Default_Ignorable_Code_Point: drawn as nothing, or as a blank. */
        public static bool is_default_ignorable (unichar c) {
            uint v = (uint) c;
            return v == 0x00AD || v == 0x034F || v == 0x061C || (v >= 0x115F && v <= 0x1160) || (v >= 0x17B4 && v <= 0x17B5)
                || (v >= 0x180B && v <= 0x180F) || (v >= 0x200B && v <= 0x200F) || (v >= 0x202A && v <= 0x202E)
                || (v >= 0x2060 && v <= 0x206F) || v == 0x3164 || (v >= 0xFE00 && v <= 0xFE0F) || v == 0xFEFF
                || v == 0xFFA0 || (v >= 0xFFF0 && v <= 0xFFF8) || (v >= 0x1BCA0 && v <= 0x1BCA3)
                || (v >= 0x1D173 && v <= 0x1D17A) || (v >= 0xE0000 && v <= 0xE0FFF);
        }

        /* Lines the text takes at `columns` characters, broken at spaces as the card breaks it; a run with no space
         * wider than a line takes as many as it needs. Wide characters count twice. */
        public static int line_count (string text, int columns) {
            int total = 0;
            foreach (unowned string line in text.split ("\n")) {
                int rows = 1;
                int used = 0;
                foreach (unowned string word in line.split (" ")) {
                    int width = 0;
                    int index = 0;
                    unichar c;
                    while (word.get_next_char (ref index, out c)) {
                        if (c.iszerowidth ()) {
                            continue;
                        }
                        width += is_wide (c) ? 2 : 1;
                    }
                    int needed = used == 0 ? width : used + 1 + width;
                    if (needed <= columns) {
                        used = needed;
                        continue;
                    }
                    if (used > 0) {
                        rows++;
                    }
                    while (width > columns) {
                        rows++;
                        width -= columns;
                    }
                    used = width;
                }
                total += rows;
            }
            return total;
        }

        static bool is_wide (unichar c) {
            uint v = (uint) c;
            return (v >= 0x1100 && v <= 0x115F) || (v >= 0x2E80 && v <= 0xA4CF) || (v >= 0xAC00 && v <= 0xD7A3)
                || (v >= 0xF900 && v <= 0xFAFF) || (v >= 0xFE30 && v <= 0xFE4F) || (v >= 0xFF00 && v <= 0xFF60)
                || (v >= 0xFFE0 && v <= 0xFFE6) || (v >= 0x1F300 && v <= 0x1FAFF) || (v >= 0x20000 && v <= 0x3FFFD);
        }
    }
}

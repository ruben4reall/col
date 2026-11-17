import AppKit

/// The icons a drawer can show: SF Symbols, the icons macOS draws its own menu bar with, grouped by theme. A search
/// matches a theme or any part of a symbol's name ("lock", "cloud", "chart"), and an exact SF Symbol name outside the
/// library works too. `SymbolLibraryTests` checks that every name exists on this macOS.
public enum SymbolLibrary {
    public struct Section: Identifiable, Sendable {
        public let title: String
        public let symbols: [String]
        public var id: String { title }
    }

    /// Theme titles are the keys of `Strings.symbolSection(_:)`.
    public static let sections: [Section] = [
        Section(title: "Files & Cloud", symbols: ["cloud", "cloud.fill", "icloud", "icloud.fill", "icloud.and.arrow.down", "arrow.clockwise.icloud", "externaldrive", "externaldrive.fill", "internaldrive", "internaldrive.fill", "folder", "folder.fill", "folder.badge.gearshape", "tray", "tray.fill", "tray.full", "tray.full.fill", "tray.2", "tray.2.fill", "archivebox", "archivebox.fill", "doc", "doc.fill", "doc.on.doc", "doc.on.doc.fill", "doc.text", "doc.text.fill", "paperclip", "server.rack", "arrow.triangle.2.circlepath", "arrow.up.arrow.down.circle", "square.and.arrow.down", "square.and.arrow.up", "shippingbox", "shippingbox.fill", "externaldrive.connected.to.line.below"]),
        Section(title: "Security & Privacy", symbols: ["lock", "lock.fill", "lock.open", "lock.open.fill", "lock.shield", "lock.shield.fill", "shield", "shield.fill", "shield.lefthalf.filled", "checkmark.shield", "checkmark.shield.fill", "exclamationmark.shield", "key", "key.fill", "key.horizontal", "key.horizontal.fill", "eye", "eye.fill", "eye.slash", "eye.slash.fill", "hand.raised", "hand.raised.fill", "network.badge.shield.half.filled", "person.badge.key", "faceid", "touchid", "lock.rectangle", "lock.laptopcomputer"]),
        Section(title: "Messages & People", symbols: ["bubble.left", "bubble.left.fill", "bubble.right", "bubble.right.fill", "bubble.left.and.bubble.right", "bubble.left.and.bubble.right.fill", "message", "message.fill", "envelope", "envelope.fill", "envelope.open", "envelope.badge", "paperplane", "paperplane.fill", "phone", "phone.fill", "video", "video.fill", "bell", "bell.fill", "bell.badge", "at", "person", "person.fill", "person.2", "person.2.fill", "person.3", "person.3.fill", "megaphone", "megaphone.fill", "quote.bubble", "captions.bubble", "bubble.middle.bottom"]),
        Section(title: "Developer", symbols: ["hammer", "hammer.fill", "wrench.and.screwdriver", "wrench.and.screwdriver.fill", "terminal", "terminal.fill", "chevron.left.forwardslash.chevron.right", "curlybraces", "curlybraces.square", "cpu", "cpu.fill", "memorychip", "memorychip.fill", "cube", "cube.fill", "cube.transparent", "gearshape.2", "gearshape.2.fill", "ladybug", "ladybug.fill", "ant", "ant.fill", "point.3.connected.trianglepath.dotted", "arrow.triangle.branch", "network", "globe", "hammer.circle", "wrench.adjustable"]),
        Section(title: "AI & Ideas", symbols: ["sparkles", "sparkle", "wand.and.stars", "wand.and.rays", "brain", "brain.head.profile", "lightbulb", "lightbulb.fill", "atom", "text.bubble", "text.bubble.fill", "waveform", "waveform.circle", "mic", "mic.fill", "star", "star.fill", "moon.stars", "rays", "bolt", "bolt.fill"]),
        Section(title: "Music & Video", symbols: ["music.note", "music.note.list", "music.quarternote.3", "headphones", "hifispeaker", "hifispeaker.fill", "speaker.wave.2", "speaker.wave.2.fill", "play", "play.fill", "play.circle", "play.circle.fill", "film", "film.fill", "tv", "tv.fill", "camera", "camera.fill", "radio", "radio.fill", "guitars", "pianokeys", "airpods", "beats.headphones", "music.mic"]),
        Section(title: "Devices", symbols: ["display", "display.2", "desktopcomputer", "laptopcomputer", "macbook", "keyboard", "keyboard.fill", "computermouse", "computermouse.fill", "printer", "printer.fill", "scanner", "iphone", "ipad", "applewatch", "gamecontroller", "gamecontroller.fill", "cable.connector", "powerplug", "powerplug.fill", "battery.100", "battery.75percent", "wifi", "antenna.radiowaves.left.and.right", "dot.radiowaves.left.and.right", "web.camera"]),
        Section(title: "System", symbols: ["gearshape", "gearshape.fill", "gauge.with.dots.needle.33percent", "gauge.with.dots.needle.67percent", "speedometer", "chart.bar", "chart.bar.fill", "chart.pie", "chart.pie.fill", "chart.line.uptrend.xyaxis", "waveform.path.ecg", "thermometer.medium", "fan", "fan.fill", "clock", "clock.fill", "timer", "stopwatch", "hourglass", "cup.and.saucer", "cup.and.saucer.fill", "moon", "moon.fill", "sun.max", "sun.max.fill", "power", "slider.horizontal.3", "switch.2", "menubar.rectangle"]),
        Section(title: "Productivity", symbols: ["calendar", "calendar.badge.clock", "alarm", "checklist", "checkmark.circle", "checkmark.circle.fill", "checkmark.square", "list.bullet", "list.bullet.rectangle", "note.text", "pencil", "square.and.pencil", "book", "book.fill", "bookmark", "bookmark.fill", "tag", "tag.fill", "flag", "flag.fill", "pin", "pin.fill", "briefcase", "briefcase.fill", "chart.bar.doc.horizontal", "books.vertical", "books.vertical.fill"]),
        Section(title: "Design", symbols: ["paintbrush", "paintbrush.fill", "paintbrush.pointed", "paintbrush.pointed.fill", "paintpalette", "paintpalette.fill", "pencil.tip", "eyedropper", "eyedropper.halffull", "scribble", "lasso", "crop", "photo", "photo.fill", "photo.on.rectangle", "camera.aperture", "circle.lefthalf.filled", "textformat", "textformat.size", "ruler", "ruler.fill", "rectangle.3.group", "square.grid.2x2"]),
        Section(title: "Games & Fun", symbols: ["dice", "dice.fill", "puzzlepiece", "puzzlepiece.fill", "trophy", "trophy.fill", "flag.checkered", "figure.run", "sportscourt", "soccerball", "basketball", "football", "tennis.racket", "party.popper", "balloon", "crown", "crown.fill", "gift", "gift.fill"]),
        Section(title: "Home & Places", symbols: ["house", "house.fill", "building.2", "building.2.fill", "building.columns", "car", "car.fill", "airplane", "bicycle", "tram", "map", "map.fill", "location", "location.fill", "globe.americas", "globe.europe.africa", "mappin", "mappin.and.ellipse", "signpost.right", "bed.double", "sofa", "fork.knife", "cart", "cart.fill", "bag", "bag.fill", "creditcard", "creditcard.fill", "banknote", "dollarsign.circle", "eurosign.circle"]),
        Section(title: "Nature & Weather", symbols: ["leaf", "leaf.fill", "tree", "flame", "flame.fill", "drop", "drop.fill", "snowflake", "cloud.sun", "cloud.sun.fill", "cloud.rain", "cloud.bolt", "tornado", "wind", "pawprint", "pawprint.fill", "bird", "fish", "tortoise", "hare", "carrot", "mountain.2"]),
        Section(title: "Shapes", symbols: ["circle", "circle.fill", "square", "square.fill", "triangle", "triangle.fill", "diamond", "diamond.fill", "hexagon", "hexagon.fill", "seal", "seal.fill", "heart", "heart.fill", "suit.club", "suit.diamond", "suit.spade", "suit.heart", "infinity", "number", "asterisk", "plus.circle", "xmark.circle", "circle.grid.2x2", "circle.grid.3x3", "square.grid.3x3", "square.stack.3d.up", "rectangle.stack", "square.3.layers.3d", "dot.circle", "smallcircle.filled.circle"]),
        Section(title: "Arrows", symbols: ["arrow.up", "arrow.down", "arrow.left.arrow.right", "arrow.up.arrow.down", "arrow.clockwise", "arrow.uturn.left", "arrowshape.turn.up.right", "arrow.up.right.square", "chevron.up.chevron.down", "arrow.down.circle", "arrow.up.circle"]),
    ]

    public static var allSymbols: [String] { sections.flatMap(\.symbols) }

    /// Sections whose symbols match `query`, each keeping only its matches; the whole library for an empty query. A name
    /// macOS knows but the library lacks comes first, alone, so any SF Symbol can be used.
    public static func search(_ query: String) -> [Section] {
        let needle = query.trimmingCharacters(in: .whitespaces).lowercased()
        guard !needle.isEmpty else { return sections }
        var result: [Section] = []
        if !allSymbols.contains(needle), NSImage(systemSymbolName: needle, accessibilityDescription: nil) != nil {
            result.append(Section(title: needle, symbols: [needle]))
        }
        for section in sections {
            if section.title.lowercased().contains(needle) {
                result.append(section)
                continue
            }
            let matches = section.symbols.filter { name in
                name.split(separator: ".").contains { $0.hasPrefix(needle) } || name.contains(needle)
            }
            if !matches.isEmpty { result.append(Section(title: section.title, symbols: matches)) }
        }
        return result
    }
}

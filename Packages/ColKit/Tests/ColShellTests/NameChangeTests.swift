import Foundation
@testable import ColShell
import Testing

struct NameChangeTests {
    @Test func versionsCompareNumberByNumber() {
        #expect(NameChange.isOlder("1.2.0", than: "2.0.0"))
        #expect(NameChange.isOlder("1.9.2", than: "1.10.0"))
        #expect(!NameChange.isOlder("2.0.0", than: "2.0.0"))
        #expect(!NameChange.isOlder("2.0.1", than: "2.0.0"))
    }
}

struct NameChangeMoveTests {
    @Test func foldersMergeWithoutReplacingAnything() throws {
        let files = FileManager.default
        let root = files.temporaryDirectory.appendingPathComponent("col-move-\(UUID().uuidString)")
        defer { try? files.removeItem(at: root) }
        let old = root.appendingPathComponent("Islet"), new = root.appendingPathComponent("Col")
        try files.createDirectory(at: old.appendingPathComponent("Scripts"), withIntermediateDirectories: true)
        try files.createDirectory(at: new.appendingPathComponent("Scripts"), withIntermediateDirectories: true)
        try "mine".write(to: old.appendingPathComponent("Scripts/talk.md"), atomically: true, encoding: .utf8)
        try "old".write(to: old.appendingPathComponent("Scripts/welcome.md"), atomically: true, encoding: .utf8)
        try "new".write(to: new.appendingPathComponent("Scripts/welcome.md"), atomically: true, encoding: .utf8)
        try "lyrics".write(to: old.appendingPathComponent("song.lrc"), atomically: true, encoding: .utf8)

        NameChange.move(old, into: new)

        #expect(try String(contentsOf: new.appendingPathComponent("Scripts/talk.md"), encoding: .utf8) == "mine")
        #expect(try String(contentsOf: new.appendingPathComponent("Scripts/welcome.md"), encoding: .utf8) == "new")
        #expect(try String(contentsOf: new.appendingPathComponent("song.lrc"), encoding: .utf8) == "lyrics")
    }

    @Test func aFolderAloneMovesWhole() throws {
        let files = FileManager.default
        let root = files.temporaryDirectory.appendingPathComponent("col-move-\(UUID().uuidString)")
        defer { try? files.removeItem(at: root) }
        let old = root.appendingPathComponent("Islet"), new = root.appendingPathComponent("Col")
        try files.createDirectory(at: old.appendingPathComponent("Lyrics"), withIntermediateDirectories: true)

        NameChange.move(old, into: new)

        #expect(files.fileExists(atPath: new.appendingPathComponent("Lyrics").path))
        #expect(!files.fileExists(atPath: old.path))
    }
}

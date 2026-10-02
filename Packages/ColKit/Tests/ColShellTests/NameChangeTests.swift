import Foundation
@testable import ColShell
import Testing

/// A folder of its own for each test, gone at the end.
private func scratch() throws -> URL {
    let url = FileManager.default.temporaryDirectory.appendingPathComponent("col-name-\(UUID().uuidString)")
    try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
    return url.resolvingSymlinksInPath()
}

private func executable(at url: URL) throws {
    try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
    FileManager.default.createFile(atPath: url.path, contents: Data("#!/bin/sh\n".utf8), attributes: [.posixPermissions: 0o755])
}

struct NameChangeTests {
    @Test func versionsCompareNumberByNumber() {
        #expect(NameChange.isOlder("1.2.0", than: "2.0.0"))
        #expect(NameChange.isOlder("1.9.2", than: "1.10.0"))
        #expect(!NameChange.isOlder("2.0.0", than: "2.0.0"))
        #expect(!NameChange.isOlder("2.0.1", than: "2.0.0"))
    }
}

struct NameChangeSettingsTests {
    private func defaults() -> (UserDefaults, String) {
        let name = "col-tests-\(UUID().uuidString)"
        return (UserDefaults(suiteName: name)!, name)
    }

    @Test func lyricsStayOffForSomeoneComingFromIslet() {
        let (defaults, name) = defaults()
        defer { defaults.removePersistentDomain(forName: name) }
        defaults.set(true, forKey: "hasWelcomed")
        defaults.set("0 0 300 200", forKey: "NSWindow Frame IsletFloatingPrompter")

        NameChange.carrySettings(defaults)

        #expect(defaults.object(forKey: "showsLyrics") as? Bool == false)
        #expect(defaults.string(forKey: "NSWindow Frame ColFloatingPrompter") == "0 0 300 200")
    }

    @Test func lyricsAreOnForANewUserAndDecidedOnce() {
        let (defaults, name) = defaults()
        defer { defaults.removePersistentDomain(forName: name) }

        NameChange.carrySettings(defaults)
        #expect(defaults.object(forKey: "showsLyrics") as? Bool == true)

        // Later the welcome is closed before its lyrics question: the choice already made stands.
        defaults.set(true, forKey: "hasWelcomed")
        NameChange.carrySettings(defaults)
        #expect(defaults.object(forKey: "showsLyrics") as? Bool == true)
    }

    @Test func aForcedMoveLeavesLyricsAlone() {
        let (defaults, name) = defaults()
        defer { defaults.removePersistentDomain(forName: name) }
        defaults.set(true, forKey: "hasWelcomed")
        defaults.set("0 0 300 200", forKey: "NSWindow Frame IsletFloatingPrompter")

        NameChange.carrySettings(defaults, decidingLyrics: false)

        #expect(defaults.object(forKey: "showsLyrics") == nil)
        #expect(defaults.string(forKey: "NSWindow Frame ColFloatingPrompter") == "0 0 300 200")
    }

    @Test func aChoiceAlreadyMadeIsKept() {
        let (defaults, name) = defaults()
        defer { defaults.removePersistentDomain(forName: name) }
        defaults.set(true, forKey: "hasWelcomed")
        defaults.set(true, forKey: "showsLyrics")
        defaults.set("new", forKey: "NSWindow Frame ColFloatingPrompter")
        defaults.set("old", forKey: "NSWindow Frame IsletFloatingPrompter")

        NameChange.carrySettings(defaults)

        #expect(defaults.object(forKey: "showsLyrics") as? Bool == true)
        #expect(defaults.string(forKey: "NSWindow Frame ColFloatingPrompter") == "new")
    }
}

struct NameChangeMoveTests {
    @Test func foldersMergeWithoutReplacingAnything() throws {
        let files = FileManager.default
        let root = try scratch()
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
        // What could not join stays where it was.
        #expect(try String(contentsOf: old.appendingPathComponent("Scripts/welcome.md"), encoding: .utf8) == "old")
    }

    @Test func aFolderAloneMovesWhole() throws {
        let files = FileManager.default
        let root = try scratch()
        defer { try? files.removeItem(at: root) }
        let old = root.appendingPathComponent("Islet"), new = root.appendingPathComponent("Col")
        try files.createDirectory(at: old.appendingPathComponent("Lyrics"), withIntermediateDirectories: true)

        NameChange.move(old, into: new)

        #expect(files.fileExists(atPath: new.appendingPathComponent("Lyrics").path))
        #expect(!files.fileExists(atPath: old.path))
    }

    @Test func aMergedFolderLeftEmptyGoesAndLinksMoveAsLinks() throws {
        let files = FileManager.default
        let root = try scratch()
        defer { try? files.removeItem(at: root) }
        let old = root.appendingPathComponent("Islet"), new = root.appendingPathComponent("Col")
        try files.createDirectory(at: old.appendingPathComponent("Extensions"), withIntermediateDirectories: true)
        try files.createDirectory(at: new.appendingPathComponent("Extensions"), withIntermediateDirectories: true)
        try "{}".write(to: old.appendingPathComponent("Extensions/clock.json"), atomically: true, encoding: .utf8)
        try files.createSymbolicLink(atPath: old.appendingPathComponent("latest").path, withDestinationPath: "Extensions")

        NameChange.move(old, into: new)

        #expect(files.fileExists(atPath: new.appendingPathComponent("Extensions/clock.json").path))
        #expect(try files.destinationOfSymbolicLink(atPath: new.appendingPathComponent("latest").path) == "Extensions")
        #expect((try? files.attributesOfItem(atPath: old.path)) == nil)
    }

    @Test func isletsFolderBecomesALinkToCols() throws {
        let files = FileManager.default
        let root = try scratch()
        defer { try? files.removeItem(at: root) }
        let old = root.appendingPathComponent("Islet"), new = root.appendingPathComponent("Col")
        try files.createDirectory(at: old.appendingPathComponent("Scripts"), withIntermediateDirectories: true)

        NameChange.moveLeavingLink(old, into: new)

        #expect(try files.destinationOfSymbolicLink(atPath: old.path) == "Col")
        #expect(files.fileExists(atPath: old.appendingPathComponent("Scripts").path))
    }

    @Test func noLinkForSomeoneWhoNeverHadIslet() throws {
        let files = FileManager.default
        let root = try scratch()
        defer { try? files.removeItem(at: root) }
        let old = root.appendingPathComponent("Islet"), new = root.appendingPathComponent("Col")
        try files.createDirectory(at: new, withIntermediateDirectories: true)

        NameChange.moveLeavingLink(old, into: new)

        #expect((try? files.attributesOfItem(atPath: old.path)) == nil)
    }

    @Test func aLinkOfTheUsersOwnMovesAsALink() throws {
        let files = FileManager.default
        let root = try scratch()
        defer { try? files.removeItem(at: root) }
        let synced = root.appendingPathComponent("Synced/Islet")
        try files.createDirectory(at: synced.appendingPathComponent("Scripts"), withIntermediateDirectories: true)
        try "mine".write(to: synced.appendingPathComponent("Scripts/talk.md"), atomically: true, encoding: .utf8)
        let support = root.appendingPathComponent("Support")
        try files.createDirectory(at: support, withIntermediateDirectories: true)
        let old = support.appendingPathComponent("Islet"), new = support.appendingPathComponent("Col")
        try files.createSymbolicLink(at: old, withDestinationURL: synced)

        NameChange.carryFolder(old, into: new, leavingLink: true)

        // Col's folder leads to the user's, which stays where it is; Islet's leads to Col's.
        #expect(try files.destinationOfSymbolicLink(atPath: new.path) == synced.path)
        #expect(try files.destinationOfSymbolicLink(atPath: old.path) == "Col")
        #expect(try String(contentsOf: new.appendingPathComponent("Scripts/talk.md"), encoding: .utf8) == "mine")
        #expect(try String(contentsOf: synced.appendingPathComponent("Scripts/talk.md"), encoding: .utf8) == "mine")

        // Islet's socket answers there too, and a second run finds nothing left to move.
        ControlServer.answerAsIslet(in: support)
        #expect(try files.destinationOfSymbolicLink(atPath: synced.appendingPathComponent("islet.sock").path) == "col.sock")
        NameChange.carryFolder(old, into: new, leavingLink: true)
        #expect(try files.destinationOfSymbolicLink(atPath: new.path) == synced.path)
        #expect(try files.destinationOfSymbolicLink(atPath: old.path) == "Col")
    }

    @Test func theLinkColLeftIsLeftAlone() throws {
        let files = FileManager.default
        let root = try scratch()
        defer { try? files.removeItem(at: root) }
        let old = root.appendingPathComponent("Islet"), new = root.appendingPathComponent("Col")
        try files.createDirectory(at: new, withIntermediateDirectories: true)
        try "new".write(to: new.appendingPathComponent("notes.md"), atomically: true, encoding: .utf8)
        try files.createSymbolicLink(atPath: old.path, withDestinationPath: "Col")

        NameChange.carryFolder(old, into: new, leavingLink: true)
        NameChange.carryFolder(old, into: new, leavingLink: false)

        #expect(try files.destinationOfSymbolicLink(atPath: old.path) == "Col")
        #expect((try? files.destinationOfSymbolicLink(atPath: new.path)) == nil)
        #expect(try String(contentsOf: new.appendingPathComponent("notes.md"), encoding: .utf8) == "new")
    }

    @Test func aLinkThatLeadsNowhereStaysAsItIs() throws {
        let files = FileManager.default
        let root = try scratch()
        defer { try? files.removeItem(at: root) }
        let old = root.appendingPathComponent("Islet"), new = root.appendingPathComponent("Col")
        try files.createSymbolicLink(atPath: old.path, withDestinationPath: root.appendingPathComponent("Ejected/Islet").path)

        NameChange.carryFolder(old, into: new, leavingLink: true)

        #expect(try files.destinationOfSymbolicLink(atPath: old.path) == root.appendingPathComponent("Ejected/Islet").path)
        #expect((try? files.attributesOfItem(atPath: new.path)) == nil)
    }

    @Test func aFolderThatCouldNotMoveWholeStaysAFolder() throws {
        let files = FileManager.default
        let root = try scratch()
        defer { try? files.removeItem(at: root) }
        let old = root.appendingPathComponent("Islet"), new = root.appendingPathComponent("Col")
        try files.createDirectory(at: old, withIntermediateDirectories: true)
        try files.createDirectory(at: new, withIntermediateDirectories: true)
        try "old".write(to: old.appendingPathComponent("notes.md"), atomically: true, encoding: .utf8)
        try "new".write(to: new.appendingPathComponent("notes.md"), atomically: true, encoding: .utf8)

        NameChange.moveLeavingLink(old, into: new)

        #expect((try? files.destinationOfSymbolicLink(atPath: old.path)) == nil)
        #expect(try String(contentsOf: old.appendingPathComponent("notes.md"), encoding: .utf8) == "old")
    }
}

struct NameChangeLinkTests {
    @Test func linksToAMissingAppAreRepaired() throws {
        let root = try scratch()
        defer { try? FileManager.default.removeItem(at: root) }
        let tool = root.appendingPathComponent("Applications/Col.app/Contents/Helpers/colctl")
        try executable(at: tool)
        let link = root.appendingPathComponent("bin/islet")
        try FileManager.default.createDirectory(at: link.deletingLastPathComponent(), withIntermediateDirectories: true)
        try FileManager.default.createSymbolicLink(atPath: link.path, withDestinationPath: root.path + "/Volumes/Col/Col.app/Contents/Helpers/colctl")

        #expect(NameChange.linkNeedsRepair(link, tool: tool))
    }

    @Test func linksIntoAnIsletAppAreRepaired() throws {
        let root = try scratch()
        defer { try? FileManager.default.removeItem(at: root) }
        let tool = root.appendingPathComponent("Applications/Col.app/Contents/Helpers/colctl")
        let old = root.appendingPathComponent("Applications/Islet.app/Contents/Helpers/colctl")
        try executable(at: tool)
        try executable(at: old)
        let link = root.appendingPathComponent("bin/colctl")
        try FileManager.default.createDirectory(at: link.deletingLastPathComponent(), withIntermediateDirectories: true)
        try FileManager.default.createSymbolicLink(at: link, withDestinationURL: old)

        #expect(NameChange.linkNeedsRepair(link, tool: tool))
    }

    @Test func linksIntoHomebrewsIsletAppLeadToHomebrewsLink() throws {
        let root = try scratch()
        defer { try? FileManager.default.removeItem(at: root) }
        let tool = root.appendingPathComponent("Applications/Islet.app/Contents/Helpers/colctl")
        try executable(at: tool)
        let brew = root.appendingPathComponent("homebrew/bin/islet")
        try FileManager.default.createDirectory(at: brew.deletingLastPathComponent(), withIntermediateDirectories: true)
        try FileManager.default.createSymbolicLink(at: brew, withDestinationURL: tool)
        let bin = root.appendingPathComponent("bin")
        try FileManager.default.createDirectory(at: bin, withIntermediateDirectories: true)
        try FileManager.default.createSymbolicLink(at: bin.appendingPathComponent("islet"), withDestinationURL: tool)
        try FileManager.default.createSymbolicLink(at: bin.appendingPathComponent("colctl"), withDestinationURL: brew)

        // Into the app Homebrew replaces: it goes through Homebrew's link instead, which follows the new app.
        #expect(NameChange.linkNeedsRepair(bin.appendingPathComponent("islet"), tool: brew))
        #expect(!NameChange.linkNeedsRepair(bin.appendingPathComponent("colctl"), tool: brew))
        // A link through Homebrew's that works is left alone, whichever command this copy offers.
        #expect(!NameChange.linkNeedsRepair(bin.appendingPathComponent("colctl"), tool: tool))
    }

    @Test func workingLinksAndFilesAreLeftAlone() throws {
        let root = try scratch()
        defer { try? FileManager.default.removeItem(at: root) }
        let tool = root.appendingPathComponent("Applications/Col.app/Contents/Helpers/colctl")
        let other = root.appendingPathComponent("src/col/.build/colctl")
        try executable(at: tool)
        try executable(at: other)
        let bin = root.appendingPathComponent("bin")
        try FileManager.default.createDirectory(at: bin, withIntermediateDirectories: true)
        // Already this app's command, through a relative link.
        try FileManager.default.createSymbolicLink(atPath: bin.appendingPathComponent("colctl").path,
                                                   withDestinationPath: "../Applications/Col.app/Contents/Helpers/colctl")
        // A command of the user's own choosing that works.
        try FileManager.default.createSymbolicLink(at: bin.appendingPathComponent("islet"), withDestinationURL: other)
        // Not a link at all.
        try executable(at: bin.appendingPathComponent("script"))

        #expect(!NameChange.linkNeedsRepair(bin.appendingPathComponent("colctl"), tool: tool))
        #expect(!NameChange.linkNeedsRepair(bin.appendingPathComponent("islet"), tool: tool))
        #expect(!NameChange.linkNeedsRepair(bin.appendingPathComponent("script"), tool: tool))
        #expect(!NameChange.linkNeedsRepair(bin.appendingPathComponent("absent"), tool: tool))
    }
}

struct IsletSocketTests {
    @Test func isletsSocketLeadsToColsForSomeoneComingFromIslet() throws {
        let files = FileManager.default
        let support = try scratch()
        defer { try? files.removeItem(at: support) }
        let col = support.appendingPathComponent("Col")
        try files.createDirectory(at: col, withIntermediateDirectories: true)
        try "stale".write(to: col.appendingPathComponent("islet.sock"), atomically: true, encoding: .utf8)
        try files.createSymbolicLink(atPath: support.appendingPathComponent("Islet").path, withDestinationPath: "Col")

        ControlServer.answerAsIslet(in: support)

        #expect(try files.destinationOfSymbolicLink(atPath: col.appendingPathComponent("islet.sock").path) == "col.sock")
        #expect(try files.destinationOfSymbolicLink(atPath: support.appendingPathComponent("Islet/islet.sock").path) == "col.sock")
    }

    @Test func nothingInAFolderOfTheUsersOwn() throws {
        let files = FileManager.default
        let support = try scratch()
        defer { try? files.removeItem(at: support) }
        let elsewhere = support.appendingPathComponent("Synced/Islet")
        try files.createDirectory(at: elsewhere, withIntermediateDirectories: true)
        try files.createDirectory(at: support.appendingPathComponent("Col"), withIntermediateDirectories: true)
        try files.createSymbolicLink(at: support.appendingPathComponent("Islet"), withDestinationURL: elsewhere)

        ControlServer.answerAsIslet(in: support)

        #expect((try? files.attributesOfItem(atPath: support.appendingPathComponent("Col/islet.sock").path)) == nil)
        #expect((try? files.attributesOfItem(atPath: elsewhere.appendingPathComponent("islet.sock").path)) == nil)
    }

    @Test func nothingForSomeoneWhoNeverHadIslet() throws {
        let files = FileManager.default
        let support = try scratch()
        defer { try? files.removeItem(at: support) }
        try files.createDirectory(at: support.appendingPathComponent("Col"), withIntermediateDirectories: true)

        ControlServer.answerAsIslet(in: support)

        #expect((try? files.attributesOfItem(atPath: support.appendingPathComponent("Col/islet.sock").path)) == nil)
        #expect((try? files.attributesOfItem(atPath: support.appendingPathComponent("Islet").path)) == nil)
    }
}

import Foundation
@testable import ColShell
import Testing

/// A Homebrew prefix and an applications folder of its own, laid out as `brew install --cask` leaves them.
private struct FakeHomebrew {
    let root: URL
    var prefix: URL { root.appendingPathComponent("homebrew") }
    var applications: URL { root.appendingPathComponent("Applications") }

    init() throws {
        root = FileManager.default.temporaryDirectory.appendingPathComponent("col-brew-\(UUID().uuidString)").resolvingSymlinksInPath()
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
    }

    func app(_ name: String) throws -> URL {
        let app = applications.appendingPathComponent(name)
        try FileManager.default.createDirectory(at: app.appendingPathComponent("Contents/Helpers"), withIntermediateDirectories: true)
        return app
    }

    func room(_ token: String, version: String = "1.2.0") throws -> URL {
        let room = prefix.appendingPathComponent("Caskroom/\(token)")
        try FileManager.default.createDirectory(at: room.appendingPathComponent(version), withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: room.appendingPathComponent(".metadata"), withIntermediateDirectories: true)
        return room
    }

    func installed(_ app: URL) -> Bool { Homebrew.installed(app, prefixes: [prefix]) }

    func remove() { try? FileManager.default.removeItem(at: root) }
}

struct HomebrewTests {
    @Test func theLinkBesideTheVersionNamesTheApp() throws {
        let brew = try FakeHomebrew()
        defer { brew.remove() }
        let app = try brew.app("Islet.app")
        let room = try brew.room("islet")
        #expect(!brew.installed(app))

        try FileManager.default.createSymbolicLink(at: room.appendingPathComponent("1.2.0/Islet.app"), withDestinationURL: app)

        #expect(brew.installed(app))
        #expect(!brew.installed(try brew.app("Col.app")))
    }

    @Test func theReceiptAndTheApplicationsFolderNameTheApp() throws {
        let brew = try FakeHomebrew()
        defer { brew.remove() }
        let app = try brew.app("Islet.app")
        // Islet's record, moved to Col's token when the tap renamed the cask.
        let room = try brew.room("col")
        let receipt = #"{"uninstall_artifacts":[{"app":["Islet.app"]},{"binary":["/Applications/Islet.app/Contents/Helpers/islet"]}]}"#
        try receipt.write(to: room.appendingPathComponent(".metadata/INSTALL_RECEIPT.json"), atomically: true, encoding: .utf8)
        #expect(!brew.installed(app), "installed in /Applications, not in this folder")

        let config = #"{"default":{"appdir":"/Applications"},"explicit":{"appdir":"\#(brew.applications.path)"}}"#
        try config.write(to: room.appendingPathComponent(".metadata/config.json"), atomically: true, encoding: .utf8)

        #expect(brew.installed(app))
    }

    @Test func theCommandLinkedIntoTheApp() throws {
        let brew = try FakeHomebrew()
        defer { brew.remove() }
        let app = try brew.app("Islet.app")
        _ = try brew.room("islet")
        let bin = brew.prefix.appendingPathComponent("bin")
        try FileManager.default.createDirectory(at: bin, withIntermediateDirectories: true)
        // Dangling until Sparkle's update, or through the link to colctl that 2.0 ships: it names the app either way.
        try FileManager.default.createSymbolicLink(at: bin.appendingPathComponent("islet"),
                                                   withDestinationURL: app.appendingPathComponent("Contents/Helpers/islet"))

        #expect(brew.installed(app))
    }

    @Test func homebrewsCommandLinkFollowsTheApp() throws {
        let brew = try FakeHomebrew()
        defer { brew.remove() }
        let app = try brew.app("Islet.app")
        let helpers = app.appendingPathComponent("Contents/Helpers")
        FileManager.default.createFile(atPath: helpers.appendingPathComponent("colctl").path, contents: Data("#!/bin/sh\n".utf8),
                                       attributes: [.posixPermissions: 0o755])
        try FileManager.default.createSymbolicLink(atPath: helpers.appendingPathComponent("islet").path, withDestinationPath: "colctl")
        let bin = brew.prefix.appendingPathComponent("bin")
        try FileManager.default.createDirectory(at: bin, withIntermediateDirectories: true)
        try FileManager.default.createSymbolicLink(at: bin.appendingPathComponent("islet"), withDestinationURL: helpers.appendingPathComponent("islet"))
        #expect(Homebrew.command("islet", into: app, prefixes: [brew.prefix]) == nil, "no cask")

        _ = try brew.room("islet")

        #expect(Homebrew.command("islet", into: app, prefixes: [brew.prefix]) == bin.appendingPathComponent("islet"))
        // Islet's cask linked only `islet`: `colctl` goes through it until Col's cask links its own.
        #expect(Homebrew.command("colctl", into: app, prefixes: [brew.prefix]) == bin.appendingPathComponent("islet"))
        try FileManager.default.createSymbolicLink(at: bin.appendingPathComponent("colctl"), withDestinationURL: helpers.appendingPathComponent("colctl"))
        #expect(Homebrew.command("colctl", into: app, prefixes: [brew.prefix]) == bin.appendingPathComponent("colctl"))
        // Another copy of the app is not the one these links lead to.
        #expect(Homebrew.command("islet", into: try brew.app("Col.app"), prefixes: [brew.prefix]) == nil)
    }

    @Test func aCommandWithoutACaskIsNotHomebrews() throws {
        let brew = try FakeHomebrew()
        defer { brew.remove() }
        let app = try brew.app("Islet.app")
        let bin = brew.prefix.appendingPathComponent("bin")
        try FileManager.default.createDirectory(at: bin, withIntermediateDirectories: true)
        try FileManager.default.createSymbolicLink(at: bin.appendingPathComponent("islet"),
                                                   withDestinationURL: app.appendingPathComponent("Contents/Helpers/islet"))

        #expect(!brew.installed(app))
    }
}

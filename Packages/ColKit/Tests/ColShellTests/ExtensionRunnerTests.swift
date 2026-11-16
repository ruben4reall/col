import Foundation
import Testing
@testable import ColShell

@MainActor
@Suite struct ExtensionRunnerTests {
    @Test func anExtensionIsOffWhileItsFolderSaysSo() throws {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent("col-extensions-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: folder) }
        func add(_ name: String, off: Bool = false) throws {
            let extensionFolder = folder.appendingPathComponent(name)
            try FileManager.default.createDirectory(at: extensionFolder, withIntermediateDirectories: true)
            try Data(#"{"name":"\#(name)","command":"./run.sh","interval":60}"#.utf8).write(to: extensionFolder.appendingPathComponent("extension.json"))
            if off { try Data().write(to: extensionFolder.appendingPathComponent(ExtensionRunner.offMarker)) }
        }
        try add("installed-off", off: true)
        try add("on")
        try add("off-in-settings")
        // Still being copied by colctl: never read, never run.
        try add(".installing-1234")

        let found = ExtensionRunner.scan(folder, disabled: ["off-in-settings"])
        #expect(found.map(\.folder) == ["installed-off", "off-in-settings", "on"])
        #expect(found.map(\.enabled) == [false, false, true])
    }
}

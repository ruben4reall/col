import Foundation
import Testing
@testable import ColCore

struct ExtensionTests {
    @Test func validatesAManifest() throws {
        let manifest = try ExtensionManifest(name: " CI ", command: "./run.sh", interval: 2).validated()
        #expect(manifest.name == "CI")
        #expect(manifest.interval == 10)
        #expect(throws: ExtensionManifest.Invalid.missingCommand) { try ExtensionManifest(name: "x", command: " ", interval: 60).validated() }
    }

    @Test func turnsOutputIntoAnActivity() {
        let output = Data(#"{"title":"CI","symbol":"checkmark.seal.fill","tint":"green","text":"Passed"}"#.utf8)
        let request = ExtensionManifest.activity(fromOutput: output, folder: "github")
        #expect(request?.id == "ext-github")
        #expect(request?.text == "Passed")
    }

    @Test func emptyOrBrokenOutputClears() {
        #expect(ExtensionManifest.activity(fromOutput: Data("\n".utf8), folder: "x") == nil)
        #expect(ExtensionManifest.activity(fromOutput: Data("not json".utf8), folder: "x") == nil)
    }

    @Test func decodesTheFile() throws {
        let json = #"{"name":"Uptime","command":"uptime","interval":300}"#
        let manifest = try JSONDecoder().decode(ExtensionManifest.self, from: Data(json.utf8))
        #expect(manifest.interval == 300)
    }
}

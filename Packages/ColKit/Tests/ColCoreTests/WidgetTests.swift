import Foundation
import Testing
@testable import ColCore

@Suite struct WidgetTests {
    func decode(_ json: String) throws -> WidgetRequest {
        try JSONDecoder().decode(WidgetRequest.self, from: Data(json.utf8))
    }

    @Test func readsTheDocumentedFormat() throws {
        let widget = try decode("""
        {"id":"living-room","title":"Living room","value":21.5,"unit":"°C","symbol":"thermometer.medium","tint":"orange",
         "progress":0.4,"lines":["Humidity 48%","Window closed"],"staleAfter":900,"activity":true,
         "buttons":[{"title":"Heat","url":"http://homeassistant.local:8123/api/webhook/heat"}]}
        """).validated()
        #expect(widget.id == "living-room")
        #expect(widget.value == "21.5")
        #expect(widget.shownValue == "21.5°C")
        #expect(widget.lines == ["Humidity 48%", "Window closed"])
        #expect(widget.buttons?.first?.resolvedMethod == "POST")
        #expect(widget.staleAfter == 900)
        #expect(widget.activity == true)
    }

    @Test func numbersReadTheWayPeopleWriteThem() throws {
        #expect(try decode(#"{"id":"a","value":3}"#).value == "3")
        #expect(try decode(#"{"id":"a","value":1200.0}"#).value == "1200")
        #expect(try decode(#"{"id":"a","value":0.333333}"#).value == "0.33")
        #expect(try decode(#"{"id":"a","value":"OK"}"#).value == "OK")
        #expect(try decode(#"{"id":"a","value":true}"#).value == "true")
        #expect(try decode(#"{"id":"a","lines":["a",2,null]}"#).lines == ["a", "2"])
        #expect(try decode(#"{"id":"a","stale_after":60}"#).staleAfter == 60)
    }

    @Test func idsGoInAddresses() throws {
        #expect(throws: WidgetRequest.Invalid.missingID) { try WidgetRequest(id: "  ").validated() }
        #expect(throws: WidgetRequest.Invalid.badID) { try WidgetRequest(id: "a/b").validated() }
        #expect(throws: WidgetRequest.Invalid.badID) { try WidgetRequest(id: "temp ture").validated() }
        #expect(throws: WidgetRequest.Invalid.badID) { try WidgetRequest(id: String(repeating: "x", count: 65)).validated() }
        #expect(try WidgetRequest(id: " ci.main_2-a ").validated().id == "ci.main_2-a")
    }

    @Test func buttonsOnlyCallTheWeb() throws {
        for address in ["file:///etc/passwd", "javascript:alert(1)", "shortcuts://run-shortcut?name=x", "http://", "ftp://host/x", "/relative",
                        // A user part dresses an address up as another one: this one reaches evil.example.
                        "http://homeassistant.local%3A8123%2Fapi%2Fwebhook%2Flights@evil.example/x", "https://user:pass@host.example/x",
                        "https://@host.example/x"] {
            let widget = WidgetRequest(id: "a", buttons: [WidgetButton(title: "Go", url: address)])
            #expect(throws: WidgetRequest.Invalid.badButton(0)) { try widget.validated() }
        }
        let untitled = WidgetRequest(id: "a", buttons: [WidgetButton(title: "Go", url: "https://x.y"), WidgetButton(title: " ", url: "https://x.y")])
        #expect(throws: WidgetRequest.Invalid.badButton(1)) { try untitled.validated() }
        let put = WidgetRequest(id: "a", buttons: [WidgetButton(title: "Go", url: "https://x.y", method: "DELETE")])
        #expect(throws: WidgetRequest.Invalid.badButton(0)) { try put.validated() }
        let four = WidgetRequest(id: "a", buttons: Array(repeating: WidgetButton(title: "Go", url: "https://x.y"), count: 4))
        #expect(throws: WidgetRequest.Invalid.tooManyButtons) { try four.validated() }
        let get = try WidgetRequest(id: "a", buttons: [WidgetButton(title: "Go", url: "https://x.y/hook", method: "get")]).validated()
        #expect(get.buttons?.first?.method == "GET")
        #expect(get.buttons?.first?.confirmationKey(widget: "ci") == "ci\nGET https://x.y/hook")
        #expect(get.buttons?.first?.host == "x.y")
        #expect(WidgetButton(title: "Go", url: "http://homeassistant.local:8123/api").host == "homeassistant.local:8123")
    }

    @Test func keepsWhatTheIslandShows() throws {
        let widget = try WidgetRequest(
            id: "a", title: String(repeating: "t", count: 100), progress: 3, tint: "not a colour",
            lines: ["one", " ", "two", "three", "four"], staleAfter: 1
        ).validated()
        #expect(widget.title?.count == 60)
        #expect(widget.progress == 1)
        #expect(widget.tint == nil)
        #expect(widget.lines == ["one", "two", "three"])
        #expect(widget.staleAfter == 10)
        #expect(try WidgetRequest(id: "a", progress: .nan).validated().progress == nil)
    }

    @Test func goesStaleWhenTheSenderSaid() {
        let updated = Date(timeIntervalSince1970: 1000)
        let widget = WidgetRequest(id: "a", staleAfter: 60)
        #expect(!widget.isStale(updated: updated, now: updated.addingTimeInterval(59)))
        #expect(widget.isStale(updated: updated, now: updated.addingTimeInterval(61)))
        #expect(!WidgetRequest(id: "a").isStale(updated: updated, now: .distantFuture))
    }

    @Test func becomesAnActivityThatLeavesWhenStale() throws {
        let updated = Date(timeIntervalSince1970: 1000)
        let widget = try WidgetRequest(id: "ci", value: "3", unit: "runs", symbol: "hammer.fill", tint: "green", staleAfter: 120).validated()
        let activity = widget.activity(updated: updated)
        #expect(activity.id == "widget.ci")
        #expect(activity.compact.leading == .symbol("hammer.fill", tint: .green))
        #expect(activity.compact.trailing == .text("3 runs", tint: .green))
        #expect(activity.expires == updated.addingTimeInterval(120))
        #expect(ActivitySource(activityID: activity.id) == .scripts)
        let ring = WidgetRequest(id: "a", progress: 0.5).activity(updated: updated)
        #expect(ring.compact.trailing == .ring(progress: 0.5, tint: .white))
    }

    @Test func extensionsPrintWidgets() throws {
        let output = Data(#"{"widget":{"title":"Homebrew","value":3,"unit":"outdated","symbol":"mug.fill"}}"#.utf8)
        let widget = try #require(ExtensionManifest.widget(fromOutput: output, folder: "homebrew outdated"))
        #expect(widget.id == "ext-homebrew-outdated")
        #expect(widget.value == "3")
        // Only a widget: no activity, so the closed island stays as it was.
        #expect(ExtensionManifest.activity(fromOutput: output, folder: "homebrew") == nil)
        // Both, in one run.
        let both = Data(#"{"title":"CI","text":"Passed","widget":{"value":"Passed"}}"#.utf8)
        #expect(ExtensionManifest.activity(fromOutput: both, folder: "ci")?.text == "Passed")
        #expect(ExtensionManifest.widget(fromOutput: both, folder: "ci")?.value == "Passed")
        #expect(ExtensionManifest.widget(fromOutput: Data(#"{"title":"CI"}"#.utf8), folder: "ci") == nil)
    }
}

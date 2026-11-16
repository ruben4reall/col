import Foundation
import Testing
@testable import ColCore

@Suite struct APIWidgetTests {
    let weather = try! JSONDecoder().decode(JSONValue.self, from: Data("""
    {"data":{"temp":21.46,"humidity":48,"city":"Lausanne","ok":true},
     "items":[{"name":"first"},{"name":"second"}],"0":"zero","battery":76}
    """.utf8))

    @Test func keyPathsReachIntoObjectsAndArrays() {
        #expect(JSONKeyPath("data.temp")?.value(in: weather) == .number(21.46))
        #expect(JSONKeyPath("items.1.name")?.value(in: weather) == .string("second"))
        #expect(JSONKeyPath("items[0].name")?.value(in: weather) == .string("first"))
        #expect(JSONKeyPath("data[\"city\"]")?.value(in: weather) == .string("Lausanne"))
        #expect(JSONKeyPath("0")?.value(in: weather) == .string("zero"))
        #expect(JSONKeyPath("items.5.name")?.value(in: weather) == nil)
        #expect(JSONKeyPath("data.temp.more")?.value(in: weather) == nil)
        #expect(JSONKeyPath("") == nil)
        #expect(JSONKeyPath("items[0") == nil)
    }

    @Test func templatesFillFromTheDocument() {
        #expect(WidgetTemplate.render("{data.temp}°", in: weather) == .init(text: "21.46°", missing: []))
        #expect(WidgetTemplate.render("Humidity {data.humidity}% in {data.city}", in: weather).text == "Humidity 48% in Lausanne")
        #expect(WidgetTemplate.render("{{literal}}", in: weather).text == "{literal}")
        let missing = WidgetTemplate.render("{data.wind} km/h", in: weather)
        #expect(missing.text == "– km/h")
        #expect(missing.missing == ["data.wind"])
        // An object is not text: it counts as missing.
        #expect(WidgetTemplate.render("{data}", in: weather).missing == ["data"])
        #expect(WidgetTemplate.readsDocument("{data.temp}"))
        #expect(!WidgetTemplate.readsDocument("Plain {{text}}"))
    }

    @Test func mapsAnAnswerIntoAWidget() throws {
        let definition = APIWidget(
            id: "url-weather", name: "Weather", url: "https://api.example.com/now", minutes: 5,
            mapping: .init(title: "{data.city}", value: "{data.temp}", unit: "°C", progress: "{battery}",
                           symbol: "sun.max.fill", tint: "yellow", lines: ["Humidity {data.humidity}%", ""])
        )
        let (widget, missing) = try definition.widget(from: weather)
        #expect(missing.isEmpty)
        #expect(widget.id == "url-weather")
        #expect(widget.title == "Lausanne")
        #expect(widget.value == "21.46")
        #expect(widget.progress == 0.76)
        #expect(widget.lines == ["Humidity 48%"])
        #expect(widget.staleAfter == 630)
        var scaled = definition
        scaled.mapping.progress = "{data.humidity}"
        scaled.mapping.progressMaximum = 200
        #expect(try scaled.widget(from: weather).widget.progress == 0.24)
    }

    @Test func anAnswerInColsFormatNeedsNoMapping() throws {
        let definition = APIWidget(id: "url-ci", name: "CI", url: "https://ci.example.com/col.json")
        let answer = Data(#"{"id":"ignored","value":"Passed","symbol":"checkmark.seal.fill","tint":"green"}"#.utf8)
        let widget = try definition.widget(from: answer).widget
        #expect(widget.id == "url-ci")
        #expect(widget.title == "CI")
        #expect(widget.value == "Passed")
        #expect(throws: APIWidget.Invalid.notJSON) { try definition.widget(from: Data("<html>".utf8)) }
        #expect(throws: APIWidget.Invalid.notJSON) { try definition.widget(from: Data("[1,2]".utf8)) }
        let badButton = Data(#"{"buttons":[{"title":"x","url":"file:///etc"}]}"#.utf8)
        #expect(throws: APIWidget.Invalid.badWidget(.badButton(0))) { try definition.widget(from: badButton) }
    }

    @Test func readsAtLeastEveryMinute() {
        #expect(APIWidget(name: "x", url: "https://x.y", minutes: 0).interval == 60)
        #expect(APIWidget(name: "x", url: "https://x.y", minutes: 15).interval == 900)
        #expect(APIWidget(name: "x", url: "https://x.y").isValidURL)
        #expect(!APIWidget(name: "x", url: "file:///etc/hosts").isValidURL)
        #expect(APIWidget.isValidHeaderName("X-Api-Key"))
        #expect(!APIWidget.isValidHeaderName("Bad Header"))
        #expect(!APIWidget.isValidHeaderName("X:Y"))
        #expect(WidgetRequest.isValidID(APIWidget(name: "x", url: "https://x.y").id))
    }
}

import ColCore
import SwiftUI

/// The weather and the small tools of the island's pages: Pomodoro, the shelf's tools, the clipboard's search and the
/// graphics processor on the System page.
struct GlancePane: View {
    @State private var weather = Preferences.showsWeather
    @State private var place = Preferences.weatherPlace
    @State private var followsLocation = Preferences.weatherPlace == nil
    @State private var search = ""
    @State private var results: [WeatherPlace] = []
    @State private var searching = false
    @State private var searched = false
    @State private var pomodoro = Preferences.showsPomodoro
    @State private var focusMinutes = Preferences.pomodoroPlan.focusMinutes
    @State private var breakMinutes = Preferences.pomodoroPlan.breakMinutes
    @State private var shelfTools = Preferences.shelfTools
    @State private var clipboardSearch = Preferences.searchesClipboard
    @State private var gpu = Preferences.showsGPU

    var body: some View {
        PaneScaffold(pane: .glance) {
            Section {
                IconToggle(symbol: "cloud.sun.fill", tint: .cyan, title: "Weather",
                           detail: "Now, today’s high and low and the hours ahead, in the Weather widget and on the Lock Screen. Add the widget to a page in Pages.", isOn: $weather)
                    .onChange(of: weather) {
                        Preferences.showsWeather = weather
                        if weather, followsLocation { LocationAccess.shared.request() }
                    }
                if weather {
                    Picker(selection: $followsLocation) {
                        Text("Where I am", bundle: .module).tag(true)
                        Text("A city", bundle: .module).tag(false)
                    } label: {
                        Text("Weather for", bundle: .module)
                    }
                    .pickerStyle(.segmented)
                    .onChange(of: followsLocation) {
                        if followsLocation {
                            place = nil
                            Preferences.weatherPlace = nil
                            LocationAccess.shared.request()
                        }
                    }
                    if followsLocation {
                        LocationRow()
                    } else {
                        citySearch
                    }
                }
            } header: {
                Text("Weather", bundle: .module)
            } footer: {
                Text("From Open-Meteo, a free weather service. Col sends it only a position rounded to about a kilometre, or the name of the city you search, at most every 30 minutes and only while the weather shows. Temperatures follow the unit of your Mac.", bundle: .module)
            }
            Section {
                IconToggle(symbol: "brain.head.profile.fill", tint: .red, title: "Pomodoro",
                           detail: "Focus, then a break, counted in the wings like the timer, with a gentle sound at the end. In the Tools page and as a widget.", isOn: $pomodoro)
                    .onChange(of: pomodoro) { Preferences.showsPomodoro = pomodoro }
                if pomodoro {
                    Stepper(value: $focusMinutes, in: PomodoroPlan.focusRange, step: 5) {
                        Text("Focus: \(focusMinutes) min", bundle: .module)
                    }
                    .onChange(of: focusMinutes) { savePlan() }
                    Stepper(value: $breakMinutes, in: PomodoroPlan.breakRange) {
                        Text("Break: \(breakMinutes) min", bundle: .module)
                    }
                    .onChange(of: breakMinutes) { savePlan() }
                }
            } header: {
                Text("Pomodoro", bundle: .module)
            }
            Section {
                IconToggle(symbol: "wand.and.stars", tint: .blue, title: "Tools for files on the shelf",
                           detail: "From a file’s menu: convert an image to PNG, JPEG or HEIC, resize it, compress files into a .zip, copy the text of an image. Everything runs on your Mac; what they make lands beside the original and on the shelf.", isOn: $shelfTools)
                    .onChange(of: shelfTools) { Preferences.shelfTools = shelfTools }
                IconToggle(symbol: "magnifyingglass", tint: .orange, title: "Search your copies",
                           detail: "A search field above the recent copies. The island takes the keyboard only while you type.", isOn: $clipboardSearch)
                    .onChange(of: clipboardSearch) { Preferences.searchesClipboard = clipboardSearch }
                IconToggle(symbol: "cpu", tint: .green, title: "Graphics processor on the System page",
                           detail: "Its load beside the processor’s, measured only while you look.", isOn: $gpu)
                    .onChange(of: gpu) { Preferences.showsGPU = gpu }
            } header: {
                Text("Shelf, clipboard and System", bundle: .module)
            }
        }
    }

    /// Search a city by name, then pick it among the places found.
    @ViewBuilder private var citySearch: some View {
        if let place {
            LabeledContent {
                Button { self.place = nil; Preferences.weatherPlace = nil } label: { Text("Change…", bundle: .module) }
            } label: {
                Label {
                    VStack(alignment: .leading, spacing: 1) {
                        Text(verbatim: place.name)
                        if let detail = place.detail { Text(verbatim: detail).font(.callout).foregroundStyle(.secondary) }
                    }
                } icon: { Image(systemName: "mappin.and.ellipse") }
            }
        } else {
            HStack {
                TextField(text: $search, prompt: Text("Lausanne, Tokyo…", bundle: .module)) { Text("City", bundle: .module) }
                    .onSubmit(find)
                Button(action: find) { Text("Search", bundle: .module) }
                    .disabled(search.trimmingCharacters(in: .whitespaces).count < 2 || searching)
                if searching { ProgressView().controlSize(.small) }
            }
            ForEach(results, id: \.self) { result in
                Button {
                    place = result
                    Preferences.weatherPlace = result
                    results = []
                    search = ""
                } label: {
                    HStack {
                        Text(verbatim: result.name)
                        if let detail = result.detail { Text(verbatim: detail).foregroundStyle(.secondary) }
                        Spacer()
                    }
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }
            if searched, results.isEmpty, !searching {
                Text("No city by that name.", bundle: .module).foregroundStyle(.secondary)
            }
        }
    }

    private func find() {
        let name = search
        searching = true
        Task { @MainActor in
            results = await WeatherModel.search(name)
            searching = false
            searched = true
        }
    }

    private func savePlan() {
        Preferences.pomodoroPlan = PomodoroPlan(focusMinutes: focusMinutes, breakMinutes: breakMinutes)
    }
}

/// Whether Col may know where the Mac is, and the way to allow it.
private struct LocationRow: View {
    @State private var location = LocationAccess.shared

    var body: some View {
        IconRow(symbol: "location.fill", tint: .blue, title: Text("Location", bundle: .module), detail: detail) {
            if location.canAsk {
                Button { location.request() } label: { Text("Allow…", bundle: .module) }
            } else if !location.isAllowed {
                Button { PermissionCenter.shared.openSettings(for: .location) } label: { Text("Open Settings…", bundle: .module) }
            } else {
                PermissionBadge(granted: true) {}
            }
        }
    }

    private var detail: Text {
        if location.isAllowed { return Text("To about a kilometre, read only when the weather is due.", bundle: .module) }
        if location.canAsk { return Text("macOS asks you once.", bundle: .module) }
        return Text("Location Services is off for Col. Allow it in System Settings, or choose a city.", bundle: .module)
    }
}

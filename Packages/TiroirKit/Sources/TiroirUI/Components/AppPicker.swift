import AppKit
import SwiftUI
import UniformTypeIdentifiers

/// Chooses an app by its bundle identifier: one that is open now, or any other from the Applications folder.
struct AppPicker: View {
    @Binding var bundleID: String?

    var body: some View {
        Menu {
            Section(Strings.openNow) {
                ForEach(AppLookup.openApps()) { app in
                    Button {
                        bundleID = app.id
                    } label: {
                        Label { Text(verbatim: app.name) } icon: { Image(nsImage: app.icon) }
                    }
                }
            }
            Divider()
            Button(Strings.otherApp) { chooseInApplications() }
        } label: {
            if let bundleID {
                Label { Text(verbatim: AppLookup.name(of: bundleID)) } icon: { Image(nsImage: AppLookup.icon(of: bundleID)) }
            } else {
                Text(verbatim: Strings.chooseOne)
            }
        }
        .fixedSize()
    }

    private func chooseInApplications() {
        let panel = NSOpenPanel()
        panel.directoryURL = URL(fileURLWithPath: "/Applications")
        panel.allowedContentTypes = [.application]
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = false
        panel.prompt = Strings.choose
        panel.message = Strings.chooseAppMessage
        guard panel.runModal() == .OK, let url = panel.url, let id = Bundle(url: url)?.bundleIdentifier else { return }
        bundleID = id
    }
}

/// Names and icons of apps by bundle identifier, for triggers' sentences and the app picker.
@MainActor
enum AppLookup {
    struct App: Identifiable {
        var id: String
        var name: String
        var icon: NSImage
    }

    private static var names: [String: String] = [:]

    /// The apps open now with a window or a Dock icon, by name; Tiroir left out.
    static func openApps() -> [App] {
        var seen = Set<String>()
        return NSWorkspace.shared.runningApplications
            .filter { $0.activationPolicy == .regular }
            .compactMap { app -> App? in
                guard let id = app.bundleIdentifier, id != Bundle.main.bundleIdentifier, seen.insert(id).inserted else { return nil }
                return App(id: id, name: app.localizedName ?? name(of: id), icon: small(app.icon))
            }
            .sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
    }

    /// The app's name as the Finder shows it; for an app that is not installed, the end of its identifier.
    static func name(of bundleID: String) -> String {
        if let known = names[bundleID] { return known }
        let name: String
        if let running = NSRunningApplication.runningApplications(withBundleIdentifier: bundleID).first?.localizedName {
            name = running
        } else if let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleID) {
            let bundle = Bundle(url: url)
            name = (bundle?.object(forInfoDictionaryKey: "CFBundleDisplayName") as? String)
                ?? (bundle?.object(forInfoDictionaryKey: "CFBundleName") as? String)
                ?? url.deletingPathExtension().lastPathComponent
        } else {
            return bundleID.split(separator: ".").last.map(String.init) ?? bundleID
        }
        names[bundleID] = name
        return name
    }

    static func icon(of bundleID: String) -> NSImage {
        let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleID)
        return small(url.map { NSWorkspace.shared.icon(forFile: $0.path) })
    }

    /// Menus draw an image at its own size: 16 points, like the Finder's.
    private static func small(_ image: NSImage?) -> NSImage {
        let copy = (image?.copy() as? NSImage) ?? NSImage(systemSymbolName: "app.dashed", accessibilityDescription: nil) ?? NSImage()
        copy.size = NSSize(width: 16, height: 16)
        return copy
    }
}

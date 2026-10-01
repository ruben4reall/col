import AppKit
import IsletCore
import SwiftUI

/// What the welcome finds on the Mac when it opens: the apps, devices and agents Islet's features would use. Each
/// feature starts on when the Mac has what it needs, so the island is set up for this user, not for everyone.
@MainActor
struct Discovery {
    /// Music players installed, Apple's Music always among them, and their names as the Finder shows them.
    var musicApps: [AppIcon] = []
    var musicNames: [String] = []
    var aiApps: [AIApp] = []
    /// Coding agents installed, whose hooks Islet can connect to.
    var agents: [CodingAgent] = []
    var hasBattery = false
    /// Souffleur was used here: its scripts are already in the prompter.
    var usedSouffleur = false

    /// Music players Islet recognizes by their identifiers, the way it recognizes AI apps.
    static let players: [AppIcon] = [
        AppIcon(bundleIdentifiers: ["com.spotify.client"], name: "Spotify", symbol: "music.note", tint: RGBA(red: 0.12, green: 0.84, blue: 0.38)),
        AppIcon(bundleIdentifiers: ["com.apple.Music"], name: "Music", symbol: "music.note", tint: RGBA(red: 0.98, green: 0.24, blue: 0.33)),
        AppIcon(bundleIdentifiers: ["com.deezer.deezer-desktop"], name: "Deezer", symbol: "music.note", tint: RGBA(red: 0.63, green: 0.22, blue: 1)),
        AppIcon(bundleIdentifiers: ["com.tidal.desktop"], name: "TIDAL", symbol: "music.note", tint: .white),
        AppIcon(bundleIdentifiers: ["com.amazon.music"], name: "Amazon Music", symbol: "music.note", tint: RGBA(red: 0.14, green: 0.85, blue: 0.86)),
        AppIcon(bundleIdentifiers: ["com.qobuz.QobuzDesktop"], name: "Qobuz", symbol: "music.note", tint: .white),
        AppIcon(bundleIdentifiers: ["tv.plex.plexamp"], name: "Plexamp", symbol: "music.note", tint: RGBA(red: 0.9, green: 0.63, blue: 0.05)),
        AppIcon(bundleIdentifiers: ["com.apple.podcasts"], name: "Podcasts", symbol: "mic", tint: RGBA(red: 0.6, green: 0.3, blue: 0.95)),
    ]

    static func look(ai: AIAppsModel?, power: PowerMonitor?) -> Discovery {
        var found = Discovery()
        for player in players {
            guard let url = AppIcons.url(for: player) else { continue }
            found.musicApps.append(player)
            found.musicNames.append(FileManager.default.displayName(atPath: url.path))
        }
        ai?.refreshInstalled()
        found.aiApps = ai?.installed ?? []
        found.agents = CodingAgent.allCases.filter { CommandLineInstaller.isInstalled($0) }
        found.hasBattery = power?.state != nil
        let support = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        found.usedSouffleur = FileManager.default.fileExists(atPath: support.appendingPathComponent("Souffleur").path)
        return found
    }

    /// The features to start with on this Mac.
    var suggested: Set<WelcomeModel.Feature> {
        var features: Set<WelcomeModel.Feature> = [.music, .lyrics, .headphones, .hud, .privacy, .shelf, .tools]
        if hasBattery { features.insert(.battery) }
        if !aiApps.isEmpty { features.insert(.ai) }
        if !agents.isEmpty { features.insert(.agents) }
        if usedSouffleur { features.insert(.prompter) }
        return features
    }
}

// MARK: The step

/// The first step: what Islet found on this Mac, with the real thing wherever there is one (the song playing, the
/// headphones connected, the battery, the AI apps and agents with their logos, the next event once allowed), and what
/// else it can do. Permissions are asked here, on the line that needs them, and the line shows the result at once.
struct DiscoverStep: View {
    let model: WelcomeModel
    @State private var shown = 0

    private var found: [WelcomeModel.Feature] {
        var features: [WelcomeModel.Feature] = [.music, .lyrics, .headphones]
        if !model.found.aiApps.isEmpty { features.append(.ai) }
        if !model.found.agents.isEmpty { features.append(.agents) }
        features.append(.agenda)
        if model.found.usedSouffleur { features.append(.prompter) }
        if model.found.hasBattery { features.append(.battery) }
        return features
    }

    private var others: [WelcomeModel.Feature] {
        WelcomeModel.Feature.allCases.filter { !found.contains($0) && ($0 != .agents || !model.found.agents.isEmpty) }
    }

    var body: some View {
        VStack(spacing: 16) {
            StepHeader(title: "Islet adapts to your Mac", subtitle: "Here is what it found. Keep what helps you; all of it can change later in Settings.")
            ScrollView {
                VStack(alignment: .leading, spacing: 8) {
                    SectionTitle(text: Text("On this Mac", bundle: .module))
                    LanguageRow()
                        .opacity(shown > 0 ? 1 : 0)
                        .offset(y: shown > 0 ? 0 : 10)
                    ForEach(Array(found.enumerated()), id: \.element) { index, feature in
                        FeatureRow(feature: feature, model: model)
                            .opacity(shown > index + 1 ? 1 : 0)
                            .offset(y: shown > index + 1 ? 0 : 10)
                    }
                    SectionTitle(text: Text("Also in Islet", bundle: .module)).padding(.top, 10)
                    ForEach(others) { feature in
                        FeatureRow(feature: feature, model: model)
                            .opacity(shown > found.count + 1 ? 1 : 0)
                    }
                }
                .padding(.horizontal, 36)
                .padding(.bottom, 12)
            }
            .scrollIndicators(.never)
            .mask(LinearGradient(stops: [.init(color: .black, location: 0.9), .init(color: .clear, location: 1)], startPoint: .top, endPoint: .bottom))
        }
        .padding(.top, 34)
        .task {
            // One line after another, as Islet looks around the Mac.
            for index in 0...(found.count + 1) {
                try? await Task.sleep(for: .milliseconds(index == 0 ? 250 : 110))
                withAnimation(.spring(duration: 0.45, bounce: 0.2)) { shown = index + 1 }
            }
        }
    }
}

/// The language Islet speaks: the Mac's, found like the rest; another is a menu away, and Islet starts again in it.
private struct LanguageRow: View {
    var body: some View {
        let current = AppLanguage.current
        HStack(spacing: 12) {
            Tile(symbol: "globe", tint: .blue).frame(width: 40, height: 40)
            VStack(alignment: .leading, spacing: 2) {
                Text("Language", bundle: .module).font(.system(size: 13.5, weight: .semibold))
                Group {
                    if AppLanguage.chosen == nil {
                        Text("\(AppLanguage.name(for: current)), like your Mac.", bundle: .module)
                    } else {
                        Text("\(AppLanguage.name(for: current)), chosen in Islet.", bundle: .module)
                    }
                }
                .font(.system(size: 12))
                .foregroundStyle(.white.opacity(0.55))
            }
            Spacer(minLength: 8)
            Menu {
                ForEach(AppLanguage.available, id: \.self) { language in
                    Button {
                        guard language != current else { return }
                        AppLanguage.choose(language == AppLanguage.system ? nil : language)
                        AppLanguage.relaunch()
                    } label: {
                        if language == current {
                            Label(AppLanguage.name(for: language), systemImage: "checkmark")
                        } else {
                            Text(verbatim: AppLanguage.name(for: language))
                        }
                    }
                }
            } label: {
                Text("Change", bundle: .module)
                    .font(.system(size: 11.5, weight: .semibold))
                    .foregroundStyle(.white.opacity(0.9))
                    .padding(.horizontal, 10)
                    .frame(height: 24)
                    .background(Capsule().fill(Color.white.opacity(0.12)))
            }
            .menuStyle(.button)
            .buttonStyle(.plain)
            .menuIndicator(.hidden)
            .fixedSize()
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .background(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(Color.white.opacity(0.05))
                .strokeBorder(Color.white.opacity(0.06), lineWidth: 1)
        )
    }
}

private struct SectionTitle: View {
    let text: Text

    var body: some View {
        text
            .font(.system(size: 11, weight: .semibold))
            .textCase(.uppercase)
            .kerning(0.6)
            .foregroundStyle(.white.opacity(0.4))
            .padding(.leading, 4)
    }
}

/// One feature: its picture (the real one when there is one), what it does here, a switch, and the permission or the
/// connection it needs, asked right there.
private struct FeatureRow: View {
    let feature: WelcomeModel.Feature
    let model: WelcomeModel
    @State private var hovering = false

    private var services: IslandServices? { IslandController.shared?.models }
    private var permissions: PermissionCenter { PermissionCenter.shared }

    var body: some View {
        HStack(spacing: 12) {
            picture.frame(width: 40, height: 40)
            VStack(alignment: .leading, spacing: 2) {
                feature.title.font(.system(size: 13.5, weight: .semibold))
                detail
                    .font(.system(size: 12))
                    .foregroundStyle(.white.opacity(0.55))
                    .lineLimit(2)
                    .fixedSize(horizontal: false, vertical: true)
                accessory
            }
            Spacer(minLength: 8)
            Toggle(isOn: Binding(get: { model.features.contains(feature) }, set: { model.set(feature, on: $0) })) { feature.title }
                .labelsHidden()
                .toggleStyle(.switch)
                .controlSize(.small)
                .tint(Theme.coral.color)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .background(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(Color.white.opacity(hovering ? 0.075 : 0.05))
                .strokeBorder(Color.white.opacity(0.06), lineWidth: 1)
        )
        .onHover { hovering = $0 }
        .animation(.easeOut(duration: 0.15), value: hovering)
    }

    // MARK: Picture

    @ViewBuilder private var picture: some View {
        switch feature {
        case .music:
            if let media = services?.media, media.nowPlaying.isPlaying, let artwork = media.artwork {
                Image(nsImage: artwork).resizable().aspectRatio(contentMode: .fill)
                    .frame(width: 40, height: 40)
                    .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
            } else {
                Stacked(icons: Array(model.found.musicApps.prefix(4)))
            }
        case .ai:
            Stacked(icons: model.found.aiApps.prefix(4).map(\.icon))
        case .agents:
            Stacked(icons: model.found.agents.prefix(4).map(\.icon))
        case .agenda:
            AppIconView(icon: AppIcon(bundleIdentifiers: ["com.apple.iCal"], name: "Calendar", symbol: "calendar", tint: .red), size: 40)
        case .headphones:
            Tile(symbol: headphonesSymbol, tint: .blue)
        default:
            Tile(symbol: feature.symbol, tint: feature.tint)
        }
    }

    private var headphonesSymbol: String {
        guard let output = services?.audio.output, output.transport == .bluetooth else { return "airpodspro" }
        return SystemGlyphs.audioDevice(name: output.name, transport: output.transport)
    }

    // MARK: What it does here

    @ViewBuilder private var detail: some View {
        switch feature {
        case .music:
            if let media = services?.media, media.nowPlaying.isPlaying, !media.nowPlaying.title.isEmpty {
                Text("“\(media.nowPlaying.title)” by \(media.nowPlaying.artist) is playing: the island shows it with its cover, and its controls.", bundle: .module)
            } else {
                Text("\(ListFormatter.localizedString(byJoining: model.found.musicNames)) on this Mac: whatever plays shows in the island.", bundle: .module)
            }
        case .lyrics:
            Text("The words of the song beside the player, line by line. Titles go to LRCLIB, an open database.", bundle: .module)
        case .headphones:
            if let output = services?.audio.output, output.transport == .bluetooth {
                Text("\(output.name) connected: the island shows them, with their battery, as they connect.", bundle: .module)
            } else {
                Text("Your AirPods and headphones, with their battery, as they connect.", bundle: .module)
            }
        case .ai:
            Text("\(ListFormatter.localizedString(byJoining: model.found.aiApps.map(\.name))), a tap away; your own AI servers too, and a question to them from the island.", bundle: .module)
        case .agents:
            Text("\(ListFormatter.localizedString(byJoining: model.found.agents.map(\.name))): their sessions in the notch, and their permission requests answered from it.", bundle: .module)
        case .agenda:
            if permissions.isGranted(.calendars) {
                if let event = services?.calendar.events.first {
                    Text("Next: \(event.title), \(event.start.formatted(date: .omitted, time: .shortened)).", bundle: .module)
                } else {
                    Text("Your next events beside the clock, and a button to join a call.", bundle: .module)
                }
            } else {
                Text("Your next events beside the clock, and a button to join a call. Islet needs your calendars for that.", bundle: .module)
            }
        case .prompter:
            if model.found.usedSouffleur {
                Text("Your Souffleur scripts are here: the text comes out of the notch, right under the camera, at the pace of your voice.", bundle: .module)
            } else {
                Text("For videos and calls: your text comes out of the notch, right under the camera, at the pace of your voice.", bundle: .module)
            }
        case .hud:
            Text("Volume and brightness in the notch, instead of the big square in the middle of the screen.", bundle: .module)
        case .battery:
            if let state = services?.power.state {
                let level = state.level.formatted(.percent.precision(.fractionLength(0)))
                if state.isCharging {
                    Text("\(level), charging: plugging in and a low battery show in the notch.", bundle: .module)
                } else {
                    Text("\(level): plugging in and a low battery show in the notch.", bundle: .module)
                }
            } else {
                Text("Plugging in and a low battery show in the notch.", bundle: .module)
            }
        case .privacy:
            Text("A dot beside the camera while an app uses the microphone or the camera.", bundle: .module)
        case .shelf:
            Text("Drop files on the notch to keep them at hand, and AirDrop them from there.", bundle: .module)
        case .clipboard:
            Text("What you copied, kept in memory only, never on disk.", bundle: .module)
        case .tools:
            Text("A timer in the wings, a colour picker, a mirror and a way to keep the Mac awake.", bundle: .module)
        case .system:
            Text("Processor, memory, network and disk, measured only while you look.", bundle: .module)
        }
    }

    // MARK: What it needs

    @ViewBuilder private var accessory: some View {
        switch feature {
        case .agenda where !permissions.isGranted(.calendars) && model.features.contains(.agenda):
            Ask(title: Text("Allow Calendars", bundle: .module)) {
                permissions.request(.calendars)
            }
        case .hud where !permissions.isGranted(.accessibility) && model.features.contains(.hud):
            Ask(title: Text("Allow in System Settings", bundle: .module)) {
                permissions.request(.accessibility)
            }
        case .agents where model.features.contains(.agents):
            HStack(spacing: 6) {
                ForEach(model.found.agents, id: \.self) { agent in
                    ConnectButton(agent: agent)
                }
            }
            .padding(.top, 4)
        default:
            EmptyView()
        }
    }
}

/// A permission asked on its own line: the line shows what it brings as soon as it is given.
private struct Ask: View {
    let title: Text
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            title
                .font(.system(size: 11.5, weight: .semibold))
                .foregroundStyle(.white)
                .padding(.horizontal, 10)
                .frame(height: 22)
                .background(Capsule().fill(Theme.coral.color.opacity(0.85)))
        }
        .buttonStyle(.plain)
        .padding(.top, 4)
    }
}

/// Connects one agent's hooks, with its logo; a tick once it reports to Islet.
private struct ConnectButton: View {
    let agent: CodingAgent
    @State private var connected = false

    var body: some View {
        Button {
            if !connected { _ = CommandLineInstaller.connect(agent) }
            withAnimation(.spring(duration: 0.35, bounce: 0.3)) { connected = CommandLineInstaller.isConnected(agent) }
        } label: {
            HStack(spacing: 5) {
                AppIconView(icon: agent.icon, size: 16)
                Text(verbatim: agent.name)
                Image(systemName: connected ? "checkmark" : "plus")
                    .font(.system(size: 9, weight: .bold))
                    .foregroundStyle(connected ? .green : .white.opacity(0.7))
            }
            .font(.system(size: 11.5, weight: .semibold))
            .foregroundStyle(.white.opacity(0.9))
            .padding(.leading, 4)
            .padding(.trailing, 9)
            .frame(height: 22)
            .background(Capsule().fill(.white.opacity(connected ? 0.08 : 0.12)))
        }
        .buttonStyle(.plain)
        .help(connected ? Text("Connected", bundle: .module) : Text("Connect", bundle: .module))
        .onAppear { connected = CommandLineInstaller.isConnected(agent) }
    }
}

/// Several apps in one picture, as a folder shows them: up to four small icons on a tile; one app alone, its icon.
private struct Stacked: View {
    let icons: [AppIcon]

    var body: some View {
        if icons.count == 1 {
            AppIconView(icon: icons[0], size: 40)
        } else {
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(Color.white.opacity(0.1))
                .frame(width: 38, height: 38)
                .overlay {
                    Grid(horizontalSpacing: 1, verticalSpacing: 1) {
                        GridRow {
                            slot(0)
                            slot(1)
                        }
                        GridRow {
                            slot(2)
                            slot(3)
                        }
                    }
                }
        }
    }

    @ViewBuilder private func slot(_ index: Int) -> some View {
        if index < icons.count {
            AppIconView(icon: icons[index], size: 17)
        } else {
            Color.clear.frame(width: 17, height: 17)
        }
    }
}

/// A symbol on a tile in its colour, as the settings draw them.
private struct Tile: View {
    let symbol: String
    let tint: Color

    var body: some View {
        RoundedRectangle(cornerRadius: 10, style: .continuous)
            .fill(tint.gradient)
            .frame(width: 36, height: 36)
            .overlay {
                Image(systemName: symbol)
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(.white)
            }
    }
}

// MARK: Your island

/// The island this user will have, shown on their own wallpaper with what is really happening on the Mac: their song,
/// their files, their AI apps. A chip per page, and an example of an agent asking for permission, played on this island
/// only.
struct IslandStep: View {
    let model: WelcomeModel
    @State private var page = PageDeck.homeID

    var body: some View {
        let deck = model.deck
        let size = Preferences.islandSize
        VStack(spacing: 14) {
            StepHeader(title: "Your island", subtitle: "Your pages, with what is really happening on your Mac. Pick one to see it; hover the island to try it.")
            IslandStage(size: size, glass: IslandView.glassAvailable ? Preferences.islandGlass : .off, deck: deck, page: page,
                        agents: model.features.contains(.agents) ? model.exampleAgents : nil)
                .frame(height: IslandStage.height(for: size))
                .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
                .overlay(RoundedRectangle(cornerRadius: 16, style: .continuous).strokeBorder(Color.white.opacity(0.08)))
                .padding(.horizontal, 28)
            HStack(spacing: 6) {
                ForEach(deck.pages, id: \.id) { layout in
                    PageChip(symbol: layout.tabSymbol, title: Text(verbatim: layout.title), on: page == layout.id) { page = layout.id }
                }
                if model.features.contains(.agents) {
                    PageChip(symbol: "hand.raised.fill", title: Text("An agent asks", bundle: .module), on: page == "live") { page = "live" }
                }
            }
            caption
                .font(.system(size: 12))
                .foregroundStyle(.white.opacity(0.55))
                .multilineTextAlignment(.center)
                .frame(maxWidth: 460)
                .id(page)
                .transition(.opacity)
        }
        .padding(.top, 30)
        .animation(.easeOut(duration: 0.2), value: page)
    }

    @ViewBuilder private var caption: some View {
        if page == "live" {
            let agent = model.found.agents.first ?? .claude
            Text("An example: when \(agent.name) asks to run a command, the island opens with Allow and Deny.", bundle: .module)
        } else if page == PageDeck.homeID {
            Text("What plays, the time, the song’s words and your next event, each when there is something to show.", bundle: .module)
        } else if let kind = model.deck.page(page)?.widgets.first {
            Text(kind.summary)
        }
    }
}

private struct PageChip: View {
    let symbol: String
    let title: Text
    let on: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 5) {
                Image(systemName: symbol).font(.system(size: 10.5, weight: .bold))
                title.lineLimit(1)
            }
            .font(.system(size: 11.5, weight: .semibold))
            .foregroundStyle(on ? .black : .white.opacity(0.85))
            .padding(.horizontal, 10)
            .frame(height: 26)
            .background(Capsule().fill(on ? Color.white : Color.white.opacity(0.1)))
        }
        .buttonStyle(.plain)
    }
}

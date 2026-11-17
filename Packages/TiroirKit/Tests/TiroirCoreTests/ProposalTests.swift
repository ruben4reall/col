import Foundation
import Testing
@testable import TiroirCore

@Suite struct ProposalTests {
    let classifier = Classifier()

    func inputs(_ bar: MenuBarSnapshot, developers: [String: String] = [:]) -> [ProposalInput] {
        bar.icons.map { icon in
            let category = icon.kind == .system ? CategoryID.system : classifier.classify(bundleID: icon.id.bundleID, name: icon.ownerName)
            return ProposalInput(icon: icon, category: category, developer: developers[icon.id.bundleID] ?? icon.ownerName)
        }
    }

    func propose(_ inputs: [ProposalInput], _ strategy: SortStrategy = .purpose, pinned: Set<IconID> = [], maximumDrawers: Int = 6, previous: Layout? = nil) -> Layout {
        let ids = SequentialIDs()
        return SmartSort.propose(inputs, strategy: strategy, pinned: pinned, maximumDrawers: maximumDrawers,
                                 names: englishName, everythingName: "All Icons", previous: previous, makeID: ids.make)
    }

    func drawerNames(_ layout: Layout) -> [String] { layout.drawers.map(\.name) }

    func members(_ layout: Layout, _ name: String) -> Set<String> {
        guard let drawer = layout.drawers.first(where: { $0.name == name }) else { return [] }
        return Set(layout.placements.filter { $0.value == .drawer(drawer.id) }.map(\.key.description))
    }

    /// Ruben's menu bar: Drive and Proton make a drawer, Claude and Pli have no partner and gather in Other, the
    /// essentials stay, Spotlight and the input menu make a System drawer.
    @Test func rubensMenuBar() {
        let layout = propose(inputs(sampleBar()))
        #expect(drawerNames(layout) == ["Files & Cloud", "System", "Other"])
        #expect(members(layout, "Files & Cloud") == ["com.google.drivefs", "com.protonmail.bridge"])
        #expect(members(layout, "System") == ["com.apple.Spotlight", "com.apple.TextInputMenuAgent"])
        #expect(members(layout, "Other") == ["com.anthropic.claudefordesktop", "ch.rubencatalao.pli"])
        for key in ["com.apple.menuextra.clock", "com.apple.menuextra.controlcenter", "com.apple.menuextra.wifi",
                    "com.apple.menuextra.battery", "com.apple.menuextra.sound"] {
            #expect(layout.placements[IconID(bundleID: "com.apple.controlcenter", key: key)] == .menuBar)
        }
        #expect(layout.drawers.first?.mark == .symbol("cloud.fill"), "icons by default, like macOS's own menu bar icons")
        #expect(layout.drawers.first?.category == .files)
    }

    @Test func aSingleIconOfItsKindDoesNotGetADrawer() {
        let bar = MenuBarSnapshot(icons: [
            icon("com.google.drivefs", x: 100, name: "Google Drive"),
            icon("com.hnc.Discord", x: 140, name: "Discord"),
        ])
        let layout = propose(inputs(bar))
        #expect(drawerNames(layout) == ["Other"])
    }

    @Test func aLoneIconStaysInTheMenuBar() {
        let bar = MenuBarSnapshot(icons: [icon("com.google.drivefs", x: 100, name: "Google Drive")])
        let layout = propose(inputs(bar))
        #expect(layout.drawers.isEmpty)
        #expect(layout.placements[IconID(bundleID: "com.google.drivefs")] == .menuBar)
    }

    @Test func aLoneSystemIconStaysInTheMenuBar() {
        let bar = MenuBarSnapshot(icons: [
            icon("com.apple.Spotlight", x: 100, name: "Spotlight", kind: .system),
            icon("com.google.drivefs", x: 140, name: "Google Drive"),
            icon("com.getdropbox.dropbox", x: 180, name: "Dropbox"),
        ])
        let layout = propose(inputs(bar))
        #expect(drawerNames(layout) == ["Files & Cloud"])
        #expect(layout.placements[IconID(bundleID: "com.apple.Spotlight")] == .menuBar)
    }

    @Test func pinnedIconsStay() {
        let drive = IconID(bundleID: "com.google.drivefs")
        let layout = propose(inputs(sampleBar()), pinned: [drive])
        #expect(layout.placements[drive] == .menuBar)
        #expect(!drawerNames(layout).contains("Files & Cloud"))
    }

    @Test func pastTheLimitTheSmallestDrawersMergeIntoOther() {
        let bar = MenuBarSnapshot(icons: [
            icon("com.google.drivefs", x: 0, name: "Google Drive"), icon("com.getdropbox.dropbox", x: 40, name: "Dropbox"),
            icon("com.box.desktop", x: 80, name: "Box"),
            icon("com.1password.1password", x: 120, name: "1Password"), icon("com.bitwarden.desktop", x: 160, name: "Bitwarden"),
            icon("com.hnc.Discord", x: 200, name: "Discord"), icon("com.tinyspeck.slackmacgap", x: 240, name: "Slack"),
            icon("com.spotify.client", x: 280, name: "Spotify"), icon("com.rogueamoeba.soundsource", x: 320, name: "SoundSource"),
        ])
        let layout = propose(inputs(bar), maximumDrawers: 3)
        #expect(layout.drawers.count == 3)
        #expect(drawerNames(layout).first == "Files & Cloud", "the largest drawer survives")
        #expect(drawerNames(layout).last == "Other")
        #expect(members(layout, "Other").count == 4)
    }

    @Test func byDeveloperGroupsAVendorsApps() {
        let bar = MenuBarSnapshot(icons: [
            icon("com.protonmail.bridge", x: 0, name: "Proton Mail Bridge"),
            icon("ch.protonvpn.mac", x: 40, name: "Proton VPN"),
            icon("me.proton.drive", x: 80, name: "Proton Drive"),
            icon("com.google.drivefs", x: 120, name: "Google Drive"),
        ])
        let developers = ["com.protonmail.bridge": "Proton", "ch.protonvpn.mac": "Proton", "me.proton.drive": "Proton", "com.google.drivefs": "Google"]
        let layout = propose(inputs(bar, developers: developers), .developer)
        #expect(drawerNames(layout) == ["Proton"])
        #expect(layout.drawers.first?.mark == .text("P"))
        #expect(layout.placements[IconID(bundleID: "com.google.drivefs")] == .menuBar)
    }

    @Test func justOnePutsEverythingInOneDrawer() {
        let layout = propose(inputs(sampleBar()), .justOne)
        #expect(drawerNames(layout) == ["All Icons"])
        #expect(layout.drawers.first?.mark == SmartSort.everythingMark)
        #expect(members(layout, "All Icons").count == 6)
    }

    @Test func aDrawerMadeForTheSameKindKeepsItsCustomisation() {
        var previous = Layout()
        let customised = Drawer(name: "Admin", mark: .emoji("🗂️"), category: .files, showsName: true, shortcut: .defaultFocus)
        previous.addDrawer(customised)
        let layout = propose(inputs(sampleBar()), previous: previous)
        let files = layout.drawer(for: .files)
        #expect(files?.id == customised.id)
        #expect(files?.name == "Admin")
        #expect(files?.mark == .emoji("🗂️"))
        #expect(files?.showsName == true)
        #expect(files?.shortcut == .defaultFocus)
    }

    @Test func theProposalIsDeterministic() {
        let first = propose(inputs(sampleBar()))
        let second = propose(inputs(sampleBar()).reversed())
        #expect(first == second)
    }

    @Test func initials() {
        #expect(SmartSort.initial(of: "Google") == "G")
        #expect(SmartSort.initial(of: "1Password") == "1")
        #expect(SmartSort.initial(of: "  ") == "•")
    }
}

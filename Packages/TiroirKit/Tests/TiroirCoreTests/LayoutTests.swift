import Foundation
import Testing
@testable import TiroirCore

@Suite struct LayoutTests {
    let cloud = Drawer(name: "Files & Cloud", mark: .emoji("☁️"), category: .files)
    let drive = IconID(bundleID: "com.google.drivefs")
    let dropbox = IconID(bundleID: "com.getdropbox.dropbox")

    @Test func aRecordedPlacementWins() {
        var layout = Layout(drawers: [cloud])
        layout.assign(drive, to: .hidden)
        #expect(layout.placement(of: drive, category: .files) == .hidden)
        #expect(layout.knows(drive))
    }

    @Test func aNewIconIsSortedIntoTheDrawerMadeForItsKind() {
        let layout = Layout(drawers: [cloud], newIconPolicy: .sortIntoDrawer)
        #expect(layout.placement(of: dropbox, category: .files) == .drawer(cloud.id))
        #expect(layout.placement(of: dropbox, category: .games) == .menuBar)
        #expect(layout.placement(of: dropbox, category: nil) == .menuBar)
        #expect(!layout.knows(dropbox))
    }

    @Test func theNewIconPolicyCanShowOrHide() {
        #expect(Layout(drawers: [cloud], newIconPolicy: .menuBar).placement(of: dropbox, category: .files) == .menuBar)
        #expect(Layout(drawers: [cloud], newIconPolicy: .hidden).placement(of: dropbox, category: .files) == .hidden)
    }

    @Test func removingADrawerNeverHidesAnIcon() {
        var layout = Layout(drawers: [cloud])
        layout.assign(drive, to: .drawer(cloud.id))
        layout.removeDrawer(cloud.id)
        #expect(layout.drawers.isEmpty)
        #expect(layout.placement(of: drive, category: .files) == .menuBar)
    }

    @Test func aPlacementInAMissingDrawerMeansTheMenuBar() {
        var layout = Layout()
        layout.assign(drive, to: .drawer(UUID()))
        #expect(layout.placement(of: drive, category: .files) == .menuBar)
    }

    @Test func drawersKeepTheirOrderAndMove() {
        let a = Drawer(name: "A", mark: .emoji("🅰️"))
        let b = Drawer(name: "B", mark: .emoji("🅱️"))
        let c = Drawer(name: "C", mark: .text("C"))
        var layout = Layout()
        layout.addDrawer(a)
        layout.addDrawer(c)
        layout.addDrawer(b, at: 1)
        layout.addDrawer(a)
        #expect(layout.drawers.map(\.name) == ["A", "B", "C"])
        layout.moveDrawer(c.id, to: 0)
        #expect(layout.drawers.map(\.name) == ["C", "A", "B"])
        layout.moveDrawer(c.id, to: 99)
        #expect(layout.drawers.map(\.name) == ["A", "B", "C"])
    }

    @Test func updatingADrawerCleansItsNameAndMark() {
        var layout = Layout(drawers: [cloud])
        var renamed = cloud
        renamed.name = "   Files   "
        renamed.mark = .text("CLOUD")
        layout.updateDrawer(renamed)
        #expect(layout.drawers[0].name == "Files")
        #expect(layout.drawers[0].mark == .text("CLO"))
    }

    @Test func membersFollowTheMenuBarOrder() {
        let bar = sampleBar()
        var layout = Layout(drawers: [cloud])
        layout.assign(IconID(bundleID: "com.protonmail.bridge"), to: .drawer(cloud.id))
        layout.assign(drive, to: .drawer(cloud.id))
        let members = layout.members(of: cloud.id, in: bar, categories: [:])
        #expect(members.map(\.id.bundleID) == ["com.google.drivefs", "com.protonmail.bridge"])
    }

    @Test func iconsMacOSKeepsInPlaceAreNeverMembers() {
        let bar = sampleBar()
        var layout = Layout(drawers: [cloud])
        layout.assign(IconID(bundleID: "com.apple.controlcenter", key: "com.apple.menuextra.clock"), to: .drawer(cloud.id))
        #expect(layout.members(of: cloud.id, in: bar, categories: [:]).isEmpty)
    }

    @Test func layoutsSurviveACodableRoundTrip() throws {
        var layout = Layout(drawers: [cloud], newIconPolicy: .hidden)
        layout.assign(drive, to: .drawer(cloud.id))
        layout.assign(dropbox, to: .hidden)
        layout.assign(IconID(bundleID: "com.apple.controlcenter", key: "com.apple.menuextra.wifi"), to: .menuBar)
        let data = try JSONEncoder().encode(layout)
        #expect(try JSONDecoder().decode(Layout.self, from: data) == layout)
    }

    @Test func aMalformedEntryIsSkippedNotEverything() throws {
        let json = """
        {"drawers": [], "newIconPolicy": "menuBar", "placements": [
          {"icon": {"bundleID": "com.google.drivefs", "key": ""}, "placement": {"kind": "hidden"}},
          {"icon": 42, "placement": {"kind": "hidden"}},
          {"icon": {"bundleID": "com.getdropbox.dropbox", "key": ""}, "placement": {"kind": "somethingNew"}}
        ], "futureKey": true}
        """
        let layout = try JSONDecoder().decode(Layout.self, from: Data(json.utf8))
        #expect(layout.placements.count == 2)
        #expect(layout.placements[drive] == .hidden)
        #expect(layout.placements[dropbox] == .menuBar)
        #expect(layout.newIconPolicy == .menuBar)
    }
}

@Suite struct DrawerMarkTests {
    @Test func anEmojiMarkIsOneEmoji() {
        #expect(DrawerMark.emoji("☁️").isValid)
        #expect(DrawerMark.emoji("🛠️").isValid)
        #expect(DrawerMark.emoji("👩‍💻").isValid)
        #expect(!DrawerMark.emoji("☁️☁️").isValid)
        #expect(!DrawerMark.emoji("A").isValid)
        #expect(!DrawerMark.emoji("1").isValid)
        #expect(!DrawerMark.emoji("").isValid)
    }

    @Test func symbolAndTextMarks() {
        #expect(DrawerMark.symbol("cloud.fill").isValid)
        #expect(!DrawerMark.symbol(" ").isValid)
        #expect(DrawerMark.text("Dev").isValid)
        #expect(!DrawerMark.text("Devs").isValid)
        #expect(!DrawerMark.text("   ").isValid)
        #expect(DrawerMark.text(" Devs ").normalized == .text("Dev"))
    }

    @Test func anInvalidMarkBecomesABox() {
        let drawer = Drawer(name: "x", mark: .emoji("not an emoji")).clamped
        #expect(drawer.mark == .fallback)
    }

    @Test func marksEncodeReadably() throws {
        let data = try JSONEncoder().encode(DrawerMark.symbol("cloud.fill"))
        #expect(String(decoding: data, as: UTF8.self) == #"{"symbol":"cloud.fill"}"#)
        #expect(try JSONDecoder().decode(DrawerMark.self, from: Data(#"{"emoji":"🎧"}"#.utf8)) == .emoji("🎧"))
        #expect(try JSONDecoder().decode(DrawerMark.self, from: Data("{}".utf8)) == .fallback)
    }

    @Test func aDrawerWithMissingFieldsStillDecodes() throws {
        let drawer = try JSONDecoder().decode(Drawer.self, from: Data(#"{"name": "Old", "category": "nonsense"}"#.utf8))
        #expect(drawer.name == "Old")
        #expect(drawer.category == nil)
        #expect(drawer.mark == .fallback)
    }
}

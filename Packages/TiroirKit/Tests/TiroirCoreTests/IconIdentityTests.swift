import Foundation
import Testing
@testable import TiroirCore

@Suite struct IconIdentityTests {
    @Test func anAppsOnlyIconHasNoKey() {
        let id = IconIdentity.make(bundleID: "com.google.drivefs", identifier: nil, indexFromRight: 0, countForApp: 1)
        #expect(id == IconID(bundleID: "com.google.drivefs"))
        #expect(id.description == "com.google.drivefs")
    }

    @Test func controlCenterModulesUseTheirIdentifier() {
        let wifi = IconIdentity.make(bundleID: "com.apple.controlcenter", identifier: "com.apple.menuextra.wifi", indexFromRight: 3, countForApp: 6)
        let battery = IconIdentity.make(bundleID: "com.apple.controlcenter", identifier: "com.apple.menuextra.battery", indexFromRight: 4, countForApp: 6)
        #expect(wifi.key == "com.apple.menuextra.wifi")
        #expect(wifi != battery)
        #expect(wifi.description == "com.apple.controlcenter/com.apple.menuextra.wifi")
    }

    @Test func iconsWithoutIdentifiersAreCountedFromTheRight() {
        let first = IconIdentity.make(bundleID: "com.bjango.istatmenus", identifier: nil, indexFromRight: 0, countForApp: 3)
        let third = IconIdentity.make(bundleID: "com.bjango.istatmenus", identifier: "  ", indexFromRight: 2, countForApp: 3)
        #expect(first.key == "#0")
        #expect(third.key == "#2")
    }

    /// Wi-Fi describes its signal, Pli shows the lid angle: none of it may change who the icon is.
    @Test func titleChangesKeepTheIdentity() {
        let before = IconIdentity.make(bundleID: "ch.rubencatalao.pli", identifier: nil, indexFromRight: 0, countForApp: 1)
        let after = IconIdentity.make(bundleID: "ch.rubencatalao.pli", identifier: nil, indexFromRight: 0, countForApp: 1)
        #expect(before == after)
        let wifiStrong = IconIdentity.make(bundleID: "com.apple.controlcenter", identifier: "com.apple.menuextra.wifi", indexFromRight: 3, countForApp: 6)
        let wifiMoved = IconIdentity.make(bundleID: "com.apple.controlcenter", identifier: "com.apple.menuextra.wifi", indexFromRight: 5, countForApp: 7)
        #expect(wifiStrong == wifiMoved)
    }

    @Test func identitiesSortByAppThenKey() {
        let ids = [IconID(bundleID: "b"), IconID(bundleID: "a", key: "#1"), IconID(bundleID: "a", key: "#0")]
        #expect(ids.sorted() == [IconID(bundleID: "a", key: "#0"), IconID(bundleID: "a", key: "#1"), IconID(bundleID: "b")])
    }

    @Test func identitiesSurviveACodableRoundTrip() throws {
        let id = IconID(bundleID: "com.apple.controlcenter", key: "com.apple.menuextra.sound")
        let data = try JSONEncoder().encode(id)
        #expect(try JSONDecoder().decode(IconID.self, from: data) == id)
    }

    @Test func theSnapshotKeepsTheClockFirst() {
        let bar = sampleBar()
        #expect(bar.icons.first?.id.key == "com.apple.menuextra.clock")
        #expect(bar.icons.last?.id.bundleID == "ch.rubencatalao.pli")
        #expect(bar.bundleIDs.contains("com.google.drivefs"))
        #expect(bar.icon(IconID(bundleID: "com.protonmail.bridge"))?.ownerName == "Proton Mail Bridge")
    }

    @Test func systemIconsAreNamedByTheirLabel() {
        let wifi = icon("com.apple.controlcenter", key: "com.apple.menuextra.wifi", x: 0, name: "Control Center", label: "Wi-Fi", kind: .system)
        let drive = icon("com.google.drivefs", x: 0, name: "Google Drive", label: "Google Drive, syncing")
        #expect(wifi.displayName == "Wi-Fi")
        #expect(drive.displayName == "Google Drive")
    }
}

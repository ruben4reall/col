import CoreGraphics
import Foundation
import Testing
@testable import TiroirCore

@Suite struct LayoutPlannerTests {
    let files = Drawer(name: "Files & Cloud", mark: .emoji("☁️"), category: .files)

    func layout() -> Layout {
        var layout = Layout(drawers: [files])
        layout.assign(IconID(bundleID: "com.google.drivefs"), to: .drawer(files.id))
        layout.assign(IconID(bundleID: "com.protonmail.bridge"), to: .drawer(files.id))
        layout.assign(IconID(bundleID: "ch.rubencatalao.pli"), to: .hidden)
        layout.assign(IconID(bundleID: "com.apple.controlcenter", key: "com.apple.menuextra.clock"), to: .hidden)
        return layout
    }

    @Test func drawersAndHiddenIconsAreConcealed() {
        let plan = LayoutPlanner.plan(layout: layout(), snapshot: sampleBar(), granularity: .icon, categories: [:])
        #expect(plan.concealed == [IconID(bundleID: "com.google.drivefs"), IconID(bundleID: "com.protonmail.bridge"), IconID(bundleID: "ch.rubencatalao.pli")])
        #expect(plan.visible.contains(IconID(bundleID: "com.anthropic.claudefordesktop")))
        #expect(plan.hiddenApps == ["com.google.drivefs", "com.protonmail.bridge", "ch.rubencatalao.pli"])
        #expect(plan.conflicts.isEmpty)
    }

    @Test func iconsMacOSKeepsInPlaceAlwaysShow() {
        let plan = LayoutPlanner.plan(layout: layout(), snapshot: sampleBar(), granularity: .icon, categories: [:])
        #expect(plan.visible.contains(IconID(bundleID: "com.apple.controlcenter", key: "com.apple.menuextra.clock")))
    }

    /// macOS 27 hides whole apps: an app with one icon placed in the menu bar and one in a drawer stays visible.
    @Test func appGranularityKeepsMixedAppsVisibleAndNamesThem() {
        let bar = MenuBarSnapshot(icons: [
            icon("com.bjango.istatmenus", key: "#0", x: 300),
            icon("com.bjango.istatmenus", key: "#1", x: 260),
            icon("com.google.drivefs", x: 220),
        ])
        var layout = layout()
        layout.assign(IconID(bundleID: "com.bjango.istatmenus", key: "#1"), to: .hidden)
        let perIcon = LayoutPlanner.plan(layout: layout, snapshot: bar, granularity: .icon, categories: [:])
        #expect(perIcon.concealed.contains(IconID(bundleID: "com.bjango.istatmenus", key: "#1")))
        let perApp = LayoutPlanner.plan(layout: layout, snapshot: bar, granularity: .app, categories: [:])
        #expect(perApp.conflicts == ["com.bjango.istatmenus"])
        #expect(perApp.visible.isSuperset(of: [IconID(bundleID: "com.bjango.istatmenus", key: "#0"), IconID(bundleID: "com.bjango.istatmenus", key: "#1")]))
        #expect(perApp.hiddenApps == ["com.google.drivefs"])
    }

    @Test func showEverythingAndFocus() {
        let everything = LayoutPlanner.plan(layout: layout(), snapshot: sampleBar(), granularity: .icon, categories: [:], mode: .showEverything)
        #expect(everything.concealed.isEmpty)
        let focus = LayoutPlanner.plan(layout: layout(), snapshot: sampleBar(), granularity: .icon, categories: [:], mode: .focus)
        #expect(focus.visible == [IconID(bundleID: "com.apple.controlcenter", key: "com.apple.menuextra.clock"),
                                  IconID(bundleID: "com.apple.controlcenter", key: "com.apple.menuextra.controlcenter")])
    }

    @Test func newIconsFollowThePolicy() {
        let bar = MenuBarSnapshot(icons: [icon("com.getdropbox.dropbox", x: 900)])
        let plan = LayoutPlanner.plan(layout: layout(), snapshot: bar, granularity: .icon,
                                      categories: [IconID(bundleID: "com.getdropbox.dropbox"): .files])
        #expect(plan.concealed == [IconID(bundleID: "com.getdropbox.dropbox")])
    }

    /// The divider sits at x 900 (right edge): left of it, icons are out of the menu bar.
    @Test func movesCarryOnlyMisplacedIconsNearestFirst() {
        let bar = MenuBarSnapshot(icons: [
            icon("com.anthropic.claudefordesktop", x: 850),
            icon("com.google.drivefs", x: 1095),
            icon("com.protonmail.bridge", x: 1057),
            icon("ch.rubencatalao.pli", x: 800),
        ])
        let divider = CGRect(x: 880, y: 0, width: 20, height: 33)
        let plan = LayoutPlanner.plan(layout: layout(), snapshot: bar, granularity: .icon, categories: [:])
        let moves = LayoutPlanner.moves(plan: plan, snapshot: bar, dividerFrame: divider)
        #expect(moves == [
            Move(icon: IconID(bundleID: "com.anthropic.claudefordesktop"), to: .visible),
            Move(icon: IconID(bundleID: "com.protonmail.bridge"), to: .concealed),
            Move(icon: IconID(bundleID: "com.google.drivefs"), to: .concealed),
        ])
    }

    /// An icon that appears while Tiroir arranges the bar is in the next plan once, and icons already in place are
    /// not moved again.
    @Test func newIconDuringApplyIsPlannedOnce() {
        let divider = CGRect(x: 880, y: 0, width: 20, height: 33)
        let settled = MenuBarSnapshot(icons: [icon("com.google.drivefs", x: 700), icon("com.anthropic.claudefordesktop", x: 1000)])
        var withNewcomer = settled
        withNewcomer.icons.append(icon("com.getdropbox.dropbox", x: 1040))
        withNewcomer = MenuBarSnapshot(icons: withNewcomer.icons)
        let categories = [IconID(bundleID: "com.getdropbox.dropbox"): CategoryID.files]
        let plan = LayoutPlanner.plan(layout: layout(), snapshot: withNewcomer, granularity: .icon, categories: categories)
        let moves = LayoutPlanner.moves(plan: plan, snapshot: withNewcomer, dividerFrame: divider)
        #expect(moves == [Move(icon: IconID(bundleID: "com.getdropbox.dropbox"), to: .concealed)])
    }

    @Test func iconsMacOSKeepsInPlaceAreNeverMoved() {
        let divider = CGRect(x: 1400, y: 0, width: 20, height: 33)
        let plan = LayoutPlanner.plan(layout: layout(), snapshot: sampleBar(), granularity: .icon, categories: [:])
        let moves = LayoutPlanner.moves(plan: plan, snapshot: sampleBar(), dividerFrame: divider)
        #expect(!moves.contains { $0.icon.bundleID == "com.apple.controlcenter" && $0.icon.key.hasSuffix("clock") })
    }
}

@Suite struct FrameMatcherTests {
    /// Frames seen on macOS 26.5: Accessibility elements against Control Center's windows.
    @Test func realFramesMatch() {
        let elements = [
            FrameMatcher.Element(index: 0, frame: CGRect(x: 1094, y: 4.5, width: 34, height: 24)),
            FrameMatcher.Element(index: 1, frame: CGRect(x: 1064, y: 4.5, width: 24, height: 24)),
            FrameMatcher.Element(index: 2, frame: CGRect(x: 1016, y: 3.5, width: 42, height: 26)),
        ]
        let windows = [
            FrameMatcher.Window(id: 70, frame: CGRect(x: 1095, y: 0, width: 32, height: 33)),
            FrameMatcher.Window(id: 98, frame: CGRect(x: 1057, y: 0, width: 38, height: 33)),
            FrameMatcher.Window(id: 112, frame: CGRect(x: 1017, y: 0, width: 40, height: 33)),
            FrameMatcher.Window(id: 26, frame: CGRect(x: 1363, y: 0, width: 151, height: 33)),
        ]
        #expect(FrameMatcher.match(elements: elements, windows: windows) == [0: 70, 1: 98, 2: 112])
    }

    @Test func aWindowGoesToOneElementOnly() {
        let elements = [
            FrameMatcher.Element(index: 0, frame: CGRect(x: 100, y: 4, width: 20, height: 24)),
            FrameMatcher.Element(index: 1, frame: CGRect(x: 104, y: 4, width: 20, height: 24)),
        ]
        let windows = [FrameMatcher.Window(id: 1, frame: CGRect(x: 100, y: 0, width: 28, height: 33))]
        let result = FrameMatcher.match(elements: elements, windows: windows)
        #expect(result.count == 1)
        #expect(result[1] == 1, "the element nearest the window's middle wins")
    }

    @Test func iconsHiddenByMacOSMatchNothing() {
        let elements = [FrameMatcher.Element(index: 0, frame: CGRect(x: -1, y: 969, width: 42, height: 26))]
        let windows = [FrameMatcher.Window(id: 1, frame: CGRect(x: 0, y: 0, width: 40, height: 33))]
        #expect(FrameMatcher.match(elements: elements, windows: windows).isEmpty)
    }

    @Test func emptyElementsAreIgnored() {
        let elements = [FrameMatcher.Element(index: 0, frame: CGRect(x: 0, y: 982, width: 0, height: 0))]
        #expect(FrameMatcher.match(elements: elements, windows: [FrameMatcher.Window(id: 1, frame: .zero)]).isEmpty)
    }
}

@Suite struct NotchCapacityTests {
    func item(_ name: String, _ width: CGFloat) -> NotchCapacity.Item {
        NotchCapacity.Item(id: IconID(bundleID: name), width: width)
    }

    @Test func everythingFits() {
        let result = NotchCapacity.evaluate(room: 664, items: [item("clock", 151), item("cc", 42), item("a", 40)])
        #expect(result.fits)
        #expect(result.used == 233)
        #expect(result.share < 0.4)
    }

    /// Tiroir's own drawers take room like any icon: a drawer behind the notch would lock its icons away.
    @Test func drawerItemsCountTowardTheRoom() {
        let icons = [item("clock", 151), item("cc", 42), item("a", 40), item("b", 40)]
        #expect(NotchCapacity.evaluate(room: 300, items: icons).fits)
        let withDrawers = icons + [item("tiroir.drawer.1", 30), item("tiroir.drawer.2", 30)]
        let result = NotchCapacity.evaluate(room: 300, items: withDrawers)
        #expect(result.overflow == [IconID(bundleID: "tiroir.drawer.2"), IconID(bundleID: "tiroir.drawer.1")])
        #expect(result.share > 1)
    }

    @Test func overflowListsTheLeftmostFirst() {
        let result = NotchCapacity.evaluate(room: 100, items: [item("a", 40), item("b", 40), item("c", 40), item("d", 40)])
        #expect(result.overflow == [IconID(bundleID: "d"), IconID(bundleID: "c")])
    }

    @Test func spacingCountsBetweenIcons() {
        #expect(NotchCapacity.evaluate(room: 100, items: [item("a", 48), item("b", 48)], spacing: 8).overflow.count == 1)
        #expect(NotchCapacity.evaluate(room: 100, items: [item("a", 48), item("b", 48)], spacing: 0).fits)
    }
}

@Suite struct SearchRankerTests {
    let items = [
        SearchItem(id: IconID(bundleID: "com.apple.controlcenter", key: "wifi"), title: "Wi-Fi", subtitle: "Connected"),
        SearchItem(id: IconID(bundleID: "com.google.drivefs"), title: "Google Drive", drawerName: "Files & Cloud"),
        SearchItem(id: IconID(bundleID: "com.protonmail.bridge"), title: "Proton Mail Bridge", drawerName: "Files & Cloud"),
        SearchItem(id: IconID(bundleID: "com.docker.docker"), title: "Docker Desktop", drawerName: "Developer"),
        SearchItem(id: IconID(bundleID: "com.apple.controlcenter", key: "battery"), title: "Battery"),
    ]

    func titles(_ query: String) -> [String] { SearchRanker.rank(query, in: items).map(\.title) }

    @Test func anEmptyQueryKeepsTheMenuBarOrder() {
        #expect(titles("") == items.map(\.title))
        #expect(titles("   ") == items.map(\.title))
    }

    @Test func prefixesBeatMatchesInsideWords() {
        #expect(titles("dr") == ["Google Drive"])
        #expect(titles("dock") == ["Docker Desktop"])
        #expect(titles("de") == ["Docker Desktop"], "a word prefix (Desktop) beats the drawer name (Developer)")
        #expect(titles("ri") == ["Google Drive", "Proton Mail Bridge"], "inside words, in menu bar order")
    }

    @Test func caseAndAccentsDoNotMatter() {
        #expect(titles("WI") == ["Wi-Fi"])
        #expect(titles("bättery") == ["Battery"])
    }

    @Test func initialsFindAnApp() {
        #expect(titles("gd").first == "Google Drive")
        #expect(titles("pmb").first == "Proton Mail Bridge")
    }

    @Test func drawerNamesAndLabelsMatchToo() {
        #expect(titles("files") == ["Google Drive", "Proton Mail Bridge"])
        #expect(titles("connected") == ["Wi-Fi"])
    }

    @Test func noMatchNoResult() {
        #expect(titles("zzz").isEmpty)
    }
}

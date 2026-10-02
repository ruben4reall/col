import ColCore
import Observation
import SwiftUI

/// Where the open island is: one of the user's pages, or one of the views the island opens on by itself.
enum IslandRoute: Hashable {
    /// A page of the user's deck, by its id.
    case page(String)
    /// Everything running: AI apps and activities pushed by scripts. Its tab sits right of the camera.
    case live
    /// The hello written on first launch; never a tab.
    case greeting
    /// Headphones that just connected; never a tab.
    case device
    /// Files dragged over the island when no page holds the shelf: the shelf all the same.
    case drop
    /// Souffleur, the prompter's former app, closed because it is now part of Col; never a tab.
    case souffleur

    var symbol: String {
        switch self {
        case .page: "square.fill"
        case .live: "dot.radiowaves.left.and.right"
        case .greeting: "hand.wave.fill"
        case .device: "airpodspro"
        case .drop: "tray.full.fill"
        case .souffleur: "text.aligncenter"
        }
    }
}

extension PageLayout {
    /// The page's name: the user's, else one made from what it holds.
    var title: String {
        if let name, !name.trimmingCharacters(in: .whitespaces).isEmpty { return name }
        if id == PageDeck.homeID { return String(localized: "Home", bundle: .module) }
        let kinds = widgets
        if kinds.count == 1 { return String(localized: kinds[0].title) }
        return ListFormatter.localizedString(byJoining: stacks.compactMap(\.widgets.first).map { String(localized: $0.title) })
    }

    /// The symbol of the page's tab.
    var tabSymbol: String {
        if let symbol { return symbol }
        if id == PageDeck.homeID { return "house.fill" }
        return widgets.first?.symbol ?? "square.fill"
    }
}

@MainActor
@Observable
final class IslandNavigation {
    /// The greeting says it is ready ("Let's go") instead of hello: after the welcome.
    var greetsReady = false
    private(set) var route: IslandRoute
    /// The user's pages, so the tab bar redraws when they change.
    private(set) var deck: PageDeck
    /// +1 when moving right, -1 when moving left: pages slide in from the side they come from.
    private(set) var direction = 1

    init(deck: PageDeck = Preferences.pageDeck) {
        self.deck = deck
        route = .page(deck.pages.first?.id ?? PageDeck.homeID)
    }

    var tabs: [PageLayout] { deck.pages }

    /// The page on show, when the island shows a page.
    var currentPage: PageLayout? {
        if case .page(let id) = route { return deck.page(id) }
        return nil
    }

    func reloadDeck() {
        deck = Preferences.pageDeck
        if case .page(let id) = route, deck.page(id) == nil { route = .page(deck.pages[0].id) }
    }

    /// Shows a page without a deck of its own, such as the settings' preview of a page being edited.
    func use(_ deck: PageDeck) {
        self.deck = deck
        if case .page(let id) = route, deck.page(id) == nil { route = .page(deck.pages[0].id) }
    }

    func showHome() {
        show(.page(deck.pages[0].id))
    }

    /// Back to the first page without moving, once a view the island opened on by itself has gone.
    func jumpHome() {
        route = .page(deck.pages[0].id)
    }

    /// Shows the first page that holds a widget, or the given route when none does.
    func show(_ kind: WidgetKind, otherwise fallback: IslandRoute) {
        show(deck.firstPage(holding: kind).map { .page($0.id) } ?? fallback)
    }

    func show(_ route: IslandRoute) {
        guard route != self.route else { return }
        let order = deck.pages.map { IslandRoute.page($0.id) } + [.live]
        direction = (order.firstIndex(of: route) ?? 0) > (order.firstIndex(of: self.route) ?? 0) ? 1 : -1
        withAnimation(.spring(duration: 0.42, bounce: 0.18)) { self.route = route }
    }

    /// Sets the route without moving, for views the island opens on by itself.
    func jump(to route: IslandRoute) {
        self.route = route
    }

    func step(_ offset: Int) {
        let routes = deck.pages.map { IslandRoute.page($0.id) } + [.live]
        guard let index = routes.firstIndex(of: route) else { return }
        show(routes[min(max(index + offset, 0), routes.count - 1)])
    }
}

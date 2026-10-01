import Observation
import SwiftUI

@MainActor
@Observable
final class IslandContentModel {
    var isPresented = false
    var notchWidth: CGFloat = 180
    var notchHeight: CGFloat = 32
}

/// Everything the island's content needs, handed down once.
@MainActor
struct IslandServices {
    let media: MediaController
    let lyrics: LyricsModel
    let ai: AIAppsModel
    let agents: AgentCenter
    let custom: CustomActivities
    let navigation: IslandNavigation
    let power: PowerMonitor
    let shelf: ShelfModel
    let clipboard: ClipboardMonitor
    let timer: TimerModel
    let picker: ColorPickerModel
    let mirror: MirrorModel
    let calendar: CalendarModel
    let stats: SystemStatsModel
    let device: DeviceCardModel
    let audio: AudioMonitor
    let awake: KeepAwake
    let openSettings: () -> Void

    /// The same models with pages of their own, for a second island such as the one in the settings.
    func with(navigation: IslandNavigation) -> IslandServices {
        IslandServices(
            media: media, lyrics: lyrics, ai: ai, agents: agents, custom: custom, navigation: navigation, power: power, shelf: shelf,
            clipboard: clipboard, timer: timer, picker: picker, mirror: mirror, calendar: calendar, stats: stats,
            device: device, audio: audio, awake: awake, openSettings: openSettings
        )
    }
}

/// The open island: the top row beside the camera, then the current page. The content materialises from a blur as
/// the island opens and fades out quickly as it closes, so the outline always leads the motion.
struct IslandContentView: View {
    let model: IslandContentModel
    let services: IslandServices

    var body: some View {
        VStack(spacing: 0) {
            TopBar(
                navigation: services.navigation,
                agents: services.agents,
                custom: services.custom,
                power: services.power,
                notchWidth: model.notchWidth,
                openSettings: services.openSettings
            )
            .frame(height: model.notchHeight)
            .opacity(model.isPresented && services.navigation.route != .greeting && services.navigation.route != .device ? 1 : 0)
            .animation(model.isPresented ? .easeOut(duration: 0.3).delay(0.12) : .easeOut(duration: 0.1), value: model.isPresented)

            page
                .padding(Theme.inset)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .opacity(model.isPresented ? 1 : 0)
                .blur(radius: model.isPresented ? 0 : 8)
                .scaleEffect(model.isPresented ? 1 : 0.94, anchor: .top)
                .animation(
                    model.isPresented ? .spring(duration: 0.45, bounce: 0.2).delay(0.06) : .easeOut(duration: 0.12),
                    value: model.isPresented
                )
        }
        .environment(\.colorScheme, .dark)
    }

    @ViewBuilder private var page: some View {
        let direction = CGFloat(services.navigation.direction)
        ZStack {
            switch services.navigation.route {
            case .page(let id):
                if let layout = services.navigation.deck.page(id) {
                    PageView(page: layout, services: services)
                        .transition(slide(direction))
                        .id(id)
                }
            case .live:
                LivePage(agents: services.agents, custom: services.custom)
                    .transition(slide(direction))
            case .drop:
                ShelfPage(shelf: services.shelf)
                    .transition(.opacity)
            case .greeting:
                GreetingView()
                    .transition(.opacity)
            case .device:
                DeviceCardView(model: services.device)
                    .transition(.opacity)
            }
        }
    }

    private func slide(_ direction: CGFloat) -> AnyTransition {
        .asymmetric(
            insertion: .offset(x: 60 * direction).combined(with: .opacity),
            removal: .offset(x: -60 * direction).combined(with: .opacity)
        )
    }
}

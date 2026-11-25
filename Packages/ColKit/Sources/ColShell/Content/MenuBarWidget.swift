import SwiftUI

/// The island's Menu Bar page: the drawers and their icons while they run, a click away from each icon's menu; else
/// what keeps them from running, and the one thing to do about it.
struct MenuBarWidget: View {
    @State private var drawers = MenuBarDrawers.shared
    @State private var permissions = PermissionCenter.shared

    var body: some View {
        if drawers.status == .running, let runner = drawers.runner, runner.issue == nil {
            runner.islandView { IslandController.shared?.closeIsland() }
        } else {
            offer
        }
    }

    @ViewBuilder private var offer: some View {
        VStack(spacing: 7) {
            Image(systemName: "menubar.rectangle")
                .font(.system(size: 22, weight: .medium))
                .foregroundStyle(Theme.secondaryText)
            Group {
                if !drawers.isSupportedHere {
                    Text("Tidy the menu bar into drawers", bundle: .module)
                } else if drawers.status == .yieldsToTiroir {
                    Text("Tiroir is open", bundle: .module)
                } else {
                    Text("Tidy the menu bar into drawers", bundle: .module)
                }
            }
            .font(.system(size: 13, weight: .semibold))
            .foregroundStyle(.white)
            Group {
                if !drawers.isSupportedHere {
                    Text("Needs macOS 26 or later.", bundle: .module)
                } else if drawers.status == .yieldsToTiroir {
                    Text("Tiroir already tidies your menu bar. Quit it, and Col takes over with the same drawers.", bundle: .module)
                } else if drawers.status == .running {
                    Text("The drawers need it to see which app owns each icon and to open them. Until then, every icon stays in the menu bar.", bundle: .module)
                } else {
                    Text("Icons you rarely look at wait in drawers, here and in the menu bar, and the island gets more room beside the notch.", bundle: .module)
                }
            }
            .font(.system(size: 11.5))
            .foregroundStyle(Theme.secondaryText)
            .multilineTextAlignment(.center)
            .lineLimit(3)
            .padding(.horizontal, 24)
            if drawers.isSupportedHere {
                Button(action: act) { actionTitle }
                    .buttonStyle(IslandCapsuleStyle())
                    .padding(.top, 2)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(
            RoundedRectangle(cornerRadius: Theme.cardRadius, style: .continuous)
                .strokeBorder(Color.white.opacity(0.14), style: StrokeStyle(lineWidth: 1.5, dash: [5, 4]))
        )
    }

    @ViewBuilder private var actionTitle: some View {
        if drawers.status == .yieldsToTiroir {
            Text("Quit Tiroir", bundle: .module)
        } else if drawers.status == .running {
            Text("Allow…", bundle: .module)
        } else {
            Text("Turn On", bundle: .module)
        }
    }

    private func act() {
        switch drawers.status {
        case .yieldsToTiroir: drawers.quitStandalone()
        case .running: permissions.request(.accessibility)
        case .off, .needsNewerMacOS: drawers.setEnabled(true)
        }
    }
}

/// A small capsule in the accent, for the one thing a card of the island asks.
struct IslandCapsuleStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 12, weight: .semibold))
            .foregroundStyle(.white)
            .padding(.horizontal, 14)
            .frame(height: 26)
            .background(Capsule().fill(Theme.accent))
            .opacity(configuration.isPressed ? 0.75 : 1)
            .contentShape(Capsule())
    }
}

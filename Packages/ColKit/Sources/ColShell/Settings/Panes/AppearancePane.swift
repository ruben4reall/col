import ColCore
import SwiftUI

struct AppearancePane: View {
    @State private var size = Preferences.islandSize
    @State private var motion = Preferences.motionStyle
    @State private var glass = Preferences.islandGlass
    @State private var opensOnHover = Preferences.opensOnHover
    @State private var delay = Preferences.hoverDelay
    @State private var notchStyle = Preferences.notchStyle
    @State private var floatingStyle = Preferences.floatingStyle
    @State private var showsAtRest = Preferences.showsIslandAtRest
    @State private var wingLimit = Preferences.wingLimit
    @State private var activitiesBeneath = Preferences.activitiesBeneath
    /// This Mac has a screen with a notch.
    private let hasNotch = NSScreen.screens.contains { $0.safeAreaInsets.top > 0 }
    /// Replays the opening of the island in the stage after a change.
    @State private var replay = 0

    var body: some View {
        PaneScaffold(pane: .appearance) {
            Section {
                IslandStage(size: size, glass: IslandView.glassAvailable ? glass : .off, replay: replay)
                    .frame(height: IslandStage.height(for: size))
                    .listRowInsets(EdgeInsets())
                    .animation(.spring(duration: 0.45, bounce: 0.15), value: size)
            } footer: {
                Text("Your own island, drawn by Col on your wallpaper with what it shows right now. It opens and closes like the one in the notch.", bundle: .module)
            }
            Section {
                Picker(selection: $size) {
                    Text("Compact", bundle: .module).tag(IslandSize.compact)
                    Text("Standard", bundle: .module).tag(IslandSize.standard)
                    Text("Large", bundle: .module).tag(IslandSize.large)
                } label: { Text("Size when open", bundle: .module) }
                    .pickerStyle(.segmented)
                    .onChange(of: size) {
                        Preferences.islandSize = size
                        changed()
                    }
                if IslandView.glassAvailable {
                    Picker(selection: $glass) {
                        Text("Liquid", bundle: .module).tag(IslandGlass.liquid)
                        Text("Transparent", bundle: .module).tag(IslandGlass.transparent)
                        Text("Tinted", bundle: .module).tag(IslandGlass.tinted)
                        Text("Black", bundle: .module).tag(IslandGlass.off)
                    } label: { Text("Liquid Glass", bundle: .module) }
                        .pickerStyle(.segmented)
                        .onChange(of: glass) {
                            Preferences.islandGlass = glass
                            changed()
                        }
                }
                Picker(selection: $motion) {
                    Text("Snappy", bundle: .module).tag(MotionStyle.snappy)
                    Text("Standard", bundle: .module).tag(MotionStyle.standard)
                    Text("Relaxed", bundle: .module).tag(MotionStyle.relaxed)
                } label: { Text("Animation speed", bundle: .module) }
                    .pickerStyle(.segmented)
                    .onChange(of: motion) {
                        Preferences.motionStyle = motion
                        changed()
                    }
            } header: {
                Text("Look and feel", bundle: .module)
            } footer: {
                if IslandView.glassAvailable {
                    Text("Each change also shows on the notch, at the top of your screen.", bundle: .module)
                }
            }
            Section {
                if hasNotch {
                    Picker(selection: $notchStyle) {
                        Text("In the notch", bundle: .module).tag(FloatingStyle.notch)
                        Text("Below the menu bar", bundle: .module).tag(FloatingStyle.below)
                    } label: {
                        HStack(spacing: 12) {
                            IconTile(symbol: "macbook", tint: .gray)
                            Text("On the screen with the notch", bundle: .module)
                        }
                    }
                    .onChange(of: notchStyle) {
                        Preferences.notchStyle = notchStyle
                        changed()
                    }
                }
                Picker(selection: $floatingStyle) {
                    Text("A pill in the menu bar", bundle: .module).tag(FloatingStyle.pill)
                    Text("A notch drawn by Col", bundle: .module).tag(FloatingStyle.notch)
                    Text("Below the menu bar", bundle: .module).tag(FloatingStyle.below)
                } label: {
                    HStack(spacing: 12) {
                        IconTile(symbol: "display", tint: .blue)
                        Text("On screens without a notch", bundle: .module)
                    }
                }
                .onChange(of: floatingStyle) {
                    Preferences.floatingStyle = floatingStyle
                    changed()
                }
                Picker(selection: $wingLimit) {
                    Text("Narrow", bundle: .module).tag(IslandLayout.narrowWing)
                    Text("Standard", bundle: .module).tag(IslandLayout.standardWing)
                    Text("Wide", bundle: .module).tag(IslandLayout.wideWing)
                } label: {
                    VStack(alignment: .leading, spacing: 1) {
                        Text("Wings", bundle: .module)
                        Text("How far the closed island may reach beside the camera. It never covers a menu or an icon.", bundle: .module)
                            .font(.callout)
                            .foregroundStyle(.secondary)
                    }
                }
                .pickerStyle(.segmented)
                .onChange(of: wingLimit) {
                    Preferences.wingLimit = wingLimit
                    changed()
                }
                if (hasNotch && notchStyle == .notch) || floatingStyle == .notch {
                    IconToggle(symbol: "rectangle.bottomhalf.inset.filled", tint: .teal, title: "Always show activities beneath the camera",
                               detail: "Col already puts them there when the menu bar leaves no room beside the notch, so they never cover a menu or an icon.",
                               isOn: $activitiesBeneath)
                        .onChange(of: activitiesBeneath) {
                            Preferences.activitiesBeneath = activitiesBeneath
                            changed()
                        }
                }
                IconToggle(symbol: "capsule.fill", tint: .indigo, title: "Show the island when nothing happens",
                           detail: "Without a notch to hide behind, the resting island stays in sight as a small pill or a notch. Off, it appears only when something happens.",
                           isOn: $showsAtRest)
                    .onChange(of: showsAtRest) { Preferences.showsIslandAtRest = showsAtRest }
            } header: {
                Text("Shape", bundle: .module)
            } footer: {
                if hasNotch {
                    Text("Below the menu bar suits a Mac whose notch area already shows something, such as its own Dynamic Island.", bundle: .module)
                }
            }
            Section {
                IconToggle(symbol: "cursorarrow.rays", tint: .blue, title: "Open when the pointer rests on the notch", isOn: $opensOnHover)
                    .onChange(of: opensOnHover) { Preferences.opensOnHover = opensOnHover }
                if opensOnHover {
                    LabeledContent {
                        HStack {
                            Slider(value: $delay, in: 0...0.8, step: 0.05)
                                .onChange(of: delay) { Preferences.hoverDelay = delay }
                            Text(Duration.milliseconds(Int(delay * 1000)), format: .units(allowed: [.milliseconds], width: .abbreviated))
                                .monospacedDigit()
                                .foregroundStyle(.secondary)
                                .frame(width: 64, alignment: .trailing)
                        }
                    } label: {
                        Text("Delay before opening", bundle: .module)
                    }
                }
            } header: {
                Text("Opening", bundle: .module)
            } footer: {
                Text("A click or a two-finger swipe down always opens it at once.", bundle: .module)
            }
        }
    }

    /// Plays the change in the stage, and on the real island above the window.
    private func changed() {
        replay += 1
        IslandController.shared?.previewChange()
    }
}

import IsletCore
import SwiftUI

struct AppearancePane: View {
    @State private var size = Preferences.islandSize
    @State private var motion = Preferences.motionStyle
    @State private var glass = Preferences.islandGlass
    @State private var opensOnHover = Preferences.opensOnHover
    @State private var delay = Preferences.hoverDelay
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
                Text("Your own island, drawn by Islet on your wallpaper with what it shows right now. It opens and closes like the one in the notch.", bundle: .module)
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

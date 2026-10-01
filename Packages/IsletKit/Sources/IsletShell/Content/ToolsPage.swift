@preconcurrency import AVFoundation
import IsletCore
import SwiftUI

/// Small tools: a timer, a colour picker, and a mirror.
struct ToolsPage: View {
    let timer: TimerModel
    let picker: ColorPickerModel
    let mirror: MirrorModel
    let awake: KeepAwake

    var body: some View {
        HStack(spacing: 10) {
            TimerCard(timer: timer)
                .frame(maxWidth: .infinity)
            ColorCard(picker: picker)
                .frame(width: 92)
            MirrorCard(mirror: mirror)
                .frame(width: 92)
            AwakeCard(awake: awake)
                .frame(width: 80)
        }
    }
}

/// Keeps the Mac awake, like caffeinate.
private struct AwakeCard: View {
    let awake: KeepAwake

    var body: some View {
        Button { awake.toggle() } label: {
            VStack(spacing: 8) {
                Image(systemName: awake.isOn ? "cup.and.saucer.fill" : "cup.and.saucer")
                    .font(.system(size: 20, weight: .medium))
                    .foregroundStyle(awake.isOn ? Theme.accent : Theme.secondaryText)
                    .contentTransition(.symbolEffect(.replace))
                    .symbolEffect(.bounce, value: awake.isOn)
                Text(awake.isOn ? "Awake" : "Keep awake", bundle: .module)
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(.white)
                    .multilineTextAlignment(.center)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(
                RoundedRectangle(cornerRadius: Theme.cardRadius, style: .continuous)
                    .fill(awake.isOn ? Theme.accent.opacity(0.14) : Theme.fill)
                    .strokeBorder(awake.isOn ? Theme.accent.opacity(0.4) : .clear, lineWidth: 1)
            )
            .contentShape(Rectangle())
        }
        .buttonStyle(PressableStyle())
        .animation(.spring(duration: 0.3, bounce: 0.3), value: awake.isOn)
    }
}

private struct Card<Content: View>: View {
    @ViewBuilder let content: Content

    var body: some View {
        content
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(RoundedRectangle(cornerRadius: Theme.cardRadius, style: .continuous).fill(Theme.fill))
    }
}

private struct TimerCard: View {
    let timer: TimerModel

    var body: some View {
        Card {
            if let countdown = timer.countdown {
                TimelineView(.periodic(from: .now, by: 1)) { context in
                    HStack(spacing: 14) {
                        ZStack {
                            Circle().stroke(RGBA.orange.color.opacity(0.2), lineWidth: 5)
                            Circle()
                                .trim(from: 0, to: countdown.fraction(at: context.date))
                                .stroke(RGBA.orange.color, style: StrokeStyle(lineWidth: 5, lineCap: .round))
                                .rotationEffect(.degrees(-90))
                                .animation(.linear(duration: 1), value: countdown.fraction(at: context.date))
                        }
                        .frame(width: 50, height: 50)
                        VStack(alignment: .leading, spacing: 6) {
                            Text(Countdown.format(countdown.remaining(at: context.date)))
                                .font(.system(size: 26, weight: .semibold, design: .rounded).monospacedDigit())
                                .foregroundStyle(.white)
                                .contentTransition(.numericText(countsDown: true))
                            HStack(spacing: 8) {
                                SmallButton(symbol: countdown.isPaused ? "play.fill" : "pause.fill") { timer.togglePause() }
                                SmallButton(symbol: "xmark") { timer.cancel() }
                            }
                        }
                    }
                }
            } else {
                VStack(alignment: .leading, spacing: 6) {
                    Label { Text("Timer", bundle: .module) } icon: { Image(systemName: "timer") }
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(Theme.secondaryText)
                    LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 6), count: 2), spacing: 5) {
                        ForEach(TimerModel.presets, id: \.self) { minutes in
                            Button {
                                timer.start(minutes: minutes)
                            } label: {
                                Text("\(minutes) min", bundle: .module)
                                    .font(.system(size: 11.5, weight: .semibold).monospacedDigit())
                                    .foregroundStyle(.white)
                                    .frame(maxWidth: .infinity)
                                    .frame(height: 22)
                                    .background(Capsule().fill(Theme.raisedFill))
                            }
                            .buttonStyle(PressableStyle())
                        }
                    }
                }
                .padding(10)
            }
        }
    }
}

private struct SmallButton: View {
    let symbol: String
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.system(size: 10.5, weight: .bold))
                .foregroundStyle(.white)
                .contentTransition(.symbolEffect(.replace))
                .frame(width: 30, height: 22)
                .background(Capsule().fill(Theme.raisedFill))
        }
        .buttonStyle(PressableStyle())
    }
}

private struct ColorCard: View {
    let picker: ColorPickerModel

    var body: some View {
        Card {
            VStack(spacing: 8) {
                Button { picker.pick() } label: {
                    ZStack {
                        Circle().fill(picker.colors.first.map(Color.init(nsColor:)) ?? Theme.raisedFill)
                        Image(systemName: "eyedropper.halffull")
                            .font(.system(size: 15, weight: .semibold))
                            .foregroundStyle(.white)
                            .shadow(color: .black.opacity(0.4), radius: 2)
                    }
                    .frame(width: 40, height: 40)
                }
                .buttonStyle(PressableStyle())
                if let color = picker.colors.first {
                    Text(ColorPickerModel.hex(of: color))
                        .font(.system(size: 11, weight: .semibold, design: .monospaced))
                        .foregroundStyle(picker.copied == color ? Theme.accent : .white.opacity(0.85))
                } else {
                    Text("Pick a colour", bundle: .module)
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(Theme.secondaryText)
                }
                HStack(spacing: 4) {
                    ForEach(Array(picker.colors.dropFirst().enumerated()), id: \.offset) { _, color in
                        Button { picker.copy(color) } label: {
                            Circle().fill(Color(nsColor: color)).frame(width: 12, height: 12)
                        }
                        .buttonStyle(PressableStyle())
                    }
                }
                .frame(height: 12)
            }
        }
    }
}

private struct MirrorCard: View {
    let mirror: MirrorModel

    var body: some View {
        Card {
            if mirror.isRunning {
                CameraPreview(session: mirror.session)
                    .clipShape(RoundedRectangle(cornerRadius: Theme.cardRadius, style: .continuous))
                    .onTapGesture { mirror.stop() }
                    .onDisappear { mirror.stop() }
            } else {
                Button { mirror.start() } label: {
                    VStack(spacing: 7) {
                        Image(systemName: mirror.denied ? "video.slash.fill" : "person.crop.square.fill")
                            .font(.system(size: 20, weight: .medium))
                            .foregroundStyle(Theme.secondaryText)
                        Text(mirror.denied ? "Camera access is off" : "Mirror", bundle: .module)
                            .font(.system(size: 11, weight: .semibold))
                            .foregroundStyle(.white)
                            .multilineTextAlignment(.center)
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .contentShape(Rectangle())
                }
                .buttonStyle(PressableStyle())
            }
        }
    }
}

/// A mirrored camera preview, drawn by AVFoundation's own layer.
private struct CameraPreview: NSViewRepresentable {
    let session: AVCaptureSession

    func makeNSView(context: Context) -> NSView {
        let view = NSView()
        view.wantsLayer = true
        let preview = AVCaptureVideoPreviewLayer(session: session)
        preview.videoGravity = .resizeAspectFill
        preview.connection?.automaticallyAdjustsVideoMirroring = false
        preview.connection?.isVideoMirrored = true
        preview.autoresizingMask = [.layerWidthSizable, .layerHeightSizable]
        view.layer = preview
        return view
    }

    func updateNSView(_ nsView: NSView, context: Context) {}
}

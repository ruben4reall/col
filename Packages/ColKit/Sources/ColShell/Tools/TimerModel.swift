import AppKit
import ColCore
import Observation

/// One countdown at a time, shown in the notch while it runs. Nothing ticks: a single task wakes up when it rings.
@MainActor
@Observable
final class TimerModel {
    private(set) var countdown: Countdown?
    @ObservationIgnored var post: ((Activity) -> Void)?
    @ObservationIgnored var remove: ((String) -> Void)?
    @ObservationIgnored private var alarm: Task<Void, Never>?

    static let presets: [Int] = [1, 3, 5, 10, 25, 45]
    private let tint = RGBA.orange

    func start(minutes: Int) {
        countdown = Countdown(total: TimeInterval(minutes * 60), starting: Date())
        schedule()
    }

    func togglePause() {
        guard var countdown else { return }
        let now = Date()
        if countdown.isPaused { countdown.resume(at: now) } else { countdown.pause(at: now) }
        self.countdown = countdown
        schedule()
    }

    func cancel() {
        alarm?.cancel()
        countdown = nil
        remove?("timer")
    }

    private func schedule() {
        alarm?.cancel()
        guard let countdown else { return }
        let now = Date()
        if countdown.isPaused {
            post?(Activity(
                id: "timer", priority: .standard,
                compact: CompactPresentation(leading: .symbol("pause.fill", tint: tint), trailing: .ring(progress: countdown.fraction(at: now), tint: tint)),
                updated: now
            ))
            return
        }
        guard let ends = countdown.ends else { return }
        post?(Activity(
            id: "timer", priority: .standard,
            compact: CompactPresentation(leading: .symbol("timer", tint: tint), trailing: .countdown(ends: ends, total: countdown.total, tint: tint)),
            updated: now
        ))
        alarm = Task { @MainActor [weak self] in
            try? await Task.sleep(for: .seconds(max(ends.timeIntervalSinceNow, 0)))
            guard !Task.isCancelled else { return }
            self?.ring()
        }
    }

    private func ring() {
        countdown = nil
        NSSound(named: "Glass")?.play()
        NSHapticFeedbackManager.defaultPerformer.perform(.levelChange, performanceTime: .now)
        post?(Activity(
            id: "timer", priority: .alert,
            compact: CompactPresentation(
                leading: .symbol("bell.fill", tint: tint),
                trailing: .text(String(localized: "Time’s up", bundle: .module), tint: tint)
            ),
            expires: Date().addingTimeInterval(8),
            updated: Date()
        ))
    }
}

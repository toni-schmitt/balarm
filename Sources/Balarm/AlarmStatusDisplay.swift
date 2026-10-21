import AppKit
import BalarmCore
import Observation

/// Keeps the menu bar item in step with the alarm, updating it when the second shown changes
/// instead of polling.
@MainActor
final class AlarmStatusDisplay {
    private let statusItem: AlarmStatusItem
    private var followTask: Task<Void, Never>?
    private var tickTask: Task<Void, Never>?
    private var shownCountdown: Countdown?

    /// With the default tolerance, one-second sleeps ended 40 to 65 ms late when measured,
    /// enough for the seconds to tick unevenly.
    private static let tickTolerance: Duration = .milliseconds(5)

    init(controller: AlarmController) {
        statusItem = AlarmStatusItem(controller: controller)
        followTask = Task { [weak self] in
            for await countdown in Observations({ controller.countdown }) {
                guard let self else { return }
                follow(countdown)
            }
        }
    }

    private func follow(_ countdown: Countdown?) {
        // Every change to the alarm is observed, typing included.
        guard countdown != shownCountdown else { return }
        shownCountdown = countdown
        tickTask?.cancel()
        let now = ContinuousClock.now
        statusItem.show(countdown, at: now)
        guard let countdown else { return }
        tickTask = Task { [weak self] in
            var now = now
            while let next = countdown.nextDisplayChange(after: now) {
                try? await Task.sleep(until: next, tolerance: Self.tickTolerance, clock: .continuous)
                guard !Task.isCancelled else { return }
                guard let self else { return }
                now = .now
                statusItem.show(countdown, at: now)
            }
        }
    }
}

/// The single alarm: the duration being typed, the countdown, and the ringing.
///
/// Transitions only change state and return the side effects to perform, in order, so
/// every transition can be checked without AppKit. Transitions that depend on time take
/// `now` explicitly, as `Countdown` does.
public struct Alarm: Equatable, Sendable {
    /// A side effect for `AlarmController` to perform.
    public enum Effect: Equatable, Sendable {
        case beep
        case startRinger
        case stopRinger
        /// Shows the "time's up" alert for an alarm of `seconds`.
        case postAlert(seconds: Int)
        case withdrawAlert
        /// Replaces any pending fire with one at `deadline`.
        case scheduleFire(at: ContinuousClock.Instant)
        case cancelFire
        case keepAwake(Bool)
        case saveLastDuration(seconds: Int)
    }

    /// How the user answered the "time's up" alert.
    public enum AlertAction: Equatable, Sendable {
        case stop
        case repeatAlarm
    }

    public private(set) var entry: DurationEntry
    /// `nil` while a duration is being typed.
    public private(set) var countdown: Countdown?
    /// R asks before throwing away a countdown in progress; ringing repeats without asking.
    public var isConfirmingRestart = false

    public init(lastDurationSeconds: Int) {
        entry = DurationEntry(prefilling: lastDurationSeconds) ?? DurationEntry()
    }

    /// Returns `nil` when the alarm leaves the key alone, so it keeps its system behavior
    /// (while the restart prompt is open, that means the prompt answers it). A used key
    /// returns its effects, which may be none.
    public mutating func handle(_ key: AlarmKey, at now: ContinuousClock.Instant) -> [Effect]? {
        // The restart prompt owns the keyboard while open, so Return and Esc answer it.
        guard !isConfirmingRestart else { return nil }
        guard let countdown else { return handleEntry(key, at: now) }

        if countdown.isRinging {
            switch key {
            case .enter, .escape: return stop()
            case .repeatAlarm: return repeatAlarm(at: now)
            default: return nil
            }
        }

        switch key {
        case .space: return togglePause(at: now)
        case .escape: return stop()
        case .repeatAlarm: isConfirmingRestart = true
        default: return nil
        }
        return []
    }

    public mutating func startFromEntry(at now: ContinuousClock.Instant) -> [Effect] {
        guard entry.totalSeconds > 0 else { return [.beep] }
        return start(seconds: entry.totalSeconds, at: now)
    }

    public mutating func togglePause(at now: ContinuousClock.Instant) -> [Effect] {
        guard var countdown else { return [] }
        guard !countdown.isRinging else { return [] }

        // Due but not rung yet, e.g. right after waking: ring rather than pause at 0:00.
        guard !countdown.isDue(at: now) else { return ringIfDue(at: now) }

        if countdown.isPaused {
            countdown.resume(at: now)
        } else {
            countdown.pause(at: now)
        }
        self.countdown = countdown

        return [.keepAwake(countdown.isRunning), scheduleFire()]
    }

    /// Ends the alarm, whether it is still counting down or already ringing,
    /// and offers its duration for the next start.
    public mutating func stop() -> [Effect] {
        guard let countdown else { return [] }

        isConfirmingRestart = false
        entry = DurationEntry(prefilling: countdown.totalSeconds) ?? DurationEntry()
        self.countdown = nil
        return [.cancelFire, .stopRinger, .withdrawAlert, .keepAwake(false)]
    }

    public mutating func repeatAlarm(at now: ContinuousClock.Instant) -> [Effect] {
        guard let countdown else { return [] }
        return start(seconds: countdown.totalSeconds, at: now)
    }

    /// Notification actions can arrive for an alert that is already stale,
    /// so they only act while something is actually ringing.
    public mutating func handleAlertAction(_ action: AlertAction, at now: ContinuousClock.Instant) -> [Effect] {
        guard countdown?.isRinging == true else { return [] }

        switch action {
        case .stop: return stop()
        case .repeatAlarm: return repeatAlarm(at: now)
        }
    }

    public mutating func ringIfDue(at now: ContinuousClock.Instant) -> [Effect] {
        guard var countdown else { return [] }
        guard countdown.isRunning else { return [] }
        guard countdown.isDue(at: now) else { return [scheduleFire()] }

        countdown.ring()
        self.countdown = countdown
        // Once it rings, R repeats directly, so a pending restart question no longer applies.
        isConfirmingRestart = false
        return [.startRinger, .postAlert(seconds: countdown.totalSeconds)]
    }

    private mutating func handleEntry(_ key: AlarmKey, at now: ContinuousClock.Instant) -> [Effect]? {
        switch key {
        case .digit(let digit): entry.append(digit)
        case .delete: entry.deleteLast()
        case .escape: entry.clear()
        case .enter: return startFromEntry(at: now)
        case .space, .repeatAlarm: return nil
        }
        return []
    }

    private mutating func start(seconds: Int, at now: ContinuousClock.Instant) -> [Effect] {
        isConfirmingRestart = false
        countdown = Countdown(total: .seconds(seconds), startingAt: now)
        return [
            .stopRinger, .withdrawAlert, .saveLastDuration(seconds: seconds), .keepAwake(true),
            scheduleFire(),
        ]
    }

    /// Fires at the deadline while running; paused or ringing, there is nothing to fire.
    private func scheduleFire() -> Effect {
        guard let deadline = countdown?.deadline else { return .cancelFire }
        return .scheduleFire(at: deadline)
    }
}

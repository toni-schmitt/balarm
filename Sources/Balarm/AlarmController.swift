import AppKit
import BalarmCore
import Observation

/// Runs the single alarm: feeds input to `Alarm` and performs the effects it returns,
/// from ringing and the alert to keeping the Mac awake and firing at the deadline.
@MainActor
@Observable
final class AlarmController {
    private var alarm: Alarm

    var entry: DurationEntry { alarm.entry }
    var countdown: Countdown? { alarm.countdown }
    var isConfirmingRestart: Bool {
        get { alarm.isConfirmingRestart }
        set { alarm.isConfirmingRestart = newValue }
    }

    @ObservationIgnored private let ringer = Ringer()
    @ObservationIgnored private let notifier = AlarmNotifier()
    @ObservationIgnored private var fireTask: Task<Void, Never>?
    @ObservationIgnored private var keepAwakeActivity: (any NSObjectProtocol)?
    @ObservationIgnored private var wakeObserver: (any NSObjectProtocol)?

    private static let lastDurationKey = "lastDurationSeconds"

    init() {
        alarm = Alarm(lastDurationSeconds: UserDefaults.standard.integer(forKey: Self.lastDurationKey))

        notifier.onStop = { [weak self] in
            guard let self else { return }
            perform(alarm.handleAlertAction(.stop, at: .now))
        }
        notifier.onRepeat = { [weak self] in
            guard let self else { return }
            perform(alarm.handleAlertAction(.repeatAlarm, at: .now))
        }
        notifier.activate()

        // Idle sleep is prevented while running, but closing the lid still sleeps the Mac.
        // The fire task may then resume late, so wake-up checks the deadline directly.
        wakeObserver = NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.didWakeNotification, object: nil, queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated { self?.ringIfDue() }
        }
    }

    /// Returns whether the key was used, so unused keys keep their system behavior.
    func handle(_ key: AlarmKey) -> Bool {
        guard let effects = alarm.handle(key, at: .now) else { return false }
        perform(effects)
        return true
    }

    func startFromEntry() {
        perform(alarm.startFromEntry(at: .now))
    }

    func togglePause() {
        perform(alarm.togglePause(at: .now))
    }

    func stop() {
        perform(alarm.stop())
    }

    func repeatAlarm() {
        perform(alarm.repeatAlarm(at: .now))
    }

    private func ringIfDue() {
        perform(alarm.ringIfDue(at: .now))
    }

    private func perform(_ effects: [Alarm.Effect]) {
        for effect in effects {
            switch effect {
            case .beep: NSSound.beep()
            case .startRinger: ringer.start()
            case .stopRinger: ringer.stop()
            case .postAlert(let seconds): notifier.post(body: DurationText.words(seconds: seconds))
            case .withdrawAlert: notifier.withdraw()
            case .scheduleFire(let deadline): scheduleFire(at: deadline)
            case .cancelFire: fireTask?.cancel()
            case .keepAwake(let isOn): setKeepAwake(isOn)
            case .saveLastDuration(let seconds): UserDefaults.standard.set(seconds, forKey: Self.lastDurationKey)
            }
        }
    }

    private func scheduleFire(at deadline: ContinuousClock.Instant) {
        fireTask?.cancel()
        fireTask = Task { [weak self] in
            try? await Task.sleep(until: deadline, clock: .continuous)
            guard !Task.isCancelled else { return }
            self?.ringIfDue()
        }
    }

    /// Keeps the Mac from idle-sleeping and the app out of App Nap,
    /// both of which would delay the alarm or cut the ringing short.
    /// `.userInitiated` covers both; it includes `.idleSystemSleepDisabled`.
    private func setKeepAwake(_ isOn: Bool) {
        if isOn, keepAwakeActivity == nil {
            keepAwakeActivity = ProcessInfo.processInfo.beginActivity(
                options: .userInitiated,
                reason: "An alarm is running"
            )
        } else if !isOn, let keepAwakeActivity {
            ProcessInfo.processInfo.endActivity(keepAwakeActivity)
            self.keepAwakeActivity = nil
        }
    }
}

/// The single alarm: the duration being typed, the countdown, and the ringing.
///
/// Transitions only change state and return the side effects to perform, in order, so
/// every transition can be checked without AppKit. Transitions that depend on time take
/// `now` explicitly, as `Countdown` does.
struct Alarm: Equatable, Sendable {
    /// A side effect for `AlarmController` to perform.
    enum Effect: Equatable, Sendable {
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
    enum AlertAction: Equatable, Sendable {
        case stop
        case repeatAlarm
    }

    private(set) var entry: DurationEntry
    /// `nil` while a duration is being typed.
    private(set) var countdown: Countdown?
    /// R asks before throwing away a countdown in progress; ringing repeats without asking.
    var isConfirmingRestart = false

    init(lastDurationSeconds: Int) {
        entry = DurationEntry(prefilling: lastDurationSeconds) ?? DurationEntry()
    }

    /// Returns `nil` when the alarm leaves the key alone, so it keeps its system behavior
    /// (while the restart prompt is open, that means the prompt answers it). A used key
    /// returns its effects, which may be none.
    mutating func handle(_ key: AlarmKey, at now: ContinuousClock.Instant) -> [Effect]? {
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

    mutating func startFromEntry(at now: ContinuousClock.Instant) -> [Effect] {
        guard entry.totalSeconds > 0 else { return [.beep] }
        return start(seconds: entry.totalSeconds, at: now)
    }

    mutating func togglePause(at now: ContinuousClock.Instant) -> [Effect] {
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
    mutating func stop() -> [Effect] {
        guard let countdown else { return [] }

        isConfirmingRestart = false
        entry = DurationEntry(prefilling: countdown.totalSeconds) ?? DurationEntry()
        self.countdown = nil
        return [.cancelFire, .stopRinger, .withdrawAlert, .keepAwake(false)]
    }

    mutating func repeatAlarm(at now: ContinuousClock.Instant) -> [Effect] {
        guard let countdown else { return [] }
        return start(seconds: countdown.totalSeconds, at: now)
    }

    /// Notification actions can arrive for an alert that is already stale,
    /// so they only act while something is actually ringing.
    mutating func handleAlertAction(_ action: AlertAction, at now: ContinuousClock.Instant) -> [Effect] {
        guard countdown?.isRinging == true else { return [] }

        switch action {
        case .stop: return stop()
        case .repeatAlarm: return repeatAlarm(at: now)
        }
    }

    mutating func ringIfDue(at now: ContinuousClock.Instant) -> [Effect] {
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

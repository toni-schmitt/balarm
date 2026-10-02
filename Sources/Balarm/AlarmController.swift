import AppKit
import BalarmCore
import Observation

/// Owns the single alarm: the duration being typed, the countdown, and the ringing.
@MainActor
@Observable
final class AlarmController {
    private(set) var entry: DurationEntry
    /// `nil` while a duration is being typed.
    private(set) var countdown: Countdown?
    /// R asks before throwing away a countdown in progress; ringing repeats without asking.
    var isConfirmingRestart = false

    @ObservationIgnored private let ringer = Ringer()
    @ObservationIgnored private let notifier = AlarmNotifier()
    @ObservationIgnored private var fireTask: Task<Void, Never>?
    @ObservationIgnored private var keepAwakeActivity: (any NSObjectProtocol)?
    @ObservationIgnored private var wakeObserver: (any NSObjectProtocol)?

    private static let lastDurationKey = "lastDurationSeconds"

    init() {
        let lastDuration = UserDefaults.standard.integer(forKey: Self.lastDurationKey)
        entry = DurationEntry(prefilling: lastDuration) ?? DurationEntry()

        // Notification actions can arrive for an alert that is already stale,
        // so they only act while something is actually ringing.
        notifier.onStop = { [weak self] in
            guard let self else { return }
            guard countdown?.isRinging == true else { return }
            stop()
        }
        notifier.onRepeat = { [weak self] in
            guard let self else { return }
            guard countdown?.isRinging == true else { return }
            repeatAlarm()
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
        // The restart prompt owns the keyboard while open, so Return and Esc answer it.
        guard !isConfirmingRestart else { return false }
        guard let countdown else { return handleEntry(key) }

        if countdown.isRinging {
            switch key {
            case .enter, .escape: stop()
            case .repeatAlarm: repeatAlarm()
            default: return false
            }
            return true
        }

        switch key {
        case .space: togglePause()
        case .escape: stop()
        case .repeatAlarm: isConfirmingRestart = true
        default: return false
        }
        return true
    }

    func startFromEntry() {
        guard entry.totalSeconds > 0 else {
            NSSound.beep()
            return
        }
        start(seconds: entry.totalSeconds)
    }

    func togglePause() {
        guard var countdown else { return }
        guard !countdown.isRinging else { return }

        let now = ContinuousClock.now
        // Due but not rung yet, e.g. right after waking: ring rather than pause at 0:00.
        guard !countdown.isDue(at: now) else {
            ringIfDue()
            return
        }

        if countdown.isPaused {
            countdown.resume(at: now)
        } else {
            countdown.pause(at: now)
        }
        self.countdown = countdown

        setKeepAwake(countdown.isRunning)
        scheduleFire()
    }

    /// Ends the alarm, whether it is still counting down or already ringing,
    /// and offers its duration for the next start.
    func stop() {
        guard let countdown else { return }

        fireTask?.cancel()
        ringer.stop()
        notifier.withdraw()
        setKeepAwake(false)
        isConfirmingRestart = false
        entry = DurationEntry(prefilling: countdown.totalSeconds) ?? DurationEntry()
        self.countdown = nil
    }

    func repeatAlarm() {
        guard let countdown else { return }
        start(seconds: countdown.totalSeconds)
    }

    private func handleEntry(_ key: AlarmKey) -> Bool {
        switch key {
        case .digit(let digit): entry.append(digit)
        case .delete: entry.deleteLast()
        case .escape: entry.clear()
        case .enter: startFromEntry()
        case .space, .repeatAlarm: return false
        }
        return true
    }

    private func start(seconds: Int) {
        ringer.stop()
        notifier.withdraw()
        isConfirmingRestart = false

        countdown = Countdown(total: .seconds(seconds), startingAt: .now)
        UserDefaults.standard.set(seconds, forKey: Self.lastDurationKey)
        setKeepAwake(true)
        scheduleFire()
    }

    private func scheduleFire() {
        fireTask?.cancel()
        guard let deadline = countdown?.deadline else { return }

        fireTask = Task { [weak self] in
            try? await Task.sleep(until: deadline, clock: .continuous)
            guard !Task.isCancelled else { return }
            self?.ringIfDue()
        }
    }

    private func ringIfDue() {
        guard var countdown else { return }
        guard countdown.isRunning else { return }
        guard countdown.isDue(at: .now) else {
            scheduleFire()
            return
        }

        countdown.ring()
        self.countdown = countdown
        // Once it rings, R repeats directly, so a pending restart question no longer applies.
        isConfirmingRestart = false
        ringer.start()
        notifier.post(body: DurationText.words(seconds: countdown.totalSeconds))
    }

    /// Keeps the Mac from idle-sleeping and the app out of App Nap,
    /// both of which would delay the alarm or cut the ringing short.
    private func setKeepAwake(_ isOn: Bool) {
        if isOn, keepAwakeActivity == nil {
            keepAwakeActivity = ProcessInfo.processInfo.beginActivity(
                options: [.userInitiated, .idleSystemSleepDisabled],
                reason: "An alarm is running"
            )
        } else if !isOn, let keepAwakeActivity {
            ProcessInfo.processInfo.endActivity(keepAwakeActivity)
            self.keepAwakeActivity = nil
        }
    }
}

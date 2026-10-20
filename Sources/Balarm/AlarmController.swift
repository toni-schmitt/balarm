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
        // `requestRestart()` opens the prompt; the alert's binding writes here only to close it.
        set {
            guard !newValue else { return }
            alarm.dismissRestartPrompt()
        }
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

    func setEntry(_ entry: DurationEntry) {
        alarm.setEntry(entry)
    }

    func requestRestart() {
        alarm.requestRestart()
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

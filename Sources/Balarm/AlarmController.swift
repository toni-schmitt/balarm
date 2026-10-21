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
    private(set) var alertStyle = AlarmAlertStyle.notAsked
    var isConfirmingRestart: Bool {
        get { alarm.isConfirmingRestart }
        // `requestRestart()` opens the prompt; the alert's binding writes here only to close it.
        set {
            guard !newValue else { return }
            alarm.dismissRestartPrompt()
        }
    }

    /// Opens the alarm window or brings it forward, also out of the Dock. The window provides
    /// it once it has appeared, since the action comes from its SwiftUI environment.
    @ObservationIgnored var openWindow: (() -> Void)?
    /// Minimized or hidden, the window stays open.
    private(set) var isWindowOpen = false
    /// Seen on screen or, minimized, in its Dock tile; hidden, on another Space or covered by
    /// other windows, the open window is not.
    private(set) var isWindowVisible = false

    @ObservationIgnored private let ringer = Ringer()
    @ObservationIgnored private let notifier = AlarmNotifier()
    @ObservationIgnored private var fireTask: Task<Void, Never>?
    @ObservationIgnored private var keepAwakeActivity: (any NSObjectProtocol)?
    @ObservationIgnored private var wakeObserver: (any NSObjectProtocol)?
    @ObservationIgnored private var activationObserver: (any NSObjectProtocol)?
    @ObservationIgnored private var alertStyleFollowTask: Task<Void, Never>?
    /// Reads of the style overlap; only one started after the last applied may replace it.
    @ObservationIgnored private var lastStartedAlertStyleRead = 0
    @ObservationIgnored private var lastAppliedAlertStyleRead = 0

    /// System Settings does not tell Balarm when its alert style changes there, and Balarm
    /// stays in the background meanwhile, so after opening it the style is read every second
    /// for this many seconds.
    private static let alertStyleFollowSeconds = 120

    private static let lastDurationKey = "lastDurationSeconds"

    /// With the default tolerance, a sleep may end late by a share of its length: a 60 s sleep
    /// ended 2.9 s late when measured, so a long alarm would ring well after showing 0:00.
    private static let fireTolerance: Duration = .milliseconds(5)

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
        notifier.onOpen = { [weak self] in self?.showWindow() }
        notifier.onAuthorizationResolved = { [weak self] in self?.refreshAlertStyle() }
        notifier.activate()
        refreshAlertStyle()

        // The style can only be changed in System Settings, so it is read again on return.
        activationObserver = NotificationCenter.default.addObserver(
            forName: NSApplication.didBecomeActiveNotification, object: nil, queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated { self?.refreshAlertStyle() }
        }

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

    /// The prompt shows in the window, so that comes forward too; asked while the window is
    /// closed, minimized or hidden, the prompt appears once it is back.
    func requestRestartInWindow() {
        showWindow()
        requestRestart()
    }

    func showWindow() {
        NSApp.activate()
        openWindow?()
    }

    func windowDidOpen() {
        isWindowOpen = true
    }

    func windowDidChangeVisibility(_ isVisible: Bool) {
        isWindowVisible = isVisible
        // A visible window is open, even if its opening went unreported.
        guard isVisible else { return }
        isWindowOpen = true
    }

    func windowDidClose() {
        isWindowOpen = false
        isWindowVisible = false
        perform(alarm.handleWindowClose())
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

    /// Called when the user opens Notification settings to change the alert style.
    func followAlertStyleChanges() {
        alertStyleFollowTask?.cancel()
        alertStyleFollowTask = Task { [weak self] in
            for _ in 0..<Self.alertStyleFollowSeconds {
                try? await Task.sleep(for: .seconds(1))
                guard !Task.isCancelled else { return }
                guard let self else { return }
                await readAlertStyle()
                guard alertStyle != .persistent else { return }
            }
        }
    }

    private func refreshAlertStyle() {
        Task { [weak self] in await self?.readAlertStyle() }
    }

    private func readAlertStyle() async {
        lastStartedAlertStyleRead += 1
        let read = lastStartedAlertStyleRead
        let style = await notifier.alertStyle()
        guard read > lastAppliedAlertStyleRead else { return }
        lastAppliedAlertStyleRead = read
        alertStyle = style
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
            try? await Task.sleep(until: deadline, tolerance: Self.fireTolerance, clock: .continuous)
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

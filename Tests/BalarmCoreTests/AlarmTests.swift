import Testing
@testable import BalarmCore

@Suite struct AlarmTests {
    private let start = ContinuousClock.now

    private func typing(_ digits: Int...) -> Alarm {
        var alarm = Alarm(lastDurationSeconds: 0)
        for digit in digits { _ = alarm.handle(.digit(digit), at: start) }
        return alarm
    }

    private func running(seconds: Int) -> Alarm {
        var alarm = Alarm(lastDurationSeconds: seconds)
        _ = alarm.startFromEntry(at: start)
        return alarm
    }

    private func paused(seconds: Int, after elapsed: Duration) -> Alarm {
        var alarm = running(seconds: seconds)
        _ = alarm.togglePause(at: start + elapsed)
        return alarm
    }

    private func ringing(seconds: Int) -> Alarm {
        var alarm = running(seconds: seconds)
        _ = alarm.ringIfDue(at: start + .seconds(seconds))
        return alarm
    }

    private func startEffects(seconds: Int, at now: ContinuousClock.Instant) -> [Alarm.Effect] {
        [
            .stopRinger, .withdrawAlert, .saveLastDuration(seconds: seconds), .keepAwake(isOn: true),
            .scheduleFire(at: now + .seconds(seconds)),
        ]
    }

    private let stopEffects: [Alarm.Effect] = [.cancelFire, .stopRinger, .withdrawAlert, .keepAwake(isOn: false)]

    // MARK: - Typing

    @Test func startsWithTheLastDuration() {
        let alarm = Alarm(lastDurationSeconds: 25 * 60)
        #expect(alarm.entry.isPrefilled)
        #expect(alarm.entry.totalSeconds == 25 * 60)
        #expect(alarm.countdown == nil)
        #expect(!alarm.isConfirmingRestart)
    }

    @Test(arguments: [0, -1, 99 * 3600 + 99 * 60 + 100])
    func startsEmptyWithoutAUsableLastDuration(seconds: Int) {
        let alarm = Alarm(lastDurationSeconds: seconds)
        #expect(alarm.entry.isEmpty)
    }

    @Test func editingKeysChangeTheEntryWithoutEffects() {
        var alarm = Alarm(lastDurationSeconds: 0)
        #expect(alarm.handle(.digit(2), at: start) == [])
        #expect(alarm.handle(.digit(5), at: start) == [])
        #expect(alarm.entry.digits == [2, 5])
        #expect(alarm.handle(.delete, at: start) == [])
        #expect(alarm.entry.digits == [2])
        #expect(alarm.handle(.escape, at: start) == [])
        #expect(alarm.entry.isEmpty)
    }

    @Test(arguments: [AlarmKey.space, .repeatAlarm])
    func typingLeavesOtherKeysAlone(key: AlarmKey) {
        var alarm = typing(5)
        #expect(alarm.handle(key, at: start) == nil)
        #expect(alarm == typing(5))
    }

    @Test func returnOnAnEmptyEntryBeeps() {
        var alarm = Alarm(lastDurationSeconds: 0)
        #expect(alarm.handle(.enter, at: start) == [.beep])
        #expect(alarm.countdown == nil)
    }

    @Test func returnStartsTheTypedDuration() throws {
        var alarm = typing(2, 5, 0, 0)
        #expect(alarm.handle(.enter, at: start) == startEffects(seconds: 25 * 60, at: start))
        let countdown = try #require(alarm.countdown)
        #expect(countdown.isRunning)
        #expect(countdown.total == .seconds(25 * 60))
        #expect(countdown.deadline == start + .seconds(25 * 60))
    }

    @Test func returnStartsTheRememberedDuration() {
        var alarm = Alarm(lastDurationSeconds: 90)
        #expect(alarm.handle(.enter, at: start) == startEffects(seconds: 90, at: start))
    }

    // MARK: - Running and paused

    @Test func spacePausesAndResumes() {
        var alarm = running(seconds: 60)
        #expect(alarm.handle(.space, at: start + .seconds(20)) == [.keepAwake(isOn: false), .cancelFire])
        #expect(alarm.countdown?.isPaused == true)

        #expect(alarm.handle(.space, at: start + .seconds(100)) == [
            .keepAwake(isOn: true), .scheduleFire(at: start + .seconds(140)),
        ])
        #expect(alarm.countdown?.isRunning == true)
    }

    @Test func spaceOnceDueRingsInsteadOfPausing() {
        var alarm = running(seconds: 60)
        #expect(alarm.handle(.space, at: start + .seconds(61)) == [.startRinger, .postAlert(seconds: 60)])
        #expect(alarm.countdown?.isRinging == true)
    }

    @Test func escapeCancelsAndOffersTheDuration() {
        var alarm = running(seconds: 90)
        #expect(alarm.handle(.escape, at: start + .seconds(10)) == stopEffects)
        #expect(alarm.countdown == nil)
        #expect(alarm.entry.isPrefilled)
        #expect(alarm.entry.digits == [1, 3, 0])
    }

    @Test func escapeCancelsAPausedCountdown() {
        var alarm = paused(seconds: 60, after: .seconds(20))
        #expect(alarm.handle(.escape, at: start + .seconds(30)) == stopEffects)
        #expect(alarm.countdown == nil)
    }

    @Test(arguments: [AlarmKey.digit(5), .delete, .enter])
    func runningLeavesOtherKeysAlone(key: AlarmKey) {
        var alarm = running(seconds: 60)
        #expect(alarm.handle(key, at: start + .seconds(10)) == nil)
        #expect(alarm == running(seconds: 60))
    }

    // MARK: - Restart prompt

    @Test func rAsksBeforeRestartingACountdown() {
        var alarm = running(seconds: 60)
        #expect(alarm.handle(.repeatAlarm, at: start + .seconds(10)) == [])
        #expect(alarm.isConfirmingRestart)
        #expect(alarm.countdown?.isRunning == true)
    }

    @Test(arguments: [AlarmKey.enter, .escape, .space, .repeatAlarm, .digit(1), .delete])
    func theRestartPromptGetsEveryKey(key: AlarmKey) {
        var alarm = running(seconds: 60)
        _ = alarm.handle(.repeatAlarm, at: start)
        let before = alarm
        #expect(alarm.handle(key, at: start + .seconds(10)) == nil)
        #expect(alarm == before)
    }

    @Test func restartingStartsOverAndClosesThePrompt() {
        var alarm = running(seconds: 60)
        _ = alarm.handle(.repeatAlarm, at: start)
        let now = start + .seconds(40)
        #expect(alarm.repeatAlarm(at: now) == startEffects(seconds: 60, at: now))
        #expect(!alarm.isConfirmingRestart)
        #expect(alarm.countdown?.deadline == now + .seconds(60))
    }

    @Test func dismissingThePromptKeepsTheCountdownGoing() {
        var alarm = running(seconds: 60)
        _ = alarm.handle(.repeatAlarm, at: start)
        alarm.dismissRestartPrompt()
        #expect(!alarm.isConfirmingRestart)
        #expect(alarm == running(seconds: 60))
        #expect(alarm.handle(.space, at: start + .seconds(10)) != nil)
    }

    @Test func ringingClosesTheRestartPrompt() {
        var alarm = running(seconds: 60)
        _ = alarm.handle(.repeatAlarm, at: start)
        _ = alarm.ringIfDue(at: start + .seconds(60))
        #expect(alarm.countdown?.isRinging == true)
        #expect(!alarm.isConfirmingRestart)
    }

    // MARK: - Firing

    @Test func ringIfDueBeforeTheDeadlineReschedules() {
        var alarm = running(seconds: 60)
        #expect(alarm.ringIfDue(at: start + .seconds(59)) == [.scheduleFire(at: start + .seconds(60))])
        #expect(alarm.countdown?.isRunning == true)
    }

    @Test func ringIfDueAtTheDeadlineRings() {
        var alarm = running(seconds: 60)
        #expect(alarm.ringIfDue(at: start + .seconds(60)) == [.startRinger, .postAlert(seconds: 60)])
        #expect(alarm.countdown?.isRinging == true)
    }

    @Test func ringIfDueRingsOnlyOnce() {
        var alarm = ringing(seconds: 60)
        #expect(alarm.ringIfDue(at: start + .seconds(61)) == [])
    }

    @Test func ringIfDueIgnoresAPausedCountdown() {
        var alarm = paused(seconds: 60, after: .seconds(20))
        #expect(alarm.ringIfDue(at: start + .seconds(500)) == [])
        #expect(alarm.countdown?.isPaused == true)
    }

    @Test func ringIfDueWhileTypingDoesNothing() {
        var alarm = typing(5)
        #expect(alarm.ringIfDue(at: start + .seconds(500)) == [])
    }

    // MARK: - Ringing

    @Test(arguments: [AlarmKey.enter, .escape])
    func returnOrEscapeStopsTheRinging(key: AlarmKey) {
        var alarm = ringing(seconds: 60)
        #expect(alarm.handle(key, at: start + .seconds(70)) == stopEffects)
        #expect(alarm.countdown == nil)
        #expect(alarm.entry.totalSeconds == 60)
    }

    @Test func rRepeatsWithoutAsking() {
        var alarm = ringing(seconds: 60)
        let now = start + .seconds(70)
        #expect(alarm.handle(.repeatAlarm, at: now) == startEffects(seconds: 60, at: now))
        #expect(!alarm.isConfirmingRestart)
        #expect(alarm.countdown?.isRunning == true)
    }

    @Test(arguments: [AlarmKey.space, .digit(5), .delete])
    func ringingLeavesOtherKeysAlone(key: AlarmKey) {
        var alarm = ringing(seconds: 60)
        #expect(alarm.handle(key, at: start + .seconds(70)) == nil)
        #expect(alarm == ringing(seconds: 60))
    }

    @Test func spaceWhileRingingDoesNotPause() {
        var alarm = ringing(seconds: 60)
        #expect(alarm.togglePause(at: start + .seconds(70)) == [])
        #expect(alarm.countdown?.isRinging == true)
    }

    // MARK: - Alert actions

    @Test func alertStopEndsTheRinging() {
        var alarm = ringing(seconds: 60)
        #expect(alarm.handleAlertAction(.stop, at: start + .seconds(70)) == stopEffects)
        #expect(alarm.countdown == nil)
    }

    @Test func alertRepeatStartsOver() {
        var alarm = ringing(seconds: 60)
        let now = start + .seconds(70)
        #expect(alarm.handleAlertAction(.repeatAlarm, at: now) == startEffects(seconds: 60, at: now))
    }

    @Test(arguments: [Alarm.AlertAction.stop, .repeatAlarm])
    func staleAlertActionsDoNothing(action: Alarm.AlertAction) {
        for before in [running(seconds: 60), paused(seconds: 60, after: .seconds(20)), typing(5)] {
            var alarm = before
            #expect(alarm.handleAlertAction(action, at: start + .seconds(30)) == [])
            #expect(alarm == before)
        }
    }

    // MARK: - Without a countdown

    @Test func stopAndRepeatNeedACountdown() {
        var alarm = typing(5)
        #expect(alarm.stop() == [])
        #expect(alarm.repeatAlarm(at: start) == [])
        #expect(alarm.togglePause(at: start) == [])
        #expect(alarm == typing(5))
    }

    // MARK: - Remembering the duration

    @Test func anOverflowingDurationIsOfferedNormalized() {
        var alarm = typing(9, 0)
        _ = alarm.handle(.enter, at: start)
        _ = alarm.stop()
        #expect(alarm.entry.digits == [1, 3, 0])
        #expect(alarm.entry.totalSeconds == 90)
    }

    @Test func theLongestTypeableDurationIsOfferedAgain() {
        var alarm = typing(9, 9, 9, 9, 9, 9)
        #expect(alarm.handle(.enter, at: start) == startEffects(seconds: 362_439, at: start))
        _ = alarm.stop()
        #expect(alarm.entry.isPrefilled)
        #expect(alarm.entry.digits == [9, 9, 9, 9, 9, 9])
    }
}

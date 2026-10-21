import Testing
@testable import BalarmCore

@Suite struct CountdownTests {
    private let start = ContinuousClock.now

    @Test func runsUntilTheDeadline() {
        let countdown = Countdown(total: .seconds(60), startingAt: start)
        #expect(countdown.isRunning)
        #expect(countdown.deadline == start + .seconds(60))
        #expect(countdown.remaining(at: start + .seconds(15)) == .seconds(45))
        #expect(countdown.fractionRemaining(at: start + .seconds(15)) == 0.75)
        #expect(!countdown.isDue(at: start + .seconds(59)))
        #expect(countdown.isDue(at: start + .seconds(60)))
    }

    @Test func remainingNeverGoesNegative() {
        let countdown = Countdown(total: .seconds(10), startingAt: start)
        #expect(countdown.remaining(at: start + .seconds(30)) == .zero)
        #expect(countdown.fractionRemaining(at: start + .seconds(30)) == 0)
    }

    private static let displayCases: [(elapsed: Double, expected: Int)] = [
        (0.0, 60),
        (0.001, 60),
        (0.999, 60),
        (1.0, 59),
        (59.5, 1),
        (60.0, 0),
    ]

    @Test(arguments: displayCases)
    func displayRoundsUp(elapsed: Double, expected: Int) {
        let countdown = Countdown(total: .seconds(60), startingAt: start)
        #expect(countdown.displaySeconds(at: start + .seconds(elapsed)) == expected)
    }

    @Test func pauseFreezesRemainingTime() {
        var countdown = Countdown(total: .seconds(60), startingAt: start)
        countdown.pause(at: start + .seconds(20))
        #expect(countdown.isPaused)
        #expect(countdown.deadline == nil)
        #expect(countdown.remaining(at: start + .seconds(500)) == .seconds(40))
        #expect(!countdown.isDue(at: start + .seconds(500)))
    }

    @Test func resumeMovesTheDeadline() {
        var countdown = Countdown(total: .seconds(60), startingAt: start)
        countdown.pause(at: start + .seconds(20))
        countdown.resume(at: start + .seconds(100))
        #expect(countdown.isRunning)
        #expect(countdown.deadline == start + .seconds(140))
    }

    @Test func pauseAndResumeIgnoreTheWrongPhase() {
        var countdown = Countdown(total: .seconds(60), startingAt: start)
        countdown.resume(at: start + .seconds(10))
        #expect(countdown.deadline == start + .seconds(60))

        countdown.ring()
        countdown.pause(at: start + .seconds(70))
        #expect(countdown.isRinging)
    }

    @Test func ringIgnoresAPausedCountdown() {
        var countdown = Countdown(total: .seconds(60), startingAt: start)
        countdown.pause(at: start + .seconds(20))
        countdown.ring()
        #expect(countdown.isPaused)
        #expect(countdown.remaining(at: start + .seconds(500)) == .seconds(40))
    }

    @Test func pauseKeepsFractionAndRoundsUp() {
        var countdown = Countdown(total: .seconds(60), startingAt: start)
        countdown.pause(at: start + .seconds(14.5))
        #expect(countdown.fractionRemaining(at: start + .seconds(500)) == 45.5 / 60)
        #expect(countdown.displaySeconds(at: start + .seconds(500)) == 46)
    }

    @Test func pauseIsIgnoredOnceDue() {
        var countdown = Countdown(total: .seconds(60), startingAt: start)
        countdown.pause(at: start + .seconds(60))
        #expect(countdown.isRunning)
        #expect(countdown.isDue(at: start + .seconds(60)))

        countdown.pause(at: start + .seconds(75))
        #expect(countdown.isRunning)
    }

    @Test func ringingHasNothingLeft() {
        var countdown = Countdown(total: .seconds(60), startingAt: start)
        countdown.ring()
        #expect(countdown.isRinging)
        #expect(countdown.remaining(at: start) == .zero)
        #expect(countdown.deadline == nil)
        #expect(!countdown.isDue(at: start + .seconds(120)))
    }

    private static let nextChangeCases: [(elapsed: Double, expected: Double)] = [
        (0.0, 1.0),
        (0.5, 1.0),
        (1.0, 2.0),
        (58.9, 59.0),
        (59.5, 60.0),
    ]

    @Test(arguments: nextChangeCases)
    func theDisplayNextChangesAtTheNextWholeSecondLeft(elapsed: Double, expected: Double) {
        let countdown = Countdown(total: .seconds(60), startingAt: start)
        #expect(countdown.nextDisplayChange(after: start + .seconds(elapsed)) == start + .seconds(expected))
    }

    /// Over the first seconds and across the hour, every next change is in the future and
    /// is exactly where the display drops by one.
    @Test func theNextDisplayChangeIsWhereTheDisplayDropsByOne() throws {
        let countdown = Countdown(total: .seconds(3700), startingAt: start)
        let samples = Array(stride(from: 0.0, through: 10, by: 0.05)) + Array(stride(from: 95, through: 105, by: 0.05))
        for elapsed in samples {
            let now = start + .seconds(elapsed)
            let shown = countdown.displaySeconds(at: now)
            let next = try #require(countdown.nextDisplayChange(after: now))
            #expect(next > now)
            #expect(countdown.displaySeconds(at: next) == shown - 1)
            #expect(countdown.displaySeconds(at: next - .nanoseconds(1)) == shown)
        }
    }

    @Test func aResumedCountdownChangesAtItsOwnFractions() {
        var countdown = Countdown(total: .seconds(60), startingAt: start)
        countdown.pause(at: start + .milliseconds(10_300))
        countdown.resume(at: start + .seconds(100))
        #expect(countdown.nextDisplayChange(after: start + .seconds(100)) == start + .milliseconds(100_700))
    }

    @Test(arguments: [60.0, 120.0])
    func aDueCountdownHasNoNextDisplayChange(elapsed: Double) {
        let countdown = Countdown(total: .seconds(60), startingAt: start)
        #expect(countdown.nextDisplayChange(after: start + .seconds(elapsed)) == nil)
    }

    @Test func aPausedCountdownHasNoNextDisplayChange() {
        var countdown = Countdown(total: .seconds(60), startingAt: start)
        countdown.pause(at: start + .seconds(10))
        #expect(countdown.nextDisplayChange(after: start + .seconds(20)) == nil)
    }

    @Test func aRingingCountdownHasNoNextDisplayChange() {
        var countdown = Countdown(total: .seconds(60), startingAt: start)
        countdown.ring()
        #expect(countdown.nextDisplayChange(after: start + .seconds(60)) == nil)
    }
}

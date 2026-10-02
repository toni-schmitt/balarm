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
}

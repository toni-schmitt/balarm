import Testing
@testable import BalarmCore

@Suite struct AppLifetimeTests {
    /// Feeds the steps in order and returns each decision.
    private func decisions(_ steps: [(hasAlarm: Bool, isWindowOpen: Bool)]) -> [Bool] {
        var lifetime = AppLifetime()
        return steps.map { lifetime.shouldQuit(hasAlarm: $0.hasAlarm, isWindowOpen: $0.isWindowOpen) }
    }

    @Test func launchingDoesNotQuitBeforeTheWindowOpens() {
        #expect(decisions([(false, false), (false, true)]) == [false, false])
    }

    @Test func closingTheWindowWithoutAnAlarmQuits() {
        #expect(decisions([(false, true), (false, false)]) == [false, true])
    }

    @Test func askingAgainWithoutAWindowOrAnAlarmStillQuits() {
        #expect(decisions([(false, true), (false, false), (false, false)]) == [false, true, true])
    }

    @Test func closingTheWindowKeepsAnAlarm() {
        #expect(decisions([(false, true), (true, true), (true, false)]) == [false, false, false])
    }

    @Test func anAlarmEndingWithTheWindowClosedQuits() {
        #expect(decisions([(true, true), (true, false), (false, false)]) == [false, false, true])
    }

    @Test func anAlarmEndingWithTheWindowOpenDoesNotQuit() {
        #expect(decisions([(true, true), (false, true)]) == [false, false])
    }

    @Test func reopeningTheWindowKeepsBalarmAfterTheAlarmEnds() {
        #expect(decisions([(true, true), (true, false), (true, true), (false, true)]) == [false, false, false, false])
    }
}

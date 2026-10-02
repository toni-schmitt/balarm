import Testing
@testable import BalarmCore

@Suite struct DurationEntryTests {
    private func entry(typing digits: Int...) -> DurationEntry {
        var entry = DurationEntry()
        digits.forEach { entry.append($0) }
        return entry
    }

    @Test func startsEmpty() {
        let entry = DurationEntry()
        #expect(entry.isEmpty)
        #expect(entry.paddedDigits == [0, 0, 0, 0, 0, 0])
        #expect(entry.totalSeconds == 0)
    }

    private static let typingCases: [(digits: [Int], expectedSeconds: Int)] = [
        ([2], 2),
        ([2, 5], 25),
        ([2, 5, 0], 2 * 60 + 50),
        ([2, 5, 0, 0], 25 * 60),
        ([1, 3, 0, 0, 0], 3600 + 30 * 60),
        ([1, 2, 3, 4, 5, 6], 12 * 3600 + 34 * 60 + 56),
    ]

    private static let prefillCases: [(seconds: Int, expectedDigits: [Int])] = [
        (25 * 60, [2, 5, 0, 0]),
        (90, [1, 3, 0]),
        (3600 + 30 * 60, [1, 3, 0, 0, 0]),
        (99 * 3600 + 59 * 60 + 59, [9, 9, 5, 9, 5, 9]),
    ]

    @Test(arguments: typingCases)
    func fillsFromTheRight(digits: [Int], expectedSeconds: Int) {
        var entry = DurationEntry()
        digits.forEach { entry.append($0) }
        #expect(entry.totalSeconds == expectedSeconds)
    }

    @Test func overflowingFieldsCarry() {
        let entry = entry(typing: 9, 0)
        #expect(entry.seconds == 90)
        #expect(entry.totalSeconds == 90)

        let maxed = self.entry(typing: 9, 9, 9, 9, 9, 9)
        #expect(maxed.totalSeconds == 99 * 3600 + 99 * 60 + 99)
    }

    @Test func ignoresLeadingZeros() {
        let entry = entry(typing: 0, 0, 5)
        #expect(entry.digits == [5])
    }

    @Test func keepsZerosAfterTheFirstDigit() {
        let entry = entry(typing: 1, 0, 0)
        #expect(entry.digits == [1, 0, 0])
        #expect(entry.totalSeconds == 60)
    }

    @Test func ignoresDigitsBeyondSix() {
        let entry = entry(typing: 1, 2, 3, 4, 5, 6, 7)
        #expect(entry.digits == [1, 2, 3, 4, 5, 6])
    }

    @Test func deleteRemovesLastDigit() {
        var entry = entry(typing: 2, 5, 0)
        entry.deleteLast()
        #expect(entry.digits == [2, 5])
        entry.deleteLast()
        entry.deleteLast()
        entry.deleteLast()
        #expect(entry.isEmpty)
    }

    @Test(arguments: prefillCases)
    func prefillNormalizes(seconds: Int, expectedDigits: [Int]) throws {
        let entry = try #require(DurationEntry(prefilling: seconds))
        #expect(entry.isPrefilled)
        #expect(entry.digits == expectedDigits)
        #expect(entry.totalSeconds == seconds)
    }

    @Test(arguments: [0, -1, 100 * 3600])
    func prefillRejectsUnrepresentableDurations(seconds: Int) {
        #expect(DurationEntry(prefilling: seconds) == nil)
    }

    @Test func typingReplacesPrefill() throws {
        var entry = try #require(DurationEntry(prefilling: 25 * 60))
        entry.append(5)
        #expect(!entry.isPrefilled)
        #expect(entry.digits == [5])
    }

    @Test func deleteClearsPrefillAtOnce() throws {
        var entry = try #require(DurationEntry(prefilling: 25 * 60))
        entry.deleteLast()
        #expect(entry.isEmpty)
        #expect(!entry.isPrefilled)
    }

    @Test func zeroAfterPrefillClearsIt() throws {
        var entry = try #require(DurationEntry(prefilling: 25 * 60))
        entry.append(0)
        #expect(entry.isEmpty)
        #expect(!entry.isPrefilled)
    }
}

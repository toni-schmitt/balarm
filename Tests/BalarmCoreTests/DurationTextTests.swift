import Foundation
import Testing
@testable import BalarmCore

@Suite struct DurationTextTests {
    private let english = Locale(identifier: "en_US")

    private static let wordCases: [(seconds: Int, expected: String)] = [
        (25 * 60, "25 min"),
        (3600 + 30 * 60, "1 hr, 30 min"),
        (2 * 60 + 50, "2 min, 50 sec"),
        (45, "45 sec"),
    ]

    private static let clockCases: [(seconds: Int, expected: String)] = [
        (0, "0:00"),
        (5, "0:05"),
        (65, "1:05"),
        (25 * 60, "25:00"),
        (3600, "1:00:00"),
        (3600 + 5 * 60 + 3, "1:05:03"),
        (99 * 3600 + 99 * 60 + 99, "100:40:39"),
    ]

    @Test(arguments: wordCases)
    func wordsInEnglish(seconds: Int, expected: String) {
        #expect(DurationText.words(seconds: seconds, locale: english) == expected)
    }

    @Test(arguments: clockCases)
    func clock(seconds: Int, expected: String) {
        #expect(DurationText.clock(seconds: seconds) == expected)
    }
}

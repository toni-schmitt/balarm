/// Keyboard entry for a countdown duration, filled from the right like a microwave:
/// typing `2`, `5`, `0`, `0` reads as `00:25:00`.
///
/// Fields are not validated per position, so `90` reads as `00:00:90` and runs for
/// 1 min 30 s. That keeps every keystroke meaningful without range errors or timeouts.
public struct DurationEntry: Equatable, Sendable {
    /// Six digits fill `hh:mm:ss`.
    public static let maxDigits = 6

    /// Typed digits, most significant first, without leading zeros.
    public private(set) var digits: [Int] = []

    /// A remembered duration is shown; the next digit replaces it instead of extending it.
    public private(set) var isPrefilled = false

    public init() {}

    /// Shows `seconds` as a remembered duration, normalized to `hh:mm:ss`.
    /// Returns `nil` when the duration cannot be shown in six digits (zero or over 99:59:59).
    public init?(prefilling seconds: Int) {
        guard seconds > 0, seconds <= 99 * 3600 + 59 * 60 + 59 else { return nil }
        let normalized = seconds / 3600 * 10_000 + seconds % 3600 / 60 * 100 + seconds % 60
        digits = String(normalized).compactMap(\.wholeNumberValue)
        isPrefilled = true
    }

    public var isEmpty: Bool { digits.isEmpty }

    public mutating func append(_ digit: Int) {
        precondition((0...9).contains(digit), "digit out of range: \(digit)")
        if isPrefilled { clear() }
        // A leading zero would not change the value, so it is not counted as typed.
        if digits.isEmpty && digit == 0 { return }
        guard digits.count < Self.maxDigits else { return }
        digits.append(digit)
    }

    /// Removes the last typed digit; a prefilled duration is removed as a whole.
    public mutating func deleteLast() {
        if isPrefilled {
            clear()
            return
        }
        guard !digits.isEmpty else { return }
        digits.removeLast()
    }

    public mutating func clear() {
        digits = []
        isPrefilled = false
    }

    /// All six positions of `hh:mm:ss`, zero-padded on the left.
    public var paddedDigits: [Int] {
        Array(repeating: 0, count: Self.maxDigits - digits.count) + digits
    }

    public var hours: Int { paddedDigits[0] * 10 + paddedDigits[1] }
    public var minutes: Int { paddedDigits[2] * 10 + paddedDigits[3] }
    public var seconds: Int { paddedDigits[4] * 10 + paddedDigits[5] }

    public var totalSeconds: Int { hours * 3600 + minutes * 60 + seconds }
}

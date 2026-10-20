/// Keyboard entry for a countdown duration, filled from the right like a microwave:
/// typing `2`, `5`, `0`, `0` reads as `00:25:00`.
///
/// Fields are not validated per position, so `90` reads as `00:00:90` and runs for
/// 1 min 30 s. That keeps every keystroke meaningful without range errors or timeouts.
public struct DurationEntry: Hashable, Sendable {
    /// Six digits fill `hh:mm:ss`.
    public static let maxDigits = 6

    /// Typed digits, most significant first, without leading zeros.
    public private(set) var digits: [Int] = []

    /// A remembered duration is shown; the next digit replaces it instead of extending it.
    public private(set) var isPrefilled = false

    public init() {}

    /// The entry that typing each field's two digits in turn gives, so a field above 59
    /// overflows exactly as typed digits do: `minutes: 90` runs for 1 h 30 min. Each field
    /// must be within 0...99, otherwise `nil`; all zeros give an empty entry.
    public init?(hours: Int, minutes: Int, seconds: Int) {
        guard [hours, minutes, seconds].allSatisfy({ (0...99).contains($0) }) else { return nil }
        for field in [hours, minutes, seconds] {
            append(field / 10)
            append(field % 10)
        }
    }

    /// Shows `seconds` as a remembered duration, normalized to `hh:mm:ss`.
    ///
    /// Typing can overflow every field, up to 99:99:99. Beyond 99:59:59 the hours stay at 99
    /// and the minutes, then the seconds, overflow instead, so every typeable duration can be
    /// shown again: 362439 s reads as 99:99:99.
    /// Returns `nil` when the duration cannot be shown in six digits (zero or over 99:99:99).
    public init?(prefilling seconds: Int) {
        guard seconds > 0, seconds <= 99 * 3600 + 99 * 60 + 99 else { return nil }
        let hours = min(99, seconds / 3600)
        let minutes = min(99, (seconds - hours * 3600) / 60)
        let secs = seconds - hours * 3600 - minutes * 60
        digits = String(hours * 10_000 + minutes * 100 + secs).compactMap(\.wholeNumberValue)
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

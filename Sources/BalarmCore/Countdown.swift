/// A single countdown from start until it rings.
///
/// Time is measured on `ContinuousClock`, which keeps advancing while the Mac sleeps,
/// so a countdown that expired during sleep is overdue on wake instead of resuming
/// where it left off. Every query takes `now` explicitly to keep the math testable.
public struct Countdown: Equatable, Sendable {
    public enum Phase: Equatable, Sendable {
        case running(deadline: ContinuousClock.Instant)
        case paused(remaining: Duration)
        case ringing
    }

    public let total: Duration
    public private(set) var phase: Phase

    public init(total: Duration, startingAt now: ContinuousClock.Instant) {
        precondition(total > .zero, "a countdown needs a positive duration")
        self.total = total
        phase = .running(deadline: now + total)
    }

    /// The total in whole seconds; countdowns are started from whole-second entries.
    public var totalSeconds: Int { Int(total.components.seconds) }

    public var isRunning: Bool {
        if case .running = phase { return true }
        return false
    }

    public var isPaused: Bool {
        if case .paused = phase { return true }
        return false
    }

    public var isRinging: Bool { phase == .ringing }

    /// The instant it rings, or `nil` while paused or already ringing.
    public var deadline: ContinuousClock.Instant? {
        guard case .running(let deadline) = phase else { return nil }
        return deadline
    }

    /// Time left, never negative.
    public func remaining(at now: ContinuousClock.Instant) -> Duration {
        switch phase {
        case .running(let deadline): max(.zero, deadline - now)
        case .paused(let remaining): remaining
        case .ringing: .zero
        }
    }

    /// Fraction of the total still left: 1 at the start, 0 when it rings.
    public func fractionRemaining(at now: ContinuousClock.Instant) -> Double {
        remaining(at: now) / total
    }

    /// Whole seconds to display, rounded up so the display reads `0:00` exactly when it rings.
    public func displaySeconds(at now: ContinuousClock.Instant) -> Int {
        let remaining = remaining(at: now).components
        let partial = remaining.attoseconds > 0 ? 1 : 0
        return Int(remaining.seconds) + partial
    }

    public func isDue(at now: ContinuousClock.Instant) -> Bool {
        guard let deadline else { return false }
        return now >= deadline
    }

    public mutating func pause(at now: ContinuousClock.Instant) {
        guard isRunning else { return }
        phase = .paused(remaining: remaining(at: now))
    }

    public mutating func resume(at now: ContinuousClock.Instant) {
        guard case .paused(let remaining) = phase else { return }
        phase = .running(deadline: now + remaining)
    }

    public mutating func ring() {
        phase = .ringing
    }
}

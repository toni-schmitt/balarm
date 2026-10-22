/// Tells a persistent alert that was swiped away from one still on screen.
///
/// macOS reports closing an alert but not swiping it away, which only moves it into
/// Notification Center. The one trace a swipe leaves is the system's notification overlay
/// leaving the screen right after a scroll or drag. Every notification on screen shares that
/// overlay and it does not say whose they are, so the detector takes an overlay that comes up
/// shortly after posting, with none on screen before, to be the alert's.
///
/// Other things take the overlay away too. Locking the screen and the display sleeping did so
/// until shortly after the screen was in use again, so only a gap seen to begin while the alert
/// was on a screen in use for a while, right after a scroll or drag, counts. A Focus hid it for
/// as long as the Focus was on, and what comes back afterwards may be another app's
/// notification, so after a long gap without a gesture the detector gives up.
///
/// Persistent alerts only: a temporary banner leaves by itself, which looks the same.
public struct AlertSwipeDetector: Sendable {
    /// What the screen and the input showed at one moment.
    public struct Sample: Sendable {
        public var isOverlayOnScreen: Bool
        /// Unlocked, awake and showing this user's session.
        public var isScreenInUse: Bool
        /// Seconds since the last scroll, which is what a trackpad swipe sends.
        public var secondsSinceScroll: Double
        /// Seconds since the last mouse drag, which is how a mouse swipes an alert away.
        public var secondsSinceDrag: Double
        /// The process drawing the overlay, which a restart of Notification Center changes.
        public var overlayOwner: Int32?

        public init(
            isOverlayOnScreen: Bool,
            isScreenInUse: Bool,
            secondsSinceScroll: Double,
            secondsSinceDrag: Double,
            overlayOwner: Int32?
        ) {
            self.isOverlayOnScreen = isOverlayOnScreen
            self.isScreenInUse = isScreenInUse
            self.secondsSinceScroll = secondsSinceScroll
            self.secondsSinceDrag = secondsSinceDrag
            self.overlayOwner = overlayOwner
        }
    }

    /// The defaults come from measuring on a Mac with persistent alerts, sampled every 0.1 s.
    public struct Timing: Sendable {
        /// How soon after posting the overlay must come up to count as the alert's. It took
        /// under 0.2 s, also with the screen locked.
        public var appearanceWindow: Duration
        /// How long the overlay must stay gone after a swipe gesture: short enough for the
        /// ringing to stop right after the alert has left, long enough that a flicker spanning a
        /// few samples is no swipe.
        public var goneThreshold: Duration
        /// How long the screen must have been in use with the alert posted before a gap counts.
        /// Unlocking and the display waking took the overlay away for about 0.5 s, beginning at
        /// most one sample after the screen was in use again, so a sample can show the alert on
        /// a screen in use just before such a gap. The alert is back only after that, so a
        /// swipe of it begins later still.
        public var settleThreshold: Duration
        /// How long a gap without a swipe gesture may last before the overlay that comes back
        /// can no longer be told to be the alert's. After unlocking it was back within 0.5 s;
        /// a Focus kept it away for as long as it was on.
        public var giveUpThreshold: Duration
        /// A trackpad swipe still scrolled as the overlay left.
        public var scrollWindow: Duration
        /// After dragging an alert away with the mouse, the overlay left 2.5 s later.
        public var dragWindow: Duration
        /// A longer gap between samples, from a stall or sleep, hides what the overlay did.
        public var maxSampleGap: Duration

        public init(
            appearanceWindow: Duration = .seconds(2),
            goneThreshold: Duration = .milliseconds(300),
            settleThreshold: Duration = .milliseconds(500),
            giveUpThreshold: Duration = .seconds(3),
            scrollWindow: Duration = .milliseconds(500),
            dragWindow: Duration = .seconds(4),
            maxSampleGap: Duration = .milliseconds(750)
        ) {
            self.appearanceWindow = appearanceWindow
            self.goneThreshold = goneThreshold
            self.settleThreshold = settleThreshold
            self.giveUpThreshold = giveUpThreshold
            self.scrollWindow = scrollWindow
            self.dragWindow = dragWindow
            self.maxSampleGap = maxSampleGap
        }
    }

    public enum Outcome: Sendable {
        case watching
        case swiped
        /// The overlay can no longer be told to be the alert's, so a swipe would go unnoticed.
        case gaveUp
    }

    private struct Gap {
        let since: ContinuousClock.Instant
        /// Seen to begin while the alert was on a screen in use for a while, right after a
        /// scroll or drag.
        let followsGesture: Bool
    }

    private enum Phase {
        case waitingForOverlay
        /// `alertWasShowing`: the last sample, taken in time, showed the overlay with the
        /// screen in use, so a gap that begins now is seen to begin.
        case following(owner: Int32?, gap: Gap?, alertWasShowing: Bool)
        case gaveUp
    }

    private let postedAt: ContinuousClock.Instant
    private let timing: Timing
    private var phase: Phase
    private var lastSampledAt: ContinuousClock.Instant?
    /// Posting, the last sample showing the screen out of use, or the first sample after a
    /// stall, which may have hidden the screen going out of use.
    private var lastUnsettledAt: ContinuousClock.Instant

    /// An overlay already on screen when the alert is posted belongs to another notification.
    public init(postedAt: ContinuousClock.Instant, isOverlayAlreadyOnScreen: Bool, timing: Timing = Timing()) {
        self.postedAt = postedAt
        self.timing = timing
        // The alarm can ring right after the Mac wakes, before a sample could show the screen
        // out of use.
        lastUnsettledAt = postedAt
        phase = isOverlayAlreadyOnScreen ? .gaveUp : .waitingForOverlay
    }

    public mutating func observe(_ sample: Sample, at now: ContinuousClock.Instant) -> Outcome {
        let isTimely = lastSampledAt.map { now - $0 <= timing.maxSampleGap } ?? true
        lastSampledAt = now
        if !sample.isScreenInUse || !isTimely { lastUnsettledAt = now }
        switch phase {
        case .gaveUp:
            return .gaveUp
        case .waitingForOverlay:
            return waitForOverlay(sample, at: now)
        case .following(let owner, let gap, let alertWasShowing):
            // After a stall, a gap still open may have closed and opened again unseen.
            return follow(
                sample,
                owner: owner,
                gap: isTimely ? gap : nil,
                alertWasShowing: alertWasShowing && isTimely,
                at: now
            )
        }
    }

    private mutating func waitForOverlay(_ sample: Sample, at now: ContinuousClock.Instant) -> Outcome {
        // Checked first, so a late first sample cannot adopt another notification's overlay.
        guard now - postedAt <= timing.appearanceWindow else {
            phase = .gaveUp
            return .gaveUp
        }
        guard sample.isOverlayOnScreen else { return .watching }
        phase = .following(owner: sample.overlayOwner, gap: nil, alertWasShowing: sample.isScreenInUse)
        return .watching
    }

    private mutating func follow(
        _ sample: Sample,
        owner: Int32?,
        gap: Gap?,
        alertWasShowing: Bool,
        at now: ContinuousClock.Instant
    ) -> Outcome {
        guard sample.overlayOwner == owner else {
            phase = .gaveUp
            return .gaveUp
        }
        guard sample.isScreenInUse else {
            phase = .following(owner: owner, gap: nil, alertWasShowing: false)
            return .watching
        }
        guard !sample.isOverlayOnScreen else {
            phase = .following(owner: owner, gap: nil, alertWasShowing: true)
            return .watching
        }
        let current = gap ?? Gap(
            since: now,
            followsGesture: alertWasShowing && isSettled(at: now) && followsGesture(sample)
        )
        phase = .following(owner: owner, gap: current, alertWasShowing: false)
        guard current.followsGesture else {
            guard now - current.since >= timing.giveUpThreshold else { return .watching }
            phase = .gaveUp
            return .gaveUp
        }
        guard now - current.since >= timing.goneThreshold else { return .watching }
        return .swiped
    }

    private func isSettled(at now: ContinuousClock.Instant) -> Bool {
        now - lastUnsettledAt >= timing.settleThreshold
    }

    private func followsGesture(_ sample: Sample) -> Bool {
        if sample.secondsSinceScroll <= timing.scrollWindow / .seconds(1) { return true }
        return sample.secondsSinceDrag <= timing.dragWindow / .seconds(1)
    }
}

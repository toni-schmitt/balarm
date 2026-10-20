import Testing
@testable import BalarmCore

/// The sequences follow what the window server and the input showed on a Mac with
/// persistent alerts: the overlay came up within 0.2 s of posting, also with the screen
/// locked, and left on a swipe while the trackpad still scrolled, 2.5 s after dragging the
/// alert away with the mouse, for the 4 s a Do Not Disturb was on, and for 0.5 s after
/// unlocking. It stayed through Mission Control, Notification Center and Spaces.
@Suite struct AlertSwipeDetectorTests {
    private let start = ContinuousClock.now

    private enum Screen {
        case overlay, noOverlay, locked, lockedWithOverlay
    }

    /// Seconds before the sample of the last scroll and drag; long ago unless set.
    struct Input: Sendable {
        var scroll = 100.0
        var drag = 100.0

        static let none = Input()
        static func scrolled(_ seconds: Double) -> Input { Input(scroll: seconds) }
        static func dragged(_ seconds: Double) -> Input { Input(drag: seconds) }
    }

    private struct Step {
        var at: Double
        var screen: Screen
        var input = Input.none
        var owner: Int32 = 58321
    }

    /// Feeds the steps, `at` seconds after posting, and returns the last outcome and when a
    /// swipe was reported.
    private func outcome(
        _ steps: [Step],
        isOverlayAlreadyOnScreen: Bool = false
    ) -> (last: AlertSwipeDetector.Outcome, swipedAt: Double?) {
        var detector = AlertSwipeDetector(postedAt: start, isOverlayAlreadyOnScreen: isOverlayAlreadyOnScreen)
        var last = AlertSwipeDetector.Outcome.watching
        for step in steps {
            let sample = AlertSwipeDetector.Sample(
                isOverlayOnScreen: step.screen == .overlay || step.screen == .lockedWithOverlay,
                isScreenInUse: step.screen == .overlay || step.screen == .noOverlay,
                secondsSinceScroll: step.input.scroll,
                secondsSinceDrag: step.input.drag,
                overlayOwner: step.owner
            )
            last = detector.observe(sample, at: start + .seconds(step.at))
            if last == .swiped { return (last, step.at) }
        }
        return (last, nil)
    }

    /// Samples every 0.25 s from `from` through `to`, all showing the same.
    private func steps(_ from: Double, _ to: Double, _ screen: Screen, input: Input = .none) -> [Step] {
        stride(from: from, through: to, by: 0.25).map { Step(at: $0, screen: screen, input: input) }
    }

    // MARK: - Swipes

    @Test func aTrackpadSwipeIsReported() {
        let samples = steps(0, 3.5, .overlay)
            + [Step(at: 3.75, screen: .noOverlay, input: .scrolled(0))]
            + steps(4.0, 5.0, .noOverlay, input: .scrolled(0.5))
        #expect(outcome(samples).swipedAt == 4.75)
    }

    @Test func aMouseDragIsReported() {
        let samples = steps(0, 5.5, .overlay)
            + [Step(at: 5.75, screen: .noOverlay, input: .dragged(2.5))]
            + steps(6.0, 7.0, .noOverlay, input: .dragged(3))
        #expect(outcome(samples).swipedAt == 6.75)
    }

    @Test(arguments: [Input.scrolled(0.5), .dragged(4)])
    func aGestureAtTheEdgeOfItsWindowCounts(input: Input) {
        let samples = steps(0, 2, .overlay) + steps(2.25, 3.5, .noOverlay, input: input)
        #expect(outcome(samples).swipedAt == 3.25)
    }

    @Test(arguments: [Input.scrolled(0.75), .dragged(4.5)])
    func aGestureLongBeforeTheOverlayLeftIsNoSwipe(input: Input) {
        let samples = steps(0, 2, .overlay) + steps(2.25, 6, .noOverlay, input: input)
        #expect(outcome(samples) == (.gaveUp, nil))
    }

    @Test func aSwipeAfterRingingWhileLockedIsReported() {
        let samples = steps(0, 2.5, .lockedWithOverlay) + steps(2.75, 8, .overlay)
            + steps(8.25, 9.5, .noOverlay, input: .scrolled(0))
        #expect(outcome(samples).swipedAt == 9.25)
    }

    @Test func aGapWithoutGestureShorterThanGivingUpKeepsWatching() {
        let samples = steps(0, 2, .overlay) + steps(2.25, 4.25, .noOverlay) + steps(4.5, 6, .overlay)
            + steps(6.25, 7.5, .noOverlay, input: .scrolled(0))
        #expect(outcome(samples).swipedAt == 7.25)
    }

    @Test func aSwipeAfterUnlockingIsReported() {
        // Unlocking took the overlay away for half a second, unseen as it began.
        let samples = steps(0, 2, .lockedWithOverlay) + steps(2.25, 2.75, .noOverlay, input: .scrolled(0.2))
            + steps(3, 5, .overlay) + steps(5.25, 6.5, .noOverlay, input: .scrolled(0))
        #expect(outcome(samples).swipedAt == 6.25)
    }

    // MARK: - No swipe

    @Test func anOverlayThatStaysIsNoSwipe() {
        // Mission Control, Notification Center and switching Spaces, with scrolling throughout.
        #expect(outcome(steps(0, 10, .overlay, input: .scrolled(0))) == (.watching, nil))
    }

    @Test func aShortGapIsNoSwipe() {
        let samples = steps(0, 1, .overlay) + steps(1.25, 2, .noOverlay, input: .scrolled(0)) + steps(2.25, 4, .overlay)
        #expect(outcome(samples) == (.watching, nil))
    }

    @Test func lockingAndUnlockingIsNoSwipe() {
        // Scrolling as the screen locks and as it is unlocked again.
        let samples = steps(0, 2, .overlay) + steps(2.25, 5, .locked, input: .scrolled(0.3))
            + steps(5.25, 5.75, .noOverlay, input: .scrolled(0.2)) + steps(6, 8, .overlay)
        #expect(outcome(samples) == (.watching, nil))
    }

    @Test func aGapNotSeenToBeginIsNoSwipe() {
        // The overlay left while the screen was locked and stays away after unlocking, as the
        // user scrolls.
        let samples = steps(0, 2, .overlay) + steps(2.25, 5, .locked)
            + steps(5.25, 9, .noOverlay, input: .scrolled(0.2))
        #expect(outcome(samples) == (.gaveUp, nil))
    }

    @Test func aGestureAfterTheOverlayLeftIsNoSwipe() {
        let samples = steps(0, 2, .overlay) + steps(2.25, 3, .noOverlay)
            + steps(3.25, 6, .noOverlay, input: .scrolled(0))
        #expect(outcome(samples) == (.gaveUp, nil))
    }

    @Test func aStallJustBeforeTheGapIsNoSwipe() {
        // A second passed unsampled between the last sample with the overlay and the first
        // without it.
        let samples = steps(0, 2, .overlay) + steps(3, 7, .noOverlay, input: .scrolled(0.1))
        #expect(outcome(samples) == (.gaveUp, nil))
    }

    @Test func aStallWithinTheGapStartsItOver() {
        // The Mac slept between the samples at 2.5 s and 3602.5 s.
        let samples = steps(0, 2, .overlay) + steps(2.25, 2.5, .noOverlay, input: .scrolled(0))
            + steps(3602.5, 3606, .noOverlay, input: .scrolled(0.1))
        #expect(outcome(samples) == (.gaveUp, nil))
    }

    // MARK: - Giving up

    @Test func doNotDisturbHidingTheOverlayEndsTheWatch() {
        // Turned on from Control Center, which is a click. What comes back when it is turned
        // off may be another app's notification, so a swipe of that is not the alert's.
        let samples = steps(0, 6, .overlay) + steps(6.25, 10.5, .noOverlay) + steps(10.75, 12, .overlay)
            + steps(12.25, 14, .noOverlay, input: .scrolled(0))
        #expect(outcome(samples) == (.gaveUp, nil))
    }

    @Test func aRestartedNotificationCenterEndsTheWatch() {
        let samples = steps(0, 2, .overlay) + [Step(at: 2.25, screen: .noOverlay, input: .scrolled(0), owner: 4242)]
        #expect(outcome(samples) == (.gaveUp, nil))
    }

    @Test func anOverlayAlreadyOnScreenBelongsToAnotherNotification() {
        let samples = steps(0, 2, .overlay) + steps(2.25, 4, .noOverlay, input: .scrolled(0))
        #expect(outcome(samples, isOverlayAlreadyOnScreen: true) == (.gaveUp, nil))
    }

    @Test func anOverlayComingUpLateIsNotTheAlerts() {
        // A Focus held the alert back; another notification shows and is swiped later.
        let samples = steps(0, 2, .noOverlay) + steps(2.25, 6, .overlay)
            + steps(6.25, 8, .noOverlay, input: .scrolled(0))
        #expect(outcome(samples) == (.gaveUp, nil))
    }

    @Test func anOverlayComingUpLateOnTheLockScreenIsNotTheAlerts() {
        // The alert was held back; another notification shows on the lock screen later.
        let samples = steps(0, 2.5, .locked) + steps(2.75, 5, .lockedWithOverlay) + steps(5.25, 7, .overlay)
            + steps(7.25, 9, .noOverlay, input: .scrolled(0))
        #expect(outcome(samples) == (.gaveUp, nil))
    }

    @Test func aFirstSampleAfterTheWindowGivesUp() {
        #expect(outcome([Step(at: 2.5, screen: .overlay)]) == (.gaveUp, nil))
    }
}

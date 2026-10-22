import BalarmCore
import Testing
import UserNotifications
@testable import Balarm

@MainActor
@Suite struct AlarmNotifierTests {
    @Test func addingTheCurrentAlertLeavesItShowing() throws {
        let notificationDelivery = DeferredAlarmNotificationDelivery()
        let notifier = AlarmNotifier(notificationDelivery: notificationDelivery, alertScreen: ScriptedAlertScreen())
        notifier.post(body: "Alarm")
        let identifier = try #require(notificationDelivery.requests.first?.identifier)
        notificationDelivery.complete(at: 0)
        #expect(notificationDelivery.removedPending.isEmpty)
        #expect(notificationDelivery.removedDelivered.isEmpty)
        #expect(notifier.presentationOptions(for: identifier) == [.banner, .list])
    }

    @Test func lateDeliveryIsRemovedWithoutRemovingTheNewAlert() throws {
        let notificationDelivery = DeferredAlarmNotificationDelivery()
        let notifier = AlarmNotifier(notificationDelivery: notificationDelivery, alertScreen: ScriptedAlertScreen())
        notifier.post(body: "First alarm")
        let first = try #require(notificationDelivery.requests.first?.identifier)
        notifier.withdraw()
        notifier.post(body: "Second alarm")
        let second = try #require(notificationDelivery.requests.last?.identifier)
        #expect(first != second)
        notificationDelivery.clearRemovals()

        // The first request finishes after the second one is already visible.
        notificationDelivery.complete(at: 1)
        #expect(notificationDelivery.removedPending.isEmpty)
        #expect(notificationDelivery.removedDelivered.isEmpty)
        notificationDelivery.complete(at: 0)
        #expect(notificationDelivery.removedPending == [first])
        #expect(notificationDelivery.removedDelivered == [first])
        #expect(notifier.presentationOptions(for: first).isEmpty)
        #expect(notifier.presentationOptions(for: second) == [.banner, .list])
    }

    @Test func postingAgainReplacesThePreviousAlert() throws {
        let notificationDelivery = DeferredAlarmNotificationDelivery()
        let notifier = AlarmNotifier(notificationDelivery: notificationDelivery, alertScreen: ScriptedAlertScreen())
        notifier.post(body: "First alarm")
        let first = try #require(notificationDelivery.requests.first?.identifier)
        notifier.post(body: "Second alarm")
        let second = try #require(notificationDelivery.requests.last?.identifier)
        #expect(notificationDelivery.removedPending == [first])
        #expect(notificationDelivery.removedDelivered == [first])
        #expect(notifier.presentationOptions(for: first).isEmpty)
        #expect(notifier.presentationOptions(for: second) == [.banner, .list])
    }

    @Test func stoppingBeforeDeliveryRemovesTheLateAlert() throws {
        let notificationDelivery = DeferredAlarmNotificationDelivery()
        let notifier = AlarmNotifier(notificationDelivery: notificationDelivery, alertScreen: ScriptedAlertScreen())
        notifier.post(body: "Alarm")
        let identifier = try #require(notificationDelivery.requests.first?.identifier)
        notifier.withdraw()
        notificationDelivery.clearRemovals()
        notificationDelivery.complete(at: 0)
        #expect(notificationDelivery.removedPending == [identifier])
        #expect(notificationDelivery.removedDelivered == [identifier])
        #expect(notifier.presentationOptions(for: identifier).isEmpty)
    }

    @Test(arguments: [AlarmNotifier.stopActionID, AlarmNotifier.repeatActionID, UNNotificationDismissActionIdentifier])
    func staleActionsCannotAffectTheNewAlarm(actionID: String) throws {
        let notificationDelivery = DeferredAlarmNotificationDelivery()
        let notifier = AlarmNotifier(notificationDelivery: notificationDelivery, alertScreen: ScriptedAlertScreen())
        var stops = 0
        var repeats = 0
        notifier.onStop = { stops += 1 }
        notifier.onRepeat = { repeats += 1 }
        notifier.post(body: "First alarm")
        let first = try #require(notificationDelivery.requests.first?.identifier)
        notifier.withdraw()
        notifier.post(body: "Second alarm")
        let second = try #require(notificationDelivery.requests.last?.identifier)

        var opens = 0
        notifier.onOpen = { opens += 1 }
        notifier.handleResponse(actionID: actionID, requestID: first)
        #expect(stops == 0)
        #expect(repeats == 0)
        #expect(opens == 0)
        #expect(notifier.presentationOptions(for: second) == [.banner, .list])

        let isRepeat = actionID == AlarmNotifier.repeatActionID
        notifier.handleResponse(actionID: actionID, requestID: second)
        #expect(stops == (isRepeat ? 0 : 1))
        #expect(repeats == (isRepeat ? 1 : 0))
        #expect(notifier.presentationOptions(for: second).isEmpty)
        // A duplicate response must also be harmless.
        notifier.handleResponse(actionID: actionID, requestID: second)
        #expect(stops + repeats == 1)
    }

    // MARK: - Swiping the alert away

    @Test func aSwipeStopsTheAlarm() async throws {
        let notificationDelivery = DeferredAlarmNotificationDelivery(style: .persistent)
        let alertScreen = ScriptedAlertScreen()
        let notifier = AlarmNotifier(notificationDelivery: notificationDelivery, alertScreen: alertScreen, timing: .fast)
        var stops = 0
        notifier.onStop = { stops += 1 }
        notifier.post(body: "Alarm")
        let identifier = try #require(notificationDelivery.requests.first?.identifier)

        alertScreen.showOverlay()
        await waitUntil { alertScreen.samplesWithOverlay > 0 }
        alertScreen.swipeOverlayAway()
        await waitUntil { stops == 1 }
        #expect(stops == 1)
        #expect(notificationDelivery.removedDelivered == [identifier])
    }

    @Test func withTemporaryAlertsASwipeIsNotWatched() async throws {
        let notificationDelivery = DeferredAlarmNotificationDelivery(style: .temporary)
        let alertScreen = ScriptedAlertScreen()
        let notifier = AlarmNotifier(notificationDelivery: notificationDelivery, alertScreen: alertScreen, timing: .fast)
        var stops = 0
        notifier.onStop = { stops += 1 }
        notifier.post(body: "Alarm")

        alertScreen.showOverlay()
        try await Task.sleep(for: .milliseconds(30))
        alertScreen.swipeOverlayAway()
        try await Task.sleep(for: .milliseconds(200))
        #expect(stops == 0)
        #expect(alertScreen.samplesWithOverlay == 0)
    }

    @Test func aWithdrawnAlertsWatchCannotStopTheAlarm() async throws {
        let notificationDelivery = DeferredAlarmNotificationDelivery(style: .persistent)
        let alertScreen = ScriptedAlertScreen()
        let notifier = AlarmNotifier(notificationDelivery: notificationDelivery, alertScreen: alertScreen, timing: .fast)
        var stops = 0
        notifier.onStop = { stops += 1 }
        notifier.post(body: "Alarm")

        alertScreen.showOverlay()
        await waitUntil { alertScreen.samplesWithOverlay > 0 }
        notifier.withdraw()
        alertScreen.swipeOverlayAway()
        try await Task.sleep(for: .milliseconds(200))
        #expect(stops == 0)
    }

    @Test func aFailedAlertIsNotWatched() async throws {
        let notificationDelivery = DeferredAlarmNotificationDelivery(style: .persistent)
        let alertScreen = ScriptedAlertScreen()
        let notifier = AlarmNotifier(notificationDelivery: notificationDelivery, alertScreen: alertScreen, timing: .fast)
        var stops = 0
        notifier.onStop = { stops += 1 }
        notifier.post(body: "Alarm")
        notificationDelivery.complete(at: 0, error: CancellationError())

        // Another notification comes up and is swiped away.
        alertScreen.showOverlay()
        try await Task.sleep(for: .milliseconds(30))
        alertScreen.swipeOverlayAway()
        try await Task.sleep(for: .milliseconds(200))
        #expect(stops == 0)
    }

    @Test func switchingToTemporaryAlertsBeforeTheSwipeCountsKeepsItRinging() async throws {
        let notificationDelivery = DeferredAlarmNotificationDelivery(style: .persistent)
        let alertScreen = ScriptedAlertScreen()
        let notifier = AlarmNotifier(notificationDelivery: notificationDelivery, alertScreen: alertScreen, timing: .fast)
        var stops = 0
        notifier.onStop = { stops += 1 }
        notifier.post(body: "Alarm")

        alertScreen.showOverlay()
        await waitUntil { alertScreen.samplesWithOverlay > 0 }
        notificationDelivery.style = .temporary
        alertScreen.swipeOverlayAway()
        try await Task.sleep(for: .milliseconds(200))
        #expect(stops == 0)
    }

    // MARK: - Clicking the alert

    @Test func clickingTheAlertOpensBalarmAndShowsTheAlertAgain() async throws {
        let notificationDelivery = DeferredAlarmNotificationDelivery()
        let notifier = AlarmNotifier(notificationDelivery: notificationDelivery, alertScreen: ScriptedAlertScreen(), timing: .fast)
        var stops = 0
        var opens = 0
        notifier.onStop = { stops += 1 }
        notifier.onOpen = { opens += 1 }
        notifier.post(body: "25 min")
        let clicked = try #require(notificationDelivery.requests.first?.identifier)

        notifier.handleResponse(actionID: UNNotificationDefaultActionIdentifier, requestID: clicked)
        #expect(opens == 1)
        #expect(notificationDelivery.requests.count == 1)
        await waitUntil { notificationDelivery.requests.count == 2 }
        let shownAgain = try #require(notificationDelivery.requests.last)
        #expect(shownAgain.identifier != clicked)
        #expect(shownAgain.content.body == "25 min")
        #expect(notifier.presentationOptions(for: clicked).isEmpty)
        #expect(notifier.presentationOptions(for: shownAgain.identifier) == [.banner, .list])
        #expect(stops == 0)
    }

    @Test func theOverlayLeavingOnAClickIsNoSwipe() async throws {
        let notificationDelivery = DeferredAlarmNotificationDelivery(style: .persistent)
        let alertScreen = ScriptedAlertScreen()
        // Showing the alert again takes longer than a swipe needs to be reported.
        var timing = AlarmNotifier.Timing.fast
        timing.reshowDelay = .milliseconds(150)
        let notifier = AlarmNotifier(notificationDelivery: notificationDelivery, alertScreen: alertScreen, timing: timing)
        var stops = 0
        notifier.onStop = { stops += 1 }
        notifier.post(body: "Alarm")
        let clicked = try #require(notificationDelivery.requests.first?.identifier)

        alertScreen.showOverlay()
        await waitUntil { alertScreen.samplesWithOverlay > 0 }
        notifier.handleResponse(actionID: UNNotificationDefaultActionIdentifier, requestID: clicked)
        // The worst case: the pointer also scrolled as the clicked alert left.
        alertScreen.swipeOverlayAway()
        await waitUntil { notificationDelivery.requests.count == 2 }
        #expect(notificationDelivery.requests.count == 2)
        #expect(stops == 0)
    }

    @Test func theAlertShownAgainIsWatchedForASwipe() async throws {
        let notificationDelivery = DeferredAlarmNotificationDelivery(style: .persistent)
        let alertScreen = ScriptedAlertScreen()
        let notifier = AlarmNotifier(notificationDelivery: notificationDelivery, alertScreen: alertScreen, timing: .fast)
        var stops = 0
        notifier.onStop = { stops += 1 }
        notifier.post(body: "Alarm")
        let clicked = try #require(notificationDelivery.requests.first?.identifier)
        alertScreen.showOverlay()
        await waitUntil { alertScreen.samplesWithOverlay > 0 }

        notifier.handleResponse(actionID: UNNotificationDefaultActionIdentifier, requestID: clicked)
        alertScreen.hideOverlay()
        await waitUntil { notificationDelivery.requests.count == 2 }
        let seenBefore = alertScreen.samplesWithOverlay
        alertScreen.showOverlay()
        await waitUntil { alertScreen.samplesWithOverlay > seenBefore }
        alertScreen.swipeOverlayAway()
        await waitUntil { stops == 1 }
        #expect(stops == 1)
    }

    @Test func stoppingBeforeTheAlertIsShownAgainKeepsItHidden() async throws {
        let notificationDelivery = DeferredAlarmNotificationDelivery()
        let notifier = AlarmNotifier(notificationDelivery: notificationDelivery, alertScreen: ScriptedAlertScreen(), timing: .fast)
        notifier.post(body: "Alarm")
        let clicked = try #require(notificationDelivery.requests.first?.identifier)

        notifier.handleResponse(actionID: UNNotificationDefaultActionIdentifier, requestID: clicked)
        notifier.withdraw()
        try await Task.sleep(for: .milliseconds(100))
        #expect(notificationDelivery.requests.count == 1)
    }

    @Test func clickingAnEarlierAlertOnlyOpensBalarm() throws {
        let notificationDelivery = DeferredAlarmNotificationDelivery()
        let notifier = AlarmNotifier(notificationDelivery: notificationDelivery, alertScreen: ScriptedAlertScreen(), timing: .fast)
        var opens = 0
        notifier.onOpen = { opens += 1 }
        notifier.post(body: "Alarm")
        let identifier = try #require(notificationDelivery.requests.first?.identifier)
        notifier.withdraw()

        notifier.handleResponse(actionID: UNNotificationDefaultActionIdentifier, requestID: identifier)
        #expect(opens == 1)
        #expect(notificationDelivery.requests.count == 1)
    }

    /// Polls, since the notifier's tasks run on their own schedule.
    private func waitUntil(_ condition: () -> Bool) async {
        for _ in 0..<400 {
            if condition() { return }
            try? await Task.sleep(for: .milliseconds(5))
        }
    }
}

private extension AlarmNotifier.Timing {
    /// Real time passes in these tests, so everything is short; sample gaps stay unchecked, and
    /// the screen counts as settled at once.
    static let fast = AlarmNotifier.Timing(
        swipeCheckInterval: .milliseconds(5),
        reshowDelay: .milliseconds(20),
        swipe: AlertSwipeDetector.Timing(
            appearanceWindow: .seconds(5),
            goneThreshold: .milliseconds(30),
            settleThreshold: .zero,
            maxSampleGap: .seconds(5)
        )
    )
}

@MainActor
private final class ScriptedAlertScreen: AlertScreen {
    /// How many samples showed the overlay, so a test can wait until the watch saw it.
    private(set) var samplesWithOverlay = 0
    private var current = AlertSwipeDetector.Sample(
        isOverlayOnScreen: false,
        isScreenInUse: true,
        secondsSinceScroll: 100,
        secondsSinceDrag: 100,
        overlayOwner: 58321
    )

    func sample() -> AlertSwipeDetector.Sample {
        if current.isOverlayOnScreen { samplesWithOverlay += 1 }
        return current
    }

    func showOverlay() {
        current.isOverlayOnScreen = true
        current.secondsSinceScroll = 100
    }

    /// Without a gesture, as when a click takes the alert away.
    func hideOverlay() {
        current.isOverlayOnScreen = false
    }

    func swipeOverlayAway() {
        current.isOverlayOnScreen = false
        current.secondsSinceScroll = 0
    }
}

@MainActor
private final class DeferredAlarmNotificationDelivery: AlarmNotificationDelivery {
    var style: AlarmAlertStyle
    var requests: [UNNotificationRequest] = []
    var completions: [@MainActor @Sendable ((any Error)?) -> Void] = []
    var removedPending: [String] = []
    var removedDelivered: [String] = []

    init(style: AlarmAlertStyle = .temporary) {
        self.style = style
    }

    func add(
        _ request: UNNotificationRequest,
        completion: @escaping @MainActor @Sendable ((any Error)?) -> Void
    ) {
        requests.append(request)
        completions.append(completion)
    }

    func complete(at index: Int, error: (any Error)? = nil) { completions[index](error) }
    func removePending(_ identifiers: [String]) { removedPending += identifiers }
    func removeDelivered(_ identifiers: [String]) { removedDelivered += identifiers }
    func alertStyle() async -> AlarmAlertStyle { style }

    func clearRemovals() {
        removedPending = []
        removedDelivered = []
    }
}

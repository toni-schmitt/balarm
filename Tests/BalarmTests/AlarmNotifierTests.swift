import Testing
import UserNotifications
@testable import Balarm

@MainActor
@Suite struct AlarmNotifierTests {
    @Test func addingTheCurrentAlertLeavesItShowing() throws {
        let notificationDelivery = DeferredAlarmNotificationDelivery()
        let notifier = AlarmNotifier(notificationDelivery: notificationDelivery)
        notifier.post(body: "Alarm")
        let identifier = try #require(notificationDelivery.requests.first?.identifier)
        notificationDelivery.complete(at: 0)
        #expect(notificationDelivery.removedPending.isEmpty)
        #expect(notificationDelivery.removedDelivered.isEmpty)
        #expect(notifier.presentationOptions(for: identifier) == [.banner, .list])
    }

    @Test func lateDeliveryIsRemovedWithoutRemovingTheNewAlert() throws {
        let notificationDelivery = DeferredAlarmNotificationDelivery()
        let notifier = AlarmNotifier(notificationDelivery: notificationDelivery)
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
        let notifier = AlarmNotifier(notificationDelivery: notificationDelivery)
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
        let notifier = AlarmNotifier(notificationDelivery: notificationDelivery)
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
        let notifier = AlarmNotifier(notificationDelivery: notificationDelivery)
        var stops = 0
        var repeats = 0
        notifier.onStop = { stops += 1 }
        notifier.onRepeat = { repeats += 1 }
        notifier.post(body: "First alarm")
        let first = try #require(notificationDelivery.requests.first?.identifier)
        notifier.withdraw()
        notifier.post(body: "Second alarm")
        let second = try #require(notificationDelivery.requests.last?.identifier)

        notifier.handleResponse(actionID: actionID, requestID: first)
        #expect(stops == 0)
        #expect(repeats == 0)
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
}

@MainActor
private final class DeferredAlarmNotificationDelivery: AlarmNotificationDelivery {
    var requests: [UNNotificationRequest] = []
    var completions: [@MainActor @Sendable ((any Error)?) -> Void] = []
    var removedPending: [String] = []
    var removedDelivered: [String] = []

    func add(
        _ request: UNNotificationRequest,
        completion: @escaping @MainActor @Sendable ((any Error)?) -> Void
    ) {
        requests.append(request)
        completions.append(completion)
    }

    func complete(at index: Int) { completions[index](nil) }
    func removePending(_ identifiers: [String]) { removedPending += identifiers }
    func removeDelivered(_ identifiers: [String]) { removedDelivered += identifiers }

    func clearRemovals() {
        removedPending = []
        removedDelivered = []
    }
}

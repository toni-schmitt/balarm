import AppKit
import UserNotifications
import os

private let log = Logger(subsystem: Bundle.main.bundleIdentifier ?? "Balarm", category: "Notifications")

/// Shows the "time's up" alert with Stop and Repeat, like Clock.app's timer alert.
@MainActor
final class AlarmNotifier: NSObject, UNUserNotificationCenterDelegate {
    var onStop: () -> Void = {}
    var onRepeat: () -> Void = {}

    private let notificationDelivery: any AlarmNotificationDelivery
    /// Only this notification may present or act on the current alarm.
    private var currentRequestID: String?

    private static let categoryID = "alarm"
    nonisolated static let stopActionID = "stop"
    nonisolated static let repeatActionID = "repeat"

    init(notificationDelivery: any AlarmNotificationDelivery = SystemAlarmNotificationDelivery()) {
        self.notificationDelivery = notificationDelivery
        super.init()
    }

    func activate() {
        let center = UNUserNotificationCenter.current()
        center.delegate = self
        // Quitting while ringing can leave an alert behind whose Stop and Repeat no longer
        // have an alarm to act on.
        center.removeAllDeliveredNotifications()

        let category = UNNotificationCategory(
            identifier: Self.categoryID,
            actions: [
                UNNotificationAction(identifier: Self.stopActionID, title: "Stop"),
                UNNotificationAction(identifier: Self.repeatActionID, title: "Repeat"),
            ],
            intentIdentifiers: [],
            // Closing the alert stops the ringing instead of leaving it looping unseen.
            options: [.customDismissAction]
        )
        center.setNotificationCategories([category])

        Task {
            do {
                let granted = try await center.requestAuthorization(options: [.alert])
                if !granted {
                    log.notice("Notifications are turned off for Balarm; it will only ring")
                }
            } catch {
                log.error("Notification authorization failed: \(error.localizedDescription, privacy: .public)")
            }
        }
    }

    func post(body: String) {
        withdraw()
        let content = UNMutableNotificationContent()
        content.title = "Alarm"
        content.body = body
        content.categoryIdentifier = Self.categoryID
        // Deliberately silent: Ringer loops the tone until stopped, and a notification
        // sound would play on top of it.
        content.sound = nil

        let requestID = "alarm.rang.\(UUID().uuidString)"
        currentRequestID = requestID
        let request = UNNotificationRequest(identifier: requestID, content: content, trigger: nil)
        notificationDelivery.add(request) { [weak self] error in
            if let error {
                log.error("Cannot show the alarm notification: \(error.localizedDescription, privacy: .public)")
                return
            }
            self?.withdrawIfStale(requestID)
        }
    }

    func withdraw() {
        guard let requestID = currentRequestID else { return }
        currentRequestID = nil
        removeAlert(requestID)
    }

    /// Adding the request is asynchronous, so an alarm stopped right at 0:00 is withdrawn
    /// before its alert exists; remove the alert again once the request has been added.
    private func withdrawIfStale(_ requestID: String) {
        guard currentRequestID != requestID else { return }
        removeAlert(requestID)
    }

    /// Removes the request whether it is still waiting to be shown or already on screen:
    /// `add`'s completion does not say which of the two it is in.
    private func removeAlert(_ requestID: String) {
        notificationDelivery.removePending([requestID])
        notificationDelivery.removeDelivered([requestID])
    }

    func presentationOptions(for requestID: String) -> UNNotificationPresentationOptions {
        // A withdrawn request may still reach the delegate while add is in flight.
        guard currentRequestID == requestID else { return [] }
        // Shown even while Balarm is frontmost, since the alert carries the Stop/Repeat actions.
        return [.banner, .list]
    }

    func handleResponse(actionID: String, requestID: String) {
        guard currentRequestID == requestID else { return }
        switch actionID {
        case Self.stopActionID, UNNotificationDismissActionIdentifier:
            withdraw()
            onStop()
        case Self.repeatActionID:
            withdraw()
            onRepeat()
        default:
            NSApp.activate()
        }
    }

    nonisolated func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        willPresent notification: UNNotification
    ) async -> UNNotificationPresentationOptions {
        await presentationOptions(for: notification.request.identifier)
    }

    nonisolated func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        didReceive response: UNNotificationResponse
    ) async {
        let actionID = response.actionIdentifier
        let requestID = response.notification.request.identifier
        await MainActor.run {
            handleResponse(actionID: actionID, requestID: requestID)
        }
    }
}

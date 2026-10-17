import AppKit
import UserNotifications
import os

private let log = Logger(subsystem: "com.toni.balarm", category: "Notifications")

/// Shows the "time's up" alert with Stop and Repeat, like Clock.app's timer alert.
@MainActor
final class AlarmNotifier: NSObject, UNUserNotificationCenterDelegate {
    var onStop: () -> Void = {}
    var onRepeat: () -> Void = {}

    private let center = UNUserNotificationCenter.current()
    private var isShowingAlert = false

    private static let categoryID = "alarm"
    private static let requestID = "alarm.rang"
    private static let stopActionID = "stop"
    private static let repeatActionID = "repeat"

    func activate() {
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
        let content = UNMutableNotificationContent()
        content.title = "Alarm"
        content.body = body
        content.categoryIdentifier = Self.categoryID
        // Deliberately silent: Ringer loops the tone until stopped, and a notification
        // sound would play on top of it.
        content.sound = nil

        isShowingAlert = true
        let request = UNNotificationRequest(identifier: Self.requestID, content: content, trigger: nil)
        center.add(request) { [weak self] error in
            if let error {
                log.error("Cannot show the alarm notification: \(error.localizedDescription, privacy: .public)")
                return
            }
            Task { @MainActor in self?.withdrawIfStale() }
        }
    }

    func withdraw() {
        isShowingAlert = false
        removeAlert()
    }

    /// Adding the request is asynchronous, so an alarm stopped right at 0:00 is withdrawn
    /// before its alert exists; remove the alert again once the request has been added.
    private func withdrawIfStale() {
        guard !isShowingAlert else { return }
        removeAlert()
    }

    /// Removes the request whether it is still waiting to be shown or already on screen:
    /// `add`'s completion does not say which of the two it is in.
    private func removeAlert() {
        center.removePendingNotificationRequests(withIdentifiers: [Self.requestID])
        center.removeDeliveredNotifications(withIdentifiers: [Self.requestID])
    }

    nonisolated func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        willPresent notification: UNNotification
    ) async -> UNNotificationPresentationOptions {
        // Shown even while Balarm is frontmost, since the alert carries the Stop/Repeat actions.
        [.banner, .list]
    }

    nonisolated func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        didReceive response: UNNotificationResponse
    ) async {
        let actionID = response.actionIdentifier
        await MainActor.run {
            switch actionID {
            case Self.stopActionID, UNNotificationDismissActionIdentifier:
                onStop()
            case Self.repeatActionID:
                onRepeat()
            default:
                NSApp.activate()
            }
        }
    }
}

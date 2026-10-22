import BalarmCore
import UserNotifications
import os

private let log = Logger(subsystem: Bundle.main.bundleIdentifier ?? "Balarm", category: "Notifications")

/// Shows the "time's up" alert with Stop and Repeat, like Clock.app's timer alert.
@MainActor
final class AlarmNotifier: NSObject, UNUserNotificationCenterDelegate {
    var onStop: () -> Void = {}
    var onRepeat: () -> Void = {}
    var onOpen: () -> Void = {}
    /// Called when asking whether Balarm may notify has finished, whether answered now, on an
    /// earlier launch, or failed, since the alert style may have changed.
    var onAuthorizationResolved: () -> Void = {}

    /// The alert of the ringing alarm.
    private struct CurrentAlert {
        let requestID: String
        /// Kept to show the same alert again after a click removes it.
        let body: String
    }

    struct Timing {
        /// A swipe stops the ringing the detector's `goneThreshold` plus up to one interval
        /// after the alert leaves the screen. Well below the detector's `maxSampleGap`, which
        /// would otherwise ignore every gap. A check took about 1 ms with 24 windows on
        /// screen when measured, 0.3 ms of it CPU.
        var swipeCheckInterval: Duration = .milliseconds(100)
        /// The clicked alert's overlay left about 0.4 s after the click when measured.
        /// Showing the alert again only after that keeps the new alert's overlay its own.
        var reshowDelay: Duration = .seconds(1)
        var swipe = AlertSwipeDetector.Timing()
    }

    private let notificationDelivery: any AlarmNotificationDelivery
    private let alertScreen: any AlertScreen
    private let timing: Timing
    /// Only this alert may present or act on the current alarm.
    private var currentAlert: CurrentAlert?
    private var swipeWatchTask: Task<Void, Never>?
    private var reshowTask: Task<Void, Never>?

    private static let categoryID = "alarm"
    nonisolated static let stopActionID = "stop"
    nonisolated static let repeatActionID = "repeat"

    init(
        notificationDelivery: any AlarmNotificationDelivery = SystemAlarmNotificationDelivery(),
        alertScreen: any AlertScreen = SystemAlertScreen(),
        timing: Timing = Timing()
    ) {
        self.notificationDelivery = notificationDelivery
        self.alertScreen = alertScreen
        self.timing = timing
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
            // Closing the alert, or clearing it in Notification Center, stops the ringing
            // instead of leaving it looping unseen.
            options: [.customDismissAction]
        )
        center.setNotificationCategories([category])

        Task {
            do {
                // The badge is the time left on the Dock icon: macOS has been reported to hide
                // the Dock badge of an app that uses notifications unless it asked for badges.
                let granted = try await center.requestAuthorization(options: [.alert, .badge])
                if !granted {
                    log.notice("Notifications are turned off for Balarm; it will only ring")
                }
            } catch {
                log.error("Notification authorization failed: \(error.localizedDescription, privacy: .public)")
            }
            onAuthorizationResolved()
        }
    }

    func alertStyle() async -> AlarmAlertStyle {
        await notificationDelivery.alertStyle()
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
        currentAlert = CurrentAlert(requestID: requestID, body: body)
        let detector = AlertSwipeDetector(
            postedAt: .now,
            isOverlayAlreadyOnScreen: alertScreen.sample().isOverlayOnScreen,
            timing: timing.swipe
        )
        // Started first, so a failure that `add` reports right away can still end it.
        watchForSwipe(of: requestID, with: detector)
        let request = UNNotificationRequest(identifier: requestID, content: content, trigger: nil)
        notificationDelivery.add(request) { [weak self] error in
            if let error {
                log.error("Cannot show the alarm notification: \(error.localizedDescription, privacy: .public)")
                self?.stopWatching(requestID)
                return
            }
            self?.withdrawIfStale(requestID)
        }
    }

    func withdraw() {
        guard let currentAlert else { return }
        self.currentAlert = nil
        swipeWatchTask?.cancel()
        reshowTask?.cancel()
        removeAlert(currentAlert.requestID)
    }

    /// Adding the request is asynchronous, so an alarm stopped right at 0:00 is withdrawn
    /// before its alert exists; remove the alert again once the request has been added.
    private func withdrawIfStale(_ requestID: String) {
        guard currentAlert?.requestID != requestID else { return }
        removeAlert(requestID)
    }

    /// Without the alert on screen, an overlay that comes up is another notification's.
    private func stopWatching(_ requestID: String) {
        guard currentAlert?.requestID == requestID else { return }
        swipeWatchTask?.cancel()
    }

    /// Swiping the alert away reaches Balarm neither as a response nor as a removal, since
    /// it only moves the alert into Notification Center, so the screen is watched instead.
    private func watchForSwipe(of requestID: String, with detector: AlertSwipeDetector) {
        swipeWatchTask?.cancel()
        swipeWatchTask = Task { [weak self, notificationDelivery, alertScreen, timing] in
            guard await notificationDelivery.alertStyle() == .persistent else { return }
            var detector = detector
            while !Task.isCancelled {
                guard self != nil else { return }
                switch detector.observe(alertScreen.sample(), at: .now) {
                case .watching:
                    break
                case .gaveUp:
                    return
                case .swiped:
                    // The style may have changed during the ring; a temporary banner leaves
                    // by itself.
                    guard await notificationDelivery.alertStyle() == .persistent else { return }
                    guard !Task.isCancelled else { return }
                    self?.alertWasSwiped(requestID)
                    return
                }
                try? await Task.sleep(for: timing.swipeCheckInterval)
            }
        }
    }

    /// A swipe dismisses the alert just like its close button.
    private func alertWasSwiped(_ requestID: String) {
        guard currentAlert?.requestID == requestID else { return }
        withdraw()
        onStop()
    }

    private func reshow(_ requestID: String) {
        guard let currentAlert else { return }
        guard currentAlert.requestID == requestID else { return }
        post(body: currentAlert.body)
    }

    /// Removes the request whether it is still waiting to be shown or already on screen:
    /// `add`'s completion does not say which of the two it is in.
    private func removeAlert(_ requestID: String) {
        notificationDelivery.removePending([requestID])
        notificationDelivery.removeDelivered([requestID])
    }

    func presentationOptions(for requestID: String) -> UNNotificationPresentationOptions {
        // A withdrawn request may still reach the delegate while add is in flight.
        guard currentAlert?.requestID == requestID else { return [] }
        // Shown even while Balarm is frontmost, since the alert carries the Stop/Repeat actions.
        return [.banner, .list]
    }

    func handleResponse(actionID: String, requestID: String) {
        // Showing the alarm is harmless even for the alert of an earlier alarm.
        if actionID == UNNotificationDefaultActionIdentifier { onOpen() }
        guard let currentAlert else { return }
        guard currentAlert.requestID == requestID else { return }
        switch actionID {
        case Self.stopActionID, UNNotificationDismissActionIdentifier:
            withdraw()
            onStop()
        case Self.repeatActionID:
            withdraw()
            onRepeat()
        case UNNotificationDefaultActionIdentifier:
            // Clicking the alert removes it, but the alarm rings on until stopped. Its
            // overlay leaving now is the click, not a swipe.
            swipeWatchTask?.cancel()
            reshowTask?.cancel()
            reshowTask = Task { [weak self, timing] in
                try? await Task.sleep(for: timing.reshowDelay)
                guard !Task.isCancelled else { return }
                self?.reshow(requestID)
            }
        default:
            break
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

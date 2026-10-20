import UserNotifications

/// The `UNUserNotificationCenter` calls that `AlarmNotifier` makes, behind a protocol so
/// tests can decide when `add` completes: a late completion is what leaves a stale alert.
@MainActor
protocol AlarmNotificationDelivery {
    func add(
        _ request: UNNotificationRequest,
        completion: @escaping @MainActor @Sendable ((any Error)?) -> Void
    )
    func removePending(_ identifiers: [String])
    func removeDelivered(_ identifiers: [String])
    /// Whether Balarm's alerts are allowed and stay on screen until acted on, a style only
    /// the user can choose.
    func showsPersistentAlerts() async -> Bool
}

@MainActor
struct SystemAlarmNotificationDelivery: AlarmNotificationDelivery {
    private let center = UNUserNotificationCenter.current()

    func add(
        _ request: UNNotificationRequest,
        completion: @escaping @MainActor @Sendable ((any Error)?) -> Void
    ) {
        center.add(request) { error in
            Task { @MainActor in completion(error) }
        }
    }

    func removePending(_ identifiers: [String]) {
        center.removePendingNotificationRequests(withIdentifiers: identifiers)
    }

    func removeDelivered(_ identifiers: [String]) {
        center.removeDeliveredNotifications(withIdentifiers: identifiers)
    }

    func showsPersistentAlerts() async -> Bool {
        let settings = await center.notificationSettings()
        guard settings.authorizationStatus == .authorized else { return false }
        guard settings.alertSetting == .enabled else { return false }
        return settings.alertStyle == .alert
    }
}

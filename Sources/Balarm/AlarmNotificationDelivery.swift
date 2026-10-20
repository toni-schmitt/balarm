import UserNotifications

/// How macOS shows Balarm's alerts, which only the user can choose.
enum AlarmAlertStyle {
    /// Not asked yet: the first launch asks before any alert can show.
    case notAsked
    /// Stays on screen until acted on, which the alarm's alert needs.
    case persistent
    /// Leaves the screen after a few seconds while the alarm rings on.
    case temporary
    /// No alert shows; the tone still rings.
    case off

    init(
        authorizationStatus: UNAuthorizationStatus,
        alertSetting: UNNotificationSetting,
        alertStyle: UNAlertStyle
    ) {
        guard authorizationStatus != .notDetermined else {
            self = .notAsked
            return
        }
        // Provisional authorization only delivers quietly to Notification Center.
        guard authorizationStatus == .authorized else {
            self = .off
            return
        }
        guard alertSetting == .enabled else {
            self = .off
            return
        }
        switch alertStyle {
        case .alert: self = .persistent
        case .banner: self = .temporary
        case .none: self = .off
        @unknown default: self = .off
        }
    }
}

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
    func alertStyle() async -> AlarmAlertStyle
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

    func alertStyle() async -> AlarmAlertStyle {
        let settings = await center.notificationSettings()
        return AlarmAlertStyle(
            authorizationStatus: settings.authorizationStatus,
            alertSetting: settings.alertSetting,
            alertStyle: settings.alertStyle
        )
    }
}

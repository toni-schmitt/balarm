import Testing
import UserNotifications
@testable import Balarm

@Suite struct AlarmAlertStyleTests {
    @Test(arguments: [
        (UNAlertStyle.alert, AlarmAlertStyle.persistent),
        (.banner, .temporary),
        (.none, .off),
    ])
    func anAllowedAlertStyleMaps(alertStyle: UNAlertStyle, expected: AlarmAlertStyle) {
        #expect(AlarmAlertStyle(authorizationStatus: .authorized, alertSetting: .enabled, alertStyle: alertStyle) == expected)
    }

    @Test func notAskedYetIsItsOwnStyle() {
        #expect(AlarmAlertStyle(authorizationStatus: .notDetermined, alertSetting: .notSupported, alertStyle: .none) == .notAsked)
    }

    @Test(arguments: [UNAuthorizationStatus.denied, .provisional])
    func withoutFullAuthorizationAlertsAreOff(status: UNAuthorizationStatus) {
        #expect(AlarmAlertStyle(authorizationStatus: status, alertSetting: .enabled, alertStyle: .alert) == .off)
    }

    @Test(arguments: [UNNotificationSetting.disabled, .notSupported])
    func disabledAlertsAreOff(setting: UNNotificationSetting) {
        #expect(AlarmAlertStyle(authorizationStatus: .authorized, alertSetting: setting, alertStyle: .alert) == .off)
    }
}

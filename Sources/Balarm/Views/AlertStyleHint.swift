import SwiftUI

/// Shown while the alarm's alert cannot stay on screen until the alarm is stopped, nor stop it
/// when swiped away: Balarm's alerts are temporary or turned off, which only the user can
/// change.
struct AlertStyleHint: View {
    private let message: String
    private let onOpenSettings: () -> Void
    @Environment(\.openURL) private var openURL

    /// With an app's bundle ID as `id`, this pane ID opened that app's own page according to a
    /// report for macOS 27.2; on other versions it may open the Notifications list instead.
    private static let notificationSettings = "x-apple.systempreferences:com.apple.preference.notifications"

    /// `nil` when the style needs no hint.
    init?(style: AlarmAlertStyle, onOpenSettings: @escaping () -> Void) {
        switch style {
        case .notAsked, .persistent:
            return nil
        case .temporary:
            message = "Set alerts to Persistent to keep the alarm's alert on screen."
        case .off:
            message = "Alarm alerts are off, so only the tone rings."
        }
        self.onOpenSettings = onOpenSettings
    }

    var body: some View {
        VStack(spacing: 2) {
            Text(message)
                .foregroundStyle(.secondary)
            Button("Open Notification Settings", action: openSettings)
                .buttonStyle(.link)
                .help("Opens Balarm's notifications in System Settings")
        }
        .font(.callout)
        .multilineTextAlignment(.center)
        // Wraps instead of widening the window, whose width the dial sets.
        .frame(maxWidth: ringDiameter)
        .fixedSize(horizontal: false, vertical: true)
    }

    private func openSettings() {
        let appQuery = Bundle.main.bundleIdentifier.map { "?id=\($0)" } ?? ""
        guard let url = URL(string: Self.notificationSettings + appQuery) else { return }
        onOpenSettings()
        openURL(url)
    }
}

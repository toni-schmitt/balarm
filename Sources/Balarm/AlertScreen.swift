import AppKit
import BalarmCore

/// The screen and input as `AlertSwipeDetector` needs them, behind a protocol so tests can
/// play back what the screen showed.
@MainActor
protocol AlertScreen {
    func sample() -> AlertSwipeDetector.Sample
}

/// Notification Center draws every notification on screen into one full-screen overlay
/// window. Apps can see that the window is on screen, but not its contents.
@MainActor
struct SystemAlertScreen: AlertScreen {
    private static let notificationCenterID = "com.apple.notificationcenterui"
    private static let screenSaverID = "com.apple.ScreenSaver.Engine"

    func sample() -> AlertSwipeDetector.Sample {
        let owner = NSRunningApplication.runningApplications(withBundleIdentifier: Self.notificationCenterID)
            .first?.processIdentifier
        return AlertSwipeDetector.Sample(
            isOverlayOnScreen: owner.map(isOverlayOnScreen(ownedBy:)) ?? false,
            isScreenInUse: isScreenInUse(),
            secondsSinceScroll: secondsSinceLast(.scrollWheel),
            secondsSinceDrag: secondsSinceLast(.leftMouseDragged),
            overlayOwner: owner
        )
    }

    /// A value below 0 would read as a gesture just now, so it counts as never.
    private func secondsSinceLast(_ eventType: CGEventType) -> Double {
        let seconds = CGEventSource.secondsSinceLastEventType(.hidSystemState, eventType: eventType)
        return seconds >= 0 ? seconds : .infinity
    }

    private func isOverlayOnScreen(ownedBy owner: pid_t) -> Bool {
        let options: CGWindowListOption = [.optionOnScreenOnly, .excludeDesktopElements]
        let windows = CGWindowListCopyWindowInfo(options, kCGNullWindowID) as? [[String: Any]] ?? []
        return windows.contains { window in
            guard window[kCGWindowOwnerPID as String] as? pid_t == owner else { return false }
            // The overlay was measured at level 21, above the normal window level of 0.
            let layer = window[kCGWindowLayer as String] as? Int ?? 0
            return layer > 0
        }
    }

    private func isScreenInUse() -> Bool {
        let session = CGSessionCopyCurrentDictionary() as? [String: Any] ?? [:]
        guard session[kCGSessionOnConsoleKey as String] as? Bool ?? false else { return false }
        // Not a documented key, but the one macOS sets while the screen is locked.
        guard !(session["CGSSessionScreenIsLocked"] as? Bool ?? false) else { return false }
        guard CGDisplayIsAsleep(CGMainDisplayID()) == 0 else { return false }
        return NSRunningApplication.runningApplications(withBundleIdentifier: Self.screenSaverID).isEmpty
    }
}

import AppKit
import BalarmCore
import SwiftUI

@main
struct BalarmApp: App {
    @NSApplicationDelegateAdaptor private var appDelegate: AppDelegate

    init() {
        // When System Settings keeps windows on quitting, macOS reopens only the windows open
        // at the time, so after quitting with the window closed, the next launch showed none.
        // `.defaultLaunchBehavior(.presented)` did not change that, and
        // `.restorationBehavior(.disabled)` showed no window even after quitting with it open.
        // The undocumented setting to ignore saved state does: nothing else is worth restoring,
        // since quitting cancels the alarm and the window's position is saved apart from it.
        UserDefaults.standard.register(defaults: ["ApplePersistenceIgnoreState": true])
    }

    var body: some Scene {
        Window("Balarm", id: AlarmView.windowID) {
            AlarmView(controller: appDelegate.controller)
                .background(AlarmKeyboard(onKey: appDelegate.controller.handle))
                // SwiftUI opens the window again with the same views, so only their appearing
                // tells that it opened.
                .onAppear(perform: appDelegate.controller.windowDidOpen)
                .background(AlarmWindowTracker(
                    onVisibilityChange: appDelegate.controller.windowDidChangeVisibility,
                    onClose: appDelegate.controller.windowDidClose
                ))
                .containerBackground(.thinMaterial, for: .window)
        }
        .windowStyle(.hiddenTitleBar)
        .windowResizability(.contentSize)
        .windowBackgroundDragBehavior(.enabled)
        .defaultPosition(.center)
    }
}

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    let controller = AlarmController()
    private var statusDisplay: AlarmStatusDisplay?
    private var lifetimeTask: Task<Void, Never>?

    /// Notification Center removes the alert on a background thread after the request returns,
    /// as `removeDeliveredNotifications` documents, which quitting right after the alarm ends
    /// could cut short.
    private static let quitDelay: Duration = .milliseconds(500)

    func applicationDidFinishLaunching(_ notification: Notification) {
        statusDisplay = AlarmStatusDisplay(controller: controller)
        lifetimeTask = Task { [controller] in
            var lifetime = AppLifetime()
            let states = Observations { (hasAlarm: controller.countdown != nil, isWindowOpen: controller.isWindowOpen) }
            for await state in states {
                guard lifetime.shouldQuit(hasAlarm: state.hasAlarm, isWindowOpen: state.isWindowOpen) else { continue }
                try? await Task.sleep(for: Self.quitDelay)
                // The window may have been opened again meanwhile, from the Dock or the alert.
                let isWindowOpen = controller.isWindowOpen
                guard lifetime.shouldQuit(hasAlarm: controller.countdown != nil, isWindowOpen: isWindowOpen) else { continue }
                NSApp.terminate(nil)
            }
        }
    }

    // `AppLifetime` decides, also whether closing the window quits.
    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        false
    }

    // The window's own `openWindow` also restores it from the Dock or reopens it after it was
    // closed; until the window has provided it, AppKit's default reopening applies.
    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        guard controller.openWindow != nil else { return true }
        controller.showWindow()
        return false
    }

    // Quitting cancels a running alarm. The Dock badge follows the alarm asynchronously, too
    // late once Balarm exits, so it is cleared here.
    func applicationWillTerminate(_ notification: Notification) {
        controller.stop()
        NSApp.dockTile.badgeLabel = nil
    }
}

import AppKit
import SwiftUI

@main
struct BalarmApp: App {
    @NSApplicationDelegateAdaptor private var appDelegate: AppDelegate

    var body: some Scene {
        Window("Balarm", id: AlarmView.windowID) {
            AlarmView(controller: appDelegate.controller)
                .background(AlarmKeyboard(onKey: appDelegate.controller.handle))
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

    // The window is the alarm: closing it quits, and quitting cancels the alarm.
    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        true
    }

    func applicationWillTerminate(_ notification: Notification) {
        controller.stop()
    }
}

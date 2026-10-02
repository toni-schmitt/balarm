import AppKit
import SwiftUI

@main
struct BalarmApp: App {
    @NSApplicationDelegateAdaptor private var appDelegate: AppDelegate

    var body: some Scene {
        Window("Balarm", id: "main") {
            AlarmView(controller: appDelegate.controller)
                .containerBackground(.thinMaterial, for: .window)
        }
        .windowStyle(.hiddenTitleBar)
        .windowResizability(.contentSize)
        .windowBackgroundDragBehavior(.enabled)
        .defaultPosition(.center)
        .commands {
            TypingAnimationCommands()
        }
    }
}

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    let controller = AlarmController()
    private var keyMonitor: Any?

    func applicationDidFinishLaunching(_ notification: Notification) {
        // An app-wide key monitor instead of SwiftUI focus: typing must work the moment
        // the window appears, without first clicking into it.
        keyMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [controller] event in
            guard let key = AlarmKey(event) else { return event }
            // A held Return would otherwise stop the ringing and then restart the alarm.
            guard !event.isARepeat || key.isRepeatable else { return nil }
            return controller.handle(key) ? nil : event
        }
    }

    // The window is the alarm: closing it quits, and quitting cancels the alarm.
    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        true
    }

    func applicationWillTerminate(_ notification: Notification) {
        controller.stop()
    }
}

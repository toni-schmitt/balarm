import BalarmCore
import SwiftUI

struct AlarmView: View {
    static let windowID = "main"

    @Bindable var controller: AlarmController
    @Environment(\.openWindow) private var openWindow

    var body: some View {
        VStack(spacing: 0) {
            if let countdown = controller.countdown {
                CountdownView(countdown: countdown, controller: controller)
            } else {
                EntryView(
                    entry: controller.entry,
                    onStart: controller.startFromEntry,
                    onEdit: controller.setEntry
                )
            }
            if let hint = AlertStyleHint(
                style: controller.alertStyle,
                onOpenSettings: controller.followAlertStyleChanges
            ) {
                hint.padding(.bottom, 20)
            }
        }
        .onAppear {
            let openAlarmWindow = openWindow
            controller.openWindow = { openAlarmWindow(id: Self.windowID) }
        }
        .alert("Restart the alarm?", isPresented: $controller.isConfirmingRestart) {
            Button("Restart", action: controller.repeatAlarm)
                .keyboardShortcut(.defaultAction)
            // Not "Cancel": next to a running alarm, that word means cancelling the alarm itself.
            Button("Don't Restart", role: .cancel) {}
        } message: {
            if let countdown = controller.countdown {
                Text("It starts over at \(DurationText.words(seconds: countdown.totalSeconds)).")
            }
        }
    }
}

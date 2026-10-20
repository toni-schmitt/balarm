import BalarmCore
import SwiftUI

struct AlarmView: View {
    @Bindable var controller: AlarmController

    var body: some View {
        Group {
            if let countdown = controller.countdown {
                CountdownView(countdown: countdown, controller: controller)
            } else {
                EntryView(
                    entry: controller.entry,
                    onStart: controller.startFromEntry,
                    onEdit: controller.setEntry
                )
            }
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

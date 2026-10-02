import SwiftUI

struct AlarmView: View {
    let controller: AlarmController

    var body: some View {
        if let countdown = controller.countdown {
            CountdownView(countdown: countdown, controller: controller)
        } else {
            EntryView(entry: controller.entry, onStart: controller.startFromEntry)
        }
    }
}

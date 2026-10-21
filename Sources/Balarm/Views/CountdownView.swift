import BalarmCore
import SwiftUI

struct CountdownView: View {
    let countdown: Countdown
    let controller: AlarmController

    var body: some View {
        AlarmScreen(header: DurationText.words(seconds: countdown.totalSeconds)) {
            // SwiftUI keeps redrawing the timeline while the window is closed or hidden.
            let isPaused = !countdown.isRunning || !controller.isWindowVisible
            TimelineView(.animation(minimumInterval: frameInterval, paused: isPaused)) { _ in
                dial(at: .now)
            }
        } buttons: {
            buttons
        }
    }

    /// Redraws about once per device pixel the arc travels, so a short countdown sweeps
    /// smoothly at 60 fps while a long one is not redrawn needlessly. The 0.1 s cap keeps
    /// the seconds display from visibly lagging behind the clock.
    private var frameInterval: Double {
        let ringPixels = Double.pi * ringDiameter * 2  // Retina: two pixels per point
        let secondsPerPixel = Double(countdown.totalSeconds) / ringPixels
        return min(0.1, max(1.0 / 60, secondsPerPixel))
    }

    private func dial(at now: ContinuousClock.Instant) -> some View {
        let secondsLeft = countdown.displaySeconds(at: now)
        let endTime = Date.now.addingTimeInterval(countdown.remaining(at: now) / .seconds(1))

        return Dial(
            ring: ProgressRing(
                fraction: countdown.isRinging ? 1 : countdown.fractionRemaining(at: now),
                isDimmed: countdown.isPaused,
                isPulsing: countdown.isRinging
            )
        ) {
            VStack(spacing: 6) {
                Text(DurationText.clock(seconds: secondsLeft))
                    .font(.system(size: 50, weight: .light).monospacedDigit())
                    .lineLimit(1)
                    .minimumScaleFactor(0.5)
                    .contentTransition(.numericText(countsDown: true))
                    .animation(.snappy, value: secondsLeft)
                status(endTime: endTime)
                    .font(.callout)
            }
        }
    }

    @ViewBuilder
    private func status(endTime: Date) -> some View {
        if countdown.isRinging {
            Image(systemName: "bell.fill")
                .foregroundStyle(Color.accentColor)
                .symbolEffect(.wiggle, options: .repeat(.continuous))
        } else if countdown.isPaused {
            Text("Paused")
                .foregroundStyle(.tertiary)
        } else {
            Label {
                Text(endTime, format: .dateTime.hour().minute())
            } icon: {
                Image(systemName: "bell.fill")
            }
            .foregroundStyle(.secondary)
        }
    }

    @ViewBuilder
    private var buttons: some View {
        if countdown.isRinging {
            Button("Repeat", systemImage: "arrow.clockwise", action: controller.repeatAlarm)
                .buttonStyle(.glass)
                .help("Repeat (R)")
            Button("Stop", systemImage: "stop.fill", action: controller.stop)
                .buttonStyle(.glassProminent)
                .help("Stop (⏎ or Esc)")
        } else {
            Button("Cancel", systemImage: "xmark", action: controller.stop)
                .buttonStyle(.glass)
                .help("Cancel (Esc)")
            Button("Restart", systemImage: "arrow.clockwise", action: controller.requestRestart)
                .buttonStyle(.glass)
                .help("Restart (R)")
            Button(
                countdown.isPaused ? "Resume" : "Pause",
                systemImage: countdown.isPaused ? "play.fill" : "pause.fill",
                action: controller.togglePause
            )
            .buttonStyle(.glassProminent)
            .help(countdown.isPaused ? "Resume (Space)" : "Pause (Space)")
        }
    }
}

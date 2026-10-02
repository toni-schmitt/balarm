import SwiftUI

/// Clock.app-style ring: the arc is the time left and empties clockwise from 12 o'clock.
struct ProgressRing: View {
    /// Fraction of time left, 0...1.
    var fraction: Double
    var isDimmed = false
    var isPulsing = false

    private let lineWidth: CGFloat = 8

    var body: some View {
        ZStack {
            Circle()
                .stroke(.quaternary, lineWidth: lineWidth)

            if fraction > 0 {
                Circle()
                    .trim(from: 1 - fraction, to: 1)
                    .stroke(Color.accentColor, style: StrokeStyle(lineWidth: lineWidth, lineCap: .round))
                    .rotationEffect(.degrees(-90))
                    .opacity(isDimmed ? 0.4 : 1)
                    .modifier(Pulse(isActive: isPulsing))
            }
        }
        .padding(lineWidth / 2)
        .animation(.easeInOut(duration: 0.25), value: isDimmed)
    }
}

/// Fades in and out continuously while active; inactive, it adds no animation work.
private struct Pulse: ViewModifier {
    var isActive: Bool

    func body(content: Content) -> some View {
        if isActive {
            content.phaseAnimator([1.0, 0.3]) { view, opacity in
                view.opacity(opacity)
            } animation: { _ in
                .easeInOut(duration: 0.7)
            }
        } else {
            content
        }
    }
}

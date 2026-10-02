import SwiftUI

let ringDiameter: CGFloat = 220

/// The layout every state shares — header, dial, buttons — so switching between
/// typing, counting down and ringing never moves anything on screen.
struct AlarmScreen<DialContent: View, Buttons: View>: View {
    var header: String
    var isHeaderPlaceholder = false
    @ViewBuilder var dial: DialContent
    @ViewBuilder var buttons: Buttons

    var body: some View {
        VStack(spacing: 22) {
            Text(header)
                .font(.headline)
                .foregroundStyle(isHeaderPlaceholder ? .tertiary : .secondary)
                .lineLimit(1)
                .contentTransition(.numericText())

            dial
                .frame(width: ringDiameter, height: ringDiameter)

            HStack(spacing: 44) {
                buttons
            }
            .labelStyle(.iconOnly)
            .buttonBorderShape(.circle)
            .controlSize(.extraLarge)
            .frame(height: 52)
        }
        .padding(.horizontal, 40)
        .padding(.top, 2)
        .padding(.bottom, 30)
        .animation(.snappy(duration: 0.25), value: header)
    }
}

/// The ring with a readout centered inside it.
struct Dial<Center: View>: View {
    var ring: ProgressRing
    @ViewBuilder var center: Center

    var body: some View {
        ZStack {
            ring
            center
                .frame(maxWidth: ringDiameter - 44)
        }
    }
}

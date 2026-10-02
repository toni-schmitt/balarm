import BalarmCore
import SwiftUI

struct EntryView: View {
    let entry: DurationEntry
    let onStart: () -> Void

    var body: some View {
        AlarmScreen(
            header: entry.totalSeconds > 0 ? DurationText.words(seconds: entry.totalSeconds) : "Type a duration",
            isHeaderPlaceholder: entry.totalSeconds == 0
        ) {
            Dial(ring: ProgressRing(fraction: 0)) {
                VStack(spacing: 8) {
                    EntryDigits(entry: entry)
                    Text("⏎ to start")
                        .font(.callout)
                        .foregroundStyle(.tertiary)
                        .opacity(entry.totalSeconds > 0 ? 1 : 0)
                }
            }
        } buttons: {
            Button("Start", systemImage: "play.fill", action: onStart)
                .buttonStyle(.glassProminent)
                .disabled(entry.totalSeconds == 0)
                .help("Start (⏎)")
        }
    }
}

private let digitFontSize: CGFloat = 38

/// `hh:mm:ss` with typed digits bright, a remembered duration dimmed,
/// and the zeros that only pad the display faint.
///
/// Every keystroke shifts all digits one place, and rolling each changed position smears
/// the whole display. So only the newest digit, always in the last position, rolls in;
/// the shifted digits change in place.
private struct EntryDigits: View {
    let entry: DurationEntry

    var body: some View {
        let padding = DurationEntry.maxDigits - entry.digits.count
        HStack(spacing: 0) {
            ForEach(Array(entry.paddedDigits.enumerated()), id: \.offset) { slot, digit in
                if slot == 2 || slot == 4 {
                    Text(":").foregroundStyle(style(isPadding: slot < padding))
                }
                if slot == DurationEntry.maxDigits - 1 {
                    // A new identity per keystroke, so the digit rolls in even when it
                    // repeats the one before it.
                    ZStack {
                        Text(String(digit))
                            .foregroundStyle(style(isPadding: slot < padding))
                            .id(entry)
                            .transition(.roll)
                    }
                } else {
                    Text(String(digit))
                        .foregroundStyle(style(isPadding: slot < padding))
                        .contentTransition(.identity)
                }
            }
        }
        .font(.system(size: digitFontSize, weight: .light).monospacedDigit())
        .lineLimit(1)
        .animation(.snappy(duration: 0.12), value: entry)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(entry.totalSeconds > 0 ? DurationText.words(seconds: entry.totalSeconds) : "No duration")
    }

    private func style(isPadding: Bool) -> HierarchicalShapeStyle {
        if isPadding { return .tertiary }
        return entry.isPrefilled ? .secondary : .primary
    }
}

/// The newest digit rises into place while the one it replaces rises out, both briefly
/// blurred, like a counter ticking over.
private struct Roll: ViewModifier {
    /// 1 is below its place (arriving), 0 in place, -1 above (leaving).
    var position: CGFloat

    func body(content: Content) -> some View {
        content
            .offset(y: position * digitFontSize / 2)
            .blur(radius: abs(position) * 3)
            .opacity(1 - abs(position))
    }
}

private extension AnyTransition {
    static var roll: AnyTransition {
        .asymmetric(
            insertion: .modifier(active: Roll(position: 1), identity: Roll(position: 0)),
            removal: .modifier(active: Roll(position: -1), identity: Roll(position: 0))
        )
    }
}

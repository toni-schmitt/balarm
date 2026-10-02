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
/// the whole display. So only the position that lights up rolls in (typing) or the one
/// that goes dark rolls back (deleting); the other digits change in place.
private struct EntryDigits: View {
    let entry: DurationEntry

    var body: some View {
        let padding = DurationEntry.maxDigits - entry.digits.count
        HStack(spacing: 0) {
            ForEach(Array(entry.paddedDigits.enumerated()), id: \.offset) { slot, digit in
                if slot == 2 || slot == 4 {
                    Text(":").foregroundStyle(style(isPadding: slot < padding))
                }
                // A remembered duration counts as dark, so typing over it rolls in only
                // the typed digit.
                let isLit = slot >= padding && !entry.isPrefilled
                ZStack {
                    Text(String(digit))
                        .foregroundStyle(style(isPadding: slot < padding))
                        .contentTransition(.identity)
                        // A new identity only when the position lights up or goes dark,
                        // which is what makes exactly that position roll.
                        .id(isLit)
                        .transition(.roll(isLit: isLit))
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

/// A digit rolling through its position, briefly blurred, like a counter ticking over.
private struct Roll: ViewModifier {
    /// 1 is below its place, 0 in place, -1 above.
    var position: CGFloat

    func body(content: Content) -> some View {
        content
            .offset(y: position * digitFontSize / 2)
            .blur(radius: abs(position) * 3)
            .opacity(1 - abs(position))
    }
}

private extension AnyTransition {
    /// Lighting up rolls upward: the dark digit leaves above, the lit one arrives from below.
    /// Going dark reverses it, so a lit digit leaves below and a dark one arrives from above.
    static func roll(isLit: Bool) -> AnyTransition {
        .modifier(active: Roll(position: isLit ? 1 : -1), identity: Roll(position: 0))
    }
}

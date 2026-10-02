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

/// `hh:mm:ss` with typed digits bright, a remembered duration dimmed,
/// and the zeros that only pad the display faint.
private struct EntryDigits: View {
    let entry: DurationEntry

    var body: some View {
        let padding = DurationEntry.maxDigits - entry.digits.count
        HStack(spacing: 0) {
            ForEach(Array(entry.paddedDigits.enumerated()), id: \.offset) { index, digit in
                if index == 2 || index == 4 {
                    Text(":").foregroundStyle(style(isPadding: index < padding))
                }
                Text(String(digit))
                    .foregroundStyle(style(isPadding: index < padding))
                    .contentTransition(.numericText())
            }
        }
        .font(.system(size: 38, weight: .light).monospacedDigit())
        .lineLimit(1)
        .animation(.snappy(duration: 0.2), value: entry)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(entry.totalSeconds > 0 ? DurationText.words(seconds: entry.totalSeconds) : "No duration")
    }

    private func style(isPadding: Bool) -> HierarchicalShapeStyle {
        if isPadding { return .tertiary }
        return entry.isPrefilled ? .secondary : .primary
    }
}

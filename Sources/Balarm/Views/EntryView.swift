import AppKit
import BalarmCore
import SwiftUI

struct EntryView: View {
    let entry: DurationEntry
    let onStart: () -> Void

    @AppStorage(TypingAnimation.storageKey) private var typingAnimation = TypingAnimation.slide

    var body: some View {
        AlarmScreen(
            header: entry.totalSeconds > 0 ? DurationText.words(seconds: entry.totalSeconds) : "Type a duration",
            isHeaderPlaceholder: entry.totalSeconds == 0
        ) {
            Dial(ring: ProgressRing(fraction: 0)) {
                VStack(spacing: 8) {
                    digits
                        .font(.system(size: DigitMetrics.fontSize, weight: .light).monospacedDigit())
                        .lineLimit(1)
                        .accessibilityElement(children: .ignore)
                        .accessibilityLabel(
                            entry.totalSeconds > 0 ? DurationText.words(seconds: entry.totalSeconds) : "No duration"
                        )
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

    @ViewBuilder
    private var digits: some View {
        switch typingAnimation {
        case .slide: SlidingDigits(entry: entry)
        case .roll: PositionalDigits(entry: entry, transition: .numericText(), animation: .snappy(duration: 0.12))
        case .crossfade: PositionalDigits(entry: entry, transition: .opacity, animation: .easeOut(duration: 0.15))
        }
    }
}

/// Typed digits bright, a remembered duration dimmed, and the zeros that only pad the display faint.
private func digitStyle(isPadding: Bool, entry: DurationEntry) -> HierarchicalShapeStyle {
    if isPadding { return .tertiary }
    return entry.isPrefilled ? .secondary : .primary
}

/// Each of the six positions keeps its place and changes its value; every keystroke shifts
/// all typed digits, so every typed position transitions at once.
private struct PositionalDigits: View {
    let entry: DurationEntry
    let transition: ContentTransition
    let animation: Animation

    var body: some View {
        let padding = DurationEntry.maxDigits - entry.digits.count
        HStack(spacing: 0) {
            ForEach(Array(entry.paddedDigits.enumerated()), id: \.offset) { slot, digit in
                if slot == 2 || slot == 4 {
                    Text(":").foregroundStyle(digitStyle(isPadding: slot < padding, entry: entry))
                }
                Text(String(digit))
                    .foregroundStyle(digitStyle(isPadding: slot < padding, entry: entry))
                    .contentTransition(transition)
            }
        }
        .animation(animation, value: entry)
    }
}

/// Each typed digit keeps its identity and moves one slot left per keystroke, so typing reads
/// as the display shifting rather than every digit changing.
private struct SlidingDigits: View {
    let entry: DurationEntry

    private struct Glyph: Identifiable {
        let id: String
        let text: String
        let slot: Int
        let isColon: Bool
        let isPadding: Bool
    }

    var body: some View {
        ZStack(alignment: .leading) {
            ForEach(glyphs) { glyph in
                Text(glyph.text)
                    .fixedSize()
                    .frame(width: glyph.isColon ? DigitMetrics.colonWidth : DigitMetrics.digitWidth)
                    .foregroundStyle(digitStyle(isPadding: glyph.isPadding, entry: entry))
                    .offset(x: glyph.isColon ? DigitMetrics.colonX(beforeSlot: glyph.slot) : DigitMetrics.x(ofSlot: glyph.slot))
                    .transition(
                        glyph.isPadding
                            ? .opacity
                            : .opacity.combined(with: .offset(x: DigitMetrics.digitWidth / 2))
                    )
            }
        }
        .frame(width: DigitMetrics.totalWidth, alignment: .leading)
        .animation(.snappy(duration: 0.2), value: entry)
    }

    private var glyphs: [Glyph] {
        let padding = DurationEntry.maxDigits - entry.digits.count
        let pads = (0..<padding).map {
            Glyph(id: "pad-\($0)", text: "0", slot: $0, isColon: false, isPadding: true)
        }
        // Prefilled and typed digits get distinct identities, so replacing a remembered
        // duration fades it out instead of sliding its digits around.
        let prefix = entry.isPrefilled ? "prefilled" : "typed"
        let typed = entry.digits.enumerated().map { index, digit in
            Glyph(id: "\(prefix)-\(index)", text: String(digit), slot: padding + index, isColon: false, isPadding: false)
        }
        let colons = [2, 4].map {
            Glyph(id: "colon-\($0)", text: ":", slot: $0, isColon: true, isPadding: $0 < padding)
        }
        return pads + typed + colons
    }
}

/// Glyph advances of the entry font, so sliding digits land exactly where static text would.
private enum DigitMetrics {
    static let fontSize: CGFloat = 38
    static let digitWidth = advance(of: "0")
    static let colonWidth = advance(of: ":")
    static let totalWidth = digitWidth * CGFloat(DurationEntry.maxDigits) + colonWidth * 2

    /// Slots 0–5 are `h h : m m : s s`; a colon precedes slots 2 and 4.
    static func x(ofSlot slot: Int) -> CGFloat {
        let colonsBefore = slot >= 4 ? 2 : slot >= 2 ? 1 : 0
        return digitWidth * CGFloat(slot) + colonWidth * CGFloat(colonsBefore)
    }

    static func colonX(beforeSlot slot: Int) -> CGFloat {
        x(ofSlot: slot) - colonWidth
    }

    private static func advance(of glyph: String) -> CGFloat {
        let font = NSFont.monospacedDigitSystemFont(ofSize: fontSize, weight: .light)
        return ceil((glyph as NSString).size(withAttributes: [.font: font]).width)
    }
}

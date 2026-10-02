import SwiftUI

/// How typed digits animate into the `hh:mm:ss` display.
enum TypingAnimation: String, CaseIterable, Identifiable {
    /// Digits slide one place left per keystroke, like a microwave display.
    case slide
    /// Every changed digit rolls to its new value.
    case roll
    /// Every changed digit fades to its new value in place.
    case crossfade

    static let storageKey = "typingAnimation"

    var id: Self { self }

    var title: LocalizedStringKey {
        switch self {
        case .slide: "Slide"
        case .roll: "Roll"
        case .crossfade: "Crossfade"
        }
    }
}

/// View › Typing Animation, with ⌘1–⌘3 to compare the styles while typing.
struct TypingAnimationCommands: Commands {
    @AppStorage(TypingAnimation.storageKey) private var selection = TypingAnimation.slide

    var body: some Commands {
        CommandGroup(after: .toolbar) {
            Section("Typing Animation") {
                ForEach(Array(TypingAnimation.allCases.enumerated()), id: \.element) { index, animation in
                    Toggle(animation.title, isOn: isSelected(animation))
                        .keyboardShortcut(KeyEquivalent(Character(String(index + 1))), modifiers: .command)
                }
            }
        }
    }

    private func isSelected(_ animation: TypingAnimation) -> Binding<Bool> {
        Binding {
            selection == animation
        } set: { isOn in
            guard isOn else { return }
            selection = animation
        }
    }
}

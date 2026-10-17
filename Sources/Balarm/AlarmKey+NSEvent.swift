import AppKit
import BalarmCore
import Carbon.HIToolbox

extension AlarmKey {
    init?(_ event: NSEvent) {
        let modifiers = event.modifierFlags.intersection(.deviceIndependentFlagsMask)

        // ⌘. is the system-wide "cancel" chord, the same as Escape.
        if modifiers.contains(.command) {
            guard event.charactersIgnoringModifiers == "." else { return nil }
            self = .escape
            return
        }
        // Shift stays allowed: some layouts (e.g. AZERTY) need it to type digits.
        guard modifiers.isDisjoint(with: [.control, .option]) else { return nil }

        switch Int(event.keyCode) {
        case kVK_Return, kVK_ANSI_KeypadEnter: self = .enter
        case kVK_Delete, kVK_ForwardDelete: self = .delete
        case kVK_Escape, kVK_ANSI_KeypadClear: self = .escape
        case kVK_Space: self = .space
        default:
            guard let character = event.characters?.first else { return nil }
            if character.isASCII, let digit = character.wholeNumberValue {
                self = .digit(digit)
            } else if character.lowercased() == "r" {
                self = .repeatAlarm
            } else {
                return nil
            }
        }
    }
}

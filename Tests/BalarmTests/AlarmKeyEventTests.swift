import AppKit
import BalarmCore
import Carbon.HIToolbox
import Testing
@testable import Balarm

@Suite struct AlarmKeyEventTests {
    typealias KeyPress = (
        keyCode: Int, characters: String, ignoringModifiers: String,
        modifiers: NSEvent.ModifierFlags, expected: AlarmKey?
    )

    private static func press(
        _ keyCode: Int, _ characters: String, ignoringModifiers: String? = nil,
        _ modifiers: NSEvent.ModifierFlags = [], expected: AlarmKey?
    ) -> KeyPress {
        (keyCode, characters, ignoringModifiers ?? characters, modifiers, expected)
    }

    private static let presses: [KeyPress] = [
        press(kVK_Return, "\r", expected: .enter),
        press(kVK_ANSI_KeypadEnter, "\u{3}", expected: .enter),
        press(kVK_Delete, "\u{7F}", expected: .delete),
        press(kVK_ForwardDelete, "\u{F728}", .function, expected: .delete),
        press(kVK_Escape, "\u{1B}", expected: .escape),
        press(kVK_ANSI_KeypadClear, "\u{F739}", expected: .escape),
        press(kVK_Space, " ", expected: .space),
        press(kVK_ANSI_5, "5", expected: .digit(5)),
        press(kVK_ANSI_0, "0", expected: .digit(0)),
        press(kVK_ANSI_Keypad7, "7", .numericPad, expected: .digit(7)),
        // AZERTY types digits with Shift.
        press(kVK_ANSI_1, "1", ignoringModifiers: "&", .shift, expected: .digit(1)),
        press(kVK_ANSI_R, "r", expected: .repeatAlarm),
        press(kVK_ANSI_R, "R", ignoringModifiers: "r", .shift, expected: .repeatAlarm),
        press(kVK_ANSI_Period, ".", .command, expected: .escape),
        // Every other chord is left to the menu and the system.
        press(kVK_ANSI_Q, "q", .command, expected: nil),
        press(kVK_ANSI_R, "r", .command, expected: nil),
        press(kVK_ANSI_5, "∞", ignoringModifiers: "5", .option, expected: nil),
        press(kVK_ANSI_5, "5", .control, expected: nil),
        press(kVK_ANSI_R, "\u{12}", ignoringModifiers: "r", .control, expected: nil),
        // US Shift+1 types "!", not a digit.
        press(kVK_ANSI_1, "!", ignoringModifiers: "1", .shift, expected: nil),
        press(kVK_ANSI_A, "a", expected: nil),
        // Only ASCII digits count, not other scripts' digits.
        press(kVK_ANSI_5, "٥", expected: nil),
    ]

    @Test(arguments: presses)
    func mapsKeyPresses(press: KeyPress) throws {
        let event = try #require(NSEvent.keyEvent(
            with: .keyDown,
            location: .zero,
            modifierFlags: press.modifiers,
            timestamp: 0,
            windowNumber: 0,
            context: nil,
            characters: press.characters,
            charactersIgnoringModifiers: press.ignoringModifiers,
            isARepeat: false,
            keyCode: UInt16(press.keyCode)
        ))
        #expect(AlarmKey(event) == press.expected)
    }
}

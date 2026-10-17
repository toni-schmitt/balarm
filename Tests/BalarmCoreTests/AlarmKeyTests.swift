import Testing
@testable import BalarmCore

@Suite struct AlarmKeyTests {
    @Test(arguments: [AlarmKey.digit(0), .digit(9), .delete])
    func editingKeysRepeatWhileHeld(key: AlarmKey) {
        #expect(key.isRepeatable)
    }

    /// A held Return would otherwise stop the ringing and then restart the alarm.
    @Test(arguments: [AlarmKey.enter, .escape, .space, .repeatAlarm])
    func actionKeysActOncePerPress(key: AlarmKey) {
        #expect(!key.isRepeatable)
    }
}

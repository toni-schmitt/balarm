import AVFoundation
import Testing
@testable import Balarm

@MainActor
@Suite struct RingerTests {
    /// The tone sits in a private framework that a macOS update may move, and the app then rings
    /// with Glass without saying so, so the move shows up here instead.
    @Test func theAlarmToneLoads() throws {
        _ = try AVAudioPlayer(contentsOf: Ringer.toneURL)
    }
}

import AVFoundation
import AppKit
import os

private let log = Logger(subsystem: Bundle.main.bundleIdentifier ?? "Balarm", category: "Ringer")

/// Loops Clock.app's default alarm tone, Radial, until stopped.
///
/// The tone plays from the system's ToneLibrary, so neither the repository nor the app
/// carries Apple's audio.
///
/// When the tone is missing or does not start, the system's Glass sound loops instead:
/// a single beep is too easy to miss for an alarm.
@MainActor
final class Ringer {
    /// Inside a private framework, so a macOS update may move it.
    static let toneURL = URL(
        fileURLWithPath: "/System/Library/PrivateFrameworks/ToneLibrary.framework/Versions/A/Resources/Ringtones/Radial-EncoreInfinitum.m4r"
    )

    private var player: AVAudioPlayer?
    private let fallback: NSSound? = {
        let sound = NSSound(named: "Glass")
        sound?.loops = true
        return sound
    }()

    func start() {
        guard let player = player ?? makePlayer() else {
            startFallback()
            return
        }
        self.player = player
        player.currentTime = 0
        guard player.play() else {
            log.error("The alarm tone did not start playing; ringing with Glass instead")
            startFallback()
            return
        }
    }

    func stop() {
        player?.stop()
        fallback?.stop()
    }

    private func startFallback() {
        guard let fallback else {
            log.error("The Glass system sound is missing; beeping once instead")
            NSSound.beep()
            return
        }
        fallback.currentTime = 0
        guard fallback.play() else {
            log.error("The Glass system sound did not start playing; beeping once instead")
            NSSound.beep()
            return
        }
    }

    private func makePlayer() -> AVAudioPlayer? {
        do {
            let player = try AVAudioPlayer(contentsOf: Self.toneURL)
            player.numberOfLoops = -1
            player.prepareToPlay()
            return player
        } catch {
            log.error("Cannot play \(Self.toneURL.path, privacy: .public): \(error.localizedDescription, privacy: .public)")
            return nil
        }
    }
}

import AVFoundation
import AppKit
import os

private let log = Logger(subsystem: "com.toni.balarm", category: "Ringer")

/// Loops Clock.app's default alarm tone, Radial, until stopped.
///
/// The tone is copied into the bundle by `build.sh` from the system ToneLibrary,
/// so the app plays exactly the sound Clock.app uses without shipping Apple's audio in the repo.
///
/// When the tone is missing or does not start, the system's Glass sound loops instead:
/// a single beep is too easy to miss for an alarm.
@MainActor
final class Ringer {
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
            log.error("Radial.m4a did not start playing; ringing with Glass instead")
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
        guard let url = Bundle.main.url(forResource: "Radial", withExtension: "m4a") else {
            log.error("Radial.m4a is missing from the app bundle; build the app with build.sh")
            return nil
        }
        do {
            let player = try AVAudioPlayer(contentsOf: url)
            player.numberOfLoops = -1
            player.prepareToPlay()
            return player
        } catch {
            log.error("Cannot play \(url.path, privacy: .public): \(error.localizedDescription, privacy: .public)")
            return nil
        }
    }
}

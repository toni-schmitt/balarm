import AVFoundation
import AppKit
import os

private let log = Logger(subsystem: "com.toni.balarm", category: "Ringer")

/// Loops Clock.app's default alarm tone, Radial, until stopped.
///
/// The tone is copied into the bundle by `build.sh` from the system ToneLibrary,
/// so the app plays exactly the sound Clock.app uses without shipping Apple's audio in the repo.
@MainActor
final class Ringer {
    private var player: AVAudioPlayer?

    func start() {
        guard let player = player ?? makePlayer() else {
            NSSound.beep()
            return
        }
        self.player = player
        player.currentTime = 0
        player.play()
    }

    func stop() {
        player?.stop()
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

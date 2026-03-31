import AVFoundation

class SoundPlayer {
    static let shared = SoundPlayer()
    private var player: AVAudioPlayer?

    private init() {
        do {
            try AVAudioSession.sharedInstance().setCategory(.playback, mode: .default, options: .mixWithOthers)
            try AVAudioSession.sharedInstance().setActive(true)
        } catch {
            print("[SoundPlayer] Audio session error: \(error)")
        }

        guard let url = Bundle.main.url(forResource: "ping", withExtension: "mp3") else {
            print("[SoundPlayer] ERROR: ping.mp3 not found in bundle")
            return
        }

        do {
            player = try AVAudioPlayer(contentsOf: url)
            player?.volume = 1.0
            player?.prepareToPlay()
        } catch {
            print("[SoundPlayer] Player init error: \(error)")
        }
    }

    func play() {
        guard let player else { return }
        player.currentTime = 0
        player.play()
    }
}

import AVFoundation
import Foundation

final class SoundPlayer {
    static let shared = SoundPlayer()

    /// Kalıcı sessize alma; UserDefaults "soundMuted" anahtarında saklanır.
    /// Müzik susturulurken durmaz (ses açılınca kaldığı yerden sürer).
    var isMuted: Bool = UserDefaults.standard.bool(forKey: "soundMuted") {
        didSet {
            UserDefaults.standard.set(isMuted, forKey: "soundMuted")
            musicPlayer?.volume = isMuted ? 0 : SoundPlayer.musicVolume
            ambientPlayer?.volume = isMuted ? 0 : ambientVolume
        }
    }

    private static let musicVolume: Float = 0.35

    private var players: [String: AVAudioPlayer] = [:]
    private var lastPlayed: [String: TimeInterval] = [:]
    private var musicPlayer: AVAudioPlayer?
    /// Şu an dönen müzik parçasının adı (test/teşhis ve yinelenen çağrı koruması için).
    private(set) var currentMusic: String?
    /// Ambiyans kanalı (V3): müzikten BAĞIMSIZ ikinci döngü (orman/cırcır/zindan/bataklık).
    private var ambientPlayer: AVAudioPlayer?
    private var ambientVolume: Float = 0.35
    private(set) var currentAmbient: String?

    private init() {
        #if os(iOS)
        try? AVAudioSession.sharedInstance().setCategory(.ambient)
        #endif
    }

    /// Aynı sesi `throttle` saniyeden sık çalmaz (MG spam'ini önler).
    func play(_ name: String, throttle: TimeInterval = 0.08) {
        guard !isMuted else { return }
        let now = Date().timeIntervalSinceReferenceDate
        if let last = lastPlayed[name], now - last < throttle { return }
        lastPlayed[name] = now

        let player: AVAudioPlayer
        if let cached = players[name] {
            player = cached
        } else {
            guard let url = Bundle.main.url(forResource: name, withExtension: "wav"),
                  let made = try? AVAudioPlayer(contentsOf: url) else { return }
            made.prepareToPlay()
            players[name] = made
            player = made
        }
        player.currentTime = 0
        player.play()
    }

    /// Sonsuz döngülü müzik kanalı. Aynı parça zaten çalıyorsa dokunmaz.
    /// Sessize alınmışken de çalmaya devam eder (volume 0) — açınca akış kesintisiz sürer.
    func playMusic(_ name: String) {
        // Menüye dönüş tek kapıdan geçer (MenuView.onAppear → music_menu): oyun
        // ambiyansı burada kesilir. GameSession.deinit'e bağlamadık — restart'ta
        // yeni oturum init'i eski deinit'ten ÖNCE koşabilir ve yeni ambiyansı keserdi.
        if name == "music_menu" { playAmbient(nil) }
        guard currentMusic != name else { return }
        guard let url = Bundle.main.url(forResource: name, withExtension: "mp3"),
              let player = try? AVAudioPlayer(contentsOf: url) else { return }
        musicPlayer?.stop()
        player.numberOfLoops = -1
        player.volume = isMuted ? 0 : SoundPlayer.musicVolume
        player.prepareToPlay()
        player.play()
        musicPlayer = player
        currentMusic = name
        #if DEBUG
        print("SoundPlayer: müzik → \(url.path)")
        #endif
    }

    func stopMusic() {
        musicPlayer?.stop()
        musicPlayer = nil
        currentMusic = nil
    }

    /// Ambiyans döngüsü (V3): müzikle eşzamanlı ikinci kanal. nil → durdurur.
    /// Aynı parça zaten dönüyorsa dokunmaz; sessizken volume 0 ile döner
    /// (müzik kanalıyla aynı sözleşme — ses açılınca akış kesintisiz sürer).
    /// Kaynak biçimi karışık: orman/cırcır MP3, zindan/bataklık M4A (OGG'den
    /// AAC'ye sıkıştırıldı) — uzantılar sırayla denenir.
    func playAmbient(_ name: String?, volume: Float = 0.35) {
        guard let name else {
            ambientPlayer?.stop()
            ambientPlayer = nil
            currentAmbient = nil
            return
        }
        guard currentAmbient != name else { return }
        guard let url = Bundle.main.url(forResource: name, withExtension: "mp3")
                ?? Bundle.main.url(forResource: name, withExtension: "m4a")
                ?? Bundle.main.url(forResource: name, withExtension: "wav"),
              let player = try? AVAudioPlayer(contentsOf: url) else { return }
        ambientPlayer?.stop()
        player.numberOfLoops = -1
        ambientVolume = volume
        player.volume = isMuted ? 0 : volume
        player.prepareToPlay()
        player.play()
        ambientPlayer = player
        currentAmbient = name
        #if DEBUG
        print("SoundPlayer: ambiyans → \(url.path)")
        #endif
    }
}

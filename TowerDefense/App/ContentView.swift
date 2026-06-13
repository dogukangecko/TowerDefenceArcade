import GameCore
import SpriteKit
import SwiftUI

/// Günlük Meydan Okuma tarihi (yalnız ContentView durumunda yaşar).
private struct DailyDate {
    let year: Int
    let month: Int
    let day: Int
}

struct ContentView: View {
    @State private var inGame = false
    @State private var showingHowTo = false
    @State private var showingShop = false
    @State private var showingAchievements = false
    /// Hakkında ekranı (K1): GitHub bağlantısı + varlık sahiplerine atıf.
    @State private var showingCredits = false
    @State private var showingCampaign = false
    @State private var gameID = UUID()
    /// nil = Sonsuz/Günlük; dolu = Sefer seviyesi. Sefer'den çıkışta CampaignView'a
    /// dönülür (showingCampaign açık kalır).
    @State private var campaignLevel: Int?
    /// Günlük Meydan Okuma (E3): dolu ise oyun .daily kipinde açılır — tarih
    /// TIKLAMA anında yakalanır (gece yarısı geçişinde menü kartıyla tutarlı).
    @State private var dailyDate: DailyDate?
    /// Sefer kademe seçimi (CampaignView panelinden); "Sıradaki Seviye" aynı
    /// kademeyle sürer. Sonsuz/Günlük'te GameSession zaten .normal'e sabitler.
    @State private var campaignDifficulty: Difficulty = .normal
    /// Sefer mutatör seçimi (E4 — zorluk panelinden). "Sıradaki Seviye"de
    /// SIFIRLANIR: mutatör kapısı seviye+kademe kazanımına bağlı, sıradaki
    /// seviyede o kapı henüz açılmamış olabilir.
    @State private var campaignMutators: [Mutator] = []
    @AppStorage("selectedMap") private var selectedMap = Persistence.classicMapName

    init() {
        #if DEBUG
        // Başsız UI doğrulama kancası (yalnız DEBUG): "--sefer" Sefer ekranını,
        // "--seviye N" doğrudan N. seviyeyi açar — ekran görüntüsüyle doğrulama
        // tıklama gerektirmeden yapılabilsin diye. "--zorluk <rawValue>"
        // (normal/zor/cokZor/kabus) doğrudan açılan seviyenin kademesini seçer.
        let args = ProcessInfo.processInfo.arguments
        if args.contains("--sefer") {
            _showingCampaign = State(initialValue: true)
        }
        // "--basarimlar": Başarımlar vitrinini doğrudan açar (E5 ss doğrulaması).
        if args.contains("--basarimlar") {
            _showingAchievements = State(initialValue: true)
        }
        // "--hakkinda": Hakkında ekranını doğrudan açar (K1 ss doğrulaması).
        if args.contains("--hakkinda") {
            _showingCredits = State(initialValue: true)
        }
        if let i = args.firstIndex(of: "--seviye"), i + 1 < args.count,
           let n = Int(args[i + 1]), (1...50).contains(n) {
            _campaignLevel = State(initialValue: n)
            _inGame = State(initialValue: true)
        }
        if let i = args.firstIndex(of: "--zorluk"), i + 1 < args.count,
           let d = Difficulty(rawValue: args[i + 1]) {
            _campaignDifficulty = State(initialValue: d)
        }
        // "--serbest [arena adı]": Sonsuz Mod'u doğrudan açar (Serbest Oyun
        // kaldırıldı; arg adı ss betikleri bozulmasın diye korunur —
        // ör. --serbest "Nehir Geçidi"). Ad verilmezse seçili arena.
        if let i = args.firstIndex(of: "--serbest") {
            if i + 1 < args.count, Maps.all.contains(where: { $0.name == args[i + 1] }) {
                UserDefaults.standard.set(args[i + 1], forKey: "selectedMap")
            }
            _inGame = State(initialValue: true)
        }
        // "--obsidyen": ödül kilidini simüle eden geçici bayrak (E2 doğrulaması).
        // Persistence.obsidyenUnlocked DEBUG'da bu anahtarı da kabul eder;
        // doğrulama bitince `defaults delete ... debugObsidyen` ile temizlenir.
        if args.contains("--obsidyen") {
            UserDefaults.standard.set(true, forKey: "debugObsidyen")
        }
        #endif
    }

    var body: some View {
        if inGame {
            GameView(mode: currentMode,
                     difficulty: campaignDifficulty,
                     onRestart: { gameID = UUID() },
                     onExit: { inGame = false },
                     onNext: nextLevelAction)
                .id(gameID)   // kimlik değişince oturum + sahne sıfırdan kurulur
        } else if showingCampaign {
            CampaignView(onPlay: { level, difficulty, mutators in
                dailyDate = nil
                campaignLevel = level
                campaignDifficulty = difficulty
                campaignMutators = mutators
                gameID = UUID()
                inGame = true
            }, onClose: { showingCampaign = false })
        } else if showingHowTo {
            HowToPlayView(onClose: { showingHowTo = false })
        } else if showingShop {
            ShopView(onClose: { showingShop = false })
        } else if showingAchievements {
            AchievementsView(onClose: { showingAchievements = false })
        } else if showingCredits {
            CreditsView(onClose: { showingCredits = false })
        } else {
            MenuView(onCampaign: { showingCampaign = true },
                     onDaily: {
                // Tarih tıklama anında: kart "bugün" derken oyun başka günü açmasın.
                let c = Calendar.current.dateComponents([.year, .month, .day], from: Date())
                guard let y = c.year, let m = c.month, let d = c.day else { return }
                campaignLevel = nil
                dailyDate = DailyDate(year: y, month: m, day: d)
                gameID = UUID()
                inGame = true
            }, onEndless: {
                campaignLevel = nil
                dailyDate = nil
                gameID = UUID()
                inGame = true
            }, onShop: { showingShop = true },
               onAchievements: { showingAchievements = true },
               onHowTo: { showingHowTo = true },
               onCredits: { showingCredits = true })
        }
    }

    /// Kip önceliği: Sefer > Günlük > Sonsuz (Serbest Oyun kaldırıldı —
    /// menüden oyuna giden kalan tek yol Sonsuz arenasıdır).
    private var currentMode: GameMode {
        if let level = campaignLevel {
            return .campaign(level: level, mutators: campaignMutators)
        }
        if let daily = dailyDate {
            return .daily(year: daily.year, month: daily.month, day: daily.day)
        }
        return .endless(mapName: selectedMap)
    }

    /// Sefer galibiyetinde sıradaki seviyeye sıçrama; son seviyede (50) gizli.
    /// campaignDifficulty DEĞİŞMEZ — sıradaki seviye aynı kademeyle başlar.
    private var nextLevelAction: (() -> Void)? {
        guard let level = campaignLevel, level < 50 else { return nil }
        return {
            campaignLevel = level + 1
            // Mutatör kapısı seviye başına: sıradaki seviyede kazanılmamış
            // olabilir — taşınmaz (kademe ise mevcut davranış gereği taşınır).
            campaignMutators = []
            gameID = UUID()
        }
    }
}

struct GameView: View {
    @StateObject private var session: GameSession
    let onRestart: () -> Void
    let onExit: () -> Void
    /// Sefer'de sıradaki seviyeyi başlatır; ResultOverlay yalnız galibiyette gösterir.
    let onNext: (() -> Void)?

    init(mode: GameMode, difficulty: Difficulty = .normal,
         onRestart: @escaping () -> Void,
         onExit: @escaping () -> Void, onNext: (() -> Void)? = nil) {
        // .id(gameID) her yeni oyunda görünümü sıfırdan kurar; StateObject ilk
        // kuruluş değerini o yüzden güvenle kipe bağlayabilir.
        _session = StateObject(wrappedValue: GameSession(mode: mode, difficulty: difficulty))
        self.onRestart = onRestart
        self.onExit = onExit
        self.onNext = onNext
    }

    var body: some View {
        ZStack {
            SpriteView(scene: session.scene)
                .ignoresSafeArea()
            HUDView(session: session)
            if session.showNoTowerConfirm {
                NoTowerConfirmOverlay(
                    onConfirm: { session.confirmStartWaveAnyway() },
                    onCancel: { session.showNoTowerConfirm = false })
            }
            if session.isPaused && (session.phase == .building || session.phase == .waveActive) {
                PauseOverlay(
                    onResume: { session.isPaused = false },
                    onRestart: onRestart,
                    onExit: onExit)
            }
            if session.phase == .won || session.phase == .lost {
                ResultOverlay(won: session.phase == .won,
                              killCount: session.killCount,
                              reachedWave: session.waveNumber,
                              totalWaves: session.totalWaves,
                              // Sonsuz rekoru (bestEndlessWave); diğer kipler kullanmaz.
                              bestWave: session.isEndless
                                  ? Persistence.bestEndlessWave(mapName: session.mapName)
                                  : 0,
                              treasuryEarned: session.lastTreasuryEarned,
                              stars: session.lastStars,
                              difficulty: campaignDifficultyForOverlay,
                              mutators: session.mutators,
                              isEndless: session.isEndless,
                              isDaily: session.isDaily,
                              achievements: session.newAchievements,
                              onRestart: onRestart, onExit: onExit,
                              onNext: session.phase == .won ? onNext : nil)
            }
        }
    }

    /// ResultOverlay'in zorluk kapsülü yalnız Sefer'de görünür; diğer kiplerde nil.
    private var campaignDifficultyForOverlay: Difficulty? {
        if case .campaign = session.mode { return session.difficulty }
        return nil
    }
}

import Combine
import GameCore
import SpriteKit

/// Oyun kipi: Sefer LevelGenerator'ın tohumlu 50 seviyesini oynar (kilit +
/// yıldız ilerlemeli); Sonsuz el yapımı arenalarda (Maps.all) EndlessWaves
/// üreteciyle koşar — galibiyet yok, rekor dalga var. (Eski Serbest Oyun kipi
/// kaldırıldı; el yapımı haritalar artık yalnız Sonsuz arenasıdır.)
enum GameMode {
    /// mutators: E4 gönüllü zorluk anahtarları — yalnız Sefer'de anlamlı
    /// (panel, o seviye+kademe kazanılmışsa seçtirir; motor kuralları uygular).
    case campaign(level: Int, mutators: [Mutator])
    case endless(mapName: String)
    /// Günlük Meydan Okuma (E3): tarihe tohumlu tek seviye, gün başına TEK deneme,
    /// can 10, Hazine sabit ×2 (kademe/mutatör çarpanı yok).
    case daily(year: Int, month: Int, day: Int)
}

@MainActor
final class GameSession: ObservableObject {
    let engine: GameEngine
    private(set) lazy var scene: GameScene = GameScene(session: self)

    /// İlk oyun rehberi adımı; "tutorialDone" UserDefaults anahtarıyla bir defalıktır.
    enum TutorialStep { case buildTower, startWave, done }

    @Published var gold = 0
    @Published var lives = 0
    @Published var waveNumber = 0
    @Published var phase: GamePhase = .building
    @Published var selectedTowerID: Int?
    @Published var buildTile: GridPoint? {
        // İnşa karesi değişince/kapanınca menzil önizlemesi sıfırlanır — tek noktadan:
        // handleTap, Kapat butonu, dalga başlangıcı ve build() hep buradan geçer.
        didSet { if buildTile != oldValue { previewKind = nil } }
    }
    /// İnşa menüsünde ilk dokunuşla seçilen kule türü (menzil önizlemesi); ikinci dokunuş inşa eder.
    @Published var previewKind: TowerKind?
    @Published var killCount = 0
    /// Sürükle-bırak inşa: HUD kartından sürüklenen kule türü (hayalet görünür).
    @Published var dragKind: TowerKind?
    /// Parmağın/imlecin SwiftUI .global uzayındaki konumu (SpriteView tam ekran — SKView
    /// view-koordinatlarıyla birebir; sahne convertPoint(fromView:) ile çözer).
    var dragViewPoint: CGPoint?
    /// Sahnenin her karede yazdığı kenetlenmiş GEÇERLİ kare (uygunsuz/harita dışı → nil).
    var dragSnapTile: GridPoint?
    @Published var isPaused = false
    @Published var gameSpeed: Double = 1.0
    /// Dalga bitince kısa molanın ardından sıradakini kendiliğinden başlat (kalıcı tercih).
    @Published var autoWave = UserDefaults.standard.bool(forKey: "autoWave") {
        didSet { UserDefaults.standard.set(autoWave, forKey: "autoWave") }
    }
    @Published var isMuted: Bool = SoundPlayer.shared.isMuted
    @Published var tutorialStep: TutorialStep =
        UserDefaults.standard.bool(forKey: "tutorialDone") ? .done : .buildTower
    @Published var showNoTowerConfirm = false
    /// Bu oyunun sonunda kazanılan Hazine (dalga×10 + galibiyette +100); ResultOverlay gösterir.
    @Published var lastTreasuryEarned: Int?
    /// Sefer sonucu yıldızlar (0–3); Sonsuz/Günlük'te hep nil → ResultOverlay göstermez.
    @Published var lastStars: Int?
    /// Bu oyunun sonunda YENİ kazanılan başarımlar (E5) — ResultOverlay üstünde
    /// altın kapsül şeridi; boşsa hiçbir şey gösterilmez.
    @Published var newAchievements: [Achievement] = []

    /// Bu turda kurulan kuleler (E5 — satılanlar dahil: tek-tip/spartali
    /// satışla hile yapılamasın diye engine.towers yerine birikimli sayılır).
    private var builtKinds: [TowerKind] = []

    var totalWaves: Int { engine.totalWaves }
    /// Sonsuz kip mi? HUD sayacı ve ResultOverlay başlığı buradan dallanır.
    var isEndless: Bool { engine.isEndless }
    /// Günlük kip mi? ResultOverlay alt satırı + "Tekrar Oyna" gizleme buradan okur.
    var isDaily: Bool {
        if case .daily = mode { return true }
        return false
    }
    var selectedTower: Tower? {
        guard let id = selectedTowerID else { return nil }
        return engine.towers.first { $0.id == id }
    }

    let mode: GameMode

    /// Sonsuz'da arena adı (Maps.all — bestEndlessWave skor anahtarıyla aynı);
    /// Sefer/Günlük'te seviyenin üretilmiş adı (yalnız görüntü — skor anahtarı DEĞİL).
    let mapName: String

    /// Tur başındaki can (mağaza extraLives dahil) — Sefer yıldız oranının paydası.
    private let initialLives: Int

    /// Zorluk kademesi (H1): yalnız Sefer'de anlamlı — Sonsuz/Günlük HER ZAMAN .normal
    /// (init parametresi yok sayılır). Motor canı/HP'yi/fiyatları bununla bileştirir;
    /// Hazine kazanımı ve galibiyet kaydı da buradan okur.
    let difficulty: Difficulty

    /// Aktif mutatörler (E4): yalnız Sefer kipinden gelir; diğer kiplerde boş.
    /// Hazine çarpanı ve ResultOverlay ikon dizisi buradan okur.
    let mutators: [Mutator]

    /// Görsel palet (V2): Sefer/Günlük seviyesinin tohumlu endeksi (0…2);
    /// Sonsuz hep 0 (taban yeşil). Sahne çim/kıyı/dekor tonunu buradan okur.
    let palette: Int

    init(mode: GameMode, difficulty: Difficulty = .normal) {
        self.mode = mode
        // Serbest kurallar: Sonsuz ve Günlük her zaman .normal (kademe yalnız Sefer'de).
        if case .campaign(_, let mutators) = mode {
            self.difficulty = difficulty
            self.mutators = mutators
        } else {
            self.difficulty = .normal
            self.mutators = []
        }
        // Satın alınmış VE açık bırakılmış yükseltmeler tur başında motora uygulanır
        // (oyuncu zorluk için mağazadan item kapatabilir) — Sefer'de de geçerli.
        // CatalogClient.shared: SwiftUI environment'taki örnekle aynı tekil.
        let modifiers = CatalogClient.shared.modifiers(ownedIDs: Persistence.activeItems)
        switch mode {
        case .endless(let mapName):
            // Sonsuz: dalga dizisi boş, tamamı haritaya tohumlu üreteçten gelir.
            // Galibiyet yok (motor .won'u asla tetiklemez) — yalnız rekor dalga.
            // Bilinmeyen ad klasiğe düşer.
            let entry = Maps.all.first { $0.name == mapName } ?? Maps.all[0]
            self.mapName = entry.name
            self.palette = 0
            engine = GameEngine(map: entry.map, waves: [], modifiers: modifiers,
                                waveProvider: EndlessWaves.provider(
                                    mapSeed: EndlessWaves.seed(for: entry.name)))
        case .campaign(let level, let mutators):
            let def = LevelGenerator.level(level)
            self.mapName = def.name
            self.palette = def.palette
            // Üretilmiş dalgalar + KADEME-ÇÖZÜMLÜ birim HP çarpanı (H1b:
            // TunedDifficulty.hpMultByTier — her kademenin kendi ayarlı eğrisi)
            // motora aynen geçer; motor üstüne kademe çarpanı bindirmez.
            engine = GameEngine(map: def.map, waves: def.waves,
                                modifiers: modifiers,
                                enemyHPMultiplier: LevelGenerator.hpMultiplier(
                                    level, difficulty: self.difficulty),
                                difficulty: self.difficulty,
                                mutators: mutators)
        case .daily(let year, let month, let day):
            let def = LevelGenerator.daily(year: year, month: month, day: day)
            self.mapName = def.name
            self.palette = def.palette
            // Can 10 sabit (Normal tabanı yerine açık override; extraLives üste
            // gelir — mağaza bonusu her kipte işler). hpMultiplier üreteçten (2.2).
            engine = GameEngine(map: def.map, waves: def.waves,
                                lives: 10, modifiers: modifiers,
                                enemyHPMultiplier: def.hpMultiplier)
            // Tek deneme kilidi BAŞLANGIÇTA düşer: yarıda bırakmak/yeniden
            // başlatmak yeni deneme açmaz.
            Persistence.recordDailyAttemptStart(
                Persistence.dailyKey(year: year, month: month, day: day))
        }
        initialLives = engine.lives
        syncFromEngine()
        // Müzik/ambiyans matrisi (V3): kademe atmosferi ses katmanıyla desteklenir.
        // Kâbus → savaş müziği + zindan; Çok Zor → zindan; Zor/Günlük → cırcır;
        // Normal → orman (sulu Sefer haritasında %30 tohumlu bataklık; Sonsuz
        // arenasında su varsa hep bataklık — Nehir Geçidi). Menüye dönüşte
        // ambiyansı SoundPlayer.playMusic("music_menu") keser.
        let music = difficulty == .kabus ? "music_battle" : "music_game"
        let ambient: String
        switch difficulty {
        case .kabus, .cokZor: ambient = "amb_dungeon"
        case .zor: ambient = "amb_crickets"
        case .normal:
            switch mode {
            case .daily: ambient = "amb_crickets"
            case .endless:
                // Arena ambiyansı haritadan: sulu arena (Nehir Geçidi) bataklık —
                // eski Serbest Oyun kuralı arenayla birlikte Sonsuz'a taşındı.
                ambient = engine.map.waterTiles.isEmpty ? "amb_forest" : "amb_swamp"
            case .campaign:
                // Tohum = seviye adının FNV-1a'sı: aynı seviye hep aynı ambiyans.
                let h = mapName.utf8.reduce(UInt64(0xcbf2_9ce4_8422_2325)) {
                    ($0 ^ UInt64($1)) &* 0x0000_0100_0000_01B3
                }
                ambient = (!engine.map.waterTiles.isEmpty && h % 100 < 30)
                    ? "amb_swamp" : "amb_forest"
            }
        }
        SoundPlayer.shared.playMusic(music)
        SoundPlayer.shared.playAmbient(ambient)
    }

    /// Sahne her karede çağırır; yalnızca değişen değerleri yayınlar.
    func syncFromEngine() {
        if gold != engine.gold { gold = engine.gold }
        if lives != engine.lives { lives = engine.lives }
        if waveNumber != engine.waveNumber { waveNumber = engine.waveNumber }
        if phase != engine.phase {
            phase = engine.phase
            if phase == .building {
                // Dalga tamamlandı (oyun sonu değil): otomatik mod açıksa kısa moladan
                // sonra sıradaki dalga. reallyStartWave bilinçli tercih gereği kulesiz
                // onay sorusunu atlar.
                scheduleAutoWaveIfNeeded()
            }
            if phase == .won || phase == .lost {
                buildTile = nil
                selectedTowerID = nil
                let won = phase == .won
                switch mode {
                case .endless:
                    // Sonsuzda yalnız kayıp vardır; rekor = ulaşılan (başlatılan son) dalga.
                    Persistence.recordEndlessWave(engine.waveNumber, mapName: mapName)
                case .daily(let year, let month, let day):
                    // Günün sonucu: faz geçişi tek kez yakalandığından çift yazılmaz;
                    // dailyWinCount'u Persistence kendisi gün başına 1 ile sınırlar.
                    Persistence.recordDailyResult(
                        Persistence.dailyKey(year: year, month: month, day: day),
                        won: won, wave: engine.waveNumber)
                case .campaign(let level, _):
                    // Yıldız: kalan can oranına göre (≥%90→3, ≥%30→2, >0→1);
                    // kayıpta 0 — overlay boş yıldız gösterir. Faz geçişi tek kez
                    // yakalandığından lastStars çifte yazılmaz.
                    if lastStars == nil {
                        if won {
                            let ratio = Double(engine.lives) / Double(max(1, initialLives))
                            let stars = ratio >= 0.9 ? 3 : (ratio >= 0.3 ? 2 : 1)
                            lastStars = stars
                            // Yıldız/kilit her kademede aynı sayılır; kademe galibiyeti
                            // ayrıca işaretlenir (H2 rozetleri buradan okuyacak).
                            Persistence.recordStars(level: level, stars)
                            Persistence.recordSeferWin(level: level, difficulty: difficulty)
                            Persistence.unlockedLevel = max(Persistence.unlockedLevel, level + 1)
                        } else {
                            lastStars = 0
                        }
                    }
                }
                // Hazine kazanımı (her iki kipte) — faz geçişi tek kez yakalandığından
                // çift sayım olmaz. Kayıpta son dalga TAMAMLANMAMIŞTIR: yalnız biten
                // dalgalar sayılır.
                if lastTreasuryEarned == nil {
                    let waves = won ? engine.waveNumber : max(0, engine.waveNumber - 1)
                    let earned: Int
                    if case .daily = mode {
                        // Günlük: SABİT ×2 — kademe/mutatör çarpanı bilerek yok
                        // (tek deneme ödülü; difficulty zaten .normal, mutators boş).
                        earned = difficulty.treasuryEarned(wavesCompleted: waves,
                                                           won: won) * 2
                    } else {
                        // Birleşik çarpan (kademe × mutatörler, tavan ×4) SON tutara
                        // uygulanır (Difficulty.treasuryEarned → Mutator.treasuryMultiplier);
                        // Sonsuz'da difficulty .normal + mutators boş → çarpan 1.
                        earned = difficulty.treasuryEarned(wavesCompleted: waves,
                                                           won: won, mutators: mutators)
                    }
                    Persistence.earnTreasury(earned)
                    lastTreasuryEarned = earned
                }
                evaluateAchievements(won: won)
            }
        }
    }

    /// Oyun sonu başarım değerlendirmesi (E5). Faz geçişi tek kez yakalandığından
    /// tek kez koşar; SIRA ÖNEMLİ — mod sonuçları + Hazine yukarıda KAYDEDİLMİŞTİR,
    /// sayaçlar bu oyun dahil günceldir. leaks = toplam can kaybı (boss livesCost>1
    /// birden çok sayar — kabul: kusursuz, hiç can kaybı demektir).
    private func evaluateAchievements(won: Bool) {
        Persistence.addKills(killCount)
        // Not: AchievementContext.Mode.freePlay GameCore'da yaşamaya devam eder
        // (test sabitleri kullanıyor); uygulama artık o kipi hiç üretmez.
        let mode: AchievementContext.Mode = switch self.mode {
        case .campaign: .campaign
        case .endless: .endless
        case .daily: .daily
        }
        let ctx = AchievementContext(
            won: won,
            leaks: initialLives - engine.lives,
            towerKindsUsed: Set(builtKinds),
            towersBuilt: builtKinds.count,
            difficulty: difficulty,
            mode: mode,
            reachedWave: engine.waveNumber,
            normalPlusWinLevels: Persistence.normalPlusWinLevels,
            kabusWinLevels: Persistence.kabusWinCount,
            treasury: Persistence.treasury,
            totalKills: Persistence.totalKills,
            dailyWins: Persistence.dailyWinCount,
            bestEndlessWave: Persistence.bestEndlessWaveOverall)
        let earned = AchievementEngine.evaluate(ctx, already: Persistence.achievedIDs)
        guard !earned.isEmpty else { return }
        Persistence.recordAchievements(earned.map(\.id))
        newAchievements = earned
    }

    /// Otomatik dalga: planlama anındaki dalga numarası yakalanır — gecikme sırasında
    /// oyuncu elle başlattıysa/oyun bittiyse/mod kapandıysa/duraklatıldıysa vazgeçilir.
    private func scheduleAutoWaveIfNeeded() {
        guard autoWave else { return }
        let plannedWave = engine.waveNumber
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.6) { [weak self] in
            guard let self,
                  self.autoWave,
                  self.engine.phase == .building,
                  self.engine.waveNumber == plannedWave,
                  !self.isPaused else { return }
            self.reallyStartWave()
        }
    }

    func startWave() {
        if engine.phase == .building && engine.towers.isEmpty {
            showNoTowerConfirm = true
            return
        }
        reallyStartWave()
    }

    func confirmStartWaveAnyway() {
        showNoTowerConfirm = false
        reallyStartWave()
    }

    private func reallyStartWave() {
        guard case .success = engine.startNextWave() else { return }
        buildTile = nil
        selectedTowerID = nil
        SoundPlayer.shared.play("click")
        syncFromEngine()
        // Sonsuzda "son dalga" yok; her 10. dalga boss dalgasıdır.
        let subtitle: String? = if engine.isEndless {
            engine.waveNumber % 10 == 0 ? "Boss dalgası!" : nil
        } else {
            engine.waveNumber == engine.totalWaves ? "Son dalga — boss geliyor!" : nil
        }
        scene.showBanner(title: "DALGA \(engine.waveNumber)", subtitle: subtitle, icon: "⚔️")
        if tutorialStep != .done {
            tutorialStep = .done
            UserDefaults.standard.set(true, forKey: "tutorialDone")
        }
    }

    func build(_ kind: TowerKind) {
        guard let tile = buildTile else { return }
        if buildAt(tile: tile, kind: kind) { buildTile = nil }
    }

    /// Ortak inşa yolu: iki-dokunuş akışı buildTile'dan, sürükle-bırak doğrudan kareden gelir.
    @discardableResult
    func buildAt(tile: GridPoint, kind: TowerKind) -> Bool {
        var built = false
        if case .success = engine.buildTower(kind, at: tile) {
            built = true
            builtKinds.append(kind)
            if tutorialStep == .buildTower { tutorialStep = .startWave }
            SoundPlayer.shared.play("click")
        }
        syncFromEngine()
        return built
    }

    /// Sürükleme bitti: geçerli karede bırakıldıysa kur. Başarılı kurulumda inşa menüsü
    /// kapanır (iş bitti); uygunsuz bırakışta menü açık kalır (oyuncu tekrar dener).
    func commitDrag() {
        defer {
            dragKind = nil
            dragViewPoint = nil
            dragSnapTile = nil
        }
        guard let kind = dragKind else { return }
        // Son parmak konumundan kesin hesap: sahnenin kare-başı yazımı bir kare geride olabilir.
        if let point = dragViewPoint {
            dragSnapTile = scene.validDragTile(atViewPoint: point, kind: kind)
        }
        guard let tile = dragSnapTile else { return }
        if buildAt(tile: tile, kind: kind) { buildTile = nil }
    }

    func upgradeSelected() {
        guard let id = selectedTowerID else { return }
        if case .success = engine.upgradeTower(id: id) {
            SoundPlayer.shared.play("click")
        }
        syncFromEngine()
    }

    func sellSelected() {
        guard let id = selectedTowerID else { return }
        if case .success = engine.sellTower(id: id) {
            selectedTowerID = nil
            SoundPlayer.shared.play("click")
        }
        syncFromEngine()
    }

    /// Seçili kulenin hedefleme modunu sıradakine çevirir (ilk → güçlü → yakın → ilk).
    /// Tower bir referans tipi; @Published değişmediği için objectWillChange elle tetiklenir.
    func cycleTargeting() {
        guard let tower = selectedTower else { return }
        let all = TargetingMode.allCases
        let idx = all.firstIndex(of: tower.targetingMode) ?? 0
        objectWillChange.send()
        tower.targetingMode = all[(idx + 1) % all.count]
        SoundPlayer.shared.play("click")
    }

    func toggleSpeed() {
        switch gameSpeed {
        case 1.0: gameSpeed = 2.0
        case 2.0: gameSpeed = 3.0
        default: gameSpeed = 1.0
        }
    }

    func toggleMute() {
        SoundPlayer.shared.isMuted.toggle()
        isMuted = SoundPlayer.shared.isMuted
    }

    /// İnşa fazında HUD'da gösterilen sıradaki dalga özeti, örn. "6× Yaprak Böceği · 2× Magma Yengeci".
    var upcomingWaveSummary: String? {
        guard let wave = engine.upcomingWave else { return nil }
        return wave.groups
            .map { "\($0.count)× \(Self.enemyName($0.kind))" }
            .joined(separator: " · ")
    }

    static func enemyName(_ kind: EnemyKind) -> String {
        switch kind {
        case .infantry: "Yaprak Böceği"
        case .scout: "Ateş Böceği"
        case .armored: "Magma Yengeci"
        case .boss: "Ateş Eşekarısı"
        case .scorpion: "Akrep"
        case .clampbeetle: "Kıskaç Böceği"
        case .voidbutterfly: "Gölge Kelebeği"
        case .locust: "Çekirge"
        }
    }
}

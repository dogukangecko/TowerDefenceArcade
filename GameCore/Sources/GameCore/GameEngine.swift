public enum GamePhase: Equatable {
    case building, waveActive, won, lost
}

public final class GameEngine {
    public let map: MapDefinition
    /// Bilerek internal: UI katmanı dalga içeriğini değil yalnızca totalWaves/waveNumber'ı okur.
    let waves: [WaveDefinition]

    public private(set) var phase: GamePhase = .building
    public private(set) var gold: Int
    public private(set) var lives: Int
    public private(set) var waveNumber = 0       // başlatılan dalga sayısı (1 tabanlı)
    public private(set) var towers: [Tower] = []
    public private(set) var enemies: [Enemy] = []

    public var totalWaves: Int { waves.count }

    /// Sonsuz kip mi? Provider varken `.won` ASLA tetiklenmez (oyun yalnız kayıpla
    /// biter); UI dalga sayacında totalWaves yerine ∞ gösterir.
    public var isEndless: Bool { waveProvider != nil }

    /// Sıradaki (henüz başlatılmamış) dalganın tanımı; oyun bittiyse veya dalga kalmadıysa nil.
    /// Dalga aktifken MEVCUT dalgayı değil, ondan SONRAKİ dalgayı döndürür.
    /// Sabit dizi bittiyse provider'dan okur (deterministik üreteç — tekrarlı çağrı güvenli).
    public var upcomingWave: WaveDefinition? {
        guard phase == .building || phase == .waveActive else { return nil }
        if waveNumber < waves.count { return waves[waveNumber] }
        return waveProvider?(waveNumber + 1)
    }

    /// Sonsuz Mod (E1): sabit dalga dizisi bitince sıradaki dalga buradan istenir
    /// (1 tabanlı dalga numarasıyla). nil dönerse dalga kalmamıştır (uç durum —
    /// startNextWave başarısız olur). Üreteç DETERMİNİSTİK olmalıdır: aynı n her
    /// çağrıda aynı dalgayı döndürmeli (upcomingWave tekrar tekrar sorabilir).
    private let waveProvider: ((Int) -> WaveDefinition?)?

    private var nextEntityID = 1
    private var pendingSpawns: [(kind: EnemyKind, time: Double, hpMultiplier: Double)] = []
    private var waveClock: Double = 0

    /// Kalıcı yükseltmelerden gelen tur değiştiricileri (varsayılan: etkisiz).
    public let modifiers: RunModifiers

    /// Birim HP çarpanı (G5b — asıl zorluk kaldıracı): doğan her düşmanın
    /// azami/mevcut HP'si bununla ölçeklenir. Ödül (bounty) ve can bedeli
    /// (livesCost) TABAN kalır — tasarım gereği gelir-nötr: κ ekonomisinde
    /// HP bütçesi ölçeklemesi geliri de ölçeklediği için zorlaştırmaz; bu
    /// çarpan geliri sabit tutarak tek sızıntı mekanizmasını (yol boyu teslim
    /// edilebilir hasarın aşılması) devreye sokar.
    /// H1b: çağıran KADEME-ÇÖZÜMLÜ değeri verir
    /// (LevelGenerator.hpMultiplier(_:difficulty:)); motor üstüne kademe
    /// çarpanı BİNDİRMEZ — değer aynen kullanılır.
    public let enemyHPMultiplier: Double

    /// Zorluk kademesi (H1): can ve maliyet kaldıraçlarını bileştirir
    /// (HP kaldıracı H1b'den beri enemyHPMultiplier'da kademe-çözümlü gelir).
    public let difficulty: Difficulty

    /// Aktif mutatörler (E4) — tur boyunca değişmez. Türetilmiş kural değerleri
    /// init'te bir kez hesaplanır (aşağıdaki sabitler); update sıcak yolunda
    /// liste taranmaz.
    public let mutators: [Mutator]
    /// Düşman hız çarpanı (mutatör bileşimi; varsayılan 1) — doğuşta uygulanır.
    private let enemySpeedMultiplier: Double
    /// Düşman ödül çarpanı (mutatör bileşimi; varsayılan 1) — krediye uygulanır.
    private let bountyMultiplier: Double
    /// camKuleler: upgradeTower her zaman .mutatorForbidden döner.
    private let upgradesDisabled: Bool
    /// ucKule: dolu ise buildTower yalnız bu türleri kabul eder.
    private let allowedKinds: Set<TowerKind>?

    /// `lives: nil` (varsayılan) → kademe tabanı (difficulty.startingLives) kullanılır;
    /// açık değer kademeyi ezer (test/araç kullanımı). Her iki yolda da
    /// modifiers.extraLives üste eklenir. İSTİSNA — demirIrade mutatörü: can
    /// AYNEN livesOverride'a (1) sabitlenir; ne açık değer ne extraLives işler
    /// (Demir İrade kimliği: tam 1 can).
    public init(map: MapDefinition, waves: [WaveDefinition] = Waves.campaign,
                gold: Int = Balance.startingGold, lives: Int? = nil,
                modifiers: RunModifiers = .none, enemyHPMultiplier: Double = 1.0,
                difficulty: Difficulty = .normal,
                waveProvider: ((Int) -> WaveDefinition?)? = nil,
                mutators: [Mutator] = []) {
        self.map = map
        self.waves = waves
        self.waveProvider = waveProvider
        self.modifiers = modifiers
        self.enemyHPMultiplier = enemyHPMultiplier
        self.difficulty = difficulty
        self.mutators = mutators
        self.enemySpeedMultiplier = mutators.reduce(1.0) { $0 * $1.speedMultiplier }
        self.bountyMultiplier = mutators.reduce(1.0) { $0 * $1.bountyMultiplier }
        self.upgradesDisabled = mutators.contains { $0.upgradesDisabled }
        // Birden çok filtre (bugün tek: ucKule) kesişimle birleşir.
        self.allowedKinds = mutators.compactMap(\.allowedKinds).reduce(nil) {
            (acc: Set<TowerKind>?, kinds) in acc.map { $0.intersection(kinds) } ?? Set(kinds)
        }
        self.gold = gold + modifiers.startGoldBonus
        if let forced = mutators.compactMap(\.livesOverride).min() {
            self.lives = forced
        } else {
            self.lives = (lives ?? difficulty.startingLives) + modifiers.extraLives
        }
    }

    /// Ödül ölçekleme kuralı (E4 altinKitligi): en yakına yuvarla, taban 1 —
    /// hiçbir öldürme tamamen ödülsüz kalmaz.
    static func scaledBounty(_ bounty: Int, multiplier: Double) -> Int {
        max(1, Int((Double(bounty) * multiplier).rounded()))
    }

    // MARK: - Kademe fiyatları (UI gerçek fiyatı buradan okur)

    /// İnşa fiyatı: ceil(taban × kademe çarpanı). 1e-9 payı ikili kayan nokta
    /// kalıntısının tam değerleri yukarı taşırmasını önler (50×1.08 = 54.000…007 → 54).
    public func cost(of kind: TowerKind) -> Int {
        Int((Double(Balance.cost(of: kind)) * difficulty.costMultiplier - 1e-9).rounded(.up))
    }

    /// Yükseltme fiyatı: ceil(taban × kademe çarpanı); `toLevel` HEDEF seviye (2…3).
    public func upgradeCost(of kind: TowerKind, toLevel: Int) -> Int {
        Int((Double(Balance.upgradeCost(of: kind, toLevel: toLevel))
            * difficulty.costMultiplier - 1e-9).rounded(.up))
    }

    public func tower(at tile: GridPoint) -> Tower? {
        towers.first { $0.tile == tile }
    }

    @discardableResult
    public func buildTower(_ kind: TowerKind, at tile: GridPoint) -> Result<Tower, CommandError> {
        guard phase == .building || phase == .waveActive else { return .failure(.gameOver) }
        // E4 ucKule: izin listesi dışındaki tür, kare/altın bakılmadan reddedilir.
        if let allowed = allowedKinds, !allowed.contains(kind) {
            return .failure(.mutatorForbidden)
        }
        guard map.isBuildable(tile) else { return .failure(.tileNotBuildable) }
        guard tower(at: tile) == nil else { return .failure(.tileOccupied) }
        let cost = cost(of: kind)
        guard gold >= cost else { return .failure(.insufficientGold) }
        gold -= cost
        let t = Tower(id: nextEntityID, kind: kind, tile: tile)
        nextEntityID += 1
        towers.append(t)
        return .success(t)
    }

    @discardableResult
    public func upgradeTower(id: Int) -> Result<Int, CommandError> {
        guard phase == .building || phase == .waveActive else { return .failure(.gameOver) }
        // E4 camKuleler: yükseltme kökten yasak (kule/altın bakılmadan).
        guard !upgradesDisabled else { return .failure(.mutatorForbidden) }
        guard let t = towers.first(where: { $0.id == id }) else { return .failure(.noTowerThere) }
        guard t.canUpgrade else { return .failure(.maxLevelReached) }
        let cost = upgradeCost(of: t.kind, toLevel: t.level + 1)
        guard gold >= cost else { return .failure(.insufficientGold) }
        gold -= cost
        t.upgrade(cost: cost)  // Tower bir sınıf; t doğrudan referans, kopya değil
        return .success(t.level)
    }

    @discardableResult
    public func sellTower(id: Int) -> Result<Int, CommandError> {
        guard phase == .building || phase == .waveActive else { return .failure(.gameOver) }
        guard let idx = towers.firstIndex(where: { $0.id == id }) else { return .failure(.noTowerThere) }
        let refund = Int((Double(towers[idx].invested) * Balance.sellRefundRate).rounded())
        gold += refund
        towers.remove(at: idx)
        return .success(refund)
    }

    @discardableResult
    public func startNextWave() -> Result<Int, CommandError> {
        guard phase == .building else {
            return .failure(phase == .waveActive ? .waveInProgress : .gameOver)
        }
        // Sabit dizi öncelikli; bitince provider devralır (Sonsuz Mod). Provider'sız
        // motorda dizi biter bitmez faz .won olduğundan buraya zaten gelinmez.
        let def: WaveDefinition
        if waveNumber < waves.count {
            def = waves[waveNumber]
        } else if let provided = waveProvider?(waveNumber + 1) {
            def = provided
        } else {
            return .failure(.gameOver)
        }
        waveNumber += 1
        pendingSpawns = []
        var t = 0.0
        for group in def.groups {
            for _ in 0..<group.count {
                pendingSpawns.append((kind: group.kind, time: t,
                                      hpMultiplier: group.hpMultiplier))
                t += group.interval
            }
        }
        waveClock = 0
        phase = .waveActive
        return .success(waveNumber)
    }

    /// Simülasyonu dt kadar ilerletir. Büyük dt değerlerini kelepçelemek çağıranın
    /// sorumluluğudur (Scene katmanı 1/20 sn ile sınırlar); motor söyleneni aynen simüle eder.
    public func update(dt: Double) -> [GameEvent] {
        guard phase == .waveActive else { return [] }
        var events: [GameEvent] = []

        // 1) Zamanı gelen düşmanları doğur
        waveClock += dt
        while let next = pendingSpawns.first, next.time <= waveClock {
            pendingSpawns.removeFirst()
            // Etkili HP çarpanı = motor (kademe-çözümlü) × grup (Sonsuz Mod n>10 rampası).
            let e = Enemy(id: nextEntityID, kind: next.kind,
                          hpMultiplier: enemyHPMultiplier * next.hpMultiplier,
                          speedMultiplier: enemySpeedMultiplier)
            nextEntityID += 1
            enemies.append(e)
            events.append(.enemySpawned(id: e.id))
        }

        // 2) Hareket + üsse sızanlar
        var leakedIDs: [Int] = []
        for e in enemies where e.isAlive {
            if e.advance(dt: dt, on: map) { leakedIDs.append(e.id) }
        }
        for id in leakedIDs {
            guard let e = enemies.first(where: { $0.id == id }) else { continue }
            enemies.removeAll { $0.id == id }
            lives = max(0, lives - e.stats.livesCost)
            events.append(.enemyLeaked(id: id, livesLost: e.stats.livesCost))
        }

        // 3) Kuleler ateş eder
        for t in towers {
            t.cooldown = max(0, t.cooldown - dt)
            guard t.cooldown <= 0 else { continue }
            guard let target = Targeting.selectTarget(for: t, on: map, among: enemies) else { continue }
            t.cooldown = t.stats.fireInterval
            let targetPos = target.position(on: map)
            events.append(.towerFired(towerID: t.id, kind: t.kind,
                                      targetID: target.id, targetPosition: targetPos))
            // Hasar tek noktada hesaplanır; RunModifiers çarpanı burada uygulanır.
            let damage = t.stats.damage * modifiers.damageMultiplier
            if t.stats.splashRadius > 0 {
                for e in enemies where e.isAlive
                    && e.position(on: map).distance(to: targetPos) <= t.stats.splashRadius {
                    e.takeDamage(damage)
                }
            } else {
                target.takeDamage(damage)
            }
        }

        // 4) Ölenler: ödül + temizlik. E4 altinKitligi: ödül ölçeklenir (taban 1);
        // olay kasaya yazılan GERÇEK tutarı taşır (UI +n etiketi doğru kalır).
        for e in enemies where !e.isAlive {
            let bounty = Self.scaledBounty(e.stats.bounty, multiplier: bountyMultiplier)
            gold += bounty
            events.append(.enemyDied(id: e.id, kind: e.kind,
                                     bounty: bounty, position: e.position(on: map)))
        }
        enemies.removeAll { !$0.isAlive }

        // 5) Kaybetme / dalga sonu / kazanma
        // Kayıp kontrolü bilerek önce: son düşman sızarken can biterse dalga bonusu verilmez.
        if lives <= 0 {
            phase = .lost
            events.append(.gameLost)
        } else if pendingSpawns.isEmpty && enemies.isEmpty {
            let bonus = Balance.waveClearBonus(waveNumber: waveNumber)
            gold += bonus
            events.append(.waveCompleted(waveNumber: waveNumber, bonus: bonus))
            // Sonsuz kipte (provider varken) .won ASLA tetiklenmez — oyun yalnız
            // kayıpla biter; dizi bitse de sıradaki dalga provider'dan gelir.
            if waveNumber == waves.count && !isEndless {
                phase = .won
                events.append(.gameWon)
            } else {
                phase = .building
            }
        }
        return events
    }
}

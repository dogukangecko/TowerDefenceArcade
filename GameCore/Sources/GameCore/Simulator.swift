/// Başsız (UI'siz) deterministik oyun simülatörü ve aç gözlü inşa politikası.
/// BalanceLab ve denge testleri buradan beslenir. Hiçbir yerde rastgelelik yoktur;
/// aynı girdiler her koşuda birebir aynı sonucu üretir.

public struct SimResult: Sendable, Equatable {
    public let won: Bool
    public let livesLeft: Int
    /// Kaybedildiyse kaybın gerçekleştiği dalga numarası; aksi halde nil
    /// (kazanıldı veya maxSeconds duvarına takıldı).
    public let failedAtWave: Int?
    /// Başlatılan SON dalga (E1 — Sonsuz Mod raporu): kayıpta failedAtWave ile
    /// aynıdır; galibiyette son dalga numarası; duvarda son başlatılan dalga.
    public let reachedWave: Int
    public let goldSpentOnTowers: Int   // inşa + yükseltme harcamaları
    public let towersBuilt: Int

    public init(won: Bool, livesLeft: Int, failedAtWave: Int?, reachedWave: Int,
                goldSpentOnTowers: Int, towersBuilt: Int) {
        self.won = won
        self.livesLeft = livesLeft
        self.failedAtWave = failedAtWave
        self.reachedWave = reachedWave
        self.goldSpentOnTowers = goldSpentOnTowers
        self.towersBuilt = towersBuilt
    }
}

public enum PolicyCommand: Sendable, Equatable {
    case build(TowerKind, GridPoint)
    case upgrade(towerID: Int)
}

public protocol BuildPolicy {
    /// Her inşa fazında ve dalga içinde her 0.5 sim-saniyede çağrılır; komut listesi döner.
    /// Geçersiz komutlar (dolu kare, yetersiz altın) sessizce yok sayılır.
    mutating func decide(engine: GameEngine) -> [PolicyCommand]
}

public enum Simulator {
    /// Deterministik başsız oyun: inşa fazlarında policy çalışır, dalga otomatik başlar,
    /// update dt=0.1 sabit adımla ilerler. maxSeconds güvenlik supabıdır (sonsuz döngü koruması);
    /// duvara takılırsa won=false, failedAtWave=nil döner.
    public static func run(map: MapDefinition, waves: [WaveDefinition],
                           modifiers: RunModifiers = .none,
                           enemyHPMultiplier: Double = 1.0,
                           difficulty: Difficulty = .normal,
                           waveProvider: ((Int) -> WaveDefinition?)? = nil,
                           mutators: [Mutator] = [],
                           policy: inout some BuildPolicy,
                           maxSeconds: Double = 600) -> SimResult {
        let engine = GameEngine(map: map, waves: waves, modifiers: modifiers,
                                enemyHPMultiplier: enemyHPMultiplier,
                                difficulty: difficulty,
                                waveProvider: waveProvider,
                                mutators: mutators)
        let dt = 0.1
        let decideInterval = 0.5
        var simTime = 0.0
        var sinceDecide = 0.0
        var goldSpent = 0
        var towersBuilt = 0

        func apply(_ commands: [PolicyCommand]) {
            for command in commands {
                let goldBefore = engine.gold
                switch command {
                case .build(let kind, let tile):
                    if case .success = engine.buildTower(kind, at: tile) { towersBuilt += 1 }
                case .upgrade(let towerID):
                    _ = engine.upgradeTower(id: towerID)
                }
                goldSpent += goldBefore - engine.gold   // başarısız komut fark bırakmaz
            }
        }

        while engine.phase == .building || engine.phase == .waveActive, simTime < maxSeconds {
            if engine.phase == .building {
                apply(policy.decide(engine: engine))
                // Boş dalga listesi vb. durumlarda sonsuz döngüye girme.
                guard case .success = engine.startNextWave() else { break }
                sinceDecide = 0
            }
            while engine.phase == .waveActive, simTime < maxSeconds {
                _ = engine.update(dt: dt)
                simTime += dt
                sinceDecide += dt
                // Dalga içi karar: gerçek oyundaki "dalga sırasında inşa serbest" davranışını yansıtır.
                if sinceDecide >= decideInterval - 1e-9, engine.phase == .waveActive {
                    sinceDecide = 0
                    apply(policy.decide(engine: engine))
                }
            }
        }

        return SimResult(
            won: engine.phase == .won,
            livesLeft: engine.lives,
            failedAtWave: engine.phase == .lost ? engine.waveNumber : nil,
            reachedWave: engine.waveNumber,
            goldSpentOnTowers: goldSpent,
            towersBuilt: towersBuilt)
    }
}

/// Aç gözlü inşa politikası — basit ama deterministik bir "yetkin oyuncu" modeli.
///
/// Kapsama: bir inşa karesinin değeri, merkezi kule menzilinde kalan yol karesi sayısıdır
/// (aday kule türünün 1. seviye menziliyle ölçülür). Karar döngüsü, bütçe içinde kaldıkça:
/// en iyi yeni-kule seçeneği (alım gücündeki türler arasında en yüksek etkiliDPS/altın;
/// o türün menziline göre en yüksek kapsamalı boş kareye yerleştirilir) ile en iyi yükseltme
/// seçeneğini (seviye sınırı altındaki kulelerde en yüksek ΔetkiliDPS/maliyet) karşılaştırır,
/// verimli olanı uygular ve tekrarlar. Eşitlikler deterministik kırılır: kareler satır-major
/// (row, sonra col), kuleler TowerKind.allCases sırası, yükseltmeler kule dizilim sırası;
/// inşa/yükseltme verim eşitliğinde inşa tercih edilir.
public struct GreedyPolicy: BuildPolicy {
    public let buildBudgetRatio: Double

    /// buildBudgetRatio: her karar anında mevcut altının harcanabilir oranı
    /// (varsayılan 0.9 — küçük bir yedek tutar).
    public init(buildBudgetRatio: Double = 0.9) {
        self.buildBudgetRatio = buildBudgetRatio
    }

    public mutating func decide(engine: GameEngine) -> [PolicyCommand] {
        var commands: [PolicyCommand] = []
        var budget = Int(Double(engine.gold) * buildBudgetRatio)
        var occupied = Set(engine.towers.map(\.tile))
        var plannedLevels = Dictionary(uniqueKeysWithValues: engine.towers.map { ($0.id, $0.level) })

        while true {
            let build = bestBuildOption(engine: engine, occupied: occupied, budget: budget)
            let upgrade = bestUpgradeOption(engine: engine,
                                            plannedLevels: plannedLevels, budget: budget)
            if let b = build, b.efficiency >= (upgrade?.efficiency ?? -.infinity) {
                commands.append(.build(b.kind, b.tile))
                budget -= engine.cost(of: b.kind)
                occupied.insert(b.tile)
            } else if let u = upgrade {
                commands.append(.upgrade(towerID: u.towerID))
                budget -= u.cost
                plannedLevels[u.towerID]! += 1
            } else {
                break
            }
        }
        return commands
    }

    // MARK: - Seçenek değerlendirme

    private struct BuildOption { let efficiency: Double; let kind: TowerKind; let tile: GridPoint }
    private struct UpgradeOption { let efficiency: Double; let towerID: Int; let cost: Int }

    /// Fiyatlar motorun kademe-farkında erişimcilerinden okunur — politika
    /// zorluk kademesindeki gerçek fiyatla bütçeler (Kâbus'ta zam dahil).
    private func bestBuildOption(engine: GameEngine,
                                 occupied: Set<GridPoint>, budget: Int) -> BuildOption? {
        let map = engine.map
        var bestKind: TowerKind?
        var bestEfficiency = -Double.infinity
        for kind in TowerKind.allCases {   // eşitlikte enum sırası kazanır (strict >)
            let cost = engine.cost(of: kind)
            guard cost <= budget else { continue }
            let efficiency = Self.effectiveDPS(kind, level: 1) / Double(cost)
            if efficiency > bestEfficiency {
                bestEfficiency = efficiency
                bestKind = kind
            }
        }
        guard let kind = bestKind else { return nil }
        let range = Balance.stats(for: kind, level: 1).range
        guard let tile = bestCoverageTile(on: map, occupied: occupied, range: range) else {
            return nil
        }
        return BuildOption(efficiency: bestEfficiency, kind: kind, tile: tile)
    }

    /// En yüksek kapsamalı boş inşa karesi; satır-major (row, sonra col) eşitlik kırılımı.
    /// Hiç yol karesi kapsamayan kareler elenir (sıfır kapsamalı kuleye para yatırılmaz).
    private func bestCoverageTile(on map: MapDefinition,
                                  occupied: Set<GridPoint>, range: Double) -> GridPoint? {
        var bestTile: GridPoint?
        var bestCoverage = 0
        for row in 0..<map.rows {
            for col in 0..<map.columns {
                let tile = GridPoint(col: col, row: row)
                guard map.isBuildable(tile), !occupied.contains(tile) else { continue }
                let coverage = Self.coverage(of: tile, range: range, on: map)
                if coverage > bestCoverage {   // strict >: satır-major ilk aday kazanır
                    bestCoverage = coverage
                    bestTile = tile
                }
            }
        }
        return bestTile
    }

    private func bestUpgradeOption(engine: GameEngine,
                                   plannedLevels: [Int: Int], budget: Int) -> UpgradeOption? {
        var best: UpgradeOption?
        for tower in engine.towers {   // dizilim (id) sırası; eşitlikte erken kule kazanır (strict >)
            let level = plannedLevels[tower.id] ?? tower.level
            guard level < Balance.maxTowerLevel else { continue }
            let cost = engine.upgradeCost(of: tower.kind, toLevel: level + 1)
            guard cost <= budget else { continue }
            let deltaDPS = Self.effectiveDPS(tower.kind, level: level + 1)
                - Self.effectiveDPS(tower.kind, level: level)
            let efficiency = deltaDPS / Double(cost)
            if efficiency > (best?.efficiency ?? -.infinity) {
                best = UpgradeOption(efficiency: efficiency, towerID: tower.id, cost: cost)
            }
        }
        return best
    }

    // MARK: - Sezgisel metrikler

    /// Etkili DPS = hasar / atış aralığı; alan hasarlı (AoE) kulelere sürü primi eklenir.
    /// Sezgisel: AoE kule kalabalık dalgada birden çok düşmana aynı anda vurur; tam sürü
    /// yoğunluğunu modellemek yerine yarıçapla orantılı sabit çarpan kullanılır:
    /// etkiliDPS × (1 + splashRadius/100 × 0.5). Örn. 70pt yarıçap ≈ +%35 verim varsayımı.
    static func effectiveDPS(_ kind: TowerKind, level: Int) -> Double {
        let stats = Balance.stats(for: kind, level: level)
        var dps = stats.damage / stats.fireInterval
        if stats.splashRadius > 0 {
            dps *= 1 + stats.splashRadius / 100 * 0.5
        }
        return dps
    }

    /// Kapsama: merkezi `range` içinde kalan yol karesi sayısı (kare merkezinden ölçülür).
    /// Sayım sıra-bağımsızdır; Set iterasyon sırası determinizmi etkilemez.
    static func coverage(of tile: GridPoint, range: Double, on map: MapDefinition) -> Int {
        let center = map.center(of: tile)
        return map.pathTiles.count { map.center(of: $0).distance(to: center) <= range }
    }
}

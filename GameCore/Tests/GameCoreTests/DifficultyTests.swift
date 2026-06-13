import XCTest
@testable import GameCore

/// H1/H1b — Zorluk kademeleri çekirdeği: Normal / Zor / Çok Zor / Kâbus.
/// Kademe parametreleri, maliyet çarpanı (yukarı yuvarlama), can bileşimi,
/// HP kaldıracı (H1b: kademe başına ayarlı eğri — motor verilen çarpanı aynen
/// kullanır), Simulator geçişi ve Hazine kazanım çarpanı.
final class DifficultyTests: XCTestCase {
    let straightMap = try! MapDefinition.parse("""
    S########B
    ..........
    """, tileSize: 80)

    // MARK: - Kademe parametreleri

    func testTierOrderAndRawValues() {
        XCTAssertEqual(Difficulty.allCases, [.normal, .zor, .cokZor, .kabus])
        XCTAssertEqual(Difficulty.cokZor.rawValue, "cokZor")
        // Codable: kalıcı anahtarlarda rawValue kullanılır — yuvarlak tur korunmalı.
        XCTAssertEqual(Difficulty(rawValue: "kabus"), .kabus)
    }

    func testTierParameters() {
        // H1b: sabit hp merdiveni kalktı — fallbackHPMultiplier yalnız ayarlı
        // eğri yokken devreye giren mütevazı yedek.
        XCTAssertEqual(Difficulty.normal.fallbackHPMultiplier, 1.0)
        XCTAssertEqual(Difficulty.zor.fallbackHPMultiplier, 1.12)
        XCTAssertEqual(Difficulty.cokZor.fallbackHPMultiplier, 1.22)
        XCTAssertEqual(Difficulty.kabus.fallbackHPMultiplier, 1.32)

        XCTAssertEqual(Difficulty.normal.startingLives, 20)
        XCTAssertEqual(Difficulty.zor.startingLives, 14)
        XCTAssertEqual(Difficulty.cokZor.startingLives, 10)
        XCTAssertEqual(Difficulty.kabus.startingLives, 3)

        XCTAssertEqual(Difficulty.normal.costMultiplier, 1.0)
        XCTAssertEqual(Difficulty.zor.costMultiplier, 1.0)
        XCTAssertEqual(Difficulty.cokZor.costMultiplier, 1.08)
        XCTAssertEqual(Difficulty.kabus.costMultiplier, 1.15)

        XCTAssertEqual(Difficulty.normal.treasuryMultiplier, 1.0)
        XCTAssertEqual(Difficulty.zor.treasuryMultiplier, 1.5)
        XCTAssertEqual(Difficulty.cokZor.treasuryMultiplier, 2.0)
        XCTAssertEqual(Difficulty.kabus.treasuryMultiplier, 3.0)
    }

    func testLabels() {
        XCTAssertEqual(Difficulty.normal.label, "Normal")
        XCTAssertEqual(Difficulty.zor.label, "Zor")
        XCTAssertEqual(Difficulty.cokZor.label, "Çok Zor")
        XCTAssertEqual(Difficulty.kabus.label, "Kâbus")
    }

    // MARK: - Maliyet çarpanı: motor erişimcileri + yukarı yuvarlama

    func testEngineCostAccessorsRoundUp() {
        let normal = GameEngine(map: straightMap)
        XCTAssertEqual(normal.cost(of: .machineGun), 50)            // 50 × 1.0
        XCTAssertEqual(normal.upgradeCost(of: .machineGun, toLevel: 2), 40)

        let zor = GameEngine(map: straightMap, difficulty: .zor)    // çarpan 1.0
        XCTAssertEqual(zor.cost(of: .machineGun), 50)

        let cokZor = GameEngine(map: straightMap, difficulty: .cokZor)
        XCTAssertEqual(cokZor.cost(of: .machineGun), 54)            // 50 × 1.08 = 54 (tam)
        XCTAssertEqual(cokZor.cost(of: .dart), 119)                 // 110 × 1.08 = 118.8 → 119
        XCTAssertEqual(cokZor.upgradeCost(of: .machineGun, toLevel: 2), 44) // 40 × 1.08 = 43.2 → 44

        let kabus = GameEngine(map: straightMap, difficulty: .kabus)
        XCTAssertEqual(kabus.cost(of: .machineGun), 58)             // 50 × 1.15 = 57.5 → 58
        XCTAssertEqual(kabus.cost(of: .rocket), 115)                // 100 × 1.15 = 115 (tam)
        XCTAssertEqual(kabus.upgradeCost(of: .machineGun, toLevel: 2), 46)  // 40 × 1.15 = 46 (tam)
        XCTAssertEqual(kabus.upgradeCost(of: .machineGun, toLevel: 3), 74)  // 64 × 1.15 = 73.6 → 74
    }

    func testBuildChargesAdjustedCost() {
        let kabus = GameEngine(map: straightMap, difficulty: .kabus)  // 140 altın
        _ = kabus.buildTower(.machineGun, at: GridPoint(col: 1, row: 1))
        XCTAssertEqual(kabus.gold, 140 - 58)
    }

    func testBuildFailsWhenGoldCoversBaseButNotAdjustedCost() {
        // 57 altın taban maliyeti (50) karşılar ama Kâbus fiyatını (58) karşılamaz.
        let kabus = GameEngine(map: straightMap, gold: 57, difficulty: .kabus)
        XCTAssertEqual(kabus.buildTower(.machineGun, at: GridPoint(col: 1, row: 1)).failureValue,
                       .insufficientGold)
        XCTAssertEqual(kabus.gold, 57)   // başarısız komut para düşmez
    }

    func testUpgradeChargesAdjustedCost() {
        let cokZor = GameEngine(map: straightMap, gold: 1000, difficulty: .cokZor)
        guard case .success(let t) = cokZor.buildTower(.machineGun, at: GridPoint(col: 1, row: 1))
        else { return XCTFail("inşa başarısız") }
        let before = cokZor.gold
        _ = cokZor.upgradeTower(id: t.id)
        XCTAssertEqual(before - cokZor.gold, 44)   // 40 × 1.08 → 44
    }

    // MARK: - Can bileşimi

    func testStartingLivesPerTier() {
        XCTAssertEqual(GameEngine(map: straightMap).lives, 20)
        XCTAssertEqual(GameEngine(map: straightMap, difficulty: .zor).lives, 14)
        XCTAssertEqual(GameEngine(map: straightMap, difficulty: .cokZor).lives, 10)
        XCTAssertEqual(GameEngine(map: straightMap, difficulty: .kabus).lives, 3)
    }

    func testExtraLivesComposeWithDifficulty() {
        let mods = RunModifiers(startGoldBonus: 0, damageMultiplier: 1.0, extraLives: 2)
        XCTAssertEqual(GameEngine(map: straightMap, modifiers: mods, difficulty: .kabus).lives, 5)
        XCTAssertEqual(GameEngine(map: straightMap, modifiers: mods).lives, 22)
    }

    func testExplicitLivesParamOverridesDifficulty() {
        // Test/araç kullanımı: açık lives parametresi kademe tabanını ezer
        // (extraLives yine eklenir — mevcut davranış korunur).
        XCTAssertEqual(GameEngine(map: straightMap, lives: 7, difficulty: .kabus).lives, 7)
    }

    // MARK: - HP bileşimi (H1b): motor verilen çarpanı AYNEN kullanır

    func testEngineUsesPassedHPMultiplierVerbatim() {
        // Kâbus dahil hiçbir kademe motoru çarpan bindirmeye itmez — çağıran
        // kademe-çözümlü değeri verir (LevelGenerator.hpMultiplier(_:difficulty:)).
        let tuned = LevelGenerator.hpMultiplier(20, difficulty: .kabus)
        let waves = [WaveDefinition(groups: [SpawnGroup(kind: .infantry, count: 1, interval: 1.0)])]
        let engine = GameEngine(map: straightMap, waves: waves,
                                enemyHPMultiplier: tuned, difficulty: .kabus)
        _ = engine.startNextWave()
        _ = engine.update(dt: 0.05)
        XCTAssertEqual(engine.enemies.first?.maxHP ?? 0, 60 * tuned, accuracy: 1e-9)
        // Ödül/can bedeli taban kalır (gelir-nötrlük kademe eğrisinde de geçerli).
        XCTAssertEqual(engine.enemies.first?.stats.bounty, 7)
    }

    func testTierResolvedMultiplierReadsTierCurve() {
        // Ayarlı eğri varken her kademe KENDİ eğrisinden okur; fallback devre dışı.
        for diff in Difficulty.allCases {
            guard let curve = TunedDifficulty.hpMultByTier[diff.rawValue],
                  curve.count == 50 else { continue }
            XCTAssertEqual(LevelGenerator.hpMultiplier(20, difficulty: diff),
                           curve[19], accuracy: 1e-9, diff.rawValue)
        }
        // Normal kademe eski tek-parametreli API ile aynı değeri verir.
        XCTAssertEqual(LevelGenerator.hpMultiplier(20, difficulty: .normal),
                       LevelGenerator.hpMultiplier(20), accuracy: 1e-9)
    }

    // NOT: kademeler arası hpMult monotonluğu BİLEREK assert edilmez — her
    // kademe kendi bandına (can/maliyet kimliği simde etkinken) ayrı ayarlanır;
    // ör. Kâbus'un 3 canlı kimliği aynı sızıntıyı çok daha pahalı yaptığından
    // ayarlı çarpanı Çok Zor'un altına düşebilir. Oyuncunun gördüğü zorluk
    // kimlik kaldıraçlarının (can + maliyet + bant) bileşimidir.

    /// Örneklem kazanılabilirlik (H1b gereksinimi): her kademe-eğri hücresinde
    /// en az BİR bütçe varyantı kazanmalı. Maliyet sınırlı tutuldu: kazanan
    /// bulununca kısa devre (tipik 6 sim).
    func testSampledTierWinnability() throws {
        try XCTSkipIf((TunedDifficulty.hpMultByTier["kabus"] ?? []).count < 50,
                      "ayar v3 henüz üretilmedi")
        for level in [10, 30] {
            let def = LevelGenerator.level(level)
            for diff in [Difficulty.zor, .cokZor, .kabus] {
                let hp = LevelGenerator.hpMultiplier(level, difficulty: diff)
                var won = false
                for ratio in [0.8, 0.9, 1.0] where !won {
                    var policy = GreedyPolicy(buildBudgetRatio: ratio)
                    won = Simulator.run(map: def.map, waves: def.waves,
                                        enemyHPMultiplier: hp,
                                        difficulty: diff, policy: &policy).won
                }
                XCTAssertTrue(won, "L\(level) \(diff.rawValue): hiçbir varyant kazanamadı")
            }
        }
    }

    func testNormalDifficultyKeepsTunedHPUnchanged() {
        let waves = [WaveDefinition(groups: [SpawnGroup(kind: .infantry, count: 1, interval: 1.0)])]
        let engine = GameEngine(map: straightMap, waves: waves, enemyHPMultiplier: 2.0)
        _ = engine.startNextWave()
        _ = engine.update(dt: 0.05)
        XCTAssertEqual(engine.enemies.first?.maxHP ?? 0, 120, accuracy: 1e-9)
    }

    // MARK: - Simulator geçişi

    private struct IdlePolicy: BuildPolicy {
        mutating func decide(engine: GameEngine) -> [PolicyCommand] { [] }
    }

    func testSimulatorDifficultyPassthrough() {
        // Kulesiz tek scout sızar: Kâbus 3 → 2 can; Normal 20 → 19 can.
        let waves = [WaveDefinition(groups: [SpawnGroup(kind: .scout, count: 1, interval: 0.2)])]
        var kabusPolicy = IdlePolicy()
        let kabus = Simulator.run(map: straightMap, waves: waves,
                                  difficulty: .kabus, policy: &kabusPolicy)
        XCTAssertEqual(kabus.livesLeft, 2)
        var normalPolicy = IdlePolicy()
        let normal = Simulator.run(map: straightMap, waves: waves, policy: &normalPolicy)
        XCTAssertEqual(normal.livesLeft, 19)
    }

    // MARK: - Hazine kazanımı

    func testTreasuryEarnedMultiplier() {
        // Taban formül: dalga × 10 + (galibiyette 100); kademe çarpanı SONA uygulanır.
        XCTAssertEqual(Difficulty.normal.treasuryEarned(wavesCompleted: 10, won: true), 200)
        XCTAssertEqual(Difficulty.zor.treasuryEarned(wavesCompleted: 10, won: true), 300)
        XCTAssertEqual(Difficulty.kabus.treasuryEarned(wavesCompleted: 10, won: true), 600)
        // Kayıpta da aynı çarpan (tek formül): 3 dalga × 10 = 30 → Zor 45, Çok Zor 60.
        XCTAssertEqual(Difficulty.zor.treasuryEarned(wavesCompleted: 3, won: false), 45)
        XCTAssertEqual(Difficulty.cokZor.treasuryEarned(wavesCompleted: 3, won: false), 60)
        // Hiç dalga bitmeden kayıp: kademe ne olursa olsun 0.
        XCTAssertEqual(Difficulty.kabus.treasuryEarned(wavesCompleted: 0, won: false), 0)
    }
}

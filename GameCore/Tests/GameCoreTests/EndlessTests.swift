import XCTest
@testable import GameCore

/// E1 Sonsuz Mod: SpawnGroup hpMultiplier, GameEngine waveProvider, EndlessWaves üreteci
/// ve sim sonlanma kanıtı.
final class EndlessTests: XCTestCase {
    let miniMap = try! MapDefinition.parse("""
    S##.
    ..#.
    ..B.
    """, tileSize: 80)                       // yol uzunluğu 320

    private func run(_ engine: GameEngine, seconds: Double, step: Double = 0.05) {
        var t = 0.0
        while t < seconds {
            _ = engine.update(dt: step)
            t += step
        }
    }

    // MARK: - (1) SpawnGroup.hpMultiplier

    func testSpawnGroupHPMultiplierDefaultsToOne() {
        // Geriye uyumlu init: hpMultiplier verilmezse 1.0.
        let group = SpawnGroup(kind: .infantry, count: 3, interval: 0.5)
        XCTAssertEqual(group.hpMultiplier, 1.0)
        let scaled = SpawnGroup(kind: .infantry, count: 3, interval: 0.5, hpMultiplier: 1.5)
        XCTAssertEqual(scaled.hpMultiplier, 1.5)
    }

    func testEngineAppliesGroupTimesEngineHPMultiplier() {
        // Grup çarpanı × motor çarpanı: 1.5 × 2.0 = 3.0.
        let waves = [WaveDefinition(groups: [
            SpawnGroup(kind: .infantry, count: 1, interval: 0.5, hpMultiplier: 1.5),
        ])]
        let engine = GameEngine(map: miniMap, waves: waves, enemyHPMultiplier: 2.0)
        _ = engine.startNextWave()
        run(engine, seconds: 0.1)
        let base = Balance.stats(for: .infantry).maxHP
        XCTAssertEqual(engine.enemies.first?.maxHP, base * 3.0)
    }

    func testEngineWithoutGroupMultiplierUnchanged() {
        // hpMultiplier 1.0 olan grup eski davranışla birebir aynı.
        let waves = [WaveDefinition(groups: [SpawnGroup(kind: .scout, count: 1, interval: 0.5)])]
        let engine = GameEngine(map: miniMap, waves: waves, enemyHPMultiplier: 1.25)
        _ = engine.startNextWave()
        run(engine, seconds: 0.1)
        XCTAssertEqual(engine.enemies.first?.maxHP, Balance.stats(for: .scout).maxHP * 1.25)
    }

    // MARK: - (2) GameEngine.waveProvider

    /// Tek zayıf düşmanlı minik dalga — sızıntıyla hızla biter.
    private func tinyWave() -> WaveDefinition {
        WaveDefinition(groups: [SpawnGroup(kind: .scout, count: 1, interval: 0.2)])
    }

    func testWaveProviderCalledWithSequentialIndices() {
        var asked: [Int] = []
        let engine = GameEngine(map: miniMap, waves: [], lives: 1000,
                                waveProvider: { n in asked.append(n); return self.tinyWave() })
        XCTAssertTrue(engine.isEndless)
        for expected in 1...3 {
            XCTAssertEqual(try? engine.startNextWave().get(), expected)
            run(engine, seconds: 4.0)            // scout sızar, dalga biter
            XCTAssertEqual(engine.phase, .building)
        }
        // upcomingWave da provider'dan okur (4. dalga) — başlatılan 1,2,3 sırayla istendi.
        XCTAssertEqual(asked.prefix(3), [1, 2, 3])
    }

    func testProviderTakesOverAfterFixedWavesExhausted() {
        // 1 sabit dalga + provider: 2. dalga provider(2)'den gelir.
        var asked: [Int] = []
        let engine = GameEngine(map: miniMap, waves: [tinyWave()], lives: 1000,
                                waveProvider: { n in asked.append(n); return self.tinyWave() })
        _ = engine.startNextWave()
        run(engine, seconds: 4.0)
        XCTAssertEqual(engine.phase, .building)  // sabit dizinin sonu ama .won DEĞİL
        _ = engine.startNextWave()
        XCTAssertTrue(asked.contains(2))
    }

    func testEndlessNeverWinsThroughWave15() {
        let engine = GameEngine(map: miniMap, waves: [], lives: 1000,
                                waveProvider: { _ in self.tinyWave() })
        for n in 1...15 {
            XCTAssertEqual(try? engine.startNextWave().get(), n)
            run(engine, seconds: 4.0)
            XCTAssertEqual(engine.phase, .building, "dalga \(n) sonrası .won tetiklenmemeli")
        }
        XCTAssertEqual(engine.waveNumber, 15)
    }

    func testEndlessLossStillEndsGame() {
        // 2 can, kulesiz: sızıntılar canı bitirir → .lost.
        let engine = GameEngine(map: miniMap, waves: [], lives: 2,
                                waveProvider: { _ in
                                    WaveDefinition(groups: [SpawnGroup(kind: .scout, count: 3, interval: 0.2)])
                                })
        _ = engine.startNextWave()
        run(engine, seconds: 6.0)
        XCTAssertEqual(engine.phase, .lost)
    }

    func testNonEndlessEngineUnchanged() {
        let engine = GameEngine(map: miniMap, waves: [tinyWave()], lives: 1000)
        XCTAssertFalse(engine.isEndless)
        _ = engine.startNextWave()
        run(engine, seconds: 4.0)
        XCTAssertEqual(engine.phase, .won)       // provider yokken son dalga kazandırır
    }

    // MARK: - (3) EndlessWaves üreteci

    func testEndlessProviderDeterministic() {
        let a = EndlessWaves.provider(mapSeed: 42)
        let b = EndlessWaves.provider(mapSeed: 42)
        for n in 1...30 {
            XCTAssertEqual(a(n), b(n), "dalga \(n) aynı tohumla birebir aynı olmalı")
        }
        // Farklı tohum farklı kompozisyon üretir (en az bir dalga ayrışır).
        let c = EndlessWaves.provider(mapSeed: 99)
        XCTAssertTrue((1...30).contains { a($0) != c($0) })
    }

    func testEndlessBudgetAdherence() {
        // Toplam ETKİLİ HP (taban HP × grup çarpanı) bütçenin ±%15 bandında.
        let provider = EndlessWaves.provider(mapSeed: 7)
        for n in 1...40 {
            guard let wave = provider(n) else { return XCTFail("dalga \(n) nil") }
            let effectiveHP = wave.groups.reduce(0.0) {
                $0 + Double($1.count) * Balance.stats(for: $1.kind).maxHP * $1.hpMultiplier
            }
            let budget = EndlessWaves.budget(wave: n)
            XCTAssertGreaterThanOrEqual(effectiveHP, budget * 0.85, "dalga \(n) bütçe altı")
            XCTAssertLessThanOrEqual(effectiveHP, budget * 1.15, "dalga \(n) bütçe üstü")
        }
    }

    func testEndlessBossCadence() {
        let provider = EndlessWaves.provider(mapSeed: 7)
        for n in 1...40 {
            let hasBoss = provider(n)!.groups.contains { $0.kind == .boss }
            XCTAssertEqual(hasBoss, n % 10 == 0, "dalga \(n): boss yalnız her 10.da")
        }
    }

    func testEndlessHPMultiplierSchedule() {
        // n ≤ 10: çarpan 1; n > 10: 1.04^(n−10) (BTD6 freeplay tarzı kaçınılmaz son).
        let provider = EndlessWaves.provider(mapSeed: 7)
        for n in [1, 5, 10] {
            for g in provider(n)!.groups {
                XCTAssertEqual(g.hpMultiplier, 1.0, "dalga \(n) çarpansız olmalı")
            }
        }
        for n in [11, 15, 25] {
            let expected = pow(1.04, Double(n - 10))
            for g in provider(n)!.groups {
                XCTAssertEqual(g.hpMultiplier, expected, accuracy: 1e-9, "dalga \(n)")
            }
        }
    }

    func testEndlessUsesFullRoster() {
        // Sonsuz sefer-sonrası içerik: tanıtım takvimi yok, tüm türler 1. dalgadan havuzda.
        // (Erken dalgalarda bütçe küçük olduğundan pahalı türler nadir; 1–20 birleşiminde
        // boss hariç tüm türler görülmeli.)
        let provider = EndlessWaves.provider(mapSeed: 7)
        var seen = Set<EnemyKind>()
        for n in 1...20 {
            for g in provider(n)!.groups { seen.insert(g.kind) }
        }
        for kind in EnemyKind.allCases where kind != .boss {
            XCTAssertTrue(seen.contains(kind), "\(kind) 20 dalgada hiç görünmedi")
        }
    }

    func testSeedForMapNameStableAndDistinct() {
        XCTAssertEqual(EndlessWaves.seed(for: "Klasik Vadi"), EndlessWaves.seed(for: "Klasik Vadi"))
        XCTAssertNotEqual(EndlessWaves.seed(for: "Klasik Vadi"), EndlessWaves.seed(for: "Nehir Yarığı"))
    }

    // MARK: - (4) Sim sonlanma kanıtı + SimResult.reachedWave

    func testGreedyPolicyDiesBeforeWave80OnClassicEndless() {
        var policy = GreedyPolicy(buildBudgetRatio: 0.9)
        let result = Simulator.run(map: Maps.classic(), waves: [],
                                   waveProvider: EndlessWaves.provider(
                                       mapSeed: EndlessWaves.seed(for: "Klasik Vadi")),
                                   policy: &policy, maxSeconds: 36_000)
        XCTAssertFalse(result.won, "sonsuzda galibiyet olamaz")
        XCTAssertNotNil(result.failedAtWave, "bot maxSeconds duvarına takılmamalı, ÖLMELİ")
        XCTAssertLessThan(result.reachedWave, 80, "üstel HP çarpanı 80'den önce öldürmeli")
        XCTAssertEqual(result.reachedWave, result.failedAtWave)
        print("[sonsuz-sim] GreedyPolicy(0.9) klasikte dalga \(result.reachedWave)'de öldü, " +
              "kule \(result.towersBuilt), harcama \(result.goldSpentOnTowers)")
    }

    func testSimResultReachedWaveOnFiniteRun() {
        // Sonlu kampanyada reachedWave = başlatılan son dalga.
        var policy = GreedyPolicy()
        let result = Simulator.run(map: Maps.classic(), waves: Waves.campaign, policy: &policy)
        XCTAssertTrue(result.won)
        XCTAssertEqual(result.reachedWave, Waves.campaign.count)
    }
}

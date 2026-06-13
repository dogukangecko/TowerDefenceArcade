import XCTest
@testable import GameCore

final class EngineSimulationTests: XCTestCase {
    let miniMap = try! MapDefinition.parse("""
    S##.
    ..#.
    ..B.
    """, tileSize: 80)                       // yol uzunluğu 320

    let straightMap = try! MapDefinition.parse("""
    S########B
    ..........
    """, tileSize: 80)                       // yol uzunluğu 720

    @discardableResult
    private func run(_ engine: GameEngine, seconds: Double,
                     step: Double = 1.0 / 60.0) -> [GameEvent] {
        var events: [GameEvent] = []
        var t = 0.0
        while t < seconds {
            events += engine.update(dt: step)
            t += step
        }
        return events
    }

    func testStartWaveAndSpawnSchedule() {
        let waves = [WaveDefinition(groups: [SpawnGroup(kind: .infantry, count: 3, interval: 0.5)])]
        let engine = GameEngine(map: miniMap, waves: waves)
        XCTAssertEqual(try? engine.startNextWave().get(), 1)
        XCTAssertEqual(engine.phase, .waveActive)
        XCTAssertEqual(engine.startNextWave().failureValue, .waveInProgress)

        let early = run(engine, seconds: 0.1)
        XCTAssertEqual(engine.enemies.count, 1)   // t=0 spawn
        XCTAssertEqual(early.filter { if case .enemySpawned = $0 { true } else { false } }.count, 1)

        run(engine, seconds: 1.0)                 // t=1.1 → 3 düşman da çıktı
        XCTAssertEqual(engine.enemies.count, 3)
    }

    func testLeakCostsLivesAndCompletesWave() {
        let waves = [
            WaveDefinition(groups: [SpawnGroup(kind: .scout, count: 2, interval: 0.2)]),
            WaveDefinition(groups: [SpawnGroup(kind: .scout, count: 1, interval: 0.2)]),
        ]
        let engine = GameEngine(map: miniMap, waves: waves)
        _ = engine.startNextWave()
        let events = run(engine, seconds: 4.0)    // scout 320/210 ≈ 1.6 sn'de sızar

        XCTAssertEqual(engine.lives, 18)          // 2 sızıntı
        XCTAssertTrue(engine.enemies.isEmpty)
        XCTAssertTrue(events.contains(.enemyLeaked(id: 1, livesLost: 1)))
        XCTAssertTrue(events.contains(.waveCompleted(waveNumber: 1, bonus: 18)))
        XCTAssertEqual(engine.phase, .building)   // son dalga değildi
        XCTAssertEqual(engine.gold, 140 + 18)
    }

    func testTowerKillsEnemyAndEarnsBounty() {
        let waves = [WaveDefinition(groups: [SpawnGroup(kind: .infantry, count: 1, interval: 1.0)])]
        let engine = GameEngine(map: straightMap, waves: waves)
        _ = engine.buildTower(.sniper, at: GridPoint(col: 1, row: 1)) // 120 → kalan 20; tek atış öldürür
        _ = engine.startNextWave()
        let events = run(engine, seconds: 1.0)

        XCTAssertTrue(events.contains { if case .towerFired = $0 { true } else { false } })
        XCTAssertTrue(events.contains { if case .enemyDied(_, .infantry, 7, _) = $0 { true } else { false } })
        XCTAssertTrue(events.contains(.gameWon))
        XCTAssertEqual(engine.phase, .won)
        XCTAssertEqual(engine.lives, 20)
        XCTAssertEqual(engine.gold, 20 + 7 + 18)  // kalan + bounty (κ: 7) + dalga bonusu
    }

    // MARK: - Birim HP çarpanı (G5b)

    func testEnemyHPMultiplierScalesHPButBountyStaysBase() {
        // 2× HP: keskin nişancı (60 hasar) piyadeyi (60→120 HP) tek atışta öldüremez.
        let waves = [WaveDefinition(groups: [SpawnGroup(kind: .infantry, count: 1, interval: 1.0)])]
        let engine = GameEngine(map: straightMap, waves: waves, enemyHPMultiplier: 2.0)
        _ = engine.buildTower(.sniper, at: GridPoint(col: 1, row: 1))
        _ = engine.startNextWave()
        run(engine, seconds: 0.1)                 // doğdu + ilk atışı yedi
        XCTAssertEqual(engine.enemies.first?.maxHP ?? 0, 120, accuracy: 1e-9)
        XCTAssertEqual(engine.enemies.first?.hp ?? 0, 60, accuracy: 1e-9)
        XCTAssertEqual(engine.enemies.first?.stats.maxHP ?? 0, 60, accuracy: 1e-9)

        let events = run(engine, seconds: 4.0)    // 2. atış (t≈2.8) öldürür
        // Ödül TABAN bounty'dir (κ gelir-nötrlüğü: HP çarpanı geliri şişirmez).
        XCTAssertTrue(events.contains { if case .enemyDied(_, .infantry, 7, _) = $0 { true } else { false } })
        XCTAssertEqual(engine.phase, .won)
        XCTAssertEqual(engine.gold, 140 - 120 + 7 + 18)  // kalan + taban ödül + dalga bonusu
    }

    func testEnemyHPMultiplierLeakCostsBaseLives() {
        let waves = [WaveDefinition(groups: [SpawnGroup(kind: .scout, count: 1, interval: 0.2)])]
        let engine = GameEngine(map: miniMap, waves: waves, enemyHPMultiplier: 5.0)
        _ = engine.startNextWave()
        let events = run(engine, seconds: 4.0)
        XCTAssertEqual(engine.lives, 19)          // livesCost taban kalır
        XCTAssertTrue(events.contains(.enemyLeaked(id: 1, livesLost: 1)))
    }

    func testSplashHitsCluster() {
        // Aynı anda doğan 3 piyade aynı konumda ilerler; tek roket hepsine 25 vurur
        let waves = [WaveDefinition(groups: [SpawnGroup(kind: .infantry, count: 3, interval: 0)])]
        let engine = GameEngine(map: straightMap, waves: waves, gold: 100)
        _ = engine.buildTower(.rocket, at: GridPoint(col: 1, row: 1))
        _ = engine.startNextWave()
        run(engine, seconds: 0.1)                 // ilk atış
        XCTAssertEqual(engine.enemies.count, 3)
        for e in engine.enemies {
            XCTAssertEqual(e.hp, 35, accuracy: 0.001)  // 60 - 25
        }
    }

    func testMachineGunHitsSingleTarget() {
        let waves = [WaveDefinition(groups: [SpawnGroup(kind: .infantry, count: 2, interval: 0)])]
        let engine = GameEngine(map: straightMap, waves: waves)
        _ = engine.buildTower(.machineGun, at: GridPoint(col: 1, row: 1))
        _ = engine.startNextWave()
        run(engine, seconds: 1.0 / 60.0 + 0.001, step: 1.0 / 60.0)  // tek update
        let hps = engine.enemies.map(\.hp).sorted()
        XCTAssertEqual(hps, [54, 60])             // yalnız biri 6 hasar aldı
    }

    func testBossLeakLosesFiveLivesAndGame() {
        let waves = [WaveDefinition(groups: [SpawnGroup(kind: .boss, count: 1, interval: 1.0)])]
        let engine = GameEngine(map: miniMap, waves: waves, lives: 5)
        _ = engine.startNextWave()
        let events = run(engine, seconds: 9.0)    // boss 320/45 ≈ 7.1 sn

        XCTAssertEqual(engine.lives, 0)
        XCTAssertTrue(events.contains(.gameLost))
        XCTAssertEqual(engine.phase, .lost)
        // Kaybedince dalga bonusu verilmez
        XCTAssertFalse(events.contains { if case .waveCompleted = $0 { true } else { false } })
    }

    func testUpdateIdleInBuildingPhase() {
        let engine = GameEngine(map: miniMap)
        XCTAssertEqual(engine.update(dt: 1.0), [])
        XCTAssertEqual(engine.phase, .building)
    }

    func testBuildDuringWaveAndWin() {
        let waves = [WaveDefinition(groups: [SpawnGroup(kind: .infantry, count: 2, interval: 0)])]
        let engine = GameEngine(map: straightMap, waves: waves)
        _ = engine.startNextWave()
        run(engine, seconds: 0.05)                    // dalga aktifken
        XCTAssertEqual(engine.phase, .waveActive)
        XCTAssertNotNil(try? engine.buildTower(.sniper, at: GridPoint(col: 1, row: 1)).get(),
                        "dalga sırasında inşa serbest olmalı")
        let events = run(engine, seconds: 4.0)
        XCTAssertTrue(events.contains(.gameWon))
        XCTAssertEqual(engine.towers.count, 1)
    }

    func testStartWaveRejectedAfterGameOver() {
        // Kaybedildikten sonra
        let lostEngine = GameEngine(
            map: miniMap,
            waves: [WaveDefinition(groups: [SpawnGroup(kind: .scout, count: 1, interval: 0)])],
            lives: 1)
        _ = lostEngine.startNextWave()
        run(lostEngine, seconds: 3.0)                 // scout sızar → kaybedildi
        XCTAssertEqual(lostEngine.phase, .lost)
        XCTAssertEqual(lostEngine.startNextWave().failureValue, .gameOver)

        // Kazanıldıktan sonra
        let wonEngine = GameEngine(
            map: straightMap,
            waves: [WaveDefinition(groups: [SpawnGroup(kind: .infantry, count: 1, interval: 0)])])
        _ = wonEngine.buildTower(.sniper, at: GridPoint(col: 1, row: 1))
        _ = wonEngine.startNextWave()
        run(wonEngine, seconds: 1.0)
        XCTAssertEqual(wonEngine.phase, .won)
        XCTAssertEqual(wonEngine.startNextWave().failureValue, .gameOver)
    }

    func testEconomyCommandsRejectedAfterGameOver() {
        let waves = [WaveDefinition(groups: [SpawnGroup(kind: .infantry, count: 1, interval: 0)])]
        let engine = GameEngine(map: straightMap, waves: waves)
        let tower = try! engine.buildTower(.sniper, at: GridPoint(col: 1, row: 1)).get()
        _ = engine.startNextWave()
        run(engine, seconds: 1.0)                 // tek piyade ölür → kazanıldı
        XCTAssertEqual(engine.phase, .won)
        XCTAssertEqual(engine.upgradeTower(id: tower.id).failureValue, .gameOver)
        XCTAssertEqual(engine.sellTower(id: tower.id).failureValue, .gameOver)
        XCTAssertEqual(engine.buildTower(.machineGun, at: GridPoint(col: 2, row: 1)).failureValue, .gameOver)
    }

    func testUpcomingWavePreview() {
        let waves = [
            WaveDefinition(groups: [SpawnGroup(kind: .infantry, count: 2, interval: 0)]),
            WaveDefinition(groups: [SpawnGroup(kind: .scout, count: 3, interval: 0.1)]),
        ]
        let engine = GameEngine(map: straightMap, waves: waves)
        XCTAssertEqual(engine.upcomingWave?.groups.first?.kind, .infantry)

        _ = engine.buildTower(.sniper, at: GridPoint(col: 1, row: 1))
        _ = engine.startNextWave()
        XCTAssertEqual(engine.upcomingWave?.groups.first?.kind, .scout) // aktifken sıradaki

        run(engine, seconds: 4.0)            // 1. dalga temiz → building
        XCTAssertEqual(engine.phase, .building)
        XCTAssertEqual(engine.upcomingWave?.groups.first?.kind, .scout)

        _ = engine.startNextWave()
        XCTAssertNil(engine.upcomingWave)    // son dalga başladı, sırada dalga yok
        run(engine, seconds: 8.0)            // scoutlar sızar (nişancı cooldown'u yetişmez) ama can > 0 → kazanılır
        XCTAssertEqual(engine.phase, .won)
        XCTAssertNil(engine.upcomingWave)
    }

    func testUpcomingWaveEdgeCases() {
        // Boş dalga listesi: güvenle nil
        XCTAssertNil(GameEngine(map: miniMap, waves: []).upcomingWave)
        // Tek dalgalı oyun: başlamadan önce o dalga, başladıktan sonra nil
        let single = GameEngine(map: miniMap,
                                waves: [WaveDefinition(groups: [SpawnGroup(kind: .infantry, count: 1, interval: 0)])])
        XCTAssertEqual(single.upcomingWave?.groups.first?.kind, .infantry)
        _ = single.startNextWave()
        XCTAssertNil(single.upcomingWave)
    }
}

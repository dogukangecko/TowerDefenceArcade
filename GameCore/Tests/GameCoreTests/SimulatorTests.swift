import XCTest
@testable import GameCore

/// Hiç kule kurmayan politika — sızıntı/kayıp senaryolarının taban çizgisi.
private struct NoBuildPolicy: BuildPolicy {
    mutating func decide(engine: GameEngine) -> [PolicyCommand] { [] }
}

/// Önceden yazılmış komut listelerini sırayla döndüren politika (mikro testler için).
private struct ScriptedPolicy: BuildPolicy {
    var script: [[PolicyCommand]]
    mutating func decide(engine: GameEngine) -> [PolicyCommand] {
        script.isEmpty ? [] : script.removeFirst()
    }
}

final class SimulatorTests: XCTestCase {

    // MARK: - (a) Boş politika kaybeder

    func testEmptyPolicyLosesEarlyOnClassicMap() {
        var policy = NoBuildPolicy()
        let result = Simulator.run(map: Maps.classic(), waves: Waves.campaign, policy: &policy)

        XCTAssertFalse(result.won)
        XCTAssertNotNil(result.failedAtWave)
        XCTAssertLessThanOrEqual(result.failedAtWave ?? .max, 3,
                                 "20 can, kümülatif sızıntıyla en geç 3. dalgada bitmeli")
        XCTAssertEqual(result.livesLeft, 0)
        XCTAssertEqual(result.towersBuilt, 0)
        XCTAssertEqual(result.goldSpentOnTowers, 0)
    }

    // MARK: - (b) GreedyPolicy klasik haritada inşa eder, deterministiktir

    func testGreedyPolicyBuildsAndIsDeterministicOnClassic() {
        // Kazanma ASSERT EDİLMEZ: kazanamama denge sinyalidir, G3 raporu karar verir.
        var p1 = GreedyPolicy()
        let r1 = Simulator.run(map: Maps.classic(), waves: Waves.campaign, policy: &p1)
        var p2 = GreedyPolicy()
        let r2 = Simulator.run(map: Maps.classic(), waves: Waves.campaign, policy: &p2)

        XCTAssertGreaterThan(r1.towersBuilt, 3)
        XCTAssertGreaterThan(r1.goldSpentOnTowers, 0)
        XCTAssertEqual(r1, r2, "aynı girdiyle iki koşu birebir aynı SimResult vermeli")
    }

    // MARK: - (c) Determinizm (farklı harita + bütçe oranı)

    func testDeterminismOnRiverMapWithCustomBudget() {
        var p1 = GreedyPolicy(buildBudgetRatio: 0.7)
        let r1 = Simulator.run(map: Maps.river(), waves: Waves.campaign, policy: &p1)
        var p2 = GreedyPolicy(buildBudgetRatio: 0.7)
        let r2 = Simulator.run(map: Maps.river(), waves: Waves.campaign, policy: &p2)
        XCTAssertEqual(r1, r2)
    }

    // MARK: - (c2) Birim HP çarpanı geçişi (G5b)

    func testEnemyHPMultiplierPassthroughMakesGameHarder() {
        // Çarpan κ gelir-nötrlüğünü deler: aynı politika, daha az kalan can.
        var p1 = GreedyPolicy(buildBudgetRatio: 0.9)
        let base = Simulator.run(map: Maps.classic(), waves: Waves.campaign, policy: &p1)
        var p2 = GreedyPolicy(buildBudgetRatio: 0.9)
        let hard = Simulator.run(map: Maps.classic(), waves: Waves.campaign,
                                 enemyHPMultiplier: 12.0, policy: &p2)
        XCTAssertLessThan(hard.livesLeft, base.livesLeft)

        var p3 = GreedyPolicy(buildBudgetRatio: 0.9)
        let hard2 = Simulator.run(map: Maps.classic(), waves: Waves.campaign,
                                  enemyHPMultiplier: 12.0, policy: &p3)
        XCTAssertEqual(hard, hard2, "çarpanlı koşu da deterministik olmalı")
    }

    // MARK: - (d) maxSeconds güvenlik supabı

    func testSimulatorStopsAtMaxSeconds() {
        // 100 piyade, 10 sn arayla: dalga ~1000 sn sürer; 5 sn'lik duvar erken keser.
        let longWave = [WaveDefinition(groups: [SpawnGroup(kind: .infantry, count: 100, interval: 10)])]
        let map = try! MapDefinition.parse("""
        S##.
        ..#.
        ..B.
        """, tileSize: 80)
        var policy = NoBuildPolicy()
        let result = Simulator.run(map: map, waves: longWave, policy: &policy, maxSeconds: 5)

        XCTAssertFalse(result.won)
        XCTAssertNil(result.failedAtWave, "kaybedilmedi, süre doldu")
        XCTAssertGreaterThan(result.livesLeft, 0)
    }

    // MARK: - Mikro: sim döngüsü gerçekten hasar uyguluyor

    func testScriptedMachineGunKillsInfantryBeforeLeak() {
        // Yol 11 kare (800 pt); piyade 110 hız → ~7.3 sn. Merkezdeki makineli
        // (menzil 200) tüm yolu kapsar; 60 HP / 6 hasar = 10 atış ≈ 4 sn → sızmadan ölür.
        let map = try! MapDefinition.parse("""
        S####
        ....#
        B####
        """, tileSize: 80)
        let wave = [WaveDefinition(groups: [SpawnGroup(kind: .infantry, count: 1, interval: 1.0)])]
        var policy = ScriptedPolicy(script: [[.build(.machineGun, GridPoint(col: 2, row: 1))]])
        let result = Simulator.run(map: map, waves: wave, policy: &policy)

        XCTAssertTrue(result.won)
        XCTAssertEqual(result.livesLeft, Balance.startingLives, "piyade sızmadan ölmeli")
        XCTAssertEqual(result.towersBuilt, 1)
        XCTAssertEqual(result.goldSpentOnTowers, Balance.cost(of: .machineGun))
    }

    // MARK: - GreedyPolicy birim davranışları

    func testGreedyPolicyRespectsBudgetRatio() {
        // 140 altın × 0.9 = 126 bütçe: 2 makineli (100) alınır, 3.'ye (50) yetmez.
        let engine = GameEngine(map: Maps.classic(), waves: Waves.campaign)
        var policy = GreedyPolicy(buildBudgetRatio: 0.9)
        let commands = policy.decide(engine: engine)

        var planned = 0
        for case .build(let kind, _) in commands { planned += Balance.cost(of: kind) }
        XCTAssertGreaterThan(commands.count, 0)
        XCTAssertLessThanOrEqual(planned, Int(Double(engine.gold) * 0.9))
    }

    func testGreedyPolicyCommandsApplyWithoutFailure() {
        // Politikanın planladığı komutlar motorda geçerli olmalı (kare dolu/yetersiz altın yok).
        let engine = GameEngine(map: Maps.classic(), waves: Waves.campaign)
        var policy = GreedyPolicy()
        let commands = policy.decide(engine: engine)
        XCTAssertFalse(commands.isEmpty)
        for cmd in commands {
            switch cmd {
            case .build(let kind, let tile):
                if case .failure(let err) = engine.buildTower(kind, at: tile) {
                    XCTFail("inşa komutu reddedildi: \(err)")
                }
            case .upgrade(let id):
                if case .failure(let err) = engine.upgradeTower(id: id) {
                    XCTFail("yükseltme komutu reddedildi: \(err)")
                }
            }
        }
    }

    // MARK: - G3 kalibrasyon regresyonu

    func testCalibrationPinGreedyWinsClassicWithHealthyLives() {
        // BalanceLab G3 kalibrasyon çıpası (docs/denge-raporu.md):
        // GreedyPolicy(0.9) klasik haritada KAZANIR ve canı sağlıklı bantta bitirir.
        // Mevcut sonuç 20/20'dir (κ=0.12 ekonomisi adet ölçeklemesini kendi kendine
        // finanse ettiğinden bot tavandadır); alt sınır 14, gelecekte denge "çok zor"
        // yöne kayarsa bu test sinyal verir. Bant geniş tutuldu ki kırılgan olmasın.
        var policy = GreedyPolicy(buildBudgetRatio: 0.9)
        let result = Simulator.run(map: Maps.classic(), waves: Waves.campaign, policy: &policy)

        XCTAssertTrue(result.won, "kalibre kampanyayı GreedyPolicy(0.9) kazanmalı")
        XCTAssertTrue((14...20).contains(result.livesLeft),
                      "kalan can kalibrasyon bandı dışında: \(result.livesLeft)")
        XCTAssertGreaterThan(result.towersBuilt, 3)
    }

    func testGreedyPolicyDecisionIsDeterministic() {
        let e1 = GameEngine(map: Maps.river(), waves: Waves.campaign)
        let e2 = GameEngine(map: Maps.river(), waves: Waves.campaign)
        var p1 = GreedyPolicy()
        var p2 = GreedyPolicy()
        XCTAssertEqual(p1.decide(engine: e1), p2.decide(engine: e2))
    }
}

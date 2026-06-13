import XCTest
@testable import GameCore

/// E4 Mutatörler: beş mutatörün parametreleri, birleşik Hazine çarpanı (üst sınır ×4),
/// motor kuralları (hız, yükseltme yasağı, tür filtresi, ödül kısıtı, tek can)
/// ve sim duman testleri.
final class MutatorTests: XCTestCase {
    let straightMap = try! MapDefinition.parse("""
    S########B
    ..........
    """, tileSize: 80)

    // MARK: - (1) Parametreler

    func testMutatorCasesAndRawValues() {
        XCTAssertEqual(Mutator.allCases,
                       [.hizliDusmanlar, .camKuleler, .ucKule, .altinKitligi, .demirIrade])
        // rawValue kalıcı kayıtlarda kullanılabilir — yuvarlak tur korunmalı.
        XCTAssertEqual(Mutator(rawValue: "demirIrade"), .demirIrade)
    }

    func testMutatorParameters() {
        // Hız: yalnız hizliDusmanlar 1.3, diğerleri etkisiz.
        XCTAssertEqual(Mutator.hizliDusmanlar.speedMultiplier, 1.3)
        for m in Mutator.allCases where m != .hizliDusmanlar {
            XCTAssertEqual(m.speedMultiplier, 1.0, "\(m) hız çarpanı etkisiz olmalı")
        }
        // Yükseltme yasağı: yalnız camKuleler.
        XCTAssertTrue(Mutator.camKuleler.upgradesDisabled)
        for m in Mutator.allCases where m != .camKuleler {
            XCTAssertFalse(m.upgradesDisabled, "\(m) yükseltmeyi yasaklamamalı")
        }
        // Tür filtresi: yalnız ucKule; sıralı sabit liste.
        XCTAssertEqual(Mutator.ucKule.allowedKinds, [.machineGun, .shock, .dart])
        for m in Mutator.allCases where m != .ucKule {
            XCTAssertNil(m.allowedKinds, "\(m) tür filtrelememeli")
        }
        // Ödül kısıtı: yalnız altinKitligi 0.7.
        XCTAssertEqual(Mutator.altinKitligi.bountyMultiplier, 0.7)
        for m in Mutator.allCases where m != .altinKitligi {
            XCTAssertEqual(m.bountyMultiplier, 1.0, "\(m) ödülü değiştirmemeli")
        }
        // Tek can: yalnız demirIrade.
        XCTAssertEqual(Mutator.demirIrade.livesOverride, 1)
        for m in Mutator.allCases where m != .demirIrade {
            XCTAssertNil(m.livesOverride, "\(m) canı ezmemeli")
        }
    }

    func testMutatorPresentation() {
        // Etiket/açıklama boş olamaz; ikonlar sabit ve ayrışık.
        for m in Mutator.allCases {
            XCTAssertFalse(m.label.isEmpty)
            XCTAssertFalse(m.desc.isEmpty)
            XCTAssertFalse(m.icon.isEmpty)
        }
        XCTAssertEqual(Set(Mutator.allCases.map(\.icon)).count, Mutator.allCases.count)
    }

    // MARK: - (2) Hazine çarpanı bileşimi + üst sınır

    func testTreasuryMultiplierPerMutator() {
        XCTAssertEqual(Mutator.hizliDusmanlar.treasuryMultiplier, 1.5)
        XCTAssertEqual(Mutator.camKuleler.treasuryMultiplier, 1.5)
        XCTAssertEqual(Mutator.ucKule.treasuryMultiplier, 1.5)
        XCTAssertEqual(Mutator.altinKitligi.treasuryMultiplier, 2.0)
        XCTAssertEqual(Mutator.demirIrade.treasuryMultiplier, 2.0)
    }

    func testCombinedTreasuryMultiplier() {
        // Mutatörsüz: kademe çarpanı aynen.
        XCTAssertEqual(Mutator.treasuryMultiplier(difficulty: .normal, mutators: []), 1.0)
        XCTAssertEqual(Mutator.treasuryMultiplier(difficulty: .kabus, mutators: []), 3.0)
        // Çarpım: zorluk × mutatörler.
        XCTAssertEqual(Mutator.treasuryMultiplier(difficulty: .normal,
                                                  mutators: [.hizliDusmanlar]), 1.5)
        XCTAssertEqual(Mutator.treasuryMultiplier(difficulty: .zor,
                                                  mutators: [.altinKitligi]), 3.0)
        XCTAssertEqual(Mutator.treasuryMultiplier(difficulty: .normal,
                                                  mutators: [.hizliDusmanlar, .camKuleler]),
                       2.25)
        // Üst sınır ×4: Kâbus ×3 × demirIrade ×2 = 6 → 4.
        XCTAssertEqual(Mutator.treasuryMultiplier(difficulty: .kabus,
                                                  mutators: [.demirIrade]), 4.0)
        // Tüm mutatörler Normal'de bile tavana çarpar: 1.5³×2×2 = 13.5 → 4.
        XCTAssertEqual(Mutator.treasuryMultiplier(difficulty: .normal,
                                                  mutators: Mutator.allCases), 4.0)
    }

    func testTreasuryEarnedWithMutators() {
        // Taban (10 dalga galibiyeti = 200) × birleşik çarpan; mutatörsüz davranış değişmez.
        XCTAssertEqual(Difficulty.normal.treasuryEarned(wavesCompleted: 10, won: true), 200)
        XCTAssertEqual(Difficulty.zor.treasuryEarned(wavesCompleted: 10, won: true,
                                                     mutators: [.altinKitligi]), 600)   // ×3
        // Kâbus + demirIrade: 6 → tavan 4 → 800.
        XCTAssertEqual(Difficulty.kabus.treasuryEarned(wavesCompleted: 10, won: true,
                                                       mutators: [.demirIrade]), 800)
        // Kayıp + kesirli çarpan yuvarlanır: 3 dalga × 10 = 30 × 1.5 = 45.
        XCTAssertEqual(Difficulty.normal.treasuryEarned(wavesCompleted: 3, won: false,
                                                        mutators: [.camKuleler]), 45)
    }

    // MARK: - (3) Motor: hızlı düşmanlar

    func testFastEnemiesSpawnWithScaledSpeed() throws {
        let waves = [WaveDefinition(groups: [
            SpawnGroup(kind: .infantry, count: 1, interval: 0.5),
        ])]
        let engine = GameEngine(map: straightMap, waves: waves,
                                mutators: [.hizliDusmanlar])
        _ = engine.startNextWave()
        _ = engine.update(dt: 0.1)
        let enemy = try XCTUnwrap(engine.enemies.first)
        let base = Balance.stats(for: .infantry).speed
        // Etkili hız taban × 1.3; doğuşu izleyen update'te yol mesafesi de ölçekli.
        XCTAssertEqual(enemy.speed, base * 1.3, accuracy: 1e-9)
        XCTAssertEqual(enemy.pathDistance, base * 1.3 * 0.1, accuracy: 1e-9)
    }

    func testEnemySpeedUnchangedWithoutMutator() throws {
        let waves = [WaveDefinition(groups: [
            SpawnGroup(kind: .infantry, count: 1, interval: 0.5),
        ])]
        let engine = GameEngine(map: straightMap, waves: waves)
        _ = engine.startNextWave()
        _ = engine.update(dt: 0.1)
        let enemy = try XCTUnwrap(engine.enemies.first)
        XCTAssertEqual(enemy.speed, Balance.stats(for: .infantry).speed)
    }

    // MARK: - (4) Motor: cam kuleler (yükseltme yasak)

    func testGlassTowersRejectUpgrade() {
        let engine = GameEngine(map: straightMap, gold: 10_000,
                                mutators: [.camKuleler])
        guard case .success(let tower) = engine.buildTower(.machineGun,
                                                           at: GridPoint(col: 0, row: 1)) else {
            return XCTFail("İnşa serbest kalmalı")
        }
        let goldBefore = engine.gold
        XCTAssertEqual(engine.upgradeTower(id: tower.id), .failure(.mutatorForbidden))
        XCTAssertEqual(engine.gold, goldBefore)     // başarısız komut altın yakmaz
        XCTAssertEqual(tower.level, 1)
    }

    // MARK: - (5) Motor: üç kule (tür filtresi)

    func testThreeTowersRejectsDisallowedKinds() {
        let engine = GameEngine(map: straightMap, gold: 10_000, mutators: [.ucKule])
        let goldBefore = engine.gold
        for kind in [TowerKind.rocket, .sniper] {
            guard case .failure(let error) = engine.buildTower(kind,
                                                               at: GridPoint(col: 0, row: 1))
            else { return XCTFail("\(kind) reddedilmeliydi") }
            XCTAssertEqual(error, .mutatorForbidden)
        }
        XCTAssertEqual(engine.gold, goldBefore)
        XCTAssertTrue(engine.towers.isEmpty)
        // İzinli üç tür inşa edilebilir.
        for (i, kind) in [TowerKind.machineGun, .shock, .dart].enumerated() {
            if case .failure(let e) = engine.buildTower(kind, at: GridPoint(col: i, row: 1)) {
                XCTFail("\(kind) izinli olmalıydı: \(e)")
            }
        }
        // İzinli türde yükseltme serbest (camKuleler yok).
        if case .failure(let e) = engine.upgradeTower(id: engine.towers[0].id) {
            XCTFail("Yükseltme serbest kalmalıydı: \(e)")
        }
    }

    // MARK: - (6) Motor: altın kıtlığı (ödül ×0.7, min 1)

    func testGoldScarcityScalesBounty() {
        // Tek piyade tam yolda ölür: ödül = max(1, round(7 × 0.7)) = 5.
        let waves = [WaveDefinition(groups: [
            SpawnGroup(kind: .infantry, count: 1, interval: 0.5),
        ])]
        let engine = GameEngine(map: straightMap, waves: waves, gold: 10_000,
                                mutators: [.altinKitligi])
        guard case .success = engine.buildTower(.sniper, at: GridPoint(col: 4, row: 1)) else {
            return XCTFail("inşa")
        }
        _ = engine.startNextWave()
        var credited: Int?
        var goldBeforeDeath = 0
        for _ in 0..<400 {
            let before = engine.gold
            let events = engine.update(dt: 0.05)
            if let death = events.compactMap({ event -> Int? in
                if case .enemyDied(_, _, let bounty, _) = event { return bounty }
                return nil
            }).first {
                credited = death
                goldBeforeDeath = before
                break
            }
        }
        XCTAssertEqual(credited, 5, "infantry ödülü 7 × 0.7 → 5 olmalı")
        // Olaydaki ödül kasaya yazılanla aynı (dalga bonusu ayrı olayda gelir;
        // ölüm anındaki fark yalnız ödüldür — tek düşman, son update'te bonus
        // da binebilir; bu yüzden alt sınır kontrolü):
        XCTAssertGreaterThanOrEqual(engine.gold - goldBeforeDeath, 5)
    }

    func testBountyFloorIsOne() {
        // En düşük ödül (locust, 3): 3 × 0.7 = 2.1 → 2; taban 1 sınıfı korunur.
        // Taban kuralının kendisi birim olarak: max(1, round(1×0.7)) = 1.
        XCTAssertEqual(GameEngine.scaledBounty(3, multiplier: 0.7), 2)
        XCTAssertEqual(GameEngine.scaledBounty(1, multiplier: 0.7), 1)
        XCTAssertEqual(GameEngine.scaledBounty(7, multiplier: 1.0), 7)
    }

    // MARK: - (7) Motor: demir irade (tam 1 can — extraLives EKLENMEZ)

    func testIronWillForcesExactlyOneLife() {
        let modifiers = RunModifiers(startGoldBonus: 0, damageMultiplier: 1.0, extraLives: 5)
        // demirIrade: kademe canı VE mağaza extraLives yok sayılır — kimlik tam 1 can.
        let iron = GameEngine(map: straightMap, modifiers: modifiers,
                              difficulty: .zor, mutators: [.demirIrade])
        XCTAssertEqual(iron.lives, 1)
        // Mutatörsüz aynı kurulum: 14 + 5 = 19 (davranış değişmedi).
        let plain = GameEngine(map: straightMap, modifiers: modifiers, difficulty: .zor)
        XCTAssertEqual(plain.lives, 19)
    }

    func testIronWillSingleLeakLosesGame() {
        let waves = [WaveDefinition(groups: [
            SpawnGroup(kind: .infantry, count: 1, interval: 0.5),
        ])]
        let engine = GameEngine(map: straightMap, waves: waves, mutators: [.demirIrade])
        _ = engine.startNextWave()
        for _ in 0..<400 where engine.phase == .waveActive {
            _ = engine.update(dt: 0.05)
        }
        XCTAssertEqual(engine.phase, .lost)
    }

    // MARK: - (8) Bileşim: iki mutatör birlikte

    func testCompositionGlassPlusThreeTowers() {
        let engine = GameEngine(map: straightMap, gold: 10_000,
                                mutators: [.camKuleler, .ucKule])
        guard case .failure(.mutatorForbidden) = engine.buildTower(
            .rocket, at: GridPoint(col: 0, row: 1)) else {
            return XCTFail("rocket reddedilmeliydi")
        }
        guard case .success(let dart) = engine.buildTower(.dart,
                                                          at: GridPoint(col: 0, row: 1)) else {
            return XCTFail("dart izinli olmalı")
        }
        XCTAssertEqual(engine.upgradeTower(id: dart.id), .failure(.mutatorForbidden))
    }

    func testCompositionFastPlusIronWill() {
        let waves = [WaveDefinition(groups: [
            SpawnGroup(kind: .infantry, count: 1, interval: 0.5),
        ])]
        let engine = GameEngine(map: straightMap, waves: waves,
                                mutators: [.hizliDusmanlar, .demirIrade])
        XCTAssertEqual(engine.lives, 1)
        _ = engine.startNextWave()
        _ = engine.update(dt: 0.1)
        XCTAssertEqual(engine.enemies.first?.speed ?? 0,
                       Balance.stats(for: .infantry).speed * 1.3, accuracy: 1e-9)
    }

    // MARK: - (9) Sim duman testleri

    func testSimSmokeFastEnemiesRunsToCompletion() {
        // GreedyPolicy klasikte hizliDusmanlar ile takılmadan biter (kazanmak şart değil).
        var policy = GreedyPolicy()
        let result = Simulator.run(map: Maps.classic(), waves: Waves.campaign,
                                   mutators: [.hizliDusmanlar], policy: &policy)
        // maxSeconds duvarı: won=false && failedAtWave=nil ikilisi duvar demektir —
        // bitmiş bir oyun ya kazanılmış ya da bir dalgada kaybedilmiştir.
        XCTAssertTrue(result.won || result.failedAtWave != nil,
                      "sim duvara takıldı: \(result)")
        XCTAssertGreaterThan(result.towersBuilt, 0)
    }

    func testSimSmokeThreeTowersStillBuilds() {
        // Tür filtresi altında bot yine kule kurabiliyor (reddedilen komutlar
        // sessizce yutulur; izinli türler yeterli).
        var policy = GreedyPolicy()
        let result = Simulator.run(map: Maps.classic(), waves: Waves.campaign,
                                   mutators: [.ucKule], policy: &policy)
        XCTAssertTrue(result.won || result.failedAtWave != nil,
                      "sim duvara takıldı: \(result)")
        XCTAssertGreaterThan(result.towersBuilt, 0)
    }
}

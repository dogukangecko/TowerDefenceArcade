import XCTest
@testable import GameCore

final class BalanceTests: XCTestCase {
    func testTowerCosts() {
        XCTAssertEqual(Balance.cost(of: .machineGun), 50)
        XCTAssertEqual(Balance.cost(of: .rocket), 100)
        XCTAssertEqual(Balance.cost(of: .sniper), 120)
        XCTAssertEqual(Balance.upgradeCost(of: .machineGun, toLevel: 2), 40) // %80
    }

    func testUpgradeScaling() {
        for kind in TowerKind.allCases {
            let l1 = Balance.stats(for: kind, level: 1)
            let l2 = Balance.stats(for: kind, level: 2)
            XCTAssertGreaterThan(l2.damage, l1.damage)
            XCTAssertGreaterThan(l2.range, l1.range)
            XCTAssertLessThan(l2.fireInterval, l1.fireInterval)
        }
        XCTAssertEqual(Balance.stats(for: .machineGun, level: 2).damage, 9, accuracy: 0.001)
    }

    func testEnemyStats() {
        for kind in EnemyKind.allCases {
            let s = Balance.stats(for: kind)
            XCTAssertGreaterThan(s.maxHP, 0)
            XCTAssertGreaterThan(s.speed, 0)
            XCTAssertGreaterThan(s.bounty, 0)
            XCTAssertGreaterThan(s.livesCost, 0)
        }
        XCTAssertEqual(Balance.stats(for: .boss).livesCost, 5)
        XCTAssertGreaterThan(Balance.stats(for: .boss).maxHP,
                             Balance.stats(for: .armored).maxHP, "boss en dayanıklı olmalı")
        XCTAssertGreaterThan(Balance.stats(for: .scout).speed,
                             Balance.stats(for: .infantry).speed, "keşif en hızlı olmalı")
    }

    func testCampaignHasTenWaves() {
        XCTAssertEqual(Waves.campaign.count, 10)
        for wave in Waves.campaign {
            XCTAssertFalse(wave.groups.isEmpty)
            for g in wave.groups {
                XCTAssertGreaterThan(g.count, 0)
                XCTAssertGreaterThanOrEqual(g.interval, 0)
            }
        }
        // Boss yalnızca son dalgada
        XCTAssertTrue(Waves.campaign[9].groups.contains { $0.kind == .boss })
        for i in 0..<9 {
            XCTAssertFalse(Waves.campaign[i].groups.contains { $0.kind == .boss })
        }
    }

    func testWaveClearBonus() {
        // G3 kalibrasyonu: 25+5w → 15+3w (gelir makası — denge-raporu.md)
        XCTAssertEqual(Balance.waveClearBonus(waveNumber: 1), 18)
        XCTAssertEqual(Balance.waveClearBonus(waveNumber: 10), 45)
    }

    func testNewTowerKindsExist() {
        XCTAssertEqual(TowerKind.allCases.count, 8)
        XCTAssertTrue(TowerKind.allCases.contains(.crystal))
        XCTAssertTrue(TowerKind.allCases.contains(.shock))
        XCTAssertTrue(TowerKind.allCases.contains(.orb))
        XCTAssertTrue(TowerKind.allCases.contains(.dart))
        XCTAssertTrue(TowerKind.allCases.contains(.solar))
    }

    func testDartTowerProfile() {
        // Dikenatar: arbaletten uzun menzil + biraz yüksek hasar, orta hız, tek hedef
        let dart = Balance.stats(for: .dart, level: 1)
        XCTAssertEqual(dart.damage, 12, accuracy: 0.001)
        XCTAssertEqual(dart.range, 230, accuracy: 0.001)
        XCTAssertEqual(dart.fireInterval, 0.5, accuracy: 0.001)
        XCTAssertEqual(dart.splashRadius, 0)
        XCTAssertEqual(Balance.cost(of: .dart), 110)
        let machineGun = Balance.stats(for: .machineGun, level: 1)
        XCTAssertGreaterThan(dart.range, machineGun.range)
        XCTAssertGreaterThan(dart.damage, machineGun.damage)
        XCTAssertLessThan(dart.fireInterval, Balance.stats(for: .sniper, level: 1).fireInterval)
    }

    func testSolarTowerProfile() {
        // Güneş Kulesi: en pahalı premium — geniş alan VE uzun menzil
        let solar = Balance.stats(for: .solar, level: 1)
        XCTAssertEqual(solar.damage, 45, accuracy: 0.001)
        XCTAssertEqual(solar.range, 280, accuracy: 0.001)
        XCTAssertEqual(solar.fireInterval, 1.8, accuracy: 0.001)
        XCTAssertEqual(solar.splashRadius, 70, accuracy: 0.001)
        XCTAssertEqual(Balance.cost(of: .solar), 260)
        XCTAssertGreaterThan(Balance.cost(of: .solar), Balance.cost(of: .crystal))
        let orb = Balance.stats(for: .orb, level: 1)
        XCTAssertGreaterThan(solar.splashRadius, orb.splashRadius)
        XCTAssertGreaterThan(solar.range, orb.range)
    }

    func testNewTowerStatsProfiles() {
        // Kristal: pahalı, çok yüksek tek hedef hasarı
        let crystal = Balance.stats(for: .crystal, level: 1)
        XCTAssertGreaterThan(crystal.damage, Balance.stats(for: .sniper, level: 1).damage)
        XCTAssertEqual(crystal.splashRadius, 0)
        XCTAssertGreaterThan(Balance.cost(of: .crystal), Balance.cost(of: .sniper))
        // Şok: en hızlı atış, en kısa menzil
        let shock = Balance.stats(for: .shock, level: 1)
        XCTAssertLessThan(shock.fireInterval, Balance.stats(for: .machineGun, level: 1).fireInterval)
        XCTAssertLessThan(shock.range, Balance.stats(for: .machineGun, level: 1).range)
        // Orb: alan hasarlı, mancınıktan hızlı ama hafif
        let orb = Balance.stats(for: .orb, level: 1)
        XCTAssertGreaterThan(orb.splashRadius, 0)
        XCTAssertLessThan(orb.fireInterval, Balance.stats(for: .rocket, level: 1).fireInterval)
        XCTAssertLessThan(orb.damage, Balance.stats(for: .rocket, level: 1).damage)
    }

    func testNewEnemyKindsExist() {
        XCTAssertEqual(EnemyKind.allCases.count, 8)
        XCTAssertTrue(EnemyKind.allCases.contains(.scorpion))
        XCTAssertTrue(EnemyKind.allCases.contains(.clampbeetle))
        XCTAssertTrue(EnemyKind.allCases.contains(.voidbutterfly))
        XCTAssertTrue(EnemyKind.allCases.contains(.locust))
    }

    func testNewEnemyStatsProfiles() {
        let armored = Balance.stats(for: .armored)
        let scout = Balance.stats(for: .scout)
        // Akrep: zırhlıya yakın HP (~%85), belirgin daha hızlı; ödülü keşif-zırhlı arası
        let scorpion = Balance.stats(for: .scorpion)
        XCTAssertEqual(scorpion.maxHP, 220, accuracy: 0.001)
        XCTAssertEqual(scorpion.speed, 85, accuracy: 0.001)
        XCTAssertLessThan(scorpion.maxHP, armored.maxHP)
        XCTAssertGreaterThan(scorpion.speed, armored.speed)
        XCTAssertGreaterThan(scorpion.bounty, scout.bounty)
        XCTAssertLessThan(scorpion.bounty, armored.bounty)
        // Kıskaç Böceği: orta HP, orta hız
        let clamp = Balance.stats(for: .clampbeetle)
        XCTAssertEqual(clamp.maxHP, 120, accuracy: 0.001)
        XCTAssertEqual(clamp.speed, 100, accuracy: 0.001)
        XCTAssertLessThan(clamp.maxHP, scorpion.maxHP)
        XCTAssertGreaterThan(clamp.maxHP, Balance.stats(for: .infantry).maxHP)
        // Gölge Kelebeği: düşük HP, oyunun en yüksek hızı
        let butterfly = Balance.stats(for: .voidbutterfly)
        XCTAssertEqual(butterfly.maxHP, 30, accuracy: 0.001)
        for kind in EnemyKind.allCases where kind != .voidbutterfly {
            XCTAssertGreaterThan(butterfly.speed, Balance.stats(for: kind).speed,
                                 "kelebek en hızlı olmalı: \(kind)")
        }
        // Çekirge: en düşük HP, hızlı, en düşük ödül (sürü düşmanı)
        let locust = Balance.stats(for: .locust)
        for kind in EnemyKind.allCases where kind != .locust {
            XCTAssertLessThan(locust.maxHP, Balance.stats(for: kind).maxHP,
                              "çekirge en kırılgan olmalı: \(kind)")
            XCTAssertLessThan(locust.bounty, Balance.stats(for: kind).bounty,
                              "çekirge en düşük ödül olmalı: \(kind)")
        }
        XCTAssertGreaterThan(locust.speed, Balance.stats(for: .infantry).speed)
    }

    func testIsFlying() {
        XCTAssertTrue(EnemyKind.boss.isFlying)
        XCTAssertTrue(EnemyKind.clampbeetle.isFlying)
        XCTAssertTrue(EnemyKind.voidbutterfly.isFlying)
        XCTAssertTrue(EnemyKind.locust.isFlying)
        XCTAssertFalse(EnemyKind.infantry.isFlying)
        XCTAssertFalse(EnemyKind.scout.isFlying)
        XCTAssertFalse(EnemyKind.armored.isFlying)
        XCTAssertFalse(EnemyKind.scorpion.isFlying)
    }

    func testWaveCompositionIntroducesNewKinds() {
        let waves = Waves.campaign
        // İlk 3 dalga yalnızca piyade/keşif (mevcut kompozisyon korunur)
        for i in 0..<3 {
            for g in waves[i].groups {
                XCTAssertTrue([.infantry, .scout].contains(g.kind),
                              "dalga \(i + 1) yalnızca piyade/keşif içermeli")
            }
        }
        // Tanıtım dalgaları
        XCTAssertTrue(waves[3].groups.contains { $0.kind == .scorpion })
        XCTAssertTrue(waves[4].groups.contains { $0.kind == .locust })
        XCTAssertTrue(waves[5].groups.contains { $0.kind == .clampbeetle })
        XCTAssertTrue(waves[7].groups.contains { $0.kind == .voidbutterfly })
        XCTAssertTrue(waves[9].groups.contains { $0.kind == .locust },
                      "final boss çekirge eskortuyla gelmeli")
        // Çekirge sürüsü: kalabalık ve kısa aralık
        let swarm = waves[4].groups.first { $0.kind == .locust }!
        XCTAssertGreaterThanOrEqual(swarm.count, 15)
        XCTAssertLessThanOrEqual(swarm.interval, 0.3)
        // Hiçbir tür tanıtım dalgasından önce görünmez
        let intro: [EnemyKind: Int] = [.scorpion: 3, .locust: 4, .clampbeetle: 5, .voidbutterfly: 7]
        for (kind, wave) in intro {
            for i in 0..<wave {
                XCTAssertFalse(waves[i].groups.contains { $0.kind == kind },
                               "\(kind) dalga \(wave + 1)'den önce görünmemeli")
            }
        }
        // 9. dalga "her şey": en az 5 farklı tür
        XCTAssertGreaterThanOrEqual(Set(waves[8].groups.map(\.kind)).count, 5)
    }

    func testWaveTotalHPNonDecreasing() {
        let totals = Waves.campaign.map { wave in
            wave.groups.reduce(0.0) { $0 + Double($1.count) * Balance.stats(for: $1.kind).maxHP }
        }
        for i in 1..<totals.count {
            XCTAssertGreaterThanOrEqual(totals[i], totals[i - 1],
                                        "dalga \(i + 1) toplam HP düşmemeli: \(totals)")
        }
    }

    // MARK: - Sefer dengesi (G1)

    func testUpgradeCostIsGeometric() {
        // upgradeCost(kind, hedefSeviye) = 0.8 · taban · 1.6^(hedef−2)
        XCTAssertEqual(Balance.upgradeCost(of: .machineGun, toLevel: 2), 40)  // 0.8 × 50
        XCTAssertEqual(Balance.upgradeCost(of: .machineGun, toLevel: 3), 64)  // 0.8 × 50 × 1.6
    }

    func testUpgradeEfficiencyRunawayFixed() {
        // Eski kusur: sabit 40 maliyetle 3. seviye adımının ΔDPS/altın'ı taban kulenin
        // ~1.69 katıydı → tek kule şişirme domine ederdi. Geometrik maliyet (×1.6/seviye)
        // bunu ~1.05'e indirir. NOT: seviye başına DPS çarpanı 1.5/0.85 ≈ 1.7647 > 1.6
        // olduğundan oran matematiksel olarak 1.0'ın altına İNEMEZ (maliyetler 40/64
        // testle sabitliyken); kalan ~%5 fark G3 BalanceLab kalibrasyonunun konusudur.
        func dps(_ level: Int) -> Double {
            let s = Balance.stats(for: .machineGun, level: level)
            return s.damage / s.fireInterval
        }
        let baseEff = dps(1) / Double(Balance.cost(of: .machineGun))
        // 2. seviye adımı taban kuleden gerçekten DÜŞÜK verimli:
        let step2Eff = (dps(2) - dps(1)) / Double(Balance.upgradeCost(of: .machineGun, toLevel: 2))
        XCTAssertLessThan(step2Eff, baseEff, "2. seviye yükseltme adımı taban kuleden verimli olmamalı")
        // 3. seviye adımı tabanın en fazla 1.1 katı (kaçak öncesi 1.69'du):
        let step3Eff = (dps(3) - dps(2)) / Double(Balance.upgradeCost(of: .machineGun, toLevel: 3))
        XCTAssertLessThan(step3Eff / baseEff, 1.1, "yükseltme verim kaçağı geri döndü")
    }

    func testBountiesFollowKappaFormula() {
        // κ = 0.12: bounty = max(2, round(0.12 · maxHP)) — gelir tehdide oranlı kalır.
        for kind in EnemyKind.allCases where kind != .boss {
            let s = Balance.stats(for: kind)
            XCTAssertEqual(s.bounty, max(2, Int((0.12 * s.maxHP).rounded())),
                           "κ=0.12 formülü ihlali: \(kind) (HP \(s.maxHP))")
        }
        // Boss formül dışı: sabit 150 (final dalga ödülü ağırlıkla dalga bonusundan gelir).
        XCTAssertEqual(Balance.stats(for: .boss).bounty, 150)
    }

    func testBossRebalance() {
        // Boss HP final dalga toplamının ~0.5×'i hedefine çekildi (2500 → 1000).
        let boss = Balance.stats(for: .boss)
        XCTAssertEqual(boss.maxHP, 1000, accuracy: 0.001)
        XCTAssertEqual(boss.livesCost, 5, "livesCost değişmemeli")
    }

    func testAllTowerKindsHaveCompleteBalance() {
        for kind in TowerKind.allCases {
            XCTAssertGreaterThan(Balance.cost(of: kind), 0)
            for level in 1...Balance.maxTowerLevel {
                XCTAssertGreaterThan(Balance.stats(for: kind, level: level).damage, 0)
            }
        }
    }
}

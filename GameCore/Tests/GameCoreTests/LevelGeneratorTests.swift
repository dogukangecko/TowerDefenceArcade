import XCTest
@testable import GameCore

final class LevelGeneratorTests: XCTestCase {
    // MARK: - Formül yardımcıları (spec sabitleri — testler üreteçten bağımsız hesaplar)

    /// s(w) testere dişi.
    private let saw: [Double] = [1, 1, 1.15, 0.85, 1.2, 1, 1.3, 0.8, 1.25, 1.5]

    private func formulaD(_ level: Int) -> Double {
        min(2.2, 0.85 + 0.15 * Double((level + 4) / 5))   // ⌈L/5⌉
    }

    /// Üretimde geçerli D: TunedDifficulty doluysa oradan, yoksa formül.
    /// Bütçe testleri kompozisyon çözücünün sadakatini ölçer; D'nin kaynağı
    /// değil, bütçeye uyumu test edilir — formülün geri kalanı bağımsız hesaplanır.
    private func dIndex(_ level: Int) -> Double {
        TunedDifficulty.dByLevel.indices.contains(level - 1)
            ? TunedDifficulty.dByLevel[level - 1]
            : formulaD(level)
    }

    /// Kompozisyon D'si: çeşitlilik için bütçeye giren D, 1.3 ile tavanlanır
    /// (zorluk artık birim-HP çarpanında taşınır; adetler makul kalır — G5b).
    private func compositionD(_ level: Int) -> Double {
        min(dIndex(level), 1.3)
    }

    private func budget(_ level: Int, _ wave: Int) -> Double {
        120 * compositionD(level) * pow(1.22, Double(wave - 1)) * saw[wave - 1]
    }

    private func waveHP(_ wave: WaveDefinition) -> Double {
        wave.groups.reduce(0) { $0 + Double($1.count) * Balance.stats(for: $1.kind).maxHP }
    }

    private func introLevel(_ kind: EnemyKind) -> Int {
        switch kind {
        case .infantry, .scout: 1
        case .locust: 3
        case .scorpion: 6
        case .armored: 8
        case .clampbeetle: 10
        case .voidbutterfly: 14
        case .boss: 10   // yalnız L%10==0 dalga 10'da; ilk olası 10
        }
    }

    private func assertSameWaves(_ a: [WaveDefinition], _ b: [WaveDefinition],
                                 file: StaticString = #filePath, line: UInt = #line) {
        XCTAssertEqual(a.count, b.count, file: file, line: line)
        for (wa, wb) in zip(a, b) {
            XCTAssertEqual(wa.groups.count, wb.groups.count, file: file, line: line)
            for (ga, gb) in zip(wa.groups, wb.groups) {
                XCTAssertEqual(ga.kind, gb.kind, file: file, line: line)
                XCTAssertEqual(ga.count, gb.count, file: file, line: line)
                XCTAssertEqual(ga.interval, gb.interval, accuracy: 1e-12, file: file, line: line)
            }
        }
    }

    // MARK: - Determinizm

    func testLevel7Deterministic() {
        let a = LevelGenerator.level(7)
        let b = LevelGenerator.level(7)
        XCTAssertEqual(a.id, 7)
        XCTAssertEqual(a.name, b.name)
        XCTAssertEqual(a.difficultyIndex, b.difficultyIndex)
        XCTAssertEqual(a.map.pathOrder, b.map.pathOrder)
        XCTAssertEqual(a.map.waterTiles, b.map.waterTiles)
        XCTAssertEqual(a.map.spawn, b.map.spawn)
        XCTAssertEqual(a.map.base, b.map.base)
        assertSameWaves(a.waves, b.waves)
    }

    // MARK: - Harita geçerliliği (50 seviye)

    func testAll50MapsParseValid() {
        for id in 1...50 {
            let lvl = LevelGenerator.level(id)
            XCTAssertEqual(lvl.map.columns, 16, "seviye \(id)")
            XCTAssertEqual(lvl.map.rows, 9, "seviye \(id)")
            XCTAssertGreaterThanOrEqual(lvl.map.pathOrder.count, 20, "seviye \(id): yol çok kısa")
            XCTAssertEqual(lvl.map.spawn.col, 0, "seviye \(id): S sol kenarda olmalı")
            XCTAssertEqual(lvl.map.base.col, 15, "seviye \(id): B sağ kenarda olmalı")
            XCTAssertEqual(lvl.difficultyIndex, dIndex(id), accuracy: 1e-9, "seviye \(id)")
            XCTAssertEqual(lvl.difficultyIndex, LevelGenerator.difficultyIndex(id),
                           accuracy: 1e-9, "seviye \(id): D hook ile tutarsız")
        }
    }

    func testAll50MapScoresInBand() {
        for id in 1...50 {
            let lvl = LevelGenerator.level(id)
            let m = LevelGenerator.normalizedMapScore(of: lvl.map)
            XCTAssertGreaterThanOrEqual(m, 0.7, "seviye \(id): M=\(m) bandın altında")
            XCTAssertLessThanOrEqual(m, 1.4, "seviye \(id): M=\(m) bandın üstünde")
        }
    }

    func testRiverOnlyOnScheduledLevels() {
        for id in 1...50 {
            let lvl = LevelGenerator.level(id)
            if !lvl.map.waterTiles.isEmpty {
                XCTAssertTrue(id >= 8 && id % 3 == 0,
                              "seviye \(id): takvim dışı nehir")
                // Yol nehir bandını TAM 1 kez kesmeli: su sütunlarındaki yol karesi
                // sayısı sütun başına 1 olmalı ve hepsi aynı satırda (tek köprü).
                let riverCols = Set(lvl.map.waterTiles.map(\.col))
                var bridgeRows = Set<Int>()
                for c in riverCols {
                    let crossings = lvl.map.pathOrder.filter { $0.col == c }
                    XCTAssertEqual(crossings.count, 1, "seviye \(id): sütun \(c) tek geçiş değil")
                    bridgeRows.formUnion(crossings.map(\.row))
                }
                XCTAssertEqual(bridgeRows.count, 1, "seviye \(id): köprü tek satırda olmalı")
            }
        }
    }

    // MARK: - Harita topolojisi D'den bağımsız (G5: ayar haritaları karıştırmaz)

    func testMapTopologyIndependentOfDifficulty() {
        // Aynı seviyenin haritası, araya farklı D'lerle dalga üretimi girse de özdeş:
        // D yalnız dalga bütçesini besler, harita tohum/kabul döngüsüne girmez.
        let before = LevelGenerator.generateMap(id: 7).ascii
        let easy = LevelGenerator.waves(id: 7, difficulty: 0.8)
        let hard = LevelGenerator.waves(id: 7, difficulty: 2.2)
        let after = LevelGenerator.generateMap(id: 7).ascii
        XCTAssertEqual(before, after, "harita D enjeksiyonundan etkilenmemeli")
        // D gerçekten dalga bütçesine akıyor (dikiş canlı):
        let easyHP = easy.reduce(0.0) { $0 + waveHP($1) }
        let hardHP = hard.reduce(0.0) { $0 + waveHP($1) }
        XCTAssertGreaterThan(hardHP, easyHP * 1.5, "D dalga bütçesini ölçeklemeli")
        // Üretim hattıyla tutarlılık: kompozisyon D'si ile çağrı = level(id).waves.
        assertSameWaves(LevelGenerator.waves(id: 7, difficulty: LevelGenerator.compositionD(7)),
                        LevelGenerator.level(7).waves)
    }

    // MARK: - Birim HP çarpanı alanı (G5b)

    func testHPMultiplierCarriedAndCompositionCapped() {
        for id in 1...50 {
            let lvl = LevelGenerator.level(id)
            XCTAssertEqual(lvl.hpMultiplier, LevelGenerator.hpMultiplier(id),
                           accuracy: 1e-9, "seviye \(id): hpMultiplier hook ile tutarsız")
            XCTAssertGreaterThanOrEqual(lvl.hpMultiplier, 0.8, "seviye \(id)")
            XCTAssertLessThanOrEqual(lvl.hpMultiplier, 6.0, "seviye \(id)")
            XCTAssertEqual(LevelGenerator.compositionD(id),
                           min(LevelGenerator.difficultyIndex(id), 1.3),
                           accuracy: 1e-9, "seviye \(id): kompozisyon tavanı")
        }
    }

    // MARK: - Dalga bütçeleri

    func testWaveBudgetsExactLevels() {
        // Örneklem seviyelerde HER dalga ±%15 bandında.
        for id in [1, 10, 25, 50] {
            let lvl = LevelGenerator.level(id)
            XCTAssertEqual(lvl.waves.count, 10, "seviye \(id)")
            for (i, wave) in lvl.waves.enumerated() {
                let want = budget(id, i + 1)
                let got = waveHP(wave)
                XCTAssertGreaterThanOrEqual(got, want * 0.85,
                    "seviye \(id) dalga \(i+1): HP \(got) < %85 × \(want)")
                XCTAssertLessThanOrEqual(got, want * 1.15,
                    "seviye \(id) dalga \(i+1): HP \(got) > %115 × \(want)")
            }
        }
    }

    func testWaveBudgetsTotalsAllLevels() {
        // Diğer seviyeler: 10 dalganın toplam HP'si toplam bütçenin ±%15'inde.
        for id in 1...50 {
            let lvl = LevelGenerator.level(id)
            let wantTotal = (1...10).reduce(0.0) { $0 + budget(id, $1) }
            let gotTotal = lvl.waves.reduce(0.0) { $0 + waveHP($1) }
            XCTAssertGreaterThanOrEqual(gotTotal, wantTotal * 0.85, "seviye \(id)")
            XCTAssertLessThanOrEqual(gotTotal, wantTotal * 1.15, "seviye \(id)")
        }
    }

    // MARK: - Tanıtım takvimi / boss / mini-boss

    func testIntroScheduleHonored() {
        for id in 1...50 {
            let lvl = LevelGenerator.level(id)
            for wave in lvl.waves {
                for group in wave.groups {
                    XCTAssertGreaterThanOrEqual(id, introLevel(group.kind),
                        "seviye \(id): \(group.kind) tanıtımından önce")
                }
            }
        }
    }

    func testBossExactlyOnMultiplesOfTen() {
        for id in 1...50 {
            let lvl = LevelGenerator.level(id)
            let bossCount = lvl.waves.flatMap(\.groups)
                .filter { $0.kind == .boss }
                .reduce(0) { $0 + $1.count }
            if id % 10 == 0 {
                XCTAssertEqual(bossCount, 1, "seviye \(id): tam 1 boss olmalı")
                let lastWaveBoss = lvl.waves[9].groups.contains { $0.kind == .boss }
                XCTAssertTrue(lastWaveBoss, "seviye \(id): boss 10. dalgada olmalı")
            } else {
                XCTAssertEqual(bossCount, 0, "seviye \(id): boss olmamalı")
            }
        }
    }

    func testMiniBossOnMultiplesOfFive() {
        // L%5==0 && L%10!=0 ve armored tanıtılmışsa (L≥8): 10. dalgada ≥3 armored.
        for id in [15, 25, 35, 45] {
            let lvl = LevelGenerator.level(id)
            let armoredInFinal = lvl.waves[9].groups
                .filter { $0.kind == .armored }
                .reduce(0) { $0 + $1.count }
            XCTAssertGreaterThanOrEqual(armoredInFinal, 3, "seviye \(id): mini-boss paketi eksik")
        }
    }

    func testSpawnIntervalsInBand() {
        for id in [1, 10, 25, 50] {
            let lvl = LevelGenerator.level(id)
            for wave in lvl.waves {
                for group in wave.groups {
                    XCTAssertGreaterThanOrEqual(group.interval, 0.25, "seviye \(id)")
                    XCTAssertLessThanOrEqual(group.interval, 1.2, "seviye \(id)")
                }
            }
        }
    }

    // MARK: - Enstrümantasyon: tohum reddi

    func testMapGenerationAttemptsWithinLimit() {
        var totalAttempts = 0
        var rejected = 0
        var rivers = 0
        for id in 1...50 {
            let candidate = LevelGenerator.generateMap(id: id)
            XCTAssertLessThanOrEqual(candidate.attempts, 20, "seviye \(id)")
            totalAttempts += candidate.attempts
            rejected += candidate.attempts - 1
            if candidate.hasRiver { rivers += 1 }
        }
        let scheduledRivers = (1...50).filter { $0 >= 8 && $0 % 3 == 0 }.count
        print("[üreteç] 50 seviye: toplam deneme \(totalAttempts), " +
              "reddedilen tohum \(rejected) (ort. \(Double(rejected) / 50)/seviye), " +
              "nehir \(rivers)/\(scheduledRivers) takvimli seviyede")
    }

    // MARK: - Adlar + meta

    func testNamesUniqueAcross50() {
        let names = (1...50).map { LevelGenerator.level($0).name }
        XCTAssertEqual(Set(names).count, 50, "adlar benzersiz olmalı")
        for name in names {
            XCTAssertTrue(name.contains(" "), "ad 'Ön Arka' biçiminde olmalı: \(name)")
        }
    }

    func testMetaMatchesLevels() {
        let meta = LevelGenerator.meta(50)
        XCTAssertEqual(meta.count, 50)
        for entry in meta {
            let lvl = LevelGenerator.level(entry.id)
            XCTAssertEqual(entry.name, lvl.name, "seviye \(entry.id)")
            XCTAssertEqual(entry.hasRiver, !lvl.map.waterTiles.isEmpty, "seviye \(entry.id)")
        }
    }

    // MARK: - Palet (V2 — sahne çim tonu endeksi)

    func testPaletteDeterministicAndInRange() {
        for id in 1...50 {
            let p = LevelGenerator.level(id).palette
            XCTAssertTrue((0...2).contains(p), "seviye \(id): palet \(p) aralık dışı")
            XCTAssertEqual(p, LevelGenerator.level(id).palette,
                           "seviye \(id): palet deterministik olmalı")
        }
    }

    func testPaletteDistributionNonDegenerate() {
        // 50 seviyede en az 2 farklı palet görülmeli — sabit/yozlaşmış dağılım yakalanır.
        let distinct = Set((1...50).map { LevelGenerator.level($0).palette })
        XCTAssertGreaterThanOrEqual(distinct.count, 2, "paletler: \(distinct)")
    }

    func testDailyPaletteDeterministicAndInRange() {
        let a = LevelGenerator.daily(year: 2026, month: 6, day: 12).palette
        let b = LevelGenerator.daily(year: 2026, month: 6, day: 12).palette
        XCTAssertEqual(a, b, "günlük palet deterministik olmalı")
        XCTAssertTrue((0...2).contains(a))
    }
}

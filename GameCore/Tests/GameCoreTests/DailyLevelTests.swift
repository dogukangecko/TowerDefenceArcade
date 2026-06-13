import XCTest
@testable import GameCore

/// E3 — Günlük Meydan Okuma üreteci: tarihe tohumlu, deterministik, tek seviye.
final class DailyLevelTests: XCTestCase {
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

    /// İki günün seviyesi "farklı" mı: harita yolu YA DA dalga bileşimi ayrışmalı.
    private func levelsDiffer(_ a: LevelDefinition, _ b: LevelDefinition) -> Bool {
        if a.map.pathOrder != b.map.pathOrder { return true }
        if a.map.waterTiles != b.map.waterTiles { return true }
        guard a.waves.count == b.waves.count else { return true }
        for (wa, wb) in zip(a.waves, b.waves) {
            guard wa.groups.count == wb.groups.count else { return true }
            for (ga, gb) in zip(wa.groups, wb.groups) {
                if ga.kind != gb.kind || ga.count != gb.count { return true }
            }
        }
        return false
    }

    // MARK: - Determinizm

    func testSameDayProducesIdenticalLevel() {
        let a = LevelGenerator.daily(year: 2026, month: 6, day: 12)
        let b = LevelGenerator.daily(year: 2026, month: 6, day: 12)
        XCTAssertEqual(a.id, 0, "günlük seviye id 0 (sefer dışı işaret) taşımalı")
        XCTAssertEqual(a.name, b.name)
        XCTAssertEqual(a.map.pathOrder, b.map.pathOrder)
        XCTAssertEqual(a.map.waterTiles, b.map.waterTiles)
        XCTAssertEqual(a.map.spawn, b.map.spawn)
        XCTAssertEqual(a.map.base, b.map.base)
        assertSameWaves(a.waves, b.waves)
    }

    // MARK: - Günler farklı (iki örnek çift)

    func testConsecutiveDaysDiffer() {
        let a = LevelGenerator.daily(year: 2026, month: 6, day: 12)
        let b = LevelGenerator.daily(year: 2026, month: 6, day: 13)
        XCTAssertTrue(levelsDiffer(a, b), "ardışık günler aynı seviyeyi üretmemeli")
    }

    func testDistantDaysDiffer() {
        let a = LevelGenerator.daily(year: 2026, month: 1, day: 1)
        let b = LevelGenerator.daily(year: 2027, month: 1, day: 1)
        XCTAssertTrue(levelsDiffer(a, b), "farklı yıllar aynı seviyeyi üretmemeli")
    }

    // MARK: - Sabitler: hpMultiplier 2.2, 10 dalga, ad öneki

    func testFixedHPMultiplierTenWavesAndNamePrefix() {
        for day in [1, 7, 15, 28] {
            let lvl = LevelGenerator.daily(year: 2026, month: 6, day: day)
            XCTAssertEqual(lvl.hpMultiplier, 2.2, accuracy: 1e-12, "gün \(day)")
            XCTAssertEqual(lvl.waves.count, 10, "gün \(day)")
            XCTAssertTrue(lvl.name.hasPrefix("Günlük: "), "gün \(day): \(lvl.name)")
            // Önekten sonrası üretilmiş "Ön Arka" adı olmalı.
            let rest = lvl.name.dropFirst("Günlük: ".count)
            XCTAssertTrue(rest.contains(" "), "gün \(day): üretilmiş ad eksik: \(lvl.name)")
        }
    }

    // MARK: - Harita kalitesi: aynı kabul/red hattı → M bandı + geçerlilik

    func testDailyMapsValidAndInMBand() {
        for day in 1...30 {
            let lvl = LevelGenerator.daily(year: 2026, month: 6, day: day)
            XCTAssertEqual(lvl.map.columns, 16, "gün \(day)")
            XCTAssertEqual(lvl.map.rows, 9, "gün \(day)")
            XCTAssertGreaterThanOrEqual(lvl.map.pathOrder.count, 20, "gün \(day): yol kısa")
            XCTAssertEqual(lvl.map.spawn.col, 0, "gün \(day)")
            XCTAssertEqual(lvl.map.base.col, 15, "gün \(day)")
            let m = LevelGenerator.normalizedMapScore(of: lvl.map)
            XCTAssertGreaterThanOrEqual(m, 0.7, "gün \(day): M=\(m) bandın altında")
            XCTAssertLessThanOrEqual(m, 1.4, "gün \(day): M=\(m) bandın üstünde")
        }
    }

    // MARK: - Nehir: tohumdan ~%40 kapı (takvim yok)

    func testDailyRiverRateRoughly40Percent() {
        var rivers = 0
        var total = 0
        for month in 1...12 {
            for day in 1...28 {
                let lvl = LevelGenerator.daily(year: 2026, month: month, day: day)
                total += 1
                if !lvl.map.waterTiles.isEmpty { rivers += 1 }
            }
        }
        let rate = Double(rivers) / Double(total)
        // %40 kapı + uygun sütun yoksa nehirsiz düşer → gerçek oran biraz altta.
        XCTAssertGreaterThan(rate, 0.15, "nehir oranı çok düşük: \(rate)")
        XCTAssertLessThan(rate, 0.55, "nehir oranı çok yüksek: \(rate)")
        print("[günlük] 336 günde nehir oranı: \(rate)")
    }
}

import XCTest
@testable import GameCore

/// G5 doğrulaması: BalanceLab `ayar` modunun ürettiği TunedDifficulty ile
/// örneklem seviyeler hedef bandın ±2 toleransında. Tolerans bilinçli geniş:
/// burada TEK politika (0.9) koşuyor, BalanceLab ise 3 varyantın MEDYANINI
/// banda oturtuyor — tek varyant medyandan sapabilir; sıkı bant BalanceLab'ın işi.
final class TunedDifficultyTests: XCTestCase {
    /// Spec hedef bantları (kalan can / 20): 1-10 ≥%90, 11-30 %70-90,
    /// 31-45 %45-75, 46-50 %30-60.
    static func band(for level: Int) -> ClosedRange<Int> {
        switch level {
        case 1...10: 18...20
        case 11...30: 14...18
        case 31...45: 9...15
        default: 6...12
        }
    }

    func testTunedTableShape() throws {
        try XCTSkipIf(TunedDifficulty.dByLevel.isEmpty, "ayar henüz üretilmedi (formül modunda)")
        XCTAssertEqual(TunedDifficulty.dByLevel.count, 50)
        for (i, d) in TunedDifficulty.dByLevel.enumerated() {
            XCTAssertGreaterThanOrEqual(d, 0.7, "L\(i + 1)")
            XCTAssertLessThanOrEqual(d, 2.4, "L\(i + 1)")
        }
    }

    /// H1b: dört kademenin de eğrisi tam (50 giriş) ve arama aralığında.
    /// Alt sınır: normal 0.8 (v2 aralığı — regresyon), diğer kademeler 0.85.
    func testTunedHPMultiplierTablesComplete() throws {
        try XCTSkipIf(TunedDifficulty.hpMultByTier.isEmpty, "ayar v3 henüz üretilmedi")
        for diff in Difficulty.allCases {
            let curve = try XCTUnwrap(TunedDifficulty.hpMultByTier[diff.rawValue],
                                      "\(diff.rawValue) eğrisi yok")
            XCTAssertEqual(curve.count, 50, "\(diff.rawValue)")
            let alt = diff == .normal ? 0.8 : 0.85
            for (i, h) in curve.enumerated() {
                XCTAssertGreaterThanOrEqual(h, alt, "\(diff.rawValue) L\(i + 1)")
                XCTAssertLessThanOrEqual(h, 6.0, "\(diff.rawValue) L\(i + 1)")
            }
        }
    }

    /// G5b: bandın HER İKİ kenarı ±2 toleransla assert edilir — birim-HP çarpanı
    /// κ gelir-nötrlüğünü deldiği için üst kenar artık ulaşılabilir (G5'teki
    /// "yalnız alt kenar" sınırlaması kalktı). Tolerans bilinçli geniş: burada
    /// TEK politika (0.9) koşuyor, BalanceLab 3 varyantın MEDYANINI banda oturtur.
    func testSampleLevelsWithinBandBothEdges() throws {
        try XCTSkipIf((TunedDifficulty.hpMultByTier["normal"] ?? []).count < 50,
                      "ayar v3 henüz üretilmedi")
        for id in [1, 5, 10, 20, 30, 40, 45, 48, 50] {
            let lvl = LevelGenerator.level(id)
            var policy = GreedyPolicy(buildBudgetRatio: 0.9)
            let r = Simulator.run(map: lvl.map, waves: lvl.waves,
                                  enemyHPMultiplier: lvl.hpMultiplier, policy: &policy)
            let band = Self.band(for: id)
            XCTAssertGreaterThanOrEqual(r.livesLeft, band.lowerBound - 2,
                "seviye \(id): can \(r.livesLeft) bandın (\(band)) -2 altında")
            XCTAssertLessThanOrEqual(r.livesLeft, band.upperBound + 2,
                "seviye \(id): can \(r.livesLeft) bandın (\(band)) +2 üstünde")
        }
    }
}

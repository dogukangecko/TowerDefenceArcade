import XCTest
@testable import GameCore

/// Result'tan hata değerini çeker; Success Equatable olmasa da hata karşılaştırması yapılabilir.
extension Result {
    var failureValue: Failure? {
        if case .failure(let f) = self { return f }
        return nil
    }
}

final class EngineEconomyTests: XCTestCase {
    var engine: GameEngine!
    let buildTile = GridPoint(col: 0, row: 1)

    override func setUp() {
        let map = try! MapDefinition.parse("""
        S##.
        ..#.
        ..B.
        """, tileSize: 80)
        engine = GameEngine(map: map)   // 140 altın, 20 can
    }

    func testBuildTower() throws {
        let tower = try engine.buildTower(.machineGun, at: buildTile).get()
        XCTAssertEqual(engine.gold, 90)
        XCTAssertEqual(engine.towers.count, 1)
        XCTAssertEqual(engine.tower(at: buildTile)?.id, tower.id)
    }

    func testBuildRejectsBadTiles() {
        XCTAssertEqual(engine.buildTower(.machineGun, at: GridPoint(col: 1, row: 0)).failureValue,
                       .tileNotBuildable)              // yol karesi
        _ = engine.buildTower(.machineGun, at: buildTile)
        XCTAssertEqual(engine.buildTower(.sniper, at: buildTile).failureValue,
                       .tileOccupied)                  // dolu kare
    }

    func testBuildRejectsInsufficientGold() {
        _ = engine.buildTower(.sniper, at: GridPoint(col: 0, row: 1))  // 120 → kalan 20
        XCTAssertEqual(engine.buildTower(.machineGun, at: GridPoint(col: 0, row: 2)).failureValue,
                       .insufficientGold)
        XCTAssertEqual(engine.gold, 20)
    }

    func testUpgrade() throws {
        // Geometrik maliyet: 2. seviye 40, 3. seviye 64 → varsayılan 140 altın yetmez.
        let rich = GameEngine(map: engine.map, gold: 200)
        let t = try rich.buildTower(.machineGun, at: buildTile).get()  // -50 → 150
        XCTAssertEqual(try rich.upgradeTower(id: t.id).get(), 2)       // -40 → 110
        XCTAssertEqual(try rich.upgradeTower(id: t.id).get(), 3)       // -64 → 46
        XCTAssertEqual(rich.gold, 46)
        XCTAssertEqual(rich.upgradeTower(id: t.id).failureValue, .maxLevelReached)
        XCTAssertEqual(rich.upgradeTower(id: 999).failureValue, .noTowerThere)
    }

    func testUpgradeRejectsInsufficientGold() throws {
        let t = try engine.buildTower(.sniper, at: buildTile).get()    // kalan 20
        XCTAssertEqual(engine.upgradeTower(id: t.id).failureValue, .insufficientGold) // 96 gerek
    }

    func testSellRefunds70PercentOfInvested() throws {
        let t = try engine.buildTower(.machineGun, at: buildTile).get() // 90 kaldı
        _ = engine.upgradeTower(id: t.id)                               // 50 kaldı, yatırım 90
        XCTAssertEqual(try engine.sellTower(id: t.id).get(), 63)        // 90 × 0.7
        XCTAssertEqual(engine.gold, 113)
        XCTAssertTrue(engine.towers.isEmpty)
        XCTAssertEqual(engine.sellTower(id: t.id).failureValue, .noTowerThere)
    }
}

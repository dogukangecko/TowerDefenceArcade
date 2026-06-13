import XCTest
@testable import GameCore

final class EnemyTests: XCTestCase {
    let map = try! MapDefinition.parse("""
    S##.
    ..#.
    ..B.
    """, tileSize: 80)

    func testAdvanceMovesAlongPath() {
        let e = Enemy(id: 1, kind: .infantry)   // hız 110
        let reached = e.advance(dt: 1.0, on: map)
        XCTAssertFalse(reached)
        XCTAssertEqual(e.pathDistance, 110, accuracy: 0.001)
        XCTAssertEqual(e.position(on: map).y, 40, accuracy: 0.001) // hâlâ üst satırda
        XCTAssertEqual(e.position(on: map).x, 150, accuracy: 0.001) // 40 + 110
    }

    func testReachesBase() {
        let e = Enemy(id: 1, kind: .scout)      // hız 210, yol 320
        XCTAssertFalse(e.advance(dt: 1.0, on: map))
        XCTAssertTrue(e.advance(dt: 1.0, on: map)) // 420 > 320
        XCTAssertEqual(e.pathDistance, 420, accuracy: 0.001)
    }

    // MARK: - Birim HP çarpanı (G5b)

    func testHPMultiplierScalesOnlyHP() {
        let e = Enemy(id: 1, kind: .infantry, hpMultiplier: 2.5)   // taban 60 HP
        XCTAssertEqual(e.maxHP, 150, accuracy: 1e-9)
        XCTAssertEqual(e.hp, 150, accuracy: 1e-9)
        // Taban istatistikler değişmez: hız/ödül/can bedeli gelir-nötr kalır.
        XCTAssertEqual(e.stats.maxHP, 60)
        XCTAssertEqual(e.stats.bounty, 7)
        XCTAssertEqual(e.stats.livesCost, 1)
    }

    func testDefaultHPMultiplierIsNeutral() {
        let e = Enemy(id: 1, kind: .infantry)
        XCTAssertEqual(e.maxHP, 60, accuracy: 1e-9)
        XCTAssertEqual(e.hp, e.maxHP, accuracy: 1e-9)
    }

    func testTakeDamageAndDeath() {
        let e = Enemy(id: 1, kind: .infantry)   // 60 HP
        e.takeDamage(25)
        XCTAssertEqual(e.hp, 35)
        XCTAssertTrue(e.isAlive)
        e.takeDamage(100)
        XCTAssertEqual(e.hp, 0)                 // negatife düşmez
        XCTAssertFalse(e.isAlive)
    }
}

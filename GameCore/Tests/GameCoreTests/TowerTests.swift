import XCTest
@testable import GameCore

final class TowerTests: XCTestCase {
    // Düz yol: 10 sütun, üst satır yol
    let map = try! MapDefinition.parse("""
    S########B
    ..........
    """, tileSize: 80)

    /// Düşmanı yolda tam `distance` noktasına taşır.
    private func enemy(id: Int, kind: EnemyKind = .infantry, at distance: Double) -> Enemy {
        let e = Enemy(id: id, kind: kind)
        _ = e.advance(dt: distance / e.stats.speed, on: map)
        return e
    }

    func testTowerInvestAndUpgrade() {
        let t = Tower(id: 1, kind: .machineGun, tile: GridPoint(col: 1, row: 1))
        XCTAssertEqual(t.level, 1)
        XCTAssertEqual(t.invested, 50)
        XCTAssertTrue(t.canUpgrade)
        t.upgrade(cost: Balance.upgradeCost(of: .machineGun, toLevel: 2))  // 40
        XCTAssertEqual(t.level, 2)
        XCTAssertEqual(t.invested, 90)
        t.upgrade(cost: Balance.upgradeCost(of: .machineGun, toLevel: 3))  // 64
        XCTAssertEqual(t.level, 3)
        XCTAssertEqual(t.invested, 154)
        XCTAssertFalse(t.canUpgrade)
    }

    func testTargetingPrefersFurthestInRange() {
        let t = Tower(id: 1, kind: .machineGun, tile: GridPoint(col: 1, row: 1)) // merkez (120,120), menzil 200
        let near = enemy(id: 1, at: 160)   // (200,40) → mesafe ~113, menzilde
        let far = enemy(id: 2, at: 240)    // (280,40) → mesafe ~179, menzilde
        let out = enemy(id: 3, at: 700)    // menzil dışı
        let target = Targeting.selectTarget(for: t, on: map, among: [near, far, out])
        XCTAssertEqual(target?.id, 2)
    }

    func testTargetingModes() {
        let t = Tower(id: 1, kind: .machineGun, tile: GridPoint(col: 1, row: 1)) // merkez (120,120), menzil 200
        // Üçü de menzilde: önde infantry (60 HP), ortada armored (260 HP, en güçlü),
        // geride scout (35 HP, kuleye en yakın: ~89 < ~113 < ~179).
        let front = enemy(id: 1, kind: .infantry, at: 240) // (280,40)
        let middle = enemy(id: 2, kind: .armored, at: 160) // (200,40)
        let back = enemy(id: 3, kind: .scout, at: 120)     // (160,40)
        let all = [back, middle, front]

        t.targetingMode = .first
        XCTAssertEqual(Targeting.selectTarget(for: t, on: map, among: all)?.id, 1)
        t.targetingMode = .strongest
        XCTAssertEqual(Targeting.selectTarget(for: t, on: map, among: all)?.id, 2)
        t.targetingMode = .nearest
        XCTAssertEqual(Targeting.selectTarget(for: t, on: map, among: all)?.id, 3)
    }

    func testTargetingIgnoresDeadAndOutOfRange() {
        let t = Tower(id: 1, kind: .machineGun, tile: GridPoint(col: 1, row: 1))
        let dead = enemy(id: 1, at: 160)
        dead.takeDamage(1000)
        let out = enemy(id: 2, at: 700)
        XCTAssertNil(Targeting.selectTarget(for: t, on: map, among: [dead, out]))
        XCTAssertNil(Targeting.selectTarget(for: t, on: map, among: []))
    }
}

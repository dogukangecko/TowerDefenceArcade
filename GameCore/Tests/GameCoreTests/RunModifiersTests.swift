import XCTest
@testable import GameCore

final class RunModifiersTests: XCTestCase {
    let straightMap = try! MapDefinition.parse("""
    S########B
    ..........
    """, tileSize: 80)

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

    func testNoneModifiersKeepDefaults() {
        let engine = GameEngine(map: straightMap, modifiers: .none)
        XCTAssertEqual(engine.gold, Balance.startingGold)
        XCTAssertEqual(engine.lives, Balance.startingLives)
    }

    func testDefaultInitEqualsNone() {
        // modifiers parametresi verilmeden kurulan engine .none ile birebir aynı
        let engine = GameEngine(map: straightMap)
        XCTAssertEqual(engine.gold, Balance.startingGold)
        XCTAssertEqual(engine.lives, Balance.startingLives)
    }

    func testStartGoldBonusAndExtraLives() {
        let mods = RunModifiers(startGoldBonus: 50, damageMultiplier: 1.5, extraLives: 2)
        let engine = GameEngine(map: straightMap, modifiers: mods)
        XCTAssertEqual(engine.gold, Balance.startingGold + 50)
        XCTAssertEqual(engine.lives, Balance.startingLives + 2)
    }

    func testDamageMultiplierAppliesToSingleTargetShot() {
        // Makineli: hasar 6 × 1.5 = 9; piyade 60 HP → ilk atıştan sonra 51
        let mods = RunModifiers(startGoldBonus: 0, damageMultiplier: 1.5, extraLives: 0)
        let waves = [WaveDefinition(groups: [SpawnGroup(kind: .infantry, count: 1, interval: 0)])]
        let engine = GameEngine(map: straightMap, waves: waves, modifiers: mods)
        _ = engine.buildTower(.machineGun, at: GridPoint(col: 1, row: 1))
        _ = engine.startNextWave()
        run(engine, seconds: 1.0 / 60.0 + 0.001, step: 1.0 / 60.0)  // tek update → tek atış

        let expected = Balance.stats(for: EnemyKind.infantry).maxHP
            - Balance.stats(for: .machineGun, level: 1).damage * 1.5
        XCTAssertEqual(engine.enemies.first?.hp ?? -1, expected, accuracy: 0.001)
    }

    func testDamageMultiplierAppliesToSplash() {
        // Roket: hasar 25 × 1.5 = 37.5; aynı anda doğan 3 piyade 60 → 22.5
        let mods = RunModifiers(startGoldBonus: 0, damageMultiplier: 1.5, extraLives: 0)
        let waves = [WaveDefinition(groups: [SpawnGroup(kind: .infantry, count: 3, interval: 0)])]
        let engine = GameEngine(map: straightMap, waves: waves, modifiers: mods)
        _ = engine.buildTower(.rocket, at: GridPoint(col: 1, row: 1))
        _ = engine.startNextWave()
        run(engine, seconds: 0.1)                 // ilk atış

        XCTAssertEqual(engine.enemies.count, 3)
        for e in engine.enemies {
            XCTAssertEqual(e.hp, 60 - 25 * 1.5, accuracy: 0.001)
        }
    }
}

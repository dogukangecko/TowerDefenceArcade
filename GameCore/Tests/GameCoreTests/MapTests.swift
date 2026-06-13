import XCTest
@testable import GameCore

final class MapTests: XCTestCase {
    let mini = """
    S##.
    ..#.
    ..B.
    """

    func testParseMiniMap() throws {
        let map = try MapDefinition.parse(mini, tileSize: 80)
        XCTAssertEqual(map.columns, 4)
        XCTAssertEqual(map.rows, 3)
        XCTAssertEqual(map.spawn, GridPoint(col: 0, row: 0))
        XCTAssertEqual(map.base, GridPoint(col: 2, row: 2))
        XCTAssertEqual(map.pathOrder, [
            GridPoint(col: 0, row: 0), GridPoint(col: 1, row: 0), GridPoint(col: 2, row: 0),
            GridPoint(col: 2, row: 1), GridPoint(col: 2, row: 2),
        ])
        XCTAssertEqual(map.totalPathLength, 320) // 4 adım × 80
        XCTAssertEqual(map.pathTiles.count, 5)
    }

    func testBuildable() throws {
        let map = try MapDefinition.parse(mini, tileSize: 80)
        XCTAssertTrue(map.isBuildable(GridPoint(col: 0, row: 1)))
        XCTAssertFalse(map.isBuildable(GridPoint(col: 1, row: 0)))  // yol
        XCTAssertFalse(map.isBuildable(GridPoint(col: 4, row: 0)))  // sınır dışı
    }

    func testPositionAlongPath() throws {
        let map = try MapDefinition.parse(mini, tileSize: 80)
        XCTAssertEqual(map.position(atPathDistance: 0), Vec2(x: 40, y: 40))
        XCTAssertEqual(map.position(atPathDistance: 80), Vec2(x: 120, y: 40))
        XCTAssertEqual(map.position(atPathDistance: 120), Vec2(x: 160, y: 40))
        XCTAssertEqual(map.position(atPathDistance: 999), Vec2(x: 200, y: 200)) // sona kenetlenir
    }

    func testTileLookup() throws {
        let map = try MapDefinition.parse(mini, tileSize: 80)
        XCTAssertEqual(map.tile(at: Vec2(x: 100, y: 100)), GridPoint(col: 1, row: 1))
        XCTAssertNil(map.tile(at: Vec2(x: -5, y: 10)))
    }

    func testParseErrors() {
        XCTAssertThrowsError(try MapDefinition.parse("..B", tileSize: 80)) {
            XCTAssertEqual($0 as? MapError, .missingSpawn)
        }
        XCTAssertThrowsError(try MapDefinition.parse("S#.", tileSize: 80)) {
            XCTAssertEqual($0 as? MapError, .missingBase)
        }
        // Kopuk yol: (1,0)'dan B'ye komşuluk yok
        XCTAssertThrowsError(try MapDefinition.parse("S#.B", tileSize: 80)) {
            XCTAssertEqual($0 as? MapError, .brokenPath(at: GridPoint(col: 1, row: 0)))
        }
        // Dallanan yol
        let branching = """
        S#B
        .#.
        """
        XCTAssertThrowsError(try MapDefinition.parse(branching, tileSize: 80)) {
            XCTAssertEqual($0 as? MapError, .brokenPath(at: GridPoint(col: 1, row: 0)))
        }
        XCTAssertThrowsError(try MapDefinition.parse("S##\n#B", tileSize: 80)) {
            XCTAssertEqual($0 as? MapError, .inconsistentRowLength(row: 1))
        }
    }

    func testClassic() {
        let map = Maps.classic()
        XCTAssertEqual(map.columns, 16)
        XCTAssertEqual(map.rows, 9)
        XCTAssertEqual(map.spawn, GridPoint(col: 0, row: 1))
        XCTAssertEqual(map.base, GridPoint(col: 11, row: 8))
        XCTAssertEqual(map.pathOrder.count, 35)
        XCTAssertEqual(map.totalPathLength, 34 * 80)
    }

    // Su: '~' karesi inşa edilemez; yol suyu kesebilir ('#' su DEĞİLDİR).
    let pond = """
    .~.
    S#B
    .~.
    """

    func testWaterParsing() throws {
        let map = try MapDefinition.parse(pond, tileSize: 80)
        XCTAssertEqual(map.waterTiles,
                       [GridPoint(col: 1, row: 0), GridPoint(col: 1, row: 2)])
        // Yol karesi su karelerinin ARASINDAN geçer ama su sayılmaz.
        XCTAssertFalse(map.waterTiles.contains(GridPoint(col: 1, row: 1)))
        XCTAssertEqual(map.pathOrder, [
            GridPoint(col: 0, row: 1), GridPoint(col: 1, row: 1), GridPoint(col: 2, row: 1),
        ])
    }

    func testWaterNotBuildable() throws {
        let map = try MapDefinition.parse(pond, tileSize: 80)
        XCTAssertFalse(map.isBuildable(GridPoint(col: 1, row: 0)))  // su
        XCTAssertFalse(map.isBuildable(GridPoint(col: 1, row: 2)))  // su
        XCTAssertFalse(map.isBuildable(GridPoint(col: 1, row: 1)))  // yol (köprü)
        XCTAssertTrue(map.isBuildable(GridPoint(col: 0, row: 0)))   // çim
        XCTAssertTrue(map.isBuildable(GridPoint(col: 2, row: 2)))   // çim
    }

    func testClassicHasNoWater() {
        XCTAssertTrue(Maps.classic().waterTiles.isEmpty)
    }

    func testRiverMap() {
        let map = Maps.river()
        XCTAssertEqual(map.columns, 16)
        XCTAssertEqual(map.rows, 9)
        XCTAssertFalse(map.waterTiles.isEmpty)
        // Su ve yol kümeleri ayrıktır.
        XCTAssertTrue(map.waterTiles.isDisjoint(with: map.pathTiles))
        // Yol nehri keser: en az bir yol karesinin hem üstü hem altı su
        // (dikey nehir şeridi yatay yolla geçilir).
        let crossings = map.pathTiles.filter {
            map.waterTiles.contains(GridPoint(col: $0.col, row: $0.row - 1))
                && map.waterTiles.contains(GridPoint(col: $0.col, row: $0.row + 1))
        }
        XCTAssertFalse(crossings.isEmpty)
        // Nehir TEK kez kesilir: tüm geçiş kareleri aynı satırda.
        XCTAssertEqual(Set(crossings.map(\.row)).count, 1)
    }

    func testMapsAll() {
        XCTAssertEqual(Maps.all.map(\.name), ["Klasik Vadi", "Nehir Geçidi"])
        XCTAssertEqual(Maps.all[0].map.columns, Maps.classic().columns)
        XCTAssertFalse(Maps.all[1].map.waterTiles.isEmpty)
    }

    func testPathSidesMini() throws {
        let map = try MapDefinition.parse(mini, tileSize: 80)
        XCTAssertEqual(map.pathSides(of: GridPoint(col: 0, row: 1)), [.up])          // üstünde S
        XCTAssertEqual(map.pathSides(of: GridPoint(col: 1, row: 1)), [.up, .right])  // viraj içi
        XCTAssertEqual(map.pathSides(of: GridPoint(col: 3, row: 0)), [.left])
        XCTAssertEqual(map.pathSides(of: GridPoint(col: 0, row: 2)), [])
        // Yol karesi için de saf çalışır: (1,0) düz segment
        XCTAssertEqual(map.pathSides(of: GridPoint(col: 1, row: 0)), [.left, .right])
    }

    func testPathSidesClassic() {
        let map = Maps.classic()
        XCTAssertEqual(map.pathSides(of: GridPoint(col: 0, row: 0)), [.down])
        XCTAssertEqual(map.pathSides(of: GridPoint(col: 12, row: 1)), [.left])
        XCTAssertEqual(map.pathSides(of: GridPoint(col: 4, row: 3)), [.down])
        XCTAssertEqual(map.pathSides(of: GridPoint(col: 5, row: 5)), [.up, .down])   // iki yol şeridi arası
        XCTAssertEqual(map.pathSides(of: GridPoint(col: 14, row: 4)), [])
    }

    func testPathShapeClassification() throws {
        let map = try MapDefinition.parse("""
        S##..
        ..#..
        ..##B
        """, tileSize: 10)
        // Spawn: sağa açılır
        XCTAssertEqual(map.pathShape(of: GridPoint(col: 0, row: 0)), .spawnCap(open: .right))
        // Düz yatay
        XCTAssertEqual(map.pathShape(of: GridPoint(col: 1, row: 0)), .straight(vertical: false))
        // Köşe: soldan gelir (left), aşağı gider (down)
        XCTAssertEqual(map.pathShape(of: GridPoint(col: 2, row: 0)), .corner(sides: [.left, .down]))
        // Düz dikey
        XCTAssertEqual(map.pathShape(of: GridPoint(col: 2, row: 1)), .straight(vertical: true))
        // Köşe: yukarıdan gelir, sağa gider
        XCTAssertEqual(map.pathShape(of: GridPoint(col: 2, row: 2)), .corner(sides: [.up, .right]))
        // Üs: soldan açılır
        XCTAssertEqual(map.pathShape(of: GridPoint(col: 4, row: 2)), .baseCap(open: .left))
        // Yol olmayan kare nil
        XCTAssertNil(map.pathShape(of: GridPoint(col: 0, row: 1)))
    }

    func testPathShapeSingleTileNeighborDirections() throws {
        let map = try MapDefinition.parse("""
        .S.
        .#.
        .B.
        """, tileSize: 10)
        XCTAssertEqual(map.pathShape(of: GridPoint(col: 1, row: 0)), .spawnCap(open: .down))
        XCTAssertEqual(map.pathShape(of: GridPoint(col: 1, row: 1)), .straight(vertical: true))
        XCTAssertEqual(map.pathShape(of: GridPoint(col: 1, row: 2)), .baseCap(open: .up))
    }
}

import XCTest
@testable import GameCore

final class GeometryTests: XCTestCase {
    func testVec2Operations() {
        let a = Vec2(x: 3, y: 4)
        XCTAssertEqual(a.length, 5)
        XCTAssertEqual(a + Vec2(x: 1, y: 1), Vec2(x: 4, y: 5))
        XCTAssertEqual(a - Vec2(x: 1, y: 1), Vec2(x: 2, y: 3))
        XCTAssertEqual(a * 2, Vec2(x: 6, y: 8))
        XCTAssertEqual(Vec2(x: 0, y: 0).distance(to: a), 5)
    }

    func testGridPointHashable() {
        let set: Set<GridPoint> = [GridPoint(col: 1, row: 2), GridPoint(col: 1, row: 2)]
        XCTAssertEqual(set.count, 1)
    }
}

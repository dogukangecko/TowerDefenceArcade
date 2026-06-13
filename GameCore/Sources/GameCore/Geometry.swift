public struct Vec2: Equatable, Sendable {
    public var x: Double
    public var y: Double

    public init(x: Double, y: Double) {
        self.x = x
        self.y = y
    }

    public static func + (a: Vec2, b: Vec2) -> Vec2 { Vec2(x: a.x + b.x, y: a.y + b.y) }
    public static func - (a: Vec2, b: Vec2) -> Vec2 { Vec2(x: a.x - b.x, y: a.y - b.y) }
    public static func * (a: Vec2, s: Double) -> Vec2 { Vec2(x: a.x * s, y: a.y * s) }

    public var length: Double { (x * x + y * y).squareRoot() }
    public func distance(to other: Vec2) -> Double { (self - other).length }
}

public struct GridPoint: Hashable, Sendable {
    public var col: Int
    public var row: Int

    public init(col: Int, row: Int) {
        self.col = col
        self.row = row
    }
}

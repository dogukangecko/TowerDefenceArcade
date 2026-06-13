public enum MapError: Error, Equatable {
    case missingSpawn
    case missingBase
    case brokenPath(at: GridPoint)
    case inconsistentRowLength(row: Int)
}

public struct MapDefinition: Sendable {
    public let columns: Int
    public let rows: Int
    public let tileSize: Double
    public let spawn: GridPoint
    public let base: GridPoint
    public let pathTiles: Set<GridPoint>
    public let waterTiles: Set<GridPoint>   // '~' kareleri; inşa edilemez, yol değildir
    public let pathOrder: [GridPoint]   // spawn'dan üsse sıralı tile listesi
    public let totalPathLength: Double

    public func center(of tile: GridPoint) -> Vec2 {
        Vec2(x: (Double(tile.col) + 0.5) * tileSize,
             y: (Double(tile.row) + 0.5) * tileSize)
    }

    public func tile(at p: Vec2) -> GridPoint? {
        guard p.x >= 0, p.y >= 0 else { return nil }
        let c = Int(p.x / tileSize), r = Int(p.y / tileSize)
        guard c < columns, r < rows else { return nil }
        return GridPoint(col: c, row: r)
    }

    public func isBuildable(_ tile: GridPoint) -> Bool {
        tile.col >= 0 && tile.row >= 0 && tile.col < columns && tile.row < rows
            && !pathTiles.contains(tile) && !waterTiles.contains(tile)
    }

    /// Yol başından `d` nokta uzaklıktaki konum; sona kenetlenir.
    public func position(atPathDistance d: Double) -> Vec2 {
        let clamped = max(0, min(d, totalPathLength))
        let index = Int(clamped / tileSize)
        guard index < pathOrder.count - 1 else { return center(of: pathOrder[pathOrder.count - 1]) }
        let t = (clamped - Double(index) * tileSize) / tileSize
        let a = center(of: pathOrder[index])
        let b = center(of: pathOrder[index + 1])
        return a + (b - a) * t
    }

    public static func parse(_ ascii: String, tileSize: Double) throws -> MapDefinition {
        let lines = ascii.split(separator: "\n").map(String.init)
        let columns = lines[0].count
        var pathSet = Set<GridPoint>()
        var waterSet = Set<GridPoint>()
        var spawn: GridPoint?
        var base: GridPoint?

        for (r, line) in lines.enumerated() {
            guard line.count == columns else { throw MapError.inconsistentRowLength(row: r) }
            for (c, ch) in line.enumerated() {
                let p = GridPoint(col: c, row: r)
                switch ch {
                case "#": pathSet.insert(p)
                case "S": pathSet.insert(p); spawn = p
                case "B": pathSet.insert(p); base = p
                case "~": waterSet.insert(p)   // su; yol '#' önceliklidir (köprü sahnede çizilir)
                default: break
                }
            }
        }
        guard let s = spawn else { throw MapError.missingSpawn }
        guard let b = base else { throw MapError.missingBase }

        // S'den B'ye yürü: her adımda tam bir ziyaret edilmemiş yol komşusu olmalı
        var order = [s]
        var visited: Set<GridPoint> = [s]
        var current = s
        while current != b {
            let neighbors = [
                GridPoint(col: current.col + 1, row: current.row),
                GridPoint(col: current.col - 1, row: current.row),
                GridPoint(col: current.col, row: current.row + 1),
                GridPoint(col: current.col, row: current.row - 1),
            ].filter { pathSet.contains($0) && !visited.contains($0) }
            guard neighbors.count == 1 else { throw MapError.brokenPath(at: current) }
            current = neighbors[0]
            visited.insert(current)
            order.append(current)
        }

        return MapDefinition(
            columns: columns, rows: lines.count, tileSize: tileSize,
            spawn: s, base: b, pathTiles: pathSet, waterTiles: waterSet, pathOrder: order,
            totalPathLength: Double(order.count - 1) * tileSize)
    }
}

/// Izgara uzayında dik yön (row artışı = down — satır 0 üsttedir).
public enum Direction: CaseIterable, Sendable, Hashable {
    case up, down, left, right

    func neighbor(of tile: GridPoint) -> GridPoint {
        switch self {
        case .up: GridPoint(col: tile.col, row: tile.row - 1)
        case .down: GridPoint(col: tile.col, row: tile.row + 1)
        case .left: GridPoint(col: tile.col - 1, row: tile.row)
        case .right: GridPoint(col: tile.col + 1, row: tile.row)
        }
    }
}

extension MapDefinition {
    /// Verilen karenin dik komşularından yol olanların yönleri.
    /// Her kare için saf çalışır; sahne yalnızca yol olmayan karelerde overlay basar.
    public func pathSides(of tile: GridPoint) -> Set<Direction> {
        Set(Direction.allCases.filter { pathTiles.contains($0.neighbor(of: tile)) })
    }
}

/// Yol karesinin görsel şekli — sahne, tile dokusunu ve dönüşünü buradan seçer.
public enum PathTileShape: Equatable, Sendable {
    case straight(vertical: Bool)
    case corner(sides: Set<Direction>)   // tam iki dik komşu yön
    case spawnCap(open: Direction)
    case baseCap(open: Direction)
}

extension MapDefinition {
    /// İki kare arasındaki ızgara yönü (komşu olmalı).
    private func direction(from a: GridPoint, to b: GridPoint) -> Direction {
        if b.col > a.col { return .right }
        if b.col < a.col { return .left }
        if b.row > a.row { return .down }
        return .up
    }

    /// Yol karesinin şekli; yol değilse nil. pathOrder üzerinden önceki/sonraki
    /// kareye bakar — kavşak yoktur (parse tek zincir garantiler).
    public func pathShape(of tile: GridPoint) -> PathTileShape? {
        guard let index = pathOrder.firstIndex(of: tile) else { return nil }
        if index == 0 {
            return .spawnCap(open: direction(from: tile, to: pathOrder[1]))
        }
        if index == pathOrder.count - 1 {
            return .baseCap(open: direction(from: tile, to: pathOrder[index - 1]))
        }
        let back = direction(from: tile, to: pathOrder[index - 1])
        let forward = direction(from: tile, to: pathOrder[index + 1])
        let vertical: Set<Direction> = [.up, .down]
        if vertical.contains(back) == vertical.contains(forward) {
            return .straight(vertical: vertical.contains(back))
        }
        return .corner(sides: [back, forward])
    }
}

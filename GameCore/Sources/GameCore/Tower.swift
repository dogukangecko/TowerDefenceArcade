/// Kulenin menzil içindeki düşmanlardan hangisini seçeceği.
public enum TargetingMode: String, CaseIterable, Sendable {
    case first, strongest, nearest
}

public final class Tower: Identifiable {
    public let id: Int
    public let kind: TowerKind
    public let tile: GridPoint
    public private(set) var level = 1
    public private(set) var invested: Int
    public var targetingMode: TargetingMode = .first
    var cooldown: Double = 0

    public var stats: TowerStats { Balance.stats(for: kind, level: level) }
    public var canUpgrade: Bool { level < Balance.maxTowerLevel }

    init(id: Int, kind: TowerKind, tile: GridPoint) {
        self.id = id
        self.kind = kind
        self.tile = tile
        self.invested = Balance.cost(of: kind)
    }

    func upgrade(cost: Int) {
        guard canUpgrade else { return }
        level += 1
        invested += cost
    }
}

public enum Targeting {
    /// Menzil içindeki canlı düşmanlardan kulenin hedefleme moduna göre seçim yapar.
    public static func selectTarget(for tower: Tower, on map: MapDefinition,
                                    among enemies: [Enemy]) -> Enemy? {
        let towerPos = map.center(of: tower.tile)
        let range = tower.stats.range
        let inRange = enemies
            .filter { $0.isAlive && $0.position(on: map).distance(to: towerPos) <= range }
        switch tower.targetingMode {
        case .first:
            return inRange.max(by: { $0.pathDistance < $1.pathDistance })
        case .strongest:
            // Ölçekli maxHP (taban × HP çarpanı): çarpan motor genelinde tekdüze
            // olduğundan sıralama tabanla aynı; gelecekteki tür-bazlı çarpanlara dayanıklı.
            return inRange.max(by: { $0.maxHP < $1.maxHP })
        case .nearest:
            return inRange.min(by: {
                $0.position(on: map).distance(to: towerPos) < $1.position(on: map).distance(to: towerPos)
            })
        }
    }
}

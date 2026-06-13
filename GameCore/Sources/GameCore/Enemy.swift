public final class Enemy: Identifiable {
    public let id: Int
    public let kind: EnemyKind
    /// TABAN istatistikler (hız, ödül, can bedeli ve taban HP). Ödül/can bedeli
    /// her zaman buradan okunur — birim HP çarpanı GELİR-NÖTRDÜR (κ ekonomisi
    /// delinir: düşman zorlaşır ama daha fazla altın getirmez).
    public let stats: EnemyStats
    /// Ölçekli azami HP = stats.maxHP × hpMultiplier. Can barı oranı ve ölüm
    /// eşiği BU değeri kullanır; stats.maxHP taban arama tablosu olarak kalır.
    public let maxHP: Double
    /// Etkili hız = stats.speed × hız çarpanı (E4 hizliDusmanlar; varsayılan 1).
    /// Hareket BU değeri kullanır; stats.speed taban arama tablosu olarak kalır.
    public let speed: Double
    public private(set) var hp: Double
    public private(set) var pathDistance: Double = 0

    public var isAlive: Bool { hp > 0 }

    init(id: Int, kind: EnemyKind, hpMultiplier: Double = 1.0,
         speedMultiplier: Double = 1.0) {
        let s = Balance.stats(for: kind)
        self.id = id
        self.kind = kind
        self.stats = s
        self.maxHP = s.maxHP * hpMultiplier
        self.hp = s.maxHP * hpMultiplier
        self.speed = s.speed * speedMultiplier
    }

    public func position(on map: MapDefinition) -> Vec2 {
        map.position(atPathDistance: pathDistance)
    }

    /// true dönerse düşman üsse ulaştı.
    func advance(dt: Double, on map: MapDefinition) -> Bool {
        guard isAlive, pathDistance < map.totalPathLength else {
            return pathDistance >= map.totalPathLength
        }
        pathDistance += speed * dt
        return pathDistance >= map.totalPathLength
    }

    func takeDamage(_ amount: Double) {
        hp = max(0, hp - amount)
    }
}

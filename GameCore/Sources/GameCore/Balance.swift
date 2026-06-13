import Foundation

public enum TowerKind: String, CaseIterable, Sendable {
    case machineGun, rocket, sniper, crystal, shock, orb, dart, solar
}

public enum EnemyKind: String, CaseIterable, Sendable {
    case infantry, scout, armored, boss, scorpion, clampbeetle, voidbutterfly, locust

    /// Uçan düşmanlar sahnede gölge + havada süzülme görseliyle çizilir;
    /// yol takibi aynıdır (oynanış değişmez).
    public var isFlying: Bool {
        switch self {
        case .boss, .clampbeetle, .voidbutterfly, .locust: return true
        case .infantry, .scout, .armored, .scorpion: return false
        }
    }
}

public struct TowerStats: Sendable {
    public let damage: Double
    public let range: Double
    public let fireInterval: Double
    public let splashRadius: Double   // 0 = tek hedef
}

public struct EnemyStats: Sendable {
    public let maxHP: Double
    public let speed: Double          // nokta/saniye
    public let bounty: Int
    public let livesCost: Int
}

public enum Balance {
    public static let tileSize = 80.0
    /// G3 kalibrasyonu: 150 → 140 — erken oyunda 3. kuleyi geciktirir.
    public static let startingGold = 140
    public static let startingLives = 20
    public static let sellRefundRate = 0.7
    public static let maxTowerLevel = 3

    private static let towerCosts: [TowerKind: Int] = [
        .machineGun: 50, .rocket: 100, .sniper: 120,
        .crystal: 180, .shock: 70, .orb: 140,
        .dart: 110, .solar: 260,
    ]

    private static let baseTowerStats: [TowerKind: TowerStats] = [
        .machineGun: TowerStats(damage: 6,    range: 200, fireInterval: 0.35, splashRadius: 0),
        .rocket:     TowerStats(damage: 25,   range: 240, fireInterval: 1.6,  splashRadius: 70),
        .sniper:     TowerStats(damage: 60,   range: 440, fireInterval: 2.8,  splashRadius: 0),
        .crystal:    TowerStats(damage: 90,   range: 260, fireInterval: 2.2,  splashRadius: 0),
        .shock:      TowerStats(damage: 3.5,  range: 150, fireInterval: 0.15, splashRadius: 0),
        .orb:        TowerStats(damage: 16,   range: 220, fireInterval: 1.1,  splashRadius: 50),
        .dart:       TowerStats(damage: 12,   range: 230, fireInterval: 0.5,  splashRadius: 0),
        .solar:      TowerStats(damage: 45,   range: 280, fireInterval: 1.8,  splashRadius: 70),
    ]

    /// Ödüller κ-formülüne bağlı: bounty = max(2, round(0.12 · maxHP)).
    /// (Boss hariç — sabit 150; final ödülü ağırlıkla dalga bonusundan gelir.)
    /// Sabit yazılır, BalanceTests formülle doğrular.
    private static let enemyStats: [EnemyKind: EnemyStats] = [
        .infantry: EnemyStats(maxHP: 60, speed: 110, bounty: 7, livesCost: 1),
        .scout: EnemyStats(maxHP: 35, speed: 210, bounty: 4, livesCost: 1),
        .armored: EnemyStats(maxHP: 260, speed: 65, bounty: 31, livesCost: 1),
        .boss: EnemyStats(maxHP: 1000, speed: 45, bounty: 150, livesCost: 5),
        // İçerik dalgası: akrep zırhlının ~%85 HP'siyle ama %30 daha hızlı;
        // kıskaç böceği orta sınıf uçan; gölge kelebeği en hızlı-kırılgan;
        // çekirge sürü düşmanı (en düşük HP ve ödül).
        .scorpion: EnemyStats(maxHP: 220, speed: 85, bounty: 26, livesCost: 1),
        .clampbeetle: EnemyStats(maxHP: 120, speed: 100, bounty: 14, livesCost: 1),
        .voidbutterfly: EnemyStats(maxHP: 30, speed: 240, bounty: 4, livesCost: 1),
        .locust: EnemyStats(maxHP: 25, speed: 180, bounty: 3, livesCost: 1),
    ]

    public static func cost(of kind: TowerKind) -> Int { towerCosts[kind]! }

    /// Geometrik yükseltme maliyeti: 0.8 · taban · 1.6^(hedefSeviye − 2).
    /// `toLevel` HEDEF seviyedir (2 veya 3); maliyet artışı verim kaçağını frenler.
    public static func upgradeCost(of kind: TowerKind, toLevel: Int) -> Int {
        precondition((2...maxTowerLevel).contains(toLevel),
                     "toLevel \(toLevel) aralık dışı: 2…\(maxTowerLevel)")
        return Int(Double(cost(of: kind)) * 0.8 * pow(1.6, Double(toLevel - 2)))
    }

    public static func stats(for kind: TowerKind, level: Int) -> TowerStats {
        precondition((1...maxTowerLevel).contains(level), "level \(level) aralık dışı: 1…\(maxTowerLevel)")
        let base = baseTowerStats[kind]!
        let l = Double(level - 1)
        return TowerStats(
            damage: base.damage * pow(1.5, l),
            range: base.range * pow(1.15, l),
            fireInterval: base.fireInterval * pow(0.85, l),
            splashRadius: base.splashRadius * pow(1.15, l))
    }

    public static func stats(for kind: EnemyKind) -> EnemyStats { enemyStats[kind]! }

    /// G3 kalibrasyonu: 25+5w → 15+3w — gelir makasını açar (bkz.
    /// docs/denge-raporu.md).
    public static func waveClearBonus(waveNumber: Int) -> Int { 15 + 3 * waveNumber }
}

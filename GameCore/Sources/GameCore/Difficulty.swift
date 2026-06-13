import Foundation

/// Sefer zorluk kademeleri (H1/H1b). Kademe kimliği üç kaldıraçtır:
/// - startingLives: tur başı can (mağaza extraLives üstüne eklenir).
/// - costMultiplier: kule inşa/yükseltme fiyatlarına yukarı yuvarlamalı çarpan
///   (GameEngine.cost(of:) / upgradeCost(of:toLevel:)).
/// - treasuryMultiplier: tur sonu Hazine kazanımına çarpan (risk ödülü).
/// Birim HP çarpanı ARTIK kademe sabiti DEĞİL (H1b): her (kademe, seviye) için
/// BalanceLab `ayar` v3'ün ayarladığı TunedDifficulty.hpMultByTier eğrisinden
/// gelir — sabit 1.25/1.5/1.75 merdiveni üst kademeleri L20+ seviyelerde
/// matematiksel olarak kazanılamaz yapıyordu (TunedDifficulty payı zaten yiyor;
/// bkz. denge-raporu.md H1b). Motor verilen çarpanı AYNEN kullanır,
/// üstüne kademe çarpanı bindirmez.
/// rawValue kalıcı anahtarlarda kullanılır ("seferWon_<n>_<rawValue>") — DEĞİŞTİRME.
public enum Difficulty: String, CaseIterable, Sendable, Codable {
    case normal, zor, cokZor, kabus

    /// YEDEK formül çarpanı: yalnız ayarlı eğri (TunedDifficulty.hpMultByTier)
    /// boş/eksikse LevelGenerator.hpMultiplier(_:difficulty:) bunun ile
    /// Normal eğriyi ölçekler — mütevazı merdiven; gerçek kademe zorluğu
    /// can/maliyet kimliğinden gelir. Ayarlı eğri varken HİÇ kullanılmaz.
    public var fallbackHPMultiplier: Double {
        switch self {
        case .normal: 1.0
        case .zor: 1.12
        case .cokZor: 1.22
        case .kabus: 1.32
        }
    }

    public var startingLives: Int {
        switch self {
        case .normal: 20
        case .zor: 14
        case .cokZor: 10
        case .kabus: 3
        }
    }

    public var costMultiplier: Double {
        switch self {
        case .normal: 1.0
        case .zor: 1.0
        case .cokZor: 1.08
        case .kabus: 1.15
        }
    }

    public var treasuryMultiplier: Double {
        switch self {
        case .normal: 1.0
        case .zor: 1.5
        case .cokZor: 2.0
        case .kabus: 3.0
        }
    }

    public var label: String {
        switch self {
        case .normal: "Normal"
        case .zor: "Zor"
        case .cokZor: "Çok Zor"
        case .kabus: "Kâbus"
        }
    }

    /// Tur sonu Hazine kazanımı: (biten dalga × 10 + galibiyette 100) × BİRLEŞİK
    /// çarpan (kademe × mutatörler, tavan ×4 — Mutator.treasuryMultiplier),
    /// en yakın tam sayıya yuvarlanır. Kayıp/galibiyet ayrımı yapılmaz — tek formül.
    /// Mutatörsüz çağrı (varsayılan []) eski davranışla birebir aynıdır.
    public func treasuryEarned(wavesCompleted: Int, won: Bool,
                               mutators: [Mutator] = []) -> Int {
        let base = wavesCompleted * 10 + (won ? 100 : 0)
        let multiplier = Mutator.treasuryMultiplier(difficulty: self, mutators: mutators)
        return Int((Double(base) * multiplier).rounded())
    }
}

/// Kalıcı yükseltmelerin (mağaza item'ları) tek bir tura uygulanan toplam etkisi.
/// Motor bunları init'te alır; tur boyunca değişmez.
public struct RunModifiers: Sendable {
    /// Başlangıç altınına eklenir.
    public let startGoldBonus: Int
    /// Tüm kule hasarlarına çarpan olarak uygulanır (1.0 = etkisiz).
    public let damageMultiplier: Double
    /// Başlangıç canına eklenir.
    public let extraLives: Int

    public init(startGoldBonus: Int, damageMultiplier: Double, extraLives: Int) {
        self.startGoldBonus = startGoldBonus
        self.damageMultiplier = damageMultiplier
        self.extraLives = extraLives
    }

    /// Etkisiz varsayılan: mevcut davranışı birebir korur.
    public static let none = RunModifiers(startGoldBonus: 0, damageMultiplier: 1.0, extraLives: 0)
}

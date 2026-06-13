public struct SpawnGroup: Sendable, Equatable {
    public let kind: EnemyKind
    public let count: Int
    /// Grup içindeki ardışık düşman doğumları arasındaki saniye.
    public let interval: Double
    /// Grup-yerel HP çarpanı (E1 — Sonsuz Mod): motor doğumda bunu motor-seviyesi
    /// enemyHPMultiplier ile ÇARPAR. Ödül/can bedeli taban kalır (gelir-nötr,
    /// G5b kuralıyla tutarlı). Varsayılan 1.0 → mevcut dalga tanımları değişmez.
    public let hpMultiplier: Double

    public init(kind: EnemyKind, count: Int, interval: Double, hpMultiplier: Double = 1.0) {
        self.kind = kind
        self.count = count
        self.interval = interval
        self.hpMultiplier = hpMultiplier
    }
}

public struct WaveDefinition: Sendable, Equatable {
    public let groups: [SpawnGroup]

    public init(groups: [SpawnGroup]) {
        self.groups = groups
    }
}

public enum Waves {
    /// G3 kalibrasyonu: adetler sıkı ±%20 bandında artırıldı (taban: S8 değerleri);
    /// gerekçe ve iterasyon tabloları docs/denge-raporu.md içinde.
    /// Oyun içi serbest oyun kaldırıldı; bu 10-dalga dizisi kalibrasyon referansı
    /// (BalanceLab + testler + motor varsayılanı) olarak yaşıyor.
    public static let campaign: [WaveDefinition] = [
        WaveDefinition(groups: [SpawnGroup(kind: .infantry, count: 7, interval: 1.0)]),
        // 2: 12 yerine 11 — 3. dalga toplam HP monotonluğu korunsun (660 ≤ 680).
        WaveDefinition(groups: [SpawnGroup(kind: .infantry, count: 11, interval: 0.8)]),
        WaveDefinition(groups: [SpawnGroup(kind: .infantry, count: 9, interval: 0.8),
                                SpawnGroup(kind: .scout, count: 4, interval: 0.6)]),
        // 4: akrep tanıtımı — keşif perdesi + zırh delici hızlı akrepler
        WaveDefinition(groups: [SpawnGroup(kind: .scout, count: 12, interval: 0.5),
                                SpawnGroup(kind: .scorpion, count: 3, interval: 1.2)]),
        // 5: çekirge sürüsü — kalabalık, kısa aralık
        WaveDefinition(groups: [SpawnGroup(kind: .locust, count: 28, interval: 0.2),
                                SpawnGroup(kind: .infantry, count: 12, interval: 0.5)]),
        // 6: kıskaç böceği tanıtımı (ilk dayanıklı uçan)
        WaveDefinition(groups: [SpawnGroup(kind: .clampbeetle, count: 6, interval: 1.2),
                                SpawnGroup(kind: .scout, count: 12, interval: 0.4),
                                SpawnGroup(kind: .infantry, count: 9, interval: 0.6)]),
        // 7: karışık kara ordusu
        WaveDefinition(groups: [SpawnGroup(kind: .infantry, count: 12, interval: 0.45),
                                SpawnGroup(kind: .scout, count: 9, interval: 0.4),
                                SpawnGroup(kind: .armored, count: 3, interval: 1.5),
                                SpawnGroup(kind: .scorpion, count: 3, interval: 1.0)]),
        // 8: gölge kelebeği tanıtımı + karışık
        WaveDefinition(groups: [SpawnGroup(kind: .voidbutterfly, count: 12, interval: 0.35),
                                SpawnGroup(kind: .clampbeetle, count: 6, interval: 1.1),
                                SpawnGroup(kind: .armored, count: 6, interval: 1.2),
                                SpawnGroup(kind: .scout, count: 7, interval: 0.4)]),
        // 9: her şey birden
        WaveDefinition(groups: [SpawnGroup(kind: .infantry, count: 12, interval: 0.4),
                                SpawnGroup(kind: .scout, count: 9, interval: 0.35),
                                SpawnGroup(kind: .scorpion, count: 4, interval: 0.9),
                                SpawnGroup(kind: .armored, count: 4, interval: 1.0),
                                SpawnGroup(kind: .clampbeetle, count: 4, interval: 1.1),
                                SpawnGroup(kind: .voidbutterfly, count: 9, interval: 0.4),
                                SpawnGroup(kind: .locust, count: 16, interval: 0.25)]),
        // 10: boss + eskort — boss HP 2500→1000 dengelemesiyle eskort büyütüldü
        // ki toplam dalga HP'si 9. dalganın altına düşmesin (4300 ≥ 4105).
        WaveDefinition(groups: [SpawnGroup(kind: .locust, count: 24, interval: 0.25),
                                SpawnGroup(kind: .scorpion, count: 4, interval: 1.0),
                                SpawnGroup(kind: .armored, count: 7, interval: 1.0),
                                SpawnGroup(kind: .boss, count: 1, interval: 1.0)]),
    ]
}

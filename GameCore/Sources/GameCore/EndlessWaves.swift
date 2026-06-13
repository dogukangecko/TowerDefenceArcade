import Foundation

/// Sonsuz Mod dalga üreteci (E1): GameEngine.waveProvider'a verilen deterministik
/// kapanış. Sefer-sonrası içerik olduğundan tanıtım takvimi YOK — tüm tür havuzu
/// (boss hariç) 1. dalgadan açıktır; boss her 10. dalgada gelir.
///
/// Bütçe: W(n) = 120 · 1.22^(n−1) · s((n−1)%10+1) — kampanya eğrisinin 10 dalgalık
/// testere dişi ritmi sonsuza döngülenir. n>10'dan itibaren her birime grup HP
/// çarpanı 1.04^(n−10) biner (BTD6 freeplay tarzı): gelir taban kaldığı için
/// (SpawnGroup.hpMultiplier gelir-nötr) son KAÇINILMAZDIR — sorulan tek soru
/// "hangi dalgaya kadar?". Bütçe ETKİLİ HP (taban × çarpan) cinsinden doldurulur.
public enum EndlessWaves {
    /// Harita başına dalga üreteci. Aynı (mapSeed, n) HER ZAMAN aynı dalgayı verir
    /// (upcomingWave tekrarlı sorar; kayıt/rekor karşılaştırmaları adil kalır).
    public static func provider(mapSeed: UInt64) -> (Int) -> WaveDefinition? {
        { n in n >= 1 ? wave(n, mapSeed: mapSeed) : nil }
    }

    /// Harita adından kararlı tohum (FNV-1a 64-bit). String.hashValue süreçler
    /// arası rastgele tohumlanır — kalıcı determinizm için kullanılamaz.
    public static func seed(for mapName: String) -> UInt64 {
        var hash: UInt64 = 0xCBF2_9CE4_8422_2325
        for byte in mapName.utf8 {
            hash ^= UInt64(byte)
            hash = hash &* 0x0000_0100_0000_01B3
        }
        return hash
    }

    /// HP bütçesi: kampanya formülü, testere dişi 10'luk döngüyle.
    static func budget(wave n: Int) -> Double {
        120 * pow(1.22, Double(n - 1)) * LevelGenerator.sawtooth[(n - 1) % 10]
    }

    /// n>10 rampası: 1.04^(n−10); ilk 10 dalga çarpansız (kampanya hissi).
    static func hpMultiplier(wave n: Int) -> Double {
        n > 10 ? pow(1.04, Double(n - 10)) : 1.0
    }

    /// Kompozisyon: LevelGenerator.generateWaves ile aynı omurga (ağırlıklı seçim,
    /// adet hedefi, ±%15 bütçe bandı) ama tam roster + döngüsel boss + etkili HP.
    static func wave(_ n: Int, mapSeed: UInt64) -> WaveDefinition {
        var rng = SeededRNG(seed: mapSeed &+ UInt64(n) &* 0x9E37_79B9_7F4A_7C15)
        let allowed = EnemyKind.allCases.filter { $0 != .boss }
        let hpMult = hpMultiplier(wave: n)
        /// Etkili HP: bütçe bandı toplam etkili HP üstünden tutturulur.
        func effectiveHP(_ kind: EnemyKind) -> Double {
            Balance.stats(for: kind).maxHP * hpMult
        }

        var budget = budget(wave: n)
        var groups: [SpawnGroup] = []

        if n % 10 == 0 {
            // Boss: etkili HP'si bütçeden düşülür, kalan eskorta gider.
            groups.append(SpawnGroup(kind: .boss, count: 1, interval: 1.0,
                                     hpMultiplier: hpMult))
            budget -= effectiveHP(.boss)
        }
        budget = max(budget, 0)

        // Adet hedefi tür seçimini yönlendirir: hedefin 2 katı aşılınca yüksek-HP
        // türlere geçilir (kalabalık patlaması frenlenir).
        let countTarget = Int((5 * pow(1.10, Double(n - 1))).rounded())
        var weights: [EnemyKind: Double] = [:]
        for kind in allowed {
            weights[kind] = Double.random(in: 0.5...1.5, using: &rng)
        }

        var counts: [EnemyKind: Int] = [:]
        var hpSum = 0.0
        var unitCount = 0
        while hpSum < budget {
            // ±%15 garantisi: tek tür bile bandı taşıracaksa eklenmez.
            let headroom = budget * 1.15 - hpSum
            var candidates = allowed.filter { effectiveHP($0) <= headroom }
            if candidates.isEmpty { break }
            if unitCount >= 2 * countTarget {
                let sorted = candidates.sorted { effectiveHP($0) > effectiveHP($1) }
                candidates = Array(sorted.prefix(max(1, sorted.count / 2)))
            }
            let kind = weightedPick(candidates, weights: weights, rng: &rng)
            counts[kind, default: 0] += 1
            hpSum += effectiveHP(kind)
            unitCount += 1
        }

        // Deterministik grup sırası: EnemyKind.allCases; aralıklar 0.25–1.2.
        for kind in EnemyKind.allCases {
            guard let count = counts[kind], count > 0 else { continue }
            let jitter = Double.random(in: 0.85...1.15, using: &rng)
            let interval = min(1.2, max(0.25, 6.0 / Double(count) * jitter))
            groups.append(SpawnGroup(kind: kind, count: count, interval: interval,
                                     hpMultiplier: hpMult))
        }
        return WaveDefinition(groups: groups)
    }

    private static func weightedPick(_ kinds: [EnemyKind],
                                     weights: [EnemyKind: Double],
                                     rng: inout SeededRNG) -> EnemyKind {
        let total = kinds.reduce(0) { $0 + (weights[$1] ?? 1) }
        var roll = Double.random(in: 0..<total, using: &rng)
        for kind in kinds {
            roll -= weights[kind] ?? 1
            if roll < 0 { return kind }
        }
        return kinds[kinds.count - 1]
    }
}

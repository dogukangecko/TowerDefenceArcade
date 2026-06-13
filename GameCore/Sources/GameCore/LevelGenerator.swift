import Foundation

/// Sefer modunun tek seviyesi: tohumdan deterministik üretilir.
public struct LevelDefinition: Sendable {
    public let id: Int
    public let name: String
    public let map: MapDefinition
    public let waves: [WaveDefinition]
    public let difficultyIndex: Double
    /// Birim HP çarpanı (G5b): motor düşman HP'sini bununla ölçekler; ödül ve
    /// can bedeli taban kalır. GameEngine(enemyHPMultiplier:)'a aynen aktarılır.
    public let hpMultiplier: Double
    /// Görsel palet endeksi (V2): 0=yeşil, 1=soluk/altın, 2=koyu yeşil — tohumdan
    /// deterministik. Yalnız sahne çim/kıyı/dekor tonunu seçer; oynanışa girmez.
    public let palette: Int
}

/// 50 seviyelik Sefer üreteci. Her şey SplitMix64 tohumlu → aynı id her zaman
/// aynı harita + dalgalar. Harita üretimi serpantin şablonlu öz-kaçınan yol,
/// M-skoru bandı dışını reddedip tohum+1 ile yeniden dener.
public enum LevelGenerator {
    static let gridColumns = 16
    static let gridRows = 9
    static let minPathTiles = 20
    static let mapScoreBand = 0.7...1.4
    static let maxMapAttempts = 20

    // MARK: - Genel API

    public static func level(_ id: Int) -> LevelDefinition {
        precondition((1...50).contains(id), "seviye \(id) aralık dışı: 1…50")
        let candidate = generateMap(id: id)
        return LevelDefinition(
            id: id,
            name: names(50)[id - 1],
            map: candidate.map,
            waves: generateWaves(id: id, difficulty: compositionD(id)),
            difficultyIndex: difficultyIndex(id),
            hpMultiplier: hpMultiplier(id),
            palette: palette(seed: 0x9A1E_7001 &+ UInt64(id) &* 0x9E37_79B9_7F4A_7C15))
    }

    /// Palet endeksi 0…2: ayrı tohum uzayı — harita/dalga üretimini ETKİLEMEZ
    /// (mevcut tohum akışlarına çekiliş eklemek tüm seviyeleri değiştirirdi).
    static func palette(seed: UInt64) -> Int {
        var rng = SeededRNG(seed: seed)
        return Int.random(in: 0...2, using: &rng)
    }

    /// Günlük Meydan Okuma (E3): tarihe tohumlu TEK seviye — sefer uzayından
    /// ayrı tohum alanı (0xDA117 ⊕ YYYYMMDD), AYNI harita kabul/red hattı
    /// (M bandı dahil). Sabitler: 10 dalga, hpMultiplier 2.2 (Zor–Çok Zor arası),
    /// tam düşman kadrosu + dalga 10 boss finali; nehir takvim yerine tohumdan
    /// %40 kapıyla. id 0 = "sefer dışı" işareti (level(_:) 1…50 ile çakışmaz).
    public static func daily(year: Int, month: Int, day: Int) -> LevelDefinition {
        let dateSeed = UInt64(0xDA117) ^ UInt64(year * 10_000 + month * 100 + day)
        var rng = SeededRNG(seed: dateSeed)
        // Nehir kapısı: %40 (uygun sütun yoksa placeRiver yine nehirsiz bırakır).
        let wantRiver = Double.random(in: 0..<1, using: &rng) < 0.4
        let name = "Günlük: \(frontNames.randomElement(using: &rng)!) "
            + backNames.randomElement(using: &rng)!
        let candidate = generateMap(
            seed: 0xDA11_7001 &+ dateSeed &* 0x9E37_79B9_7F4A_7C15,
            wantRiver: wantRiver,
            label: "günlük \(year)-\(month)-\(day)")
        // Kompozisyon D'si sefer tavanıyla aynı (1.3): adetler makul kalır,
        // zorluk sabit 2.2 birim-HP çarpanında taşınır. id 50 → tam kadro +
        // dalga 10 boss (intro takvimi ve boss kuralı 50 ile en genişler).
        let waves = generateWaves(
            seed: 0xDA11_7002 &+ dateSeed &* 0xBF58_476D_1CE4_E5B9,
            id: 50, difficulty: 1.3)
        return LevelDefinition(
            id: 0,
            name: name,
            map: candidate.map,
            waves: waves,
            difficultyIndex: 1.3,
            hpMultiplier: 2.2,
            palette: palette(seed: 0xDA11_7003 &+ dateSeed &* 0x9E37_79B9_7F4A_7C15))
    }

    /// Sefer ekranı için hafif liste: harita kabul/red sürecini AYNEN koşar
    /// (reddedilen tohumlar nehri kaydırabilir → hasRiver ancak böyle doğru
    /// kalır) ama dalga üretimini atlar.
    public static func meta(_ count: Int) -> [(id: Int, name: String, hasRiver: Bool)] {
        let nameList = names(count)
        return (1...count).map { id in
            (id: id, name: nameList[id - 1], hasRiver: generateMap(id: id).hasRiver)
        }
    }

    /// D(L): BalanceLab'ın ürettiği TunedDifficulty varsa oradan, yoksa formülden.
    /// Yalnız DALGA bütçesini besler — harita topolojisi D'den bağımsızdır
    /// (generateMap hiçbir D girdisi almaz; ayar haritaları yeniden karıştırmaz).
    public static func difficultyIndex(_ level: Int) -> Double {
        TunedDifficulty.dByLevel.indices.contains(level - 1)
            ? TunedDifficulty.dByLevel[level - 1]
            : formulaD(level)
    }

    /// Formül varsayılanı: D(L) = min(2.2, 0.85 + 0.15·⌈L/5⌉).
    /// BalanceLab `ayar` modu ikili aramaya buradan başlar.
    public static func formulaD(_ level: Int) -> Double {
        min(2.2, 0.85 + 0.15 * Double((level + 4) / 5))
    }

    /// Kompozisyon D'si (G5b): dalga BÜTÇESİNE giren D, ÇEŞİTLİLİK içindir ve
    /// 1.3 ile tavanlanır — adetler makul kalsın diye. Zorluğun kendisi artık
    /// birim HP çarpanında taşınır (bütçe-D κ ekonomisinde gelir-nötr olduğundan
    /// zorlaştıramıyordu; bkz. denge-raporu.md G5 bölümü).
    public static func compositionD(_ level: Int) -> Double {
        min(difficultyIndex(level), 1.3)
    }

    /// Birim HP çarpanı (Normal kademe): BalanceLab `ayar`ın ürettiği tablo
    /// varsa oradan, yoksa nötr 1.0. Motorun gelir-nötr zorluk kaldıracını besler.
    public static func hpMultiplier(_ level: Int) -> Double {
        tunedHPMult(level, tier: .normal) ?? 1.0
    }

    /// Kademe-çözümlü birim HP çarpanı (H1b): kademenin KENDİ ayarlı eğrisi
    /// (TunedDifficulty.hpMultByTier) varsa oradan; eğri boş/eksikse Normal
    /// eğri × kademenin mütevazı yedek merdiveni (Difficulty.fallbackHPMultiplier).
    /// GameSession sefer motorunu bununla kurar — motor üstüne kademe çarpanı
    /// BİNDİRMEZ (sabit merdiven üst kademeleri L20+ kazanılamaz yapıyordu).
    public static func hpMultiplier(_ level: Int, difficulty: Difficulty) -> Double {
        tunedHPMult(level, tier: difficulty)
            ?? hpMultiplier(level) * difficulty.fallbackHPMultiplier
    }

    private static func tunedHPMult(_ level: Int, tier: Difficulty) -> Double? {
        guard let curve = TunedDifficulty.hpMultByTier[tier.rawValue],
              curve.indices.contains(level - 1) else { return nil }
        return curve[level - 1]
    }

    /// BalanceLab ayar sondası için açık dikiş: dalgaları VERİLEN D ile üretir
    /// (harita sabit kalır — D yalnız bütçeye girer). level(_:)'in kullandığı
    /// üretimle birebir aynı yol; difficulty == difficultyIndex(id) verilirse
    /// level(id).waves ile özdeş sonuç döner.
    public static func waves(id: Int, difficulty: Double) -> [WaveDefinition] {
        generateWaves(id: id, difficulty: difficulty)
    }

    // MARK: - Harita üretimi

    struct MapCandidate {
        let map: MapDefinition
        let ascii: String
        let hasRiver: Bool
        let attempts: Int   // kaç tohum denendi (enstrümantasyon)
    }

    static func generateMap(id: Int) -> MapCandidate {
        // Sefer tohum uzayı + nehir takvimi (id ≥ 8 ve id % 3 == 0) değişmedi:
        // daily(_:_:_:) aynı kabul/red hattını kendi tohum uzayıyla koşar.
        generateMap(seed: 0x5EFE_0001 &+ UInt64(id) &* 0x9E37_79B9_7F4A_7C15,
                    wantRiver: id >= 8 && id % 3 == 0,
                    label: "seviye \(id)")
    }

    static func generateMap(seed initialSeed: UInt64, wantRiver: Bool,
                            label: String) -> MapCandidate {
        var seed = initialSeed
        var best: MapCandidate?   // band dışıysa en yakın geçerli aday (güvenlik ağı)
        var bestDistance = Double.infinity

        for attempt in 1...maxMapAttempts {
            defer { seed &+= 1 }
            var rng = SeededRNG(seed: seed)
            guard let (ascii, hasRiver) = buildAscii(wantRiver: wantRiver, rng: &rng),
                  let map = try? MapDefinition.parse(ascii, tileSize: Balance.tileSize),
                  map.pathOrder.count >= minPathTiles
            else { continue }

            let score = normalizedMapScore(of: map)
            if mapScoreBand.contains(score) {
                return MapCandidate(map: map, ascii: ascii, hasRiver: hasRiver, attempts: attempt)
            }
            let distance = score < mapScoreBand.lowerBound
                ? mapScoreBand.lowerBound - score
                : score - mapScoreBand.upperBound
            if distance < bestDistance {
                bestDistance = distance
                best = MapCandidate(map: map, ascii: ascii, hasRiver: hasRiver, attempts: attempt)
            }
        }
        // 20 denemede band tutturulamadı: en yakın geçerli adayı döndür —
        // testteki band asserti bunu üretici hatası olarak yakalar.
        guard let fallback = best else {
            fatalError("\(label): \(maxMapAttempts) denemede geçerli harita üretilemedi")
        }
        return fallback
    }

    /// Serpantin yol: 2-4 yatay koşu (satır araları ≥2 → zincir dallanmaz),
    /// dikey bağlantılar; S sol kenarda, B sağ kenarda. wantRiver doğruysa
    /// yolun TAM 1 kez yatay kestiği sütun(lar)a '~' bandı yerleştirilir.
    private static func buildAscii(wantRiver: Bool,
                                   rng: inout SeededRNG) -> (ascii: String, hasRiver: Bool)? {
        let runCount = Int.random(in: 2...4, using: &rng)

        // Koşu satırları: monoton, ardışık fark ≥ 2 (bitişik satırlar parse'da dallanır).
        var runRows: [Int] = []
        var minRow = 0
        for i in 0..<runCount {
            let slack = gridRows - 1 - 2 * (runCount - 1 - i)
            guard minRow <= slack else { return nil }
            let row = Int.random(in: minRow...slack, using: &rng)
            runRows.append(row)
            minRow = row + 2
        }
        if Bool.random(using: &rng) {   // dikey ayna — S üstte ya da altta başlasın
            runRows = runRows.map { gridRows - 1 - $0 }
        }

        // Dönüş sütunları: 1…14, komşu dönüşler arası fark ≥ 2 (görünür koşu).
        var turns: [Int] = []
        for _ in 0..<(runCount - 1) {
            let options = (1...(gridColumns - 2)).filter { c in
                turns.last.map { abs(c - $0) >= 2 } ?? true
            }
            guard let pick = options.randomElement(using: &rng) else { return nil }
            turns.append(pick)
        }

        // Izgarayı çiz.
        var grid = Array(repeating: Array(repeating: Character("."), count: gridColumns),
                         count: gridRows)
        var col = 0
        for i in 0..<runCount {
            let row = runRows[i]
            let endCol = i == runCount - 1 ? gridColumns - 1 : turns[i]
            for c in stride(from: col, through: endCol, by: col <= endCol ? 1 : -1) {
                grid[row][c] = "#"
            }
            col = endCol
            if i < runCount - 1 {
                let nextRow = runRows[i + 1]
                for r in stride(from: row, through: nextRow, by: row <= nextRow ? 1 : -1) {
                    grid[r][col] = "#"
                }
            }
        }
        grid[runRows[0]][0] = "S"
        grid[runRows[runCount - 1]][gridColumns - 1] = "B"

        // Nehir: yolun tek yatay geçişle kestiği sütun(lar) — uygun sütun yoksa nehirsiz.
        var hasRiver = false
        if wantRiver {
            hasRiver = placeRiver(in: &grid, rng: &rng)
        }

        let ascii = grid.map { String($0) }.joined(separator: "\n")
        return (ascii, hasRiver)
    }

    /// Yolun TAM 1 yol karesi içerdiği sütunlar nehir adayıdır (dönüş sütunları
    /// dikey kareler yüzünden ≥3 kare içerir → otomatik elenir; kalan tek kare
    /// hep düz yatay geçiştir). 2 sütunluk bant için bitişik iki adayın köprü
    /// satırı aynı olmalı — yoksa yol nehri 2 ayrı satırdan keserdi.
    private static func placeRiver(in grid: inout [[Character]], rng: inout SeededRNG) -> Bool {
        func pathTiles(inColumn c: Int) -> [Int] {
            (0..<gridRows).filter { grid[$0][c] != "." }
        }
        let singles = (1...(gridColumns - 2)).filter { pathTiles(inColumn: $0).count == 1 }
        guard !singles.isEmpty else { return false }

        let wantWide = Int.random(in: 1...2, using: &rng) == 2
        var band: [Int] = []
        if wantWide {
            let pairs = singles.filter { c in
                singles.contains(c + 1)
                    && pathTiles(inColumn: c) == pathTiles(inColumn: c + 1)
            }
            if let start = pairs.randomElement(using: &rng) {
                band = [start, start + 1]
            }
        }
        if band.isEmpty {
            band = [singles.randomElement(using: &rng)!]
        }
        for c in band {
            for r in 0..<gridRows where grid[r][c] == "." {
                grid[r][c] = "~"
            }
        }
        return true
    }

    // MARK: - M skoru (harita cimriliği)

    /// Σ inşa karesi başına ≤200pt menzildeki yol karesi sayısı; klasik haritaya
    /// normalize. Banda zorlama, spec'teki M(L) çarpanının yerini tutar — dalga
    /// bütçesine ayrıca M koymuyoruz (bkz. generateWaves yorumu).
    static func normalizedMapScore(of map: MapDefinition) -> Double {
        rawMapScore(of: map) / classicMapScore
    }

    private static let classicMapScore = rawMapScore(of: Maps.classic())

    private static func rawMapScore(of map: MapDefinition) -> Double {
        let coverRange = 200.0
        let pathCenters = map.pathOrder.map(map.center)
        var sum = 0
        for r in 0..<map.rows {
            for c in 0..<map.columns {
                let tile = GridPoint(col: c, row: r)
                guard map.isBuildable(tile) else { continue }
                let center = map.center(of: tile)
                sum += pathCenters.lazy.filter { center.distance(to: $0) <= coverRange }.count
            }
        }
        return Double(sum)
    }

    // MARK: - Dalga kompozisyonu

    /// Tür tanıtım takvimi (boss ayrı kural: yalnız L%10==0'ın 10. dalgası).
    static func introLevel(_ kind: EnemyKind) -> Int {
        switch kind {
        case .infantry, .scout: 1
        case .locust: 3
        case .scorpion: 6
        case .armored: 8
        case .clampbeetle: 10
        case .voidbutterfly: 14
        case .boss: Int.max
        }
    }

    /// Testere dişi profili (10 dalgalık ritim) — EndlessWaves de aynı ritmi
    /// (n−1)%10+1 ile döngüleyerek kullanır; o yüzden internal.
    static let sawtooth: [Double] = [1, 1, 1.15, 0.85, 1.2, 1, 1.3, 0.8, 1.25, 1.5]

    /// HP bütçesi W(L,w) = 120 · D · 1.22^(w−1) · s(w).
    /// NOT: Spec'teki M(L) çarpanı bilerek YOK — harita zorluğu ayrı bir eksen:
    /// üretici haritayı zaten M∈[0.7,1.4] bandına zorladığı için dalga bütçesine
    /// bir de M katmak zorluğu çift sayardı.
    static func waveBudget(difficulty: Double, wave: Int) -> Double {
        120 * difficulty * pow(1.22, Double(wave - 1)) * sawtooth[wave - 1]
    }

    static func generateWaves(id: Int, difficulty: Double) -> [WaveDefinition] {
        // Sefer tohum uzayı değişmedi; daily aynı üretimi kendi tohumuyla koşar
        // (id orada yalnız kadro/boss kurallarını seçer — 50: tam kadro + boss).
        generateWaves(seed: 0xDA16_A001 &+ UInt64(id) &* 0xBF58_476D_1CE4_E5B9,
                      id: id, difficulty: difficulty)
    }

    static func generateWaves(seed: UInt64, id: Int, difficulty: Double) -> [WaveDefinition] {
        var rng = SeededRNG(seed: seed)
        let allowed = EnemyKind.allCases.filter { $0 != .boss && introLevel($0) <= id }

        return (1...10).map { w in
            var budget = waveBudget(difficulty: difficulty, wave: w)
            var groups: [SpawnGroup] = []

            if w == 10 && id % 10 == 0 {
                // Boss: HP'si bütçeden düşülür, kalan eskorta gider.
                groups.append(SpawnGroup(kind: .boss, count: 1, interval: 1.0))
                budget -= Balance.stats(for: .boss).maxHP
            } else if w == 10 && id % 5 == 0 {
                // Mini-boss paketi: armored×3 (tanıtımdan önceyse — yalnız L5 —
                // takvimi bozmamak için en dayanıklı açık tür olan infantry×3).
                let miniKind: EnemyKind = allowed.contains(.armored) ? .armored : .infantry
                groups.append(SpawnGroup(kind: miniKind, count: 3, interval: 1.0))
                budget -= 3 * Balance.stats(for: miniKind).maxHP
            }
            budget = max(budget, 0)

            // Adet hedefi tür seçimini yönlendirir (bütçeyi HP doldurur):
            // hedefin 2 katı aşılınca yüksek-HP türlere geçilir.
            let countTarget = Int((5 * pow(1.10, Double(w - 1))).rounded())
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
                var candidates = allowed.filter { Balance.stats(for: $0).maxHP <= headroom }
                if candidates.isEmpty { break }
                if unitCount >= 2 * countTarget {
                    let sorted = candidates.sorted {
                        Balance.stats(for: $0).maxHP > Balance.stats(for: $1).maxHP
                    }
                    candidates = Array(sorted.prefix(max(1, sorted.count / 2)))
                }
                let kind = weightedPick(candidates, weights: weights, rng: &rng)
                counts[kind, default: 0] += 1
                hpSum += Balance.stats(for: kind).maxHP
                unitCount += 1
            }

            // Deterministik grup sırası: EnemyKind.allCases. Aralıklar 0.25–1.2,
            // kalabalık gruplar daha sık doğar.
            for kind in EnemyKind.allCases {
                guard let count = counts[kind], count > 0 else { continue }
                let jitter = Double.random(in: 0.85...1.15, using: &rng)
                let interval = min(1.2, max(0.25, 6.0 / Double(count) * jitter))
                groups.append(SpawnGroup(kind: kind, count: count, interval: interval))
            }
            return WaveDefinition(groups: groups)
        }
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

    // MARK: - Adlar

    private static let frontNames = [
        "Kuzgun", "Sisli", "Kanlı", "Yıldız", "Demir", "Gölge", "Fırtına",
        "Altın", "Buzul", "Ejder", "Kızıl", "Gümüş", "Çorak", "Uluyan",
    ]
    private static let backNames = [
        "Geçidi", "Vadisi", "Burnu", "Ovası", "Koyağı", "Sırtı",
        "Bataklığı", "Yaylası", "Kalesi", "Uçurumu",
    ]

    /// Tohumlu benzersiz ad listesi: çakışmada tohum ilerletilir (yeniden çekilir).
    static func names(_ count: Int) -> [String] {
        precondition(count <= frontNames.count * backNames.count)
        var rng = SeededRNG(seed: 0xAD1A_5EFE)
        var used = Set<String>()
        var result: [String] = []
        while result.count < count {
            let name = "\(frontNames.randomElement(using: &rng)!) \(backNames.randomElement(using: &rng)!)"
            if used.insert(name).inserted {
                result.append(name)
            }
        }
        return result
    }
}

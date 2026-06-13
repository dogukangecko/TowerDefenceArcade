/// BalanceLab — başsız denge laboratuvarı.
///
/// Kullanım:
///   swift run BalanceLab                    → rapor modu (varsayılan)
///   swift run BalanceLab rapor [oran...]   → el yapımı haritalarda GreedyPolicy taraması
///   swift run BalanceLab detay             → dalga dalga can/altın/kule dökümü (teşhis)
///   swift run -c release BalanceLab ayar   → 4 kademe × 50 seviyenin birim HP çarpanı
///                                            eğrilerini ikili aramayla ayarlar (v3 — H1b,
///                                            kompozisyon D sabit), TunedDifficulty.swift'i
///                                            YENİDEN YAZAR
///
/// `rapor` modu: Maps.all × budgetRatio {0.7, 0.9, 1.0} (veya argüman olarak verilen
/// oranlar) kombinasyonlarını Waves.campaign ile koşar ve hizalı bir tablo basar.
/// Determinist olduğundan çıktı aynı kod tabanında her koşuda birebir aynıdır.

import GameCore

let mode = CommandLine.arguments.dropFirst().first ?? "rapor"

func pad(_ s: String, _ width: Int, right: Bool = false) -> String {
    let fill = String(repeating: " ", count: max(0, width - s.count))
    return right ? fill + s : s + fill
}

func rapor() {
    let extra = CommandLine.arguments.dropFirst(2).compactMap(Double.init)
    let ratios = extra.isEmpty ? [0.7, 0.9, 1.0] : extra
    print("BalanceLab rapor — Waves.campaign (\(Waves.campaign.count) dalga), GreedyPolicy")
    print("Hedef bant: medyan kalan can 14-18 / \(Balance.startingLives)\n")

    let header = [pad("Harita", 14), pad("Oran", 5),
                  pad("Sonuç", 8), pad("Can", 5, right: true),
                  pad("Dalga", 6, right: true), pad("Kule", 5, right: true),
                  pad("Harcama", 8, right: true)].joined(separator: "  ")
    print(header)
    print(String(repeating: "-", count: header.count))

    for (name, map) in Maps.all {
        var lives: [Int] = []
        for ratio in ratios {
            var policy = GreedyPolicy(buildBudgetRatio: ratio)
            let r = Simulator.run(map: map, waves: Waves.campaign, policy: &policy)
            lives.append(r.livesLeft)
            let sonuc = r.won ? "KAZANDI" : (r.failedAtWave != nil ? "KAYIP" : "SÜRE")
            let dalga = r.failedAtWave.map(String.init) ?? "-"
            print([pad(name, 14), pad(String(format: "%.1f", ratio), 5),
                   pad(sonuc, 8), pad("\(r.livesLeft)", 5, right: true),
                   pad(dalga, 6, right: true), pad("\(r.towersBuilt)", 5, right: true),
                   pad("\(r.goldSpentOnTowers)", 8, right: true)].joined(separator: "  "))
        }
        let medyan = lives.sorted()[lives.count / 2]
        let yuzde = 100 * medyan / Balance.startingLives
        print("  → \(name) medyan can: \(medyan)/\(Balance.startingLives) (%\(yuzde))\n")
    }
}

/// Kalibrasyon teşhisi: dalga dalga can/altın/kule dökümü (GreedyPolicy 0.9, klasik).
func detay() {
    let map = Maps.classic()
    var policy = GreedyPolicy(buildBudgetRatio: 0.9)
    let engine = GameEngine(map: map, waves: Waves.campaign)
    let dt = 0.1
    var sinceDecide = 0.0
    print("Dalga  Can   Altın  Kule")
    while engine.phase == .building || engine.phase == .waveActive {
        if engine.phase == .building {
            for cmd in policy.decide(engine: engine) {
                switch cmd {
                case .build(let kind, let tile): _ = engine.buildTower(kind, at: tile)
                case .upgrade(let id): _ = engine.upgradeTower(id: id)
                }
            }
            guard case .success = engine.startNextWave() else { break }
            sinceDecide = 0
        }
        while engine.phase == .waveActive {
            _ = engine.update(dt: dt)
            sinceDecide += dt
            if sinceDecide >= 0.5 - 1e-9, engine.phase == .waveActive {
                sinceDecide = 0
                for cmd in policy.decide(engine: engine) {
                    switch cmd {
                    case .build(let kind, let tile): _ = engine.buildTower(kind, at: tile)
                    case .upgrade(let id): _ = engine.upgradeTower(id: id)
                    }
                }
            }
        }
        print(pad("\(engine.waveNumber)", 5, right: true)
              + pad("\(engine.lives)", 6, right: true)
              + pad("\(engine.gold)", 7, right: true)
              + pad("\(engine.towers.count)", 6, right: true))
    }
    print("Faz: \(engine.phase)")
}

// MARK: - ayar modu (G5 → v3 H1b)

import Foundation

/// Kademe hedef bantları (medyan kalan can; kademenin kendi başlangıç canının
/// kesri olarak Normal spec yüzdeleriyle SIKILAŞTIRILMIŞ uyum):
/// - normal (20 can): 18-20 · 14-18 · 9-15 · 6-12  (G5b speciyle AYNI — regresyon).
/// - zor    (14 can): 11-14 · 8-11 · 5-9 · 3-7.
/// - cokZor (10 can): 7-10 · 5-8 · 3-6 · 2-5.
/// kabus bant kullanmaz — kazanılabilirlik-öncelikli arama (aşağıda).
func hedefBant(_ level: Int, _ diff: Difficulty) -> ClosedRange<Int> {
    switch diff {
    case .normal:
        switch level {
        case 1...10: 18...20
        case 11...30: 14...18
        case 31...45: 9...15
        default: 6...12
        }
    case .zor:
        switch level {
        case 1...10: 11...14
        case 11...30: 8...11
        case 31...45: 5...9
        default: 3...7
        }
    case .cokZor:
        switch level {
        case 1...10: 7...10
        case 11...30: 5...8
        case 31...45: 3...6
        default: 2...5
        }
    case .kabus:
        fatalError("kabus bant kullanmaz — kazanılabilirlik araması")
    }
}

struct AyarSonuc {
    let level: Int
    let d: Double                       // kompozisyon kaynağı (formül değeri; tavansız)
    let hpMult: Double                  // birim HP çarpanı (asıl zorluk kaldıracı)
    let medyan: Int
    let varyantSonuclari: [SimResult]   // 0.8 / 0.9 / 1.0 sırasıyla
    let bantta: Bool                    // kabus'ta: ≥1 varyant kazanıyor mu
    let probeSayisi: Int
    let kelepce: Bool                   // yalnız kabus: 1.0 altına kelepçelendi
}

/// ayar v3 (H1b): DÖRT kademenin 50'şer seviyelik birim HP eğrisini ayarlar.
/// Kompozisyon (dalga çeşitliliği) formül D'sinin 1.3 tavanlı haliyle SABİT
/// üretilir; sondalar yalnız motorun enemyHPMultiplier kaldıracını değiştirir
/// ve kademenin can/maliyet kimliği simde ETKİNDİR (difficulty: geçilir).
/// - normal/zor/cokZor: GreedyPolicy {0.8, 0.9, 1.0} medyanı kademenin kendi
///   bandına oturana dek ikili arama (normal aralık [0.8, 6.0] — v2 ile birebir
///   aynı kod yolu, regresyon; zor/cokZor [0.85, 6.0]). Yakınsamazsa banda en
///   yakın sonda + UYARI.
/// - kabus: kazanılabilirlik-öncelikli — en az BİR varyantın kazandığı EN BÜYÜK
///   çarpan ∈ [1.0, 6.0]; 1.0 bile kazanılamazsa [0.85, 1.0) aralığına aşağı
///   kelepçelenir (kimlik oradaki 3 candan gelir) ve seviye raporlanır.
func ayar() {
    let ratios = [0.8, 0.9, 1.0]
    var tumSonuclar: [Difficulty: [AyarSonuc]] = [:]
    var uyarilar: [Difficulty: [Int]] = [:]
    var kazanilamayanlar: [Int] = []   // kabus: 0.85'te bile kazanan varyant yok
    let baslangic = Date()

    for diff in Difficulty.allCases {
        var sonuclar: [AyarSonuc] = []
        for level in 1...50 {
            // Harita + dalgalar seviye başına TEK üretim: HP çarpanı ne haritaya
            // ne kompozisyona dokunur (testle kilitli: topoloji D'den bağımsız).
            let map = LevelGenerator.level(level).map
            let dFormul = LevelGenerator.formulaD(level)
            let waves = LevelGenerator.waves(id: level, difficulty: min(dFormul, 1.3))

            var denenen: [Double: (medyan: Int, results: [SimResult])] = [:]
            var probeSirasi: [Double] = []
            func sonda(_ hHam: Double) -> (medyan: Int, results: [SimResult]) {
                let h = (hHam * 1000).rounded() / 1000   // yazılacak 3 ondalıkla AYNI değeri ölç
                if let eski = denenen[h] { return eski }
                var results: [SimResult] = []
                for ratio in ratios {
                    var policy = GreedyPolicy(buildBudgetRatio: ratio)
                    results.append(Simulator.run(map: map, waves: waves,
                                                 enemyHPMultiplier: h,
                                                 difficulty: diff, policy: &policy))
                }
                let medyan = results.map(\.livesLeft).sorted()[results.count / 2]
                denenen[h] = (medyan, results)
                probeSirasi.append(h)
                return (medyan, results)
            }

            var hSecim: Double
            var kelepce = false

            if diff == .kabus {
                // Kazanılabilirlik-öncelikli: ≥1 varyant kazanıyorsa "geçer".
                func kazanir(_ h: Double) -> Bool { sonda(h).results.contains { $0.won } }
                if kazanir(1.0) {
                    if kazanir(6.0) {
                        hSecim = 6.0
                    } else {
                        // En büyük kazanılabilir çarpan: lo hep kazanır, hi hep kaybeder.
                        var lo = 1.0, hi = 6.0, enIyi = 1.0
                        for _ in 0..<12 {
                            let mid = (lo + hi) / 2
                            let midYuvarlak = (mid * 1000).rounded() / 1000
                            if kazanir(mid) {
                                lo = mid
                                enIyi = max(enIyi, midYuvarlak)
                            } else { hi = mid }
                        }
                        hSecim = enIyi
                    }
                } else {
                    // 1.0 bile kazanılamıyor → 0.85 tabanına dek AŞAĞI kelepçele.
                    kelepce = true
                    if kazanir(0.85) {
                        var lo = 0.85, hi = 1.0, enIyi = 0.85
                        for _ in 0..<12 {
                            let mid = (lo + hi) / 2
                            let midYuvarlak = (mid * 1000).rounded() / 1000
                            if kazanir(mid) {
                                lo = mid
                                enIyi = max(enIyi, midYuvarlak)
                            } else { hi = mid }
                        }
                        hSecim = enIyi
                    } else {
                        hSecim = 0.85   // taban: kazanılamaz kalıyor — yüksek sesle raporla
                        kazanilamayanlar.append(level)
                    }
                }
            } else {
                let bant = hedefBant(level, diff)
                let hAralik = diff == .normal ? 0.8...6.0 : 0.85...6.0
                // 1) Nötr başlangıç: çarpansız (1.0) banda oturuyorsa dokunma.
                let h0 = 1.0
                let m0 = sonda(h0).medyan
                var secilen: Double?
                if bant.contains(m0) {
                    secilen = h0
                } else {
                    // 2) İkili arama: medyan > bant → çok kolay → çarpanı büyüt; tersi küçült.
                    var lo = m0 > bant.upperBound ? h0 : hAralik.lowerBound
                    var hi = m0 > bant.upperBound ? hAralik.upperBound : h0
                    for _ in 0..<12 {
                        let mid = (lo + hi) / 2
                        let m = sonda(mid).medyan
                        if bant.contains(m) {
                            secilen = (mid * 1000).rounded() / 1000
                            break
                        }
                        if m > bant.upperBound { lo = mid } else { hi = mid }
                    }
                }
                // 3) Yakınsamadıysa: banda en yakın sondayı al, uyar.
                if let s = secilen {
                    hSecim = s
                } else {
                    func uzaklik(_ m: Int) -> Int {
                        m < bant.lowerBound ? bant.lowerBound - m
                            : m > bant.upperBound ? m - bant.upperBound : 0
                    }
                    hSecim = probeSirasi.min {
                        let (a, b) = (uzaklik(denenen[$0]!.medyan), uzaklik(denenen[$1]!.medyan))
                        return a != b ? a < b : $0 < $1   // eşitlikte küçük çarpan (kolay yön) — deterministik
                    }!
                    uyarilar[diff, default: []].append(level)
                }
            }

            let secimSonuc = denenen[hSecim]!
            let bantta = diff == .kabus
                ? secimSonuc.results.contains { $0.won }
                : hedefBant(level, diff).contains(secimSonuc.medyan)
            sonuclar.append(AyarSonuc(level: level, d: dFormul, hpMult: hSecim,
                                      medyan: secimSonuc.medyan,
                                      varyantSonuclari: secimSonuc.results,
                                      bantta: bantta,
                                      probeSayisi: denenen.count,
                                      kelepce: kelepce))
        }
        tumSonuclar[diff] = sonuclar
    }

    let sure = Date().timeIntervalSince(baslangic)

    // Özet tablolar (kademe başına)
    print("BalanceLab ayar v3 — 4 kademe × 50 seviye, GreedyPolicy {0.8, 0.9, 1.0}")
    print("Kompozisyon D = min(formül, 1.3) sabit; kademe can/maliyet kimliği simde etkin")
    print("Süre: \(String(format: "%.1f", sure)) sn\n")
    for diff in Difficulty.allCases {
        let sonuclar = tumSonuclar[diff]!
        let kimlik = "can \(diff.startingLives), maliyet ×\(diff.costMultiplier)"
        let kural = diff == .kabus ? "kazanılabilirlik (≥1 varyant)" : "medyan banda"
        print("— \(diff.label) (\(kimlik)) — \(kural)")
        let header = [pad("L", 3, right: true), pad("hpMult", 7, right: true),
                      pad("Medyan", 7, right: true), pad("Bant", 7),
                      pad("Varyant", 14), pad("Sonda", 6, right: true),
                      pad("Durum", 16)].joined(separator: "  ")
        print(header)
        print(String(repeating: "-", count: header.count))
        for s in sonuclar {
            let bantStr = diff == .kabus ? "≥1 K"
                : { let b = hedefBant(s.level, diff); return "\(b.lowerBound)-\(b.upperBound)" }()
            let varyant = s.varyantSonuclari
                .map { "\($0.won ? "K" : "✗")\($0.livesLeft)" }.joined(separator: "/")
            let durum = s.bantta
                ? (s.kelepce ? "✓ (kelepçe <1)" : "✓")
                : (diff == .kabus ? "KAZANILAMAZ" : "UYARI: bant dışı")
            print([pad("\(s.level)", 3, right: true),
                   pad(String(format: "%.3f", s.hpMult), 7, right: true),
                   pad("\(s.medyan)", 7, right: true),
                   pad(bantStr, 7),
                   pad(varyant, 14),
                   pad("\(s.probeSayisi)", 6, right: true),
                   pad(durum, 16)].joined(separator: "  "))
        }
        let isabet = sonuclar.count { $0.bantta }
        print("İsabet: \(isabet)/50\n")
    }

    // Tehdit kontrolü (Normal 46-50): en az bir bütçe varyantı bandın altına inmeli ya da kaybetmeli.
    print("Tehdit kontrolü (Normal L46-50): en az bir varyant <14 can ya da kayıp olmalı")
    for s in tumSonuclar[.normal]! where s.level >= 46 {
        let tehdit = s.varyantSonuclari.contains { !$0.won || $0.livesLeft < 14 }
        let canlar = s.varyantSonuclari.map { "\($0.livesLeft)\($0.won ? "" : "✗")" }
            .joined(separator: "/")
        print("  L\(s.level): varyant canları \(canlar) → tehdit \(tehdit ? "✓" : "YOK (uyarı)")")
    }
    for diff in Difficulty.allCases {
        if let u = uyarilar[diff], !u.isEmpty {
            print("\nUYARI — \(diff.label): banda oturmayan seviyeler: \(u.map(String.init))")
        }
    }
    let kelepceler = tumSonuclar[.kabus]!.filter(\.kelepce).map(\.level)
    if !kelepceler.isEmpty {
        print("\nKâbus kelepçe (<1.0) seviyeleri: \(kelepceler.map(String.init)) — kimlik 3 candan")
    }
    if !kazanilamayanlar.isEmpty {
        print("KAZANILAMAZ (kabus, 0.85'te bile): \(kazanilamayanlar.map(String.init)) — TASARIM SORUNU")
    }

    yazTunedDifficulty(tumSonuclar[.normal]!.map(\.d),
                       Difficulty.allCases.map { ($0.rawValue, tumSonuclar[$0]!.map(\.hpMult)) })
}

/// TunedDifficulty.swift'i yeniden yazar. Başlıkta tarih YOK — dosya deterministik
/// olmalı (aynı kod tabanında her koşu birebir aynı içerik). Kademe sırası
/// Difficulty.allCases ile sabit.
func yazTunedDifficulty(_ dByLevel: [Double], _ hpMultByTier: [(tier: String, values: [Double])]) {
    precondition(dByLevel.count == 50 && hpMultByTier.allSatisfy { $0.values.count == 50 })
    func blok(_ values: [Double], girinti: String) -> String {
        stride(from: 0, to: 50, by: 10).map { start in
            girinti + (start..<start + 10)
                .map { String(format: "%.3f", values[$0]) }
                .joined(separator: ", ") + ","
        }.joined(separator: "\n")
    }
    let tierBloklar = hpMultByTier.map { tier, values in
        "        \"\(tier)\": [\n\(blok(values, girinti: "            "))\n        ],"
    }.joined(separator: "\n")

    let icerik = """
    /// ÜRETİLMİŞ DOSYA — elle düzenlemeyin.
    /// Üretici: `swift run -c release BalanceLab ayar` (v3 — H1b).
    /// dByLevel: kompozisyon kaynağı (formül D değerleri; üreteç bütçeye 1.3
    /// tavanıyla sokar — çeşitlilik ekseni). hpMultByTier: kademe başına birim HP
    /// çarpanı eğrisi (anahtar Difficulty.rawValue) — asıl zorluk kaldıracı.
    /// normal/zor/cokZor: GreedyPolicy bütçe oranları {0.8, 0.9, 1.0} medyanı
    /// kademenin kendi hedef bandına oturana dek ikili aramayla ayarlanır
    /// (kademe can/maliyet kimliği simde ETKİN). kabus: kazanılabilirlik-öncelikli —
    /// en az BİR varyantın kazandığı en büyük çarpan; 1.0 bile kazanılamazsa
    /// 0.85 tabanına dek aşağı kelepçelenir (kimlik 3 candan gelir).
    /// Çarpan gelir-nötrdür (ödül/can bedeli taban kalır).
    /// Harita topolojisi her ikisinden de bağımsızdır.
    public enum TunedDifficulty {
        public static let dByLevel: [Double] = [
    \(blok(dByLevel, girinti: "        "))
        ]

        /// Kademe başına birim HP çarpanı (H1b): motor düşman HP'sini
        /// LevelGenerator.hpMultiplier(_:difficulty:) üzerinden bununla ölçekler.
        public static let hpMultByTier: [String: [Double]] = [
    \(tierBloklar)
        ]
    }

    """

    // main.swift → Sources/BalanceLab → Sources → GameCore/TunedDifficulty.swift
    let hedef = URL(fileURLWithPath: #filePath)
        .deletingLastPathComponent()
        .deletingLastPathComponent()
        .appendingPathComponent("GameCore/TunedDifficulty.swift")
    do {
        try icerik.write(to: hedef, atomically: true, encoding: .utf8)
        print("\nYazıldı: \(hedef.path)")
    } catch {
        print("\nHATA: TunedDifficulty.swift yazılamadı: \(error)")
        exit(1)
    }
}

// MARK: - zorluk modu (H1 → H1b)

/// Zorluk kademeleri doğrulaması: örnek seviyeler × 4 kademe × GreedyPolicy
/// {0.8, 0.9, 1.0}. Her hücre kademenin KENDİ ayarlı eğrisiyle koşar
/// (LevelGenerator.hpMultiplier(_:difficulty:) — H1b). GEREKSİNİM: her
/// (seviye, kademe) hücresinde en az BİR varyant kazanmalı — Kâbus'ta varyant
/// kaybı kimliğin parçası, ama üçü birden asla kaybetmemeli. İhlal varsa
/// `ayar` modu yeniden koşulur (eğri eskimiş demektir).
func zorluk() {
    let levels = [1, 5, 10, 20, 30, 40, 45, 50]
    let ratios = [0.8, 0.9, 1.0]
    // "magaza" argümanı: tam mağaza profili (gerçek kampanya oyuncusu L20+ itibarıyla
    // genelde tüm bonus item'lara sahiptir; çıplak bot kötümser alt sınırdır).
    let magaza = CommandLine.arguments.dropFirst(2).first == "magaza"
    let mods = magaza
        ? RunModifiers(startGoldBonus: 50, damageMultiplier: 1.1, extraLives: 2)
        : RunModifiers.none
    print("BalanceLab zorluk — örnek seviyeler × kademeler, GreedyPolicy \(ratios)"
          + (magaza ? " — TAM MAĞAZA (+50 altın, ×1.1 hasar, +2 can)" : ""))
    print("Kademe kimliği: can \(Difficulty.allCases.map { String($0.startingLives) }.joined(separator: "/")) · maliyet ×\(Difficulty.allCases.map { String($0.costMultiplier) }.joined(separator: "/")) · hp = kademenin ayarlı eğrisi (H1b)\n")

    let header = [pad("L", 3, right: true), pad("Zorluk", 8),
                  pad("hpMult", 7, right: true),
                  pad("Sonuçlar (0.8/0.9/1.0)", 24),
                  pad("Medyan can", 10, right: true), pad("Durum", 10)]
        .joined(separator: "  ")
    print(header)
    print(String(repeating: "-", count: header.count))

    var ihlaller: [(level: Int, diff: Difficulty)] = []
    for level in levels {
        let def = LevelGenerator.level(level)
        for diff in Difficulty.allCases {
            let hp = LevelGenerator.hpMultiplier(level, difficulty: diff)
            var results: [SimResult] = []
            for ratio in ratios {
                var policy = GreedyPolicy(buildBudgetRatio: ratio)
                results.append(Simulator.run(map: def.map, waves: def.waves,
                                             modifiers: mods,
                                             enemyHPMultiplier: hp,
                                             difficulty: diff, policy: &policy))
            }
            let medyan = results.map(\.livesLeft).sorted()[results.count / 2]
            let kazanan = results.count { $0.won }
            let cells = results.map { "\($0.won ? "K" : "✗")\($0.livesLeft)" }
                .joined(separator: "/")
            let durum = kazanan == 0 ? "İHLAL" : (kazanan == results.count ? "✓" : "✓ (\(kazanan)/3)")
            if kazanan == 0 { ihlaller.append((level, diff)) }
            print([pad("\(level)", 3, right: true), pad(diff.label, 8),
                   pad(String(format: "%.3f", hp), 7, right: true),
                   pad(cells, 24),
                   pad("\(medyan)", 10, right: true), pad(durum, 10)]
                .joined(separator: "  "))
        }
        print("")
    }

    if ihlaller.isEmpty {
        print("Gereksinim sağlandı: her (seviye, kademe) hücresinde en az bir kazanan varyant var.")
    } else {
        print("İHLAL — üç varyantı da kaybeden hücreler: "
              + ihlaller.map { "L\($0.level) \($0.diff.label)" }.joined(separator: ", "))
        print("Kademe eğrileri eskimiş: `swift run -c release BalanceLab ayar` ile yeniden ayarlayın.")
    }
}

/// Teşhis: D yanıt eğrisi — bot hangi D'de sızdırmaya başlıyor? (ayar aralığının
/// [0.7, 2.4] DIŞINI da tarar; bandın ulaşılabilirliğini raporlamak için.)
func dtara() {
    let levels = [10, 20, 35, 50]
    let dValues: [Double] = [1.0, 2.4, 3.0, 4.0, 6.0, 8.0, 12.0, 16.0, 24.0]
    print("D yanıt eğrisi — GreedyPolicy 0.9, kalan can (✗ = kayıp)")
    for level in levels {
        let map = LevelGenerator.level(level).map
        var line = pad("L\(level)", 4)
        for d in dValues {
            let waves = LevelGenerator.waves(id: level, difficulty: d)
            var policy = GreedyPolicy(buildBudgetRatio: 0.9)
            let r = Simulator.run(map: map, waves: waves, policy: &policy)
            line += "  D\(String(format: "%4.1f", d))→" + pad("\(r.livesLeft)\(r.won ? "" : "✗")", 3)
        }
        print(line)
    }
}

switch mode {
case "rapor":
    rapor()
case "detay":
    detay()
case "ayar":
    ayar()
case "zorluk":
    zorluk()
case "dtara":
    dtara()
default:
    print("Bilinmeyen mod: \(mode). Kullanım: BalanceLab [rapor|detay|ayar|zorluk|dtara]")
}

import Foundation

/// E5 — Başarımlar: oyun sonu anlık görüntüsü + kalıcı sayaçlardan oluşan bağlam.
/// Saf veri: GameSession oyun bittiğinde doldurur, AchievementEngine değerlendirir.
/// Sayaç alanları (normalPlusWinLevels, treasury, totalKills, dailyWins,
/// bestEndlessWave) BU OYUN DAHİL güncel değerlerdir — çağıran önce kaydeder.
public struct AchievementContext: Sendable {
    /// Oyun kipi — Difficulty yalnız campaign'de anlamlı (diğerlerinde .normal).
    public enum Mode: Sendable {
        case campaign, freePlay, endless, daily
    }

    public var won: Bool
    /// Toplam can kaybı (initialLives − lives). Boss livesCost>1 ise tek boss
    /// birden çok sızıntı sayar — kabul: "kusursuz" hiç can kaybı demektir.
    public var leaks: Int
    public var towerKindsUsed: Set<TowerKind>
    /// Bu turda KURULAN toplam kule (satılanlar dahil — satışla hile yapılamaz).
    public var towersBuilt: Int
    public var difficulty: Difficulty
    public var mode: Mode
    public var reachedWave: Int
    /// Sefer'de HERHANGİ kademede kazanılmış seviye sayısı (0–50).
    public var normalPlusWinLevels: Int
    /// Kâbus kademesinde kazanılmış seviye sayısı (0–50).
    public var kabusWinLevels: Int
    public var treasury: Int
    public var totalKills: Int
    public var dailyWins: Int
    /// Tüm haritalardaki en iyi sonsuz dalga rekoru.
    public var bestEndlessWave: Int

    public var isKabus: Bool { difficulty == .kabus }

    public init(won: Bool, leaks: Int, towerKindsUsed: Set<TowerKind>,
                towersBuilt: Int, difficulty: Difficulty, mode: Mode,
                reachedWave: Int, normalPlusWinLevels: Int, kabusWinLevels: Int,
                treasury: Int, totalKills: Int, dailyWins: Int,
                bestEndlessWave: Int) {
        self.won = won
        self.leaks = leaks
        self.towerKindsUsed = towerKindsUsed
        self.towersBuilt = towersBuilt
        self.difficulty = difficulty
        self.mode = mode
        self.reachedWave = reachedWave
        self.normalPlusWinLevels = normalPlusWinLevels
        self.kabusWinLevels = kabusWinLevels
        self.treasury = treasury
        self.totalKills = totalKills
        self.dailyWins = dailyWins
        self.bestEndlessWave = bestEndlessWave
    }
}

/// Tek başarım tanımı. id kalıcı kayıt anahtarıdır (Persistence.achievedIDs) —
/// DEĞİŞTİRME; başlık/açıklama/ikon yalnız sunumdur.
public struct Achievement: Identifiable, Sendable, Equatable {
    public let id: String
    public let title: String
    public let desc: String
    public let icon: String
}

/// Saf değerlendirme motoru: bağlam + halihazırda kazanılmış id kümesi →
/// YENİ kazanılan başarımlar (katalog sırasında). UserDefaults/yan etki yok.
public enum AchievementEngine {
    /// 11 yerel başarım — katalog sırası vitrindeki ve toast'taki sıradır.
    public static let all: [Achievement] = [
        Achievement(id: "ilk-zafer", title: "İlk Zafer",
                    desc: "Herhangi bir kipte ilk galibiyetini al", icon: "🥇"),
        Achievement(id: "kusursuz", title: "Kusursuz",
                    desc: "Hiç can kaybetmeden bir oyun kazan", icon: "🛡️"),
        Achievement(id: "tek-tip", title: "Tek Tip",
                    desc: "Tek kule türüyle (en az 3 kule) kazan", icon: "🎯"),
        Achievement(id: "spartali", title: "Spartalı",
                    desc: "En çok 4 kuleyle bir oyun kazan", icon: "⚔️"),
        Achievement(id: "kabus-avcisi", title: "Kâbus Avcısı",
                    desc: "Kâbus kademesinde bir seviye kazan", icon: "💀"),
        Achievement(id: "sefer-fatihi", title: "Sefer Fatihi",
                    desc: "50 Sefer seviyesinin tamamını kazan", icon: "👑"),
        Achievement(id: "obsidyen-efendisi", title: "Obsidyen Efendisi",
                    desc: "50 seviyenin tamamını Kâbus'ta kazan", icon: "🖤"),
        Achievement(id: "zengin", title: "Zengin",
                    desc: "Hazinende 2000 altın biriktir", icon: "💰"),
        Achievement(id: "katliam", title: "Katliam",
                    desc: "Toplamda 5000 düşman öldür", icon: "🔥"),
        Achievement(id: "dalga-ustasi", title: "Dalga Ustası",
                    desc: "Sonsuz Mod'da 25. dalgaya ulaş", icon: "🌊"),
        Achievement(id: "mudavim", title: "Müdavim",
                    desc: "3 Günlük Meydan Okuma kazan", icon: "📅"),
    ]

    /// Bağlamı katalogla karşılaştırır; already'dekiler asla yeniden verilmez.
    public static func evaluate(_ ctx: AchievementContext,
                                already: Set<String>) -> [Achievement] {
        all.filter { !already.contains($0.id) && passes($0.id, ctx) }
    }

    /// Kural tablosu: galibiyet bazlılar bu oyunun anlık görüntüsünden,
    /// sayaç bazlılar kalıcı toplamlardan okur (galibiyet ŞART DEĞİL —
    /// AchievementsView pasif değerlendirmesi de aynı yoldan geçer).
    private static func passes(_ id: String, _ c: AchievementContext) -> Bool {
        switch id {
        case "ilk-zafer": c.won
        case "kusursuz": c.won && c.leaks == 0
        case "tek-tip": c.won && c.towerKindsUsed.count == 1 && c.towersBuilt >= 3
        case "spartali": c.won && c.towersBuilt <= 4
        case "kabus-avcisi": c.won && c.isKabus
        case "sefer-fatihi": c.normalPlusWinLevels == 50
        case "obsidyen-efendisi": c.kabusWinLevels == 50
        case "zengin": c.treasury >= 2000
        case "katliam": c.totalKills >= 5000
        case "dalga-ustasi": c.bestEndlessWave >= 25
        case "mudavim": c.dailyWins >= 3
        default: false
        }
    }
}

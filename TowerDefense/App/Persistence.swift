import Foundation
import GameCore

/// Kalıcı en iyi sonuçlar (UserDefaults sarmalayıcı) — harita başına ayrı.
/// Klasik harita ESKİ anahtarları kullanır (geriye uyum: mevcut rekorlar korunur);
/// diğer haritalar "_<harita adı>" ekiyle ayrışır.
/// Not: Serbest Oyun kaldırıldı — eski bestWave/winCount anahtarları
/// UserDefaults'ta öksüz kaldı (zararsız), API'leri silindi.
enum Persistence {
    static let classicMapName = "Klasik Vadi"

    private static func key(_ base: String, mapName: String) -> String {
        mapName == classicMapName ? base : "\(base)_\(mapName)"
    }

    // MARK: - Sonsuz Mod rekoru (E1) — arena (harita) başına ayrı

    /// Sonsuzda ulaşılan en iyi dalga (başlatılan son dalga); hiç oynanmadıysa 0.
    static func bestEndlessWave(mapName: String) -> Int {
        UserDefaults.standard.integer(forKey: key("bestEndlessWave", mapName: mapName))
    }

    /// Sonsuz oyun sonunda çağrılır; yalnız İYİLEŞME yazılır.
    static func recordEndlessWave(_ reachedWave: Int, mapName: String) {
        if reachedWave > bestEndlessWave(mapName: mapName) {
            UserDefaults.standard.set(reachedWave,
                                      forKey: key("bestEndlessWave", mapName: mapName))
        }
    }

    // MARK: - Sefer (kampanya) ilerlemesi — Sonsuz/eski anahtarlardan tamamen ayrı

    /// Açık en yüksek Sefer seviyesi (1 tabanlı). Varsayılan 1: yalnız ilk seviye açık.
    static var unlockedLevel: Int {
        get { max(1, UserDefaults.standard.integer(forKey: "seferUnlockedLevel")) }
        set { UserDefaults.standard.set(newValue, forKey: "seferUnlockedLevel") }
    }

    /// Seviyenin kazanılmış yıldızı (0–3); hiç kazanılmadıysa 0.
    static func stars(level: Int) -> Int {
        UserDefaults.standard.integer(forKey: "seferStars_\(level)")
    }

    /// Yıldız kaydı: yalnız İYİLEŞME yazılır (düşük skor mevcut rekoru ezmez).
    static func recordStars(level: Int, _ newStars: Int) {
        if newStars > stars(level: level) {
            UserDefaults.standard.set(newStars, forKey: "seferStars_\(level)")
        }
    }

    /// Seviye bu kademede kazanıldı mı? (H1 — kademe rozetleri H2'de buradan okunur.)
    /// Anahtar: "seferWon_<n>_<rawValue>" — rawValue kalıcıdır, Difficulty'de kilitli.
    static func seferWon(level: Int, difficulty: Difficulty) -> Bool {
        UserDefaults.standard.bool(forKey: "seferWon_\(level)_\(difficulty.rawValue)")
    }

    /// Kademe galibiyetini işaretler (tek yönlü; yıldız/kilit mantığından bağımsız).
    static func recordSeferWin(level: Int, difficulty: Difficulty) {
        UserDefaults.standard.set(true, forKey: "seferWon_\(level)_\(difficulty.rawValue)")
    }

    // MARK: - Obsidyen ödülü (E2) — 50 Kâbus zaferinin kilidi

    /// Kâbus kademesinde kazanılmış Sefer seviyesi sayısı (0–50).
    static var kabusWinCount: Int {
        (1...50).filter { seferWon(level: $0, difficulty: .kabus) }.count
    }

    /// Obsidyen seti açık mı: 50 seviyenin TAMAMI Kâbus'ta kazanılmış.
    /// DEBUG'da "--obsidyen" launch arg'ının yazdığı bayrak da kabul edilir
    /// (ekran doğrulaması gerçek 50 zafer gerektirmesin diye).
    static var obsidyenUnlocked: Bool {
        #if DEBUG
        if UserDefaults.standard.bool(forKey: "debugObsidyen") { return true }
        #endif
        return kabusWinCount == 50
    }

    // MARK: - Günlük Meydan Okuma (E3) — gün başına TEK deneme

    /// Günün kalıcı anahtarı: "daily_YYYYMMDD".
    static func dailyKey(year: Int, month: Int, day: Int) -> String {
        String(format: "daily_%04d%02d%02d", year, month, day)
    }

    /// Günün durumu: denendi mi / kazanıldı mı / ulaşılan dalga (denenmediyse 0).
    static func dailyState(_ key: String) -> (attempted: Bool, won: Bool, wave: Int) {
        (attempted: UserDefaults.standard.bool(forKey: "\(key)_attempted"),
         won: UserDefaults.standard.bool(forKey: "\(key)_won"),
         wave: UserDefaults.standard.integer(forKey: "\(key)_wave"))
    }

    /// Oyun BAŞLARKEN çağrılır: tek deneme kilidi anında düşer (yarıda bırakmak
    /// ya da yeniden başlatmak yeni deneme açmaz — aynı gün kilitli kalır).
    static func recordDailyAttemptStart(_ key: String) {
        UserDefaults.standard.set(true, forKey: "\(key)_attempted")
    }

    /// Oyun sonunda çağrılır; dailyWinCount aynı gün için EN FAZLA 1 artar
    /// (E5 "müdavim" başarımı bu sayaçtan okuyacak).
    static func recordDailyResult(_ key: String, won: Bool, wave: Int) {
        if won && !UserDefaults.standard.bool(forKey: "\(key)_won") {
            UserDefaults.standard.set(dailyWinCount + 1, forKey: "dailyWinCount")
        }
        if won { UserDefaults.standard.set(true, forKey: "\(key)_won") }
        UserDefaults.standard.set(wave, forKey: "\(key)_wave")
    }

    /// Toplam günlük galibiyet sayısı (gün başına en çok 1).
    static var dailyWinCount: Int {
        UserDefaults.standard.integer(forKey: "dailyWinCount")
    }

    // MARK: - Başarımlar (E5) — kazanılmış id kümesi + kalıcı sayaçlar

    /// Kazanılmış başarım id'leri (AchievementEngine.all id'leri).
    static var achievedIDs: Set<String> {
        Set(UserDefaults.standard.stringArray(forKey: "achievedIDs") ?? [])
    }

    /// Yeni kazanımları kümeye ekler (tek yönlü — başarım geri alınmaz).
    static func recordAchievements(_ ids: [String]) {
        guard !ids.isEmpty else { return }
        UserDefaults.standard.set(Array(achievedIDs.union(ids)).sorted(),
                                  forKey: "achievedIDs")
    }

    /// Tüm oyunlardaki toplam öldürme ("katliam" başarımı buradan okur).
    static var totalKills: Int {
        UserDefaults.standard.integer(forKey: "totalKills")
    }

    /// Oyun sonunda o turun killCount'u eklenir.
    static func addKills(_ count: Int) {
        guard count > 0 else { return }
        UserDefaults.standard.set(totalKills + count, forKey: "totalKills")
    }

    /// HERHANGİ kademede kazanılmış Sefer seviyesi sayısı (0–50) —
    /// "sefer-fatihi" başarımı 50'de düşer.
    static var normalPlusWinLevels: Int {
        (1...50).filter { level in
            Difficulty.allCases.contains { seferWon(level: level, difficulty: $0) }
        }.count
    }

    /// Tüm haritalardaki en iyi sonsuz dalga ("dalga-ustasi" başarımı için).
    static var bestEndlessWaveOverall: Int {
        Maps.all.map { bestEndlessWave(mapName: $0.name) }.max() ?? 0
    }

    // MARK: - Hazine (kalıcı cüzdan) + mağaza envanteri

    /// Kalıcı Hazine — oyun içi tur altınından AYRI; mağaza item'ları bununla alınır.
    static var treasury: Int {
        get { UserDefaults.standard.integer(forKey: "treasury") }
        set { UserDefaults.standard.set(newValue, forKey: "treasury") }
    }

    /// Satın alınan item id'leri (katalog id'si — tohum item'larında sabit slug).
    static var ownedItems: Set<String> {
        get { Set(UserDefaults.standard.stringArray(forKey: "ownedItems") ?? []) }
        set { UserDefaults.standard.set(Array(newValue).sorted(), forKey: "ownedItems") }
    }

    /// Oyuncunun bilerek kapattığı item'lar (zorluk tercihi) — sahiplik silinmez.
    static var disabledItems: Set<String> {
        get { Set(UserDefaults.standard.stringArray(forKey: "disabledItems") ?? []) }
        set { UserDefaults.standard.set(Array(newValue).sorted(), forKey: "disabledItems") }
    }

    /// Yeni oyunda bonusu uygulanacak item'lar: sahip olunan − kapatılanlar.
    static var activeItems: Set<String> { ownedItems.subtracting(disabledItems) }

    static func toggleItemEnabled(_ id: String) {
        guard ownedItems.contains(id) else { return }
        if disabledItems.contains(id) {
            disabledItems.remove(id)
        } else {
            disabledItems.insert(id)
        }
    }

    // MARK: - Kuşanılan görünümler (skin seti / harita teması)

    /// Kuşanılı skin setinin assetKey'i (ör. "buz"); nil = orijinal görünüm.
    static var equippedSkin: String? {
        get { UserDefaults.standard.string(forKey: "equippedSkin") }
        set { UserDefaults.standard.set(newValue, forKey: "equippedSkin") }
    }

    /// Kuşanılı harita temasının assetKey'i (ör. "sonbahar"); nil = orijinal.
    static var equippedTheme: String? {
        get { UserDefaults.standard.string(forKey: "equippedTheme") }
        set { UserDefaults.standard.set(newValue, forKey: "equippedTheme") }
    }

    static func earnTreasury(_ amount: Int) {
        guard amount > 0 else { return }
        treasury += amount
    }

    /// Tek seferlik kalıcı satın alma: Hazine yeterse düşer ve sahiplik ekler.
    static func purchase(_ item: CatalogItem) -> Bool {
        guard !ownedItems.contains(item.id), treasury >= item.priceGold else { return false }
        treasury -= item.priceGold
        ownedItems.insert(item.id)
        return true
    }
}

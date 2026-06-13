import Foundation
import GameCore

/// Tek bir mağaza item'ının etkisi — bilinmeyen `type` oyun tarafından sessizce yok sayılır.
struct CatalogEffect: Codable, Hashable {
    let type: String
    let value: Double
}

struct CatalogItem: Codable, Identifiable, Hashable {
    let id: String
    let name: String
    let desc: String
    let icon: String
    let priceGold: Int
    let effect: CatalogEffect
    let premium: Bool
    /// "item" | "skin" | "theme" — eski önbellek JSON'unda alan yok → "item"
    /// (geriye uyum: kind'siz katalog bonusu gibi davranır, skin akışı görünmez).
    let kind: String
    /// Skin/tema varlık öneki (ör. "buz" → skin_buz_*.png); item'larda nil.
    let assetKey: String?

    /// Elle decode: kind/assetKey alanları olmayan ESKİ önbellek JSON'u da çözülür.
    /// (Encode tarafı sentezli kalır; önbellek zaten ham API verisiyle yazılıyor.)
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(String.self, forKey: .id)
        name = try c.decode(String.self, forKey: .name)
        desc = try c.decode(String.self, forKey: .desc)
        icon = try c.decode(String.self, forKey: .icon)
        priceGold = try c.decode(Int.self, forKey: .priceGold)
        effect = try c.decode(CatalogEffect.self, forKey: .effect)
        premium = try c.decode(Bool.self, forKey: .premium)
        kind = try c.decodeIfPresent(String.self, forKey: .kind) ?? "item"
        assetKey = try c.decodeIfPresent(String.self, forKey: .assetKey)
    }
}

struct Catalog: Codable {
    let version: Int
    let items: [CatalogItem]
}

/// Mağaza kataloğu istemcisi: canlı API → son önbellek → gömülü varsayılan.
/// Açılışta SENKRON yüklenir (önbellek ya da bundle — ağ beklenmez); `refresh()`
/// arka planda canlı kataloğu çekip önbelleği tazeler.
///
/// Paylaşımlı tekil: SwiftUI environment'ı da GameSession init'i de aynı örneği
/// kullanır (GameSession environment'a erişemez — init sırasında engine kurulur).
@MainActor
final class CatalogClient: ObservableObject {
    static let shared = CatalogClient()

    @Published private(set) var catalog: Catalog
    /// Mağazanın "Yenile" düğmesi sürerken ProgressView göstermesi için.
    @Published private(set) var isLoading = false

    /// UserDefaults "catalogURL" ile değiştirilebilir (canlıya alırken domain yazılır).
    private static let defaultURL = "http://localhost:3000/api/v1/catalog"

    private static var cacheFileURL: URL? {
        guard let dir = FileManager.default.urls(for: .applicationSupportDirectory,
                                                 in: .userDomainMask).first
        else { return nil }
        return dir.appendingPathComponent("catalog_cache.json")
    }

    init() {
        catalog = Self.loadCacheOrBundle()
    }

    /// Önbellek → bundle sırasıyla senkron yükler; ikisi de yoksa boş katalog
    /// (bundle her sürümde gömülü olduğundan pratikte boşa düşülmez).
    private static func loadCacheOrBundle() -> Catalog {
        let decoder = JSONDecoder()
        if let url = cacheFileURL,
           let data = try? Data(contentsOf: url),
           let cached = try? decoder.decode(Catalog.self, from: data) {
            return cached
        }
        if let url = Bundle.main.url(forResource: "default_catalog", withExtension: "json"),
           let data = try? Data(contentsOf: url),
           let bundled = try? decoder.decode(Catalog.self, from: data) {
            return bundled
        }
        return Catalog(version: 0, items: [])
    }

    /// Canlı kataloğu çeker (5sn zaman aşımı); başarıda önbelleğe yazar ve yayınlar.
    /// Her tür hata sessizce yutulur — eldeki katalog geçerli kalır.
    func refresh() async {
        let urlString = UserDefaults.standard.string(forKey: "catalogURL") ?? Self.defaultURL
        guard let url = URL(string: urlString) else { return }
        var request = URLRequest(url: url)
        request.timeoutInterval = 5

        isLoading = true
        defer { isLoading = false }
        do {
            let (data, response) = try await URLSession.shared.data(for: request)
            guard let http = response as? HTTPURLResponse, http.statusCode == 200 else { return }
            let fresh = try JSONDecoder().decode(Catalog.self, from: data)
            catalog = fresh
            if let cacheURL = Self.cacheFileURL {
                try? FileManager.default.createDirectory(
                    at: cacheURL.deletingLastPathComponent(),
                    withIntermediateDirectories: true)
                try? data.write(to: cacheURL, options: .atomic)
            }
        } catch {
            // Çevrimdışı/zaman aşımı: mevcut katalog (önbellek ya da bundle) kullanılmaya devam eder.
        }
    }

    /// Sahip olunan item'lardan tek turluk RunModifiers üretir:
    /// startGold ve extraLives toplanır, towerDamage çarpımsal (1+v) birleşir.
    /// Katalogda artık bulunmayan id'ler ve bilinmeyen effect type'ları yok sayılır.
    func modifiers(ownedIDs: Set<String>) -> RunModifiers {
        var startGold = 0
        var damageMultiplier = 1.0
        var extraLives = 0
        // Yalnız kind=="item" bonus üretir — skin/tema görünümdür, RunModifiers'a girmez.
        for item in catalog.items where item.kind == "item" && ownedIDs.contains(item.id) {
            switch item.effect.type {
            case "startGold": startGold += Int(item.effect.value)
            case "towerDamage": damageMultiplier *= 1.0 + item.effect.value
            case "extraLives": extraLives += Int(item.effect.value)
            default: break // ileri uyumluluk: bilinmeyen etki sessizce atlanır
            }
        }
        return RunModifiers(startGoldBonus: startGold,
                            damageMultiplier: damageMultiplier,
                            extraLives: extraLives)
    }
}

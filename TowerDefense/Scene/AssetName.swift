import GameCore
import SpriteKit

enum AssetName {
    static let tileGrass = "tile_grass"
    static let baseKeep = "base_keep"
    static let decorations = ["decor_tree_a", "decor_tree_b", "decor_tree_c", "decor_tree_d",
                              "decor_rocks_a", "decor_rocks_b", "decor_rocks_c", "decor_rocks_d",
                              "decor_bush", "decor_tuft"]

    static func towerKey(_ kind: TowerKind) -> String {
        switch kind {
        case .machineGun: "archer"
        case .rocket: "catapult"
        case .sniper: "bastion"
        case .crystal: "crystal"
        case .shock: "shock"
        case .orb: "orb"
        case .dart: "dart"
        case .solar: "solar"
        }
    }
    static func towerBody(_ kind: TowerKind, level: Int) -> String {
        "tower_\(towerKey(kind))_\(min(max(level, 1), 3))"
    }
    static func portrait(_ kind: TowerKind) -> String { "portrait_\(towerKey(kind))" }

    static func enemyKey(_ kind: EnemyKind) -> String {
        switch kind {
        case .infantry: "infantry"
        case .scout: "scout"
        case .armored: "armored"
        case .boss: "boss"
        case .scorpion: "scorpion"
        case .clampbeetle: "clampbeetle"
        case .voidbutterfly: "voidbutterfly"
        case .locust: "locust"
        }
    }
    /// PathTileShape -> dilimlenmiş tile adı (rotasyon YOK; yön başına ayrı hücre).
    static func tile(for shape: PathTileShape?) -> String {
        guard let shape else { return tileGrass }
        switch shape {
        case .straight(let vertical): return vertical ? "tile_path_v" : "tile_path_h"
        case .corner(let sides):
            if sides == [.right, .down] { return "tile_corner_rd" }
            if sides == [.left, .down] { return "tile_corner_ld" }
            if sides == [.right, .up] { return "tile_corner_ru" }
            return "tile_corner_lu"
        case .spawnCap(let open), .baseCap(let open):
            switch open {
            case .right: return "tile_cap_r"
            case .left: return "tile_cap_l"
            case .down: return "tile_cap_d"
            case .up: return "tile_cap_u"
            }
        }
    }
}

/// Kare animasyon bankası — pixel-art: filtreleme .nearest.
enum TextureBank {
    static var frameCounts: [String: Int] = [:]   // GameScene kurulumunda yüklenir

    static func texture(_ name: String) -> SKTexture {
        let t = SKTexture(imageNamed: skinResolved(name))
        t.filteringMode = .nearest
        return t
    }

    // MARK: - Skin önek çözümü

    /// Set başına bundle'daki skin dosya adları — İLK kullanımda bir kez taranır
    /// (her kare için Bundle araması YAPILMAZ; texture() sıcak yolda ucuz kalır).
    private static var skinNameCache: [String: Set<String>] = [:]
    /// Skinlenebilir varlık türleri (proj/impact orijinal kalır — mermi kimliği değişmez).
    private static let skinnablePrefixes = ["tower_", "weapon_", "portrait_"]

    /// Kuşanılı skin seti varsa ve ad kule gövdesi/silahı/portresiyse
    /// "skin_<set>_<ad>" varyantını döndürür; bundle'da yoksa orijinal ad.
    /// texture() ve bundleImage() aynı çözümden geçer.
    static func skinResolved(_ name: String) -> String {
        guard let set = Persistence.equippedSkin,
              skinnablePrefixes.contains(where: { name.hasPrefix($0) })
        else { return name }
        let candidate = "skin_\(set)_\(name)"
        return skinNames(for: set).contains(candidate) ? candidate : name
    }

    private static func skinNames(for set: String) -> Set<String> {
        if let cached = skinNameCache[set] { return cached }
        let prefix = "skin_\(set)_"
        let urls = Bundle.main.urls(forResourcesWithExtension: "png", subdirectory: nil) ?? []
        let names = Set(urls.lazy
            .map { $0.deletingPathExtension().lastPathComponent }
            .filter { $0.hasPrefix(prefix) })
        skinNameCache[set] = names
        return names
    }
    static func loadCounts() {
        if !frameCounts.isEmpty { return }   // restart: zaten yüklü
        guard let url = Bundle.main.url(forResource: "frame_counts", withExtension: "json"),
              let data = try? Data(contentsOf: url),
              let dict = try? JSONSerialization.jsonObject(with: data) as? [String: Int]
        else { preconditionFailure("frame_counts.json yüklenemedi") }
        frameCounts = dict
    }
    // Anahtar kuralları (slice_spire.py ile birebir):
    //   düşman: "<key>_<anim>_<dir>" sayısı; kare adı "enemy_<key>_<anim>_<dir>_<i>"
    //   kule:   "<key>_<lvl>_weapon|proj|impact"; kare adı "weapon_<key>_<lvl>_<i>" vb.
    static func enemyFrames(_ kind: EnemyKind, _ anim: String, _ dir: String) -> [SKTexture] {
        let key = AssetName.enemyKey(kind)
        let n = frameCounts["\(key)_\(anim)_\(dir)"] ?? 0
        precondition(n > 0, "düşman karesi yok: \(key) \(anim) \(dir)")
        return (0..<n).map { texture("enemy_\(key)_\(anim)_\(dir)_\($0)") }
    }
    /// Basit döngü şeritleri (ör. su): sayaç anahtarı = kare adı öneki.
    static func loopFrames(_ key: String) -> [SKTexture] {
        let n = frameCounts[key] ?? 0
        precondition(n > 0, "kare yok: \(key)")
        return (0..<n).map { texture("\(key)_\($0)") }
    }
    static func towerFrames(_ kind: TowerKind, level: Int, _ part: String) -> [SKTexture] {
        let key = AssetName.towerKey(kind)
        let n = frameCounts["\(key)_\(level)_\(part)"] ?? 0
        precondition(n > 0, "kule karesi yok: \(key) \(level) \(part)")
        let prefix = part == "weapon" ? "weapon" : part
        return (0..<n).map { texture("\(prefix)_\(key)_\(level)_\($0)") }
    }
}

import GameCore
import SpriteKit

final class GameScene: SKScene {
    unowned let session: GameSession

    private var map: MapDefinition { session.engine.map }
    private var didBuildScene = false
    private var isDetached = false
    private var lastUpdateTime: TimeInterval = 0

    private let tileLayer = SKNode()
    /// Ambient yaşam (V2): kelebekler + rüzgâr/yaprak esintileri — zemin dekorunun
    /// üstünde (tile z0 üstü), kule/düşmanların altında (world z10 altı) uçar.
    private let ambientLayer = SKNode()
    /// Kuleler ve düşmanlar TEK katmanda: SpriteKit (ignoresSiblingOrder=false) ayrı
    /// dalları asla iç içe sıralamaz; perspektif örtmesi için kardeş olmaları şart.
    private let worldLayer = SKNode()
    /// Can barları y-derinlik sıralamasından muaf — dünyanın üstünde ayrı katman.
    private let barLayer = SKNode()
    private let effectLayer = SKNode()
    private let overlayLayer = SKNode()

    private var towerNodes: [Int: SKNode] = [:]
    private struct EnemyVisual {
        let container: SKNode
        let body: SKSpriteNode
        let hpFill: SKShapeNode
        let barNode: SKNode    // barLayer'da yaşar; her karede düşmanla konumlanır
        let barWidth: CGFloat  // dolgu yolunun yeniden çizimi için
        var facing = ""        // "down" | "up" | "side"
        var mirrored = false
        var lastRatio = 1.0    // |Δ| > 0.01 olunca yol yeniden çizilir
        var barVisible = false // tam canda gizli; ilk hasarda belirir (boss hep görünür)
    }
    private var enemyNodes: [Int: EnemyVisual] = [:]
    private let rangeCircle = SKShapeNode()
    private var rangeCircleKey: (id: Int, level: Int)?
    private let buildMarker = SKShapeNode(rectOf: CGSize(width: 76, height: 76), cornerRadius: 8)
    /// Sürükle-bırak hayaleti: tek seferlik oluşturulan yarı saydam gövde + menzil halkası.
    private let ghostBody = SKSpriteNode()
    private let ghostRing = SKShapeNode()
    private var ghostKind: TowerKind?

    /// Spire silah/mermi kareleri yukarı bakar; sağa (0 rad) hizalamak için -90° düzeltme.
    static let assetRotationOffset: CGFloat = -CGFloat.pi / 2

    init(session: GameSession) {
        self.session = session
        super.init(size: CGSize(width: 1280, height: 720))
        scaleMode = .aspectFit
        backgroundColor = SKColor(red: 0.102, green: 0.078, blue: 0.047, alpha: 1)  // koyu meşe zemin (Theme.bgDark ile uyumlu)
    }

    required init?(coder: NSCoder) { fatalError("kullanılmıyor") }

    // MARK: - Koordinat dönüşümü (GameCore y-aşağı, SpriteKit y-yukarı)

    func scenePoint(_ v: Vec2) -> CGPoint {
        CGPoint(x: v.x, y: Double(size.height) - v.y)
    }

    func corePoint(_ p: CGPoint) -> Vec2 {
        Vec2(x: p.x, y: Double(size.height) - p.y)
    }

    /// Ekranda daha güneyde (küçük y) duran nesne öne çizilir (katman içi 0..9 aralığı).
    private func depth(forSceneY y: CGFloat) -> CGFloat {
        (size.height - y) / size.height * 9
    }

    // MARK: - Kurulum

    override func willMove(from view: SKView) {
        isDetached = true   // restart: session serbest bırakılırken update'in unowned erişimini kes
    }

    override func didMove(to view: SKView) {
        isDetached = false
        guard !didBuildScene else { return }
        didBuildScene = true
        verifyAssets()

        tileLayer.zPosition = 0
        ambientLayer.zPosition = 6
        worldLayer.zPosition = 10
        barLayer.zPosition = 25
        effectLayer.zPosition = 30
        overlayLayer.zPosition = 40
        for layer in [tileLayer, ambientLayer, worldLayer, barLayer, effectLayer, overlayLayer] {
            addChild(layer)
        }
        buildTiles()
        buildDecorations()
        buildAmbient()

        // Kâbus gece örtüsü (V3): tam ekran mor-lacivert perde, z5 — zemin/dekor
        // (tile z0) ÜSTÜNDE, ambient (z6) ve kule/düşman (world z10) ALTINDA;
        // can barları/HUD etkilenmez. Sahnede kamera yok: sahne boyutunda sabit
        // çocuk yeterli (.aspectFit tüm sahneyi olduğu gibi ölçekler).
        if session.difficulty == .kabus {
            let night = SKSpriteNode(
                color: SKColor(red: 0.16, green: 0.10, blue: 0.30, alpha: 1),
                size: size)
            night.alpha = 0.22
            night.position = CGPoint(x: size.width / 2, y: size.height / 2)
            night.zPosition = 5
            addChild(night)
        }

        // Mağaza bonusları görünür olsun: oyuncu satın aldığının işlediğini açılışta görür.
        let mods = session.engine.modifiers
        if mods.startGoldBonus > 0 || mods.extraLives > 0 || mods.damageMultiplier > 1.0 {
            var parts: [String] = []
            if mods.startGoldBonus > 0 { parts.append("+\(mods.startGoldBonus) altın") }
            if mods.extraLives > 0 { parts.append("+\(mods.extraLives) can") }
            if mods.damageMultiplier > 1.0 {
                parts.append("+%\(Int(((mods.damageMultiplier - 1) * 100).rounded())) hasar")
            }
            run(.sequence([.wait(forDuration: 0.6), .run { [weak self] in
                self?.showBanner(title: "MAĞAZA BONUSU",
                                 subtitle: parts.joined(separator: "  •  "),
                                 icon: "🛒")
            }]))
        }

        rangeCircle.strokeColor = SKColor(white: 1, alpha: 0.6)
        rangeCircle.fillColor = SKColor(white: 1, alpha: 0.12)
        rangeCircle.lineWidth = 2
        rangeCircle.isHidden = true
        overlayLayer.addChild(rangeCircle)

        buildMarker.strokeColor = SKColor.yellow
        buildMarker.fillColor = SKColor(red: 1, green: 1, blue: 0, alpha: 0.15)
        buildMarker.lineWidth = 3
        buildMarker.isHidden = true
        overlayLayer.addChild(buildMarker)

        // Sürükleme hayaleti: makeTowerNode ile aynı çapa/boyut mantığı, alpha 0.55.
        ghostBody.anchorPoint = CGPoint(x: 0.5, y: 0.30)
        ghostBody.alpha = 0.55
        ghostBody.zPosition = 2
        ghostBody.isHidden = true
        overlayLayer.addChild(ghostBody)
        ghostRing.lineWidth = 2
        ghostRing.zPosition = 1
        ghostRing.isHidden = true
        overlayLayer.addChild(ghostRing)
    }

    /// Spec gereği: asset eksikse sessiz bozulma yerine açık mesajla erken çökme.
    private func verifyAssets() {
        TextureBank.loadCounts()
        var names = [AssetName.tileGrass, "tile_path_h", "tile_path_v",
                     "tile_corner_rd", "tile_corner_ld", "tile_corner_ru", "tile_corner_lu",
                     "tile_cap_r", "tile_cap_l", "tile_cap_d", "tile_cap_u",
                     AssetName.baseKeep, "build_0", "water_0",
                     "bridge_h_0", "bridge_h_1", "bridge_h_2",
                     "bridge_h_top_0", "bridge_h_top_1", "bridge_h_top_2",
                     "bridge_v_0", "bridge_v_1", "bridge_v_2",
                     // V2: kıyılar (tip başına ilk kare), harabeler, ambient + wisp
                     "shore_edge_n_0", "shore_edge_s_0", "shore_edge_w_0", "shore_edge_e_0",
                     "shore_out_nw_0", "shore_out_ne_0", "shore_out_sw_0", "shore_out_se_0",
                     "shore_in_nw_0", "shore_in_ne_0", "shore_in_sw_0", "shore_in_se_0",
                     "decor_ruin_a", "decor_ruin_b", "decor_ruin_c", "decor_ruin_d",
                     "decor_wall_a", "decor_wall_b",
                     "fx_leaf_0", "fx_wind_0", "wisp_glow_0",
                     "ambient_butterfly_a_0", "ambient_butterfly_b_0"]
            + AssetName.decorations
        for kind in TowerKind.allCases {
            for level in 1...3 { names.append(AssetName.towerBody(kind, level: level)) }
            names.append(AssetName.portrait(kind))
            let key = AssetName.towerKey(kind)
            for level in 1...3 {
                names += ["weapon_\(key)_\(level)_0", "proj_\(key)_\(level)_0", "impact_\(key)_\(level)_0"]
            }
        }
        for kind in EnemyKind.allCases {
            let key = AssetName.enemyKey(kind)
            for anim in ["walk", "death"] {
                for dir in ["down", "up", "side"] {
                    names.append("enemy_\(key)_\(anim)_\(dir)_0")
                }
            }
        }
        names.append("collapse_0")
        for name in names {
            precondition(Bundle.main.url(forResource: name, withExtension: "png") != nil,
                         "Asset eksik: \(name).png — scripts/fetch_spire.sh çalıştırıp projeyi yeniden derleyin")
        }
        for sound in ["shot_archer", "shot_ballista", "shot_catapult", "impact_boulder",
                      "enemy_death", "leak", "build", "coin", "click"] {
            precondition(Bundle.main.url(forResource: sound, withExtension: "wav") != nil,
                         "Ses eksik: \(sound).wav — scripts/fetch_assets.sh çalıştırıp projeyi yeniden derleyin")
        }
        for music in ["music_menu", "music_game", "music_battle",
                      "amb_forest", "amb_crickets"] {
            precondition(Bundle.main.url(forResource: music, withExtension: "mp3") != nil,
                         "Müzik eksik: \(music).mp3 — scripts/fetch_assets.sh çalıştırıp projeyi yeniden derleyin")
        }
        // V3: zindan/bataklık ambiyansı OGG'den AAC'ye sıkıştırılır (m4a).
        for amb in ["amb_dungeon", "amb_swamp"] {
            precondition(Bundle.main.url(forResource: amb, withExtension: "m4a") != nil,
                         "Ambiyans eksik: \(amb).m4a — scripts/fetch_assets.sh çalıştırıp projeyi yeniden derleyin")
        }
    }

    private func buildTiles() {
        let ts = CGFloat(map.tileSize)
        let tint = grassTint()
        // Su animasyonu: aynı tipteki tüm kareler tek paylaşılan aksiyonla senkron
        // dalgalanır; kıyı şeritleri de mevcut su zamanlamasını (0.18s) kullanır
        // ve hepsi didMove'da aynı anda başladığından blok geneli senkron kalır.
        var loopCache: [String: (first: SKTexture, action: SKAction)] = [:]
        func waterLoop(_ key: String) -> (first: SKTexture, action: SKAction) {
            if let hit = loopCache[key] { return hit }
            let frames = TextureBank.loopFrames(key)
            let entry = (frames[0],
                         SKAction.repeatForever(.animate(with: frames, timePerFrame: 0.18)))
            loopCache[key] = entry
            return entry
        }
        func addWater(at tile: GridPoint, allowShore: Bool = true) {
            let kind = allowShore ? shoreKind(for: tile) : nil
            let loop = waterLoop(kind.map { "shore_\($0)" } ?? "water")
            let sprite = SKSpriteNode(texture: loop.first)
            sprite.size = CGSize(width: ts, height: ts)
            sprite.position = scenePoint(map.center(of: tile))
            // Kıyı karesinde çim GÖMÜLÜdür: çim karelerine vurulan palet/sonbahar
            // tonu kıyıya da vurulur, yoksa kıyıda dikiş görünür (V1 endişe 2).
            // Düz su boyanmaz.
            if kind != nil, let tint {
                sprite.color = tint.color
                sprite.colorBlendFactor = tint.factor
            }
            tileLayer.addChild(sprite)
            sprite.run(loop.action)
        }
        for row in 0..<map.rows {
            for col in 0..<map.columns {
                let tile = GridPoint(col: col, row: row)
                if map.waterTiles.contains(tile) {
                    addWater(at: tile)
                    continue
                }
                if let bridge = bridgeTexture(for: tile) {
                    // Köprü güvertesi yol dokusunun YERİNE çizilir; altına su konur
                    // (güverte opak ama kıyı/kenar tutarlılığı için) ve yatayda üst
                    // korkuluk üstteki su karesine dekor olarak taşar. Köprü altı
                    // hep DÜZ su: güverte kareyi örter, kıyı şeridi gerekmez.
                    addWater(at: tile, allowShore: false)
                    let deck = SKSpriteNode(texture: TextureBank.texture(bridge.deck))
                    deck.size = CGSize(width: ts, height: ts)
                    deck.position = scenePoint(map.center(of: tile))
                    deck.zPosition = 1
                    tileLayer.addChild(deck)
                    if let topName = bridge.topOverlay {
                        let top = SKSpriteNode(texture: TextureBank.texture(topName))
                        top.size = CGSize(width: ts, height: ts)
                        top.position = scenePoint(map.center(
                            of: GridPoint(col: tile.col, row: tile.row - 1)))
                        top.zPosition = 1
                        tileLayer.addChild(top)
                    }
                    continue
                }
                let tileShape = map.pathShape(of: tile)
                let sprite = SKSpriteNode(texture: TextureBank.texture(
                    AssetName.tile(for: tileShape)))
                sprite.size = CGSize(width: ts, height: ts)
                sprite.position = scenePoint(map.center(of: tile))
                // Çim tonu: sonbahar teması ya da seviye paleti (yol/su/köprü etkilenmez).
                if tileShape == nil, let tint {
                    sprite.color = tint.color
                    sprite.colorBlendFactor = tint.factor
                }
                tileLayer.addChild(sprite)
            }
        }
        // Üs yapısı: baseCap karesinin üstüne gözcü kulesi silüeti
        let keep = SKSpriteNode(texture: TextureBank.texture(AssetName.baseKeep))
        keep.anchorPoint = CGPoint(x: 0.5, y: 0.18)   // tabanı karede, gövdesi yukarı taşar
        keep.size = CGSize(width: ts * 0.9, height: ts * 0.9 * keep.texture!.size().height
                                                   / keep.texture!.size().width)
        keep.position = scenePoint(map.center(of: map.base))
        keep.zPosition = 2
        tileLayer.addChild(keep)

        // Komuta masası çerçevesi
        let border = SKShapeNode(rect: CGRect(x: 2, y: 2, width: size.width - 4, height: size.height - 4))
        border.strokeColor = SKColor(red: 0.16, green: 0.13, blue: 0.10, alpha: 1)
        border.lineWidth = 4
        border.zPosition = 3
        tileLayer.addChild(border)
    }

    /// Yol karesi nehri kesiyorsa köprü parçası: üst+alt su → yatay köprü
    /// (segment ucuna göre sol/orta/sağ; yalnız yatayda üst korkuluk taşması var),
    /// sol+sağ su → dikey köprü (üst/orta/alt). Tek karelik geçiş orta parça kullanır.
    private func bridgeTexture(for tile: GridPoint) -> (deck: String, topOverlay: String?)? {
        func isHBridge(_ t: GridPoint) -> Bool {
            map.pathTiles.contains(t)
                && map.waterTiles.contains(GridPoint(col: t.col, row: t.row - 1))
                && map.waterTiles.contains(GridPoint(col: t.col, row: t.row + 1))
        }
        func isVBridge(_ t: GridPoint) -> Bool {
            map.pathTiles.contains(t)
                && map.waterTiles.contains(GridPoint(col: t.col - 1, row: t.row))
                && map.waterTiles.contains(GridPoint(col: t.col + 1, row: t.row))
        }
        if isHBridge(tile) {
            let leftEnd = !isHBridge(GridPoint(col: tile.col - 1, row: tile.row))
            let rightEnd = !isHBridge(GridPoint(col: tile.col + 1, row: tile.row))
            let i = (leftEnd && rightEnd) ? 1 : leftEnd ? 0 : rightEnd ? 2 : 1
            return ("bridge_h_\(i)", "bridge_h_top_\(i)")
        }
        if isVBridge(tile) {
            let topEnd = !isVBridge(GridPoint(col: tile.col, row: tile.row - 1))
            let bottomEnd = !isVBridge(GridPoint(col: tile.col, row: tile.row + 1))
            let i = (topEnd && bottomEnd) ? 1 : topEnd ? 0 : bottomEnd ? 2 : 1
            return ("bridge_v_\(i)", nil)
        }
        return nil
    }

    /// Ham ton: RGB + blend ağırlığı (SKColor bileşen okuma — NSColor renk
    /// uzayı tuzağına girmeden karıştırma yapabilmek için sayılar saklanır).
    private struct Tint {
        var r, g, b: CGFloat
        var factor: CGFloat
    }

    /// Çim/kıyı/tutam-çalı ton karışımı (V2+V3): taban = sonbahar teması (HER
    /// ZAMAN paleti ezer) ya da seviye paleti (1 = soluk altın, 2 = koyu yeşil);
    /// üstüne zorluk katmanı (V3) bindirilir. İkisi de yoksa nil — doku olduğu
    /// gibi kalır (palet 0 + Normal; Sonsuz/Günlük difficulty zaten .normal).
    private func grassTint() -> (color: SKColor, factor: CGFloat)? {
        let base: Tint? = if Persistence.equippedTheme == "sonbahar" {
            Tint(r: 0.85, g: 0.62, b: 0.25, factor: 0.18)
        } else {
            switch session.palette {
            case 1: Tint(r: 0.78, g: 0.72, b: 0.45, factor: 0.12)
            case 2: Tint(r: 0.30, g: 0.45, b: 0.30, factor: 0.15)
            default: nil
            }
        }
        // Zorluk tonu (yalnız Sefer'de .normal dışı olabilir): zor → sıcak
        // alacakaranlık, cokZor → soğuk çelik, kabus → koyu mor (+ tam ekran örtü).
        let mood: Tint? = switch session.difficulty {
        case .normal: nil
        case .zor: Tint(r: 0.88, g: 0.60, b: 0.35, factor: 0.08)
        case .cokZor: Tint(r: 0.45, g: 0.55, b: 0.70, factor: 0.10)
        case .kabus: Tint(r: 0.20, g: 0.15, b: 0.30, factor: 0.12)
        }
        guard let mixed = Self.composeTints(base, mood) else { return nil }
        return (SKColor(red: mixed.r, green: mixed.g, blue: mixed.b, alpha: 1), mixed.factor)
    }

    /// İki ton katmanını TEK (renk, blendFactor) çiftine bileştirir — sprite'ta
    /// tek colorBlendFactor var, sıralı iki boyama uygulanamaz. Birim mantığı:
    /// renkler kendi blend ağırlıklarıyla orantılı lerp'lenir
    /// (r = (r1·f1 + r2·f2)/(f1+f2) — ağır katman rengi baskın), faktörler
    /// TOPLANIR (iki katmanın toplam örtücülüğü) ve 0.35'te kapaklanır ki
    /// çim dokusu okunur kalsın. Tek katman varsa aynen geçer.
    private static func composeTints(_ a: Tint?, _ b: Tint?) -> Tint? {
        switch (a, b) {
        case (nil, nil): return nil
        case (let t?, nil), (nil, let t?): return t
        case (let p?, let d?):
            let total = p.factor + d.factor
            let w = d.factor / total
            return Tint(r: p.r + (d.r - p.r) * w,
                        g: p.g + (d.g - p.g) * w,
                        b: p.b + (d.b - p.b) * w,
                        factor: min(total, 0.35))
        }
    }

    /// Su karesinin 4-komşu kara/su desenine göre kıyı tipi (`shore_<tip>` adının
    /// eki; ad = ÇİMİN olduğu yön — V1 dilimleme kuralıyla birebir). Harita dışı
    /// VE köprü kareleri su sayılır: bant ekran kenarında kesilmez, kıyı çizgisi
    /// köprünün altından sürer (güverte kendi karesini zaten tam örter).
    /// Tek kara komşu → düz kenar; iki BİTİŞİK kara → dış köşe; hiç dik kara ama
    /// tam BİR çapraz kara → iç köşe. Karşılıklı iki kara (1 kare genişlik kanal)
    /// ve 3+ kara düz su kalır — sette uç/yarımada karesi yok (V1 endişe 1).
    private func shoreKind(for tile: GridPoint) -> String? {
        func waterLike(_ col: Int, _ row: Int) -> Bool {
            guard col >= 0, row >= 0, col < map.columns, row < map.rows else { return true }
            let t = GridPoint(col: col, row: row)
            return map.waterTiles.contains(t)
                || (map.pathTiles.contains(t) && bridgeTexture(for: t) != nil)
        }
        let n = !waterLike(tile.col, tile.row - 1)   // kuzeyde kara (satır 0 üstte)
        let s = !waterLike(tile.col, tile.row + 1)
        let w = !waterLike(tile.col - 1, tile.row)
        let e = !waterLike(tile.col + 1, tile.row)
        switch [n, s, w, e].filter({ $0 }).count {
        case 1:
            return n ? "edge_n" : s ? "edge_s" : w ? "edge_w" : "edge_e"
        case 2:
            if n && w { return "out_nw" }
            if n && e { return "out_ne" }
            if s && w { return "out_sw" }
            if s && e { return "out_se" }
            return nil   // karşılıklı çift: dar kanal — düz su
        case 0:
            // İç köşe: çim yalnız tek çapraz cepte; birden çok cep desteklenmez.
            let pockets: [(String, Int, Int)] = [("in_nw", -1, -1), ("in_ne", 1, -1),
                                                 ("in_sw", -1, 1), ("in_se", 1, 1)]
                .filter { !waterLike(tile.col + $0.1, tile.row + $0.2) }
            return pockets.count == 1 ? pockets[0].0 : nil
        default:
            return nil
        }
    }

    /// Koordinat-hash'li deterministik dekor (~%10 yoğunluk) — her açılışta aynı görünüm.
    /// V2: 12 dilim — 0-9 eski havuz, 10-11 harabe/duvar (Kâbus'ta 8-11: yoğun
    /// harabe atmosferi). Geniş parçalar yer kontrolünden geçemezse kayaya düşer.
    private func buildDecorations() {
        let tint = grassTint()
        // Sonbahar temasında ağaç havuzu sonbahar ağaçları (c/d) ağırlıklı olur;
        // hash dağılımı korunur (aynı 10 uzunluk).
        let decorPool: [String] = Persistence.equippedTheme == "sonbahar"
            ? ["decor_tree_c", "decor_tree_d", "decor_tree_c", "decor_tree_d",
               "decor_rocks_a", "decor_rocks_b", "decor_rocks_c", "decor_rocks_d",
               "decor_bush", "decor_tuft"]
            : AssetName.decorations
        let ruinPool = ["decor_ruin_a", "decor_ruin_b", "decor_ruin_c",
                        "decor_ruin_d", "decor_wall_a", "decor_wall_b"]
        // Halka/sıra/duvar komşu karelere taşar: üst VE sağ komşu da inşa
        // edilebilir çim olmalı; sütunlar (a/b) tek kare genişlik — her yere olur.
        let wideRuins: Set<String> = ["decor_ruin_c", "decor_ruin_d",
                                      "decor_wall_a", "decor_wall_b"]
        // Ekran boyutları: kaynak piksel ≈ ×0.62 (ağacın 64→40 diliyle uyumlu).
        let ruinSizes: [String: CGSize] = [
            "decor_ruin_a": CGSize(width: 34, height: 117),   // 54×186 taş sütun
            "decor_ruin_b": CGSize(width: 34, height: 117),
            "decor_ruin_c": CGSize(width: 76, height: 74),    // 122×119 halka
            "decor_ruin_d": CGSize(width: 104, height: 73),   // 172×120 sıra
            "decor_wall_a": CGSize(width: 36, height: 23),    // 58×37 duvar
            "decor_wall_b": CGSize(width: 38, height: 23),
        ]
        let ruinSliceStart = session.difficulty == .kabus ? 8 : 10
        for row in 0..<map.rows {
            for col in 0..<map.columns {
                let tile = GridPoint(col: col, row: row)
                guard map.isBuildable(tile) else { continue }
                var h = UInt32(truncatingIfNeeded: (col &* 73_856_093) ^ (row &* 19_349_663))
                h = (h ^ (h >> 13)) &* 0x5BD1_E995
                guard h % 10 == 0 else { continue }
                let slice = Int((h / 10) % 12)
                var name: String
                if slice >= ruinSliceStart {
                    // Harabe dilimi: tür seçimi hash'in üst bitlerinden (tohumlu).
                    name = ruinPool[Int((h / 120) % UInt32(ruinPool.count))]
                    if wideRuins.contains(name),
                       !(map.isBuildable(GridPoint(col: col, row: row - 1))
                         && map.isBuildable(GridPoint(col: col + 1, row: row))) {
                        name = "decor_rocks_b"   // taşacak yer yok: kayaya düş
                    }
                } else {
                    name = decorPool[slice % decorPool.count]
                }
                // Ağaç tepesi üstteki kareye taşar (40×80, merkezde): yalnızca yukarı komşusu
                // (row-1 — satır 0 üsttedir, ekranda yukarısı) da inşa edilebilir çimse ağaç
                // dik; değilse (yol/su/harita dışı) deterministik küçük dekora düş.
                if name.hasPrefix("decor_tree"),
                   !map.isBuildable(GridPoint(col: col, row: row - 1)) {
                    name = "decor_rocks_a"
                }
                let isTree = name.hasPrefix("decor_tree")
                let ruinSize = ruinSizes[name]
                let sprite = SKSpriteNode(texture: TextureBank.texture(name))
                sprite.size = isTree
                    ? CGSize(width: 40, height: 80)   // 1×2 hücre oranı
                    : ruinSize ?? CGSize(width: 36, height: 36)
                var pos = scenePoint(map.center(of: tile))
                if isTree {
                    // Aynı hash bitleri, dar eşleme: x ±10, y yalnız aşağı (0..-14) —
                    // taç hiçbir zaman yukarı komşunun ötesine süzülmez.
                    pos.x += Double(Int(h % 41)) / 2.0 - 10.0
                    pos.y -= Double(Int((h / 41) % 41)) * 14.0 / 40.0
                } else if let ruinSize {
                    // Harabeler kare merkezine yakın durur (dar x sapması); uzun
                    // sütun yukarı, geniş parçalar kontrol edilen üst/sağ komşuya taşar.
                    pos.x += Double(Int(h % 21)) - 10.0
                    pos.y += Double(ruinSize.height > 80 ? 18 : 6)
                } else {
                    pos.x += Double(Int(h % 41)) - 20.0
                    pos.y += Double(Int((h / 41) % 41)) - 20.0
                }
                sprite.position = pos
                sprite.zPosition = 2
                // Tutam/çalı çimle aynı yeşildendir: palet/sonbahar tonu aynen vurulur
                // (V1 endişe 2 — kayalar/harabeler taş rengi, boyanmaz).
                if let tint, name == "decor_bush" || name == "decor_tuft" {
                    sprite.color = tint.color
                    sprite.colorBlendFactor = tint.factor
                }
                if name.hasPrefix("decor_tree") {
                    let sway = SKAction.sequence([
                        .rotate(toAngle: 0.035, duration: 1.6 + Double(h % 7) * 0.1),
                        .rotate(toAngle: -0.035, duration: 1.6 + Double(h % 7) * 0.1),
                    ])
                    sprite.run(.repeatForever(sway))
                }
                tileLayer.addChild(sprite)
            }
        }
    }

    // MARK: - Ambient yaşam (V2)

    /// Seviye tohumlu kelebekler + aralıklı rüzgâr/yaprak esintisi. Kelebek sayısı,
    /// türleri ve durak rotaları harita adına tohumlu (aynı seviye hep aynı canlılar);
    /// rüzgâr zamanlaması bilinçli olarak tohumsuz (her oturumda farklı esinti anı).
    /// Performans: 2-3 kalıcı kelebek + kısa ömürlü esinti düğümleri (≤8 eşzamanlı).
    private func buildAmbient() {
        var rng = SeededRNG(seed: Self.fnv1a(session.mapName))
        let buildableCenters: [CGPoint] = (0..<map.rows).flatMap { row in
            (0..<map.columns).compactMap { col in
                let t = GridPoint(col: col, row: row)
                return map.isBuildable(t) ? scenePoint(map.center(of: t)) : nil
            }
        }
        guard !buildableCenters.isEmpty else { return }
        for _ in 0..<Int.random(in: 2...3, using: &rng) {
            let key = Bool.random(using: &rng) ? "ambient_butterfly_a" : "ambient_butterfly_b"
            let frames = TextureBank.loopFrames(key)
            let butterfly = SKSpriteNode(texture: frames[0])
            butterfly.setScale(0.35)
            butterfly.alpha = 0.85
            butterfly.position = buildableCenters.randomElement(using: &rng)!
            butterfly.run(.repeatForever(.animate(with: frames, timePerFrame: 0.08)))
            // 6 tohumlu durak arası süzülme; dizi başa sarınca son duraktan ilk
            // durağa akar — döngü kopmaz, ışınlanma olmaz.
            let hops: [SKAction] = (0..<6).map { _ in
                let move = SKAction.move(to: buildableCenters.randomElement(using: &rng)!,
                                         duration: Double.random(in: 5...9, using: &rng))
                move.timingMode = .easeInEaseOut
                return move
            }
            butterfly.run(.repeatForever(.sequence(hops)))
            ambientLayer.addChild(butterfly)
        }
        // Rüzgâr: 25-45 sn arayla şerit + yaprak savrulması.
        ambientLayer.run(.repeatForever(.sequence([
            .wait(forDuration: 35, withRange: 20),
            .run { [weak self] in self?.spawnWindGust() },
        ])))
    }

    /// fx_wind şeridi ekranı soldan sağa 3 sn'de geçer; eşzamanlı yapraklar
    /// yukarıdan aşağı-sağa savrularak iner (sonbahar temasında 8, yoksa 3).
    /// Yaprak şeridinin son kareleri BOŞ (V1 tasarımı) — yaprak inerken kaybolur.
    private func spawnWindGust() {
        let windFrames = TextureBank.loopFrames("fx_wind")
        let wind = SKSpriteNode(texture: windFrames[0])
        wind.setScale(1.5)
        wind.alpha = 0.7
        wind.position = CGPoint(x: -40, y: .random(in: size.height * 0.25...size.height * 0.8))
        ambientLayer.addChild(wind)
        wind.run(.repeatForever(.animate(with: windFrames, timePerFrame: 0.05)))
        wind.run(.sequence([.moveTo(x: size.width + 40, duration: 3.0), .removeFromParent()]))

        let leafFrames = TextureBank.loopFrames("fx_leaf")
        let leafCount = Persistence.equippedTheme == "sonbahar" ? 8 : 3
        for i in 0..<leafCount {
            let leaf = SKSpriteNode(texture: leafFrames[0])
            leaf.setScale(1.2)
            leaf.position = CGPoint(x: .random(in: 0...size.width * 0.7), y: size.height + 20)
            leaf.isHidden = true
            ambientLayer.addChild(leaf)
            let fall = Double.random(in: 3.2...4.6)
            let drift = SKAction.moveBy(x: .random(in: 120...260),
                                        y: -(size.height + 60), duration: fall)
            drift.timingMode = .easeIn
            leaf.run(.sequence([
                .wait(forDuration: Double(i) * 0.3),   // yapraklar peş peşe kopar
                .unhide(),
                .group([.animate(with: leafFrames,
                                 timePerFrame: fall / Double(leafFrames.count)), drift]),
                .removeFromParent(),
            ]))
        }
    }

    /// Harita adından deterministik tohum (FNV-1a 64) — Sefer adları benzersiz,
    /// Sonsuz arena adları sabit: aynı seviye hep aynı ambient kadro.
    private static func fnv1a(_ s: String) -> UInt64 {
        var h: UInt64 = 0xcbf2_9ce4_8422_2325
        for b in s.utf8 {
            h ^= UInt64(b)
            h = h &* 0x0000_0100_0000_01B3
        }
        return h
    }

    // MARK: - Girdi

    private func handleTap(at point: CGPoint) {
        guard session.phase == .building || session.phase == .waveActive else { return }
        guard let tile = map.tile(at: corePoint(point)) else {
            session.buildTile = nil
            session.selectedTowerID = nil
            return
        }
        if let tower = session.engine.tower(at: tile) {
            session.selectedTowerID = tower.id
            session.buildTile = nil
        } else if map.isBuildable(tile) {
            session.buildTile = tile
            session.selectedTowerID = nil
        } else {
            session.buildTile = nil
            session.selectedTowerID = nil
        }
    }

    #if os(macOS)
    override func mouseDown(with event: NSEvent) {
        handleTap(at: event.location(in: self))
    }
    #else
    override func touchesBegan(_ touches: Set<UITouch>, with event: UIEvent?) {
        guard let touch = touches.first else { return }
        handleTap(at: touch.location(in: self))
    }
    #endif

    // MARK: - Oyun döngüsü (sonraki görevlerde genişletilecek)

    // SpriteKit update/girdi geri çağrıları ana iş parçacığında çalışır; session (@MainActor)
    // erişimi bu varsayıma dayanır. Proje Swift 5.9 modunda — Swift 6'ya geçişte
    // GameScene/SoundPlayer izolasyonu yeniden ele alınmalı.
    override func update(_ currentTime: TimeInterval) {
        guard !isDetached else { return }
        let dt = lastUpdateTime == 0 ? 0 : min(currentTime - lastUpdateTime, 1.0 / 20.0)
        lastUpdateTime = currentTime
        // Duraklatmada TAM donma: yürüme/atış animasyonları, barlar, efektler,
        // dekor salınımı ve ambient yaşam dahil. overlayLayer (menzil çemberi,
        // duyurular) donmaz. ambientLayer hız almaz: rüzgâr/kelebek ortamdır,
        // oynanış hızıyla ilgisi yok (tileLayer'daki ağaç salınımı gibi).
        for layer in [tileLayer, ambientLayer, worldLayer, barLayer, effectLayer] {
            layer.isPaused = session.isPaused
        }
        // Oyun hızı animasyonlara da yansır: yürüme/atış (world), efektler ve barlar
        // (bar action taşımıyor — tutarlılık için zararsız). tileLayer 1x kalır:
        // ağaç salınımı ortam rüzgârıdır, oynanış hızıyla ilgisi yok.
        effectLayer.speed = CGFloat(session.gameSpeed)
        worldLayer.speed = CGFloat(session.gameSpeed)
        barLayer.speed = CGFloat(session.gameSpeed)
        // Hayalet, duraklatma korumasından ÖNCE: sürükleme biterse anında gizlenmeli.
        syncDragGhost()
        guard dt > 0, !session.isPaused else { return }

        let events = session.engine.update(dt: dt * session.gameSpeed)
        handle(events: events)
        syncEnemies()
        syncTowers()
        syncOverlays()
        session.syncFromEngine()
    }

    private func handle(events: [GameEvent]) {
        for event in events {
            switch event {
            case .towerFired(let towerID, let kind, let targetID, let targetPosition):
                fireEffect(towerID: towerID, kind: kind, targetPosition: targetPosition)

                // İsabet flaşı: hedef düşmanın sprite'ını anlık beyaza boyar, sonra söner.
                if let v = enemyNodes[targetID] {
                    v.body.removeAction(forKey: "flash")
                    v.body.run(.sequence([
                        .colorize(with: .white, colorBlendFactor: 0.7, duration: 0.05),
                        .colorize(withColorBlendFactor: 0, duration: 0.12),
                    ]), withKey: "flash")
                }

                // Hasar sayısı: yalnızca hasar >= 10 olan kuleler (örn. shock 3.5 hasar verir
                // ve 0.15s aralıkla atar — bu kadar sık yüzen yazı ekranı kirletir).
                if let tower = session.engine.towers.first(where: { $0.id == towerID }) {
                    let damage = tower.stats.damage
                    if damage >= 10 {
                        var p = scenePoint(targetPosition)
                        p.y += 22   // barın biraz üstünde görünsün
                        floatingText("-\(Int(damage))", at: p,
                                     color: SKColor(red: 1, green: 0.5, blue: 0.3, alpha: 1),
                                     fontSize: 14)
                    }
                }

            case .enemyDied(let id, let kind, let bounty, let position):
                session.killCount += 1
                SoundPlayer.shared.play("enemy_death", throttle: 0.1)
                var p = scenePoint(position)
                if let visual = enemyNodes.removeValue(forKey: id) {
                    // Mevcut bakış yönünde ölüm kareleri; ayna (xScale işareti) korunur
                    let facing = visual.facing.isEmpty ? "side" : visual.facing
                    let frames = TextureBank.enemyFrames(kind, "death", facing)
                    visual.body.removeAllActions()   // yürüme + boss salınımı durur
                    // Flash renk kalıntısını sıfırla: removeAllActions() "flash" eylemini keser
                    // ama colorBlendFactor değerini sıfırlamaz — ölüm animasyonu beyaz kalabilir.
                    visual.body.colorBlendFactor = 0
                    visual.container.children
                        .filter { $0.name != "body" }
                        .forEach { $0.run(.fadeOut(withDuration: 0.15)) }   // gölge söner
                    visual.barNode.run(.sequence([                          // can barı söner
                        .fadeOut(withDuration: 0.15),
                        .removeFromParent(),
                    ]))
                    visual.body.run(.sequence([
                        .animate(with: frames, timePerFrame: 0.08),
                        .wait(forDuration: 0.25),
                        .fadeOut(withDuration: 0.3),
                    ]))
                    visual.container.run(.sequence([
                        .wait(forDuration: 0.08 * Double(frames.count) + 0.6),
                        .removeFromParent(),
                    ]))
                }
                SoundPlayer.shared.play("coin", throttle: 0.15)
                p.y += 22
                floatingText("+\(bounty)", at: p,
                             color: SKColor(red: 0.95, green: 0.78, blue: 0.25, alpha: 1))
            case .enemyLeaked(let id, let livesLost):
                if let visual = enemyNodes.removeValue(forKey: id) {
                    visual.container.removeFromParent()
                    visual.barNode.removeFromParent()
                }
                SoundPlayer.shared.play("leak", throttle: 0.3)
                vignetteFlash()
                var p = scenePoint(map.center(of: map.base))
                p.y += 50
                floatingText("-\(livesLost) ❤", at: p, color: .red, fontSize: 26)
            case .waveCompleted(_, let bonus):
                showBanner(title: "DALGA TAMAMLANDI",
                           subtitle: "+\(bonus) altın ödül", icon: "🪙")
            case .gameWon, .gameLost:
                SoundPlayer.shared.stopMusic()
                effectLayer.removeAllChildren()   // uçuştaki roket/efekt hayaletlerini temizle
            case .enemySpawned:
                break   // HUD, session.phase üzerinden tepki verir
            }
        }
    }

    private func fireEffect(towerID: Int, kind: TowerKind, targetPosition: Vec2) {
        guard let towerNode = towerNodes[towerID] else { return }
        let target = scenePoint(targetPosition)
        let from = towerNode.position
        let dx = target.x - from.x, dy = target.y - from.y
        // towerFired event'i level taşımıyor; motor durumundan çöz
        let level = session.engine.towers.first(where: { $0.id == towerID })?.level ?? 1

        // Silahı hedefe döndür + atış animasyonu
        if let turret = towerNode.childNode(withName: "turret") as? SKSpriteNode {
            turret.run(.rotate(toAngle: atan2(dy, dx) + Self.assetRotationOffset,
                               duration: 0.06, shortestUnitArc: true))
            let frames = TextureBank.towerFrames(kind, level: level, "weapon")
            // Uzun sayfalar (orb 29 kare) da ≤0.45s'de tamamlansın
            let tpf = min(0.05, 0.45 / Double(frames.count))
            turret.removeAction(forKey: "attack")
            turret.run(.sequence([
                .animate(with: frames, timePerFrame: tpf),
                .setTexture(frames[0]),
            ]), withKey: "attack")
        }

        // Animasyonlu mermi: mancınık (rocket) parabolik, diğerleri düz uçuş
        let projFrames = TextureBank.towerFrames(kind, level: level, "proj")
        let impactFrames = TextureBank.towerFrames(kind, level: level, "impact")
        let proj = SKSpriteNode(texture: projFrames[0])
        let projSize = projFrames[0].size()
        // Spire mermileri çok küçük (8-22 px); ×1.6'da bile 80pt karoda kayboluyor.
        // Uzun kenarı en az 18pt olacak şekilde tek tip ölçek.
        let projScale = max(1.6, 18 / max(projSize.width, projSize.height))
        proj.size = CGSize(width: projSize.width * projScale, height: projSize.height * projScale)
        proj.zRotation = atan2(dy, dx) + Self.assetRotationOffset
        proj.zPosition = 6
        proj.position = from
        if projFrames.count > 1 {
            proj.run(.repeatForever(.animate(with: projFrames, timePerFrame: 0.07)))
        }
        effectLayer.addChild(proj)
        let distance = (dx * dx + dy * dy).squareRoot()
        let speed: CGFloat = kind == .rocket ? 420 : 900
        let impact: () -> Void = { [weak self] in
            guard let self else { return }
            let hit = SKSpriteNode(texture: impactFrames[0])
            hit.size = CGSize(width: impactFrames[0].size().width * 1.6,
                              height: impactFrames[0].size().height * 1.6)
            hit.position = target
            hit.zPosition = 7
            self.effectLayer.addChild(hit)
            hit.run(.sequence([.animate(with: impactFrames, timePerFrame: 0.06), .removeFromParent()]))
            // Taş ve alan hasarlı orb isabetleri ekranı hafifçe sarsar
            if kind == .rocket || kind == .orb { self.shakeScreen(intensity: 3) }
            SoundPlayer.shared.play(Self.impactSound(for: kind), throttle: 0.1)
        }
        if kind == .rocket {     // mancınık: yay + dönen taş
            let arc = CGMutablePath()
            let mid = CGPoint(x: (from.x + target.x) / 2,
                              y: (from.y + target.y) / 2 + max(50, distance * 0.25))
            arc.move(to: from)
            arc.addQuadCurve(to: target, control: mid)
            proj.run(.sequence([
                .group([.follow(arc, asOffset: false, orientToPath: false,
                                duration: Double(distance / speed)),
                        .rotate(byAngle: .pi * 2, duration: Double(distance / speed))]),
                .removeFromParent(),
            ])) { impact() }
        } else {
            proj.run(.sequence([.move(to: target, duration: Double(distance / speed)),
                                .removeFromParent()])) { impact() }
        }
        SoundPlayer.shared.play(Self.shotSound(for: kind), throttle: 0.05)
    }

    private static func shotSound(for kind: TowerKind) -> String {
        switch kind {
        case .machineGun, .shock, .dart: "shot_archer"
        case .sniper, .crystal: "shot_ballista"
        case .rocket, .orb, .solar: "shot_catapult"
        }
    }

    private static func impactSound(for kind: TowerKind) -> String {
        switch kind {
        case .rocket, .orb, .solar: "impact_boulder"
        default: "enemy_death"   // hafif tok ses; ayrı isabet sesi v2'de
        }
    }

    /// Yukarı süzülüp solan kısa yazı (ödül/can kaybı geri bildirimi).
    private func floatingText(_ text: String, at point: CGPoint, color: SKColor,
                              fontSize: CGFloat = 20) {
        let label = SKLabelNode(text: text)
        label.fontName = "Helvetica-Bold"
        label.fontSize = fontSize
        label.fontColor = color
        label.position = point
        label.zPosition = 5
        effectLayer.addChild(label)
        label.run(.sequence([
            .group([.moveBy(x: 0, y: 28, duration: 0.8), .fadeOut(withDuration: 0.8)]),
            .removeFromParent(),
        ]))
    }

    // MARK: - Bildirim banner'ları (parşömen plaka + yaylanan giriş + kuyruk)

    private var bannerQueue: [(title: String, subtitle: String?, icon: String?, tint: SKColor)] = []
    private var bannerShowing = false

    /// Eski çağrı imzasıyla uyumlu sarmalayıcı — yeni plakalı sisteme yönlendirir.
    func banner(_ text: String, color: SKColor = .white, yOffset: CGFloat = 60) {
        showBanner(title: text, tint: color)
    }

    /// Profesyonel bildirim: 9-slice parşömen plaka, ikon, yaylanan giriş (yukarıdan
    /// süzülüp hafif taşma ile oturur), altın çizgi vurgusu; sıraya alınır — üst üste binmez.
    func showBanner(title: String, subtitle: String? = nil,
                    icon: String? = nil, tint: SKColor = SKColor(red: 0.95, green: 0.78, blue: 0.25, alpha: 1)) {
        bannerQueue.append((title, subtitle, icon, tint))
        presentNextBanner()
    }

    private func presentNextBanner() {
        guard !bannerShowing, !bannerQueue.isEmpty else { return }
        bannerShowing = true
        let item = bannerQueue.removeFirst()

        let container = SKNode()
        container.zPosition = 12

        // Metin ölçüsüne göre plaka genişliği
        let titleLabel = SKLabelNode(text: item.title)
        titleLabel.fontName = "Helvetica-Bold"
        titleLabel.fontSize = 30
        titleLabel.fontColor = SKColor(red: 0.10, green: 0.08, blue: 0.05, alpha: 1)  // koyu meşe mürekkep
        titleLabel.verticalAlignmentMode = .center

        let subtitleLabel: SKLabelNode? = item.subtitle.map { text in
            let l = SKLabelNode(text: text)
            l.fontName = "Helvetica"
            l.fontSize = 17
            l.fontColor = SKColor(red: 0.10, green: 0.08, blue: 0.05, alpha: 0.65)
            l.verticalAlignmentMode = .center
            return l
        }

        let iconLabel: SKLabelNode? = item.icon.map { emoji in
            let l = SKLabelNode(text: emoji)
            l.fontSize = 34
            l.verticalAlignmentMode = .center
            return l
        }

        let textWidth = max(titleLabel.frame.width, subtitleLabel?.frame.width ?? 0)
        let iconWidth: CGFloat = iconLabel != nil ? 48 : 0
        let plateW = max(260, textWidth + iconWidth + 96)
        let plateH: CGFloat = item.subtitle != nil ? 96 : 76

        // 9-slice parşömen plaka (Adventure ui_panel; centerRect ile kenarlar bozulmadan gerilir)
        let plateTexture = SKTexture(imageNamed: "ui_panel")
        plateTexture.filteringMode = .linear   // UI görseli pixel-art değil; yumuşak ölçeklensin
        let plate = SKSpriteNode(texture: plateTexture)
        plate.centerRect = CGRect(x: 0.35, y: 0.35, width: 0.3, height: 0.3)
        plate.size = CGSize(width: plateW, height: plateH)
        container.addChild(plate)

        // Altın vurgu çizgisi (başlığın altında, plaka renk kimliği)
        let underline = SKSpriteNode(color: item.tint,
                                     size: CGSize(width: min(textWidth + 24, plateW - 72), height: 3))
        underline.position = CGPoint(x: iconWidth / 2, y: item.subtitle != nil ? 2 : -16)
        underline.alpha = 0.9
        container.addChild(underline)

        let textX = iconWidth / 2
        titleLabel.position = CGPoint(x: textX, y: item.subtitle != nil ? 16 : 4)
        container.addChild(titleLabel)
        if let s = subtitleLabel {
            s.position = CGPoint(x: textX, y: -18)
            container.addChild(s)
        }
        if let ic = iconLabel {
            ic.position = CGPoint(x: -plateW / 2 + 42, y: item.subtitle != nil ? 0 : 4)
            container.addChild(ic)
        }

        // Yukarıdan süzül, hafifçe taş, otur; bekle; yukarı süzülüp kaybol.
        let targetY = size.height - 96
        container.position = CGPoint(x: size.width / 2, y: size.height + plateH)
        container.setScale(0.92)
        container.alpha = 0
        overlayLayer.addChild(container)

        let slideIn = SKAction.group([
            .fadeIn(withDuration: 0.18),
            .scale(to: 1.0, duration: 0.22),
            .sequence([
                {
                    let drop = SKAction.moveTo(y: targetY - 10, duration: 0.28)
                    drop.timingMode = .easeOut
                    return drop
                }(),
                {
                    let settle = SKAction.moveTo(y: targetY, duration: 0.14)
                    settle.timingMode = .easeInEaseOut
                    return settle
                }(),
            ]),
        ])
        let slideOut = SKAction.group([
            {
                let up = SKAction.moveTo(y: targetY + 46, duration: 0.3)
                up.timingMode = .easeIn
                return up
            }(),
            .fadeOut(withDuration: 0.26),
            .scale(to: 0.94, duration: 0.3),
        ])
        container.run(.sequence([
            slideIn,
            .wait(forDuration: 1.5),
            slideOut,
            .removeFromParent(),
            .run { [weak self] in
                self?.bannerShowing = false
                self?.presentNextBanner()
            },
        ]))
    }

    /// Can kaybında ekran kenarında kısa kırmızı flaş.
    private func vignetteFlash() {
        let frame = SKShapeNode(rect: CGRect(origin: .zero, size: size))
        frame.strokeColor = .red
        frame.lineWidth = 36
        frame.alpha = 0
        frame.zPosition = 9
        overlayLayer.addChild(frame)
        frame.run(.sequence([
            .fadeAlpha(to: 0.7, duration: 0.08),
            .fadeOut(withDuration: 0.3),
            .removeFromParent(),
        ]))
    }

    private func syncEnemies() {
        var seen = Set<Int>()
        for enemy in session.engine.enemies {
            seen.insert(enemy.id)
            var visual = enemyNodes[enemy.id] ?? makeEnemyNode(for: enemy)
            let pos = enemy.position(on: map)
            visual.container.position = scenePoint(pos)
            visual.container.zPosition = depth(forSceneY: visual.container.position.y)
            let barYOffset: CGFloat = enemy.kind == .boss ? 52 : 34
            visual.barNode.position = CGPoint(x: visual.container.position.x,
                                              y: visual.container.position.y + barYOffset)

            // Yön: yolda 1 nokta ilerisine bak; rotasyon yerine yön bazlı kare seti
            let ahead = map.position(atPathDistance: enemy.pathDistance + 1)
            let dir = ahead - pos
            if dir.length > 0.0001 {
                let (facing, mirrored): (String, Bool) =
                    abs(dir.x) >= abs(dir.y) ? ("side", dir.x < 0)
                                             : (dir.y > 0 ? "down" : "up", false)   // GameCore y-aşağı
                if facing != visual.facing || mirrored != visual.mirrored {
                    visual.facing = facing
                    visual.mirrored = mirrored
                    // "side" kareleri sağa bakar; sola giderken negatif xScale ile aynala
                    visual.body.xScale = mirrored ? -abs(visual.body.xScale)
                                                  : abs(visual.body.xScale)
                    visual.body.removeAction(forKey: "walk")
                    visual.body.run(.repeatForever(.animate(
                        with: TextureBank.enemyFrames(enemy.kind, "walk", facing),
                        timePerFrame: enemy.kind == .scout ? 0.06 : 0.1)), withKey: "walk")
                }
            }
            // Can dolgusu: yol yeniden çizimi pahalı — yalnız %1'den büyük değişimde.
            // ÖLÇEKLİ maxHP (G5b): stats.maxHP taban tablo değeri; HP çarpanlı
            // düşmanda oran yanlış olurdu (bar hiç dolmazdı/yanlış başlar).
            let ratio = max(0, enemy.hp / enemy.maxHP)
            if abs(ratio - visual.lastRatio) > 0.01 {
                visual.lastRatio = ratio
                visual.hpFill.path = Self.hpFillPath(width: visual.barWidth, ratio: ratio)
                visual.hpFill.fillColor = Self.hpColor(forRatio: ratio)
                if !visual.barVisible {   // ilk hasar: bar süzülerek belirir
                    visual.barVisible = true
                    visual.barNode.run(.fadeAlpha(to: 1, duration: 0.15))
                }
            }
            enemyNodes[enemy.id] = visual
        }
        for (id, visual) in enemyNodes where !seen.contains(id) {
            visual.container.removeFromParent()
            visual.barNode.removeFromParent()
            enemyNodes.removeValue(forKey: id)
        }
    }

    private func makeEnemyNode(for enemy: Enemy) -> EnemyVisual {
        let container = SKNode()
        let firstFrame = TextureBank.enemyFrames(enemy.kind, "walk", "down").first!
        let body = SKSpriteNode(texture: firstFrame)
        body.name = "body"
        // Genişlik sabit; yükseklik doku oranından (Firebug kareleri 128×64 — geniş)
        let baseWidth: CGFloat
        switch enemy.kind {
        case .infantry: baseWidth = 44
        case .scout: baseWidth = 56     // geniş böcek; gövde küçük kalmasın
        case .armored: baseWidth = 50
        case .boss: baseWidth = 72
        case .scorpion: baseWidth = 50
        case .clampbeetle: baseWidth = 48
        case .voidbutterfly: baseWidth = 44
        case .locust: baseWidth = 40
        }
        let texSize = firstFrame.size()
        body.size = CGSize(width: baseWidth, height: baseWidth * texSize.height / texSize.width)
        if enemy.kind.isFlying {
            // Uçanlar: zemin gölgesi + havada salınım; gölge gövdeyle ölçeklenir
            container.addChild(makeShadow(width: baseWidth * 0.55,
                                          yOffset: -baseWidth * 0.36))
            body.run(.repeatForever(.sequence([
                .moveBy(x: 0, y: 4, duration: 0.6),
                .moveBy(x: 0, y: -4, duration: 0.6),
            ])), withKey: "hover")
            if enemy.kind == .boss { shakeScreen() }   // giriş sarsıntısı bossa özel
        }
        container.addChild(body)

        // Can barı ayrı katmanda (barLayer): kule gövdeleri barı örtemez.
        // Bar çocukları yerel y=0'da; barNode her karede düşman + barYOffset'e taşınır.
        // Tam canda gizli (alpha 0) — ilk hasarda süzülerek belirir; boss hep görünür.
        let barWidth: CGFloat = enemy.kind == .boss ? 72 : 48
        let barNode = SKNode()

        let barBack = SKShapeNode(rectOf: CGSize(width: barWidth + 2, height: 7),
                                  cornerRadius: 3.5)
        barBack.fillColor = SKColor(white: 0, alpha: 0.78)
        barBack.strokeColor = SKColor(white: 1, alpha: 0.30)
        barBack.lineWidth = 1
        barNode.addChild(barBack)

        let barFill = SKShapeNode()
        barFill.name = "hpFill"
        barFill.path = Self.hpFillPath(width: barWidth, ratio: 1)
        barFill.fillColor = Self.hpColor(forRatio: 1)
        barFill.strokeColor = .clear
        barNode.addChild(barFill)
        barNode.alpha = enemy.kind == .boss ? 1 : 0
        barLayer.addChild(barNode)

        worldLayer.addChild(container)
        let visual = EnemyVisual(container: container, body: body, hpFill: barFill,
                                 barNode: barNode, barWidth: barWidth,
                                 barVisible: enemy.kind == .boss)
        enemyNodes[enemy.id] = visual
        return visual
    }

    /// Yuvarlatılmış can dolgusu yolu — sol kenardan ratio kadar; en az 2pt görünür kalır.
    private static func hpFillPath(width: CGFloat, ratio: Double) -> CGPath {
        CGPath(roundedRect: CGRect(x: -width / 2 + 1, y: -2,
                                   width: max(2, (width - 2) * ratio), height: 4),
               cornerWidth: 2, cornerHeight: 2, transform: nil)
    }

    /// Can oranına göre dolgu rengi: yeşil → amber → kırmızı.
    private static func hpColor(forRatio ratio: Double) -> SKColor {
        if ratio > 0.55 { return SKColor(red: 0.30, green: 0.85, blue: 0.35, alpha: 1) }
        if ratio >= 0.28 { return SKColor(red: 0.95, green: 0.78, blue: 0.20, alpha: 1) }
        return SKColor(red: 0.90, green: 0.30, blue: 0.20, alpha: 1)
    }

    /// Kısa ekran sarsıntısı (boss girişi, büyük isabet).
    private func shakeScreen(intensity: CGFloat = 7) {
        let shake = SKAction.sequence([
            .moveBy(x: intensity, y: 0, duration: 0.04),
            .moveBy(x: -intensity * 2, y: intensity, duration: 0.04),
            .moveBy(x: intensity, y: -intensity, duration: 0.04),
            .moveBy(x: 0, y: 0, duration: 0.02),
        ])
        // barLayer da sarsılır ki barlar sarsıntıda düşmanlarından kopmasın
        for layer in [tileLayer, worldLayer, barLayer] { layer.run(shake) }
    }

    private func syncTowers() {
        var seen = Set<Int>()
        for tower in session.engine.towers {
            seen.insert(tower.id)
            let node = towerNodes[tower.id] ?? makeTowerNode(for: tower)
            if let badge = node.childNode(withName: "levelBadge") as? SKLabelNode {
                badge.text = tower.level > 1 ? "\(tower.level)" : ""
            }
            // Yükseltme görseli: gövde dokusu seviyeyle değişir, silah yukarı taşınır
            if let body = node.childNode(withName: "body") as? SKSpriteNode {
                let want = AssetName.towerBody(tower.kind, level: tower.level)
                if body.userData?["tex"] as? String != want {
                    let tex = TextureBank.texture(want)
                    body.texture = tex
                    body.userData = ["tex": want]
                    let ts = CGFloat(map.tileSize)
                    body.size = towerBodySize(for: tex)
                    if let weapon = node.childNode(withName: "turret") as? SKSpriteNode {
                        weapon.position = CGPoint(x: 0, y: min(weaponHeight(for: tower),
                                                               body.size.height * 0.62))
                        weapon.texture = TextureBank.towerFrames(tower.kind,
                                         level: tower.level, "weapon").first!
                    }
                    // İnşa kareleri yeniden oynar + ses
                    SoundPlayer.shared.play("build", throttle: 0.2)
                    let buildFX = SKSpriteNode(texture: TextureBank.texture("build_0"))
                    buildFX.size = CGSize(width: ts, height: ts)
                    buildFX.zPosition = 4
                    node.addChild(buildFX)
                    buildFX.run(.sequence([
                        .animate(with: buildFrames(), timePerFrame: 0.05),
                        .removeFromParent(),
                    ]))
                }
            }
        }
        for (id, node) in towerNodes where !seen.contains(id) {
            towerNodes.removeValue(forKey: id)
            // Satış: gövde/silah/rozet anında gizlenir, yerinde yıkım toz bulutu oynar.
            for name in ["body", "turret", "levelBadge"] {
                node.childNode(withName: name)?.alpha = 0
            }
            SoundPlayer.shared.play("impact_boulder", throttle: 0.2)
            let ts = CGFloat(map.tileSize)
            let collapseFX = SKSpriteNode(texture: TextureBank.texture("collapse_0"))
            collapseFX.size = CGSize(width: ts, height: ts)
            collapseFX.zPosition = 3
            node.addChild(collapseFX)
            // 13 karelik yıkım sayfası — örnekleme gerekmez (build'in 44'ünün aksine)
            collapseFX.run(.animate(with: collapseFrames(), timePerFrame: 0.05)) {
                node.removeFromParent()
            }
        }
    }

    /// Yıkım animasyonu kareleri — 13 karelik Collapse sayfası, tamamı kullanılır.
    private func collapseFrames() -> [SKTexture] {
        let n = TextureBank.frameCounts["collapse"] ?? 1
        return (0..<n).map { TextureBank.texture("collapse_\($0)") }
    }

    /// Birimlerin/kulelerin altına yumuşak elips gölge.
    private func makeShadow(width: CGFloat, yOffset: CGFloat) -> SKShapeNode {
        let shadow = SKShapeNode(ellipseOf: CGSize(width: width, height: width * 0.36))
        shadow.fillColor = SKColor(white: 0, alpha: 0.22)
        shadow.strokeColor = .clear
        shadow.position = CGPoint(x: 0, y: yOffset)
        shadow.zPosition = -1
        return shadow
    }

    /// Kule gövdesi ekran boyutu: genişlik ts*0.92, AMA toplam yükseklik ts*1.75'i aşamaz
    /// (64×192 kaynaklar için genişlik daraltılır — uzun kuleler kareden taşmasın).
    private func towerBodySize(for texture: SKTexture) -> CGSize {
        let ts = CGFloat(map.tileSize)
        let aspect = texture.size().height / texture.size().width
        let width = min(ts * 0.92, ts * 1.75 / aspect)
        return CGSize(width: width, height: width * aspect)
    }

    private func makeTowerNode(for tower: Tower) -> SKNode {
        let container = SKNode()
        container.position = scenePoint(map.center(of: tower.tile))
        container.zPosition = depth(forSceneY: container.position.y)   // kule sabit — bir kez yeter

        let body = SKSpriteNode(texture: TextureBank.texture(
            AssetName.towerBody(tower.kind, level: tower.level)))
        body.name = "body"
        body.userData = ["tex": AssetName.towerBody(tower.kind, level: tower.level)]
        let ts = CGFloat(map.tileSize)
        body.size = towerBodySize(for: body.texture!)
        body.anchorPoint = CGPoint(x: 0.5, y: 0.30)   // gövde yukarı doğru taşar
        container.addChild(body)

        let weapon = SKSpriteNode(texture: TextureBank.towerFrames(tower.kind,
                                  level: tower.level, "weapon").first!)
        weapon.name = "turret"
        weapon.size = CGSize(width: ts * 0.7, height: ts * 0.7)
        // Daraltılmış gövdelerde silah havada kalmasın: gövde yüksekliğinin %62'sine kenetle.
        weapon.position = CGPoint(x: 0, y: min(weaponHeight(for: tower),
                                               body.size.height * 0.62))
        weapon.zPosition = 2
        container.addChild(weapon)

        let badge = SKLabelNode(text: "")
        badge.name = "levelBadge"
        badge.fontName = "Helvetica-Bold"
        badge.fontSize = 16
        badge.fontColor = SKColor(red: 0.91, green: 0.64, blue: 0.24, alpha: 1)
        badge.position = CGPoint(x: 22, y: -26)
        badge.zPosition = 3
        container.addChild(badge)

        worldLayer.addChild(container)
        towerNodes[tower.id] = container

        // İnşa animasyonu (Builder pack kareleri) + ses
        SoundPlayer.shared.play("build")
        let buildFX = SKSpriteNode(texture: TextureBank.texture("build_0"))
        buildFX.size = CGSize(width: ts, height: ts)
        buildFX.zPosition = 4
        container.addChild(buildFX)
        // 44 karelik inşa sayfası 0.05s/kare ile fazla yavaş; her 3. kare (~0.75s)
        let frames = buildFrames()
        body.alpha = 0; weapon.alpha = 0
        buildFX.run(.sequence([
            .animate(with: frames, timePerFrame: 0.05),
            .removeFromParent(),
        ])) { body.run(.fadeIn(withDuration: 0.1)); weapon.run(.fadeIn(withDuration: 0.1)) }

        // Wisp yapı ruhu (V2): yalnız YENİ kulede — şantiyenin üstünde 3.5 sn
        // hafif sinüs salınımıyla süzülür, sönerek kaybolur (yükseltme/satışta yok).
        let wispFrames = TextureBank.loopFrames("wisp_glow")
        let wisp = SKSpriteNode(texture: wispFrames[0])
        wisp.size = CGSize(width: 44, height: 44)
        wisp.position = CGPoint(x: 0, y: 30)
        wisp.zPosition = 5
        container.addChild(wisp)
        wisp.run(.repeatForever(.animate(with: wispFrames, timePerFrame: 0.09)))
        let bobUp = SKAction.moveBy(x: 0, y: 6, duration: 0.7)
        bobUp.timingMode = .easeInEaseOut
        let bobDown = SKAction.moveBy(x: 0, y: -6, duration: 0.7)
        bobDown.timingMode = .easeInEaseOut
        wisp.run(.repeatForever(.sequence([bobUp, bobDown])))
        wisp.run(.sequence([.wait(forDuration: 3.5),
                            .fadeOut(withDuration: 0.5),
                            .removeFromParent()]))
        return container
    }

    /// İnşa animasyonu kareleri — 44 karelik sayfadan her 3. kare örneklenir.
    private func buildFrames() -> [SKTexture] {
        let n = TextureBank.frameCounts["build"] ?? 1
        return stride(from: 0, to: n, by: 3).map { TextureBank.texture("build_\($0)") }
    }

    /// Silahın gövde üstüne oturduğu y-ofseti (gövde yüksekliğine oranla; gözle ayarlanır).
    // kristal için S11'de ince ayar gerekebilir
    private func weaponHeight(for tower: Tower) -> CGFloat {
        let ts = CGFloat(map.tileSize)
        switch tower.level {
        case 1: return ts * 0.30
        case 2: return ts * 0.42
        default: return ts * 0.54
        }
    }

    // MARK: - Sürükle-bırak hayaleti

    /// SwiftUI .global noktasındaki kareyi yalnızca KURULABİLİRSE döndürür
    /// (çim + boş + altın yetiyor). Hem her karelik hayalet boyaması hem de
    /// bırakış anında GameSession.commitDrag son sözü buradan alır.
    func validDragTile(atViewPoint viewPoint: CGPoint, kind: TowerKind) -> GridPoint? {
        guard session.phase == .building || session.phase == .waveActive,
              let tile = dragTile(atViewPoint: viewPoint),
              map.isBuildable(tile),
              session.engine.tower(at: tile) == nil,
              session.gold >= session.engine.cost(of: kind) else { return nil }
        return tile
    }

    /// Harita karesi (uygunluk bakılmaz). SpriteView tam pencere (ZStack + ignoresSafeArea)
    /// olduğundan SwiftUI .global koordinatı SKView genişlik/yüksekliğiyle birebir;
    /// aspectFit harf kutusunu convertPoint(fromView:) çözer.
    /// macOS: SwiftUI y üstten, SKView'ın NSView'ı alttan sayar — dikey eksen çevrilir
    /// (iOS'ta UIKit de üstten saydığı için dönüşüm gerekmez).
    private func dragTile(atViewPoint viewPoint: CGPoint) -> GridPoint? {
        guard let view else { return nil }
        var p = viewPoint
        #if os(macOS)
        p.y = view.bounds.height - p.y
        #endif
        return map.tile(at: corePoint(convertPoint(fromView: p)))
    }

    /// Sürüklenen kartın hayalet kulesi + canlı menzil halkası: kare merkezine kenetlenir,
    /// uygun karede yeşil, uygunsuzda kırmızı; harita dışında gizlenir.
    private func syncDragGhost() {
        guard let kind = session.dragKind, let viewPoint = session.dragViewPoint,
              let tile = dragTile(atViewPoint: viewPoint) else {
            ghostBody.isHidden = true
            ghostRing.isHidden = true
            ghostKind = nil
            session.dragSnapTile = nil
            return
        }
        if ghostKind != kind {   // tür değişiminde bir kez: doku, boyut, halka yarıçapı
            ghostKind = kind
            let tex = TextureBank.texture(AssetName.towerBody(kind, level: 1))
            ghostBody.texture = tex
            ghostBody.size = towerBodySize(for: tex)
            let r = CGFloat(Balance.stats(for: kind, level: 1).range)
            ghostRing.path = CGPath(ellipseIn: CGRect(x: -r, y: -r, width: 2 * r, height: 2 * r),
                                    transform: nil)
        }
        let validTile = validDragTile(atViewPoint: viewPoint, kind: kind)
        session.dragSnapTile = validTile
        let tint: SKColor = validTile != nil
            ? SKColor(red: 0.3, green: 0.9, blue: 0.4, alpha: 1)
            : SKColor(red: 0.95, green: 0.3, blue: 0.25, alpha: 1)
        ghostBody.color = tint
        ghostBody.colorBlendFactor = 0.35
        ghostRing.strokeColor = tint.withAlphaComponent(0.8)
        ghostRing.fillColor = tint.withAlphaComponent(0.12)
        let center = scenePoint(map.center(of: tile))
        ghostBody.position = center
        ghostRing.position = center
        ghostBody.isHidden = false
        ghostRing.isHidden = false
    }

    private func syncOverlays() {
        // İnşa önizlemesi önceliklidir: inşa menüsü açıkken seçili kule olamaz
        // (handleTap ikisini karşılıklı sıfırlar) ama yarış durumuna karşı net dal sırası.
        if let tile = session.buildTile, let kind = session.previewKind {
            rangeCircle.isHidden = false
            // Önizleme için sahte anahtar: negatif tür indeksi — gerçek kule id'leriyle (>0)
            // çakışmaz; tür değişince yarıçap yeniden çizilir.
            let key = (id: -(TowerKind.allCases.firstIndex(of: kind)! + 1), level: 0)
            if rangeCircleKey == nil || rangeCircleKey! != key {
                rangeCircleKey = key
                let r = CGFloat(Balance.stats(for: kind, level: 1).range)
                rangeCircle.path = CGPath(ellipseIn: CGRect(x: -r, y: -r, width: 2 * r, height: 2 * r),
                                          transform: nil)
            }
            rangeCircle.position = scenePoint(map.center(of: tile))
        } else if let tower = session.selectedTower {
            rangeCircle.isHidden = false
            let key = (id: tower.id, level: tower.level)
            if rangeCircleKey == nil || rangeCircleKey! != key {
                rangeCircleKey = key
                let r = CGFloat(tower.stats.range)
                rangeCircle.path = CGPath(ellipseIn: CGRect(x: -r, y: -r, width: 2 * r, height: 2 * r),
                                          transform: nil)
            }
            rangeCircle.position = scenePoint(map.center(of: tower.tile))
        } else {
            rangeCircle.isHidden = true
            rangeCircleKey = nil
        }
        if let tile = session.buildTile {
            buildMarker.isHidden = false
            buildMarker.position = scenePoint(map.center(of: tile))
        } else {
            buildMarker.isHidden = true
        }
    }
}

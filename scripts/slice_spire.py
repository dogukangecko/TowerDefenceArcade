#!/usr/bin/env python3
# Spire sheet'lerini oyunun kullandığı tekil PNG karelerine keser. Deterministik;
# çıktılar repoya commit edilir. Kaynak: Vendor/spire (scripts/fetch_spire.sh).
# Kullanım: python3 scripts/slice_spire.py
import glob, os, sys
from PIL import Image, ImageChops

V = "Vendor/spire/"
OUT = "TowerDefense/Resources/SpriteAssets"
os.makedirs(OUT, exist_ok=True)
for old in glob.glob(os.path.join(OUT, "*.png")) + glob.glob(os.path.join(OUT, "*.json")):
    os.remove(old)  # deterministik çıktı: eski kareler kalmasın

def find(pat):
    hits = glob.glob(V + "**/" + pat, recursive=True)
    assert hits, "bulunamadı: " + pat
    return hits[0]

def save(img, name):
    img.save(os.path.join(OUT, name + ".png"))

def nonempty(img, threshold=8):
    a = img.getchannel("A")
    return a.getextrema()[1] > threshold

# ---- 1) Zemin: Grass Tileset (64px hücre haritası — spec'te doğrulandı) ----
TS = Image.open(find("Grass Tileset.png")).convert("RGBA")
def cell(c, r, w=1, h=1):
    return TS.crop((c * 64, r * 64, (c + w) * 64, (r + h) * 64))

# Hücre haritası ızgara dökümüyle yeniden doğrulandı (2026-06-11):
#   - Düz çim (1,1) DEĞİL (boş hücre): gerçek çim (2,1).
#   - Kapaklar artı şeklinin kollarından (1-3, 6-8): kol ucu kapalı, açık taraf
#     merkeze bakar — (1,7) sağa açık, (3,7) sola, (2,6) aşağı, (2,8) yukarı.
TILES = {
    "tile_grass": (2, 1), "tile_path_h": (6, 1), "tile_path_v": (5, 2),
    "tile_corner_rd": (5, 1), "tile_corner_ld": (7, 1),
    "tile_corner_ru": (5, 3), "tile_corner_lu": (7, 3),
    "tile_cap_r": (1, 7), "tile_cap_l": (3, 7), "tile_cap_d": (2, 6), "tile_cap_u": (2, 8),
    "decor_rocks_a": (13, 12), "decor_rocks_b": (14, 12),
    "decor_rocks_c": (13, 13), "decor_rocks_d": (14, 13),
    "decor_bush": (11, 9), "decor_tuft": (12, 9),
}
for name, (c, r) in TILES.items():
    save(cell(c, r), name)
for name, (c, r) in {"decor_tree_a": (13, 6), "decor_tree_b": (14, 6),
                     "decor_tree_c": (13, 9), "decor_tree_d": (14, 9)}.items():
    save(cell(c, r, 1, 2), name)

counts = {}

# ---- 1b) Su kareleri: "Animated water tiles.png" 4480x448 = 10 blok x 448px ----
# ÖLÇÜLDÜ (2026-06-12): 10 blok eşit doluluk (%67.3); her blok 7x7 hücrelik artı
# şekli, merkez hücre (192,192)-(256,256) %100 opak ve kareler arası piksel farkı
# >0 (gerçek animasyon). Merkez hücre = kesintisiz döşenebilir su karesi.
W = Image.open(find("Animated water tiles.png")).convert("RGBA")
assert W.size == (4480, 448), f"su sheet boyutu değişti: {W.size}"
for i in range(10):
    fr = W.crop((i * 448 + 192, 192, i * 448 + 256, 256))
    assert fr.getchannel("A").getextrema()[0] == 255, f"su karesi {i} tam opak değil"
    save(fr, f"water_{i}")
counts["water"] = 10

# ---- 1b2) Su kıyıları: aynı bloğun 7x7 artı şekli kıyı geçiş karelerini içerir.
# GÖRSEL DOĞRULAMA (2026-06-12, kontak tabaka + hücre alfa haritası): artı kolları
# tam opak, çim zemin kareye GÖMÜLÜ; su kıyı hücresine ~14-17px girer, arada kum
# şeridi. Ad = çimin olduğu yön(ler): edge_n = kuzeyi çim düz kenar; out_nw = çim
# K+B (dış köşe — su GD çeyreğinde); in_nw = çim yalnız KB cebinde (iç köşe, gerisi
# su). Aynı tipin blok içi kopyaları piksel-eş ÖLÇÜLDÜ (yalnız sol kol 2 hücresinde
# gömülü pırıltı farkı; kanonik hücreler eş olan çoğunluktan seçildi).
SHORE = {"edge_n": (3, 0), "edge_e": (4, 1), "edge_s": (3, 6), "edge_w": (2, 1),
         "out_nw": (2, 0), "out_ne": (4, 0), "out_sw": (2, 6), "out_se": (4, 6),
         "in_nw": (2, 2), "in_ne": (4, 2), "in_sw": (2, 4), "in_se": (4, 4)}
for t, (c, r) in SHORE.items():
    for i in range(10):
        fr = W.crop((i * 448 + c * 64, r * 64, i * 448 + (c + 1) * 64, (r + 1) * 64))
        assert fr.getchannel("A").getextrema()[0] == 255, f"kıyı {t}/{i} opak değil"
        save(fr, f"shore_{t}_{i}")
    counts[f"shore_{t}"] = 10

# ---- 1c) Köprüler (Grass Tileset): yatay köprü 2 satırlık grafik — satır 14
# güverte hücreleri (sol/orta/sağ, %100 opak), satır 13 üst korkuluk (üstteki
# su karesine taşan yarı saydam dekor). Dikey köprü sütun 11, satır 12-14;
# satır 15 BOŞ (alfa ölçümü — plandaki 12..15 tahmini 3 hücre çıktı; yan
# korkuluk şeritleri komşu sütunlarda %5'lik taşma, tek hücre kullanımında atlanır).
for i, c in enumerate((7, 8, 9)):
    save(cell(c, 14), f"bridge_h_{i}")
    save(cell(c, 13), f"bridge_h_top_{i}")
    assert nonempty(cell(c, 14)) and nonempty(cell(c, 13))
for i, r in enumerate((12, 13, 14)):
    save(cell(11, r), f"bridge_v_{i}")
    assert nonempty(cell(11, r))
assert not nonempty(cell(11, 15)), "dikey köprü 4. hücre dolu çıktı — düzeni yeniden ölç"

# ---- 1c2) Harabe/duvar dekorları (Grass Tileset). Koordinatlar GÖRSEL DOĞRULANDI
# (2026-06-12, kontak tabaka): taş sütunlar (6,10) ve (7,10) 1x3 hücre, taş sıra
# (8,9) 3x2, taş halka (8,11) 3x2 — satır 13'te yatay köprü grafiği başladığından
# halka 2 satıra sığıyor; bölgenin sağ kenarına dikey köprünün korkuluk direği
# (x 187-191) taşıyor, bbox öncesi 8px kırpılarak dışlanır. Hepsi şeffaf zeminli;
# alfa bbox kırpması. Beklenen boyutlar ölçümden sabitlendi (kaynak değişirse patlar).
RUINS = {"decor_ruin_a": (cell(6, 10, 1, 3), (54, 186)),   # taş sütun
         "decor_ruin_b": (cell(7, 10, 1, 3), (54, 186)),   # taş sütun 2
         "decor_ruin_c": (TS.crop((8 * 64, 11 * 64, 11 * 64 - 8, 13 * 64)), (122, 119)),  # halka
         "decor_ruin_d": (cell(8, 9, 3, 2), (172, 120))}   # taş sıra
for name, (img, expect) in sorted(RUINS.items()):
    bb = img.getbbox()
    assert bb, "boş dekor: " + name
    img = img.crop(bb)
    assert img.size == expect, f"{name}: beklenmedik boyut {img.size}"
    save(img, name)

# Kaya duvar parçaları (8,7) ve (9,7) — tekil yatay duvar segmentleri. Hücreler
# tam opak: çim zemin kareye gömülü ve düz çim hücresi (2,1) ile piksel-eş
# (ÖLÇÜLDÜ: fark maskesi yalnız duvar + yeşil gölge piksellerini bırakıyor).
# Çim fark maskesiyle şeffaflaştırılır; kesik uçlar "yıkık duvar" görünümü verir.
grass_ref = cell(2, 1).convert("RGB")
for name, (c, r), expect in (("decor_wall_a", (8, 7), (58, 37)),
                             ("decor_wall_b", (9, 7), (61, 37))):
    wcell = cell(c, r)
    dmask = ImageChops.difference(wcell.convert("RGB"), grass_ref).convert("L")
    wcell.putalpha(dmask.point(lambda x: 255 if x else 0))
    bb = wcell.getbbox()
    assert bb, "boş duvar: " + name
    wcell = wcell.crop(bb)
    assert wcell.size == expect, f"{name}: beklenmedik boyut {wcell.size}"
    save(wcell, name)

# ---- 2) Kuleler: gövde (3 seviye yan yana) + seviye silah/mermi/isabet sheet'leri ----
# Spire No -> oyun anahtarı (spec kadro tablosu + içerik dalgası rezervleri)
TOWERS = {1: "archer", 3: "catapult", 6: "bastion", 2: "crystal", 7: "shock", 5: "orb",
          4: "dart", 8: "solar"}

# Kare-olmayan şeritler için ÖLÇÜLMÜŞ kare genişlikleri (alfa sütun boşlukları +
# önizleme GIF kare sayılarıyla doğrulandı — tahmin değil):
#   Tower 01 okları: 3 ince dik kare (8/15/22 x 40)
#   Tower 06 cıvataları: 3-4 ince kare (6/8/10 geniş)
#   Tower 04 sv2 dikenleri: 90x12, GIF önizleme 6 kare -> kare 15x12
FRAME_W_OVERRIDES = {
    "Tower 01 - Level 01 - Projectile.png": 8,
    "Tower 01 - Level 02 - Projectile.png": 15,
    "Tower 01 - Level 03 - Projectile.png": 22,
    "Tower 04 - Level 02 - Projectile.png": 15,
    "Tower 06 - Level 01 - Projectile.png": 6,
    "Tower 06 - Level 02 - Projectile.png": 8,
    "Tower 06 - Level 03 - Projectile.png": 10,
}

# Tower 08 güneş patlaması sheet'leri DEV karelerle geliyor (256/320 px; GIF kare
# sayılarıyla doğrulandı: 1792/256=7, 3840/320=12, 5440/320=17). Diğer kulelerin
# mermi/isabet kareleri 8-64 px — ekran ölçeği tutarlı kalsın diye 64 px'e tam-kat
# küçültülür (256/4, 320/5; piksel-art için NEAREST, deterministik).
DOWNSCALE = {
    "Tower 08 - Level 01 - Projectile.png": 4,
    "Tower 08 - Level 02 - Projectile.png": 5,
    "Tower 08 - Level 03 - Projectile.png": 5,
}

def two_row_grid(sheet):
    # Tower 02 ve Tower 05 silah sheet'leri 2 satırlı kare ızgara (GIF önizleme
    # tek kristal/küre gösteriyor; orta yatay çizgi tamamen şeffaf). Tespit:
    # yükseklik çift, orta 2 piksel satırı boş ve genişlik yarı yüksekliğe bölünüyor.
    if sheet.height % 2:
        return False
    mid = sheet.height // 2
    if sheet.width % mid:
        return False
    band = sheet.crop((0, mid - 1, sheet.width, mid + 1))
    return band.getchannel("A").getextrema()[1] <= 8

def slice_grid(sheet, frame_w, frame_h, prefix, allow_gap=False):
    # Satır-öncelikli ızgara dilimleme. Bazı şeritler boş karede başlıyor (ör.
    # Tower 02 Impact: kare 0 tamamen şeffaf) ve 2 satırlı ızgaraların sonu boş;
    # baştaki/sondaki boş kareler kırpılır, kalanlar 0'dan yeniden numaralanır.
    # allow_gap: Tower 04 isabetinde orijinal animasyonun 1 karelik "yanıp sönme"
    # boşluğu var (görsel doğrulandı); boş iç kareler atlanarak sıkıştırılır.
    frames = []
    for r in range(sheet.height // frame_h):
        for c in range(sheet.width // frame_w):
            frames.append(sheet.crop((c * frame_w, r * frame_h,
                                      (c + 1) * frame_w, (r + 1) * frame_h)))
    flags = [nonempty(f) for f in frames]
    assert any(flags), "boş şerit: " + prefix
    lo, hi = flags.index(True), len(flags) - 1 - flags[::-1].index(True)
    if not allow_gap:
        assert all(flags[lo:hi + 1]), f"şeritte iç boşluk: {prefix} {flags}"
    n = 0
    for fr, ok in zip(frames[lo:hi + 1], flags[lo:hi + 1]):
        if not ok:
            continue
        save(fr, f"{prefix}_{n}")
        n += 1
    return n

for num, key in TOWERS.items():
    base_sheet = Image.open(find(f"Tower 0{num}.png")).convert("RGBA")
    bw = base_sheet.width // 3
    for lvl in range(1, 4):
        save(base_sheet.crop(((lvl - 1) * bw, 0, lvl * bw, base_sheet.height)),
             f"tower_{key}_{lvl}")
        for kind, pats in {
            "weapon": [f"Tower 0{num} - Level 0{lvl} - Weapon.png"],
            "proj":   [f"Tower 0{num} - Level 0{lvl} - Projectile.png",
                       f"Tower 0{num} - Level X - Projectile.png"],
            # Tower 08'in hiç Impact dosyası YOK (pakette doğrulandı); mermi
            # sheet'i zaten büyüyen güneş patlaması — isabet için de o kullanılır.
            "impact": [f"Tower 0{num} - Level 0{lvl} - Projectile - Impact.png",
                       f"Tower 0{num} - Weapon - Impact.png",
                       f"Tower 0{num} - Level X - Projectile - Impact.png",
                       f"Tower 0{num} - Level 0{lvl} - Projectile.png"],
        }.items():
            sheet, sheet_base = None, None
            for pat in pats:
                hits = glob.glob(V + "**/" + pat, recursive=True)
                hits = [h for h in hits if "Spritesheets" in h] or hits
                if hits:
                    sheet = Image.open(hits[0]).convert("RGBA")
                    sheet_base = os.path.basename(hits[0])
                    break
            assert sheet is not None, f"yok: tower {num} lvl {lvl} {kind}"
            if two_row_grid(sheet):
                # 2 satırlı silah sheet'i: üst satır bekleme döngüsü, alt satır
                # saldırı döngüsü (görsel olarak doğrulandı: kristal/küre şarj +
                # şimşek kareleri alt satırda). Oyun yalnızca saldırı döngüsünü
                # kullanıyor; alt satırı al.
                fh = fw = sheet.height // 2
                sheet = sheet.crop((0, fh, sheet.width, sheet.height))
            else:
                if sheet_base in DOWNSCALE:
                    f = DOWNSCALE[sheet_base]
                    sheet = sheet.resize((sheet.width // f, sheet.height // f),
                                         Image.NEAREST)
                fh = sheet.height
                fw = FRAME_W_OVERRIDES.get(sheet_base, fh)
            assert sheet.width % fw == 0, f"bölünemeyen şerit: {num}/{lvl}/{kind} {sheet.size}"
            counts[f"{key}_{lvl}_{kind}"] = slice_grid(
                sheet, fw, fh, f"{kind}_{key}_{lvl}",
                allow_gap=(num == 4 and kind == "impact"))

    # Kule portresi (inşa menüsü): gövde sv1 + silah sv1 kare 0 kompoziti
    base1 = Image.open(os.path.join(OUT, f"tower_{key}_1.png"))
    w0 = Image.open(os.path.join(OUT, f"weapon_{key}_1_0.png"))
    comp = Image.new("RGBA", (max(base1.width, w0.width), base1.height + w0.height // 3))
    comp.alpha_composite(base1, ((comp.width - base1.width) // 2, comp.height - base1.height))
    comp.alpha_composite(w0, ((comp.width - w0.width) // 2, 0))
    save(comp, f"portrait_{key}")

# ---- 3) Üs yapısı: Tower 08 gövde sv3 — Tower 08 artık oynanabilir (solar),
# üs kalesi ayrışsın diye deterministik HSV kaydırması: ton +0.55, doygunluk
# x0.6 -> mavi-gri kale. Alfa kanalı aynen korunur.
b8 = Image.open(find("Tower 08.png")).convert("RGBA")
bw8 = b8.width // 3
keep = b8.crop((2 * bw8, 0, 3 * bw8, b8.height))
alpha = keep.getchannel("A")
h, s, v = keep.convert("RGB").convert("HSV").split()
h = h.point(lambda x: (x + 140) % 256)      # 0.55 * 255 ≈ 140
s = s.point(lambda x: int(x * 0.6))
keep = Image.merge("HSV", (h, s, v)).convert("RGB").convert("RGBA")
keep.putalpha(alpha)
save(keep, "base_keep")

# ---- 4) Düşmanlar: yön bazlı 3x3 blok (satır 0-2 idle, 3-5 yürüme, 6-8 ölüm; d/u/y) ----
# Satır sırası görsel olarak doğrulandı (Firebug kontak tabakası): 0-2 idle,
# 3-5 yürüme, 6-8 ölüm (ölüm satırları parıltıyla dağılarak bitiyor); her blokta
# yön sırası aşağı/yukarı/yan. Firebug kareleri kare DEĞİL: 128x64 (GIF 1280x640).
ENEMIES = {"Leafbug": ("infantry", 64, 64), "Firebug": ("scout", 128, 64),
           "Magma Crab": ("armored", 64, 64), "Firewasp": ("boss", 96, 96),
           # İçerik dalgası rezervleri (2026-06-12): kare boyları ÖLÇÜLDÜ —
           # alfa sütun-koşu analizi: 64px sınırlarını kesen içerik yok (4 sheet).
           # Scorpion 512x576, Clampbeetle/Voidbutterfly 832x576, Locust 896x576;
           # hepsi 9 satır x 64, satır blokları idle/move/death (kontak tabakayla
           # doğrulandı: ölüm satırları soluklaşarak dağılıyor).
           "Scorpion": ("scorpion", 64, 64), "Clampbeetle": ("clampbeetle", 64, 64),
           "Voidbutterfly": ("voidbutterfly", 64, 64), "Flying Locust": ("locust", 64, 64)}
# Yan bakış normalizasyonu: Leafbug/Firebug/Firewasp SAĞA bakıyor, Magma Crab
# SOLA (kıskaçlar önde — down/up karelerinde doğrulandı). Crab yan kareleri
# yatay aynalanır ki tüm düşmanlar için tek kural geçerli olsun: yan = SAĞ.
# Yeni dörtlüde yan kare 0 görsel kontrolü: Scorpion ve Clampbeetle SOLA bakıyor
# (kıskaçlar solda), Voidbutterfly ve Flying Locust SAĞA (baş sağda).
FLIP_SIDE = {"Magma Crab", "Scorpion", "Clampbeetle"}
DIRS = ["down", "up", "side"]
ANIMS = ["idle", "walk", "death"]
for sheet_name, (key, fw, fh) in ENEMIES.items():
    sheet = Image.open(find(sheet_name + ".png")).convert("RGBA")
    assert sheet.height == fh * 9, f"{sheet_name}: beklenen 9 satır x {fh}px, gerçek {sheet.size}"
    assert sheet.width % fw == 0, f"{sheet_name}: genişlik {fw}'e bölünmüyor: {sheet.size}"
    for ai, anim in enumerate(ANIMS):
        for di, d in enumerate(DIRS):
            row = ai * 3 + di
            n = 0
            for i in range(sheet.width // fw):
                fr = sheet.crop((i * fw, row * fh, (i + 1) * fw, (row + 1) * fh))
                if not nonempty(fr):
                    break
                if d == "side" and sheet_name in FLIP_SIDE:
                    fr = fr.transpose(Image.FLIP_LEFT_RIGHT)
                save(fr, f"enemy_{key}_{anim}_{d}_{i}")
                n += 1
            assert n > 0, f"boş satır: {sheet_name} {anim} {d}"
            counts[f"{key}_{anim}_{d}"] = n

# ---- 5) İnşa animasyonu (Builder): 192px ızgara ----
con = Image.open(find("Tower Construction.png")).convert("RGBA")
assert con.width % 192 == 0 and con.height % 192 == 0, f"construction ızgara dışı: {con.size}"
ci = 0
for r in range(con.height // 192):
    for c in range(con.width // 192):
        fr = con.crop((c * 192, r * 192, (c + 1) * 192, (r + 1) * 192))
        if nonempty(fr):
            save(fr, f"build_{ci}")
            ci += 1
counts["build"] = ci

# ---- 5b) Yıkım animasyonu (Collapse): 3328x192 — 192'ye TAM bölünmüyor. Kare
# genişliği ÖLÇÜLDÜ (tahmin değil): alfa sütun profiliyle içerik blokları çıkarıldı;
# bölenler içinde yalnız 256 hiçbir içerik bloğunu kare sınırında kesmiyor
# (208x16 adayı 9 blokta sınır kesiyor — yanlış). 256x13, kare yüksekliği 192.
col = Image.open(find("Tower - Collapse.png")).convert("RGBA")
assert col.size == (3328, 192), f"collapse boyut değişti: {col.size}"
counts["collapse"] = slice_grid(col, 256, 192, "collapse")

# ---- 5c) Ambiyans efekt şeritleri: 32px düz şerit (Leaves Falling / Wind Blowing).
# Kare doluluğu ÖLÇÜLDÜ (2026-06-12): yaprağın son 2 karesi ve rüzgârın baş/son
# dönüşümlü kareleri TAMAMEN BOŞ — orijinal animasyon zamanlaması (yanıp sönme /
# sönümlenme) bozulmasın diye kareler kırpılmadan sırayla kaydedilir.
for fxname, key in (("Leaves Falling.png", "fx_leaf"), ("Wind Blowing.png", "fx_wind")):
    fx = Image.open(find(fxname)).convert("RGBA")
    assert fx.height == 32 and fx.width % 32 == 0, f"{fxname} ızgara dışı: {fx.size}"
    for i in range(fx.width // 32):
        save(fx.crop((i * 32, 0, (i + 1) * 32, 32)), f"{key}_{i}")
    counts[key] = fx.width // 32

# ---- 5d) Wisp yapıcı ruhu (Builder paketi): 9x6 ızgara 64px. Satır düzeni GÖRSEL
# DOĞRULANDI (2026-06-12, kontak tabaka): satır 0-2 bekleme (aşağı/yan/yukarı —
# yüz yalnız satır 0'da görünür), satır 3-5 parlama/büyü (sarı aura kareleri,
# aynı yön sırası). Oyun aşağı bakan kareleri kullanır: satır 0 = idle, satır 3 = glow.
wisp = Image.open(find("Wisp - Animations.png")).convert("RGBA")
assert wisp.size == (576, 384), f"wisp sheet boyutu değişti: {wisp.size}"
for key, row in (("wisp_idle", 0), ("wisp_glow", 3)):
    for i in range(9):
        fr = wisp.crop((i * 64, row * 64, (i + 1) * 64, (row + 1) * 64))
        assert nonempty(fr), f"{key} {i} boş"
        save(fr, f"{key}_{i}")
    counts[key] = 9

# ---- 6) Menü arka planı: 16x9 hücrelik sahne kompozisyonu (1024x576) ----
# Dilimlenmiş çıktılardan deterministik kompozisyon — sabit koordinatlar, rastgelelik yok.
def outimg(name):
    return Image.open(os.path.join(OUT, name + ".png")).convert("RGBA")

T = 64
menu = Image.new("RGBA", (16 * T, 9 * T))
grass = outimg("tile_grass")
for r in range(9):
    for c in range(16):
        menu.paste(grass, (c * T, r * T))

# S-kıvrımlı yol: soldan satır 3 → (5,3) ld köşesi (sol+aşağı açık) → aşağı →
# (5,6) ru (sağ+yukarı) → sağa → (11,6) lu (sol+yukarı) → yukarı →
# (11,2) rd (sağ+aşağı) → sağ kenardan çıkış. Köşe adı = yolun açık kenarları.
PATH_CELLS = (
    [(c, 3, "tile_path_h") for c in range(0, 5)] + [(5, 3, "tile_corner_ld")] +
    [(5, r, "tile_path_v") for r in range(4, 6)] + [(5, 6, "tile_corner_ru")] +
    [(c, 6, "tile_path_h") for c in range(6, 11)] + [(11, 6, "tile_corner_lu")] +
    [(11, r, "tile_path_v") for r in range(3, 6)] + [(11, 2, "tile_corner_rd")] +
    [(c, 2, "tile_path_h") for c in range(12, 16)]
)
for c, r, name in PATH_CELLS:
    menu.alpha_composite(outimg(name), (c * T, r * T))

def put(name, x, y):
    menu.alpha_composite(outimg(name), (x, y))

# Çizim sırası: dekor (arka) → yapılar → düşmanlar (ön). Dekor yoldan uzak çimde.
put("decor_tree_a", 768, 0)     # sağ üst ağaç kümesi (kale yanı)
put("decor_tree_b", 704, 0)
put("decor_bush", 256, 64)      # sol üst çalı
put("decor_tree_b", 832, 448)   # sağ alt küme
put("decor_tree_a", 896, 440)
put("decor_rocks_a", 384, 448)  # alt orta kayalar
put("decor_bush", 512, 256)     # orta çim adası
put("decor_rocks_a", 704, 480)
put("base_keep", 960, 0)             # yol çıkışındaki kale (sütun 15, satır 0-2)
put("portrait_archer", 112, 32)      # sol, giriş yolunun üstünde
put("portrait_catapult", 112, 416)   # sol alt
put("portrait_crystal", 832, 240)    # merkez-sağ
put("enemy_scout_walk_side_0", 128, 192)    # giriş yolunda (satır 3)
put("enemy_armored_walk_side_0", 512, 384)  # alt yolda (satır 6)
put("enemy_boss_walk_side_0", 752, 112)     # çıkış yolunda (satır 2)
save(menu, "menu_bg")

# ---- 7) Skin setleri: dilimlenmiş kule görsellerine deterministik HSV kaydırma ----
# Aseprite deneyinde doğrulanan tonlar (derece→0-255: 185°≈132, 320°≈227, 80°≈57).
# Kapsam: tower_/weapon_/portrait_ öneki (proj/impact orijinal kalır — mermi
# kimliği değişmesin). Çıktı: skin_<set>_<orijinal_ad>.png; alfa aynen korunur.
# Girdiler 2'li (hue, sat) ya da 3'lü (hue, sat, val) — val: V kanalına klemp'li
# ekleme (negatif = koyulaştırma; obsidyen: soğuk mor-siyah Kâbus ödülü).
SKINS = {"buz": (132, 13), "kor": (227, 26), "zehir": (57, -13),
         "obsidyen": (132, -60, -45)}  # (hue +0-255, sat delta[, val delta])

def reskin(img, hue, sat, val=0):
    alpha = img.getchannel("A")
    h, s, v = img.convert("RGB").convert("HSV").split()
    h = h.point(lambda x: (x + hue) % 256)
    s = s.point(lambda x: max(0, min(255, x + sat)))
    v = v.point(lambda x: max(0, min(255, x + val)))
    out = Image.merge("HSV", (h, s, v)).convert("RGB").convert("RGBA")
    out.putalpha(alpha)
    return out

skin_targets = sorted(
    f for f in os.listdir(OUT)
    if f.endswith(".png") and not f.startswith("skin_")
    and f.startswith(("tower_", "weapon_", "portrait_")))
for skin, (hue, sat, *rest) in sorted(SKINS.items()):
    for fname in skin_targets:
        src = Image.open(os.path.join(OUT, fname)).convert("RGBA")
        save(reskin(src, hue, sat, *rest), f"skin_{skin}_{os.path.splitext(fname)[0]}")
print("skin setleri:", len(SKINS), "x", len(skin_targets), "=",
      len(SKINS) * len(skin_targets), "png")

# ---- 7b) Ambient kelebekler: voidbutterfly yürüme (aşağı) karelerinin HSV
# varyantları — sahnede küçük ölçekli süs canlısı (reskin altyapısı yeniden
# kullanılır; kareler 64px düşman boyutu, sahne küçültecek). a: sıcak eflatun
# (ton +40°≈28, doygunluk +20), b: yeşil-turkuaz (ton +200°≈142, doygunluk +20)
# — kontak tabakada doğrulanan fiili renkler; iki varyant net ayrışıyor.
AMBIENT = {"a": (28, 20), "b": (142, 20)}
nbf = counts["voidbutterfly_walk_down"]
for var, (hue, sat) in sorted(AMBIENT.items()):
    for i in range(nbf):
        src = Image.open(os.path.join(OUT, f"enemy_voidbutterfly_walk_down_{i}.png")).convert("RGBA")
        save(reskin(src, hue, sat), f"ambient_butterfly_{var}_{i}")
    counts[f"ambient_butterfly_{var}"] = nbf

import json
json.dump(counts, open(os.path.join(OUT, "frame_counts.json"), "w"), indent=1, sort_keys=True)
print("DİLİMLEME TAMAM:", len(os.listdir(OUT)), "dosya;", "kare sayıları frame_counts.json'da")

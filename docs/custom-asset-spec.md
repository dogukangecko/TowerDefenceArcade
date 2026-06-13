# Özel Görsel Üretim Şartnamesi (AI Üreticiler İçin)

Oyunun mevcut sanat dili: **koyu-fantastik pixel art**, 64px ızgara mantığı, hafif 3/4
önden bakış (tepeden değil, yandan değil), şeffaf arka plan, dış çizgili (outlined)
gövdeler, doygun ama koyu palet (turuncu/amber vurgular, zümrüt yeşili çimen, taş grisi).
Referans: `TowerDefense/Resources/SpriteAssets/` içindeki mevcut sprite'lar ve uygulama ikonu.

## Altın kurallar (her üretim için)

1. **Şeffaf arka plan** (PNG, RGBA). Yere gölge ÇİZME — gölgeyi oyun kendisi ekliyor.
2. **Stil**: "pixel art" açıkça istenmeli; yumuşak boyama/airbrush stili oyunla çatışır.
3. **Üretim boyutu**: AI'dan istenen boyutun 8 katında üret (ör. 64×128 hedef → 512×1024
   iste); biz keskin (nearest) küçültmeyle orana indiririz. Oran birebir korunmalı.
4. **Çerçeveleme**: nesne tuvali doldursun, kenarlarda ~%5 pay; ALTI ortalanmış
   (kuleler tabanından oturur).
5. **Bakış açısı**: hafif yukarıdan 3/4 ön cephe (ikondaki kale gibi); saf tepeden veya
   saf yandan DEĞİL.
6. Tek dosyada TEK nesne (sprite sheet üretme — kareleri ayrı dosyalar halinde).

## Asset tipleri ve hedef ölçüler

| Tip | Hedef ölçü (oran) | AI üretim boyutu | Adlandırma | Not |
|---|---|---|---|---|
| Kule gövdesi | 64×128 (1:2) — büyük kuleler 64×192 (1:3) | 512×1024 / 512×1536 | `tower_<anahtar>_<seviye>.png` (seviye 1-3) | 3 seviye aynı kulenin büyüyen halleri; silah TAKILI DEĞİL (tepe platformu boş) |
| Kule silahı | 96×96 kare | 768×768 | `weapon_<anahtar>_<seviye>_0.png` | Namlu/silah YUKARI bakar; oyun döndürür. Tek kare yeter; atış animasyonu istersen `_1.._5` ek kareler |
| Mermi | ~8-24 px genişlik, uzunluk serbest (ör. 16×48) | 128×384 | `proj_<anahtar>_<seviye>_0.png` | Uç YUKARI bakar; ince-uzun ok/cıvata ya da küre |
| İsabet efekti | 64×64 kare × 4-6 kare | 512×512 her kare | `impact_<anahtar>_<seviye>_<i>.png` | Patlama/parçalanma dizisi; kare tutarlılığı zor — istersen tek karelik parlama da kabul |
| Zemin karosu | 64×64, KENARDAN KENARA dolu (şeffaflık YOK) | 512×512 | `tile_grass.png` vb. | Dikişsiz (seamless) olmalı — "tileable/seamless" iste |
| Dekor | 64×64 (taş/çalı) veya 64×128 (ağaç) | 512×512 / 512×1024 | `decor_<ad>.png` | Şeffaf zemin |
| Üs kalesi | 64×192 (1:3) | 512×1536 | `base_keep.png` | Oyuncunun savunduğu yapı |
| Kule portresi | 96×160 (3:5) | 768×1280 | `portrait_<anahtar>.png` | Mağaza/inşa menüsü kartı: gövde+silah birlikte, vitrin pozu |
| UI panel (9-slice) | 128×128, kenar süsü dış 24px şeritte | 1024×1024 | `ui_panel.png` vb. | Orta alan sade kalmalı (gerilir) |
| Menü arka planı | 1024×576 (16:9) | 2048×1152 | `menu_bg.png` | Tek parça sahne illüstrasyonu, şeffaflık yok |
| **Düşmanlar** | 64×64 kare; 3 yön × yürüme(8)+ölüm(6) kare | — | `enemy_<anahtar>_<anim>_<yön>_<i>.png` | ⚠️ EN ZOR: AI'lar kareler arası tutarlılığı zor korur. Önce kule/dekor/zeminle başla; düşmanlar Spire'da kalsın, hazır olunca deneriz |

Kule anahtarları: `archer, dart, catapult, bastion, crystal, shock, orb, solar`
(yenisini eklersek yeni anahtar açarız).

## Hazır AI prompt şablonları (İngilizce daha iyi sonuç verir)

**Kule gövdesi (örnek: archer seviye 3):**
> Pixel art sprite of a tall medieval stone archer tower, dark fantasy style, slight
> top-down 3/4 front view, empty flat platform on top (no weapon), dark outline,
> moody saturated colors with amber accents, transparent background, no ground
> shadow, centered, bottom-anchored, game asset, 512x1024

**Kule silahı:**
> Pixel art sprite of a wooden crossbow turret weapon viewed from slightly above,
> FACING STRAIGHT UP, dark fantasy style, dark outline, transparent background,
> single game asset sprite, 768x768

**Zemin karosu:**
> Seamless tileable pixel art grass texture tile, dark emerald green with small
> dots, top-down, dark fantasy game, fills entire square edge to edge, 512x512

**Portre:**
> Pixel art game shop card portrait of a complete medieval crystal tower with
> glowing purple crystal on top, dark fantasy, 3/4 front view, dark outline,
> transparent background, 768x1280

**Menü arka planı:**
> Pixel art dark fantasy tower defense landscape, stone towers along a winding
> dirt path through dark emerald grass, dramatic amber lighting, game menu
> background illustration, 16:9, 2048x1152

## Teslim ve entegrasyon

1. Üretilenleri `CustomAssets/` klasörüne yukarıdaki adlarla koy (klasörü açman yeter).
2. Bana haber ver: doğrulama + keskin küçültme + oyuna aktarma script'ini çalıştırırım
   (ölçü/oran/şeffaflık kontrolü; uymayanları raporlar, uyanları SpriteAssets'e basar).
3. Oyunu açıp birlikte bakarız; beğenmediğin geri alınır (eski Spire sprite'ı geri gelir —
   her şey git'te).

**Tavsiye sıra**: 1) bir kulenin 3 seviyesi + silahı + portresi (tek kule = stil testi)
→ 2) beğenirsen kalan kuleler → 3) zemin/dekor → 4) menü arka planı → 5) en son düşmanlar.

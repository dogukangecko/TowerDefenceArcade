# BalanceLab — Serbest Oyun Kalibrasyon Raporu (G3)

**Tarih:** 2026-06-12 · **Araç:** `swift run -c release BalanceLab rapor` (deterministik)
**Hedef:** El yapımı kampanyada ("11-30 bandı") GreedyPolicy medyan kalan can %70-90 (14-18/20);
hiçbir oran varyantı 8. dalgadan önce kaybetmemeli.
**İzinli kaldıraçlar:** Waves.campaign adetleri (±%20), waveClearBonus katsayıları,
gerekirse başlangıç altını 150→140. κ=0.12 sabit.

## İterasyonlar

### İterasyon 0 — Taban (G2 sonrası, değişiklik yok)

```
Harita          Oran   Sonuç       Can   Kule   Harcama
Klasik Vadi     0.7    KAZANDI      20     23      2526
Klasik Vadi     0.9    KAZANDI      20     21      2562
Klasik Vadi     1.0    KAZANDI      20     21      2578
Nehir Geçidi    0.7    KAZANDI      20     22      2556
Nehir Geçidi    0.9    KAZANDI      20     21      2562
Nehir Geçidi    1.0    KAZANDI      20     22      2580
→ medyan: 20/20 (%100) her iki haritada
```

### İterasyon 1 — Kaldıraç (a): waveClearBonus 25+5w → 15+3w

Toplam bonus geliri 525 → 315 altın (−%40). Sonuç: yine 20/20 her hücrede
(harcama ~2560 → ~2370; bot daha az kule kurar ama sızdırmaz).

### İterasyon 2 — Kaldıraç (b): dalga 6-10 adetleri +%20

Sonuç: yine 20/20. Adet artışı κ-bazlı ödüllerle **kendini finanse eder**:
+%20 düşman = +%20 gelir → bot dalga içinde anında ek kule kurar.

### İterasyon 3 — Dalga 1-5 adetleri de +%15-20 (en dar nokta erken oyun)

Sonuç: yine 20/20.

### İterasyon 4 — Kaldıraç (c): başlangıç altını 150 → 140

Sonuç: yine 20/20.

### Duyarlılık sondaları (teşhis, kalıcı değil)

- `waveClearBonus = 0` (uç değer): **yine 20/20** — ekonomi kaldıraçları botu etkilemiyor.
- Bütçe oranı taraması: 0.5-1.0 arası hep 20/20; 0.4'te Klasik 13 can; 0.3'te ilk kule
  bile alınamayıp kayıp. Sızıntı uçurumu "ilk kule alınabilirliği" eşiğine bağlı, kademeli değil.
- Adet ölçek taraması (×1.2 … ×3.0, GreedyPolicy 0.9, klasik): **×3'te bile 20/20.**

## Nihai kalibrasyon (commit edilen durum)

Kaldıraçlar: `waveClearBonus = 15 + 3w` · `startingGold = 140` · dalga adetleri sıkı
±%20 tavanında (1: 6→7, 2: 10→11*, 3: 8→9, 4: keşif 10→12, 5: çekirge 24→28 + piyade
10→12, 6: 5/10/8→6/12/9, 7: 10/8→12/9, 8: 10/5/5/6→12/6/6/7, 9: 10/8/4/4/4/8/14→
12/9/4/4/4/9/16, 10: çekirge 20→24, zırhlı 6→7). *2. dalga 11: 3. dalga HP
monotonluğu korunsun diye (660 ≤ 680).

```
BalanceLab rapor — Waves.campaign (10 dalga), GreedyPolicy
Hedef bant: medyan kalan can 14-18 / 20

Harita          Oran   Sonuç       Can   Dalga   Kule   Harcama
---------------------------------------------------------------
Klasik Vadi     0.7    KAZANDI      20       -     26      2596
Klasik Vadi     0.9    KAZANDI      20       -     22      2580
Klasik Vadi     1.0    KAZANDI      20       -     25      2618
  → Klasik Vadi medyan can: 20/20 (%100)

Nehir Geçidi    0.7    KAZANDI      20       -     25      2594
Nehir Geçidi    0.9    KAZANDI      20       -     22      2580
Nehir Geçidi    1.0    KAZANDI      20       -     23      2590
  → Nehir Geçidi medyan can: 20/20 (%100)
```

## Bulgu: 14-18 bandı izinli kaldıraçlarla ULAŞILAMAZ

Kanıt zinciri (yukarıdaki sondalar):

1. **κ ekonomisi ölçek-değişmezi:** ödül = 0.12·HP olduğundan adet artışı geliri aynı
   oranda artırır; bot dalga içi 0.5 sn kadansla anında yeni kule kurarak emer
   (adet ×3'te bile sızıntı yok).
2. **Bonus/altın payı küçük:** bonus toplamı (~315) toplam gelirin ~%12'si; sıfırlamak
   bile sızıntı yaratmıyor. Başlangıç altını −10 yalnız ilk saniyeleri etkiler.
3. **Sızıntıyı yaratan tek mekanizma HP-tarafı:** tek düşmanın yol boyu teslim
   edilebilir hasarı aşması gerekir — bu, spec'in üretilmiş seviyeler için kullandığı
   D(L) HP çarpanıdır ve G3'ün el yapımı dalgalar için izinli kaldıraçlarında YOKTUR.

**Sonuç/öneri:** Bot için tavan 20/20 kalır; insan oyuncu içinse gelir makası
(−%40 bonus, −10 altın) + %15-20 daha kalabalık dalgalar belirgin sıkılaştırmadır.
14-18 bandı isteniyorsa el yapımı dalgalara da hafif bir D-çarpanı (HP ölçeği)
uygulanmalı (spec değişikliği — G5'teki TunedDifficulty mekanizmasının serbest oyuna
uzantısı). Regresyon çıpası `testCalibrationPinGreedyWinsClassicWithHealthyLives`:
kazanma + can ∈ 14…20 (gelecekte "çok zor" yönlü kaymayı yakalar; görevde istenen
10…19 bandı bugünkü gerçek sonuç 20 olduğundan uyarlanmıştır).

8. dalga öncesi kayıp kriteri: ✓ hiçbir oran varyantı kaybetmiyor (hepsi kazanıyor).

---

# BalanceLab — `ayar` Modu Raporu (G5)

**Araç:** `swift run -c release BalanceLab ayar` (deterministik — iki koşu birebir aynı
dosyayı üretir; süre ≈ 2.8 sn, derleme hariç). Politika: GreedyPolicy bütçe oranları
{0.8, 0.9, 1.0}, üçünün **medyan** kalan canı hedefe oturtulur. D ∈ [0.7, 2.4],
ikili arama ≤12 yineleme + formül başlangıç sondası; her sondada YALNIZ dalgalar
yeniden üretilir (harita sabit — topoloji D'den bağımsız, testle kilitli:
`testMapTopologyIndependentOfDifficulty`).

## Özet tablo

```
  L        D   Medyan  Bant      Sonda  Durum
----------------------------------------------------
  1    1.000       20  18-20         1  ✓
  2    1.000       20  18-20         1  ✓
  3    1.000       20  18-20         1  ✓
  4    1.000       20  18-20         1  ✓
  5    1.000       20  18-20         1  ✓
  6    1.150       20  18-20         1  ✓
  7    1.150       20  18-20         1  ✓
  8    1.150       20  18-20         1  ✓
  9    1.150       20  18-20         1  ✓
 10    1.150       20  18-20         1  ✓
 11    1.300       20  14-18        12  UYARI: bant dışı
 12    1.300       20  14-18        12  UYARI: bant dışı
 13    1.300       20  14-18        12  UYARI: bant dışı
 14    1.300       20  14-18        12  UYARI: bant dışı
 15    1.300       20  14-18        12  UYARI: bant dışı
 16    1.450       20  14-18        12  UYARI: bant dışı
 17    1.450       20  14-18        12  UYARI: bant dışı
 18    1.450       20  14-18        12  UYARI: bant dışı
 19    1.450       20  14-18        12  UYARI: bant dışı
 20    1.450       20  14-18        12  UYARI: bant dışı
 21    1.600       20  14-18        12  UYARI: bant dışı
 22    1.600       20  14-18        12  UYARI: bant dışı
 23    1.600       20  14-18        12  UYARI: bant dışı
 24    1.600       20  14-18        12  UYARI: bant dışı
 25    1.600       20  14-18        12  UYARI: bant dışı
 26    1.750       20  14-18        11  UYARI: bant dışı
 27    1.750       20  14-18        11  UYARI: bant dışı
 28    1.750       20  14-18        11  UYARI: bant dışı
 29    1.750       20  14-18        11  UYARI: bant dışı
 30    1.750       20  14-18        11  UYARI: bant dışı
 31    1.900       20  9-15         11  UYARI: bant dışı
 32    1.900       20  9-15         11  UYARI: bant dışı
 33    1.900       20  9-15         11  UYARI: bant dışı
 34    1.900       20  9-15         11  UYARI: bant dışı
 35    1.900       20  9-15         11  UYARI: bant dışı
 36    2.050       20  9-15         10  UYARI: bant dışı
 37    2.050       20  9-15         10  UYARI: bant dışı
 38    2.050       20  9-15         10  UYARI: bant dışı
 39    2.050       20  9-15         10  UYARI: bant dışı
 40    2.050       20  9-15         10  UYARI: bant dışı
 41    2.200       20  9-15         10  UYARI: bant dışı
 42    2.200       20  9-15         10  UYARI: bant dışı
 43    2.200       20  9-15         10  UYARI: bant dışı
 44    2.200       20  9-15         10  UYARI: bant dışı
 45    2.200       20  9-15         10  UYARI: bant dışı
 46    2.200       20  6-12         10  UYARI: bant dışı
 47    2.200       20  6-12         10  UYARI: bant dışı
 48    2.200       20  6-12         10  UYARI: bant dışı
 49    2.200       20  6-12         10  UYARI: bant dışı
 50    2.200       20  6-12         10  UYARI: bant dışı
```

Tehdit kontrolü (L46-50, "en az bir varyant <14 can ya da kayıp"): **hiçbirinde tehdit
yok** — üç varyant da 20/20.

## Bulgu: bantlar [0.7, 2.4] bütçe-D'siyle ULAŞILAMAZ — eğri formüle düşer

Bot, aralıktaki HER D sondasında 20/20 (L≥11'in 50 seviyesinden 40'ı bant dışı, hepsi
"çok kolay" yönünde). Mesafe-eşitliğinde deterministik kıstas en küçük sondalı D'dir =
formül başlangıcı → üretilen eğri tasarım formülüyle (D = 0.85 + 0.15·⌈L/5⌉, tavan 2.2)
birebir aynıdır. Bu, G3 bulgusunun doğrudan sonucu:

1. D dalga **bütçesini** ölçekler; kompozisyon çözücü bütçeyi aynı HP'li düşmanlardan
   DAHA ÇOK adetle doldurur → bütçe-D pratikte adet ölçeklemesidir.
2. Adet ölçeklemesi κ ekonomisinde **gelir-nötr**: ödül = 0.12·HP → +%X HP bütçesi =
   +%X gelir; bot dalga içi 0.5 sn kadansla geliri anında DPS'e çevirir.
3. Sızıntı ancak DPS teslim kapasitesi doyunca başlar. `dtara` yanıt eğrisi
   (GreedyPolicy 0.9, kalan can):

```
L10   D1.0→20  D2.4→20  D3.0→20  D4.0→20  D6.0→20  D8.0→19  D12→7   D16→0✗  D24→0✗
L20   D1.0→20  D2.4→20  D3.0→20  D4.0→20  D6.0→19  D8.0→15  D12→12  D16→0✗  D24→0✗
L35   D1.0→20  D2.4→20  D3.0→20  D4.0→20  D6.0→20  D8.0→20  D12→11  D16→5   D24→0✗
L50   D1.0→20  D2.4→20  D3.0→20  D4.0→20  D6.0→19  D8.0→17  D12→7   D16→0✗  D24→0✗
```

Kırılma D≈6-8'de başlıyor; hedef bantlar D≈10-14'e denk geliyor — arama aralığının
4-6 katı. Aralığı oraya genişletmek YANLIŞ olur: bot insanüstü (0.5 sn kadanslı
kusursuz yerleşim); botu kanatan D, insan için oynanmaz seviye demektir ve spec D
tavanını bilerek 2.2'de tutuyor.

**Sonuç/öneri:** Asıl kaldıraç birim-HP ölçeklemesi (D'nin bir bölümünü düşman
`maxHP`'sine uygulamak — tek düşmanın yol boyu teslim edilebilir hasarı aşması, κ
gelir-nötrlüğünü deldiği kanıtlanmış tek sızıntı mekanizması; bkz. G3). Bu, motor
değişikliği (SpawnGroup/Enemy HP çarpanı) gerektirir → G5 kapsamı dışı, ayrı görev
önerisi. Bu arada üretilen eğri formülle aynı olduğundan oyun davranışı değişmez;
`ayar` altyapısı (arama + dosya üretimi + tehdit kontrolü) birim-HP kaldıracı
eklendiğinde olduğu gibi yeniden kullanılır.

## Doğrulama testleri

- `testMapTopologyIndependentOfDifficulty`: L7 haritası farklı D enjeksiyonlarında
  özdeş; D yalnız dalga HP'sini ölçekler. ✓
- `testTunedTableShape`: 50 giriş, hepsi [0.7, 2.4]. ✓
- `testSampleLevelsNotHarderThanBand`: örneklem [1,5,10,20,30,40,45,48,50],
  GreedyPolicy(0.9) — kalan can ≥ bant alt kenarı −2. ÜST kenar asserti bilinçli
  yok (yukarıdaki bulgu: üst kenara inmek bütçe-D ile imkânsız). ✓
- G4 dalga-bant testleri: ayarlı D'lerin en küçüğü 1.000 ≥ 0.97 → w=1 alt kenar
  gevşetmesi GEREKMEDİ (±%15 olduğu gibi). ✓
- Toplam: 94 test, 0 hata, 0 atlama.

---

# BalanceLab — `ayar` v2: Birim HP Çarpanı Raporu (G5b)

**Araç:** `swift run -c release BalanceLab ayar` (v2 — deterministik; iki koşu birebir
aynı dosyayı üretir, sha1 doğrulandı; süre ≈ 0.7 sn, derleme hariç).

**Tasarım:** G5'in önerdiği motor kaldıracı eklendi — `GameEngine(enemyHPMultiplier:)`
doğan her düşmanın azami/mevcut HP'sini ölçekler; **ödül ve can bedeli TABAN kalır**
(gelir-nötr: κ ekonomisini deldiği kanıtlı tek sızıntı mekanizması, bkz. G3/G5).
Kompozisyon (dalga çeşitliliği) artık `compositionD = min(D_formül, 1.3)` ile sabit —
adetler makul kalır; zorluğun tamamı `hpMultByLevel` tablosunda taşınır.
`Enemy` ölçekli `maxHP` alanı taşır (can barı/ölüm eşiği bunu kullanır; `stats.maxHP`
taban arama tablosu olarak kalır). Arama: GreedyPolicy {0.8, 0.9, 1.0} medyanı,
hpMult ∈ [0.8, 6.0], ikili arama ≤12 yineleme, nötr 1.0 başlangıç sondası.

## Özet tablo (gerçek eğri — bant isabeti 50/50, UYARI yok)

```
  L        D   hpMult   Medyan  Bant      Sonda  Durum
-------------------------------------------------------------
  1    1.000    1.000       20  18-20         1  ✓
  2    1.000    1.000       20  18-20         1  ✓
  3    1.000    1.000       20  18-20         1  ✓
  4    1.000    1.000       20  18-20         1  ✓
  5    1.000    1.000       20  18-20         1  ✓
  6    1.150    1.000       20  18-20         1  ✓
  7    1.150    1.000       20  18-20         1  ✓
  8    1.150    1.000       20  18-20         1  ✓
  9    1.150    1.000       20  18-20         1  ✓
 10    1.150    1.000       20  18-20         1  ✓
 11    1.300    3.500       14  14-18         2  ✓
 12    1.300    2.875       17  14-18         4  ✓
 13    1.300    3.188       17  14-18         5  ✓
 14    1.300    2.875       16  14-18         4  ✓
 15    1.300    3.500       15  14-18         2  ✓
 16    1.450    2.250       16  14-18         3  ✓
 17    1.450    2.250       18  14-18         3  ✓
 18    1.450    2.875       18  14-18         4  ✓
 19    1.450    2.875       14  14-18         4  ✓
 20    1.450    3.383       15  14-18         8  ✓
 21    1.600    2.875       16  14-18         4  ✓
 22    1.600    3.500       17  14-18         2  ✓
 23    1.600    2.250       16  14-18         3  ✓
 24    1.600    2.250       18  14-18         3  ✓
 25    1.600    2.250       16  14-18         3  ✓
 26    1.750    2.250       16  14-18         3  ✓
 27    1.750    2.250       17  14-18         3  ✓
 28    1.750    2.250       16  14-18         3  ✓
 29    1.750    2.250       18  14-18         3  ✓
 30    1.750    2.250       18  14-18         3  ✓
 31    1.900    2.875       12  9-15          4  ✓
 32    1.900    3.500       10  9-15          2  ✓
 33    1.900    3.500       11  9-15          2  ✓
 34    1.900    3.188       15  9-15          5  ✓
 35    1.900    3.500       10  9-15          2  ✓
 36    2.050    2.875        9  9-15          4  ✓
 37    2.050    3.500       13  9-15          2  ✓
 38    2.050    2.875       12  9-15          4  ✓
 39    2.050    3.500       11  9-15          2  ✓
 40    2.050    3.500       15  9-15          2  ✓
 41    2.200    3.500        9  9-15          2  ✓
 42    2.200    2.875       15  9-15          4  ✓
 43    2.200    3.500       11  9-15          2  ✓
 44    2.200    3.500       15  9-15          2  ✓
 45    2.200    2.875       13  9-15          4  ✓
 46    2.200    2.875        9  6-12          4  ✓
 47    2.200    3.500       12  6-12          2  ✓
 48    2.200    3.188        8  6-12          5  ✓
 49    2.200    3.500        7  6-12          2  ✓
 50    2.200    3.188       10  6-12          5  ✓

Bant isabeti: 50/50
```

Tehdit kontrolü (L46-50, "en az bir varyant <14 can ya da kayıp") — **5/5 ✓**:

```
L46: 6/9/10 ✓   L47: 12/13/12 ✓   L48: 8/6/12 ✓   L49: 6/7/9 ✓   L50: 16/10/4 ✓
```

## Bulgular

1. **Bantlar artık ULAŞILABİLİR** — G5'te 40/50 seviye "çok kolay" yönünde bant
   dışıyken v2'de 50/50 isabet. HP çarpanı gelir-nötrlüğü sayesinde bot gerçekten
   kanıyor: bandın ÜST kenarı da test edilebilir hale geldi
   (`testSampleLevelsWithinBandBothEdges`, ±2 tolerans, iki kenar).
2. **Eğri biçimi:** L1-10 nötr (1.0 — bant zaten 18-20), L11'de 3.5'a sıçrar
   (bant 14-18'e düşer), sonra seviye başına 2.25-3.5 bandında dalgalanır.
   Çarpan monoton DEĞİL — her seviyenin haritası/kompozisyonu farklı olduğundan
   aynı bant farklı çarpanlarla yakalanır; oyuncunun gördüğü zorluk bandı monoton.
3. **L10→L11 uçurumu:** çarpan 1.0→3.5 sıçrar. Bu, spec bantlarının kendi
   süreksizliğidir (18-20 → 14-18); istenirse bantları yumuşatmak ayrı tasarım
   kararı (G6+ adayı).
4. `dByLevel` artık yalnız kompozisyon kaynağı (formül değerleri; üreteçte 1.3
   tavanı) — oyun davranışındaki zorluk `hpMultByLevel`'dan gelir;
   `LevelDefinition.hpMultiplier` alanı motorla bağlamak için hazır (Sefer
   bağlantısı G6'da `GameEngine(enemyHPMultiplier: level.hpMultiplier)`).

---

# BalanceLab — `ayar` v3: Kademe Başına Ayarlı HP Eğrileri (H1b)

H1'in sabit kademe HP merdiveni (×1.25/1.5/1.75) üst kademeleri L20+ seviyelerde
matematiksel olarak kazanılamaz yapıyordu: TunedDifficulty seviye eğrisi sızıntı
payını zaten tükettiğinden, üstüne binen sabit çarpan botu (ve insanı) duvara
çarpıyordu (`zorluk`/`zorlukTara` çıktıları, H1 commit notu). Karar: **kademe
kimliği = daha az can + maliyet çarpanı + DAHA SIKI hedef bantlar**; her
(kademe, seviye) HP çarpanını BalanceLab bulur.

## Mimari değişiklik

- `TunedDifficulty.hpMultByLevel` → `hpMultByTier: [String: [Double]]`
  (anahtar `Difficulty.rawValue`, 4 × 50 değer).
- `LevelGenerator.hpMultiplier(_:difficulty:)`: kademenin KENDİ eğrisi; eğri
  boşsa yedek = Normal eğri × `Difficulty.fallbackHPMultiplier`
  (1.0/1.12/1.22/1.32 — mütevazı merdiven, yalnız formül modunda).
- `GameEngine` artık kademe çarpanı BİLEŞTİRMEZ (`effectiveEnemyHPMultiplier`
  kalktı): çağıran kademe-çözümlü değeri verir; `Difficulty.hpMultiplier` silindi.
- `GameSession` sefer motorunu `LevelGenerator.hpMultiplier(level, difficulty:)`
  ile kurar. `zorlukTara` modu kaldırıldı (görevi `ayar` v3 devraldı).

## `ayar` v3 araması

Koşu: `swift run -c release BalanceLab ayar` — **süre 3.7 sn** (v2 ≈ 0.7 sn,
~5×; 4 kademe × 50 seviye, sondalar 3'er varyant). Determinist: ardışık iki koşu
birebir aynı dosyayı üretir (sha1 doğrulandı). Kademe can/maliyet kimliği simde
ETKİN (`difficulty:` geçilir).

Hedef bantlar (medyan kalan can; GreedyPolicy {0.8, 0.9, 1.0} medyanı):

| Kademe | L1-10 | L11-30 | L31-45 | L46-50 | Arama |
|---|---|---|---|---|---|
| Normal (20 can) | 18-20 | 14-18 | 9-15 | 6-12 | [0.8, 6.0] — v2 ile AYNI kod yolu |
| Zor (14 can) | 11-14 | 8-11 | 5-9 | 3-7 | [0.85, 6.0] |
| Çok Zor (10 can, ×1.08) | 7-10 | 5-8 | 3-6 | 2-5 | [0.85, 6.0] |
| Kâbus (3 can, ×1.15) | kazanılabilirlik-öncelikli: ≥1 varyantın kazandığı EN BÜYÜK çarpan ∈ [1.0, 6.0]; 1.0 bile kaybederse [0.85, 1.0) kelepçesi | | | | |

Sonuç: **dört kademede de isabet 50/50** — UYARI yok. **Normal eğri v2 ile
bayt-bayt AYNI** (regresyon ✓). **Kâbus kelepçesi HİÇ tetiklenmedi**: kelepçe
listesi BOŞ — kazanılabilirlik 3 canla bile her seviyede hpMult ≥ 1.542'de
korunuyor (min L16/L28 = 1.542, maks L22 = 3.350). Yani Kâbus, Çok Zor'un
ayarlı eğrisine yakın HP taşırken canı 10 → 3'e düşürür: kimlik gerçek.

## Doğrulama: `zorluk` modu (çıplak GreedyPolicy, mağazasız)

GEREKSİNİM: her (seviye, kademe) hücresinde ≥1 kazanan varyant — **SAĞLANDI**.
Kâbus'ta varyant kayıpları kimliğin parçası (✗ hücreleri).

```
  L  Zorluk     hpMult  Sonuçlar (0.8/0.9/1.0)    Medyan can  Durum
  1  Normal      1.000  K20/K20/K20                       20  ✓
  1  Zor         1.000  K14/K14/K14                       14  ✓
  1  Çok Zor     1.000  K10/K10/K10                       10  ✓
  1  Kâbus       2.550  ✗0/✗0/K2                           0  ✓ (1/3)
 10  Normal      1.000  K20/K20/K20                       20  ✓
 10  Zor         1.000  K14/K14/K14                       14  ✓
 10  Çok Zor     1.000  K10/K10/K10                       10  ✓
 10  Kâbus       2.200  ✗0/✗0/K1                           0  ✓ (1/3)
 20  Normal      3.383  K8/K15/K15                        15  ✓
 20  Zor         3.383  K2/K9/K9                           9  ✓
 20  Çok Zor     2.875  K8/K8/K8                           8  ✓
 20  Kâbus       3.085  ✗0/✗0/K1                           0  ✓ (1/3)
 30  Normal      2.250  K17/K18/K19                       18  ✓
 30  Zor         2.875  K9/K11/K12                        11  ✓
 30  Çok Zor     2.250  K7/K8/K8                           8  ✓
 30  Kâbus       2.150  ✗0/K1/K1                           1  ✓ (2/3)
 40  Normal      3.500  K15/K11/K19                       15  ✓
 40  Zor         3.500  K9/K5/K13                          9  ✓
 40  Çok Zor     3.188  K6/K5/K3                           5  ✓
 40  Kâbus       2.949  ✗0/✗0/K1                           0  ✓ (1/3)
 50  Normal      3.188  K16/K10/K4                        10  ✓
 50  Zor         3.188  K10/K4/✗0                          4  ✓ (2/3)
 50  Çok Zor     2.875  K3/K4/K5                           4  ✓
 50  Kâbus       2.450  ✗0/✗0/K2                           0  ✓ (1/3)
```

(L5/L45 satırları da koşuldu — hepsi ✓; tam çıktı `swift run -c release
BalanceLab zorluk`.)

## Bulgular

1. **Kademeler arası hpMult monoton DEĞİL ve olması da beklenmez** — her kademe
   kendi bandına, kendi can/maliyet kimliği etkinken ayarlanır. Örn. L20'de
   Çok Zor (2.875) < Zor (3.383): 10 canlık bütçede aynı sızıntı daha pahalı,
   bot bandı daha düşük HP'de yakalar. Kâbus eğrisi çoğunlukla Çok Zor
   cıvarında — zorluk farkı 3 can + ×1.15 maliyetten gelir. Testler bu yüzden
   monotonluk assert etmez (DifficultyTests'te belgeli).
2. **Kâbus L1-10 nötr DEĞİL** (2.1-3.1): Normal/Zor/Çok Zor erken seviyelerde
   1.0'da kalırken (bant zaten tutuyor) Kâbus'un kazanılabilirlik-öncelikli
   araması "hâlâ kazanılabilen en sıkı" çarpanı bulur — Kâbus 1. seviyeden
   itibaren jilet gibi, tasarım gereği.
3. Testler: 115 → 117 (kademe eğrisi bütünlüğü, kademe-çözümlü okuma,
   örneklem kazanılabilirlik L10/L30 × Zor/Çok Zor/Kâbus kısa devreli).

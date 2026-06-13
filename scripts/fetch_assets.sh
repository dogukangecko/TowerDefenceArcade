#!/bin/bash
# Kenney CC0 UI ve ses paketlerini indirir, kullanılan dosyaları projeye kopyalar.
# Spire sprite paketleri için: ./scripts/fetch_spire.sh
set -euo pipefail
cd "$(dirname "$0")/.."

VENDOR=Vendor
SOUNDS=TowerDefense/Resources/Sounds
mkdir -p "$VENDOR" "$SOUNDS"

# URL'ler 2026-06-10'da doğrulandı
fetch() { [ -f "$2" ] || curl -sL --fail -A "Mozilla/5.0" -o "$2" "$1"; }

# ---- Ses ve UI paketleri ----
UIADV_URL="https://kenney.nl/media/pages/assets/ui-pack-adventure/9a877376bc-1723597274/kenney_ui-pack-adventure.zip"
RPGAUDIO_URL="https://kenney.nl/media/pages/assets/rpg-audio/8e99002d76-1677590336/kenney_rpg-audio.zip"
IMPACT_URL="https://kenney.nl/media/pages/assets/impact-sounds/87b4ddecda-1677589768/kenney_impact-sounds.zip"

fetch "$UIADV_URL"    "$VENDOR/uiadv.zip"
fetch "$RPGAUDIO_URL" "$VENDOR/rpgaudio.zip"
fetch "$IMPACT_URL"   "$VENDOR/impact.zip"
[ -d "$VENDOR/uiadv" ]    || unzip -q -o "$VENDOR/uiadv.zip"    -d "$VENDOR/uiadv"
[ -d "$VENDOR/rpgaudio" ] || unzip -q -o "$VENDOR/rpgaudio.zip" -d "$VENDOR/rpgaudio"
[ -d "$VENDOR/impact" ]   || unzip -q -o "$VENDOR/impact.zip"   -d "$VENDOR/impact"

# UI 9-slice PNG'leri (UI Pack Adventure, 2x "Double" varyantı)
UIDIR=TowerDefense/Resources/UI
mkdir -p "$UIDIR"
UA="$VENDOR/uiadv/PNG/Double"   # 2x çözünürlük varyantı
cp "$UA/panel_brown.png" "$UIDIR/ui_panel.png"
cp "$UA/panel_brown_dark.png" "$UIDIR/ui_panel_dark.png"
cp "$UA/panel_border_brown.png" "$UIDIR/ui_frame.png"
cp "$UA/button_brown.png" "$UIDIR/ui_button.png"
cp "$UA/button_red.png" "$UIDIR/ui_button_danger.png"
cp "$UA/button_grey.png" "$UIDIR/ui_button_flat.png"
cp "$UA/banner_hanging.png" "$UIDIR/ui_banner.png"

# ---- Müzik (RandomMind, CC0, OpenGameArt — AVAudioPlayer MP3'ü doğrudan çalar) ----
# Menü: "Medieval: The Old Tower Inn" — https://opengameart.org/content/medieval-the-old-tower-inn
# Oyun: "Medieval: Market Day" (loop)  — https://opengameart.org/content/medieval-market-day
fetch "https://opengameart.org/sites/default/files/The_Old_Tower_Inn.mp3" "$SOUNDS/music_menu.mp3"
fetch "https://opengameart.org/sites/default/files/Loop_Market_Day_0.mp3" "$SOUNDS/music_game.mp3"

# ---- V3: Ambiyans + savaş müziği (hepsi CC0, OpenGameArt) ----
# amb_forest:   "Forest Ambience"      — https://opengameart.org/content/forest-ambience
# amb_crickets: "Crickets Ambience"    — https://opengameart.org/content/crickets-ambience
# music_battle: "Battle Theme"         — https://opengameart.org/sites/default/files/battle_8.mp3
# amb_dungeon / amb_swamp OGG kaynaklı → aşağıda WAV'a açılıp m4a'ya sıkıştırılır
# (ham WAV 18-36MB; AAC ~1-2MB ve AVAudioPlayer doğal çalar — depo/bundle şişmesin).
fetch "https://opengameart.org/sites/default/files/Forest_Ambience.mp3" "$SOUNDS/amb_forest.mp3"
fetch "https://opengameart.org/sites/default/files/crickets_1.mp3"      "$SOUNDS/amb_crickets.mp3"
fetch "https://opengameart.org/sites/default/files/battle_8.mp3"        "$SOUNDS/music_battle.mp3"
fetch "https://opengameart.org/sites/default/files/dungeon_ambient_1_0.ogg" "$VENDOR/dungeon_ambient.ogg"
fetch "https://opengameart.org/sites/default/files/swamp.ogg"               "$VENDOR/swamp.ogg"

# OGG -> WAV (SpriteKit/AVAudioPlayer OGG desteklemez)
rm -f "$SOUNDS/shot_mg.wav" "$SOUNDS/shot_sniper.wav" "$SOUNDS/explosion.wav"
python3 -c "import soundfile" 2>/dev/null \
  || python3 -m pip install --quiet --user soundfile \
  || { echo "HATA: soundfile kurulamadı. Elle kurun: pip3 install soundfile" >&2; exit 1; }
python3 - <<'EOF'
import soundfile as sf
pairs = [
    ("Vendor/rpgaudio/Audio/knifeSlice2.ogg",            "TowerDefense/Resources/Sounds/shot_archer.wav"),
    ("Vendor/impact/Audio/impactPlank_medium_000.ogg",   "TowerDefense/Resources/Sounds/shot_ballista.wav"),
    ("Vendor/rpgaudio/Audio/creak2.ogg",                 "TowerDefense/Resources/Sounds/shot_catapult.wav"),
    ("Vendor/impact/Audio/impactMining_001.ogg",         "TowerDefense/Resources/Sounds/impact_boulder.wav"),
    ("Vendor/impact/Audio/impactPunch_medium_000.ogg",   "TowerDefense/Resources/Sounds/enemy_death.wav"),
    ("Vendor/impact/Audio/impactBell_heavy_000.ogg",     "TowerDefense/Resources/Sounds/leak.wav"),
    ("Vendor/impact/Audio/impactWood_heavy_000.ogg",     "TowerDefense/Resources/Sounds/build.wav"),
    ("Vendor/rpgaudio/Audio/handleCoins.ogg",            "TowerDefense/Resources/Sounds/coin.wav"),
    ("Vendor/rpgaudio/Audio/metalClick.ogg",             "TowerDefense/Resources/Sounds/click.wav"),
    # V3 ambiyans ara WAV'ları (CC0): zindan — https://opengameart.org/content/dungeon-ambience,
    # bataklık — https://opengameart.org/content/swamp-environment-audio
    ("Vendor/dungeon_ambient.ogg",                       "Vendor/amb_dungeon_tmp.wav"),
    ("Vendor/swamp.ogg",                                 "Vendor/amb_swamp_tmp.wav"),
]
for src, dst in pairs:
    data, rate = sf.read(src)
    sf.write(dst, data, rate)
    print("OK", dst)
EOF

# Uzun ambiyans döngüleri ham WAV bırakılmaz: AAC/m4a ~%95 küçük, kulakta fark yok.
afconvert -f m4af -d aac -q 127 Vendor/amb_dungeon_tmp.wav "$SOUNDS/amb_dungeon.m4a"
afconvert -f m4af -d aac -q 127 Vendor/amb_swamp_tmp.wav   "$SOUNDS/amb_swamp.m4a"
rm -f Vendor/amb_dungeon_tmp.wav Vendor/amb_swamp_tmp.wav

echo "Asset hazırlığı tamamlandı:"
echo "Sounds:"
ls "$SOUNDS"

#!/bin/bash
# Foozle "Spire" serisini (CC0) itch.io ücretsiz akışıyla indirir ve Vendor/spire altına açar.
# Akış: sayfa -> csrf -> POST download_url -> indirme sayfası -> upload_id'ler -> POST file/<id> -> zip
set -euo pipefail
cd "$(dirname "$0")/.."

VENDOR=Vendor/spire
mkdir -p "$VENDOR"
UA="Mozilla/5.0"
PACKS="spire-tileset-1 spire-tower-pack-1 spire-tower-pack-2 spire-tower-pack-3 spire-tower-pack-4 spire-enemy-pack-1 spire-enemy-pack-2 spire-builder-pack"

for pack in $PACKS; do
  [ -d "$VENDOR/$pack" ] && { echo "var: $pack"; continue; }
  jar=$(mktemp)
  page=$(curl -sL -c "$jar" -A "$UA" "https://foozlecc.itch.io/$pack")
  csrf=$(echo "$page" | grep -oE 'name="csrf_token" value="[^"]*"' | head -1 | sed 's/.*value="//;s/"//')
  dl=$(curl -s -b "$jar" -A "$UA" -X POST "https://foozlecc.itch.io/$pack/download_url" --data-urlencode "csrf_token=$csrf")
  url=$(echo "$dl" | python3 -c "import json,sys; print(json.load(sys.stdin)['url'])")
  ids=$(curl -sL -b "$jar" -A "$UA" "$url" | grep -oE 'data-upload_id="[0-9]+"' | grep -oE '[0-9]+' | sort -u)
  n=0
  for id in $ids; do
    n=$((n+1))
    f=$(curl -s -b "$jar" -A "$UA" -X POST "https://foozlecc.itch.io/$pack/file/$id" --data-urlencode "csrf_token=$csrf")
    file_url=$(echo "$f" | python3 -c "import json,sys; print(json.load(sys.stdin)['url'])")
    out="$VENDOR/${pack}_${n}.zip"
    curl -sL -A "$UA" "$file_url" -o "$out"
    # zip mi kontrol et (bazı yüklemeler tek png olabilir)
    if file "$out" | grep -q "Zip archive"; then
      mkdir -p "$VENDOR/$pack"
      unzip -q -o "$out" -d "$VENDOR/$pack"
    else
      echo "  atlandı (zip değil): $out ($(file -b "$out" | cut -c1-40))"
      rm -f "$out"
    fi
  done
  rm -f "$jar"
  echo "indi: $pack ($n dosya)"
done

echo "Spire özeti:"
for d in "$VENDOR"/spire-*/; do
  [ -d "$d" ] && echo "  $d: $(find "$d" -name '*.png' | wc -l | tr -d ' ') png"
done

#!/usr/bin/env python3
"""Kenney taret sprite'ından AppIcon.appiconset üretir. Önkoşul: ./scripts/fetch_assets.sh (Vendor/ dolu)."""
import json
import os
from PIL import Image, ImageDraw

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
TURRET = os.path.join(ROOT, "Vendor/td/PNG/Retina/towerDefense_tile204.png")
OUT = os.path.join(ROOT, "TowerDefense/Resources/Assets.xcassets/AppIcon.appiconset")
os.makedirs(OUT, exist_ok=True)

SIZE = 1024
icon = Image.new("RGBA", (SIZE, SIZE), (0, 0, 0, 0))
draw = ImageDraw.Draw(icon)
draw.rounded_rectangle([0, 0, SIZE - 1, SIZE - 1], radius=180, fill=(34, 70, 32, 255))
draw.rounded_rectangle([28, 28, SIZE - 29, SIZE - 29], radius=160,
                       outline=(58, 110, 52, 255), width=16)
turret = Image.open(TURRET).convert("RGBA").resize((720, 720), Image.LANCZOS)
icon.alpha_composite(turret, ((SIZE - 720) // 2, (SIZE - 720) // 2))

entries = []
icon.save(os.path.join(OUT, "icon_1024.png"))
entries.append({"filename": "icon_1024.png", "idiom": "universal",
                "platform": "ios", "size": "1024x1024"})
for pt in [16, 32, 128, 256, 512]:
    for scale in [1, 2]:
        px = pt * scale
        name = f"mac_{pt}x{pt}@{scale}x.png"
        icon.resize((px, px), Image.LANCZOS).save(os.path.join(OUT, name))
        entries.append({"filename": name, "idiom": "mac",
                        "size": f"{pt}x{pt}", "scale": f"{scale}x"})

with open(os.path.join(OUT, "Contents.json"), "w") as f:
    json.dump({"images": entries, "info": {"author": "xcode", "version": 1}}, f, indent=2)
print("OK:", OUT)

"""Exports 24-frame animation strips into an asset-catalog sprite atlas the game loads with SKTextureAtlas.

Each strip is 24 equal frames side by side (the pose-guided Gemini pipeline in
branding/sprites/characters/animation-tests/pose-guided writes them at 625 x 848 per frame,
feet on the line 40 px above the bottom). Frames are resized to the in-game height at @3x.

Usage: python3 ios/tools/sprite_atlas.py AtlasName HEIGHT_PT name=strip.png [name=strip.png ...]
  e.g. python3 ios/tools/sprite_atlas.py AttendantWalk 76 side=walk-side.png front=walk-front.png back=walk-back.png
Writes ios/Turbulence/Assets.xcassets/<AtlasName>.spriteatlas/<name>-NN.imageset. Needs Pillow.
"""
import json, os, shutil, sys
from PIL import Image

FRAMES = 24
here = os.path.dirname(os.path.abspath(__file__))
atlas, height_pt, pairs = sys.argv[1], float(sys.argv[2]), sys.argv[3:]
root = os.path.join(here, "..", "Turbulence", "Assets.xcassets", f"{atlas}.spriteatlas")
shutil.rmtree(root, ignore_errors=True); os.makedirs(root)
info = {"info": {"author": "xcode", "version": 1}}
json.dump(info, open(os.path.join(root, "Contents.json"), "w"), indent=2)
for pair in pairs:
    name, path = pair.split("=", 1)
    strip = Image.open(path).convert("RGBA"); fw = strip.width // FRAMES; fh = strip.height
    h = round(height_pt * 3); w = round(fw * h / fh)
    for t in range(FRAMES):
        f = strip.crop((t * fw, 0, (t + 1) * fw, fh)).resize((w, h), Image.LANCZOS)
        n = f"{name}-{t:02d}"; d = os.path.join(root, f"{n}.imageset"); os.makedirs(d)
        f.save(os.path.join(d, f"{n}.png"), optimize=True)
        json.dump({"images": [{"filename": f"{n}.png", "idiom": "universal", "scale": "3x"}], **info},
                  open(os.path.join(d, "Contents.json"), "w"), indent=2)
    print(f"{name}: {FRAMES} frames at {w}x{h} px")

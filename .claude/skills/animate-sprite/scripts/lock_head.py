"""Copies one good frame's head (and collar) onto every frame of an aligned strip, so details Gemini redraws a bit
differently each frame (face direction, collar, scarf, hair) stop flickering. Works because align_strip.py puts the
head in the same place in every frame; each frame's own small bob is followed.

Usage: lock_head.py strip-24.png out-24.png --ref 0 --cut 0.55 [--feather 24]
  --ref  the frame whose head is copied (pick the best-looking one)
  --cut  share of the figure height, from the top, that is locked; the next --feather px blend into the frame
"""
import argparse
import numpy as np
from PIL import Image

FW, FH = 625, 848
ap = argparse.ArgumentParser()
ap.add_argument("src"); ap.add_argument("out")
ap.add_argument("--ref", type=int, default=0); ap.add_argument("--cut", type=float, default=0.55)
ap.add_argument("--feather", type=int, default=24)
ap.add_argument("--width", type=float, default=0, help="also limit the lock to the head's width x this (e.g. 1.1), so shoulders and arms beside it stay animated")
a = ap.parse_args()

S = np.asarray(Image.open(a.src).convert("RGBA")).astype(float)
frames = [S[:, t * FW:(t + 1) * FW] for t in range(24)]
top = lambda f: int(np.nonzero((f[..., 3] > 128).any(1))[0].min())
bot = lambda f: int(np.nonzero((f[..., 3] > 128).any(1))[0].max())
ref = frames[a.ref]; rt = top(ref); cut = round(a.cut * (bot(ref) - rt))
band = np.nonzero((ref[rt:rt + round(0.35 * (bot(ref) - rt)), :, 3] > 128).any(0))[0]
hx0, hx1 = band.min(), band.max(); hc, hw = (hx0 + hx1) / 2, (hx1 - hx0) / 2 * (a.width or 1)
xw = np.clip((hw + a.feather - np.abs(np.arange(FW) - hc)) / a.feather, 0, 1)[None, :, None] if a.width else 1
out = []
for f in frames:
    dy = top(f) - rt                                         # follow this frame's bob
    shifted = np.zeros_like(ref)
    if dy >= 0: shifted[dy:] = ref[:FH - dy]
    else: shifted[:dy] = ref[-dy:]
    y = np.arange(FH)[:, None] - (rt + dy)
    w = np.clip((cut + a.feather - y) / a.feather, 0, 1)[..., None] * xw  # 1 over the head, ramps to 0 below the cut
    o = f.copy()
    o[..., :3] = shifted[..., :3] * w + f[..., :3] * (1 - w)
    o[..., 3:] = shifted[..., 3:] * w + f[..., 3:] * (1 - w)
    out.append(o)
Image.fromarray(np.clip(np.concatenate(out, axis=1), 0, 255).astype(np.uint8)).save(a.out)
print("locked", a.out)

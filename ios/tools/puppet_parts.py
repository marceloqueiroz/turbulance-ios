"""Slices map pieces into puppet parts that share one canvas, so they line up exactly and can turn around joints.

  whale    body, tail (feathered over the stalk), flipper (its spot on the body filled in)
  sailboat hull (with mast and deck), sails (cream pixels and their shading; the deck behind them filled in)
  gull     body (filled under the wings), left wing, right wing (wing roots feathered into the body)

Pivots (in source pixels) go to branding/map/cut/puppets.json; the app uses the same numbers.
Usage: python3 ios/tools/puppet_parts.py   (needs numpy and Pillow)
"""
import json

import numpy as np
from PIL import Image, ImageDraw

ROOT = __file__.rsplit("/ios/tools/", 1)[0]
CUT = f"{ROOT}/branding/map/cut"


def load(name):
    return np.asarray(Image.open(f"{CUT}/piece-{name}.png").convert("RGBA")).astype(np.float32)


def save(arr, name):
    Image.fromarray(np.clip(arr, 0, 255).astype(np.uint8)).save(f"{CUT}/piece-{name}.png", optimize=True)


def polygon(shape, pts):
    m = Image.new("L", (shape[1], shape[0]), 0)
    ImageDraw.Draw(m).polygon(pts, fill=255)
    return np.asarray(m) > 0


def box(x, r=2):
    acc = np.zeros_like(x)
    for dy in range(-r, r + 1):
        for dx in range(-r, r + 1):
            acc += np.roll(np.roll(x, dy, 0), dx, 1)
    return acc / (2 * r + 1) ** 2


def fill(img, hole, steps=40):
    """Fills `hole` from the colours around it (alpha-aware), so a moving part never reveals a gap."""
    out = img.copy()
    prem = out.copy(); prem[..., :3] *= prem[..., 3:4] / 255; prem[hole] = 0
    known = ~hole
    for _ in range(steps):
        k = known.astype(np.float32)
        blur, weight = box(prem * k[..., None]), box(k)
        newly = hole & ~known & (weight > 0.05)
        prem[newly] = blur[newly] / weight[newly][:, None]
        known |= newly
    rgb = np.where(prem[..., 3:4] > 1, prem[..., :3] * 255 / np.maximum(prem[..., 3:4], 1), 0)
    out[hole, :3] = rgb[hole]; out[hole, 3] = prem[hole, 3]
    return out


def part(src, mask, soft=None):
    out = src.copy()
    out[..., 3] = src[..., 3] * (soft if soft is not None else mask)
    return out


def feather_from(mask, width):
    """1 inside mask, fading to 0 over `width` px outside it (a soft overlap into the body)."""
    m = mask.astype(np.float32)
    for _ in range(width):
        m = np.maximum(m, box(m, 1) * (1 - 1 / width))
    return np.clip(m, 0, 1)


pivots = {}

# --- sailboat: sails swing round the mast's foot
s = load("sailboat"); h, w = s.shape[:2]; yy, xx = np.mgrid[0:h, 0:w]
r, g, b, a = s[..., 0], s[..., 1], s[..., 2], s[..., 3]
# cream sails including their shaded edges; the orange mast and deck (red well above blue) and the navy hull stay
sails = (a > 20) & (yy < 340) & (r > 150) & (g > 135) & (b > 105) & (r - b < 85)
sails = box(sails.astype(np.float32), 1) > 0.34                                     # close pinholes along the edges
sails &= (a > 20) & (yy < 340) & ~((r - b > 95) & (r > 160))                         # never take the mast
save(part(s, sails), "sailboat-sails")
save(fill(s, sails), "sailboat-hull")
pivots["sailboat"] = {"size": [w, h], "sails": [185, 300]}

# --- gull: wings hinge at the shoulders
gl = load("gull"); h, w = gl.shape[:2]
alpha = gl[..., 3] > 20
left = polygon(gl.shape, [(0, 0), (262, 0), (258, 96), (222, 108), (150, 104), (0, 86)]) & alpha
right = polygon(gl.shape, [(302, 58), (456, 58), (456, 236), (334, 206), (304, 156)]) & alpha
save(part(gl, left, feather_from(left, 8) * alpha), "gull-wing-left")
save(part(gl, right, feather_from(right, 8) * alpha), "gull-wing-right")
save(fill(gl, left | right), "gull-body")                                           # feathers under the wings, so folding shows no hole
pivots["gull"] = {"size": [w, h], "wingLeft": [236, 100], "wingRight": [304, 126]}

pivots["whale"] = {"size": [512, 420], "tail": [368, 147], "flipper": [300, 305]}
json.dump(pivots, open(f"{CUT}/puppets.json", "w"), indent=1)
print(json.dumps(pivots))

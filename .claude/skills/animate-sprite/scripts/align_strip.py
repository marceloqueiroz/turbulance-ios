"""Aligns a raw 24-frame strip into the final one and scores it.

  - one uniform scale for the whole strip (--height: figure height in px, to match the other facings)
  - every frame placed on the LOCKED HEAD: head centred, head top on a smooth bob curve (--bob px, 2 bobs per cycle)
  - only the body under the head (below --cut of the height) is stretched so the planted foot lands on the ground line
Never align on the lowest pixel per frame: heels and toes tipping make the whole body jump.

Prints the checks: head width spread, frame-to-frame silhouette change (incl. the loop seam 23>0) and leftover
guide colours. Writes <out>-24.png (24 x 625 x 848, feet on y=775) and <out>.gif.

Usage: align_strip.py raw-side-a.png side-a --bob 4 --height 625
"""
import argparse, math
import numpy as np
from PIL import Image

FW, FH, HEADTOP, GROUND = 625, 848, 150, 775
ap = argparse.ArgumentParser()
ap.add_argument("src"); ap.add_argument("out")
ap.add_argument("--bob", type=float, default=4); ap.add_argument("--height", type=float, default=625)
ap.add_argument("--cut", type=float, default=0.55, help="share of the height from the head top that is never stretched")
ap.add_argument("--fix-orange", action="store_true", help="repaint leftover orange guide limbs as shadowed skin (a far leg Gemini forgot)")
a = ap.parse_args()

src = Image.open(a.src).convert("RGBA")
fr = [src.crop((t * FW, 0, (t + 1) * FW, FH)) for t in range(24)]
alpha = lambda f: np.asarray(f)[..., 3] > 128
hs = sorted(int(np.ptp(np.nonzero(alpha(f).any(1))[0])) for f in fr); k = a.height / hs[12]
big = [f.resize((round(FW * k), round(FH * k)), Image.LANCZOS) for f in fr]


def head(f):
    """Head top and centre from the coloured pixels only: a silver tray or white gloves near the head must not move it."""
    px = np.asarray(f).astype(int); A = alpha(f) & ~((px[..., :3].max(2) - px[..., :3].min(2) < 28) & (px[..., :3].min(2) > 140))
    top = np.nonzero(A.any(1))[0].min(); cols = np.nonzero(A[top:top + 160].any(0))[0]
    return top, (cols.min() + cols.max()) / 2, cols.max() - cols.min()


M = [head(f) for f in big]; cut = round(a.cut * a.height)
res = []
for t, (f, (top, hx, _)) in enumerate(zip(big, M)):
    bob = a.bob * math.cos(2 * math.pi * (t / 24 * 2 - 2 / 12))          # + is down: lowest on the down poses
    c = Image.new("RGBA", (FW, FH), (0, 0, 0, 0)); c.alpha_composite(f, (round(FW / 2 - hx), round(HEADTOP + bob - top)))
    ys = np.nonzero(alpha(c).any(1))[0]; bot, yc = ys.max(), ys.min() + cut
    if bot != GROUND:
        body = c.crop((0, yc, FW, bot + 1)).resize((FW, GROUND - yc + 1), Image.LANCZOS)
        upper = c.crop((0, 0, FW, yc)); c = Image.new("RGBA", (FW, FH), (0, 0, 0, 0)); c.paste(upper, (0, 0)); c.alpha_composite(body, (0, yc))
    res.append(c)

strip = Image.new("RGBA", (FW * 24, FH))
for i, f in enumerate(res): strip.paste(f, (i * FW, 0))
if a.fix_orange:
    from scipy import ndimage
    px = np.array(strip).astype(float); r, gg, b, al = [px[..., i] for i in range(4)]
    o = ndimage.binary_dilation((al > 128) & (r > 200) & (gg > 110) & (gg < 190) & (b < 90), iterations=2) & (al > 0)
    lum = (0.3 * r + 0.59 * gg + 0.11 * b)[o] / 255 / 0.6
    px[o, 0], px[o, 1], px[o, 2] = 190 * lum, 128 * lum, 110 * lum
    strip = Image.fromarray(np.clip(px, 0, 255).astype(np.uint8)); res = [strip.crop((i * FW, 0, (i + 1) * FW, FH)) for i in range(24)]
strip.save(a.out + "-24.png")
g = [Image.alpha_composite(Image.new("RGBA", (FW, FH), (236, 230, 220, 255)), f).convert("RGB").resize((FW // 2, FH // 2)) for f in res]
g[0].save(a.out + ".gif", save_all=True, append_images=g[1:], duration=42, loop=0)

# checks
w = [m[2] for m in M]; print(f"head width spread: {100 * (max(w) - min(w)) / np.median(w):.1f}%  (want < 3%)")
A = [alpha(f) for f in res]; j = [int((A[i] ^ A[(i + 1) % 24]).sum() // 1000) for i in range(24)]
print("frame changes:", j, f"| seam 23>0 = {j[23]}, median {int(np.median(j))}  (seam should be <= ~2x median)")
px = np.asarray(strip).astype(int); r, gg, b, al = [px[..., i] for i in range(4)]
orange = int(((al > 128) & (r > 200) & (gg > 110) & (gg < 190) & (b < 90)).sum())
blue = int(((al > 128) & (b > 180) & (r < 90) & (gg < 150)).sum())
print(f"guide colour left: orange {orange} px, blue {blue} px  (want < ~50 each)")
clipped = [i for i, m in enumerate(alpha(f) for f in res) if m[:, :2].any() or m[:, -2:].any() or m[:2].any()]
print(f"frames touching the frame edge (clipped): {clipped or 'none'}  (want none: move the prop inside her width)")

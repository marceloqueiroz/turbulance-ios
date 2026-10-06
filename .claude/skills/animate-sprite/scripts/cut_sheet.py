"""Cuts a generated 6 x 4 sheet into a raw 24-frame strip: exact grid cells, magenta keyed out with despill,
only the largest blob kept (drops stray specks), each frame on an equal 625 x 848 canvas.
Positions here are rough; align_strip.py does the real alignment.

Usage: cut_sheet.py out-side-a.png raw-side-a.png
"""
import sys
import numpy as np
from PIL import Image
from scipy import ndimage

FW, FH = 625, 848


def key(c):
    a = np.asarray(c.convert("RGB")).astype(float); r, g, b = a[..., 0], a[..., 1], a[..., 2]
    alpha = 1 - np.clip(((np.minimum(r, b) - g) - 40) / 60, 0, 1)          # 1 - magenta-ness
    lab, n = ndimage.label(alpha > 0.5)
    if n:
        big = np.argmax(ndimage.sum(np.ones_like(lab), lab, range(1, n + 1))) + 1
        alpha *= ndimage.binary_dilation(lab == big, iterations=3)
    spill = np.clip(np.minimum(r, b) - g - 10, 0, None)                      # pull pink fringes back to neutral
    a[..., 0] -= spill * 0.6; a[..., 2] -= spill * 0.6
    return Image.fromarray(np.dstack([np.clip(a, 0, 255), alpha * 255]).astype(np.uint8))


src, out = sys.argv[1], sys.argv[2]
im = Image.open(src); W, H = im.size; cw, ch = W / 6, H / 4
cells = [key(im.crop((round(i % 6 * cw), round(i // 6 * ch), round((i % 6 + 1) * cw), round((i // 6 + 1) * ch)))) for i in range(24)]
strip = Image.new("RGBA", (FW * 24, FH))
for i, c in enumerate(cells):
    A = np.asarray(c)[..., 3] > 128; ys, xs = np.nonzero(A)
    hx = np.nonzero(A[ys.min():ys.min() + 120])[1].mean()                    # head-top band centre
    f = Image.new("RGBA", (FW, FH), (0, 0, 0, 0)); f.alpha_composite(c, (int(FW / 2 - hx), int(FH - 60 - ys.max())))
    strip.paste(f, (i * FW, 0))
strip.save(out)
print("raw strip", out)

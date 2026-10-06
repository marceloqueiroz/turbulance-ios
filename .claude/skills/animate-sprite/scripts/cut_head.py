"""Cuts the character's head (cap, hair, face, scarf...) out of an approved sprite or a good generated frame.
The head is pasted unchanged into every pose-guide cell, which is what stops Gemini drifting across the sheet.

Usage:
  cut_head.py src.png head.png --keep-above Y            # keep rows above Y (side views: cut just under the scarf)
  cut_head.py src.png head.png --ellipse CX,CY,RX,RY     # keep an ellipse (front/back views, where the arms touch the head)
Always look at the result: no hands, sleeves or shoulders may be left in it.
"""
import argparse
import numpy as np
from PIL import Image, ImageDraw, ImageFilter

ap = argparse.ArgumentParser()
ap.add_argument("src"); ap.add_argument("out")
ap.add_argument("--keep-above", type=int)
ap.add_argument("--ellipse")
a = ap.parse_args()
im = Image.open(a.src).convert("RGBA")
m = Image.new("L", im.size, 0); d = ImageDraw.Draw(m)
if a.keep_above is not None:
    d.rectangle((0, 0, im.width, a.keep_above), fill=255)
elif a.ellipse:
    cx, cy, rx, ry = map(float, a.ellipse.split(","))
    d.ellipse((cx - rx, cy - ry, cx + rx, cy + ry), fill=255)
    m = m.filter(ImageFilter.GaussianBlur(2))
else:
    ap.error("give --keep-above or --ellipse")
px = np.array(im); px[..., 3] = np.minimum(px[..., 3], np.array(m))
out = Image.fromarray(px)
(out.crop(out.getbbox()) if a.keep_above is not None else out).save(a.out)   # ellipse heads keep the sprite canvas (front/back guides need it)
print("head", out.getbbox())

"""Cuts a route-map render (region, airport, cloud, actor) out of its flat background.

Regions are rendered on the map's sea blue (#2C7A96), so their shallow water fades into the
same colour the game draws; pieces can use any flat colour. Gemini's "flat" background is never
quite flat, so it is estimated locally: pixels that are clearly background are averaged over a
wide blur, giving a background colour for every pixel. Soft edges (foam, shallow water, shadows)
are then un-mixed from that local background so they keep their own colour instead of a halo.

Pieces (airports, actors, clouds) are rendered on magenta and cut with --key hue: a contact
shadow is the background's hue, only darker, so it drops out instead of leaving a purple smudge
that also glues neighbouring objects together. The game draws its own soft shadows.

Usage: python3 ios/tools/map_cutout.py in.png out.png [--max 2400] [--key colour|hue]
Needs numpy and Pillow (pip install numpy pillow).
"""
import argparse

import numpy as np
from PIL import Image, ImageFilter


def blur(a, radius):
    """Wide blurs shrink and re-enlarge the float map (smooth enough for a background estimate);
    fine blurs (edge softening, values 0…1) go through an 8-bit Gaussian."""
    if radius > 4:
        h, w = a.shape
        img = Image.fromarray(a.astype(np.float32))
        small = img.resize((max(1, round(w / radius)), max(1, round(h / radius))), Image.BOX)
        return np.asarray(small.resize((w, h), Image.BILINEAR), dtype=np.float32)
    img = Image.fromarray(np.clip(a * 255, 0, 255).astype(np.uint8))
    return np.asarray(img.filter(ImageFilter.GaussianBlur(radius)), dtype=np.float32) / 255


def cut_out(im, key="colour"):
    im = im.astype(np.float32)
    h, w, _ = im.shape
    border = np.concatenate([im[:8].reshape(-1, 3), im[-8:].reshape(-1, 3), im[:, :8].reshape(-1, 3), im[:, -8:].reshape(-1, 3)])
    guess = np.median(border, axis=0)
    sure_bg = np.linalg.norm(im - guess, axis=2) < 18                  # clearly background
    wgt = blur(sure_bg.astype(np.float32), 60) + 1e-3
    bg = np.dstack([blur(im[..., c] * sure_bg, 60) / wgt for c in range(3)])
    bg[sure_bg] = im[sure_bg]
    if key == "hue":
        chroma = lambda c: c / (c.sum(axis=2, keepdims=True) + 30)    # colour with brightness divided out
        d = np.linalg.norm(chroma(im) - chroma(bg), axis=2) * 400
        sure_bg = sure_bg | (d < 10)
        bg = np.where(sure_bg[..., None], im, bg)
    else:
        d = np.linalg.norm(im - bg, axis=2)
    a = np.clip((d - 10) / 70, 0, 1)                                  # 0 at the local background, 1 on the subject
    a = blur(a, 0.7)
    a[a < 0.04] = 0
    fg = np.clip((im - (1 - a[..., None]) * bg) / np.maximum(a, 0.04)[..., None], 0, 255)
    return np.dstack([fg, a * 255]).astype(np.uint8)


def main():
    p = argparse.ArgumentParser()
    p.add_argument("src")
    p.add_argument("dst")
    p.add_argument("--max", type=int, default=0, help="longest side in pixels after cropping (0 = keep)")
    p.add_argument("--key", choices=["colour", "hue"], default="colour", help="hue for pieces on magenta (drops shadows)")
    args = p.parse_args()
    rgba = Image.fromarray(cut_out(np.asarray(Image.open(args.src).convert("RGB")), args.key))
    box = rgba.getchannel("A").point(lambda v: 255 if v > 10 else 0).getbbox()
    if box:
        pad = 16
        rgba = rgba.crop((max(0, box[0] - pad), max(0, box[1] - pad), min(rgba.width, box[2] + pad), min(rgba.height, box[3] + pad)))
    if args.max and max(rgba.size) > args.max:
        s = args.max / max(rgba.size)
        rgba = rgba.resize((round(rgba.width * s), round(rgba.height * s)), Image.LANCZOS)
    rgba.save(args.dst, optimize=True)
    print(args.dst, rgba.size)


if __name__ == "__main__":
    main()

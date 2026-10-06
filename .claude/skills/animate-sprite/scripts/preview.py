"""Walks a finished strip across a background (e.g. cabin art) and writes an MP4, so the walk is judged
moving through the scene, not looping in place. Two clips: the game's speed, then "feet planted" speed
(no foot sliding), so the slide at game speed is visible and can be decided on.

Usage: preview.py side-24.png background.png out.mp4 --fig 140 --ground 735 --x0 600 --x1 2750
                  [--game-speed 220 --sprite-pt 48 --cycles 2.6]
  --fig       figure height in background px          --ground  y of the feet in background px
  --game-speed / --sprite-pt   crew speed in pt/s and the in-game figure height in pt (speed = body heights per second)
If the background has a character painted in, have Gemini remove it first (hand patching looks worse).
Needs: uv run --with numpy --with pillow --with "imageio[ffmpeg]"
"""
import argparse
import imageio, numpy as np
from PIL import Image, ImageDraw, ImageFilter

ap = argparse.ArgumentParser()
ap.add_argument("strip"); ap.add_argument("bg"); ap.add_argument("out")
ap.add_argument("--fig", type=float, default=140); ap.add_argument("--ground", type=int, default=735)
ap.add_argument("--x0", type=float, default=600); ap.add_argument("--x1", type=float, default=2750)
ap.add_argument("--game-speed", type=float, default=220); ap.add_argument("--sprite-pt", type=float, default=48)
ap.add_argument("--cycles", type=float, default=2.6, help="walk cycles per second at game speed")
ap.add_argument("--seconds", type=float, default=7); ap.add_argument("--width", type=int, default=1584)
a = ap.parse_args()

FW, FH, FPS = 625, 848, 30
strip = Image.open(a.strip).convert("RGBA"); frames = [strip.crop((t * FW, 0, (t + 1) * FW, FH)) for t in range(24)]
A = [np.asarray(f)[..., 3] > 128 for f in frames]
figH = np.median([np.ptp(np.nonzero(m.any(1))[0]) for m in A]); s = a.fig / figH
spr = [f.resize((round(FW * s), round(FH * s)), Image.LANCZOS) for f in frames]; sw = spr[0].width; foot = round(775 * s)

# planted-foot travel per cycle: the lowest shoe pixels move back while a foot is planted
xs = [np.nonzero(m[np.nonzero(m.any(1))[0].max() - 12:].any(0))[0].mean() for m in A]
travel = sum(max(0, xs[t] - xs[t + 1]) for t in range(23)) * s
bg = Image.open(a.bg).convert("RGB")
shadow = Image.new("RGBA", (sw, 60), (0, 0, 0, 0)); ImageDraw.Draw(shadow).ellipse((sw * 0.28, 12, sw * 0.72, 48), fill=(60, 30, 20, 90))
shadow = shadow.filter(ImageFilter.GaussianBlur(6))
game = a.game_speed / a.sprite_pt * a.fig
print(f"planted foot travels {travel:.0f} px per cycle; game speed {game:.0f} px/s needs {game / max(travel, 1):.1f} cycles/s to keep feet planted")


def clip(speed, cps, label):
    out = []; span = a.x1 - a.x0
    for i in range(int(a.seconds * FPS)):
        tt = i / FPS; p = (speed * tt) % (2 * span); x = a.x0 + p if p < span else a.x1 - (p - span)
        f = spr[int(tt * cps * 24) % 24]; f = f if p < span else f.transpose(Image.FLIP_LEFT_RIGHT)
        im = bg.copy().convert("RGBA"); im.alpha_composite(shadow, (round(x - sw / 2), a.ground - 30))
        im.alpha_composite(f, (round(x - sw / 2), a.ground - foot))
        ImageDraw.Draw(im).text((40, bg.height - 80), label, fill=(60, 40, 30))
        out.append(np.asarray(im.convert("RGB").resize((a.width, round(bg.height * a.width / bg.width)), Image.LANCZOS)))
    return out


planted = 1.6
imageio.mimwrite(a.out, clip(game, a.cycles, f"game speed {a.game_speed:.0f} pt/s") +
                 clip(travel * planted, planted, "feet planted"), fps=FPS, quality=8, macro_block_size=8)
print("preview", a.out)

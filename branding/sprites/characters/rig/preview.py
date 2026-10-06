import json, math, sys
import os; NOMARK = os.environ.get("NOMARK") == "1"
from PIL import Image, ImageDraw
rigf, outp = sys.argv[1], sys.argv[2]; rig = json.load(open(rigf)); d = rigf.rsplit("/", 1)[0]
def pose(f, t):
    R = rig[f]; W, H = R["size"]; c = Image.new("RGBA", (W, H + 40), (245, 222, 206, 255)); s = math.sin(t * 2 * math.pi)
    # side: legs swing opposite each other; each arm swings opposite its own leg (a normal walk)
    ang = {"legR": -30 * s, "legL": 30 * s, "armR": 32 * s, "armL": -32 * s, "head": 3 * math.sin(t * 4 * math.pi)}
    # walking towards or away from the camera: each foot steps forward and back (up and down the screen, a little
    # wider when lifted), the arms swing opposite to the legs, the body sways side to side
    step = {"legR": 0, "legL": 0, "armR": 0, "armL": 0}; sway = 0
    # side: feet slide forward and back along the walk (legs are short stubs at this camera height, so a step
    # reads as the feet passing each other), lifting a little as they swing through
    slide = {}
    if f == "side":
        ang = {"legR": -12 * s, "legL": 12 * s, "armR": 34 * s, "armL": -34 * s, "head": 3 * math.sin(t * 4 * math.pi)}
        slide = {"legR": 34 * s, "legL": -34 * s}
        step = {"legR": -8 * max(0, math.cos(t * 2 * math.pi)), "legL": -8 * max(0, -math.cos(t * 2 * math.pi))}
    if f != "side":
        sgn = 1 if f == "front" else -1
        ang = {"armR": 14 * s, "armL": 14 * s, "legR": 0, "legL": 0, "head": 2 * s}
        step = {"legR": 40 * s, "legL": -40 * s, "armR": -22 * s, "armL": 22 * s}
        sway = int(5 * s)
    bob = int(6 * abs(s))
    for nm in R["order"]:
        if nm not in R["parts"]: continue
        im = Image.open(f"{d}/{R['parts'][nm]}"); pv = R["pivots"].get(nm)
        if pv and ang.get(nm):
            im = im.rotate(ang[nm], resample=Image.BICUBIC, center=tuple(pv))
        leg = nm in ("legL", "legR")
        c.alpha_composite(im, (int((sway if not leg else 0) + slide.get(nm, 0)), int(20 - (0 if leg else bob) + step.get(nm, 0))))
    for nm, pv in ({} if NOMARK else R["pivots"]).items():
        if pv: ImageDraw.Draw(c).ellipse((pv[0] - 6, pv[1] + 14, pv[0] + 6, pv[1] + 26), outline=(214, 40, 40), width=3)
    return c
frames = []
for k in range(12):
    row = [pose(f, k / 12) for f in ["side", "back", "front"]]
    H = max(r.height for r in row); W = sum(r.width for r in row)
    fr = Image.new("RGBA", (W, H), (245, 222, 206, 255)); x = 0
    for r in row: fr.alpha_composite(r, (x, 0)); x += r.width
    frames.append(fr.convert("RGB").resize((W // 2, H // 2), Image.LANCZOS))
frames[0].save(outp, save_all=True, append_images=frames[1:], duration=90, loop=0)
strip = Image.new("RGB", (frames[0].width, frames[0].height * 3), (255, 255, 255))
for i, k in enumerate([0, 3, 9]): strip.paste(frames[k], (0, i * frames[0].height))
strip.save(outp.replace(".gif", "-strip.jpg"), quality=85)

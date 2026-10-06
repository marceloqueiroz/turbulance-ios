import json, math, sys
import os; NOMARK = os.environ.get("NOMARK") == "1"
from PIL import Image, ImageDraw
rigf, outp = sys.argv[1], sys.argv[2]; rig = json.load(open(rigf)); d = rigf.rsplit("/", 1)[0]
def pose(f, t):
    R = rig[f]; W, H = R["size"]; c = Image.new("RGBA", (W, H + 40), (245, 222, 206, 255)); s = math.sin(t * 2 * math.pi)
    ang = {"armR": 22 * s, "armL": -22 * s, "legR": -18 * s, "legL": 18 * s, "head": 4 * math.sin(t * 4 * math.pi)}
    if f != "side": ang = {"armR": 14 * s, "armL": 14 * s, "legR": 0, "legL": 0, "head": 3 * s}
    bob = int(6 * abs(s))
    for nm in R["order"]:
        if nm not in R["parts"]: continue
        im = Image.open(f"{d}/{R['parts'][nm]}"); pv = R["pivots"].get(nm)
        if pv and ang.get(nm):
            im = im.rotate(ang[nm], resample=Image.BICUBIC, center=tuple(pv))
        c.alpha_composite(im, (0, 20 - (bob if nm != "legL" and nm != "legR" else 0)))
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

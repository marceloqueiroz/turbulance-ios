"""Splits character sprites into moving parts using a colour-coded segmentation map, fills what moving parts uncover,
finds the joints where parts touch, and writes parts + rig.json. Usage: rig.py sheet.png seg.png outdir name"""
import sys, json, os
import numpy as np
from PIL import Image, ImageFilter
from scipy import ndimage
sheet, seg, outdir, name = sys.argv[1:5]; os.makedirs(outdir, exist_ok=True)
im = np.asarray(Image.open(sheet).convert("RGB")).astype(np.float32) / 255
r, g, b = im[..., 0], im[..., 1], im[..., 2]; mag = np.minimum(r, b) - g
alpha = 1 - np.clip((mag - 0.25) / 0.35, 0, 1)
rgb = im.copy(); cast = np.clip(mag, 0, None) * 0.85; rgb[..., 0] = r - cast; rgb[..., 2] = b - cast
A = np.asarray(Image.fromarray((alpha * 255).astype(np.uint8)).filter(ImageFilter.MinFilter(3)).filter(ImageFilter.GaussianBlur(0.8))).astype(np.float32)
RGBA = np.dstack([np.clip(rgb, 0, 1) * 255, A])
S = np.asarray(Image.open(seg).convert("RGB").resize((im.shape[1], im.shape[0]), Image.NEAREST)).astype(np.float32)
PAL = {"head": (255, 0, 0), "torso": (0, 255, 0), "armR": (0, 0, 255), "armL": (255, 255, 0), "legR": (0, 255, 255), "legL": (255, 128, 0), "bg": (255, 0, 255)}
names = list(PAL); P = np.array([PAL[k] for k in names], np.float32)
lab = np.argmin(((S[:, :, None, :] - P[None, None]) ** 2).sum(-1), -1)
body = A > 30
# label every body pixel the map left as background with its nearest body label
known = body & (lab != names.index("bg"))
_, (iy, ix) = ndimage.distance_transform_edt(~known, return_indices=True)
lab = np.where(body, lab[iy, ix], names.index("bg"))
figs, n = ndimage.label(ndimage.binary_dilation(body, iterations=8))
objs = sorted([(sl[1].start, i + 1, sl) for i, sl in enumerate(ndimage.find_objects(figs)) if (figs[sl] == i + 1).sum() > 20000])
FACING = ["side", "back", "front"]
def box(x, r=2):
    acc = np.zeros_like(x)
    for dy in range(-r, r + 1):
        for dx in range(-r, r + 1): acc += np.roll(np.roll(x, dy, 0), dx, 1)
    return acc / (2 * r + 1) ** 2
def fill(img, hole, steps=40):
    out = img.copy(); prem = out.copy(); prem[..., :3] *= prem[..., 3:4] / 255; prem[hole] = 0; known = ~hole
    for _ in range(steps):
        k = known.astype(np.float32); bl, w = box(prem * k[..., None]), box(k); new = hole & ~known & (w > 0.05)
        prem[new] = bl[new] / w[new][:, None]; known |= new
    rgbp = np.where(prem[..., 3:4] > 1, prem[..., :3] * 255 / np.maximum(prem[..., 3:4], 1), 0)
    out[hole, :3] = rgbp[hole]; out[hole, 3] = prem[hole, 3]; return out
rig = {}
for (x0, fi, sl), facing in zip(objs, FACING):
    ys, xs = sl; pad = 30
    y0, y1, xa, xb = max(0, ys.start - pad), ys.stop + pad, max(0, xs.start - pad), xs.stop + pad
    L = lab[y0:y1, xa:xb].copy(); src = RGBA[y0:y1, xa:xb].copy(); mine = figs[y0:y1, xa:xb] == fi
    src[~mine, 3] = 0; L[~mine] = names.index("bg")
    # parts painted in a leg colour but sitting in the upper body are arms (the side view's near arm)
    tor = L == names.index("torso"); ty = np.nonzero(tor)[0]; mid = ty.mean() if len(ty) else L.shape[0] / 2
    for leg, arm in (("legR", "armR"), ("legL", "armL")):
        comp, k = ndimage.label(L == names.index(leg))
        for c in range(1, k + 1):
            cy = np.nonzero(comp == c)[0].mean()
            if cy < mid: L[comp == c] = names.index(arm)
    parts, pivots = {}, {}
    def m(nm): return L == names.index(nm)
    def contact(a, b):
        t = ndimage.binary_dilation(m(a), iterations=6) & ndimage.binary_dilation(m(b), iterations=6)
        yy, xx = np.nonzero(t); return [float(xx.mean()), float(yy.mean())] if len(xx) else None
    for nm in ["head", "armR", "armL", "legR", "legL"]:
        if m(nm).sum() < 50: continue
        mk = m(nm); cc, kk = ndimage.label(mk)
        if kk > 1: mk = cc == (np.argmax(ndimage.sum(mk, cc, range(1, kk + 1))) + 1)   # drop stray fragments
        L[m(nm) & ~mk] = names.index("torso")
        soft = np.clip(ndimage.gaussian_filter(mk.astype(np.float32), 1.0) * 1.6, 0, 1)
        p = src.copy(); p[..., 3] *= soft; parts[nm] = p
        pv = contact(nm, "torso");  pivots[nm] = pv
    hole = np.zeros(L.shape, bool)
    for nm in ["armR", "armL", "legR", "legL", "head"]: hole |= ndimage.binary_dilation(m(nm), iterations=2)
    t = src.copy(); t[~ndimage.binary_dilation(m("torso"), iterations=3), 3] = 0
    # what the torso shows under an arm or the head: grow the torso into those areas, clipped to the body silhouette
    grow = hole & ndimage.binary_dilation(m("torso"), iterations=25) & (src[..., 3] > 30)
    tf = fill(src.copy(), grow & ~m("torso")); tf[~(m("torso") | grow), 3] = 0; parts["torso"] = tf
    out = {}
    for nm, p in parts.items():
        fn = f"{name}-{facing}-{nm}.png"; Image.fromarray(np.clip(p, 0, 255).astype(np.uint8)).save(f"{outdir}/{fn}", optimize=True); out[nm] = fn
    rig[facing] = {"size": [L.shape[1], L.shape[0]], "parts": out, "pivots": pivots,
                   "order": ["legL", "legR", "armL" if facing != "back" else "armR", "torso", "armR" if facing != "back" else "armL", "head"]}
json.dump(rig, open(f"{outdir}/{name}-rig.json", "w"), indent=1)
print(json.dumps({k: {"size": v["size"], "pivots": v["pivots"]} for k, v in rig.items()}))

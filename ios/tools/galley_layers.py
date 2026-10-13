"""Final galley layers from the 4K text-free pictures (base, empty, oven-open, drawers-out).
Writes the app layers at 2/3 of 4K (4224 x 1792) and layout.json in DESIGN units (the 3168-wide wall the code uses).
Inputs in <dir>: base.png, empty-a.png, oven-a.png, drawer-a.png (the 4K JPEGs in branding/menu/, saved as PNG).
Usage: galley_layers.py <dir> <out dir>"""
import sys, json
from PIL import Image, ImageFilter, ImageDraw
import numpy as np
from scipy import ndimage as nd
d, out = sys.argv[1], sys.argv[2]
load = lambda n: np.asarray(Image.open(f"{d}/{n}.png").convert("RGB")).astype(np.float32)
B, E, O, D = load("base"), load("empty-a"), load("oven-a"), load("drawer-a")
H, W, _ = B.shape                     # 2688 x 6336
K = W / 3168                          # 2: 4K px per design unit
OUT = 2 / 3                           # app layers at 2/3 of 4K
box = lambda x0, y0, x1, y1: (int(x0 * K), int(y0 * K), int(x1 * K), int(y1 * K))

def colour_match(src, mask_static):
    """Per-channel gain so src's mean matches B's where nothing changed (the emptied pictures come out a little pinker)."""
    o = src.copy()
    for c in range(3):
        o[..., c] = src[..., c] * (B[..., c][mask_static].astype(np.float64).mean() / src[..., c][mask_static].astype(np.float64).mean())
    return o.clip(0, 255)
static = np.zeros((H, W), bool)
for x0, y0, x1, y1 in [box(0, 0, 480, 1344), box(2700, 0, 3168, 1344), box(600, 60, 1040, 560), box(1200, 680, 2600, 760)]:
    static[y0:y1, x0:x1] = True
static &= np.abs(B - E).max(axis=2) < 40
E = colour_match(E, static); O = colour_match(O, static)
diff = np.abs(B - E).max(axis=2)

boxes = {"cartCoral": (512, 860, 1525, 1344), "cartTeal": (1600, 860, 2650, 1344), "tag": (498, 935, 624, 1162),
         "manual": (2160, 200, 2490, 552), "cupA": (1350, 615, 1481, 795), "cupB": (1481, 615, 1612, 795)}
layout = {"size": [3168, 1344]}

def biggest(m):
    lab, n = nd.label(m)
    return m if n == 0 else lab == (1 + int(np.argmax(nd.sum(m, lab, range(1, n + 1)))))

def item(name, dif=diff, thr=26, close=10, keep_all=0, exclude=None):
    x0, y0, x1, y1 = box(*boxes[name])
    m = dif[y0:y1, x0:x1] > thr
    if exclude is not None: m &= ~exclude[y0:y1, x0:x1]
    m = nd.binary_closing(m, iterations=close)
    m = nd.binary_opening(m, iterations=3)
    if keep_all:
        lab, n = nd.label(m); sz = nd.sum(m, lab, range(1, n + 1))
        m = np.isin(lab, [i + 1 for i in range(n) if sz[i] >= keep_all])
    else: m = biggest(m)
    full = np.zeros((H, W), bool); full[y0:y1, x0:x1] = nd.binary_fill_holes(m)
    return full

def save(name, mask, rgb, bbox=None):
    a = np.asarray(Image.fromarray((mask * 255).astype(np.uint8)).filter(ImageFilter.GaussianBlur(2)))
    if bbox is None:
        ys, xs = np.nonzero(a > 8); bbox = (xs.min(), ys.min(), xs.max() + 1, ys.max() + 1)
    x0, y0, x1, y1 = bbox
    im = Image.fromarray(np.dstack([rgb.astype(np.uint8), a])[y0:y1, x0:x1])
    im = im.resize((round((x1 - x0) * OUT), round((y1 - y0) * OUT)), Image.LANCZOS)
    im.save(f"{out}/{name}.png", optimize=True)
    layout[name] = [round(x0 / K, 1), round(y0 / K, 1), round((x1 - x0) / K, 1), round((y1 - y0) / K, 1)]
    return bbox

def union(a, b):
    return (min(a[0], b[0]), min(a[1], b[1]), max(a[2], b[2]), max(a[3], b[3]))
def bb(m):
    ys, xs = np.nonzero(m); return (xs.min() - 4, ys.min() - 4, xs.max() + 5, ys.max() + 5)

tag = item("tag", close=6, keep_all=60)
save("GalleyTag", tag, B)
excl = nd.binary_dilation(tag, iterations=4)
coral = item("cartCoral", exclude=excl); teal = item("cartTeal")
dD = np.abs(D - E).max(axis=2)
coralOpen = item("cartCoral", dif=dD, exclude=excl); tealOpen = item("cartTeal", dif=dD)
for name, closed, opened in [("GalleyCartCoral", coral, coralOpen), ("GalleyCartTeal", teal, tealOpen)]:
    u = union(bb(closed), bb(opened))
    save(name, closed, B, u); save(name + "Open", opened, D, u)
manual = item("manual"); save("GalleyManual", manual, B)
cupA = item("cupA", close=8, keep_all=600); save("GalleyCup", cupA, B)
cupB = item("cupB", close=8, keep_all=600); save("GalleyCupB", cupB, B)

# the oven: its door (rounded rectangle) from the base, its lit inside from the open-oven picture
door = box(1672, 212, 2115, 540)
x0, y0, x1, y1 = door
m = Image.new("L", (x1 - x0, y1 - y0), 0); ImageDraw.Draw(m).rounded_rectangle((0, 0, x1 - x0 - 1, y1 - y0 - 1), radius=int(14 * K), fill=255)
dm = np.zeros((H, W), bool); dm[y0:y1, x0:x1] = np.asarray(m) > 128
save("GalleyOvenDoor", dm, B, door)
inside = np.zeros((H, W), bool); inside[y0:y1, x0:x1] = True
save("GalleyOvenInside", inside, O, door)

# the wall: the base picture, with the emptied picture only where a moving thing leaves a hole
holes = coral | teal | coralOpen | tealOpen | tag | manual | cupA | cupB
x0, y0, x1, y1 = box(1290, 380, 1540, 530); holes[y0:y1, x0:x1] = True     # the coffee pot: empty glass (liquid drawn in code)
soft = np.asarray(Image.fromarray((nd.binary_dilation(holes, iterations=18) * 255).astype(np.uint8)).filter(ImageFilter.GaussianBlur(8))) / 255.0
wall = B * (1 - soft[..., None]) + E * soft[..., None]
Image.fromarray(wall.astype(np.uint8)).resize((round(W * OUT), round(H * OUT)), Image.LANCZOS).save(f"{out}/GalleyWall.jpg", quality=88)
json.dump(layout, open(f"{out}/layout.json", "w"), indent=1)
print(json.dumps(layout))

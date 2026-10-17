# N737-Swift base picture: the empty painted cabin (swift-empty) rebuilt at the game layout's coordinates
# (CabinLayout.swift, 1326 x 468 world units), with keyed seat sprites at every seat point. 4 px per world unit.
import numpy as np
from PIL import Image, ImageFilter, ImageDraw
E = Image.open('swift-empty.png').convert('RGB')
IW, IH = E.size; KX = IW / 1003.83; KY = IH / 424.0
def ipx(x, y): return ((x - 33.17) * KX, (y - 18) * KY)
P = 4.0; X0, X1, Y0, Y1 = 33.0, 1361.0, 1.0, 462.0
CW, CH = int((X1 - X0) * P), int((Y1 - Y0) * P)
def cpx(x, y): return (int(round((x - X0) * P)), int(round((y - Y0) * P)))
canvas = Image.new('RGB', (CW, CH))
YA = [(18, 1), (47, 30), (194, 189), (262, 259), (418, 438), (442, 462)]   # image-world y -> layout y
def lay_to_img_y(v): return np.interp(v, [b for _, b in YA], [a for a, _ in YA])
def to_lay_y(v): return np.interp(v, [a for a, _ in YA], [b for _, b in YA])
S = np.asarray(E)
def band(ix0, ix1, lx0, lx1):
    w = int(round((lx1 - lx0) * P))
    ly = Y0 + (np.arange(CH) + 0.5) / P
    iy = np.clip(((lay_to_img_y(ly) - 18) * KY).astype(int), 0, IH - 1)
    lx = lx0 + (np.arange(w) + 0.5) / P
    ix = np.clip(((ix0 + (lx - lx0) / (lx1 - lx0) * (ix1 - ix0) - 33.17) * KX).astype(int), 0, IW - 1)
    return Image.fromarray(S[iy][:, ix])
def hfeather(img, f):
    m = np.ones((img.height, img.width), np.float32); n = int(f * P)
    if n: m[:, :n] = np.linspace(0, 1, n)[None, :]
    return Image.fromarray((m * 255).astype(np.uint8))
def boxfeather(w, h, f):
    xs = np.arange(w)[None, :]; ys = np.arange(h)[:, None]
    r = np.minimum(np.minimum(xs + 1, w - xs), np.minimum(ys + 1, h - ys)) / max(1, f * P)
    return Image.fromarray((np.clip(r, 0, 1) * 255).astype(np.uint8))

# 1. floor and runner: a clean stretch of the empty cabin, repeated with soft joins, from the nose to the tail
x = X0; first = True
while x < X1:
    b = band(420.0, 820.0, x, x + 400); canvas.paste(b, cpx(x, Y0), None if first else hfeather(b, 30)); first = False
    x += 370
# the forward galley floor (no runner there) and the runner's rounded front end, from the empty cabin
fb = band(57.0, 205.0, 57.0, 205.0)            # only its clean middle (the concept's own counters lie above and below)
f0, f1 = cpx(0, 150)[1], cpx(0, 300)[1]; fb = fb.crop((0, f0, fb.width, f1))
fm = np.ones((fb.height, fb.width), np.float32); n = int(6 * P)
fm[:n] *= np.linspace(0, 1, n)[:, None]; fm[-n:] *= np.linspace(1, 0, n)[:, None]
canvas.paste(fb, (cpx(57, 0)[0], f0), Image.fromarray((fm * 255).astype(np.uint8)))
rc = band(198.0, 250.0, 198.0, 250.0)
r0, r1 = cpx(0, 176)[1], cpx(0, 272)[1]
rc = rc.crop((0, r0, rc.width, r1)); m = np.asarray(hfeather(rc, 4)).astype(float)
m[:int(4 * P)] *= np.linspace(0, 1, int(4 * P))[:, None]; m[-int(4 * P):] *= np.linspace(1, 0, int(4 * P))[:, None]
canvas.paste(rc, (cpx(198, 0)[0], r0), Image.fromarray(m.astype(np.uint8)))
# 2. walls without windows, full length (a window-free column of each wall band, stretched)
def wall(ix, iy0, iy1, ly0, ly1, lx0=57, lx1=1302):
    a = ipx(ix, iy0); b = ipx(ix + 6, iy1)
    c = E.crop((int(a[0]), int(a[1]), int(b[0]), int(b[1]))).resize((int((lx1 - lx0) * P), int((ly1 - ly0) * P)), Image.BILINEAR)
    canvas.paste(c, cpx(lx0, ly0))
wall(248, 18, 47, 1, 30); wall(248, 418, 442, 438, 462)
# 3. nose and tail walls
canvas.paste(band(33.17, 57.0, X0, 57.0), cpx(X0, Y0))
canvas.paste(band(1019.0, 1037.0, 1304.0, 1342.0), cpx(1304, Y0)); canvas.paste(band(1034.0, 1037.0, 1342.0, X1), cpx(1342, Y0))
# 4. windows, one per seat row on both walls
def crop(ibox): a = ipx(ibox[0], ibox[1]); b = ipx(ibox[2], ibox[3]); return E.crop((int(a[0]), int(a[1]), int(b[0]), int(b[1])))
topwin = crop((268, 18, 300, 40)); botwin = crop((266, 416, 298, 442))
rows_p = [328, 376, 424]; rows_e = [479 + 36 * i for i in range(20)]
for rx in rows_p + rows_e:
    for win, ly0, ly1 in [(topwin, 1, 23), (botwin, 436, 462)]:
        w = win.resize((int(30 * P), int((ly1 - ly0) * P)), Image.LANCZOS)
        canvas.paste(w, cpx(rx - 15, ly0), boxfeather(w.width, w.height, 2))
# 5. fixtures at their layout rectangles, with a soft contact shadow
def shadow(lx0, ly0, lx1, ly1, dx=4, dy=5, blur=8, alpha=80):
    sh = Image.new('L', (CW, CH), 0); sh.paste(alpha, (*cpx(lx0 + dx, ly0 + dy), *cpx(lx1 + dx, ly1 + dy)))
    canvas.paste(Image.new('RGB', (CW, CH), (120, 80, 70)), (0, 0), sh.filter(ImageFilter.GaussianBlur(blur)))
def element(ibox, lbox, f=2, sh=True):
    c = crop(ibox).resize((int((lbox[2] - lbox[0]) * P), int((lbox[3] - lbox[1]) * P)), Image.LANCZOS)
    if sh: shadow(*lbox)
    canvas.paste(c, cpx(lbox[0], lbox[1]), boxfeather(c.width, c.height, f))
def counter(ibox, lbox, band=(0.3, 0.62)):
    """A galley counter scaled evenly to its block's width; the extra height goes into its plain top (band, as
    fractions of the picture's height), so its rounded edges and front panel keep their shape."""
    c = crop(ibox); w = int((lbox[2] - lbox[0]) * P); h = int((lbox[3] - lbox[1]) * P)
    c = c.resize((w, int(c.height * w / c.width)), Image.LANCZOS)
    y0, y1 = int(c.height * band[0]), int(c.height * band[1])
    mid = c.crop((0, y0, w, y1)).resize((w, y1 - y0 + (h - c.height)), Image.BICUBIC)
    out = Image.new('RGB', (w, h)); out.paste(c.crop((0, 0, w, y0)), (0, 0)); out.paste(mid, (0, y0))
    out.paste(c.crop((0, y1, w, c.height)), (0, y0 + mid.height))
    shadow(*lbox); canvas.paste(out, cpx(lbox[0], lbox[1]), boxfeather(w, h, 2))
# counters against the side walls at the Comet's depth (CabinLayout: 94 deep), the galley floor in front of them
counter((54, 47, 252, 148), (57, 30, 210, 124)); counter((52, 313, 250, 413), (57, 344, 210, 438))
element((257, 45, 313, 177), (222, 30, 288, 182)); element((258, 277, 314, 417), (222, 286, 288, 438))
# aft lavatories: repainted at the Swift's own 110 x 152 proportions (lav-top / lav-bot), so nothing is stretched
for path, lbox in [('lav-top.png', (1194, 30, 1304, 182)), ('lav-bot.png', (1194, 286, 1304, 438))]:
    c = Image.open(path).convert('RGB').resize((int((lbox[2] - lbox[0]) * P), int((lbox[3] - lbox[1]) * P)), Image.LANCZOS)
    canvas.paste(c, cpx(lbox[0], lbox[1]), boxfeather(c.width, c.height, 1.5))
# 6. curtain: a brass rail across the cabin at the premium/economy line, the drawn-back fabric gathered at both walls
cx = 454; d = ImageDraw.Draw(canvas)
x0, _ = cpx(cx - 1.2, 0); x1, _ = cpx(cx + 1.2, 0)
for y0, y1 in [(30, 189), (259, 438)]:
    shadow(cx - 1.5, y0, cx + 1.5, y1, 2, 3, 4, 70)
    d.rectangle((x0, cpx(0, y0)[1], x1, cpx(0, y1)[1]), fill=(196, 150, 92)); d.line((x0 + 2, cpx(0, y0)[1], x0 + 2, cpx(0, y1)[1]), fill=(240, 214, 160), width=2)
for y0, y1 in [(30, 52), (416, 438)]:
    shadow(cx - 6, y0, cx + 6, y1, 2, 3, 5, 90)
    for k in range(5):
        xx = cx - 6 + k * 2.6
        d.rounded_rectangle((*cpx(xx, y0), *cpx(xx + 3.2, y1)), radius=6, fill=(214, 112, 98) if k % 2 else (232, 132, 116))
# 7. seats at every layout seat point (CabinLayout: economy rows 36 apart, seats at y 64/108/152 and 296/340/384;
#    premium rows 48 apart, seats at y 74/142 and 306/374), facing the nose like the Comet's
def key(path):
    im = np.asarray(Image.open(path).convert('RGB')).astype(int); r, g, b = im[..., 0], im[..., 1], im[..., 2]
    m = np.maximum(r, b); dd = g - m
    a = np.clip(1 - (dd - 12) / 48.0, 0, 1)
    g2 = np.where(dd > 0, m + 4, g); out = np.dstack([r, np.minimum(g, g2), b, (a * 255)]).astype(np.uint8)
    s = Image.fromarray(out); return s.crop(s.getbbox())
eco = key('seat-eco.png'); pre = key('seat-pre.png')
def place(spr, cx, cy, w, h):
    s = spr.resize((int(w * P), int(h * P)), Image.LANCZOS)
    sha = Image.new('L', (CW, CH), 0); sha.paste(s.split()[3].point(lambda v: v * 0.45), cpx(cx - w / 2 + 3, cy - h / 2 + 4))
    canvas.paste(Image.new('RGB', (CW, CH), (110, 70, 60)), (0, 0), sha.filter(ImageFilter.GaussianBlur(6)))
    canvas.paste(s, cpx(cx - w / 2, cy - h / 2), s)
for rx in rows_e:
    for sy in [64, 108, 152, 296, 340, 384]: place(eco, rx + 1, sy, 34, 40)
for rx in rows_p:
    for sy in [74, 142, 306, 374]: place(pre, rx + 1, sy, 44, 58)
canvas.save('swift-base.png')
canvas.resize((2000, int(2000 * CH / CW))).save('swift-base-preview.png')
print(canvas.size)

"""Draws ten app-icon concepts for Turbulence in the game's palette and a comparison sheet.

Usage: python3 ios/tools/icon_options.py  → branding/icon-options/*.png and sheet.png
"""
import math
import os
from PIL import Image, ImageDraw, ImageFilter, ImageFont

S = 2048                      # drawn at 2x, saved at 1024 for smooth edges
OUT = os.path.join(os.path.dirname(__file__), "..", "..", "branding", "icon-options")

NAVY, NAVY_DEEP = (27, 42, 74), (11, 20, 40)
CREAM, CORAL, TEAL = (232, 226, 216), (232, 84, 62), (31, 138, 140)
YELLOW, RED, STEEL, WHITE = (245, 185, 66), (214, 40, 40), (201, 205, 211), (255, 255, 255)
SKY_TOP, SKY_BOTTOM = (42, 68, 120), (11, 20, 40)
SKIN, HAIR = (233, 184, 146), (58, 42, 32)
LW = 34                       # outline width (2x)


def canvas(top=SKY_TOP, bottom=SKY_BOTTOM):
    img = Image.new("RGB", (S, S))
    d = ImageDraw.Draw(img)
    for y in range(S):
        t = y / S
        d.line([(0, y), (S, y)], fill=tuple(int(top[i] * (1 - t) + bottom[i] * t) for i in range(3)))
    return img, ImageDraw.Draw(img)


def waves(d, ys, amp=60, alpha_col=(255, 255, 255), width=40, shade=0.10, base=SKY_TOP):
    col = tuple(int(base[i] * (1 - shade) + alpha_col[i] * shade) for i in range(3))
    for k, y0 in enumerate(ys):
        pts = [(x, y0 + amp * math.sin((x + k * 180) / 120)) for x in range(-40, S + 40, 12)]
        d.line(pts, fill=col, width=width, joint="curve")


def outline(d, shape, xy, fill, **kw):
    getattr(d, shape)(xy, fill=fill, outline=NAVY, width=kw.pop("w", LW), **kw)


def poly(d, pts, fill, w=LW):
    d.polygon(pts, fill=fill, outline=NAVY, width=w)


def shadow(img, draw_fn, offset=(0, 40), blur=40, opacity=110):
    layer = Image.new("L", img.size, 0)
    draw_fn(ImageDraw.Draw(layer))
    layer = layer.filter(ImageFilter.GaussianBlur(blur))
    dark = Image.new("RGB", img.size, NAVY_DEEP)
    img.paste(dark, offset, layer.point(lambda v: v * opacity // 255))


def font(size):
    for f in ["/System/Library/Fonts/SFNSRounded.ttf", "/System/Library/Fonts/Supplemental/Arial Rounded Bold.ttf",
              "/System/Library/Fonts/Supplemental/Arial Bold.ttf"]:
        if os.path.exists(f):
            return ImageFont.truetype(f, size)
    return ImageFont.load_default()


def steam(d, x, y, h=260, col=WHITE):
    for dx in (-70, 40):
        pts = [(x + dx + 30 * math.sin(t / 30), y - t) for t in range(0, h, 8)]
        d.line(pts, fill=col, width=36, joint="curve")


# ---------------------------------------------------------------- 1. The attendant
def attendant():
    img, d = canvas((58, 104, 160), (20, 36, 72))
    waves(d, [1600, 1820], base=(40, 70, 120))
    shadow(img, lambda m: m.ellipse((520, 520, 1528, 1528), fill=255))
    outline(d, "ellipse", (360, 1340, 1688, 2300), TEAL)               # shoulders / uniform
    poly(d, [(1024, 1400), (840, 1340), (1024, 1640), (1208, 1340)], CORAL)   # scarf
    outline(d, "ellipse", (560, 560, 1488, 1488), SKIN)                 # face
    d.chord((540, 500, 1508, 1300), 180, 360, fill=HAIR)                # hair
    d.arc((540, 500, 1508, 1300), 180, 360, fill=NAVY, width=LW)
    outline(d, "rounded_rectangle", (700, 360, 1348, 600), TEAL, radius=80)   # cap
    d.rectangle((700, 560, 1348, 620), fill=NAVY)
    outline(d, "ellipse", (960, 400, 1088, 528), YELLOW, w=24)          # badge
    for ex in (840, 1208):                                              # eyes
        d.ellipse((ex - 45, 980, ex + 45, 1070), fill=NAVY)
    d.arc((850, 1080, 1198, 1300), 20, 160, fill=NAVY, width=LW)        # smile
    for cx in (740, 1308):
        d.ellipse((cx - 70, 1130, cx + 70, 1210), fill=(240, 150, 130))
    return img


# ---------------------------------------------------------------- 2. Coffee under pressure
def coffee():
    img, d = canvas()
    waves(d, [420, 1700])
    shadow(img, lambda m: m.ellipse((380, 1500, 1668, 1800), fill=255))
    outline(d, "ellipse", (380, 1420, 1668, 1740), STEEL)               # saucer
    outline(d, "rounded_rectangle", (560, 880, 1360, 1580), WHITE, radius=120)   # cup
    outline(d, "ellipse", (1260, 1020, 1580, 1380), None, w=70)         # handle
    d.ellipse((1330, 1090, 1510, 1310), fill=SKY_BOTTOM)
    d.rounded_rectangle((560, 880, 1360, 1060), radius=100, fill=(107, 62, 38), outline=NAVY, width=LW)
    d.rectangle((580, 1180, 1340, 1260), fill=CORAL)                    # livery stripe
    steam(d, 960, 820, 460)
    outline(d, "ellipse", (1440, 300, 1760, 620), RED)                  # alert
    d.rounded_rectangle((1575, 360, 1625, 510), radius=24, fill=WHITE)
    d.ellipse((1570, 530, 1630, 590), fill=WHITE)
    return img


# ---------------------------------------------------------------- 3. Seatbelt sign
def seatbelt():
    img, d = canvas((30, 38, 60), (10, 14, 26))
    shadow(img, lambda m: m.rounded_rectangle((300, 560, 1748, 1488), radius=200, fill=255), blur=60)
    outline(d, "rounded_rectangle", (300, 560, 1748, 1488), (52, 58, 72), radius=200)
    glow = Image.new("RGB", (S, S), (0, 0, 0))
    gd = ImageDraw.Draw(glow)
    gd.rounded_rectangle((420, 680, 1628, 1368), radius=140, fill=YELLOW)
    glow = glow.filter(ImageFilter.GaussianBlur(70))
    img.paste(Image.blend(img, glow, 0.35))
    d = ImageDraw.Draw(img)
    outline(d, "rounded_rectangle", (420, 680, 1628, 1368), (255, 226, 140), radius=140)
    # seated figure with belt
    d.ellipse((930, 760, 1110, 940), fill=NAVY)
    d.rounded_rectangle((880, 960, 1160, 1220), radius=60, fill=NAVY)
    d.rounded_rectangle((760, 1140, 1000, 1260), radius=50, fill=NAVY)
    d.rounded_rectangle((860, 1080, 1240, 1140), radius=30, fill=CORAL)
    d.rectangle((1020, 1070, 1080, 1150), fill=STEEL)
    for k, x in enumerate((180, 1868)):                                 # shake marks
        sgn = -1 if k == 0 else 1
        for j in range(3):
            d.line([(x - sgn * 40 * j, 820 + 160 * j), (x + sgn * 60 - sgn * 40 * j, 900 + 160 * j)], fill=YELLOW, width=40)
    return img


# ---------------------------------------------------------------- 4. Call button
def call_button():
    img, d = canvas((244, 237, 226), (214, 206, 194))
    for r, a in ((820, 0.25), (660, 0.45)):                             # pulse rings
        col = tuple(int(CREAM[i] * (1 - a) + CORAL[i] * a) for i in range(3))
        d.ellipse((1024 - r, 1024 - r, 1024 + r, 1024 + r), outline=col, width=50)
    shadow(img, lambda m: m.ellipse((464, 464, 1584, 1584), fill=255), opacity=70)
    outline(d, "ellipse", (464, 464, 1584, 1584), (58, 64, 78))
    outline(d, "ellipse", (574, 574, 1474, 1474), CORAL)
    # bell
    bell = [(1024, 720), (1250, 900), (1280, 1240), (1340, 1300), (708, 1300), (768, 1240), (798, 900)]
    d.polygon(bell, fill=WHITE)
    d.pieslice((780, 700, 1268, 1180), 180, 360, fill=WHITE)
    d.ellipse((960, 1290, 1088, 1400), fill=WHITE)
    d.ellipse((990, 650, 1058, 720), fill=WHITE)
    return img


# ---------------------------------------------------------------- 5. Tipping tray
def tray():
    img, d = canvas((90, 150, 200), (30, 60, 110))
    waves(d, [500, 1500], base=(70, 120, 180))
    rot = Image.new("RGBA", (S, S), (0, 0, 0, 0))
    r = ImageDraw.Draw(rot)
    r.rounded_rectangle((300, 1180, 1748, 1300), radius=50, fill=STEEL, outline=NAVY, width=LW)
    # coffee cup
    r.rounded_rectangle((460, 820, 820, 1180), radius=60, fill=WHITE, outline=NAVY, width=LW)
    r.rectangle((480, 850, 800, 920), fill=(107, 62, 38))
    # soda glass
    r.polygon([(1180, 640), (1520, 640), (1480, 1180), (1220, 1180)], fill=WHITE, outline=NAVY, width=LW)
    r.polygon([(1196, 820), (1504, 820), (1480, 1160), (1220, 1160)], fill=(122, 59, 34))
    r.line([(1380, 700), (1460, 440)], fill=CORAL, width=44)
    rot = rot.rotate(-14, center=(1024, 1100), resample=Image.BICUBIC)
    img.paste(rot, (0, 0), rot)
    d = ImageDraw.Draw(img)
    for x, y, rr in ((1700, 1500, 70), (1780, 1700, 50), (1640, 1760, 40)):   # splash drops
        outline(d, "ellipse", (x - rr, y - rr * 1.3, x + rr, y + rr), (122, 59, 34), w=20)
    for x in (380, 1620):
        d.arc((x - 140, 440, x + 140, 720), 200, 340, fill=WHITE, width=36)   # wobble marks
    return img


# ---------------------------------------------------------------- 6. Cabin cutaway (straight)
def cabin():
    img, d = canvas()
    waves(d, [300, 1100, 1800])
    shadow(img, lambda m: m.rounded_rectangle((740, 150, 1308, 1900), radius=284, fill=255))
    poly(d, [(820, 900), (160, 1160), (180, 1280), (820, 1160)], STEEL)      # wings
    poly(d, [(1228, 900), (1888, 1160), (1868, 1280), (1228, 1160)], STEEL)
    outline(d, "rounded_rectangle", (740, 150, 1308, 1900), CREAM, radius=284)
    d.rectangle((1004, 360, 1044, 1780), fill=CORAL)                          # aisle
    for row in range(10):
        y = 420 + row * 130
        for x in (820, 900, 1108, 1188):
            d.rounded_rectangle((x, y, x + 62, y + 90), radius=14, fill=NAVY)
    icons = [(840, 560, RED), (1170, 1000, YELLOW), (840, 1400, TEAL)]
    for x, y, c in icons:
        outline(d, "ellipse", (x - 120, y - 120, x + 120, y + 120), c, w=26)
        d.rounded_rectangle((x - 16, y - 70, x + 16, y + 20), radius=14, fill=WHITE)
        d.ellipse((x - 18, y + 40, x + 18, y + 76), fill=WHITE)
    return img


# ---------------------------------------------------------------- 7. Monogram "T" tail fin
def monogram():
    img, d = canvas(CORAL, (190, 56, 40))
    waves(d, [520, 1560], base=CORAL, shade=0.12)
    shadow(img, lambda m: m.polygon([(560, 1720), (900, 380), (1560, 380), (1340, 700), (1140, 700), (980, 1720)], fill=255))
    poly(d, [(560, 1720), (900, 380), (1560, 380), (1340, 700), (1140, 700), (980, 1720)], CREAM)
    d.polygon([(700, 1180), (820, 720), (1000, 720), (880, 1180)], fill=TEAL)    # stripe
    d.line([(560, 1720), (980, 1720)], fill=NAVY, width=LW)
    for i, y in enumerate((1500, 1640, 1780)):
        pts = [(x, y + 30 * math.sin((x + i * 90) / 70)) for x in range(1100, 1900, 10)]
        d.line(pts, fill=WHITE, width=34, joint="curve")
    return img


# ---------------------------------------------------------------- 8. Drinks cart
def cart():
    img, d = canvas((58, 104, 160), (20, 36, 72))
    d.rectangle((0, 1620, S, S), fill=(76, 58, 70))
    d.rectangle((0, 1620, S, 1660), fill=CORAL)
    rot = Image.new("RGBA", (S, S), (0, 0, 0, 0))
    r = ImageDraw.Draw(rot)
    r.rounded_rectangle((560, 700, 1488, 1560), radius=60, fill=STEEL, outline=NAVY, width=LW)
    r.rounded_rectangle((620, 780, 1428, 1060), radius=30, fill=(140, 148, 160), outline=NAVY, width=24)
    r.rounded_rectangle((620, 1120, 1428, 1480), radius=30, fill=(140, 148, 160), outline=NAVY, width=24)
    r.rectangle((560, 1060, 1488, 1110), fill=CORAL)
    for k, (x, c) in enumerate(((700, (95, 168, 217)), (900, (242, 155, 48)), (1100, (122, 59, 34)), (1300, (95, 174, 91)))):
        r.rounded_rectangle((x - 50, 420 + (k % 2) * 60, x + 50, 700), radius=30, fill=c, outline=NAVY, width=22)
    for x in (680, 1368):
        r.ellipse((x - 70, 1540, x + 70, 1680), fill=NAVY)
    rot = rot.rotate(8, center=(1024, 1600), resample=Image.BICUBIC)
    img.paste(rot, (0, 0), rot)
    d = ImageDraw.Draw(img)
    for y in (900, 1060, 1220):
        d.line([(260, y), (440, y)], fill=WHITE, width=34)                 # speed lines
    return img


# ---------------------------------------------------------------- 9. Window view
def window():
    img, d = canvas((226, 220, 210), (200, 194, 184))
    shadow(img, lambda m: m.rounded_rectangle((440, 240, 1608, 1808), radius=520, fill=255), opacity=80)
    outline(d, "rounded_rectangle", (440, 240, 1608, 1808), (240, 236, 228), radius=520)
    sky = Image.new("RGB", (S, S))
    sd = ImageDraw.Draw(sky)
    for y in range(S):
        t = y / S
        sd.line([(0, y), (S, y)], fill=(int(120 * (1 - t) + 40 * t), int(180 * (1 - t) + 70 * t), int(230 * (1 - t) + 130 * t)))
    for cx, cy, rr in ((700, 1200, 260), (1000, 1150, 300), (1320, 1230, 240), (860, 1380, 280), (1200, 1420, 300)):
        sd.ellipse((cx - rr, cy - rr * 0.6, cx + rr, cy + rr * 0.6), fill=WHITE)
    sd.polygon([(1120, 380), (900, 820), (1040, 820), (920, 1120), (1260, 660), (1100, 660), (1240, 380)], fill=YELLOW)
    sky = sky.rotate(-12, center=(1024, 1024), resample=Image.BICUBIC)
    mask = Image.new("L", (S, S), 0)
    ImageDraw.Draw(mask).rounded_rectangle((560, 360, 1488, 1688), radius=440, fill=255)
    img.paste(sky, (0, 0), mask)
    d = ImageDraw.Draw(img)
    d.rounded_rectangle((560, 360, 1488, 1688), radius=440, outline=NAVY, width=LW)
    d.rounded_rectangle((640, 300, 1408, 420), radius=50, fill=(240, 236, 228), outline=NAVY, width=24)   # blind
    return img


# ---------------------------------------------------------------- 10. Plane through the bumps
def zigzag():
    img, d = canvas((31, 138, 140), (14, 70, 80))
    path = [(140, 1720), (480, 1320), (720, 1600), (1000, 1140)]
    for k in range(len(path) - 1):
        d.line([path[k], path[k + 1]], fill=(230, 245, 240), width=46)
    for x, y in path[:-1]:
        d.ellipse((x - 23, y - 23, x + 23, y + 23), fill=(230, 245, 240))
    plane = Image.new("RGBA", (S, S), (0, 0, 0, 0))
    p = ImageDraw.Draw(plane)
    p.rounded_rectangle((924, 540, 1124, 1500), radius=100, fill=CREAM, outline=NAVY, width=LW)
    p.polygon([(924, 900), (440, 1160), (460, 1260), (924, 1080)], fill=STEEL, outline=NAVY, width=LW)
    p.polygon([(1124, 900), (1608, 1160), (1588, 1260), (1124, 1080)], fill=STEEL, outline=NAVY, width=LW)
    p.polygon([(960, 1360), (760, 1500), (780, 1560), (1024, 1470), (1268, 1560), (1288, 1500), (1088, 1360)],
              fill=STEEL, outline=NAVY, width=LW)
    p.rectangle((1004, 700, 1044, 1380), fill=CORAL)
    p.rounded_rectangle((980, 600, 1068, 660), radius=20, fill=NAVY)
    plane = plane.resize((1300, 1300), Image.BICUBIC).rotate(-45, resample=Image.BICUBIC, expand=False)
    img.paste(plane, (660, 180), plane)
    return img



# ---------------------------------------------------------------- Variations on 10 (bumpy route)
def plane_sprite(size, angle, stripe=CORAL, body=CREAM):
    """The top-down plane, nose up, scaled to `size` px and rotated (degrees, clockwise)."""
    plane = Image.new("RGBA", (S, S), (0, 0, 0, 0))
    p = ImageDraw.Draw(plane)
    p.rounded_rectangle((924, 540, 1124, 1500), radius=100, fill=body, outline=NAVY, width=LW)
    p.polygon([(924, 900), (440, 1160), (460, 1260), (924, 1080)], fill=STEEL, outline=NAVY, width=LW)
    p.polygon([(1124, 900), (1608, 1160), (1588, 1260), (1124, 1080)], fill=STEEL, outline=NAVY, width=LW)
    p.polygon([(960, 1360), (760, 1500), (780, 1560), (1024, 1470), (1268, 1560), (1288, 1500), (1088, 1360)],
              fill=STEEL, outline=NAVY, width=LW)
    p.rectangle((1004, 700, 1044, 1380), fill=stripe)
    p.rounded_rectangle((980, 600, 1068, 660), radius=20, fill=NAVY)
    return plane.resize((size, size), Image.BICUBIC).rotate(-angle, resample=Image.BICUBIC)


def put(img, sprite, cx, cy):
    img.paste(sprite, (int(cx - sprite.width / 2), int(cy - sprite.height / 2)), sprite)


def bumpy(x0, y0, x1, y1, amp, waves_n, step=6):
    """A wobbly path from (x0, y0) to (x1, y1)."""
    n = int(math.hypot(x1 - x0, y1 - y0) / step)
    dx, dy = (x1 - x0) / n, (y1 - y0) / n
    L = math.hypot(dx, dy)
    nx, ny = -dy / L, dx / L
    return [(x0 + dx * k + nx * amp * math.sin(k / n * waves_n * 2 * math.pi),
             y0 + dy * k + ny * amp * math.sin(k / n * waves_n * 2 * math.pi)) for k in range(n + 1)]


def dashed(d, pts, fill, width, on=10, off=7):
    for k in range(0, len(pts) - on, on + off):
        d.line(pts[k:k + on], fill=fill, width=width, joint="curve")


def v_sunset():
    """10a: dusk sky, dashed wobbly trail, big plane."""
    img, d = canvas((240, 128, 88), (40, 44, 92))
    d.ellipse((1180, 1180, 1780, 1780), fill=(248, 196, 110))
    waves(d, [1500, 1720], base=(120, 80, 110), shade=0.18)
    dashed(d, bumpy(120, 1900, 950, 1100, 70, 2.5), WHITE, 44)
    put(img, plane_sprite(1700, 45), 1250, 800)
    return img


def v_lightning():
    """10b: the trail is a lightning bolt."""
    img, d = canvas((28, 40, 74), (8, 12, 28))
    waves(d, [420, 1500], base=(28, 40, 74), shade=0.08)
    bolt = [(180, 1860), (620, 1340), (500, 1330), (900, 900), (780, 890), (1080, 620),
            (860, 1060), (990, 1070), (700, 1420), (830, 1430)]
    glow = Image.new("RGB", (S, S), (0, 0, 0))
    ImageDraw.Draw(glow).polygon(bolt, fill=YELLOW)
    img.paste(Image.blend(img, glow.filter(ImageFilter.GaussianBlur(50)), 0.3))
    d = ImageDraw.Draw(img)
    d.polygon(bolt, fill=YELLOW, outline=NAVY, width=LW)
    put(img, plane_sprite(1500, 45), 1340, 400)
    return img


def v_pulse():
    """10c: cream card, the route drawn as a heartbeat line in coral."""
    img, d = canvas((246, 241, 232), (226, 219, 206))
    pts = [(120, 1050), (500, 1050), (620, 700), (760, 1400), (900, 870), (1020, 1050), (1220, 1050)]
    d.line(pts, fill=CORAL, width=70, joint="curve")
    for x, y in (pts[0],):
        d.ellipse((x - 35, y - 35, x + 35, y + 35), fill=CORAL)
    put(img, plane_sprite(1400, 90, stripe=TEAL), 1560, 1050)
    return img


def v_clouds():
    """10d: bright day, plane dead centre bouncing over puffy clouds, curly trail."""
    img, d = canvas((96, 176, 232), (46, 110, 190))
    for cx, cy, r in ((380, 1640, 260), (700, 1720, 300), (1100, 1690, 280), (1480, 1740, 320), (1800, 1660, 260),
                      (260, 420, 160), (1760, 380, 180)):
        outline(d, "ellipse", (cx - r, cy - r * 0.62, cx + r, cy + r * 0.62), WHITE, w=26)
    trail = bumpy(80, 1260, 790, 1115, 90, 3)
    d.line(trail, fill=WHITE, width=50, joint="curve")
    put(img, plane_sprite(1700, 60), 1150, 900)
    return img


def v_route_map():
    """10e: the route map: navy sea, cream land, a coral bumpy arc between city pins."""
    img, d = canvas((30, 48, 86), (18, 30, 58))
    d.ellipse((-300, 1100, 900, 2300), fill=(226, 218, 200))
    d.ellipse((1300, -300, 2400, 900), fill=(226, 218, 200))
    route = bumpy(420, 1520, 1500, 520, 60, 3.5)
    dashed(d, route, CORAL, 48, on=9, off=6)
    for x, y in ((420, 1520),):
        outline(d, "ellipse", (x - 90, y - 90, x + 90, y + 90), TEAL, w=26)
        d.ellipse((x - 30, y - 30, x + 30, y + 30), fill=CREAM)
    pin = [(1640, 700), (1520, 470), (1540, 380), (1640, 320), (1740, 380), (1760, 470)]
    outline(d, "ellipse", (1540, 300, 1740, 500), CORAL, w=26)
    d.polygon([(1560, 460), (1640, 640), (1720, 460)], fill=CORAL, outline=NAVY, width=26)
    d.ellipse((1600, 360, 1680, 440), fill=CREAM)
    put(img, plane_sprite(1300, 45), 1000, 1010)
    return img


def cart_sprite(size, angle):
    """The drinks trolley (front view) with bottles on top, scaled and tilted (degrees, clockwise)."""
    c = Image.new("RGBA", (S, S), (0, 0, 0, 0))
    r = ImageDraw.Draw(c)
    r.rounded_rectangle((560, 700, 1488, 1560), radius=60, fill=STEEL, outline=NAVY, width=LW)
    r.rounded_rectangle((620, 780, 1428, 1060), radius=30, fill=(140, 148, 160), outline=NAVY, width=24)
    r.rounded_rectangle((620, 1120, 1428, 1480), radius=30, fill=(140, 148, 160), outline=NAVY, width=24)
    r.rectangle((560, 1060, 1488, 1110), fill=CORAL)
    for k, (x, col) in enumerate(((700, (95, 168, 217)), (900, (242, 155, 48)), (1100, (122, 59, 34)), (1300, (95, 174, 91)))):
        r.rounded_rectangle((x - 50, 420 + (k % 2) * 60, x + 50, 700), radius=30, fill=col, outline=NAVY, width=22)
    for x in (680, 1368):
        r.ellipse((x - 70, 1540, x + 70, 1680), fill=NAVY)
    return c.resize((size, size), Image.BICUBIC).rotate(-angle, resample=Image.BICUBIC)


def speed_lines(d, x, y, n=3, length=180, gap=90, col=WHITE, width=34):
    for k in range(n):
        d.line([(x, y + k * gap), (x + length - k * 40, y + k * gap)], fill=col, width=width)


def mix_chase():
    """8+10 A: a huge plane climbs the bumpy route; the drinks cart chases along the trail below."""
    img, d = canvas((31, 138, 140), (14, 70, 80))
    waves(d, [420, 1560], base=(31, 138, 140), shade=0.08)
    trail = [(560, 1430), (660, 1230), (780, 1350), (894, 1146)]
    d.line(trail, fill=(230, 245, 240), width=50, joint="curve")
    for x, y in trail[:-1]:
        d.ellipse((x - 25, y - 25, x + 25, y + 25), fill=(230, 245, 240))
    put(img, plane_sprite(2300, 45), 1300, 740)
    put(img, cart_sprite(1050, 14), 480, 1500)
    return img


def mix_spill():
    """8+10 B: the cart fills the foreground, bottles flying off as the big plane bumps overhead."""
    img, d = canvas((31, 138, 140), (14, 70, 80))
    waves(d, [700, 1000], amp=50, base=(31, 138, 140), shade=0.14, width=44)
    route = [(1064, 816), (900, 900), (820, 700), (620, 820)]
    put(img, plane_sprite(1900, 45), 1400, 480)
    put(img, cart_sprite(1500, -10), 900, 1380)
    d = ImageDraw.Draw(img)
    for x, y, a, col in ((420, 700, -35, (95, 174, 91)), (680, 480, -70, (242, 155, 48))):   # bottles in the air
        b = Image.new("RGBA", (400, 400), (0, 0, 0, 0))
        ImageDraw.Draw(b).rounded_rectangle((150, 60, 250, 340), radius=40, fill=col, outline=NAVY, width=22)
        put(img, b.rotate(-a, resample=Image.BICUBIC), x, y)
    d = ImageDraw.Draw(img)
    for x, y in ((520, 860), (760, 640)):
        d.arc((x - 80, y - 80, x + 80, y + 80), 200, 320, fill=WHITE, width=30)
    return img


def mix_rollercoaster():
    """8+10 C: the cart rides the bumpy route like a rollercoaster up to a big plane."""
    img, d = canvas((31, 138, 140), (14, 70, 80))
    route = [(-40, 1480), (300, 1700), (760, 1540), (980, 1200), (1066, 1061)]
    d.line(route, fill=CORAL, width=90, joint="curve")
    d.line(route, fill=(230, 245, 240), width=30, joint="curve")
    put(img, plane_sprite(2200, 40), 1420, 640)
    put(img, cart_sprite(1000, -19), 438, 1354)
    return img


MIXES = [
    ("mix-a-cart-chase", "A. Cart chases the plane", mix_chase),
    ("mix-b-cart-spill", "B. Bottles flying", mix_spill),
    ("mix-c-cart-coaster", "C. Cart coaster", mix_rollercoaster),
]

VARIATIONS = [
    ("10a-sunset-trail", "10a. Sunset trail", v_sunset),
    ("10b-lightning", "10b. Lightning trail", v_lightning),
    ("10c-heartbeat", "10c. Heartbeat route", v_pulse),
    ("10d-cloud-hop", "10d. Cloud hop", v_clouds),
    ("10e-route-map", "10e. Route map", v_route_map),
]


CONCEPTS = [
    ("01-attendant", "The attendant", attendant),
    ("02-coffee", "Coffee under pressure", coffee),
    ("03-seatbelt", "Seatbelt sign", seatbelt),
    ("04-call-button", "Call button", call_button),
    ("05-tipping-tray", "Tipping tray", tray),
    ("06-cabin", "Cabin cutaway", cabin),
    ("07-tail-fin", "Tail-fin monogram", monogram),
    ("08-drinks-cart", "Runaway drinks cart", cart),
    ("09-window", "Stormy window", window),
    ("10-bumpy-route", "Bumpy route", zigzag),
]


def rounded_mask(size, r):
    m = Image.new("L", (size, size), 0)
    ImageDraw.Draw(m).rounded_rectangle((0, 0, size - 1, size - 1), radius=r, fill=255)
    return m


def make_sheet(concepts, name, numbered=True):
    thumbs = []
    for slug, title, fn in concepts:
        icon = fn().resize((1024, 1024), Image.LANCZOS)
        icon.save(os.path.join(OUT, slug + ".png"))
        thumbs.append((title, icon.resize((300, 300), Image.LANCZOS)))
    cols, pad, cell_h = 5, 40, 380
    rows = (len(thumbs) + cols - 1) // cols
    sheet = Image.new("RGB", (cols * (300 + pad) + pad, rows * cell_h + pad), (244, 239, 230))
    sd = ImageDraw.Draw(sheet)
    f = font(22)
    for k, (title, t) in enumerate(thumbs):
        x = pad + (k % cols) * (300 + pad)
        y = pad + (k // cols) * cell_h
        sheet.paste(t, (x, y), rounded_mask(300, 66))
        label = f"{k + 1}. {title}" if numbered else title
        w = sd.textlength(label, font=f)
        sd.text((x + (300 - w) / 2, y + 312), label, fill=NAVY, font=f)
    path = os.path.join(OUT, name)
    sheet.save(path)
    print("wrote", len(thumbs), "icons +", os.path.abspath(path))


if __name__ == "__main__":
    import sys
    os.makedirs(OUT, exist_ok=True)
    if "--mix" in sys.argv:
        make_sheet(MIXES, "sheet-8-10-mix.png", numbered=False)
    elif "--variations" in sys.argv:
        make_sheet(VARIATIONS, "sheet-10-variations.png", numbered=False)
    else:
        make_sheet(CONCEPTS, "sheet.png")

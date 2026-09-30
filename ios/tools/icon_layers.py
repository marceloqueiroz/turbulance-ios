"""Layer artwork for the Icon Composer app icon: a big plane climbing out of a bumpy flight path.

Each layer is a transparent 1024×1024 PNG so Icon Composer can light it as Liquid Glass.
The background colour lives in icon.json, not in a layer.

Usage: python3 ios/tools/icon_layers.py → branding/app-icon-layers/*.png
"""
import math
import os
from PIL import Image, ImageDraw

from icon_options import S, NAVY, CORAL, CREAM, STEEL, WHITE, LW, plane_sprite, bumpy

OUT = os.path.join(os.path.dirname(__file__), "..", "..", "branding", "app-icon-layers")


def layer():
    return Image.new("RGBA", (S, S), (0, 0, 0, 0))


def save(img, name):
    img.resize((1024, 1024), Image.LANCZOS).save(os.path.join(OUT, name))


def airliner():
    """A chunky top-down airliner, nose up, centred on the 2048 canvas: wide body, pointed nose,
    big swept wings with engines and a clear tail, so it reads as a plane even at icon size."""
    img = layer()
    d = ImageDraw.Draw(img)
    cx = 1024
    wing = [(cx - 110, 820), (cx - 930, 1230), (cx - 930, 1340), (cx - 110, 1130),
            (cx + 110, 1130), (cx + 930, 1340), (cx + 930, 1230), (cx + 110, 820)]
    d.polygon(wing, fill=STEEL, outline=NAVY, width=LW)
    for sx in (-1, 1):                                                     # wingtips in livery coral
        d.polygon([(cx + sx * 930, 1230), (cx + sx * 830, 1280), (cx + sx * 830, 1315), (cx + sx * 930, 1340)],
                  fill=CORAL, outline=NAVY, width=24)
    for sx in (-1, 1):                                                     # engines under the wings
        ex = cx + sx * 460
        d.rounded_rectangle((ex - 62, 930, ex + 62, 1170), radius=50, fill=(120, 128, 142), outline=NAVY, width=LW)
        d.ellipse((ex - 44, 940, ex + 44, 1000), fill=(60, 66, 80))
    stab = [(cx - 70, 1600), (cx - 400, 1790), (cx - 400, 1860), (cx - 70, 1760),
            (cx + 70, 1760), (cx + 400, 1860), (cx + 400, 1790), (cx + 70, 1600)]
    d.polygon(stab, fill=STEEL, outline=NAVY, width=LW)
    body = [(cx, 170)]                                                     # pointed ogive nose → wide body → tapered tail
    for k in range(1, 11):
        t = k / 10
        body.append((cx + 140 * math.sin(t * math.pi / 2), 170 + 330 * t))
    body += [(cx + 140, 1420), (cx + 60, 1860), (cx - 60, 1860), (cx - 140, 1420)]
    for k in range(10, 0, -1):
        t = k / 10
        body.append((cx - 140 * math.sin(t * math.pi / 2), 170 + 330 * t))
    d.polygon(body, fill=CREAM, outline=NAVY, width=LW)
    d.polygon([(cx - 70, 330), (cx, 290), (cx + 70, 330), (cx + 62, 380), (cx - 62, 380)], fill=NAVY)   # cockpit glass
    d.polygon([(cx - 28, 1560), (cx + 28, 1560), (cx + 34, 1850), (cx - 34, 1850)], fill=CORAL)       # tail fin, from above
    for k in range(12):                                                   # a row of windows on each side
        y = 520 + k * 72
        for sx in (-1, 1):
            d.rounded_rectangle((cx + sx * 88 - 14, y, cx + sx * 88 + 14, y + 34), radius=10, fill=(110, 170, 200))
    return img


PLANE_SCALE = 0.9


def placed_plane():
    """The airliner, big, nose to the top right."""
    img = layer()
    plane = airliner().rotate(-45, resample=Image.BICUBIC, center=(1024, 1024))
    k = PLANE_SCALE
    plane = plane.resize((int(S * k), int(S * k)), Image.LANCZOS)
    off = int(S * (1 - k) / 2)
    img.alpha_composite(plane, (off + 40, off - 40))
    return img


def contrails():
    """Two bumpy contrails streaming back from the engines to the lower left."""
    img = layer()
    d = ImageDraw.Draw(img)
    # engine positions after rotating the plane 45° about the centre and shifting by (40, -40)
    def rot(x, y):
        a = math.radians(45)
        dx, dy = x - 1024, y - 1024
        k = PLANE_SCALE
        return (1024 + k * (dx * math.cos(a) - dy * math.sin(a)) + 40, 1024 + k * (dx * math.sin(a) + dy * math.cos(a)) - 40)
    r = 30
    for sx in (-1, 1):
        x0, y0 = rot(1024 + sx * 460, 1190)
        x1, y1 = x0 - 700, y0 + 700
        for k, (x, y) in enumerate(bumpy(x0, y0, x1, y1, 38, 2.5, step=3)):
            rr = r * (1 - 0.45 * k / 330)
            d.ellipse((x - rr, y - rr, x + rr, y + rr), fill=WHITE)
    return img


if __name__ == "__main__":
    os.makedirs(OUT, exist_ok=True)
    save(contrails(), "trail.png")
    save(placed_plane(), "plane.png")
    # a flat preview on the teal background (the real one is rendered by Icon Composer)
    bg = Image.new("RGBA", (S, S))
    bd = ImageDraw.Draw(bg)
    for y in range(S):
        t = y / S
        bd.line([(0, y), (S, y)], fill=(int(40 * (1 - t) + 14 * t), int(160 * (1 - t) + 70 * t), int(160 * (1 - t) + 84 * t), 255))
    for part in (contrails(), placed_plane()):
        bg.alpha_composite(part)
    save(bg, "preview-flat.png")
    print("wrote layers to", os.path.abspath(OUT))

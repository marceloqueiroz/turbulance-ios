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


def clouds():
    """Two small cloud puffs low in the sky, one each side."""
    img = layer()
    d = ImageDraw.Draw(img)
    for bank in ([(300, 1760, 150), (470, 1720, 190), (640, 1780, 140)],
                 [(1420, 1820, 150), (1600, 1770, 190), (1780, 1830, 140)]):
        for cx, cy, r in bank:
            d.ellipse((cx - r, cy - r * 0.62, cx + r, cy + r * 0.62), fill=WHITE)
        xs = [c[0] for c in bank]
        d.rectangle((min(xs), bank[1][1], max(xs), bank[1][1] + 60), fill=WHITE)
    return img


def trail():
    """The bumpy flight path, from the lower left up to the plane's tail (stamped for smooth edges)."""
    img = layer()
    d = ImageDraw.Draw(img)
    r = 38
    for x, y in bumpy(210, 1540, 800, 1060, 95, 2.5, step=3):
        d.ellipse((x - r, y - r, x + r, y + r), fill=WHITE)
    return img


def plane():
    """The plane, big: nose to the top right, tail meeting the trail."""
    img = layer()
    sprite = plane_sprite(2500, 45, stripe=CORAL, body=CREAM)
    img.paste(sprite, (int(1210 - sprite.width / 2), int(800 - sprite.height / 2)), sprite)
    return img


if __name__ == "__main__":
    os.makedirs(OUT, exist_ok=True)
    save(clouds(), "clouds.png")
    save(trail(), "trail.png")
    save(plane(), "plane.png")
    # a flat preview on the teal background (the real one is rendered by Icon Composer)
    bg = Image.new("RGBA", (S, S))
    bd = ImageDraw.Draw(bg)
    for y in range(S):
        t = y / S
        bd.line([(0, y), (S, y)], fill=(int(40 * (1 - t) + 14 * t), int(160 * (1 - t) + 70 * t), int(160 * (1 - t) + 84 * t), 255))
    for part in (clouds(), trail(), plane()):
        bg.alpha_composite(part)
    save(bg, "preview-flat.png")
    print("wrote layers to", os.path.abspath(OUT))

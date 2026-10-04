"""Checks (and with --fix, repairs) the city-life paths in MapLayout.json against the region art.

Rules (Route Map Plan, City life):
  walk  - on land, at least LAND_MARGIN from any water (no one strolls along the waterline)
  road  - on land, at least ROAD_MARGIN from water
  water - on water, at least WATER_MARGIN from land; moored points too
  air, smoke, glow - anywhere

Water is found in the art itself: the open sea is transparent, and harbours, shallows, lakes and rivers
are blue-green pixels in large connected areas (or touching the sea). Teal roofs are blue-green too, but
they are small separate blobs, so they don't count.

A point that breaks its rule is moved to the nearest pixel that keeps it (within SEARCH); anything still
wrong is reported. Also flags actors whose paths come too close to another path (crowding).

Usage: python3 ios/tools/check_life.py [--fix]
Needs numpy and Pillow.
"""
import json
import sys
from collections import deque

import numpy as np
from PIL import Image

ROOT = __file__.rsplit("/ios/tools/", 1)[0]
LAYOUT = f"{ROOT}/ios/Turbulence/MapLayout.json"
W = 1000                                    # analysis width; margins below are in these pixels
LAND_MARGIN, ROAD_MARGIN, WATER_MARGIN, SEARCH, CROWD = 14, 10, 10, 60, 18


def masks(region_id):
    im = Image.open(f"{ROOT}/branding/map/cut/region-{region_id}.png").convert("RGBA")
    im = im.resize((W, round(W * im.height / im.width)), Image.LANCZOS)
    a = np.asarray(im).astype(np.int16)
    r, g, b, alpha = a[..., 0], a[..., 1], a[..., 2], a[..., 3]
    sea = alpha < 110
    # water is blue-green (harbours, shallows, lakes, rivers) in large connected areas; teal roofs are small blobs
    tinted = (g - r > 25) & (b - r > 25) & (np.abs(g - b) < 50)
    h, w = sea.shape
    water = sea.copy()
    label = np.zeros((h, w), dtype=bool)
    for y0, x0 in zip(*np.nonzero(tinted)):
        if label[y0, x0]: continue
        blob, q = [], deque([(y0, x0)])
        label[y0, x0] = True
        touches_sea = False
        while q:
            y, x = q.popleft()
            blob.append((y, x))
            for dy, dx in ((1, 0), (-1, 0), (0, 1), (0, -1)):
                ny, nx = y + dy, x + dx
                if 0 <= ny < h and 0 <= nx < w:
                    if sea[ny, nx]: touches_sea = True
                    elif tinted[ny, nx] and not label[ny, nx]:
                        label[ny, nx] = True
                        q.append((ny, nx))
        if touches_sea or len(blob) >= 300:
            ys, xs = zip(*blob)
            water[list(ys), list(xs)] = True
    return water, distance(water), distance(~water)


def distance(mask):
    """City-block distance from every pixel to the nearest True pixel in mask (two-pass)."""
    h, w = mask.shape
    big = h + w
    d = np.where(mask, 0, big).astype(np.int32)
    for y in range(h):
        row = d[y]
        if y: row = np.minimum(row, d[y - 1] + 1)
        for x in range(1, w): row[x] = min(row[x], row[x - 1] + 1)
        for x in range(w - 2, -1, -1): row[x] = min(row[x], row[x + 1] + 1)
        d[y] = row
    for y in range(h - 2, -1, -1):
        row = np.minimum(d[y], d[y + 1] + 1)
        for x in range(1, w): row[x] = min(row[x], row[x - 1] + 1)
        for x in range(w - 2, -1, -1): row[x] = min(row[x], row[x + 1] + 1)
        d[y] = row
    return d


def ok(kind, x, y, to_water, to_land, extra=0):
    if kind == "walk": return to_water[y, x] >= LAND_MARGIN + extra
    if kind == "road": return to_water[y, x] >= ROAD_MARGIN + extra
    if kind in ("water", "moored"): return to_land[y, x] >= WATER_MARGIN + extra
    return True


def main():
    fix = "--fix" in sys.argv
    layout = json.load(open(LAYOUT))
    problems = moved = 0
    for region in layout["regions"]:
        life = region.get("life")
        if not life: continue
        water, to_water, to_land = masks(region["id"])
        h, w = water.shape
        for entry in life:
            for p in entry["points"]:
                x, y = min(w - 1, int(p[0] * w)), min(h - 1, int(p[1] * h))
                if ok(entry["kind"], x, y, to_water, to_land): continue
                best = None
                for yy in range(max(0, y - SEARCH), min(h, y + SEARCH)):
                    for xx in range(max(0, x - SEARCH), min(w, x + SEARCH)):
                        if ok(entry["kind"], xx, yy, to_water, to_land, extra=4):       # land fixes well inside, so rounding can't undo them
                            dd = (xx - x) ** 2 + (yy - y) ** 2
                            if best is None or dd < best[0]: best = (dd, xx, yy)
                if best and fix:
                    p[0], p[1] = round(best[1] / w, 3), round(best[2] / h, 3)
                    moved += 1
                else:
                    problems += 1
                    print(f"{region['id']} {entry['kind']} point {p} breaks its rule" + ("" if best else " (no fix nearby)"))
        # crowding: moving paths that pass too close to each other
        moving = [e for e in life if e["kind"] in ("walk", "road", "water")]
        for i, a in enumerate(moving):
            for b in moving[i + 1:]:
                close = min(((pa[0] - pb[0]) * w) ** 2 + ((pa[1] - pb[1]) * h) ** 2 for pa in a["points"] for pb in b["points"]) ** 0.5
                if close < CROWD:
                    print(f"{region['id']} crowded: {a['kind']} {a['points'][0]} and {b['kind']} {b['points'][0]} are {close:.0f}px apart")
    if fix and moved:
        text = open(LAYOUT).read()
        head, tail = text.split('  "regions": [', 1)
        regions_text, airports = tail.split('  ],\n  "airports"', 1)
        lines = []
        for i, r in enumerate(layout["regions"]):
            life = r.pop("life", None)
            line = "    " + json.dumps(r)[:-1]
            line += (',\n      "life": [\n' + ",\n".join("        " + json.dumps(l) for l in life) + "\n      ]\n    }") if life else "}"
            lines.append(line + ("," if i < len(layout["regions"]) - 1 else ""))
        open(LAYOUT, "w").write(head + '  "regions": [\n' + "\n".join(lines) + '\n  ],\n  "airports"' + airports)
    print(f"{moved} points moved, {problems} problems left")
    sys.exit(1 if problems else 0)


if __name__ == "__main__":
    main()

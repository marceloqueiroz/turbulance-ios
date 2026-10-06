"""Draws the 6 x 4 pose-guide grid (24 frames) Gemini paints over: the real head locked in every cell,
a grey mannequin body, near/left limbs BLUE, far/right limbs ORANGE, dark shoes, white hands.

The walk follows the four key poses per step (contact, down, passing, up) for both legs, so 8 keys over
24 frames; frames 0-11 step with one leg, 12-23 with the other, and frame 23 flows into frame 0.

Usage:
  pose_guide.py --view side  --head head.png --out grid.png [--stride 42 --lift 24 --bob 9 --head-h 310]
  pose_guide.py --view front --head head.png --out grid.png
  pose_guide.py --view back  --head head.png --out grid.png
Also writes <out>-peek.png (first row) and <out>.gif (the guide animated): look at both before generating.

Proportions are the approved chibi attendant (head ~55% of the height, body ~35%, legs ~10%). Gemini copies
the guide's proportions literally, so for a new character match ITS approved sprite: edit BODY below.
"""
import argparse, math
from PIL import Image, ImageDraw

CW, CH, SS = 682, 768, 2                      # cell = 1/6 x 1/4 of the 4096 x 3072 grid; supersampled
BLUE, ORANGE, CLAY, DARK, WHITE = (60, 110, 210), (235, 140, 50), (200, 194, 186), (90, 84, 80), (245, 245, 245)
# side view body, in cell px: short legs, round torso, arms from just under the head
BODY = dict(ground=700, thigh=34, shin=32, torso=(4, -88, 96, 98), shoulder=-128, upper_arm=42, forearm=36,
            arm_swing=38, head_gap=40)
# front/back body, in px of the attendant's approved front sprite (846 x 826, centre x 440, feet ~785)
FB = dict(scale=0.72, cx=440, feet_y=785, hip_l=345, hip_r=535, skirt_y=730, torso=(440, 610, 235, 185),
          shoulder_l=(215, 430), shoulder_r=(665, 430), hand_l=115, hand_r=765, hand_y=575, depth=0.55)


def leg_state(u, stride, lift):
    """u in [0,1): 0 = heel contact in front; 0-0.5 stance (foot slides back), 0.5-1 swing (lifts, travels forward)."""
    if u < 0.5:
        s = u / 0.5
        return stride * (1 - 2 * s), 0.0, (-18 if s < 0.12 else 0 if s < 0.8 else 25 * (s - 0.8) / 0.2)
    s = (u - 0.5) / 0.5; e = 0.5 - 0.5 * math.cos(math.pi * s)
    return -stride + 2 * stride * e, lift * math.sin(math.pi * s) ** 1.3, 30 * (1 - s) - 18 * s


def bob_at(u, amp):
    """Two bobs per cycle: lowest on the down poses (frames 2, 14), highest on the up poses (8, 20)."""
    return amp * math.cos(2 * math.pi * (u * 2 - 2 / 12))


def side_frame(t, head, a):
    B = BODY
    im = Image.new("RGBA", (CW * SS, CH * SS), (255, 0, 255, 255)); d = ImageDraw.Draw(im)
    P = lambda p: (p[0] * SS, p[1] * SS)

    def line(p, q, w, c):
        d.line([P(p), P(q)], fill=c, width=w * SS)
        for z in (p, q): d.ellipse([P((z[0] - w / 2, z[1] - w / 2)), P((z[0] + w / 2, z[1] + w / 2))], fill=c)

    def ell(cx, cy, rx, ry, c, o=DARK):
        d.ellipse([P((cx - rx, cy - ry)), P((cx + rx, cy + ry))], fill=c, outline=o, width=4 * SS)

    def ik(hip, foot):
        dx, dy = foot[0] - hip[0], foot[1] - hip[1]; L1, L2 = B["thigh"], B["shin"]
        dd = min(math.hypot(dx, dy), L1 + L2 - 0.5)
        k = math.atan2(dy, dx) - math.acos((L1 * L1 + dd * dd - L2 * L2) / (2 * L1 * dd))
        return (hip[0] + L1 * math.cos(k), hip[1] + L1 * math.sin(k))

    u = t / 24; cx = CW / 2
    hipy = B["ground"] - (B["thigh"] + B["shin"]) * 0.93 + bob_at(u, a.bob)
    lean = 3 * math.sin(2 * math.pi * u)
    legs = {}
    for name, ph, depth in (("near", 0, 10), ("far", 0.5, -10)):
        x, lift, toe = leg_state((u + ph) % 1, a.stride, a.lift)
        hip = (cx + (6 if name == "far" else -6), hipy - depth * 0.3)
        foot = (cx + x, B["ground"] + depth - lift)
        legs[name] = (hip, ik(hip, foot), foot, toe, x)

    def draw_leg(name, c):
        hip, knee, foot, toe, _ = legs[name]
        line(hip, knee, 34, c); line(knee, foot, 32, c)
        r = math.radians(toe); line((foot[0] - 8, foot[1]), (foot[0] + 30 * math.cos(r), foot[1] + 30 * math.sin(r)), 24, DARK)

    def draw_arm(name, c, sh):
        x = legs["far" if name == "near" else "near"][4] / a.stride        # each arm swings with the OPPOSITE leg
        r = math.radians(90 - B["arm_swing"] * x); el = (sh[0] + B["upper_arm"] * math.cos(r), sh[1] + B["upper_arm"] * math.sin(r))
        r2 = r - math.radians(20 + 18 * max(0, x)); hand = (el[0] + B["forearm"] * math.cos(r2), el[1] + B["forearm"] * math.sin(r2))
        line(sh, el, 28, c); line(el, hand, 26, c); ell(hand[0], hand[1], 19, 19, WHITE)

    shy = hipy + B["shoulder"]
    draw_arm("far", ORANGE, (cx + 18, shy)); draw_leg("far", ORANGE)
    tx, ty, rx, ry = B["torso"]; ell(cx + tx + lean, hipy + ty, rx, ry, CLAY)
    draw_leg("near", BLUE)
    draw_arm("near", BLUE, (cx - 10, shy))
    im = im.resize((CW, CH), Image.LANCZOS)
    hh = head.resize((round(head.width * a.head_h / head.height), a.head_h), Image.LANCZOS)
    im.alpha_composite(hh, (round(CW / 2 - hh.width / 2), round(hipy - 180 - hh.height + B["head_gap"])))
    return im.convert("RGB")


def fb_frame(t, head, a):
    F = FB; k = F["scale"] * SS
    im = Image.new("RGBA", (CW * SS, CH * SS), (255, 0, 255, 255)); d = ImageDraw.Draw(im)
    u = t / 24; bob = bob_at(u, a.bob); sway = a.sway * math.sin(2 * math.pi * u)
    ox = CW * SS / 2 - F["cx"] * k + sway * k; oy = (CH - 30) * SS - 820 * k + bob * k * 0.5
    P = lambda x, y: (ox + x * k, oy + y * k)
    fwd = 1 if a.view == "front" else -1       # forward = down the screen (front) / up the screen (back)

    def ell(x, y, rx, ry, c, o=DARK):
        (p, q), (r, s) = P(x - rx, y - ry), P(x + rx, y + ry); d.ellipse((p, q, r, s), fill=c, outline=o, width=3 * SS)

    def ln(p, q, w, c):
        d.line([P(*p), P(*q)], fill=c, width=int(w * k))
        for z in (p, q): ell(*z, w / 2, w / 2, c, c)

    feet = {}
    for side, col, x0, ph in (("L", BLUE, F["hip_l"], 0.0), ("R", ORANGE, F["hip_r"], 0.5)):
        fx, lift, _ = leg_state((u + ph) % 1, a.stride * 0.8, a.lift)
        feet[side] = (col, x0, F["feet_y"] + fwd * F["depth"] * fx - lift, fx)
    arms = {}
    for side, col, sh, hx0 in (("L", BLUE, F["shoulder_l"], F["hand_l"]), ("R", ORANGE, F["shoulder_r"], F["hand_r"])):
        fx = feet["R" if side == "L" else "L"][3] / (a.stride * 0.8)
        hy = F["hand_y"] + fwd * 55 * fx; hx = hx0 + (1 if side == "L" else -1) * 18 * fx * fwd
        arms[side] = (col, sh, (hx, hy), fx)
    behind = lambda s: arms[s][3] * fwd < 0    # arm swung away from the camera goes behind the body

    def draw_arm(s):
        col, sh, hand, _ = arms[s]; ln(sh, hand, 70, col); ell(hand[0], hand[1], 48, 48, WHITE)

    for s in "LR":
        if behind(s): draw_arm(s)
    for s in "LR":
        col, x0, y, _ = feet[s]; ln((x0, F["skirt_y"]), (x0, y - 10), 70, col); ell(x0, y + 5, 52, 34, DARK, DARK)
    ell(*F["torso"], CLAY)
    for s in "LR":
        if not behind(s): draw_arm(s)
    hh = head.resize((round(head.width * k), round(head.height * k)), Image.LANCZOS)
    im.alpha_composite(hh, (round(ox), round(oy)))     # the ellipse-cut head keeps the sprite's full canvas
    return im.resize((CW, CH), Image.LANCZOS).convert("RGB")


if __name__ == "__main__":
    ap = argparse.ArgumentParser()
    ap.add_argument("--view", choices=["side", "front", "back"], required=True)
    ap.add_argument("--head", required=True); ap.add_argument("--out", required=True)
    ap.add_argument("--stride", type=float, default=42); ap.add_argument("--lift", type=float, default=24)
    ap.add_argument("--bob", type=float, default=9); ap.add_argument("--sway", type=float, default=6)
    ap.add_argument("--head-h", type=int, default=310, help="side view: head+scarf height in cell px")
    a = ap.parse_args()
    head = Image.open(a.head).convert("RGBA")
    fn = side_frame if a.view == "side" else fb_frame
    frames = [fn(t, head, a) for t in range(24)]
    g = Image.new("RGB", (CW * 6, CH * 4), (255, 0, 255))
    for t, f in enumerate(frames): g.paste(f, ((t % 6) * CW, (t // 6) * CH))
    g.resize((4096, 3072), Image.LANCZOS).save(a.out)
    base = a.out.rsplit(".", 1)[0]
    g.crop((0, 0, CW * 6, CH)).resize((CW * 3, CH // 2)).save(base + "-peek.png")
    small = [f.resize((CW // 3, CH // 3)) for f in frames]
    small[0].save(base + ".gif", save_all=True, append_images=small[1:], duration=42, loop=0)
    print("guide", a.out)

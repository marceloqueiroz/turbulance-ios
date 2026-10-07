"""Asks Gemini (gemini-3-pro-image) to paint the character over a pose-guide grid. Runs several takes in
parallel: about 1 in 3 takes fails (wrong background, guide colours left in), so always generate 3 and score.

Usage:
  gen_sheet.py --guide grid.png --view side --sprite att-side.png --design design.jpg --out out-side [--takes abc]
               [--who "the game's flight attendant"] [--look "teal uniform, coral scarf, ..."]
Writes <out>-a.png, <out>-b.png ... (4800 x 3584, 6 x 4 cells). Needs GEMINI_API_KEY (env or the repo's .env).
"""
import argparse, base64, concurrent.futures as cf, json, os, urllib.request

ap = argparse.ArgumentParser()
ap.add_argument("--guide", required=True); ap.add_argument("--view", choices=["side", "front", "back"], required=True)
ap.add_argument("--sprite", required=True, help="the approved in-game sprite for this view")
ap.add_argument("--design", required=True, help="the character design sheet")
ap.add_argument("--out", required=True); ap.add_argument("--takes", default="abc")
ap.add_argument("--pose", choices=["walk", "idle", "carry", "clean", "trash"], default="walk")
ap.add_argument("--build", default="The legs are as SHORT as in IMAGE 2: only a short stub of leg and the shoe show below the clothes; keep the small, quick steps of the guide.",
                help="the sentence about body proportions and stride; match it to the character (the default is the attendant's)")
ap.add_argument("--who", default="the game's flight attendant")
ap.add_argument("--look", default="teal uniform jacket and skirt, coral scarf, white gloves, short skin-tone legs, brown shoes")
a = ap.parse_args()

key = os.environ.get("GEMINI_API_KEY")
if not key:
    env = os.path.join(os.path.dirname(__file__), "..", "..", "..", "..", ".env")
    for line in open(env):
        if line.startswith("GEMINI_API_KEY="): key = line.split("=", 1)[1].strip().strip('"')
b64 = lambda f: base64.b64encode(open(f, "rb").read()).decode()
mime = lambda f: "image/jpeg" if f.lower().endswith((".jpg", ".jpeg")) else "image/png"

VIEW = {
    "side": ("walking to the RIGHT, seen from the side from the game's high camera",
             "Blue limbs are the NEAR side (closest to the camera), orange limbs the FAR side, partly hidden behind the body"),
    "front": ("walking TOWARD the camera (down the screen), seen from the game's high camera, face visible",
              "Blue limbs are on the LEFT of the picture, orange limbs on the RIGHT. A foot or hand that is forward is LOWER on the screen"),
    "back": ("walking AWAY from the camera (up the screen), seen from the game's high camera, back of the head visible",
             "Blue limbs are on the LEFT of the picture, orange limbs on the RIGHT. A foot or hand that is forward is HIGHER on the screen"),
}[a.view]
WHAT = {"walk": "24-frame walk cycle",
        "idle": "24 frames of the character standing still and relaxed (an idle pose: feet together, arms down)",
        "carry": "24-frame walk cycle while carrying a serving tray",
        "clean": "24-frame looping animation of the character crouched over a coffee spill on the floor, wiping it with a yellow cloth "
                 "(the yellow oval in the guide is the cloth; she sweeps it forward and back on the floor in front of her)",
        "trash": "24-frame animation of the character throwing a used paper cup into a bin in front of her: she holds the cup "
                 "(the pale rounded box in the guide) in front of her, reaches out, lets go so it drops out of the picture, and her arm comes back"}[a.pose]
TRAY = (" The light grey oval with the dark outline is a TRAY: paint it as an empty, round, polished silver serving tray held out flat "
        "on one gloved hand at CHEST height, exactly where the guide puts it: never raised above her shoulders or head, never a second "
        "tray, the whole tray inside the picture, the same tray in every one of the 24 cells (from behind, her body hides most of it). "
        "It is the only grey allowed." if a.pose == "carry" and a.view != "back" else
        " She carries a serving tray in front of her at chest height; seen from behind, her body hides it COMPLETELY: her right arm "
        "reaches forward out of sight, as in the guide. Do not paint any tray." if a.pose == "carry" else "")
PROMPT = (
    f"Animation sprite sheet, {WHAT}. IMAGE 1 is a 6 x 4 grid of POSE GUIDES, read left to right, top row first. "
    f"The character is {a.who}, {VIEW[0]}. In every cell the HEAD is already final: the same head, same size, same angle in all 24 cells. "
    "Keep it exactly as it is in each cell; do not resize, turn or redraw it, only its position shifts slightly as the body bobs. "
    "Below the head a grey mannequin shows the body for that frame; the dark shapes are the shoes, the white dots the hands. "
    f"{VIEW[1]}. Paint the body under the head in exactly the guide's pose, as the character in IMAGE 2 (the approved sprite for this view) "
    f"and IMAGE 3 (design sheet): {a.look}, soft matte toy 3D, light from the upper left. "
    "Match the guide precisely: which foot is forward, which is lifted, the knee bend, where each hand is. "
    f"{a.build} "
    f"{TRAY} Do NOT keep any blue, orange or mannequin grey: those are guide colours only. The body must be the same size in every cell. "
    "Background stays perfectly flat pure magenta (#FF00FF). No grid lines, no numbers, no text.")


def run(take):
    parts = [{"inlineData": {"mimeType": mime(f), "data": b64(f)}} for f in (a.guide, a.sprite, a.design)] + [{"text": PROMPT}]
    body = {"contents": [{"parts": parts}],
            "generationConfig": {"responseModalities": ["IMAGE"], "imageConfig": {"aspectRatio": "4:3", "imageSize": "4K"}}}
    req = urllib.request.Request("https://generativelanguage.googleapis.com/v1beta/models/gemini-3-pro-image:generateContent",
                                 data=json.dumps(body).encode(), headers={"Content-Type": "application/json", "x-goog-api-key": key})
    err = None
    for _ in range(2):
        try:
            d = json.load(urllib.request.urlopen(req, timeout=600))
            for p in d["candidates"][0]["content"]["parts"]:
                if "inlineData" in p and not p.get("thought"):
                    open(f"{a.out}-{take}.png", "wb").write(base64.b64decode(p["inlineData"]["data"])); return f"{take} OK"
        except Exception as e:
            err = e
    return f"{take} FAIL {err}"


with cf.ThreadPoolExecutor(len(a.takes)) as ex:
    for r in ex.map(run, a.takes): print(r)

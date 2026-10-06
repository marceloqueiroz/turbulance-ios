import json, os, base64, urllib.request, concurrent.futures as cf, sys
key=os.environ["GEMINI_API_KEY"]
refs=[base64.b64encode(open(f,"rb").read()).decode() for f in ["ref-face.jpg","ref-body.jpg","ref-tilt.jpg","ref-style.jpg"]]
P=("Character sheet for a mobile game sprite: the SAME flight attendant as in the first two images (chunky toy figure about 2.5 heads tall, big round head, "
"brown hair in a bun, small teal cap, big glossy dark eyes, strong brows, rosy cheeks, teal uniform jacket and skirt, coral neck scarf tied at the side, coral name badge, "
"white gloves, dark shoes; soft matte painted-vinyl 3D, warm key light from the upper left, no outlines). "
"Draw her THREE times side by side, evenly spaced and not touching, all at the same size, as seen by a game camera that looks almost straight down at the floor but tilted "
"about 20 degrees toward the bottom of the screen (like the attendant in the third image): we mostly see the top of the cap and head and the shoulders, with the face partly visible when she faces down. "
"LEFT: SIDE view, walking to the right along an aisle (profile, half the face visible). "
"MIDDLE: BACK view, facing toward the top of the screen (we see the back of her head, the bun and cap, and her back; no face). "
"RIGHT: FRONT view, facing toward the bottom of the screen (full face visible, looking slightly up at the camera). "
"Neutral standing pose in each, arms held slightly away from the body so the arms, hands and feet are clearly separate shapes (for cutting into animation parts), empty hands. "
"Background: a perfectly flat uniform pure magenta (#FF00FF) everywhere, with no floor, no shadows on the background and no other objects. No text, letters or labels.")
def run(k):
    parts=[{"inlineData":{"mimeType":"image/jpeg","data":r}} for r in refs]+[{"text":P}]
    body={"contents":[{"parts":parts}],"generationConfig":{"responseModalities":["IMAGE"],"imageConfig":{"aspectRatio":"16:9","imageSize":"2K"}}}
    req=urllib.request.Request("https://generativelanguage.googleapis.com/v1beta/models/gemini-3-pro-image:generateContent",data=json.dumps(body).encode(),headers={"Content-Type":"application/json","x-goog-api-key":key})
    d=json.load(urllib.request.urlopen(req,timeout=300))
    for p in d["candidates"][0]["content"]["parts"]:
        if "inlineData" in p and not p.get("thought"):
            open(f"sheet-{k}.png","wb").write(base64.b64decode(p["inlineData"]["data"])); return k+" OK"
    return k+" none"
with cf.ThreadPoolExecutor(3) as ex:
    for r in ex.map(run,["1","2","3"]): print(r)

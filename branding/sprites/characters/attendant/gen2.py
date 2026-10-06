import json, os, base64, urllib.request, concurrent.futures as cf
key=os.environ["GEMINI_API_KEY"]
refs=[base64.b64encode(open(f,"rb").read()).decode() for f in ["ref-design.jpg","ref-tiltcrop.jpg","ref-style.jpg"]]
P=("The first image is the approved character design sheet of a flight attendant in three facings (side walking right, back, front). "
"Redraw the SAME character, same proportions, clothes and colours, in the SAME three facings and left-to-right order, but seen from a very HIGH camera that looks down "
"almost vertically at the floor, tilted only about 20 degrees from straight down toward the bottom of the screen, exactly like the attendant in the second image. "
"So in every view: the top of the teal cap and the top of the head are the biggest shapes, the shoulders and arms are seen from above, the body is strongly foreshortened, "
"and only the tips of the shoes show below. Side view: we see the top of the head and cap, the bun, and the face in profile only slightly. "
"Back view: top and back of the head, the bun and cap, the shoulders; no face. Front view: top of the head and cap with the face visible but foreshortened, looking up a little. "
"Soft matte painted-vinyl 3D, warm key light from the upper left, matching the style of the third image. Arms slightly away from the body, empty hands. "
"All three the same size, evenly spaced, not touching. Background: perfectly flat uniform pure magenta (#FF00FF), no floor, no shadows on the background. No text.")
def run(k):
    parts=[{"inlineData":{"mimeType":"image/jpeg","data":r}} for r in refs]+[{"text":P}]
    body={"contents":[{"parts":parts}],"generationConfig":{"responseModalities":["IMAGE"],"imageConfig":{"aspectRatio":"16:9","imageSize":"2K"}}}
    req=urllib.request.Request("https://generativelanguage.googleapis.com/v1beta/models/gemini-3-pro-image:generateContent",data=json.dumps(body).encode(),headers={"Content-Type":"application/json","x-goog-api-key":key})
    d=json.load(urllib.request.urlopen(req,timeout=300))
    for p in d["candidates"][0]["content"]["parts"]:
        if "inlineData" in p and not p.get("thought"):
            open(f"ingame-{k}.png","wb").write(base64.b64decode(p["inlineData"]["data"])); return k+" OK"
    return k+" none"
with cf.ThreadPoolExecutor(3) as ex:
    for r in ex.map(run,["1","2","3"]): print(r)

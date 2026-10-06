import json, os, base64, urllib.request, concurrent.futures as cf
key=os.environ["GEMINI_API_KEY"]
b64=lambda f: base64.b64encode(open(f,"rb").read()).decode()
P=("The first image is the approved design sheet of an airline passenger. Draw the SAME character (same face, hair, clothes, colours, props, chunky toy proportions) "
"FIVE times in a row, same size, evenly spaced, not touching. CAMERA: a game camera high above, looking almost STRAIGHT DOWN at the floor, tilted only 20 degrees from vertical, "
"EXACTLY like the flight attendant in the second image: the TOP of the head and hair is the largest shape, the shoulders are seen from above, the body is strongly foreshortened "
"and short, only the tips of the feet show. NOT an eye-level or three-quarter view. "
"1) SEATED in a seat pod seen from directly above exactly like the seats in the third image (teal cushion, coral patterned headrest on the LEFT side), the passenger sitting with their back against the headrest, facing RIGHT is wrong: they face the cushion, so we see the top of their head over the cushion, lap and knees toward the right; "
"2) same seated pose, but head tilted up and one hand raised toward the bottom of the screen, calling the attendant, face visible; "
"3) WALKING to the right, seen from high above; 4) WALKING toward the top of the screen (back of the head, no face); 5) WALKING toward the bottom of the screen (face visible, foreshortened). "
"Soft matte painted-vinyl 3D, warm light from the upper left. Background: perfectly flat uniform pure magenta (#FF00FF), no floor, no shadows on the background. No text.")
def call(k):
    refs=[f"ref-{k}.jpg","ref-att-ingame.jpg","ref-seats-top.jpg"]
    parts=[{"inlineData":{"mimeType":"image/jpeg","data":b64(r)}} for r in refs]+[{"text":P}]
    body={"contents":[{"parts":parts}],"generationConfig":{"responseModalities":["IMAGE"],"imageConfig":{"aspectRatio":"21:9","imageSize":"2K"}}}
    req=urllib.request.Request("https://generativelanguage.googleapis.com/v1beta/models/gemini-3-pro-image:generateContent",data=json.dumps(body).encode(),headers={"Content-Type":"application/json","x-goog-api-key":key})
    try: d=json.load(urllib.request.urlopen(req,timeout=300))
    except Exception as e: return f"{k} ERR {e}"
    for p in d["candidates"][0]["content"]["parts"]:
        if "inlineData" in p and not p.get("thought"):
            open(f"top-{k}.png","wb").write(base64.b64decode(p["inlineData"]["data"])); return k+" OK"
    return k+" none"
with cf.ThreadPoolExecutor(5) as ex:
    for r in ex.map(call,["business","family","nervous","sleeper","chatterbox"]): print(r)

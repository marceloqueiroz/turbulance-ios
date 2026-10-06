import json, os, base64, urllib.request, concurrent.futures as cf
key=os.environ["GEMINI_API_KEY"]
b64=lambda f: base64.b64encode(open(f,"rb").read()).decode()
def call(refs, prompt, out, ar="21:9"):
    parts=[{"inlineData":{"mimeType":"image/jpeg","data":b64(r)}} for r in refs]+[{"text":prompt}]
    body={"contents":[{"parts":parts}],"generationConfig":{"responseModalities":["IMAGE"],"imageConfig":{"aspectRatio":ar,"imageSize":"2K"}}}
    req=urllib.request.Request("https://generativelanguage.googleapis.com/v1beta/models/gemini-3-pro-image:generateContent",data=json.dumps(body).encode(),headers={"Content-Type":"application/json","x-goog-api-key":key})
    try: d=json.load(urllib.request.urlopen(req,timeout=300))
    except Exception as e: return f"{out} ERR {e}"
    for p in d["candidates"][0]["content"]["parts"]:
        if "inlineData" in p and not p.get("thought"):
            open(out,"wb").write(base64.b64decode(p["inlineData"]["data"])); return out+" OK"
    return out+" none"
INGAME=("The first image is the approved design sheet of an airline passenger. Draw the SAME character (same face, hair, clothes, colours and props, same chunky toy proportions) "
"FIVE times side by side, same size, evenly spaced, not touching, as seen by the game camera: looking down from high above, tilted only about 20 degrees from straight down "
"toward the bottom of the screen, exactly like the flight attendant in the second image (top of the head is the biggest shape, body foreshortened). From left to right: "
"1) SEATED in a teal seat pod with a coral patterned headrest, exactly like the seats in the third image seen from straight above, the passenger facing LEFT (toward the nose of the plane), relaxed; "
"2) the same seated pose but with the head and one hand turned toward the bottom of the screen, as if calling the attendant (face visible); "
"3) WALKING to the right (side view); 4) WALKING away toward the top of the screen (back view, no face); 5) WALKING toward the bottom of the screen (front view, face visible). "
"Soft matte painted-vinyl 3D, warm key light from the upper left. Background: perfectly flat uniform pure magenta (#FF00FF), no floor, no shadows on the background. No text or logos.")
jobs=[]
for k in ["business","family","nervous","sleeper"]:
    jobs.append((["ref-%s.jpg"%k,"ref-att-ingame.jpg","ref-seats.jpg"], INGAME, f"ingame-{k}.png", "21:9"))
CH=("Character design sheet for a cosy, comedic mobile game about a flight attendant. Design a NEW airline PASSENGER in EXACTLY the same art style and body proportions "
"as the flight attendant in the first image and the passengers in the second image: a very chunky toy figure about 2.5 heads tall, a big round head, a short round body, "
"short stubby arms and legs, mitten-like hands, big glossy dark eyes, rosy cheeks, soft matte painted-vinyl 3D, warm key light from the upper left, no outlines. "
"NOT realistic proportions: no long limbs, no slim body. The passenger: a chatterbox, a woman with medium brown skin and big round curly dark hair, a bright coral and cream "
"patterned blouse, cream trousers, small gold hoop earrings, one stubby hand raised mid-gesture as if telling a story, mouth open in a cheerful laugh. "
"Draw her THREE times side by side at eye level, same size, evenly spaced, not touching: LEFT front view, MIDDLE side view walking to the right, RIGHT back view. "
"Background: perfectly flat uniform pure magenta (#FF00FF), no floor, no shadows on the background. No text, letters or logos.")
for t in ["a","b"]:
    jobs.append((["ref-design.jpg","ref-nervous.jpg"], CH, f"design-chatterbox-{t}.png", "16:9"))
with cf.ThreadPoolExecutor(6) as ex:
    for r in ex.map(lambda j: call(*j), jobs): print(r)

import json, os, base64, urllib.request, concurrent.futures as cf
key=os.environ["GEMINI_API_KEY"]
refs=[base64.b64encode(open(f,"rb").read()).decode() for f in ["ref-design.jpg","ref-style.jpg"]]
BASE=("Character design sheet for a cosy, comedic mobile game about a flight attendant. Design a NEW airline PASSENGER character in exactly the same art style and "
"proportions as the flight attendant in the first image: chunky toy figure about 2.5 heads tall, big round head, big glossy dark eyes, expressive brows, small nose, rosy cheeks, "
"soft matte painted-vinyl 3D, warm key light from the upper left, no outlines. Draw the passenger THREE times side by side at eye level, same size, evenly spaced, not touching: "
"LEFT front view, MIDDLE side view walking to the right, RIGHT back view. Neutral standing pose, arms slightly away from the body. Keep the palette calm and warm so it sits "
"well in the cabin of the second image; avoid the attendant's teal uniform. Background: perfectly flat uniform pure magenta (#FF00FF), no floor, no shadows on the background. "
"No text, letters or logos anywhere, including on clothes and props. The passenger: ")
V={
 "business": "a business traveller: a woman with dark skin and a neat short afro, small round glasses, a charcoal grey suit with a pale blue shirt, a slim laptop held under one arm; composed, slightly impatient expression.",
 "family": "a parent travelling with a toddler: a man with light olive skin, messy brown hair and a short beard, a mustard yellow cardigan over a white t-shirt and jeans, carrying a small toddler on his hip (the toddler is a tiny matching chunky toy character in a red romper with a dummy); warm, slightly frazzled smile.",
 "nervous": "a nervous flyer: a young man with pale freckled skin and messy ginger hair, a lavender hoodie with the hood down, clutching the hoodie strings with both hands, wide worried eyes and a wobbly mouth.",
 "sleeper": "a sleepy passenger: an older woman with tan skin and grey hair in a low bun, a soft sage green knitted jumper, a sleep mask pushed up on her forehead, a travel neck pillow around her neck, a folded blanket over one arm; drowsy half-closed eyes and a small yawn.",
 "chatterbox": "a chatterbox: a woman with medium brown skin and big curly dark hair, a bright coral and cream patterned blouse, gold hoop earrings, one hand raised mid-gesture as if telling a story, mouth open in a cheerful laugh.",
}
def run(k):
    parts=[{"inlineData":{"mimeType":"image/jpeg","data":r}} for r in refs]+[{"text":BASE+V[k]}]
    body={"contents":[{"parts":parts}],"generationConfig":{"responseModalities":["IMAGE"],"imageConfig":{"aspectRatio":"16:9","imageSize":"2K"}}}
    req=urllib.request.Request("https://generativelanguage.googleapis.com/v1beta/models/gemini-3-pro-image:generateContent",data=json.dumps(body).encode(),headers={"Content-Type":"application/json","x-goog-api-key":key})
    try: d=json.load(urllib.request.urlopen(req,timeout=300))
    except Exception as e: return f"{k} ERR {e}"
    for p in d["candidates"][0]["content"]["parts"]:
        if "inlineData" in p and not p.get("thought"):
            open(f"design-{k}.png","wb").write(base64.b64decode(p["inlineData"]["data"])); return k+" OK"
    return k+" none"
with cf.ThreadPoolExecutor(5) as ex:
    for r in ex.map(run,V): print(r)

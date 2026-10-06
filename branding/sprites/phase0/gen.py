import json, os, base64, urllib.request, concurrent.futures as cf
key=os.environ["GEMINI_API_KEY"]
refs=[base64.b64encode(open(f,"rb").read()).decode() for f in ["ref-layout.jpg","ref-attendant.jpg","ref-cabin.jpg"]]
BASE=("Repaint the first image, a top-down screenshot of a mobile game's airplane cabin, in a new art style, keeping its layout EXACTLY: "
"the same camera (straight top-down, orthographic, no perspective), the same framing, and every object in the same place and size: "
"the two galley counters at the left with their stations (drinks dispenser, coffee machine, oven at the top; oven, snack bin, toy bin, trash at the bottom), "
"the 12 rows of 2+2 seats, the aisle down the middle with the flight attendant standing on it at the left, the two lavatories and the plunger and trash stations at the right, "
"the two fold-down crew seats by the aisle, the windows along the top and bottom walls, and the thick end walls at the far left and right. "
"New style: the soft, matte, toy-like 3D of the second and third images (painted vinyl, rounded chunky shapes, soft ambient occlusion, a warm key light from the upper left, "
"soft shadows falling down and to the right, no outlines on the world objects). Seats: navy (#1B2A4A) cushions with cream headrest covers and a teal stripe, seen from directly above. "
"Passengers: chunky toy figures seen from directly above, so mostly the top of the head with its hair, the shoulders and arms: no faces. Keep each passenger's shirt colour and hair colour from the screenshot; a few seats are empty. "
"The attendant: the same character as the second image but seen from directly above: teal cap and bun, teal uniform, coral scarf. "
"Floor: plain warm cream (#E8E2D8). Walls: light steel with the coral stripe. Galley stations look like small toy appliances. Keep the overall palette calm and low-saturation. "
"Keep the one flat round call icon (yellow ring, navy outline, notepad) above the passenger near the top left exactly as it is: flat, outlined, not 3D. No text anywhere, no labels, no letters.")
V={"A":BASE+" Aisle: keep the coral (#E8543E) runner line down the middle of the aisle, on a soft taupe aisle carpet.",
   "B":BASE+" Aisle: a soft taupe (#D6CCBD) carpet runner with two thin coral edge lines, and no bright coral stripe in the middle, so orange problem icons stand out on it."}
def run(k):
    parts=[{"inlineData":{"mimeType":"image/jpeg","data":r}} for r in refs]+[{"text":V[k]}]
    body={"contents":[{"parts":parts}],"generationConfig":{"responseModalities":["IMAGE"],"imageConfig":{"aspectRatio":"21:9","imageSize":"2K"}}}
    req=urllib.request.Request("https://generativelanguage.googleapis.com/v1beta/models/gemini-3-pro-image:generateContent",data=json.dumps(body).encode(),headers={"Content-Type":"application/json","x-goog-api-key":key})
    d=json.load(urllib.request.urlopen(req,timeout=300))
    for p in d["candidates"][0]["content"]["parts"]:
        if "inlineData" in p and not p.get("thought"):
            open(f"style-{k}.png","wb").write(base64.b64decode(p["inlineData"]["data"])); return k+" OK"
    return k+" no image"
with cf.ThreadPoolExecutor(2) as ex:
    for r in ex.map(run,V): print(r)

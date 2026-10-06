import json, os, base64, urllib.request, concurrent.futures as cf
key=os.environ["GEMINI_API_KEY"]
refs=[base64.b64encode(open(f,"rb").read()).decode() for f in ["ref-layout.jpg","ref-style.jpg","ref-attendant.jpg"]]
P=("Game art for a mobile game, one landscape screen of an airplane cabin seen from STRAIGHT ABOVE: a perfectly orthographic top-down view, camera pointing straight down, "
"no perspective, no tilt, no visible sides of objects, like a floor plan rendered in 3D. "
"LAYOUT: copy the first image exactly. It is the game's real layout and every object must stay at the same position and size: "
"the galley at the left with one counter above the aisle (drinks dispenser, coffee machine, oven, from left to right) and one counter below the aisle (oven, snack bin, toy bin, trash bin); "
"exactly 12 rows of seats, 2 seats above the aisle and 2 below in each row, in the same columns; the aisle across the middle; the flight attendant on the aisle at the far left; "
"at the right end two lavatory blocks, the top one with a plunger station beside it and the bottom one with a trash bin beside it; "
"two small fold-down crew seats on the aisle edge at each end; the window strip along the top and bottom walls; the thick end walls at the far left and far right. "
"STYLE: the 1960s jet-age glamour of the second image, redrawn from straight above: rounded chrome-and-cream galley units with brass trim, "
"recognisable appliances seen from the top (a drinks fridge with coloured bottle tops, an espresso machine with cups, domed chrome ovens, a snack drawer, a toy drawer, a chrome trash bin), "
"a cream terrazzo floor in the galley and at both ends, a coral patterned aisle runner with a subtle teal motif, teal seat pods with coral patterned headrests and brass armrest caps, "
"lavatories with cream porthole doors, warm globe lights seen from above, and soft matte toy-like 3D rendering with gentle shadows falling down and to the right. "
"Passengers: chunky toy figures seen from directly above (tops of heads with hair, shoulders), keep the seated and empty seats as in the first image; no faces. "
"The attendant: the character from the third image, seen from directly above (teal cap, bun, teal uniform, coral scarf). "
"Keep the one flat yellow round call icon above the passenger near the top left exactly as in the first image: flat, outlined. "
"Keep the overall look calm, so small bright problem icons will pop. No text, letters, numbers or labels anywhere.")
V={"A":P, "B":P+" Keep the aisle runner pattern very subtle (a quiet tone-on-tone coral weave) and the terrazzo fine-grained, so the floor stays calm at phone size."}
def run(k):
    parts=[{"inlineData":{"mimeType":"image/jpeg","data":r}} for r in refs]+[{"text":V[k]}]
    body={"contents":[{"parts":parts}],"generationConfig":{"responseModalities":["IMAGE"],"imageConfig":{"aspectRatio":"21:9","imageSize":"2K"}}}
    req=urllib.request.Request("https://generativelanguage.googleapis.com/v1beta/models/gemini-3-pro-image:generateContent",data=json.dumps(body).encode(),headers={"Content-Type":"application/json","x-goog-api-key":key})
    try: d=json.load(urllib.request.urlopen(req,timeout=300))
    except Exception as e: return f"{k} ERR {e}"
    for p in d["candidates"][0]["content"]["parts"]:
        if "inlineData" in p and not p.get("thought"):
            open(f"jet-{k}.png","wb").write(base64.b64decode(p["inlineData"]["data"])); return k+" OK"
    return k+" no image"
with cf.ThreadPoolExecutor(2) as ex:
    for r in ex.map(run,V): print(r)

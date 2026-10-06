import json, os, base64, urllib.request, concurrent.futures as cf
key=os.environ["GEMINI_API_KEY"]
refs=[base64.b64encode(open(f,"rb").read()).decode() for f in ["ref-layout.jpg","ref-attendant.jpg"]]
BASE=("Game concept art for 'Turbulence', a cosy, comedic time-management game where you play a flight attendant. "
"Design a NEW interior for a small regional jet cabin, seen from STRAIGHT ABOVE (orthographic top-down, no perspective tilt), as one landscape screen. "
"The first image is only a functional diagram of what the cabin must contain, in roughly these places: at the left (front), a crew galley with two work areas, one above and one below the aisle, "
"holding a cold-drinks dispenser, a coffee machine and two ovens, a snack bin, a toy bin and a trash bin; then 12 rows of seats, two seats on each side of one central aisle; "
"at the right (back), two lavatories, one above and one below the aisle, with a plunger station next to the top one and a trash bin next to the bottom one; two fold-down crew seats by the aisle at each end. "
"Do NOT copy its look: its grey boxes and flat icons are what we want to replace. Make the galley and lavatories feel like real, characterful, designed places, "
"with built-in cabinetry, distinctive appliances you can recognise from above, little props and details, and a clear walkable floor for the crew. "
"Seen from above, every station must read instantly as what it is. Include the flight attendant from the second image, seen from straight above, standing in the galley "
"(teal cap, bun, teal uniform, coral scarf). Passengers are chunky toy figures seen from directly above (tops of heads, hair, shoulders; no faces), some seats empty. "
"Rendering: soft, matte, toy-like 3D with rounded chunky shapes, warm light from the upper left, soft shadows, no outlines. Keep the cabin calm enough that small bright problem icons would pop on top of it. "
"No text, letters, numbers or logos anywhere. ")
V={
 "1-jet-age": BASE+"Direction: 1960s jet-age airline glamour. Curved chrome-and-cream galley units with rounded corners, a terrazzo galley floor, a patterned carpet runner, "
   "rounded teal seat pods, coral accents, brass details, globe pendant lights shown from above, lavatories with porthole doors.",
 "2-toy-playset": BASE+"Direction: a premium toy airplane playset, like a beautifully designed wooden-and-plastic toy. Chunky rounded pieces, candy-like colours toned down to teal, coral, cream and navy, "
   "the galley as a playful toy kitchen with oversized knobs and dials, seats like soft rounded toy chairs, rounded rug-like aisle runner, lavatories as cute little toy cabins.",
 "3-boutique": BASE+"Direction: a boutique modern airline. Warm light oak and cream cabinetry, a sculpted galley with integrated espresso machine and ovens behind smoked glass, "
   "soft ambient light strips along the walls, a woven wool aisle runner with a subtle pattern, deep navy seats with stitched cream headrests, terracotta and teal accents, lavatories with frosted doors and a plant.",
 "4-busy-galley": BASE+"Direction: Overcooked-style lively kitchen energy, but airline. The galley is a cramped, busy, well-loved crew workspace: tiled floor, stacked trays, cup towers, "
   "a trolley parked in a bay, steam from the coffee machine, a glowing oven window, labels replaced by pictures and colours, cosy clutter that still keeps every station readable from above. Cabin seats tidy and calm in contrast.",
}
def run(k):
    parts=[{"inlineData":{"mimeType":"image/jpeg","data":r}} for r in refs]+[{"text":V[k]}]
    body={"contents":[{"parts":parts}],"generationConfig":{"responseModalities":["IMAGE"],"imageConfig":{"aspectRatio":"21:9","imageSize":"2K"}}}
    req=urllib.request.Request("https://generativelanguage.googleapis.com/v1beta/models/gemini-3-pro-image:generateContent",data=json.dumps(body).encode(),headers={"Content-Type":"application/json","x-goog-api-key":key})
    try: d=json.load(urllib.request.urlopen(req,timeout=300))
    except Exception as e: return f"{k} ERR {e}"
    for p in d["candidates"][0]["content"]["parts"]:
        if "inlineData" in p and not p.get("thought"):
            open(f"{k}.png","wb").write(base64.b64decode(p["inlineData"]["data"])); return k+" OK"
    return k+" no image"
with cf.ThreadPoolExecutor(4) as ex:
    for r in ex.map(run,V): print(r)

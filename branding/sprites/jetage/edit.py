import json, os, base64, urllib.request, sys
key=os.environ["GEMINI_API_KEY"]; out=sys.argv[1]
imgs=[("image/png",base64.b64encode(open(f,"rb").read()).decode()) for f in ["base.png","ref-toilets.png"]]
prompt=("Edit the first image, a straight top-down view of a jet-age airplane cabin for a mobile game. Keep EVERYTHING the same (camera, framing, every seat, passenger, "
"the attendant, the aisle runner, the floor, the top galley counter, the lights) except these changes:\n"
"1. The two lavatory blocks at the far right become open-top lavatories seen from straight above, in the style of the second image: no roof, so you see inside, "
"a small patterned tile floor, a cream toilet bowl, a small sink, cream walls with brass trim, and a cream door with a porthole facing the aisle. "
"Keep each lavatory in the same place and size as the blocks it replaces (one above the aisle, one below). "
"Put a plunger standing inside the top lavatory next to the toilet, and a chrome pedal trash bin inside the bottom lavatory. Remove the separate plunger and trash tiles.\n"
"2. On the bottom galley counter at the left, replace the four flat square tiles with real jet-age appliances in the same four positions, from left to right: "
"a domed chrome oven identical in design to the oven on the top counter, an open drawer of snack packets, an open drawer of small toys, and a chrome pedal trash bin. "
"Everything on both counters must share one consistent style: chrome, cream and brass, seen from straight above.\n"
"3. Make the walls at the far left and far right ends thicker, with a coral stripe running down them like the stripe on the side walls.\n"
"Keep the straight top-down orthographic view. No text, letters or labels anywhere.")
parts=[{"inlineData":{"mimeType":m,"data":d}} for m,d in imgs]+[{"text":prompt}]
body={"contents":[{"parts":parts}],"generationConfig":{"responseModalities":["IMAGE"],"imageConfig":{"aspectRatio":"21:9","imageSize":"2K"}}}
req=urllib.request.Request("https://generativelanguage.googleapis.com/v1beta/models/gemini-3-pro-image:generateContent",data=json.dumps(body).encode(),headers={"Content-Type":"application/json","x-goog-api-key":key})
d=json.load(urllib.request.urlopen(req,timeout=300))
for p in d["candidates"][0]["content"]["parts"]:
    if "inlineData" in p and not p.get("thought"):
        open(out,"wb").write(base64.b64decode(p["inlineData"]["data"])); print(out,"OK"); break
else: print("no image")

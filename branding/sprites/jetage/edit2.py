import json, os, base64, urllib.request, sys
key=os.environ["GEMINI_API_KEY"]; out=sys.argv[1]
img=base64.b64encode(open("jet-C1.png","rb").read()).decode()
prompt=("Edit this straight top-down view of a jet-age airplane cabin for a mobile game. Keep EVERYTHING the same (camera, framing, seats, passengers, the attendant, "
"the aisle runner, floor, lights, the top galley counter with drinks fridge, espresso machine and domed oven, the bottom domed oven, and both open-top lavatories) except:\n"
"1. On the bottom galley counter, remove the two stacked pull-out drawers and the trash can. In their place, to the right of the domed oven, put TWO separate open bins "
"side by side on the counter top, clearly apart with a gap between them: the left one full of colourful snack packets (no lettering), the right one full of small toys "
"(a teddy bear, a ball, a toy plane). Same chrome, cream and brass style.\n"
"2. Add a wall-mounted chrome trash bin with a brass swing flap on the left end wall, just above the aisle, beside the front crew seats; and an identical one on the right end wall, "
"just below the aisle near the bottom lavatory. Both seen from straight above, clearly reading as trash bins.\n"
"Keep the plunger and the small bin inside the lavatories as they are. Straight top-down orthographic view. No text, letters or labels anywhere.")
body={"contents":[{"parts":[{"inlineData":{"mimeType":"image/png","data":img}},{"text":prompt}]}],
      "generationConfig":{"responseModalities":["IMAGE"],"imageConfig":{"aspectRatio":"21:9","imageSize":"2K"}}}
req=urllib.request.Request("https://generativelanguage.googleapis.com/v1beta/models/gemini-3-pro-image:generateContent",data=json.dumps(body).encode(),headers={"Content-Type":"application/json","x-goog-api-key":key})
d=json.load(urllib.request.urlopen(req,timeout=300))
for p in d["candidates"][0]["content"]["parts"]:
    if "inlineData" in p and not p.get("thought"):
        open(out,"wb").write(base64.b64decode(p["inlineData"]["data"])); print(out,"OK"); break
else: print("no image")

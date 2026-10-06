import json, os, base64, urllib.request, sys
key=os.environ["GEMINI_API_KEY"]; out=sys.argv[1]
img=base64.b64encode(open("jet-D1.png","rb").read()).decode()
prompt=("Edit this straight top-down view of a jet-age airplane cabin for a mobile game. Keep EVERYTHING exactly the same except one thing on the LEFT end wall: "
"there are two chrome wall-mounted trash bins there, one above the aisle and one below. Replace the UPPER one (above the aisle) with a teal fold-down crew seat with a coral "
"patterned back, identical to the teal crew seat on the RIGHT end wall above the aisle. Keep the LOWER bin exactly as it is. "
"Straight top-down orthographic view. No text, letters or labels anywhere.")
body={"contents":[{"parts":[{"inlineData":{"mimeType":"image/png","data":img}},{"text":prompt}]}],
      "generationConfig":{"responseModalities":["IMAGE"],"imageConfig":{"aspectRatio":"21:9","imageSize":"2K"}}}
req=urllib.request.Request("https://generativelanguage.googleapis.com/v1beta/models/gemini-3-pro-image:generateContent",data=json.dumps(body).encode(),headers={"Content-Type":"application/json","x-goog-api-key":key})
d=json.load(urllib.request.urlopen(req,timeout=300))
for p in d["candidates"][0]["content"]["parts"]:
    if "inlineData" in p and not p.get("thought"):
        open(out,"wb").write(base64.b64decode(p["inlineData"]["data"])); print(out,"OK"); break
else: print("no image")

"""Asks Gemini for a colour-coded body-part map of a character sheet (head red, torso green, arms blue/yellow, legs cyan/orange,
magenta background), aligned with the sheet, for character_rig.py. Usage: GEMINI_API_KEY=... python3 character_seg.py sheet.png seg.png"""
import json, os, base64, urllib.request, sys
key=os.environ["GEMINI_API_KEY"]; src, out = sys.argv[1], sys.argv[2]
img=base64.b64encode(open(src,"rb").read()).decode()
P=("This image shows game character sprites on a magenta background. Produce a SEGMENTATION MAP of exactly this image: same size, same framing, every character in exactly "
"the same position, pose and outline. Replace each body part with ONE flat solid colour, no shading, no outlines, no texture: "
"HEAD (face, hair, hat, glasses, ears) = pure red #FF0000; TORSO (clothes, body, and anything carried against the body: a baby, a bag, a blanket, a laptop, a pillow) = pure green #00FF00; "
"the character's RIGHT ARM including the hand and glove = pure blue #0000FF; the character's LEFT ARM including the hand = pure yellow #FFFF00; "
"RIGHT LEG including the shoe = pure cyan #00FFFF; LEFT LEG including the shoe = pure orange #FF8000. Keep the background pure magenta #FF00FF. "
"Where a part is hidden behind another, only the visible part gets its colour. No other colours, no text.")
body={"contents":[{"parts":[{"inlineData":{"mimeType":"image/png","data":img}},{"text":P}]}],
      "generationConfig":{"responseModalities":["IMAGE"],"imageConfig":{"aspectRatio":"3:2","imageSize":"2K"}}}
req=urllib.request.Request("https://generativelanguage.googleapis.com/v1beta/models/gemini-3-pro-image:generateContent",data=json.dumps(body).encode(),headers={"Content-Type":"application/json","x-goog-api-key":key})
d=json.load(urllib.request.urlopen(req,timeout=300))
for p in d["candidates"][0]["content"]["parts"]:
    if "inlineData" in p and not p.get("thought"):
        open(out,"wb").write(base64.b64decode(p["inlineData"]["data"])); print(out,"OK"); break

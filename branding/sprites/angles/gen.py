import json, os, base64, urllib.request, concurrent.futures as cf
key=os.environ["GEMINI_API_KEY"]
base=base64.b64encode(open("A-topdown.png","rb").read()).decode()
att=base64.b64encode(open("../phase0/ref-attendant.jpg","rb").read()).decode()
common=("Keep the cabin, seats, floor, galley and every object exactly as in the first image, seen from straight above. "
"Change ONLY how the characters (the flight attendant and the seated passengers) are drawn: ")
V={"B-tilt20": common+"draw them as if the camera for characters were tilted about 20 degrees toward the bottom of the screen, so we still mostly see the tops of their heads "
   "but their faces are partly visible (eyes and expression readable), like a classic top-down game. The attendant should look like the second image. No text.",
   "C-threequarter": common+"draw them in a three-quarter view, as if seen from about 45 degrees above and in front, so their full faces and front of their bodies show "
   "(chunky toy figures standing or sitting upright), like the characters in a cosy isometric game, while the cabin stays top-down. The attendant should look like the second image. No text."}
def run(k):
    body={"contents":[{"parts":[{"inlineData":{"mimeType":"image/png","data":base}},{"inlineData":{"mimeType":"image/jpeg","data":att}},{"text":V[k]}]}],
          "generationConfig":{"responseModalities":["IMAGE"],"imageConfig":{"aspectRatio":"3:4","imageSize":"2K"}}}
    req=urllib.request.Request("https://generativelanguage.googleapis.com/v1beta/models/gemini-3-pro-image:generateContent",data=json.dumps(body).encode(),headers={"Content-Type":"application/json","x-goog-api-key":key})
    d=json.load(urllib.request.urlopen(req,timeout=300))
    for p in d["candidates"][0]["content"]["parts"]:
        if "inlineData" in p and not p.get("thought"):
            open(k+".png","wb").write(base64.b64decode(p["inlineData"]["data"])); return k+" OK"
    return k+" none"
with cf.ThreadPoolExecutor(2) as ex:
    for r in ex.map(run,V): print(r)

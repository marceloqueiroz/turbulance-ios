import json, os, base64, urllib.request, concurrent.futures as cf, re
key=os.environ["GEMINI_API_KEY"]
b64=lambda f: base64.b64encode(open(f,"rb").read()).decode()
P=open("gen3.py").read().split('P=(',1)[1].split('")\ndef call',1)[0]
P=eval('('+P+'")')
FIX={"chef":" Fix: he wears a proper white double-breasted chef's jacket under the navy blazer.",
     "magician":" Fix: exactly ONE small black top hat on his head, with a little white rabbit peeking out of it; no second hat.",
     "doctor":" Fix: a stethoscope hangs around her neck.",
     "honeymooners":" Fix: a short white veil attached to the flower clip at the back of her hair, simple and soft."}
ks=["honeymooners","backpacker","grandpa","kid-solo","athlete","musician","influencer","chef","tourist","knitter","student","skier","doctor","magician","pilot-offduty"]
def call(k):
    refs=[f"ref-{k}.jpg","ref-att-ingame.jpg","ref-seats-top.jpg"]
    parts=[{"inlineData":{"mimeType":"image/jpeg","data":b64(r)}} for r in refs]+[{"text":P+FIX.get(k,"")}]
    body={"contents":[{"parts":parts}],"generationConfig":{"responseModalities":["IMAGE"],"imageConfig":{"aspectRatio":"21:9","imageSize":"2K"}}}
    req=urllib.request.Request("https://generativelanguage.googleapis.com/v1beta/models/gemini-3-pro-image:generateContent",data=json.dumps(body).encode(),headers={"Content-Type":"application/json","x-goog-api-key":key})
    for a in range(2):
        try:
            d=json.load(urllib.request.urlopen(req,timeout=300))
            for p in d["candidates"][0]["content"]["parts"]:
                if "inlineData" in p and not p.get("thought"):
                    open(f"top-{k}.png","wb").write(base64.b64decode(p["inlineData"]["data"])); return k+" OK"
        except Exception as e: pass
    return k+" FAIL"
with cf.ThreadPoolExecutor(5) as ex:
    for r in ex.map(call,ks): print(r)

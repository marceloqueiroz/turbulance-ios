import json, os, base64, urllib.request, concurrent.futures as cf
key=os.environ["GEMINI_API_KEY"]
b64=lambda f: base64.b64encode(open(f,"rb").read()).decode()
refs=[b64(f) for f in ["ref-design.jpg","ref-nervous.jpg","ref-chatterbox.jpg"]]
BASE=("Character design sheet for a cosy, comedic mobile game about a flight attendant. Design a NEW airline PASSENGER in EXACTLY the same art style and body proportions "
"as the characters in the three reference images: a very chunky toy figure about 2.5 heads tall, a big round head, a short round body, short stubby arms and legs, mitten-like hands, "
"big glossy dark eyes, rosy cheeks, soft matte painted-vinyl 3D, warm key light from the upper left, no outlines. Not realistic proportions. "
"Draw the passenger THREE times side by side at eye level, same size, evenly spaced, not touching: LEFT front view, MIDDLE side view walking to the right, RIGHT back view. "
"Keep colours warm and calm; avoid a teal uniform. Background: perfectly flat uniform pure magenta (#FF00FF), no floor, no shadows on the background. "
"No text, letters, numbers or logos anywhere, including on clothes and props. The passenger: ")
V={
 "honeymooners": "a newlywed: a young woman with East Asian features, a short black bob, a cream sundress and a tiny veil-like flower clip, holding a heart-shaped balloon on a short string; dreamy smile.",
 "backpacker": "a backpacker: a young man with light brown skin and a man-bun, a khaki t-shirt, cargo shorts, a huge stuffed backpack with a rolled sleeping mat and a dangling cup; cheerful grin.",
 "grandpa": "a grandfather: an elderly man with dark skin, white moustache and bald head, a brown tweed flat cap and cardigan, a wooden cane, a crossword folded in his pocket; kind squint.",
 "kid-solo": "an unaccompanied child flying alone: a small girl (even shorter and rounder) with light skin and two pigtails, a yellow raincoat, a lanyard pouch around her neck, hugging a plush rabbit; curious wide eyes.",
 "athlete": "a sports team member: a tall-ish broad young woman with deep brown skin and braids in a high ponytail, a red and cream tracksuit, a gym bag over her shoulder and headphones round her neck; confident grin.",
 "musician": "a touring musician: a man with pale skin, shaggy black hair, a leather jacket with pins, round sunglasses pushed up, carrying a guitar case on his back; laid-back half smile.",
 "influencer": "a social media influencer: a young person with light brown skin and pastel pink hair in space buns, an oversized cream puffer jacket, holding a phone up for a selfie; big camera smile.",
 "chef": "a celebrity chef travelling: a round man with olive skin and a bushy black moustache, a white chef's jacket under a navy blazer, a rolled knife bag under his arm; proud, picky expression.",
 "tourist": "a sunburnt tourist: a man with very pink sunburnt pale skin, a straw hat, a loud orange floral shirt, a camera round his neck and a souvenir pineapple; happy and dazed.",
 "knitter": "a knitting grandmother: an elderly woman with East Asian features, white curly hair, a lilac cardigan, knitting needles and a long scarf in progress trailing from a tote bag; content smile.",
 "student": "a sleepy student: a teenager with medium brown skin and a high-top fade, a grey college hoodie, oversized headphones on, a giant takeaway cup; bored half-lidded eyes.",
 "skier": "a skier going on holiday: a woman with light skin and blonde hair, a white knitted bobble hat, a red puffer jacket, ski goggles on her hat, carrying a pair of short skis; excited grin.",
 "doctor": "an off-duty doctor: a woman with South Asian features, dark hair in a braid, a calm teal-grey cardigan over scrubs, a stethoscope peeking from a bag; calm reassuring look.",
 "magician": "a stage magician: a slim-ish man with tan skin, a pointy goatee, a purple waistcoat and small top hat, a white rabbit peeking from the hat; mischievous grin.",
 "pilot-offduty": "an off-duty pilot flying as a passenger: a man with dark skin and grey temples, a navy pilot jacket with gold stripes on the cuffs (no wings, no logos), aviator sunglasses, a rolling flight bag; amused, knowing smile.",
}
def run(k):
    parts=[{"inlineData":{"mimeType":"image/jpeg","data":r}} for r in refs]+[{"text":BASE+V[k]}]
    body={"contents":[{"parts":parts}],"generationConfig":{"responseModalities":["IMAGE"],"imageConfig":{"aspectRatio":"16:9","imageSize":"2K"}}}
    req=urllib.request.Request("https://generativelanguage.googleapis.com/v1beta/models/gemini-3-pro-image:generateContent",data=json.dumps(body).encode(),headers={"Content-Type":"application/json","x-goog-api-key":key})
    for attempt in range(2):
        try:
            d=json.load(urllib.request.urlopen(req,timeout=300))
            for p in d["candidates"][0]["content"]["parts"]:
                if "inlineData" in p and not p.get("thought"):
                    open(f"more-{k}.png","wb").write(base64.b64decode(p["inlineData"]["data"])); return k+" OK"
        except Exception as e: err=str(e)
    return k+" FAIL"
with cf.ThreadPoolExecutor(5) as ex:
    for r in ex.map(run,V): print(r)

exec(open("gen5.py").read().split("with cf.ThreadPoolExecutor")[0])
FIX["influencer"]=(" Important for the two seated poses: she sits upright in the seat like the other passengers, back against the headrest, head at the headrest end, "
 "legs toward the other end, NOT lying down and NOT upside down; in pose 2 she holds her phone up for a selfie.")
import concurrent.futures as cf
with cf.ThreadPoolExecutor(2) as ex:
    for r in ex.map(lambda k: call(k), ["influencer"]): print(r)

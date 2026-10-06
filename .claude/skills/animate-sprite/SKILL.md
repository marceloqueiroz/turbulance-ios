---
name: animate-sprite
description: Make a looping 24-frame movement animation (walk cycle, later run/carry/actions) for a Turbulence character in the approved jet-age soft-3D style, using Gemini over head-locked pose guides, then export it to a SpriteKit atlas and preview it. Use when the user asks to animate a character or passenger, make a walk/run cycle, or add movement frames to the game.
---

# Animate a character sprite (Gemini over head-locked pose guides)

The method that produced the approved attendant walk (`branding/sprites/characters/attendant/walk/`,
in game since 2026-10-06). Gemini gives the look; **motion comes from a pose guide we draw**; the
**head is locked** so the character can't drift; the **clean-up aligns on the head**, never the feet.

Scripts are in `scripts/` (run with `uv run -q --with numpy --with pillow --with scipy python ...`;
the preview also needs `--with "imageio[ffmpeg]"`). Gemini key: `GEMINI_API_KEY` in the repo `.env`.
Work in the scratchpad; copy only finals into `branding/` and the atlas into the app.

## Inputs

- The approved in-game sprite for each view (side faces right; front; back), e.g. `att-side.png`.
- The character design sheet (`ref-design.jpg` for the attendant).
- Facing left = side mirrored in code, so 3 views are enough.

## Steps (per view; do side first and get it approved before front/back)

1. **Cut the locked head** (`cut_head.py`).
   - Side: `--keep-above Y` just under the scarf. Take it from a *good generated frame* if the approved
     sprite has a hand near the face.
   - Front/back: `--ellipse CX,CY,RX,RY` over hair, cap, ears and face (include the mouth). The arms
     touch the head there; ellipse heads keep the sprite canvas on purpose.
   - Look at the result: no hands, sleeves or shoulders.
2. **Draw the pose guide** (`pose_guide.py --view side|front|back --head head.png --out guide.png`).
   - Defaults are the approved walk: `--stride 42 --lift 24 --bob 9`.
   - Look at `guide-peek.png` and `guide.gif` before spending Gemini calls.
   - For a new character, edit `BODY`/`FB` so the mannequin has **that character's proportions**.
3. **Generate 3 takes** (`gen_sheet.py --guide guide.png --view ... --sprite att-VIEW.png --design ref-design.jpg --out out-VIEW`).
   - Pass `--who` and `--look` for characters other than the attendant.
   - Each take is one 4K call, so plan on 3 calls per view.
4. **Cut each take** (`cut_sheet.py out-VIEW-a.png raw-VIEW-a.png`).
5. **Align and score each take** (`align_strip.py raw-VIEW-a.png VIEW-a --bob 4 --height H`).
   - `H`: 625 for side; scale front/back by the approved sprites' height ratio (attendant: front 580,
     back 577) so every view is the same size.
   - Pick the take that passes the checks below, then look at its GIF.
6. **Preview in the scene** (`preview.py VIEW-a-24.png cabin.png out.mp4`). A looping GIF hides sliding
   feet and bad stride length; walking across the cabin shows them.
7. **Export to the game** (`python3 ios/tools/sprite_atlas.py AtlasName 76 side=... front=... back=...`).
   - Writes `Assets.xcassets/<Atlas>.spriteatlas`, 24 frames per view at @3x.
   - 76 pt frame height gives a ~56 pt figure, which fits the 44 pt seat pitch.
   - `CrewNode` in `CabinScene.swift` is the reference consumer (`AttendantArt`): facing from movement
     (side, or front when going down / back when going up), the frame from the walk phase, and a
     passing-pose frame (6) for idle.
8. Show the user the comparison or preview, and install on the phone before calling it done.

## Quality checks (printed by align_strip.py)

| check | good | the attendant's |
|---|---|---|
| head width spread | < 3% | 0.9-1.7% |
| loop seam (frame 23 to 0 change) | within ~2x the median step | 6-7 vs 3-4 (the broken loop was 63) |
| leftover guide colour | < ~50 px orange/blue | 0-18 px |

Reject a take with:
- the wrong background (not magenta);
- blue, orange or grey limbs left in;
- a facing flip;
- legs longer than the approved sprite.

## What we learned (don't repeat these)

1. **Text-only prompts give poor motion.** Describing contact, down, passing and up in words gave tiny
   strides, a wobbling head and frames that switched facing. Gemini needs a pose per frame to paint over.
2. **Use 2D guides, not 3D clay renders, for chibi bodies.** A Blender mannequin rendered from the game
   camera hid the legs under the body. Flat guides with **blue near/left and orange far/right limbs**
   make the leg phase unambiguous.
3. **Lock the real head in every cell.** Without it Gemini drifts across the sheet (frame 1 came out
   ~10% bigger and turned more to camera than frame 24), so the loop pops at the seam. With the same
   pasted head in all 24 cells the drift is gone.
4. **Gemini copies guide proportions literally.** Long mannequin legs gave long legs. Match the approved
   sprite: attendant head ~55%, body ~35%, legs ~10% of height. Keep the stride small to match.
5. **Never align frames on their lowest pixel.** Heels and toes tipping made the body jump 13 px between
   frames. Align on the locked head, apply a smooth synthetic bob (±4 px, two per cycle), and stretch only
   the body below the head (`--cut` 0.55) so the planted foot meets the ground line.
6. **Always run 3 takes and score them.** About 1 in 3 comes back wrong (background or guide colours).
   A seam that is still too big can be repaired: send a grid with the good frames filled in and only the
   bad cells as guides, ask Gemini to repaint only those, and splice them in.
7. **Equal frames.** Every frame is 625 x 848 with feet on y = 775, so the strips tile and the atlas
   frames line up.
8. **Feet slide at game speed, and that's a design call, not a bug.** Stubby legs cover ~0.25 body
   heights per cycle; `crewSpeed` 220 pt/s needs ~19 cycles/s to keep the feet planted. The user accepted
   the walk at game speed; a run cycle is the alternative if it ever bothers them.
9. **Strip characters out of background art with Gemini.** For previews, ask Gemini to remove a
   character painted into the art; hand-patching (inpaint, mirrored patches) looked worse.

## Not working (tried and rejected)

- Cut-out rigs of the approved art: broken and empty joints.
- Blender 3D model: better motion, but the user preferred the Gemini look.
- Meshy image-to-3D with an auto-rigged walk.

## Next uses

Front/back/side walks for passengers (same steps with each passenger's sprites and `--who/--look`), then
action cycles (cleaning, trash, baking, coffee, drinks, snack/toy, luggage, lavatory door). For actions,
write a new guide function in `pose_guide.py` with the action's key poses; keep the locked head and the
same clean-up.

Status: built (simulator TB206; tests 119/119), not yet committed

# N737-Swift painted cabin

## Goal

Route 2's first aircraft, the N737-Swift, plays in a painted jet-age cabin like the Comet instead of the code-drawn
one, with its own "Coastal" identity so it reads as a different plane at a glance. Gameplay doesn't change: every
seat, counter, lavatory and station stays exactly where the layout puts it.

## Source

- [Sprite production plan](https://claude.ai/code/artifact/f4f7c7be-ca84-4a98-a006-521dae7fcfb5) §3 Aircraft cabin
  kits: Swift identity is "Coastal: cream headrest covers with a thin teal stripe, and a curtain between premium and
  economy. Premium seats are wider navy leather." Swappable cabin sets (2026-10-05): one sprite set per aircraft,
  picked by aircraft; a new aircraft may start by reusing the jet-age set.
- [Aircraft Layout Review](https://claude.ai/code/artifact/5df96b28-6e92-4308-959f-569b16e3a2f8) §2 N737-Swift
  (approved and implemented): 3-3 economy (20 rows), 3 rows of 2-2 premium behind a curtain, forward lavatory with a
  wardrobe opposite, two aft lavatories, the Comet's galley and end-wall rules.
- GDD §8a (camera, cabin art).

## Design

- **Painted pieces, composed at the layout's coordinates.** The full Swift is 1326 × 468 world units (≈2.8:1),
  wider than Gemini paints (21:9), and a concept never lands exactly on the layout. So the base is composed, like a
  sprite sheet, at 4 px per world unit over the world rectangle (33, 1)–(1361, 462): Gemini paints the Coastal cabin
  (guided by the game's own render of an 11-row Swift) and then an empty copy of it; the floor and runner repeat from
  a clean stretch of the empty copy, the walls get one window per row, the counters, wardrobe and lavatories are cut
  out and placed on their layout blocks, the curtain is drawn at `curtainX`, and two isolated seat sprites (economy,
  premium; keyed from green) are placed at every layout seat point with a soft shadow. Re-runnable:
  `ios/tools/swift_cabin_compose.py`.
- **Reused from the Comet set:** galley fittings and machine states, trash bins, jump seats and the seated attendant
  (`CabinComet` atlas). Swift-only art: the base picture. The Comet's open lavatory doors are positioned for its own
  lavatories, so they stay Comet-only for now (Swift lavatory doors stay painted shut).
- **Identity:** cream headrest covers with a thin teal stripe on economy seats; wider navy-leather premium seats in
  2-2; a curtain at the premium/economy line; same jet-age floor, runner, lighting and palette as the Comet.
- Out of scope: the A320-Current (same layout, its own identity, next), the 757 and A330, lavatory door art for the
  Swift, the toolkit station art (keeps its code-drawn sprite).

## Changes

- `Rendering/CabinSkin.swift`: `forAircraft(.swift)` with the Swift base and `baseRect`; per-set fitting atlas
  (reuses `CabinComet`); lavatory door art only where a set has it.
- Art: `CabinSwiftBase` image set; sources in `branding/sprites/cabin/swift/` (concept, empty concept, layout
  guide, seat sprites, composed master); composer in `ios/tools/swift_cabin_compose.py`.

## Testing

- Overlay check: the base picture against the game's Swift render (seats, aisle, counters, lavatories, wardrobe).
- Simulator: TB201 (first Swift flight) and a later Swift flight with every station; the follow camera end to end.
- Full test suite (rendering only; no gameplay change expected).

## Open questions

- Does the curtain need its own sprite (to show it open or drawn), or is painted into the base enough?
- The A320-Current shares this layout: reuse the composer with its own identity (coral covers, lighter galley,
  diamond runner).

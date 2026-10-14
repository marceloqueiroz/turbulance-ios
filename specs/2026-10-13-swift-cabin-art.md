Status: in progress

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

- **One painting, lengthened.** The full Swift is 1326 × 468 world units (≈2.8:1), wider than Gemini paints (21:9).
  The concept is painted for an 11-economy-row Swift (1002 wide, the Comet's 2.37:1 framing), guided by the game's
  own render of that layout (`Art.cabin`) so it lands at the layout's proportions like the Comet's did. The game's
  20-row cabin is then made by repeating one economy-row strip (rows are identical, 36 units apart).
- **Empty base picture** like the Comet's: seats empty, galley counters bare (the stations are separate sprites), no
  text or labels. Covers the same world rectangle convention as the Comet (`baseRect`: from 33 units before the nose
  wall line to 35 past the tail, 18 to height − 26).
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
- Art: `CabinSwiftBase` image set; sources in `branding/sprites/cabin/swift/`.

## Testing

- Overlay check: the base picture against the game's Swift render (seats, aisle, counters, lavatories, wardrobe).
- Simulator: TB201 (first Swift flight) and a later Swift flight with every station; the follow camera end to end.
- Full test suite (rendering only; no gameplay change expected).

## Open questions

- Does the curtain need its own sprite (to show it open or drawn), or is painted into the base enough?

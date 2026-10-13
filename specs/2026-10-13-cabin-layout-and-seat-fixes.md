Status: done

# Cabin layout, jump seats and passenger seat fixes

## Goal

Each aircraft's cabin looks the same on every flight. The crew's jump seats look and behave like a real airliner's:
folded flat on the wall, always visible, folding down for turbulence, with the attendant painted sitting in them
and stepping in and out naturally. Galley fittings sit where they should (no jumping oven, trash bins on the walls,
no plunger), and passengers stop climbing over each other to get out of their row.

## Source

- [GDD](https://claude.ai/artifact/TJLwF6QoziD4kvw7fYLhQZ) §4 Aisle traffic, §5b Jump seats, §6a "Only what this
  flight uses", Lavatories art notes. Updated in this work (rev 189): the cabin and its fixtures never change on an
  aircraft; jump seats are wall-mounted and always visible; nobody climbs over a seatmate; no plunger.

## Design

1. **Same cabin per aircraft.** `CabinLayout.equipped(for:)` filters galley stations only. Lavatories, closets,
   jump seats and cabin length match the aircraft's last flight (TB101 now shows the full Comet, lavatories included,
   unused). New stations still pop in with NEW.
2. **Jump seats.** New painted art: `jumpseat-up` (stowed against the wall) and `jumpseat-down`, 39 world units from
   wall plate to cushion edge, the plate 15 units behind the seat point (`CabinSkin.jumpSeatWallInset`). Always shown;
   folded down while the seatbelt sign is on (flights with turbulence) or while someone sits in it. The fold-away
   after Go is removed. Seatbelt-warning glow resized to cover the seat.
3. **Attendant in the seat.** `jumpseat-crew`: the attendant buckled in, seen from above like the cabin and seated
   passengers, drawn at the empty seat's size (her picture replaces the seat and her standing figure while she sits).
4. **Getting in and out.** She stands to use a seat `Tuning.jumpSeatStep` (24) out from it on the aisle. Getting out:
   during the 0.3 s unbuckle she steps forward out of the seat, level with it; she stays at that height while she
   walks along the galley floor to where she's going, then walks down to the aisle line at 70 units/s (sooner if she
   heads into the rows). Getting in: from wherever she's drawn, up to seat level, then back into the seat (0.5 s
   buckle). She faces the way she moves. Drawing only, apart from the stand point.
5. **Oven.** The ready picture's body sits 113 of 700 px lower (steam above); `CabinSkin` offsets it so every oven
   state keeps its body in place.
6. **Forward trash bin** moved from x 76 to 72, flush with the nose wall in line with the jump seat, like the tail bin.
7. **Plunger** painted out of the top lavatory (done on main, 4a03e80).
8. **Leaving a row.** Seatmates nearer the aisle (same row, same side) step out, stand aside along the aisle
   (`Tuning.stepAsideGap` 28, further for seats further in) and sit back once the passenger is out or back in, inner
   seats first. A passenger only gets up if those seatmates can (awake, not sick, no toddler, no live request).
   Seatmates standing aside don't slow the crew or stumble, don't doze while someone further in is out.
9. **Walking passengers** stay at the attendant's height (`PassengerArt.walkScale` 1); standing up and sitting down
   crossfade between the seated and walking pictures; getting on or off a toilet fades instead of jumping.
10. **Attendant front/back frames** were painted bigger than the side ones; drawn at `AttendantArt.frontBackScale` 0.9.

Out of scope: retuning star targets; painted seats for the other aircraft.

## Changes

- `Model/CabinLayout.swift` (equipped, forward trash x), `Model/Campaign.swift` (removed `usesLavatories`),
  `Model/FlightSimulation.swift` (`StrollPurpose.makeWay`, row step-out, `standX(atJumpSeat:)`, `jumpSeatStep`,
  `stepAsideGap`, removed `jumpSeatsAway`), `UI/GameController.swift`.
- `Rendering/CabinSkin.swift` (oven body offset, jump seat and seated-crew sprites, walk scale),
  `Rendering/CabinScene.swift` (jump seat states, seat step drawing, passenger crossfade, front/back scale).
- Art: `CabinComet.spriteatlas` `jumpseat-up/down/crew` (removed `crewseat`); sources in `branding/sprites/cabin/comet/`.

## Testing

- New: `testEveryFlightOfAnAircraftHasTheSameCabin`, `testSeatmateStepsOutToLetAWindowPassengerByAndBackIn`.
- Updated: `testFirstFlightHasNoTrashOrJumpSeatsInPlay`; the two lavatory tests no longer depend on timing.
- Full suite 114/114, including the difficulty bot (TB211 and TB212 sat just under their thresholds in earlier
  iterations; they pass as built, with no retuning).
- Simulator: TB101 vs TB106 cabin, ready oven, forward bin, seat taps in and out recorded frame by frame.

## Open questions

- TB211/TB212 bot margins are thin; if a later change tips them under: re-fit targets, allow extra misses, or soften
  the step-out.

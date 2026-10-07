# Turbulence

A flight-attendant time-management game for iPhone/iPad. Native Swift + SpriteKit (SwiftUI for menus).
Studio: Zelda Labs. The design lives in Claude Docs; this repo is the implementation.

## Source of truth: the design docs

Design and tuning numbers come from the docs, not from the code. When asked to "apply GDD changes", read the
doc diff since the last revision seen, implement it in `ios/`, run tests + a simulator build, and report deltas.
Ask about ambiguities in doc comments rather than guessing.

- GDD: https://claude.ai/artifact/TJLwF6QoziD4kvw7fYLhQZ
- Spawn System: https://claude.ai/code/artifact/a395ca5e-5b62-4b73-bc73-45a06097716e
- Sprite production plan: https://claude.ai/code/artifact/f4f7c7be-ca84-4a98-a006-521dae7fcfb5
- Route Map Plan: https://claude.ai/code/artifact/69e340f5-0e5f-4dcb-83cf-6dfde0f34f27
- Aircraft Layout Review: https://claude.ai/code/artifact/5df96b28-6e92-4308-959f-569b16e3a2f8
- Visual identity & icon brief: https://claude.ai/code/artifact/f0b67508-3fc4-4a39-84bd-18890b090af9
- App Store Submission Plan: https://claude.ai/code/artifact/66b6d2a6-1187-4f4d-a0fd-6d0e7a94e191

Code comments cite GDD sections (e.g. `GDD §5a`); keep doing that.

## Layout

- `ios/Turbulence.xcodeproj` — one scheme, `Turbulence`; targets `Turbulence` and `TurbulenceTests`.
- `ios/Turbulence/Model/` — engine-agnostic game logic, no SpriteKit. Keep it that way.
  - `FlightSimulation.swift` — the simulation; all tuning constants are in `enum Tuning` at the top.
  - `Campaign.swift` — routes, flights (`FlightPlan`), what each flight can roll, menus, pace.
  - `CabinLayout.swift` — rows, aisles, galley stations, lavatories, bins per aircraft.
  - `Profile.swift`, `MapState.swift`, `MapLayout.swift`, `DevSettings.swift` (DEBUG only).
- `ios/Turbulence/Rendering/` — SpriteKit: `CabinScene` (gameplay), `Art` (code-drawn art), `CabinSkin`
  (painted per-aircraft cabin sprite sets; only the Comet so far), `WorldMapScene` + `MapLife` (route map),
  `IntroScene3D` (code-built 3D intro cutscene), `Palette`.
- `ios/Turbulence/UI/` — SwiftUI: `AppModel` (screens, saves), `GameController`, `GameView`, `Landing`,
  `FrontEnd`, `WorldMapView`, `Theme`.
- `ios/Turbulence/Audio/Synth.swift` — synthesized sound.
- `ios/Turbulence/Assets.xcassets` — sprite atlases: `Attendant`, `Passengers`, `PassengerWalk`, `CabinComet`
  (+ `CabinCometBase`), map art under `Map/`.
- `ios/Turbulence/MapLayout.json` — route map regions, airports, paths.
- `ios/TurbulenceTests/` — `FlightSimulationTests` (the big one), `Bot` (a scripted player used to check
  difficulty), `IntensityReportTests`, `MapTests`, `AppModelTests`, `DevToolsTests`.
- `ios/tools/` — asset pipeline scripts (`sprite_atlas.py`, character rig/segmentation, map cutouts, icon tools).
- `branding/` — key art, logos, icon sources, map art, sprite style work and character art
  (`branding/sprites/characters/`). `animation-tests/` is git-ignored.
- `prototype/index.html` — the original web prototype; frozen reference, don't extend it.
- `.claude/skills/animate-sprite/` — project skill for making 24-frame character animations with Gemini.

## Build and test

Use XcodeBuildMCP (call `session_show_defaults` first), or:

```bash
xcodebuild test -project ios/Turbulence.xcodeproj -scheme Turbulence -destination 'platform=iOS Simulator,name=iPhone 17 Pro'
```

Run the tests and a simulator build after gameplay changes.

### Debug launch arguments

- `-flight TB307` — jump straight into one flight.
- `-demo` (`-picker` to open a machine menu) — staged demo cabin, for screenshots.
- `-introAt <seconds>` — freeze the 3D intro on one frame.
- `-resetProfile` — delete saves and device settings.
- `-demoMap`, `-flyAllLegs`, `-mapEditor` (DEBUG) — route map demos and the path editor.

The Options screen has a DEBUG-only Developer section (skip the intro, make a Dev crew with every route open).

## Art pipeline

- In-game style: jet-age soft 3D (painted sprites), no outlines. Brand art is soft 3D too.
- Images are generated with Gemini (`gemini-3-pro-image`), key in `.env` as `GEMINI_API_KEY`. Pass the
  approved character image as a reference to keep characters consistent.
- Character animations: use the `animate-sprite` skill (head-locked pose guides → Gemini → clean-up →
  `ios/tools/sprite_atlas.py` into an atlas). Side views face right; left is mirrored in code.
- Done so far: attendant walk / carry / idle (side, front, back); seated passengers in the Comet cabin;
  walks for the father, business, nervous and sleeper passengers; second crew member is a recolour.
- Work in the scratchpad; copy only finals into `branding/` and atlases into the app.

## Current game rules worth knowing

- Lavatories: a lavatory gets dirty every couple of uses. A dirty one has no timer — passengers queue at the
  door (up to `Tuning.maxLavQueue`) and each one waiting drains satisfaction until it's cleaned on the spot.
  There is no clog / plunger anymore.
- Trash goes in wall bins on the cabin end walls; there's no plunger station.
- Each flight only shows the galley stations it uses (`FlightPlan.uses`).
- The route map is free pan/zoom; the plane follows its route and the camera follows long legs.

## Working conventions

- The user often edits in the same working tree at the same time: never `git stash`, never reset their changes.
  To preview a change, apply it, render (e.g. a temporary XCTest that writes `Art.cabin` to a PNG in the
  scratchpad), then restore only the files you touched.
- Commit only when asked. Commit messages are short, plain-English summaries of what changed in the game
  (see `git log`).
- Never commit `.env` or anything in it (Gemini key, App Store Connect key).

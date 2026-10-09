# Turbulence: Map Unlock & Full Game Spec

Oct 8, 2026 · Live doc: https://claude.ai/code/artifact/7fafd49c-55d1-4b13-8258-af9159b7478c

Route 1 stays free. One non-consumable in-app purchase, **Full Game**, opens Route 2, Route 3 and every future route. The route map shows only one "Coming soon" region, and locked routes get a painted padlock on top of their clouds.

## Decisions

| Topic | Decision |
| --- | --- |
| Product | One non-consumable, Full Game. It covers routes 2 and up, including routes shipped later. |
| Star gates | Kept. Buying removes the paywall; Route 2 still opens at 12 ★ and Route 3 at 36 ★. |
| Coming soon | Only R4 Long Haul stays under storm clouds. S1 Red-Eye, S2 Storm Season and R5 Flagship are hidden until built. |
| Lock art | A painted soft-3D padlock in the jet-age style, closed and open versions. |
| Ownership | The purchase belongs to the Apple ID, so every profile on the device shares it. |

This decides the open business-model question in GDD §9 and the App Store Submission Plan's Price row, which both need updating (see Docs and App Store Connect).

## 1. One Coming Soon region

The map drops from four storm-covered regions to one. Hidden regions stay in the layout file, so bringing one back is a one-line change.

| Region | Today | After |
| --- | --- | --- |
| R4 Long Haul | Storm clouds + "Coming soon" | Unchanged |
| S1 Red-Eye | Storm clouds + "Coming soon" | Hidden: open sea |
| S2 Storm Season | Storm clouds + "Coming soon" | Hidden: open sea |
| R5 Flagship | Storm clouds + "Coming soon" | Hidden: open sea |

- `MapLayout.json`: add `"hidden": true` to S1, S2 and R5. Their art, centre and size stay as they are.
- `MapLayout.Region`: add `var hidden: Bool?`.
- `WorldMapScene.configure`: skip hidden regions completely: no land image, no clouds, no badge, no tap target, no city life.
- `MapState.Cover`: add `.hidden`, returned before any other check.
- Camera: R4 sits near the right edge (x 4400 of a 4900-wide world), and with R5 gone the top-right corner is empty sea. Check the pan limits and opening zoom; tighten the world bounds only if the empty corner shows.

## 2. Locked look: clouds plus a padlock

Every locked route keeps its soft cloud blanket, with a large painted padlock on top at the region's centre. The navy pill sits under the padlock and says why the route is locked.

### Art

- Generate with Gemini (`gemini-3-pro-image`) in the jet-age soft-3D style: brass body, coral accent, no outline. Use an existing map cloud as the style reference.
- Two images: `Map/Padlock` (closed) and `Map/PadlockOpen` (shackle up), cut to transparent PNGs in the scratchpad. Copy only the finals into `Assets.xcassets/Map/` and the sources into `branding/`.
- Size on the map: about 90 pt wide at the default zoom. It scales with the screen-sized badges so it stays readable when zoomed out.

### Badge copy

| State | Title line | Second line |
| --- | --- | --- |
| Needs the purchase | Route 2 · Coastal Shuttle | Full game |
| Owned, needs stars | Route 2 · Coastal Shuttle | 12 ★ to unlock |

The pill no longer needs its own small lock symbol, since the padlock sits above it.

### Motion

- Idle: the padlock bobs a few points on a slow loop, out of phase with the cloud drift. Reduce Motion keeps it still.
- Unlock reveal: the closed image swaps to the open one with a short shake, then the padlock scales up and fades out (about 0.5 s). The existing cloud-parting and path draw-in run after it, unchanged.

## 3. Access rules

A route opens when it is built, owned (if it needs Full Game) and has enough stars. The checks run in that order, so a player without the purchase always sees the paywall first, even with enough stars.

| Route | Needs Full Game | Stars to open | Without purchase | With purchase, short of stars |
| --- | --- | --- | --- | --- |
| 1 Regional Hops | No | 0 | Open | Open |
| 2 Coastal Shuttle | Yes | 12 | Padlock · "Full game" | Padlock · "12 ★ to unlock" |
| 3 Transcontinental | Yes | 36 | Padlock · "Full game" | Padlock · "36 ★ to unlock" |
| 4 Long Haul | Yes | 60 | Storm · "Coming soon" | Storm · "Coming soon" |

### Model changes (`ios/Turbulence/Model/`, no StoreKit import)

- `Route`: add `var requiresFullGame: Bool { id >= 2 }`, citing GDD §9.
- `Profile.isUnlocked(_ route:, fullGame:)` and `isUnlocked(_ plan:, fullGame:)`: the flag is a required parameter, not a default, so no caller can skip the paywall by accident. `nextFlight` becomes `nextFlight(fullGame:)`. About 31 call sites across the app and tests.
- `MapState(profile:fullGame:)`: `RouteAccess` gains `.needsFullGame`. `Cover` gains `.hidden` (section 1); `.clouds` covers both locked cases.
- Reveal after buying: `pendingReveals` already compares open routes with the routes this profile has seen. Once the purchase lands, any route that now passes its star gate plays the reveal with no extra code.
- Flight pins: a flight inside a locked route stays locked, as today.

## 4. StoreKit 2

A small `Store` in `ios/Turbulence/UI/Store.swift` owns everything StoreKit does. The rest of the app sees only one Bool, `ownsFullGame`.

| Piece | What it does |
| --- | --- |
| Product | Non-consumable, ID `<bundle id>.fullgame`. Loaded with `Product.products(for:)` for its `displayName` and `displayPrice`. |
| Buy | `product.purchase()`; on a verified transaction set `ownsFullGame` and call `transaction.finish()`. Pending (Ask to Buy) and cancelled results change nothing. |
| Launch | Walk `Transaction.currentEntitlements` to set `ownsFullGame`. This works offline from StoreKit's cache. |
| Updates | One `Transaction.updates` listener for the life of the app: Ask to Buy approvals, refunds (revocation), Family Sharing. |
| Restore | `AppStore.sync()`, then re-read entitlements. |
| Test seam | `AppModel` reads ownership through a small `Entitlements` protocol, so tests use a fake owner or non-owner. |
| Local config | `ios/Turbulence.storekit` with the one product, attached to the scheme's Run action so purchases work in the simulator without App Store Connect. |

`AppModel` owns the `Store`. When `ownsFullGame` changes, the map rebuilds and plays any pending reveals.

## 5. UI flows

The player reaches the purchase from two places: a padlocked route on the map and the end of Route 1. Restore lives in Options.

| Where | Trigger | Shows |
| --- | --- | --- |
| Route map | Tap a route marked "Full game" | Paywall sheet |
| Route map | Tap a route marked "12 ★ to unlock" | Today's notice (stars needed, stars you have) |
| Results screen | Finish TB106 (last flight of Route 1) without the purchase | "Unlock Route 2" button in place of "Next flight", opening the paywall sheet |
| Options | "Restore purchases" row (required by App Review) | Spinner, then "Full game restored" or "Nothing to restore" |

### Paywall sheet (`UI/PaywallSheet.swift`)

- Key art header, title "Unlock the full game".
- What's included: Route 2 Coastal Shuttle, Route 3 Transcontinental, and every future route, one line each with its aircraft.
- One line on star gates: "Routes still open as you earn stars."
- Buttons: Buy for `displayPrice`, Restore, Not now.
- While buying: buttons disabled with a spinner. On success the sheet closes and the map plays the reveal. Errors show one plain line under the buttons.

### Debug tools (DEBUG builds only)

- Developer section: an "Own full game" toggle that overrides the store.
- Launch arguments `-fullGame` and `-noFullGame`.
- The Dev crew turns ownership on.

## 6. Testing

Every access state gets a unit test, and a purchase is checked end to end in the simulator with the local StoreKit file.

- `MapTests`:
  - route access for each mix of owned / not owned and enough / too few stars
  - hidden regions return `.hidden` and add no tap target
  - exactly one region shows Coming soon
  - a purchase moves the right routes into `pendingReveals`
- `AppModelTests`: buying through the fake store rebuilds the map state; the results screen after TB106 offers Unlock instead of Next flight; Restore with nothing owned reports it.
- `DevToolsTests`: the Dev crew owns the full game; `-fullGame` and `-noFullGame` override the store.
- `FlightSimulationTests`, `Bot`, `IntensityReportTests`: no changes expected; the whole suite runs anyway.
- Simulator: with `Turbulence.storekit`, take screenshots of the padlocked map, the paywall, a purchase, the reveal, a refund (Xcode's transaction manager) and Restore.

## 7. Docs and App Store Connect

The design docs are the source of truth, so they change before the code ships. App Store Connect needs a paid agreement and the product before review.

### Docs

- [ ] GDD §9: replace "to validate, not decided" with free + Full Game non-consumable; Route 1 free.
- [ ] GDD route map section: one storm region (Long Haul), padlock over locked routes, specials hidden until built.
- [ ] Route Map Plan: the same map changes, plus the padlock art and reveal step.
- [ ] App Store Submission Plan: Price row, IAP setup steps, reviewer notes.

### App Store Connect

- [ ] Sign the Paid Apps Agreement; add banking and tax details.
- [ ] Create the non-consumable `<bundle id>.fullgame`: reference name, display name, description, price, review screenshot of the paywall.
- [ ] Turn on Family Sharing for it (can't be turned off later).
- [ ] Attach the IAP to the 1.0 version so it's reviewed with the app.
- [ ] Reviewer notes: "Route 1 is free. Full Game unlocks Routes 2 and up; routes also need stars, so use a sandbox account and the Restore button to check."
- [ ] App Privacy stays "Data Not Collected": StoreKit purchases don't change it.

## 8. Build order and open questions

Rules and tests go first, so the art can arrive last behind a placeholder lock.

1. Access rules and tests (section 3).
2. Hidden regions and the single Coming Soon (section 1).
3. `Store`, local `.storekit` file, paywall sheet, results-screen button, Restore, debug tools (sections 4 and 5).
4. Padlock art and its idle and unlock motion (section 2), replacing a code-drawn placeholder lock.
5. Doc updates and App Store Connect setup (section 7).

### Open questions

- [ ] Price: the GDD suggests $2.99–$4.99. The `.storekit` file uses $3.99 as a placeholder.
- [ ] Family Sharing: recommended on; it can't be turned off later.
- [ ] App Review access: a reviewer who buys still needs 12 ★ to see Route 2. Accept that, or show a short "Earn 12 ★ to open" line on the paywall's success screen?
- [ ] Future specials (Red-Eye, Storm Season): part of Full Game when they ship, or free updates?

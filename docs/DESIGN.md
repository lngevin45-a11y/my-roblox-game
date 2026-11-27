# Bait, Tame & Steal an Egg — Design & Build Notes

> Built via the four-phase flow: **1) Clarify → 2) Design → 3) Implement → 4) Verify**.
> This document records the decisions and the current state of the build.

## Phase 1 — Clarifying decisions (locked)

| Area | Decision |
|------|----------|
| Persistence | **Real `DataStoreService`** (guarded `pcall`; no-ops with a warning in Studio until the place is published + API Services enabled). Cash, food inventory, and tamed creatures/eggs persist. |
| Scope (this pass) | **Full loop**: `food → tame → nest → egg → cash` **plus rival nest raiding & egg theft**, all server-authoritative. |
| Map layout | **Linear "Safari Lane"** (player request — *no central zone*). A long corridor; base plots line one edge like stalls along a street; you throw food down the lane to lure roaming creatures. |
| Movement | **Roblox Physics**: real physics food projectiles (initial velocity + gravity) and creatures that move toward food via `BodyVelocity`. |

## Phase 2 — Architecture

Rojo maps:
- `src/shared` → `ReplicatedStorage.Shared` (Config, Types)
- `src/server` → `ServerScriptService.Server` (init + Greybox, DataStore, PlayerService, FoodSystem, CreatureSystem)
- `src/client` → `StarterPlayerScripts.Client` (init + Hud, Input)

`Greybox` generates 100% of the geometry + `RemoteEvent`s at startup — no external models required.

**Linear map:**
- Lane: `240 × 40` studs along X. Floor top at `y=0`, low walls along edges.
- `8` base plots in a row along the `-Z` edge. Each plot = floor pad + nest pedestal + timed shield dome (visual only this pass) + cash-collection pad (`ClickDetector`).
- Wild creatures spawn at weighted-random points *along the lane* and roam.

**Server-authoritative validation points:**
- Throw: client sends intent `(tier, lookDir)`; server checks cooldown + inventory, consumes one, spawns the projectile.
- Eat / Tame / Cash ticks: all computed on the server.
- Collect: `ClickDetector` on the cash pad; server verifies the clicker owns the plot and is the owner before transferring `pendingCash`.

## Phase 3 — Implemented this pass

- `Config.luau` — all tunables: food tiers, creature tiers (weighted), mutations, map dims, timings, palette.
- `Greybox.luau` — programmatic linear map + remotes.
- `DataStore.luau` — real `DataStoreService` load/save (guarded).
- `PlayerService.luau` — plot claim, tool grant, spawn, HUD init, re-dock saved creatures, save on leave.
- `FoodSystem.luau` — validated physics throws + active-food tracking.
- `CreatureSystem.luau` — weighted spawn, AI toward food, eat → Tame Meter, mutation roll, return-to-nest docking, `$/sec` generation, cash-pad collection, shield-dome visuals.
- Client: `Hud.luau` (cash/food/log/shield ScreenGui), `Input.luau` (tool → `ThrowFood`).

### Core loop (playable now)
Throw food → creature detects (radius) → moves (physics) → eats (tame fills, weighted by food tier) → at 100% rolls mutation (chance scales with food tiers eaten) → creature auto-returns to owner's nest → docked creature generates `$/sec` (tier × mutation mult) → owner clicks cash pad to collect. Tamed creatures persist via DataStore and re-dock on rejoin.

## Art direction (locked from reference images)

Established during the references-first pass. Used to upgrade the greybox visuals
later — **not yet implemented in code**.

- **Creatures / pets:** keep the rounded, friendly, Roblox-inspired look from the
  creature sheet. Tiers (Common→Mythic) differ by color + ornament; mutations
  (Golden / Shadow / Overcharged) are metallic / smoky / cyan-energy variants.
- **Icons / HUD:** keep the icons the user liked (food chips, coin, etc.);
  redesign the HUD around them in the visual pass.
- **Base plots:** each base is a **square plot enclosed by a low fence** (a small
  yard). The fence is intended to be **upgradable to expand the base** — deferred,
  **do NOT implement yet**. The current code uses a plain floor pad + nest; the
  fenced look is the target.
- **Layout (cross-section: base camp at START + long multi-biome path):** players
  spawn in a **base camp at the START** of the world — a cluster of fenced square
  base plots (NOT spread along the path). From there, a REALLY long horizontal
  **multi-biome path** extends forward, split into biome segments (meadow →
  forest → desert → tundra → volcanic), each with its own look and (later) its own
  creature-tier weighting / spawn table. Reference: `images/refs/map_overview.png`.
  The current code uses a single 240-stud lane with 8 plots along one edge — replace
  with base-camp + long multi-biome path when the visuals are built.
  (Biome boundaries are a later build concern; for now just the art direction.)

- **Creature modeling (pixelated / voxel, Steal-a-Brainrot-inspired):** **REAL
  animals** in a chunky blocky voxel style, built from small cubes welded to a
  root Part, flat bright colors, per-tier color + mutation recolor. **No brainrot
  characters.** Tier → animal: Common=Rabbit, Uncommon=Fox, Rare=Wolf, Epic=Bear,
  Mythic=Tiger. No external assets, no CSG union (keeps the multi-color pixelated
  look). Reference: `images/refs/pet_real_animals.png`.

## Phase 4 — Verification (next steps)

Studio playtest checklist:
1. `rojo build -o my-roblox-game.rbxlx` then open in Studio, or `rojo serve` + Studio "Rojo: Connect".
2. Play solo (or 2 players via Team Test). Confirm: lane + 8 plots + nests + domes generate.
3. Equip a food tool, look down the lane, click → a physics projectile arcs out; a nearby creature moves to it and eats.
4. Tame a creature (watch the `Tame Meter %` BillboardGui); on 100% it returns and docks at your nest; a `$/sec` value shows.
5. Wait, then click your green cash pad → cash increases in the HUD; pending resets.
6. Leave + rejoin (with API Services enabled + published) → tamed creatures re-dock and cash persists.

### Raiding & egg theft (implemented — `RaidSystem.luau`)
- Every plot nest has a `ProximityPrompt` ("Hold to Steal Egg", hold = `Config.RAID.STEAL_HOLD`). Only rivals can trigger it; the **shield** blocks theft while active.
- Stealing detaches the most valuable docked creature: its nest entry + egg are removed (owner's income stops) and the creature is **welded above the thief's head**; the thief is slowed to `RAID.CARRY_WALKSPEED`.
- The thief must physically walk back into their **own base** (`RAID.DEPOSIT_RADIUS`) to bank it permanently — `CreatureSystem.bankStolen` re-docks it at their nest (income now theirs).
- The victim's **Stun tool**: within `RAID.STUN_RANGE` it knocks the creature loose — the thief is frozen 2s, the creature's physics are restored and it **runs home** (re-using the returning AI) and re-docks.
- If the thief dies or leaves mid-heist, the creature drops and runs home.

## Notes / caveats
- The attached `superpowers-roblox.md` was empty (0 bytes) at upload time, so the four phases follow a standard Clarify→Design→Implement→Verify flow. Re-upload the file to align to its exact phases.
- `DataStore` requires the game to be **published** with **Studio API Services enabled** to actually persist; otherwise it runs with session-only data and logs a warning (no crash).

# my-roblox-game — Bait, Tame & Steal an Egg

A multiplayer "Bait, Tame & Steal an Egg" prototype built with [Rojo](https://github.com/rojo-rbx/rojo) + Luau.

**Current build (vertical slice):** a linear "Safari Lane" where you throw food to lure and tame wild creatures, dock them at your base nest to lay rare mutated eggs that generate passive cash, and collect it at your cash pad. Server-authoritative, with `DataStoreService` persistence. See [`docs/DESIGN.md`](docs/DESIGN.md) for the full architecture.

> Raid / egg-theft is intentionally deferred to the next pass (hooks for it already exist in the plot model).

## Project layout

```
src/shared/   -> ReplicatedStorage.Shared   (Config, Types)
src/server/   -> ServerScriptService.Server  (init + Greybox, DataStore, PlayerService, FoodSystem, CreatureSystem)
src/client/   -> StarterPlayerScripts.Client  (init + Hud, Input)
```

## Getting started

Build the place from scratch:

```bash
rojo build -o "my-roblox-game.rbxlx"
```

Open `my-roblox-game.rbxlx` in Roblox Studio, then start the Rojo server:

```bash
rojo serve
```

In Studio use the Rojo plugin to connect, then **Play** (solo) or **Team Test** (2+ players).

## Playing the loop

1. Equip a food tool (`Food_Berry` / `Food_Meat` / `Food_Feast`), look down the lane, and click to throw.
2. Nearby wild creatures detect the food, walk to it, and eat — filling a server-tracked **Tame Meter**.
3. At 100%, a **mutation** (Golden / Shadow / Overcharged) is rolled (higher-tier food = better odds); the creature returns to your nest and docks.
4. Docked creatures generate **$/sec** (tier × mutation multiplier). Click your green **cash pad** to collect.
5. Leave & rejoin (with the game published + API Services enabled) and your tamed creatures + cash persist.

## Persistence

Uses real `DataStoreService`. To make saves actually stick, **publish the game** and enable **Studio → API Services**. Until then the game runs with session-only data and logs a warning (it will not crash).

# Matatu Empire (MVP prototype)

Drive a matatu, tout for passengers at the stage, carry them along the route, get paid, and pimp your ride.

This is the **Phase 1–2 prototype** from the design doc: one route between two stages, three matatu tiers, the five Vibe upgrade slots, touting, server-validated fares, levels, a day/night cycle with rush hours, and saving. The city is generated in code, so you can open the place and press Play straight away.

## Quick start (no tooling)

1. Open `MatatuEmpire.rbxl` in Roblox Studio.
2. Press **Play**.
3. Click **Get matatu**. You spawn in the driver's seat at CBD Stage.
4. Press **T** to tout. Hit **T**, **E** or the SHOUT button each time the pink ring lands on the yellow one.
5. Follow the yellow beacon to Estates Stage, stop inside the coloured ring, and you get paid.
6. Press **G** for the garage to buy upgrades and new matatus.

To test saving, publish the place, then turn on **Game Settings → Security → Enable Studio Access to API Services**. Without it, the game runs with in-memory profiles and warns in the output.

## Developing with Rojo

```bash
rokit install          # installs rojo, selene, stylua from rokit.toml
rojo serve             # then click Connect in the Rojo Studio plugin
rojo build -o MatatuEmpire.rbxl   # or build a fresh place file
stylua src             # format
```

For type checking in VS Code, install the **Luau Language Server** extension. The code is written in `--!strict` and passes `luau-lsp analyze` with no errors.

## Controls

| Action | Keyboard | Mobile |
| --- | --- | --- |
| Drive | WASD / arrows | Thumbstick |
| Start touting | T | Tout button |
| Shout (during touting) | T or E | SHOUT button |
| Garage | G | Garage button |
| Horn | H | Horn button |
| Get out | Space | Jump button |

## Project layout

```
src/
  shared/                     -> ReplicatedStorage.Shared
    Config/World.luau         stages, routes, checkpoints
    Config/Vehicles.luau      matatu tiers
    Config/Upgrades.luau      the five Vibe slots and their levels
    Config/Economy.luau       fares, XP curve, rush hours, touting timings
    Net.luau                  remote names + rate limiter
    Types.luau                Profile and ClientState types
  server/                     -> ServerScriptService.Server
    init.server.luau          boots services: init() all, then start() all
    Services/
      PlayerDataService       DataStore load/save with session locking, autosave, BindToClose
      WorldService            builds the map, day/night clock, stage lookup
      VehicleService          constraint-based matatus, driving, cosmetics, speed check, flip recovery
      PassengerService        crowds, touting rounds, trips, fares
      ShopService             upgrades and vehicle purchases
      EconomyService          the only place Bob and XP change
      StateService            sends each player a coalesced state snapshot
  client/                     -> StarterPlayerScripts.Client
    init.client.luau
    Controllers/              Hud, Tout, Garage, Waypoint, State, UI helpers
```

## How the anti-exploit works

The client never sends amounts. The server:

- pays a fare only when the matatu passed every route checkpoint in order, took at least the route's minimum time, and stopped inside the destination zone;
- cancels a trip if the matatu goes faster than 1.5× its tier's top speed;
- generates touting beat times itself and scores the player's presses, ignoring future timestamps and penalising mashing;
- checks prices, levels and ownership for every purchase, and rate-limits every remote.

## Things to tune or add first

- **Driving direction.** If matatus drive backwards, set `DRIVE_SIGN = 1` at the top of `VehicleService.luau`.
- **Feel.** Torque and top speed are per tier in `Config/Vehicles.luau`. Steering lock is `MAX_STEER_DEGREES`.
- **Audio.** Paste licensed sound asset ids into `HORN_SOUND_ID` and `MUSIC_SOUND_ID` in `VehicleService.luau`.
- **Art.** Swap the generated box matatu for a Blender mesh. Keep the `Chassis`, `Body` and `DriverSeat` names, or update `buildMatatu`.
- **Next phases:** Highway district and hired NPC drivers, then saccos and route wars, then rebirth and events (see the design doc).

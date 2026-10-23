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

## Adding the 3D matatu model

`assets/matatu.glb` is a low-poly matatu (about 400 triangles) split into six parts: Body, Livery, Glass, Trim, Lights and TailLights. `assets/matatu-preview.png` shows what it looks like. Until you import it, the game uses the box matatu.

1. In Studio, open **Avatar → Import 3D** (or File → Import 3D) and pick `assets/matatu.glb`.
2. In the importer, keep the parts separate (don't merge meshes) and import.
3. Rename the imported model to **Matatu**.
4. In ReplicatedStorage, create a Folder named **Assets** and move the Matatu model into it.
5. Press Play. Every matatu now uses the mesh, stretched to each tier's size. Paint, glass tint, lights and the other upgrades still apply.

If the matatu faces backwards, select the Matatu model and add a Number attribute **Yaw** = `180`.

To change the shape, edit `tools/make_matatu_mesh.py` and run `python3 tools/make_matatu_mesh.py assets` (only needs numpy). Or open the `.glb` in Blender and model over it. Keep the six part names so the game can find them.

## Developing with Rojo

```bash
rokit install   # installs rojo, selene, stylua, luau-lsp and just from rokit.toml
just            # lists every project command
just serve      # then click Rojo -> Connect in Studio
just build      # builds MatatuEmpire.rbxl
just ci         # format check, lint and type check
```

For type checking in VS Code, install the **Luau Language Server** extension. The code is written in `--!strict` and passes `luau-lsp analyze` with no errors.

## Controls

| Action | Keyboard | Mobile |
| --- | --- | --- |
| Drive | W / Up | Thumbstick up (gamepad: right trigger) |
| Brake, then reverse | S / Down (hold) | Thumbstick down (gamepad: left trigger) |
| Steer | A D / Left Right | Thumbstick |
| Start touting | T | Tout button |
| Shout (during touting) | T or E | SHOUT button |
| Garage | G | Garage button |
| Horn | H | Horn button |
| Get out | Space | Jump button |
| Get back in | F (walk up to your matatu) | Tap the Drive prompt (gamepad: Y) |
| Unstick (reset onto the road) | R | Unstick button (gamepad: D-pad up) |

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

- **Driving.** Handling is arcade-style: the matatu glides on four invisible frictionless skids while a LinearVelocity sets its speed and an AngularVelocity sets its yaw and keeps it level. The rules (acceleration, braking, reverse, turning circle, getting off walls) live in `src/shared/DriveModel.luau`, which has no Roblox dependencies and is unit-tested by `just test`. `Controllers/Drive.luau` feeds it input and applies the result.
- **Feel.** Top speed, reverse speed, acceleration, braking, turn rate and turning radius are per tier in `Config/Vehicles.luau`. Grip and in-air control are `GRIP_FORCE` and `AIR_FORCE` in `Controllers/Drive.luau`.
- **Audio.** Paste licensed sound asset ids into `HORN_SOUND_ID` and `MUSIC_SOUND_ID` in `VehicleService.luau`.
- **Art.** Swap the generated box matatu for a Blender mesh. Keep the `Chassis`, `Body` and `DriverSeat` names, or update `buildMatatu`.
- **Next phases:** Highway district and hired NPC drivers, then saccos and route wars, then rebirth and events (see the design doc).

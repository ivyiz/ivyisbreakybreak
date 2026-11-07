# Ivyis Breaky Break

Egg farming script for **Break and Steal an Egg** (PlaceId `114326934417838`).

- `egg-farmer.lua` — main farmer with in-game UI.
- `auto-reconnect.lua` — rejoins the same server on disconnect (run separately, or drop both in an auto-execute folder).

## Features

- Walk-only movement to selected eggs (no teleporting during farm).
- Multi-select zones and egg types; high-zone eggs are preferred over low-zone ones.
- Strict "wait exact type" mode: if none of the selected eggs are alive it waits instead of farming something else.
- Minimum CPS filter for pets you pick up while carrying.
- Auto-drop carried pets at Zone 1 or Safe Zone.
- Boss pet-drop recovery: if a boss pet is taken from you, the script walks back and re-steals it.
- Auto collect gems: after a gem drop the script walks onto the pieces so the magnet picks them up.
- Start-zone eggs first: eggs closest to the zone entrance are always picked first, even if that means walking back.
- Guard gate: only steals pets or starts a new egg when the nearest ZoneGuard is far enough away (half the zone length).
- Never freezes in place: if the character stops making progress it jumps and sidesteps until it moves again.
- Swing rate follows the game's own cooldown, so pickaxe tiers, the x2 fast-swing gamepass, swing potions and Swinging mastery all apply automatically.
- Auto rejoin on disconnect.
- Config saved between sessions.

## Keybinds

| Key | Action |
| --- | --- |
| `F` | Start / stop farming |
| `K` | Toggle the UI |
| `Tab` | Switch tab (Farm / Drop) |

## Usage

```lua
loadstring(game:HttpGet("https://raw.githubusercontent.com/ivyiz/ivyisbreakybreak/main/egg-farmer.lua"))()
```

The UI opens on load. Pick the zones/eggs, set a minimum CPS, choose the drop area, then press **Start** (or `F`).

## Guard gate

Before stealing a pet or starting a new egg, the script measures the distance to the **guard of the zone being farmed** (other zones' guards are ignored). The guard must be at least **120 studs** away; while it is closer the script waits, and it will also wait if that guard is actively chasing you. After 30 s of waiting it retreats toward the zone entrance, and after 90 s it ignores the gate for that attempt. Change the threshold with `api.setGuardSafeDist(studs)` (0 = default 120).

Run the reconnect companion the same way:

```lua
loadstring(game:HttpGet("https://raw.githubusercontent.com/ivyiz/ivyisbreakybreak/main/auto-reconnect.lua"))()
```

## API

The script exposes itself on `getgenv().EggFarmer` for scripting and testing.

```lua
local api = getgenv().EggFarmer

api.start()
api.stop()
api.toggle()

api.getState()                      -- running, status, counters, selection
api.setEggs({ "Nebula Egg" })       -- select egg types by name
api.selectAll()
api.clearSelection()
api.setMin(50e9)                    -- minimum pet CPS to keep
api.setDropArea("safe")             -- "safe" | "zone1"
api.setAutoGems(true)               -- walk onto gem drops
api.setZoneStart(true)              -- eggs near the zone entrance first
api.setGuardGate(true)              -- wait for guards to move away
api.setGuardSafeDist(0)             -- 0 = default 120 studs
```

`getgenv().EggFarmerCleanup` tears down the UI and all connections; loading the script again calls it automatically.

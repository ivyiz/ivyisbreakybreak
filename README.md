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
- If a carried pet is lost (taken by another player, dropped manually or caught by a guard), the script ignores it for 20 s and keeps farming instead of walking back.
- Auto collect gems: after a gem drop the script walks onto the pieces so the magnet picks them up.
- Smart farm (one toggle): eggs closest to the zone entrance are picked first, and a new steal/egg only starts when the zone's guard is at least 80 studs away. Turning it off disables both the zone-start order and the guard check.
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

## Smart farm

One toggle in the Farm tab controls two things:

- **Start-zone eggs first** — eggs closest to the zone entrance are always picked first, even if that means walking back.
- **Guard watch** - before stealing a pet or starting a new egg, the script measures the distance to the **guard of the zone being farmed** (other zones' guards are ignored). The guard must be at least **80 studs** away; while it is closer the script waits, and it also waits if that guard is actively chasing you. After 30 s it retreats toward the zone entrance, and after 90 s it ignores the gate for that attempt.

Turning the toggle off disables both: the script picks the nearest egg and ignores guards. `api.setGuardSafeDist(studs)` changes the threshold (0 = default 80).

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
api.setSmartFarm(true)              -- zone-start order + guard watch (both)
api.setGuardSafeDist(0)             -- 0 = default 80 studs
```

`getgenv().EggFarmerCleanup` tears down the UI and all connections; loading the script again calls it automatically.

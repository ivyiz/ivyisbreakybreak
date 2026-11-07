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
- Auto mount: for long runs (over 400 studs) it hops on the fastest rideable you own, then dismounts for the last 80 studs so the approach stays precise. Swinging works while mounted too.
- Dodge guards: while a ZoneGuard is chasing close, the script weaves sideways and jumps instead of running in a straight line.
- Never freezes in place while chased: if the character stops making progress it jumps and sidesteps until it moves again.
- Swing rate follows the game's own cooldown, so pickaxe tiers, the x2 fast-swing gamepass, swing potions and Swinging mastery all apply automatically.
- Auto rejoin on disconnect.
- Config saved between sessions.

## Keybinds

| Key | Action |
| --- | --- |
| `F` | Start / stop farming |
| `K` | Toggle the UI |
| `Tab` | Collapse / expand the UI |

## Usage

```lua
loadstring(game:HttpGet("https://raw.githubusercontent.com/ivyiz/ivyisbreakybreak/main/egg-farmer.lua"))()
```

The UI opens on load. Pick the zones/eggs, set a minimum CPS, choose the drop area, then press **Start** (or `F`).

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
api.setEvade(true)                  -- dodge guards while carrying
api.setAutoMount(true)              -- ride the fastest owned mount on long walks
```

`getgenv().EggFarmerCleanup` tears down the UI and all connections; loading the script again calls it automatically.

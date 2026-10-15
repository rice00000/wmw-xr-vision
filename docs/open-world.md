# Open world

*Since 15 Oct 2026 the game is one walkable island instead of separate rooms.
This file describes what is there and the contracts the modules code against.*

## What the game is

A child spawns on the dock of a small island, straight into the welcome task.
The only building is the child's own house. A wizard (simple shapes) greets them
on the dock, holds out a glowing ball, and then walks ahead to wherever the
current task happens. Big landmarks — the giant golden tree, the wooden windmill,
the log gate with its glowing crystal, the dock — make every place findable from
afar. Training happens at fixed **stations** outdoors, and each task says which
visual skill it trains. **Magic Stones are the only currency**: tasks pay stones,
stones buy furniture in the shop on the wrist menu, bought furniture goes to the
bag (no limit) and comes out into your hand to be put anywhere — usually inside
the house.

```
spawn → welcome → find_it (picnic) → butterflies (meadow) → first_furniture → free play
 1 stone           2 stones            2 stones                1 stone
                    ↑ then repeatable from the wrist menu, one at a time ↓
                  earn Magic Stones → shop → bag → take out → place
```

No ending yet.

## The map

`levels/island/island.tscn`, a `Level` with id `island`, about 45 × 51 m. North
is −Z. The walkable ground is flat at y = 0 (stick walking never changes height);
4 m invisible walls run round the beach and the dock, so nobody walks or
teleports off. Dirt paths lead from a crossroads at (0, 12) to every place.

| place id | where | what is there |
| --- | --- | --- |
| `dock` | (0, 28.5), = `Spawn` | the dock, the wizard, a little raft floating beside it |
| `home` | (−9, 4) | centre of the house floor; 7.6 × 7.6 m of empty floor with its own collider, door in the south wall |
| `picnic` | (9.5, 2.8) | the Find It station (`content/stations/picnic_station.tscn`) under the giant tree |
| `meadow` | (−8, −8) | the butterfly station (`content/stations/meadow_station.tscn`) in a ring of flowers |
| `lighthouse` | (0, −16.5) | the north tip, past the magic gate; empty for now |

`picnic` and `meadow` are the stations' own `Place`s; the island adds the other
three. The level also holds the `GuideCharacter`, one `DecorLayout` (furniture can go
anywhere) and three spirit orbs (`modules/vision/vision_orb.tscn`) by the magic
gate. Everything you see is a script-free scene under `content/buildings/`,
`content/landmarks/` or `content/nature/`; the level only instances them.

## Rules

- **One-way dependencies:** `core` ← `player` / `components` ← `modules` ← `content` / `levels`.
  Modules never call each other except through `Events` or `Game.module(&"Name")` (null when off).
- **Training is three layers, one way: `tasks` → `trials` ← `stations`.** `modules/tasks/`
  reads `TrialDef` data (to name a task's skills) and nothing else from trials;
  `modules/trials/` (rounds, their defs, `Training`) knows nothing about tasks or stations;
  `modules/stations/` runs trials and never asks Tasks anything. Between them only `Events`:
  `trial_requested(trial, rounds, title)` down, `finished:<trial>` back.
- **Data-driven:** tasks, trials, skills, items, sounds are resources/tables in `content/`.
- **Art is swappable:** every visible thing's look is its own scene under `content/`
  with meshes (and, for static scenery, its colliders) and **no scripts**. Logic scenes
  instance that visual scene as a child named `Visual`; code only ever references
  scenes, never meshes. Replacing a model = replacing one `.tscn`.
- **Feedback is paired:** sound + visual shape + haptics, never colour alone
  (`Events.feedback`).
- **Quest performance:** `MeshInstance3D` with primitive meshes and shared
  materials, `StaticBody3D` with simple shapes. No CSG on the island.
- **Old code goes:** whatever a change replaces it deletes, in the same change.

## Contracts

### Signals (`core/events.gd`)

| Signal | From → To |
| --- | --- |
| `goal_changed(text, place)` | Tasks → wrist menu, `GuideCharacter` |
| `feedback(kind, position)` via `Events.judge()` — kinds `good`, `bad`, `reward` | anything that judges → Audio (`feedback.<kind>` row), player rig (haptic + shape mark) |
| `read_aloud(text)` | menu → Audio (text-to-speech) |
| `menu_toggled(open)` | menu → anything (world is paused while open) |
| `place_requested(item_id)` | menu bag page → placement layout |

Existing signals stay. `Events.say()` instructions are read aloud by Audio with
text-to-speech when they carry no recorded voice and `read_aloud` is on.

### Facts (reported with `Events.report`)

`opened:menu`, `accepted:<task>`, `bought:<item>`, `taken_out:<item>`,
`placed:<item>`, `put_away:<item>`, `entered:<place>` (a station or place zone),
plus the existing `grabbed`, `pressed`, `caught`, `escaped`, `finished:<trial>`.
Every fact needs a row (or a `-`) in `content/audio/sounds.tsv`.

### Places (`components/place.gd`)

A `Place` is a `Marker3D` with an `id`, in group `place`; each id once per level.
`TaskStep.place` names one; the guide walks to it (`GroundGrid`: never through
a house or across water — a water surface with a collider goes in group `water`).
The island's ids are in the table above.

### Settings (`core/settings.gd`, autoload `Settings`)

`Settings.value(key)`, `Settings.set_value(key, v)`, signal `changed(key, v)`.
Keys: `volume_master`, `volume_voice`, `read_aloud`, `subtitles`, `haptics`,
`move_mode` (`walk` | `teleport`), `turn_degrees`. Core, so anything may read it.

### Skills (`core/skill_def.gd`)

`content/skills/<id>.tres` — `display_name`, `description`. The id is
`TrialDef.skill`. `SkillDef.label(id)`.

### Items (`core/item_def.gd`)

`ItemDef.all()`, `in_shop`, `cost` (in `magic_stone`, the only currency).
Furniture = an item with a `scene`. The inventory has no limit.

### Hover (`components/hover.gd`)

`Hover.set_hovered(node, on)` — the single look of "a hand can use this". Every
grabbable, touchable, creature and menu button uses it.

### Tasks API (`Game.module(&"Tasks")`, for the menu)

One task at a time.

| call | returns |
| --- | --- |
| `current()` | the active task id, or `&""` |
| `goal()` / `goal_place()` | the current step's line / place id |
| `offers()` | task ids that can be accepted now (empty while one is active) |
| `accept(id)` | `bool`; reports `accepted:<id>` |
| `abandon()` | drops the current task (not the welcome task) |
| `describe(id)` | `{title, skills: PackedStringArray (display names), rewards: {item: n}, place, repeatable, times_done, can_abandon}` — hide "Give up" when `can_abandon` is false |
| `remind()` | repeats the current instruction |

### Pause

Opening the wrist menu pauses the tree (`get_tree().paused = true`). The player
rig, the menu and Audio run with `PROCESS_MODE_ALWAYS`. Physics does not step
while paused, so menu buttons detect pokes by distance to nodes in group `hand`,
not by Area3D overlap.

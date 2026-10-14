# XRVision

Whitebox foundation for the **Project Prakash VR game**: a Quest 3 adventure in which children
who have recently regained sight explore, catch creatures, finish quests and decorate their home,
with visual training built into the play.

Godot **4.7.2**, GDScript, Mobile renderer, OpenXR. About 1,400 lines of game code in total;
every file is short enough to read in one sitting.

> Training targets (motion, search, contrast) are placeholders until they are validated with vision researchers.

## Run it

| What | How |
|---|---|
| Desktop (no headset) | Open in Godot 4.7, press F5. Mouse looks, WASD moves, the right hand follows the crosshair (pointing at something touches it), hold left mouse to grab, `H` = help, `Esc` = free mouse. |
| One level only | Open `levels/<name>/<name>.tscn`, press F6. A player is created automatically. |
| PC VR (Quest Link / SteamVR) | Run with `--xr-mode on`. |
| Quest 3 | `tools\quest.cmd all`: build, install, launch and show logs. Also `build`, `install`, `run`, `log`, `shot`, `mirror`. |
| Smoke test | `godot --headless --path . res://tests/smoke_test.tscn -- --slot=smoke_test`. Plays the whole first-playable loop; exit code 0 = pass. |

**First-time setup on a new machine.** `addons/godotopenxrvendors/` (107 MB) is git-ignored:
install the **Godot OpenXR Vendors** plugin (5.1.0) from the editor's asset store / AssetLib, or copy the folder from another project.
The Android build template is installed automatically on the first `quest.cmd build`.
`tools/quest.ps1` has machine paths at the top (Godot, JDK, Android SDK).

In VR: **grip** grabs, touching things with your hand presses / catches them, **left stick** walks,
**right stick** left/right snap-turns, **right stick forward** aims a teleport (release to jump),
**B / Y** repeats the current instruction.

## The first playable (Oct 23)

1. **Home (tutorial):** grab the glowing ball, press the button, walk to the Training Room door.
2. **Training:** catch 3 butterflies. They escape after 20 s, and their speed adapts to the player.
3. **Backyard (quest):** find the blue butterfly among flowers and yellow decoys. Spirits:
   *Clear Sight* removes fog; *Glow Finder* outlines the target.
4. **Reward:** 1 Magic Stone and coins.
5. **Progression:** back home, spend it on the furniture board, then move the furniture by hand. The layout is saved.

All of this is data: quests in `content/quests/`, items in `content/items/`, spirit looks in `content/vision/`.

## Architecture

```
core/        Events (signal bus), Game (XR start, level switching), Level, ItemDef
player/      XR rig: hands, locomotion, teleport, desktop fallback, subtitles, fade, wrist info
components/  generic building blocks: Touchable, TouchButton, Grabbable, Zone/door, Spawner, Scatter
modules/     features, one folder each (see table)
content/     data and small scenes: items, quests, vision profiles, creatures, props
levels/      home / training / backyard
shared/      whitebox materials
```

**Dependency rule:** `core` ← `player` / `components` ← `modules` ← `content` / `levels`.
**Modules never call each other.** They either emit/listen on `Events`, or ask
`Game.module(&"Name")`, which returns `null` when that module is switched off.

| Module | Kind | Does | If you turn it off |
|---|---|---|---|
| `save` | autoload `Save` | Saves any node with `save_state()` / `load_state()`, automatically. JSON in `user://saves/<slot>.json` | Nothing persists |
| `inventory` | autoload `Inventory` | Item id → count. Fills from `Events.reward_granted` | Rewards vanish, furniture is free, wrist info hides |
| `quests` | autoload `Quests` | Linear step quests that count `Events.reported` facts, give rewards, chain | No instructions or rewards |
| `training` | autoload `Training` | Per-skill difficulty (2-down / 1-up staircase) and a JSONL research log in `user://metrics/` | Fixed easiest difficulty, no log |
| `vision` | autoload `Vision` + `VisionOrb` | Spirit "visual abilities": contrast, colour, fog and target outline | Orbs do nothing |
| `voice` | autoload `Voice` | Plays instruction clips. The only audio seam: swap in a Wwise/FMOD bridge here | Subtitles only |
| `placement` | scene nodes | `HomeLayout` (saved furniture), `DecorBoard` (buy and place), `Placeable` (settle on floor) | Delete the nodes |
| `creatures` | scene nodes | `Catchable` (touch to catch → fact, trial, item), `Wander` (adaptive flight) | Delete the nodes |

**Switching a module off:** untick its autoload in *Project Settings → Globals*. The game still runs.
**Removing it for good:** delete its folder and its nodes in levels.

### The shared contract (`core/events.gd`)

| Signal | Emitted by | Used by |
|---|---|---|
| `reported(what, id, data)`, via `Events.report(&"caught", &"butterfly_blue")` | anything: grab, press, enter, catch, place, use | Quests (progress), Training (log) |
| `instruction(text, voice)`, via `Events.say(...)` | Quests, DecorBoard | Subtitle, Voice |
| `reward_granted(item, n)` | Quests, Catchable | Inventory |
| `trial_ended(skill, success, data)` | Catchable | Training |
| `level_changing` / `level_changed` | Game | Fader, Vision, Quests |
| `save_requested` | Quests, Game (headset menu / stop) | Save |

Facts are written `what:id`, and quest steps match them exactly or with `what:*`.
Facts in use today: `entered:<level or zone>`, `grabbed:<id>`, `pressed:<id>`, `caught:<id>`,
`escaped:<id>`, `placed:<item>`, `used:<spirit>`, `asked:help`.

### How interaction works

Interaction is duck-typed, so objects never reference the player:

- A **hand** (`player/hand.gd`) calls `touch(hand)` on any area it enters, and `grab()` / `release()` on `Grabbable` bodies.
- The **head** calls `player_entered(player)` on any area it enters (doors and zones).
- Desktop mode drives the *same* hand, so everything works with mouse and keyboard.

To replace the rig (with Godot XR Tools, for example), point `Game.PLAYER_SCENE` at it and keep those three calls.

## Common tasks

- **New quest:** create a `QuestDef` resource in `content/quests/` (the file name is the id). Add steps such as
  `caught:butterfly ×3`, set `start_on = "entered:backyard"`, rewards and `next`. No code needed.
- **New item / furniture:** an `ItemDef` in `content/items/<id>.tres`. For furniture, its `scene` is a
  `Grabbable` (release mode STAY) with a `Placeable` child, origin at the bottom. Add the id to the `DecorBoard`.
- **New creature:** copy `content/creatures/butterfly.tscn` and change the id and mesh. For a quest target, add it to the `vision_target` group.
- **New spirit ability:** a `VisionProfile` in `content/vision/`, used by a `VisionOrb`.
- **New level:** a root `Node3D` using `core/level.gd`, a `Marker3D` named `Spawn`, a `WorldEnvironment`, and doors from `components/door.tscn`.
- **New saved state:** add `save_state()` and `load_state()` to any node. Nothing else is needed.
- **Per-child profile:** `Save.use_slot("child_07")`, or launch with `-- --slot=child_07`.

## Known limits / next steps

- Visual effects (Environment adjustments, outline) are cheap but **not yet measured on Quest 3**.
- No real art, audio or voice clips yet (`QuestStep.voice` is ready for them).
- Furniture can't be put back into the inventory yet. There is no shop, pets or spirit collection yet.
- Difficulty uses a placeholder staircase; trial definitions need researcher input.
- Smooth locomotion has a simple wall check, not full body collision. Comfort options (vignette, teleport-only) to decide with the team.

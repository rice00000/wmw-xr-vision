# XRVision

A VR magic adventure for children who gained sight late (Project Prakash, ages 8–18): they explore a small island, follow a friendly wizard, do short visual-training tasks at fixed stations, earn Magic Stones and furnish their own house. The training is the play. Who it is for and why is in [docs/project-design-doc.md](docs/project-design-doc.md); the island and its contracts are in [docs/open-world.md](docs/open-world.md).

Godot **4.7.2**, GDScript, Mobile renderer, OpenXR, Meta Quest.

Files are grouped by feature instead of type: each script sits next to its scene and assets, as the [Godot project organization guide](https://docs.godotengine.org/en/stable/tutorials/best_practices/project_organization.html) recommends.

## The game

The child starts on the dock of the island. The only building is their house; the giant golden tree, the windmill, the log gate and the dock are landmarks you can find your way by.

```
welcome          → find_it              → butterflies           → first_furniture  → free play
take the wizard's  5 measured rounds      5 measured catches      buy, take out
ball, open the     at the picnic table    in the meadow           and place a piece
menu, walk on      ("finding things in    ("following things      of furniture
                   a mess")               that move")
1 Magic Stone      2 Magic Stones         2 Magic Stones          1 Magic Stone
```

After that, `find_it` and `butterflies` are offered again from the wrist menu, one task at a time. **Magic Stones are the only currency**: the shop sells furniture for stones, bought furniture goes to the bag, and from the bag it comes out into your hand to be put anywhere. No ending yet.

The **wrist menu** is the only interface: a star on the left wrist (with the current goal and your stones above it) that you touch with the other hand. Pages: Home, Tasks, Shop, Bag, Settings. The world pauses while it is open.

**Controls:** grip grabs, touch to press or catch, left stick walks (or teleport only, in Settings), right stick turns (push forward to teleport), B / Y repeats the instruction or asks for the next hint, the Menu button opens the team's debug panel. Sitting at a station switches stick walking off; teleport still works.

## Run it

- **PC / Mac:** install and open [Meta XR Simulator](https://developers.meta.com/horizon/documentation/native/xrsim-getting-started/), switch on its OpenXR runtime toggle, run the project in Godot. There is no desktop branch: what works in the simulator behaves the same on the headset, so most testing happens on a laptop. (macOS: the preview window is a small always-on-top mirror, because macOS stalls a covered window to ~3 FPS.)
- **Quest builds:** install the **Godot OpenXR Vendors** plugin (5.1.0) from AssetLib, then `tools\quest.cmd all` — build, install, run and log without putting the headset on.
- **Start in one level:** `-- --level=testbed` (a folder under `levels/`, or a `res://` path). The game boots onto the island otherwise.
- **Automated tests:** `tools\test.cmd`. Exit code 0 means every check passed; it uses its own save slot. Headless prints a few harmless `Parameter "material" is null` lines from the dummy renderer.
- **Hand tests:** the Test Room has one station per module, each saying what it checks and going green or red by itself. Menu button → **Tests**, or F6 on `levels/testbed/testbed.tscn`. See [docs/hand-testing.md](docs/hand-testing.md).
- **Look at a level without a headset:** `godot --xr-mode off --path . -s res://tools/capture.gd -- island <out dir>` saves a PNG from child eye height at the spawn and every place, plus an overview.

## Where things are

```
core/        Events (signal bus), Game (XR start, level switching), Level, Settings, ItemDef, SkillDef
player/      XR rig: hands, locomotion, teleport, feedback (haptics + marks), subtitles, fade
components/  building blocks: Place, Touchable, TouchButton, Grabbable, Hover, Zone/door,
             Scatter, Highlight, Contrast
modules/     features, one folder each (table below)
content/     data and looks (below)
levels/      island (the game) and testbed (the Test Room)
shared/      shared materials and the outline shader
tests/       the smoke test and a miniature island fixture
tools/       test.cmd, quest.cmd, capture.gd
docs/        open-world, one-task-system, hand-testing, audio, the design doc
```

`content/` holds data — `tasks/`, `trials/` (+ `objects/` for Find It), `skills/`, `items/`, `vision/`, `audio/sounds.tsv` — and looks: `buildings/`, `landmarks/`, `nature/`, `stations/`, `characters/`, `creatures/`, `effects/`, `items/visuals/`, `trials/objects/visuals/`.

**The visual-scene rule:** everything you see is its own scene under `content/` with meshes (and, for static scenery, colliders) and **no scripts**. A logic scene instances its look as a child named `Visual`; code references scenes, never meshes. Replacing a model means replacing one `.tscn`. Primitive meshes, shared materials, multimeshes for repeated things, no CSG: it has to run on a Quest.

## How modules connect

**Dependencies go one way:** `core` ← `player` / `components` ← `modules` ← `content` / `levels`.
**Modules never call each other.** They emit or listen on `Events`, or ask `Game.module(&"Name")`, which returns `null` when that module is off. To switch one off, untick its autoload in *Project Settings → Globals*; the game still runs, and its Test Room station says MODULE OFF.

**Training is three layers, also one way: `tasks` → `trials` ← `stations`.** `modules/tasks/` (the narrative driver) reads `TrialDef` data to name a task's skills and nothing else from trials. `modules/trials/` (rounds, their definitions, `Training`) knows nothing about tasks or stations. `modules/stations/` runs trials and knows nothing about tasks. Everything between them goes over `Events`: a task asks for rounds with `trial_requested`, a station reports `finished:<trial>`. The smoke test fails the build if a layer's code names one it must not depend on.

| Module | Does |
| --- | --- |
| `save` | Saves any node with `save_state()` / `load_state()` to `user://saves/<slot>.json` |
| `inventory` | Item id → count (no limit), filled from `reward_granted` |
| `tasks` | **The driver.** One task at a time: walks a `TaskDef` through its steps, pays the rewards, offers repeatable tasks to the menu. A step can ask for measured rounds over the bus |
| `trials` | One measured round and how it is built: `Trial`, `TrialDef`, `TrialAxis`, `TrialCondition`, `TrialRunner`; one subfolder per kind of round, `search/` (`SearchTrial`, Find It) and `catch/` (`CatchTrial`, butterflies). Also the `Training` autoload: difficulty per skill (staircase → `TrialCondition`) and the research log in `user://metrics/` |
| `stations` | Scene nodes: `Station`, a fixed spot that runs a trial when it is asked to (a seat, a `TrialRunner` and its `Trial`, a sign, a beacon) |
| `guide` | Scene nodes: the `GuideCharacter` (today it looks like a wizard, `content/characters/wizard.tscn`), who walks ahead to the current goal's place on a `GroundGrid` (A* on the physics world), and holds out the welcome's ball |
| `menu` | The wrist menu: goal and stones on the wrist, pages Home / Tasks / Shop / Bag / Settings |
| `placement` | Scene nodes: `DecorLayout` (furniture out of the bag, into a hand, saved where it stands), `Placeable`, the put-away button |
| `creatures` | Scene nodes: `Catchable`, `Wander` |
| `vision` | Spirit abilities (contrast, colour, fog, target outline) via `VisionOrb` |
| `audio` | **All sound**, from one table (`content/audio/sounds.tsv`), plus text-to-speech for lines with no recording. No audio code exists outside this module |
| `debug` | The team's hidden panel (difficulty by hand, the door to the Test Room) and the Test Room's check stations. Untick it for a child build |

**Signals (`core/events.gd`):**

| Signal | From → To |
| --- | --- |
| `reported(what, id, data)` via `Events.report()` | anything → Tasks, Audio, Training |
| `instruction(text, voice)` via `Events.say()` | Tasks, stations → subtitles, Audio |
| `goal_changed(text, place)` | Tasks → wrist menu, `GuideCharacter` |
| `feedback(kind, position)` via `Events.judge()` — `good`, `bad`, `reward` | anything that judges → Audio, player rig (haptic + shape mark) |
| `cue(sound, position)` via `Events.play_at()` | trials → Audio |
| `reward_granted(item, n)` | Tasks, Catchable → Inventory |
| `trial_requested(trial, rounds, title)` | Tasks → the station that runs that trial (`rounds` −1 withdraws; `title` is for its sign) |
| `trial_started(trial, condition)` / `trial_ended(skill, success, data)` | trials → Training, Debug |
| `task_started` / `task_completed` | Tasks → anything |
| `read_aloud(text)` | menu → Audio |
| `menu_toggled(open)` | menu → anything (the world is paused while open) |
| `place_requested(item)` | menu bag page → DecorLayout |
| `level_changing` / `level_changed` | Game → fader, Vision, Tasks, Audio |
| `save_requested` | Tasks, Game → Save |

**Facts** look like `what:id` and are what task steps wait for, exactly or with `what:*`: `grabbed:<id>`, `pressed:<id>`, `caught:<id>`, `escaped:<id>`, `entered:<place or level>`, `finished:<trial>`, `opened:menu`, `accepted:<task>`, `bought:<item>`, `taken_out:<item>`, `placed:<item>`, `put_away:<item>`, `asked:help`, `asked:menu`. Every fact needs a row (or a `-`) in the sound table; the test suite lists any that are missing.

**Interaction** is duck-typed, so objects never reference the player: a hand calls `touch(hand)` on areas it enters and `grab()` / `release()` on `Grabbable`s, the head calls `player_entered(player)` on zones, and `Hover.set_hovered()` is the one look of "a hand can use this".

## Tasks and trials

A **task** is what the child is asked to do; a **trial** is one measured round inside it. One word for each, one layer each (`modules/tasks/`, `modules/trials/`), and the station that runs a trial is a layer of its own on top of trials — [docs/one-task-system.md](docs/one-task-system.md) says why there is no third kind of thing to ask the child to do. A `TaskDef` (`content/tasks/<id>.tres`) is a list of `TaskStep`s, rewards (Magic Stones), what starts it, the task that follows, whether the menu offers it again. A step either waits for a fact `count` times, or names a `trial`, and then `count` is rounds: the request goes out on the bus, the station for that trial answers, and the step ends on `finished:<trial>`. A step can name a `place`, and the guide leads the child there.

## How training works

One round is a **trial**. The station's `TrialRunner` asks `Training` for a `TrialCondition`, hands it to its `Trial`, waits for the round to end, and goes again.

- **One scalar, named axes.** `Training` keeps a single 0–1 difficulty per *skill* and moves it with an N-up / 1-down staircase (2 up / 1 down settles near 71% correct). A trial never reads that scalar: its `TrialDef` spreads it over named axes (`clutter`, `overlap`, `contrast`, `speed`...), and only axes marked `driven` follow it. The rest sit at a fixed value and are logged anyway, so a failed round stays attributable to **one** variable.
- **Contrast is a property of the object, not of the scene.** `components/contrast.gd` grades one object to a stated Weber contrast against the surface behind it (the tablecloth). The `vision` module's contrast is a whole-scene spirit ability the child switches on.
- **Help escalates, then fades.** The hint level rises after `TrialDef.hint_after` seconds without progress, that delay grows by `hint_fade` every round, and the level reached is logged. B / Y asks for the next hint now. Motion is a hint rung, not a difficulty axis.
- **Sessions open with a baseline.** `TrialDef.probe_rounds` unscored rounds at a fixed difficulty with help off, which never move the staircase — a pre / post when repeated later.
- **Every round is one line** in `user://metrics/<session start>.jsonl`: time, tries, hint level, every axis value, the difficulty, whether it was a probe, the target and what was picked.

## Sound

Game code reports what happened, and the `audio` module looks the answer up in one tab-separated table. `pressed.hello` falls back to `pressed`, so one row gives every button a sound. A row names a clip or a `tone:660` placeholder beep, with volume, pitch variation, bus, 2D/3D, cooldown and looping. Mistakes in the table, and facts no row answers, fail the test suite. [docs/audio.md](docs/audio.md) is the whole of it.

## How to add things

- **Task:** a `TaskDef` in `content/tasks/`, steps like `caught:butterfly ×3` or a step naming a trial, rewards in `magic_stone`. No code.
- **Trial:** a `TrialDef` in `content/trials/<id>.tres` plus a `Trial` subclass (`_setup()`, `_hint()`, `finish()`) in `modules/trials/<kind>/`, and a station that runs it: an inherited scene of `modules/stations/station.tscn` with the trial under `Runner` and its look as `Visual` (see `content/stations/`). Drop the station in the level.
- **Skill:** `content/skills/<id>.tres` with `display_name` and `description`; the id is `TrialDef.skill`.
- **Item / furniture:** an `ItemDef` in `content/items/<id>.tres` (`in_shop`, `cost` in `magic_stone`). Furniture also has a `scene`: a `Grabbable` with a `Placeable` child and its look as `Visual` from `content/items/visuals/`. The shop and bag pick it up by themselves.
- **Place:** a `Marker3D` with `components/place.gd` and a unique `id` in the level, standing where the child should end up. A station brings its own.
- **Scenery:** a script-free scene under `content/buildings/`, `content/landmarks/` or `content/nature/`, instanced in `levels/island/island.tscn`. Obstacles get colliders at least 2.5 m tall (their tops are then never a teleport target); keep walkable ground at y = 0.
- **Sound:** a row in `content/audio/sounds.tsv`. No code, ever.
- **Saved state:** `save_state()` / `load_state()` on any node.
- **Module:** an autoload in `modules/<name>/`, plus its station in the Test Room — see [docs/hand-testing.md](docs/hand-testing.md).

**Not done yet:** real art and recorded voice lines (placeholder tones and text-to-speech for now); more stations and skills; an ending; per-child calibration of where difficulty starts; validation with vision researchers, or with a child in the group it is for.

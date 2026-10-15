# XRVision

A VR magic adventure for children who gained sight late (Project Prakash, ages 8–18). Explore an island, follow a guide, practise visual skills, earn Magic Stones and decorate a home. Ideas are still open; the project is built to be extended.

Godot **4.7.2**, GDScript, Mobile renderer, OpenXR, Meta Quest.

**Playable loop:** welcome → Find It at the picnic table → catch butterflies in the meadow → buy and place furniture → free play. Training tasks can be repeated from the wrist or debug menu.

## Run it

- **PC / Mac:** install [Meta XR Simulator](https://developers.meta.com/horizon/documentation/native/xrsim-getting-started/), enable its OpenXR runtime, then run the project in Godot. The simulator uses the same XR controls as the headset.
- **Quest:** install Godot OpenXR Vendors **5.1.0** and the Android build template. Connect and authorize the headset, then run the **Meta Quest 3** export preset.
- **Tests:** `python tools/test.py`; set `GODOT` for a custom engine path. Tests use a separate save. For interactive checks, open the Test Room through Debug → Saves & testing. See [hand tests](docs/hand-testing.md) and [command-line playtesting](docs/command-playtesting.md).

**Controls:** grip grabs; touch catches creatures and presses world buttons. Left stick walks; right stick turns (forward teleports). B / Y asks for help. Touch the left wrist star or release Menu (simulator M) to open the menu; point and pull the trigger to select. Close through Home → Close or Menu. Menu + Y toggles Debug. The world pauses while menus are open.

## Where things are

Files are grouped by feature: scripts sit beside their scenes and assets.

```text
core/        Events, Game, Profile, Narrator, settings and shared data types
player/      XR rig, hands, movement, feedback and subtitles
components/  reusable interaction, placement and visual building blocks
modules/     tasks, trials, stations, guide, menu, save, inventory,
             placement, creatures, vision, audio and debug
content/     task/trial/item data, visual scenes and audio table
levels/      island and testbed (Test Room)
shared/      materials and shaders
tests/       automated checks
tools/       testing, capture and Quest deployment
```

## How modules connect

Dependencies: `core` ← `player` / `components` ← `modules` ← `content` / `levels`.
Modules communicate through `Events`; `Game.module()` looks up optional modules.

Tasks owns the current goal (`Events.goal`). Trials measure each round; stations host them. Training adjusts difficulty and logs results. Narrator keeps voice and subtitles together. Each save’s progress, settings and logs live in `user://profiles/<id>/`.

## How to add things

- **Task:** a `TaskDef` in `content/tasks/`, with fact or trial steps and rewards.
- **Trial:** a `TrialDef`, a `Trial` subclass and a station scene.
- **Furniture:** an `ItemDef` and a `Grabbable` scene with a `Placeable` child.
- **Visuals:** script-free scenes under `content/`, instanced as `Visual` children.
- **Sound:** a row in `content/audio/sounds.tsv`.
- **Saved state:** `save_state()` / `load_state()` on a node.

Details: [tasks and trials](docs/one-task-system.md), [world](docs/open-world.md), [state and narration](docs/state-and-narration.md), [audio](docs/audio.md), [team design](docs/project-design-doc.md).

**Still to do:** real art and recorded voices, more training content, an ending, per-child calibration and validation with researchers and children.

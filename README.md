# XRVision

A VR magic adventure for children who gained sight late (Project Prakash, ages 8–18). Explore an island, follow a guide, practise visual skills, earn Magic Stones and decorate a home. Ideas are still open; the project is built to be extended, all artwork is placeholder art.

Godot **4.7.2**, GDScript, Mobile renderer, OpenXR, Meta Quest.

**Playable loop:** welcome → Find items in clutter at the picnic table → catch butterflies in the meadow → buy and place furniture → free play. Training tasks can be repeated from the wrist menu or facilitator panel.

## Run it

- **PC / Mac:** install [Meta XR Simulator](https://developers.meta.com/horizon/documentation/native/xrsim-getting-started/), enable its OpenXR runtime, then run the project in Godot. The simulator uses the same XR controls as the headset.
- **Quest:** install Godot OpenXR Vendors **5.1.0** and the Android build template. Connect and authorize the headset, then run the **Meta Quest 3** export preset.

**Controls:** grip grabs; touch catches creatures and presses world buttons. Left stick walks, including during tasks; right stick turns (forward teleports). B / Y asks for help. Touch the left wrist star or release Menu (simulator M) to open the menu; point and pull the trigger to select. Close through Home → Close or Menu. Menu + Y toggles the Facilitator panel (difficulty, save slots). The world pauses while menus are open. View height (Lower / Higher) is on the menu's Settings page.

## Where things are

Code sits in layers by what it may depend on. Where a file goes:

1. Has its own script → `modules/<system>/`.
2. A building block several systems use → `components/`.
3. Otherwise it is a thing in the game (a chair, a cup, a task, a sound, a material) → `content/<kind>/`. It may use scripts from `components/` or `modules/`, never its own; `buildings/`, `landmarks/` and `nature/` are scenery with no scripts at all. A piece only one level uses sits in that level's folder.

```text
core/        Events, Game, Profile, Narrator, settings and shared data types
player/      XR rig, hands, movement, feedback and subtitles
components/  reusable interaction, placement and visual building blocks
modules/     tasks, trials, stations, guide, menu, save, inventory,
			 placement, creatures, vision, audio and facilitator
content/     task/trial/item data, visual scenes, materials and audio table
levels/      island
tests/       automated checks
tools/       testing, capture and Quest deployment
```

## How modules connect

Dependencies: `core` ← `player` / `components` ← `modules` ← `content` / `levels`. Code may also load content by path (a data folder, a table, a visual). `core` knows one scene by path: the player rig.
Modules communicate through `Events`; `Game.module()` looks up optional modules. The only direct links: `stations` and `tasks` use `trials` types, and the catch trial drives `creatures`' `Wander`. `facilitator` may use anything.

Tasks owns the current goal (`Events.goal`). Trials measure each round; stations host them. Training adjusts difficulty and logs results. Narrator keeps voice and subtitles together. Each save’s progress, settings and logs live in `user://profiles/<id>/`.

## How to add things

- **Task:** a `TaskDef` in `content/tasks/`, with fact or trial steps and rewards.
- **Trial:** a `TrialDef`, a `Trial` subclass and a station scene.
- **Furniture:** an `ItemDef` and a `Grabbable` scene with a `Placeable` child.
- **Visuals:** script-free scenes under `content/`, instanced as `Visual` children.
- **Sound:** a row in `content/audio/sounds.tsv`.
- **Speech:** edit the text; the editor bakes audio automatically. See [baked speech](docs/baked-speech.md).
- **Saved state:** `save_state()` / `load_state()` on a node.

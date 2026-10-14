# XRVision

A VR magical adventure in which children who have recently regained sight explore, catch creatures, finish quests and decorate their home, with visual training built into the play.

Godot **4.7.2**, GDScript, Mobile renderer, OpenXR.

Files are grouped by feature instead of type: each script sits next to its scene and assets, as recommended by the official [Godot project organization guide](https://docs.godotengine.org/en/stable/tutorials/best_practices/project_organization.html).

**First playable loop:** Home tutorial → Training (catch 3 butterflies) → Backyard quest (find the blue butterfly) → Magic Stone → buy and place furniture at home.

## Run it

- **PC / Mac:** install and open [Meta XR Simulator](https://developers.meta.com/horizon/documentation/native/xrsim-getting-started/), switch on its OpenXR runtime toggle, run project in Godot.
  - **Why the simulator:** The input translation lives outside the game, so there is no desktop branch to write, maintain or drift from VR. What works in the simulator behaves the same on the headset, so most testing happens on a laptop and the Quest is only needed for performance and comfort. It makes project maintenance and testing more efficient.
  - Interesting MacOS note: The godot preview window is configured as a small always-on-top mirror (`project.godot`) as when another window covers it, macOS stalls its frames to ~3 FPS.
- **Quest builds:** install the **Godot OpenXR Vendors** plugin (5.1.0) from AssetLib. WIP

**Controls:** grip grabs, touch to press or catch, left stick walks, right stick turns (push forward to teleport), B / Y repeats the instruction.

## Where things are

```
core/        Events (signal bus), Game (XR start, level switching), Level, ItemDef
player/      XR rig: hands, locomotion, teleport, subtitles, fade, wrist info
components/  generic building blocks: Touchable, TouchButton, Grabbable, Zone/door, Spawner, Scatter
modules/     features, one folder each (table below)
content/     data: items, quests, vision profiles, creatures, props
levels/      home / training / backyard
shared/      whitebox materials
```

## How modules connect

**Dependencies go one way:** `core` ← `player` / `components` ← `modules` ← `content` / `levels`.
**Modules never call each other.** They emit or listen on `Events`, or ask `Game.module(&"Name")`, which returns `null` when that module is off.
To switch a module off, untick its autoload in *Project Settings → Globals*. The game still runs without it.


| Module      | Does                                                                             |
| ----------- | -------------------------------------------------------------------------------- |
| `save`      | Saves any node with`save_state()` / `load_state()` to `user://saves/<slot>.json` |
| `inventory` | Item id → count, filled from`reward_granted`                                    |
| `quests`    | Step quests that count`reported` facts and give rewards                          |
| `training`  | Adaptive difficulty per skill and a research log in`user://metrics/`             |
| `vision`    | Spirit abilities (contrast, colour, fog, target outline) via`VisionOrb`          |
| `voice`     | Plays instruction clips; the only audio seam                                     |
| `placement` | Scene nodes:`HomeLayout`, `DecorBoard`, `Placeable`                              |
| `creatures` | Scene nodes:`Catchable`, `Wander`                                                |

**The signals (`core/events.gd`):**


| Signal                                                                   | From → To                            |
| ------------------------------------------------------------------------ | ------------------------------------- |
| `reported(what, id)`, e.g. `Events.report(&"caught", &"butterfly_blue")` | anything → Quests, Training          |
| `instruction(text, voice)` via `Events.say()`                            | Quests, DecorBoard → Subtitle, Voice |
| `reward_granted(item, n)`                                                | Quests, Catchable → Inventory        |
| `trial_ended(skill, success)`                                            | Catchable → Training                 |
| `level_changing` / `level_changed`                                       | Game → Fader, Vision, Quests         |
| `save_requested`                                                         | Quests, Game → Save                  |

Facts look like `what:id` (`caught:butterfly`, `entered:backyard`); quest steps match them exactly or with `what:*`.

**Interaction** is duck-typed, so objects never reference the player: a hand calls `touch(hand)` on areas it enters
and `grab()` / `release()` on `Grabbable`s; the head calls `player_entered(player)` on doors and zones.

## How to add things

- **Quest:** a `QuestDef` in `content/quests/` with steps like `caught:butterfly ×3`. No code.
- **Item / furniture:** an `ItemDef` in `content/items/<id>.tres`. Furniture scenes are a `Grabbable` with a `Placeable` child; add the id to the `DecorBoard`.
- **Creature:** copy `content/creatures/butterfly.tscn`. Quest targets go in the `vision_target` group.
- **Level:** a `Node3D` with `core/level.gd`, a `Marker3D` named `Spawn`, and doors from `components/door.tscn`.
- **Saved state:** add `save_state()` / `load_state()` to any node.

**Not done yet:** real art, audio and voice; researcher-defined training trials (placeholders now); comfort options.

# Hand-testing: the Test Room

Every module has one station in a room you can be standing in within ten
seconds. Each station says, on a sign in front of you, what it is checking, the
one thing to do, and what counts as a pass — and then goes green or red by
itself. Nothing to remember, nothing to count, no code to read.

## Get in

Three ways, pick whichever you are already holding:

| where you are | what to do |
| --- | --- |
| Godot editor | open `levels/testbed/testbed.tscn`, press **F6** |
| already in the game (PC or headset) | **Menu** button → **Tests** on the debug panel |
| cold start, any build | launch with `-- --level=testbed` |

The last one works on the Quest too — `tools\quest.cmd` passes it through — so
you can go from "APK installed" to "standing in the Test Room" without walking
the game.

A fourth way, with nobody in the headset: `tools\test.cmd`. It runs every
station headless along with the rest of the suite, and prints each verdict by
name. Exit code 0 means everything passed. It takes about eight seconds.

## In the room

You spawn at one end of an aisle. A pedestal per module faces you down both
sides, in the order they are worth testing; a free-play picnic station stands
beside them, and a door at the end takes you back to the island. At the far end
is the board:

```
TEST ROOM
12 / 13 PASS   1 FAILED

  Player rig    PASS
  Save          PASS
  Inventory     PASS
  Tasks: chain  FAIL
  ...
```

Two buttons at the board:

- **RUN ALL** — does every station's action in code, in order, and waits for the
  ones that need time. Thirty seconds from walking in to knowing whether the
  build is sound. This is the same code path the automated suite uses.
- **RESET** — every station back to WAITING, so you can do them by hand.

Doing them by hand is the slower, more honest pass: RUN ALL proves the
machinery, your own hands prove the machinery *plus* the reach, the collider
sizes, the labels and whether any of it is actually usable.

## What each sign says

```
INVENTORY

CHECK   a granted item lands in the count
DO      touch Give 1 Magic Stone
PASS    the Magic Stone count goes up by exactly one

WAITING   Magic Stone 10
```

The bottom line is the verdict, big and coloured: grey WAITING, green PASS, red
FAIL, dark grey MODULE OFF. Next to it are the live numbers the verdict was
reached from, so a red station tells you *what* it saw, not just that it is
unhappy.

**MODULE OFF is not a failure.** Untick a module's autoload in *Project
Settings → Globals* and its station greys out and says so, while every other
station still goes green. That is the architecture's "any module can be removed"
rule showing itself rather than being claimed.

## The thirteen stations

| # | station | module | the one move |
| --- | --- | --- | --- |
| 1 | Player rig | — | grab the ball, press B / Y |
| 2 | Save | `Save` | Add 1, then Save + reload |
| 3 | Inventory | `Inventory` | Give 1 Magic Stone |
| 4 | Tasks: chain | `Tasks` | Report a fact, twice |
| 5 | Trials: round | — | Start a round, grab the named object |
| 6 | Training | `Training` | Right, Right, Wrong |
| 7 | Vision | `Vision` | touch the spirit orb |
| 8 | Audio: seam | `Audio` | Say + beep |
| 9 | Audio: table | `Audio` | Press me |
| 10 | Placement | `Inventory` | Take a chair out, let go, grab it, Put away with the other hand |
| 11 | Creatures | — | touch the butterfly |
| 12 | Debug panel | `Debug` | press the Menu button |
| 13 | Wrist menu | `Menu` | touch the star on your left wrist, then Close |

Stations 1, 5 and 11 have no module column because what they check is scene
nodes and the player rig, not an autoload: there is nothing to untick.

Station 9 is worth a second look. Its button is an ordinary `TouchButton` with
nothing connected to it and no audio code in it anywhere, and it still makes a
sound, because `content/audio/sounds.tsv` has a row for it. Its waiting line
also lists any key the game has sent that the table has no row for — that list
is the table's to-do list. See [audio.md](audio.md).

Station 1 is first on purpose. Everything further down the aisle assumes a hand
can grab and a button can be pressed, so if it is red nothing after it means
anything.

## What the room does to your data

- It runs its own throwaway task (`content/tasks/selftest.tres`) and forgets it
  again on reset, so hand-testing never shows up in a child's progress.
- Its measured round uses its own trial and its own skill
  (`content/trials/selftest.tres`, skill `selftest`), so pressing a button here
  can never move a staircase the game trains. Its lines are still written to
  `user://metrics/`, one grep away from the real ones.
- Everything else — Magic Stones, the Save station's counter, a caught butterfly —
  lands in whatever save slot you launched with. Launch with
  `-- --slot=testbed` if you care about the slot you were playing.

## Adding a station

A new module needs a new station, or the room stops meaning "every module".

1. A script in `modules/debug/checks/` extending `ModuleCheck`. Build your props
   in `_arm()`, decide with `pass_now()` / `fail_now()`, and do the tester's part
   in `auto()` so the headless suite can run it too.
2. A `Node3D` in `levels/testbed/testbed.tscn` with that script, named
   `Check<nn><Name>` (the board lists them in name order), with `module`,
   `title`, `checks`, `action` and `pass_when` filled in.
3. Bump the expected station count in `tests/smoke_test.gd`.

The suite asserts that every station's sign is filled in and that every station
goes green, so a half-written station fails the build rather than sitting there
grey.

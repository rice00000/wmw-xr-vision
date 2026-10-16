# One truth: state, narration and saves

*Decision taken 15 Oct 2026, after a playtest where the picnic table seemed to
do nothing, the voice and the subtitle said different things, and restarting
did not always give a clean game.*

## What was wrong

None of it was two tasks running at once; `Tasks` already ran one. The current
task was **shown in five places that each kept their own copy**:

| Copy | Kept by | Fell out of step when |
| --- | --- | --- |
| subtitle queue + timer (60 ms/char) | `player/subtitle.gd` | the menu paused it but not the voice |
| speech queue | the OS text-to-speech engine | any menu read-aloud flushed it (`interrupt = true`) |
| "wanted", title, round budget | `Station` + `TrialRunner` | a request was lost or re-sent; rounds counted twice |
| goal text | wrist menu `_goal` | read before the step moved on |
| line timing (65 ms/char) | `Tasks`, `Station`, the guide | real speech ran at its own speed |

Example: opening the menu completed the welcome's second step. "Follow me to the
picnic table!" went to the speech queue, and the menu's own read-aloud wiped it
in the same frame. The subtitle held it until the menu closed. So the child
**never heard it**, and read it only once the menu had closed.

Saving only happened on task completion and focus loss, so mid-task progress
could roll back. Start over patched nodes in place and left queued lines, timers,
facilitator pins, the vision ability and the open research log behind.

## Current design

*Task persistence updated 16 Oct 2026; see [tasks and task lists](tasks.md).*

**One owner for each thing; everyone else reads it and keeps no copy.**

- **Goal** (`core/goal.gd`): `Tasks` builds one snapshot after every change
  (task, step, text, place, the fact or trial it waits for, done / needed) and
  publishes it with `Events.set_goal()`. `Events.goal` keeps the latest, so a
  level built later reads it instead of waiting to be told again. The wrist,
  menu, guide, station sign, beacon and rounds all draw from it.
  `trial_requested` and its withdraw / re-send dance are gone.
- **Rounds:** `Tasks` counts them off `trial_ended` and ends the step on the last
  one. `TrialRunner` keeps no count: it runs "round *n*", and *n* comes from the
  goal. These counts are transient: reload restarts an unfinished task from its
  first step, and trials from their first baseline probe. The station starts the
  next round when the child is in its zone, no round is out, the gap is over and
  the Narrator is quiet. Stations never restrict movement.
- **Narration** (`core/narrator.gd`, autoload `Narrator`): every line goes
  through one queue and comes out one at a time, in order.
  - The subtitle shows `Narrator.current` and Audio speaks it. Neither keeps a
    queue.
  - A line ends when it has been readable long enough **and** Audio reports the
    recording or baked voice really finished.
  - A pause stops the line and restarts it, text and voice together.
  - A line has a *topic*: a newer one replaces a waiting one on the same topic.
    So a stale instruction is never said, and B pressed five times says it once.
  - Menu read-aloud never talks over the guide.
- **Saves** (`core/profile.gd`, autoload `Profile`): each child has a folder,
  `user://profiles/<id>/`, holding `save.json`, `settings.cfg` and `metrics/`.
  - **Boot, switching save and Start over are one operation**:
    `profile_closing` (write, drop everything) → the level is freed → files
    swapped or wiped → `profile_opened` (every saveable loads, with `{}` when its
    file has nothing) → the first level is built fresh.
  - Nothing is patched in place.
  - Start over wipes progress and settings and keeps the research log, which
    marks the reset.
  - The team picks or creates a named save on the Facilitator panel's Saves tab:
    Start fresh, or Copy this save as a checkpoint (research log not copied).
- **Saving:** ordinary facts and rounds schedule a write at the end of the
  frame. Task activation and completion request an immediate write; completion
  counts and rewards are captured together. Tasks saves its active task/list
  identity and completion counts, never step or round progress. Other systems
  keep their own persistent state. A temporary file replaces the previous save;
  a failed write/rename leaves the previous file intact. A different format
  version starts fresh. Existing version-1 task progress is read using the
  migration rules in [tasks.md](tasks.md).

## Rules from here

- Something to show about the current task → read `Events.goal`. Never cache it.
- Something to say → `Narrator.say(text, voice, topic)`. Never estimate how long
  a line takes: `await Narrator.wait_quiet()` or check `Narrator.is_quiet()`.
- New saved state → `save_state()` / `load_state()`, where `load_state({})` must
  mean "new save".
- New transient state in an autoload → drop it on `profile_closing`.

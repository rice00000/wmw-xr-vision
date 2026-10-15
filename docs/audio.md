# Sound: how to add one without writing code

There is one place sound is named: `content/audio/sounds.tsv`. There is no audio
code outside `modules/audio/`, and nowhere to put any — a button, a creature and
a door contain nothing about sound, and still make one.

Open the file in a spreadsheet or a text editor, add a row, save. While the game
is running from the editor the change is live within a second.

## A row

```
key                 sound              options              note
pressed             tone:520/70        space=3d cd=0.08     every button in the game
caught.butterfly    res://…/wings.wav  space=3d vol=-4      only butterflies
asked               -                                       deliberately quiet
```

**key** — what happened, dotted. Keys fall back along the dots, so
`pressed.hello` uses the `pressed` row unless a `pressed.hello` row exists. One
row gives every button in the game a sound.

**sound** — a `res://` clip, or `tone:<hz>` / `tone:<hz>/<milliseconds>` for a
generated beep. Notes joined by `+` play one after another and a `0` Hz note is
a rest, so a placeholder can have a rhythm: `tone:660/90+880/90+1175/220` is a
quick "yes!", `tone:330/240+0/70+247/420` a slow "oh-oh". Several separated by
`|` are variations. **Empty** means the key
still falls back — a row with an empty clip cell is a placeholder saying "this
exists, fill it in". A single **`-`** means silent, and stops the fallback, so
`asked  -` quiets that whole family.

**options** — space-separated, all optional:

| option | means | default |
| --- | --- | --- |
| `vol=-6` | decibels | `0` |
| `pitch=0.9-1.1` | speed, drawn fresh each play; a single number for no variation | `1` |
| `bus=voice\|sfx\|ambience` | which bus | `sfx` |
| `space=2d\|3d` | play it where the thing happened | `2d` |
| `cd=0.2` | seconds before this row may sound again | `0` |
| `pick=random\|cycle` | how a variation is chosen; `cycle` never repeats twice running | `random` |
| `loop` | keep going (ambience) | off |

**note** — for people. Ignored.

## What the keys are

They come off the `Events` bus, so the left column is a list of things that
happen in the game. Nothing has to be registered.

| what happens | key |
| --- | --- |
| `Events.report(&"pressed", &"hello")` | `pressed.hello` → `pressed` |
| any other reported fact | `<what>.<id>` — `caught.butterfly`, `grabbed.ball`, `placed.chair`, `mispicked.cup`, `used.clear_sight`, `finished.search` |
| an item granted | `reward.magic_stone` → `reward` |
| something judged, `Events.judge(&"good")` | `feedback.good`, `feedback.bad`, `feedback.reward` |
| the wrist menu opens / closes | `opened.menu`, `closed.menu` (and every menu button is `pressed.menu_…` → `pressed`) |
| a task begins / ends | `task.started.find_it`, `task.completed.find_it` |
| a measured round begins / ends | `trial.started.search`, `trial.ended.search.hit`, `…​.miss` |
| a level comes up | `ambience.island` — a loop, swapped when the level changes |

Facts that happened somewhere carry their position, so `space=3d` puts the sound
at the button, the creature or the object. A fact with no position falls back to
playing flat.

Good and bad feedback must differ by more than pitch — by rhythm and length —
so they are told apart by anyone. The suite checks this for as long as the two
rows are tones.

## Two things the table does not name

`Events.say(text, clip)` carries the guide's recorded line next to the subtitle
text, and `Events.play_at(clip, position)` plays a clip a task is already
holding — `SearchTrial.prompt_voice` has one per object, because "kettle" is a
recording, not a row. Both still work and are still the only two audio calls
gameplay code may make.

## Speech, for everything not recorded yet

Many of the children this is for read poorly, so nothing should exist only as
text. While the **Read aloud** setting is on, the module speaks with the
platform's text-to-speech (an English voice):

- every `Events.say(text)` line that carries **no** clip, queued in order;
- every `Events.read_aloud(text)` — a wrist-menu button a fingertip is held
  near, a page coming up, "You need 1 more Magic Stone". A new one cuts off the
  one before, so pointing along a row reads the button under the finger, not a
  backlog.

Recording a line later is just passing the clip to `Events.say`; the speech for
it stops by itself. `Audio.speech` lists every request (`say: …` / `read: …`),
so the suite can see a line arrive on a machine with no speech engine.

**Volumes** follow Settings live: *Volume* on the Master bus, *Voice* on the
Voice bus and on speech. The module runs while the tree is paused, because the
wrist menu pauses it and still has to be heard.

## The two rules it enforces on itself

**The table cannot lie.** A clip path that is not there, an option that is
misspelt, a key that appears twice: all are collected when the file loads,
printed, and fail `tools\test.cmd`. A row never silently does nothing.

**The table cannot fall behind.** Every key the game sends that no row answers
is printed once as `AUDIO_UNMAPPED`, shown live on the Test Room's *Audio:
table* station, and asserted empty by the suite after a full playthrough. A new
fact in the game forces a decision here — a sound, or an explicit `-`.

## Before anything is recorded

Nothing is recorded yet, so the table is full of `tone:` rows. They are real,
audible placeholders: you can put the headset on today and hear the game
respond. Replacing one with a recording is editing one cell. Ambience rows are
deliberately `-`, because a looping tone would be unbearable.

## Why a .tsv and not a .tres per sound

The rest of `content/` is one `.tres` per thing, with the file name as the id,
because those things are few and substantial. This is fifty one-line rows that
someone doing sound will want to see all at once, sort, and edit in a
spreadsheet — and reload without restarting. That is a table, so it is a table.

## Shape of the module

```
modules/audio/audio.gd         the autoload: listens to the bus, looks keys up, plays
modules/audio/sound_table.gd   parses the .tsv, resolves a key along the dots
modules/audio/sound_def.gd     one parsed row
content/audio/sounds.tsv       the table
```

Switch the `Audio` autoload off in *Project Settings → Globals* and the game is
silent and otherwise unchanged, as with any module. Its two Test Room stations
then say MODULE OFF while the rest still pass.

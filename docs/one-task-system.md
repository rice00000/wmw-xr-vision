# Why there is one task system, not two

*Decision taken 15 Oct 2026, before prototype 1. Changes `modules/quests/` →
`modules/tasks/`.*

## What there was

Two systems that both described "something the child is asked to do".

**Quests** (`QuestDef` / `QuestStep` / the `Quests` autoload) were narrative:
a list of steps, each waiting for a `what:id` fact to be reported some number of
times, each with a line of instruction, and a reward at the end. Pure data; no
code to add one.

**Trials** (`TaskDef` / `TaskAxis` / `Trial` / `TrialRunner` / `TrialCondition`)
were measurement: one round of a visual task, built from named difficulty axes,
driven by a staircase, written to the research log. Scene nodes in a level.

Both were good at their own job and neither could do the other's. More
importantly, **nothing connected them.** The search room — the whole of
prototype 1 — was reachable only by walking through a door, ran rounds forever,
and never ended or paid anything. The measured part of the game was not part of
the game.

## What was considered

**Tasks absorb quests.** Make the round system able to express "catch three
butterflies" and "walk through the yellow door". Rejected: those are not rounds.
They have no condition, no axes, no staircase and no result worth scoring, so
every one of them would need a null `Trial` subclass and would put a junk line in
the research log. That is adding machinery to delete a concept — the opposite of
the job.

**Quests wrap trials.** A quest step may, instead of waiting for a fact, ask for
N measured rounds. Taken, with one change: the word "quest" goes.

## What was done

A **task** is what the child is asked to do. A **trial** is one measured round
inside it. One module, `modules/tasks/`, one autoload, `Tasks`, and the project's
own existing word for a round ("one round is a trial" — the README already said
so) now names the thing it always meant.

| before | after | what it is |
| --- | --- | --- |
| `QuestDef` | `TaskDef` | a task: steps, rewards, what follows |
| `QuestStep` | `TaskStep` | one step: a fact to wait for **or** a trial to run |
| `Quests` autoload | `Tasks` autoload | walks the steps, pays the rewards |
| `TaskDef` | `TrialDef` | how one measured round is built |
| `TaskAxis` | `TrialAxis` | one difficulty dimension of a trial |
| `content/quests/*.tres` | `content/tasks/*.tres` | the tasks |
| `content/tasks/search.tres` | `content/trials/search.tres` | the trials |

A trial step was almost free, because the seam already existed: `TrialRunner`
reports `finished:<trial>` when its round budget is up, and a step already knows
how to wait for a fact. So a trial step is **not** a second kind of matching —
it is an ordinary fact step whose key is `finished:<trial>`, plus one side effect
when the step is entered: `Events.trial_requested(trial, rounds, title)` (since
replaced by the published goal: see [state-and-narration.md](state-and-narration.md)). The
`Station` that runs that trial (the picnic table for `search`, the meadow for
`catch`) answers; every other station ignores it.

That keeps every architecture rule intact. The request travels on the bus, so
`Tasks` never calls a level and a level never calls `Tasks`.

Later (Oct 2026) the one module became three layers, still with one word for
each thing: `modules/tasks/` (tasks), `modules/trials/` (trials, their defs,
`Training`, one subfolder per kind of round) and `modules/stations/` (where
trials are run). Dependencies go one way, **tasks → trials ← stations**: tasks
read a `TrialDef` to name a task's visual skills, stations run trials, and neither
tasks nor trials know stations exist. The smoke test checks it. Switch the `Tasks`
autoload off and a station with `auto_start` still runs free-play rounds; switch
`Training` off and rounds still run at the trial's baseline difficulty.

## What it bought

The game's first-time loop is one chain of four data files, and the two measured
tasks sit in the middle of it, each at its own station on the island:

```
welcome            → find_it              → butterflies          → first_furniture
take the ball,       5 measured rounds      5 measured catches     buy, take out
open the menu,       at the picnic table    in the meadow          and place furniture
walk to the picnic
1 Magic Stone        2 Magic Stones         2 Magic Stones         1 Magic Stone
```

After that `find_it` and `butterflies` are offered again from the wrist menu.
`find_it` is the whole of prototype 1, and it is five lines of `.tres`. Before,
putting the search room into the game would have meant writing code to decide
when it was over and what it paid.

## Cost, honestly

A rename across the whole project, including every `.tres` that referenced the
old script paths, and a research-log field (`task` → `trial`) that changes the
shape of any log line recorded before today. No logs from children exist yet,
which is exactly why the rename happened now.

## What to do next time you add something

- Something to do → a `TaskDef` in `content/tasks/`. No code.
- A measured round of it → set `trial` on the step, and a `TrialDef` in
  `content/trials/`. Code only if the round is a new *kind* of round, i.e. a new
  `Trial` subclass.
- Do not add a third thing.

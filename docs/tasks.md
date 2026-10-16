# Tasks and task lists

`TaskListDef → TaskDef → TaskStep`. The `Tasks` autoload coordinates selection,
step progression, rewards and save requests. Lists and tasks are resources;
menus, guides and stations read `Events.goal` rather than maintaining progress.

## Content

| Resource | Location | Responsibility |
| --- | --- | --- |
| `TaskListDef` | `content/task_lists/<id>.tres` | Ordered task IDs, `auto_next`, list prerequisites and optional entry event |
| `TaskDef` | `content/tasks/<id>.tres` | Title, ordered steps, prerequisites, repeatability and completion rewards |
| `TaskStep` | Subresources inside a task | Instruction/voice, place and completion condition |

File names are stable IDs. Renaming a task changes its identity in existing
saves. A task must have at least one valid step and belong to a list to be
selectable. List entries should reference existing tasks without duplicates.
Lists appear in filename order; tasks appear in their declared order.

A step either waits for `event` (such as `grabbed:magic_ball` or `placed:*`)
`count` times, or runs `count` rounds of `trial`. A trial step ignores `event`.
`place` directs the guide; it does not independently validate event location.
Each new step updates the wrist prompt, guide and station through one `Goal`.
The wrist shows the instruction's first line; narration speaks the full text.
Use a short first line and put longer guidance after a newline.

## Selection and progression

- `auto_next = true`: offer the first unfinished task, then automatically
  advance to the next unfinished task on completion. A locked first unfinished
  task blocks the list; completed tasks are skipped, even if repeatable.
- `auto_next = false`: offer all tasks whose prerequisites are met and which
  are unfinished or repeatable. Order is presentation only. Completion returns
  to selection.
- A list's `requires` unlocks the whole list. A task's `requires` unlocks that
  task everywhere it appears. Each prerequisite means completed at least once.
- `start_on` belongs to the list. A matching gameplay fact (for example
  `entered:island`) starts its first unfinished task when no task is active.
  Without it, entry is through the menu. If several lists match, the first
  eligible list in filename order wins. Events while busy are not queued.
- Only one task can be active. It must finish before another can be selected;
  there is no switch or abandon API. Movement and other world interactions
  remain available.

The same task can belong to multiple lists. Completion counts and rewards
belong to the task globally, while the selected list supplies the progression
policy. For independent completion, create separate task resources. Repeating
an entire tutorial/list is not a separate saved concept.

The shipped lists are:

- `tutorial` / Island adventure: `welcome → find_it → butterflies →
  first_furniture`, `auto_next = true`, starts on `entered:island`.
- `practice` / Vision practice: `find_it`, `butterflies`, `auto_next = false`,
  unlocks after `first_furniture`. These reuse the tutorial's repeatable tasks.

## Saving and restart

Tasks saves only `{current, list, times_done}`: active task identity, its source
list, and completion counts. The list ID is context, not a saved list cursor.
Steps, fact counts and round counts are never saved. Reloading an unfinished
task restarts it at step zero with no reward. Its trial begins at round zero,
including baseline probes again. The new level repeats its instruction.

Activation requests an immediate save. Completion increments the task count,
applies every reward synchronously through `reward_granted`, then requests an
immediate save before announcing completion or starting the next task.
`Save` captures task state and inventory together in the same file. Inventory's
reward handler must remain synchronous. The temporary file replaces the last
save without first deleting it; failures are reported as errors.

Inventory, placed furniture, training adaptation and research logs retain their
own persistence. Restarting a task does not undo purchases or erase recorded
rounds. Author restartable objectives: a task must not require spending the
same finite currency again after reload. `first_furniture` therefore asks the
player to open the menu and place furniture; purchasing is optional if they
already own a piece. It can be taken from the bag or moved in the world.

Existing version-1 saves retain task completion counts, inventory and world
state. Old `step`/`progress` fields are ignored. An active task without a source
list is resolved from the first list that currently offers it. If the task or
list is no longer available, selection is cleared. The tutorial's entry event
can then start its first unfinished task. List progress is always derived.

## Menu and extension points

The existing wrist menu shows collapsible list headers with completion counts.
Lists with choices start expanded; finished lists start collapsed. Back/More
buttons or a vertical thumbstick flick page through three rows at a time.
Expansion is temporary UI state, cleared when switching profiles. During a
task, the page shows its objective and reward. An idle wrist says **Choose a task**.

Menu API on `Tasks`:

- `lists()`: available list summaries `{id, title, done, total, offers}`.
- `offers(list_id = &"")`: eligible IDs in one list, or a deduplicated union.
- `accept(task_id, list_id = &"")`: start an eligible task. Pass the list from
  the UI; omission chooses the first offering list in filename order.
- `current()`, `describe(task_id)`, `times_done(task_id)`, `is_done(task_id)` and
  `remind()` expose task identity, presentation and completion.

To add content, create a task resource and add its ID to a task list, or create
another list with the desired progression policy. Add prerequisite tasks before
those depending on them in automatic lists, and avoid circular prerequisites.
To add new measured gameplay, use the existing Trial/TrialDef/station layer.
No task-specific conditionals belong in the coordinator or menu.

`TaskDef.next`, `TaskDef.start_on`, `offered`, `abandonable`, `Tasks.start()` and
`Tasks.abandon()` have been removed. Automatic progression has one owner: the
list policy interpreted by `Tasks`.

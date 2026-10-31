# How the workflow works

Every rule in the prompts was added after a local model actually shipped that defect. Small local models fail in
predictable ways, and the workflow closes each one.

## Files in the project folder

| File | Written by | Purpose |
|---|---|---|
| `PLAN.task.md` | pi-pe | The task text, saved so the reviewer sees exactly what was asked |
| `PLAN.md` | planner | Context (facts with quoted proof), Requirements table, Edge cases, Logging, checkbox Steps, Verify, Blockers |
| `PLAN.notes.md` | planner | Working memory that survives context compaction: requirements, verified facts, rehearsal output |
| `PLAN.files/<path>` | planner | Full content of new or largely rewritten files. Code is written once and the executor copies it, never retypes it |
| `PLAN.rehearsal/` | planner | Scratch copy of the project where the whole plan is applied and Verify is run before PLAN.md is written |
| `PLAN.next.md` | planner | Later slices of a big task, as ready-to-plan `## Slice N:` sections |
| `PLAN.done-N.md` | pi-plan | Finished plans, archived when the next slice is planned |

## The three roles

**Planner** (`planner.md`, Swift 27B, thinking medium; tools read/grep/find/ls/write/edit/bash)
- *Small scope first.* One plan covers at most 3 requirements, 5 steps and ~150 changed lines. Anything bigger goes to
  `PLAN.next.md`. Every big plan in testing shipped untested, broken code.
- *Quote, don't claim.* Every fact in Context carries the literal output of a command it ran.
- *Rehearsal.* It applies the plan in `PLAN.rehearsal/` and runs Verify there. Don't trust a "Rehearsed" line on its
  own: one planner wrote a fabricated rehearsal with invented outputs. Check `PLAN.notes.md` for the real output.
- *Mandatory logging.* Every feature emits a named log line to `logs/run.log`, and a `--selftest` mode exercises it.
  Verify then greps the log. This is how a 9B executor proves something ran, instead of claiming it.
- *No vague steps.* A step that names only a file and a goal is invalid. Each step needs either a unique anchor plus
  the exact code, or "Copy PLAN.files/X to X".

**Reviewer** (`reviewer.md`, a fresh Swift session, thinking medium)
- Reviews the code *as it will be*: the PLAN.files/ versions, not the old files (otherwise it raises false alarms).
- Every finding needs a proof command and its output. With no evidence, the finding is dropped.
- It may only ADD a corrections block and one step above `## Verify`. In an earlier version it deleted and renumbered
  the plan's steps.
- Testing found that higher thinking (high/xhigh) did not review better than medium.

**Executor** (`executor.md`, Ornith 9B, thinking low)
- Follows the plan, ticks a box only with proof, and lets corrections override listings.
- Bounds every command with `timeout` and `| tail`. It must never use `find /`: one model walked the whole disk for
  hours.
- When the same failure happens twice, it changes approach. After 3 different approaches, it writes a Blocker and stops.
- Thinking `low` beat `off`: `off` wrote more visible text and made more edit mistakes, so it wasn't faster.

## Practical tips

- Read `PLAN.md` and the review before running `pi-exec` on anything important.
- To send feedback after a run, use `pi-pe "<feedback as a task>"`, not `pi-exec "<feedback>"`. When an old, fully
  ticked PLAN.md is present, the executor re-runs the old Verify and ignores the feedback.
- When scripting with `-p`, add `< /dev/null` (or the cmd equivalent `<nul`). With stdin left open, Pi waits forever
  and sends no request.
- `environment.md` is the cheapest fix you have: every time a model guesses wrong about your PC (python3, a taken port,
  a tool path), write the fact there.

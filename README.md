# gascoigne-harness

Agent harness shared by the gascoigne repos. Each repo mounts it as a git submodule at
`.harness/common`; everything repo-specific stays in that repo's own `.harness/`.

| Path | What |
|---|---|
| `rules.md` | hard rules every repo follows (deps, verification, working habits, design, hygiene, worktrees) |
| `data-structures.md` | choosing data structures from access patterns; decision table, red flags |
| `architecture-style.md` | core, adapters, composition root; when a port is justified |
| `code-style.md` | shape, errors, comments, docs, tests: how code reads in every repo |
| `commit-style.md` | conventional commit format, body, trailer |
| `skills/verify/` | generic verify skill |
| `skills/task-loop/` | the task loop as a skill: an orchestrator agent runs one subagent per task and gates the result |
| `commands/task-loop.md` | registers the `/task-loop` slash command; hands its arguments to the `task-loop` skill |
| `agents/` | subagent roles the loop starts: `task-designer` (read-only), `task-implementer` |
| `skills/ci-report/` | weekly report: queue, setup and task time of the 5 slowest jobs |
| `skills/state-machines/` | weekly audit of implicit state machines |
| `skills/data-model/` | design note before code; weekly data-model audit |
| `templates/task.md` | task file template |
| `scripts/check-layers.sh` | layer guard driven by `.harness/layers.txt` (rows: zone, patterns, may-import) |

## Use in a repo
```sh
git submodule add git@github.com:gascoigne-ai/gascoigne-harness.git .harness/common
git submodule update --init            # after a fresh clone or a new worktree
```
`CLAUDE.md` imports the shared files next to the repo's own:
```text
@.harness/common/rules.md
@.harness/common/commit-style.md
@.harness/common/code-style.md
@.harness/rules.md
```
Agents: symlink `.claude/agents` to `.harness/agents` and `.harness/agents/task-designer.md`, `task-implementer.md` to `../common/agents/<name>.md`.
Commands: symlink `.claude/commands` to `.harness/commands` and `.harness/commands/task-loop.md` to `../common/commands/task-loop.md`.
Skills: symlink `.harness/skills/verify` to `../common/skills/verify`, so `.claude/skills` (a symlink to
`.harness/skills`) finds it.

## Change the shared harness
Commit and push here first, then in each repo `git -C .harness/common pull` (or checkout the new
commit) and commit the pointer as `chore(harness): bump common harness`. A repo rule may add to a
shared one, never weaken it.

## Tasks (per repo)
One file per task: `.harness/tasks/NNN-slug.md` (other files there, such as notes, are ignored); see `templates/task.md`. Header lines `key: value`, a
blank line, then `# Title` and the body (goal, scope, acceptance). Keep each task one commit's worth of
work. A done task is deleted by the loop (git keeps it); open ideas live in `.harness/backlog.md`.

| Header | Meaning |
|---|---|
| `status: todo` | first line; `blocked` and `failed` are skipped |
| `kind` | `feature`, `bug`, `chore` (default), `docs`. Feature and bug tasks get a design phase, need a `## Model` section (or `Model: unchanged`) and a test in the diff |
| `commit` | conventional subject, at most 72 characters; default `chore: <title>` |
| `scope` | comma-separated globs the change may touch; anything else fails the task |
| `not_before` | `YYYY-MM-DD`; not eligible earlier |
| `depends_on` | task names; eligible once their files are gone from the checkout (merged) |

Run the queue from an agent session with the `task-loop` skill: `/task-loop`, `/task-loop --dry-run`,
`/task-loop --lint`, `/task-loop --once`, `/task-loop <task-name>`. The orchestrator agent starts subagents
inside the session, so they use its tool approvals. No shell loop, no headless `claude -p`.

**Each task runs in its own worktree** on branch `loop/NNN-slug` (`scripts/wt`); the invoking checkout is
never touched.

Per task: `task-designer` (feature and bug) → `task-implementer` → gates run by the orchestrator: the
implementer's last line is `RESULT: done` (`RESULT: blocked <reason>` stops without a commit), changes
inside `scope`, a test in the diff, the repo's check green. One gate failure goes back to the same
implementer once; then the task is `failed`, its worktree stays for inspection and the loop moves on.
Success commits on the branch (conventional subject, `Task:` line, trailer), fast-forwards the base
branch and removes the worktree.

`scripts/wt new|path|rm|ls <repo> <branch>` creates worktrees (the loop uses it too).

## Weekly audits
`rules.md` asks for `ci-report`, `state-machines` and `data-model` (audit mode) at least weekly; each
reports first and changes nothing. Schedule them with `/schedule` (a routine per skill) or cron running
`claude -p "run the <skill> skill; report only"` in the repo.

## Tests
`make check` runs the shell tests under `tests/` (scratch repos and a fake `claude`).

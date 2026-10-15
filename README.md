# gascoigne-harness

Agent harness shared by the gascoigne repos. Each repo mounts it as a git submodule at
`.harness/common`; everything repo-specific stays in that repo's own `.harness/`.

| Path | What |
|---|---|
| `rules.md` | hard rules every repo follows (deps, verification, design, hygiene, worktrees) |
| `commit-style.md` | conventional commit format, body, trailer |
| `skills/verify/` | generic verify skill |
| `scripts/loop.sh` | autonomous task loop (`VERIFY_CMD` sets the check) |

## Use in a repo
```sh
git submodule add git@github.com:gascoigne-ai/gascoigne-harness.git .harness/common
git submodule update --init            # after a fresh clone or a new worktree
```
`CLAUDE.md` imports the shared files next to the repo's own:
```text
@.harness/common/rules.md
@.harness/common/commit-style.md
@.harness/rules.md
```
Skills: symlink `.harness/skills/verify` to `../common/skills/verify`, so `.claude/skills` (a symlink to
`.harness/skills`) finds it. A repo-specific `scripts/loop.sh` may wrap the shared one and set
`VERIFY_CMD`.

## Change the shared harness
Commit and push here first, then in each repo `git -C .harness/common pull` (or checkout the new
commit) and commit the pointer as `chore(harness): bump common harness`. A repo rule may add to a
shared one, never weaken it.

## Tasks (per repo)
One file per task: `.harness/tasks/NNN-slug.md`, first line `status: todo`. Body = goal, scope,
acceptance criteria. Keep each task one commit's worth of work. Delete a task once done (git keeps
it); open ideas not yet worth a task live in `.harness/backlog.md`.

```sh
.harness/scripts/loop.sh --dry-run   # list pending tasks
.harness/scripts/loop.sh --once      # do next task only
.harness/scripts/loop.sh             # work through all todo tasks
```
Per task: headless `claude -p` with the task + harness rules → `VERIFY_CMD` → on success deletes the
task file and commits; on failure stops and prints the log path. Env: `MAX_TURNS` (default 50),
`CLAUDE` (binary, default `claude`). Transcripts go to `.harness/logs/` (gitignored).

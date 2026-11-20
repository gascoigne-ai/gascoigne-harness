---
name: task-loop
description: Work through the repo's queued task files (.harness/tasks/NNN-slug.md) by running one subagent per task and gating each result. Use when asked to run the loop, run or implement the tasks, or work the queue. Arguments - `--dry-run`, `--lint`, `--once`, or one task name.
---

# Task loop

You are the orchestrator. You read tasks, start subagents, check their work and commit it. You do
not implement a task yourself, and you never shell out to a loop script or headless `claude -p`.
Subagents run inside this session, so they use this session's tool approvals.

Roles:
- `task-designer` (`agents/task-designer.md`): read-only, writes the design note for feature and bug tasks.
- `task-implementer` (`agents/task-implementer.md`): edits code in its own worktree, test first, never commits.
- You: eligibility, gates, commit, merge, report.

If a role is missing from the agent list, start `general-purpose` with the role file's text as the
prompt. A subagent never starts another subagent; only you do.

## Task file
Header lines `key: value`, a blank line, `# Title`, body. The README of the common harness has the
header table (`status`, `kind`, `commit`, `scope`, `not_before`, `depends_on`).

## 1. Lint (also `--lint`)
For every `.harness/tasks/[0-9]*.md` report, and stop on any problem:
- first line is `status: todo`, `blocked` or `failed`;
- `kind` is `feature`, `bug`, `chore`, `refactor`, `ci` or `docs` (default `chore`);
- `commit` matches `^(feat|fix|docs|test|refactor|build|ci|chore|release)(\([a-z0-9._-]+\))?: .+$`, at most 72 characters;
- `not_before` is `YYYY-MM-DD`;
- feature and bug tasks contain `## Model` or `Model: unchanged`;
- a `todo` task is committed (`git cat-file -e HEAD:<file>`), because a worktree starts from HEAD.

## 2. Pick (also `--dry-run`)
A task is eligible when it is `status: todo`, committed, `not_before` is not in the future, and
every `depends_on` file is gone from the checkout (a done task is deleted by its commit). Take
eligible tasks in name order, one at a time. List them and stop for `--dry-run`. Stop after one
for `--once`, or run only the named task when a name is given. Never retry a task twice in one run.

## 3. Run one task
1. Start a worktree for branch `loop/<task>` from the current branch (`wt new <repo> loop/<task>`
   from the repo parent, or the Agent tool's `isolation: "worktree"`). The branch must not exist yet;
   if it does, report it and skip the task. Run `git submodule update --init` there.
2. Feature and bug tasks: start `task-designer` with the task file. Its reply must contain `## Model`
   or `Model: unchanged`, else the task fails. Keep the reply as the design.
3. Start `task-implementer` in the worktree with the task text and the design. It ends with
   `RESULT: done` or `RESULT: blocked <reason>`. Blocked: mark the task blocked in your report, keep
   the worktree, go to the next task.
4. Gates, run by you in the worktree, never trusted from the subagent:
   - **scope**: every changed or new file matches a `scope` glob (comma separated; `*` also
     matches `/`). Anything else fails.
   - **test**: feature and bug tasks have a test file in the diff (`_test.`, `.test.`, `.spec.`,
     `tests/`, `test_`).
   - **verify**: run the repo's check command from its `CLAUDE.md`. Failure
     fails the task.
5. A failed gate: send the problem to the same implementer (SendMessage) once. A second failure
   fails the task: keep the worktree, report the gate and the last 60 lines of output.
6. All gates pass: stage the scope files, delete the task file (`git rm`), commit with the `commit`
   subject (default `chore: <title>`, 72 characters), body `Task: <name>`, and the attribution
   trailer from the session. Fast-forward the base branch (`git merge --ff-only loop/<task>`),
   remove the worktree and the branch. If the fast-forward fails, keep both and report.

## 4. Report
One line per task: `done <hash>`, `blocked <reason>` or `failed <gate>`, with worktree paths for
the kept ones. End with what is left in the queue. Do not delete kept worktrees without asking.

## Rules
- Sequential only: one task at a time, so each gate sees the previous merge.
- Never edit a task file except by deleting it in the task's own commit.
- Never skip a gate, loosen scope or edit a test to pass; a stuck task is reported, not forced.
- Do not push.

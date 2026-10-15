# Common rules

Hard rules shared by every gascoigne repo (`gascoigne-cli`, `gascoigne-sdk`, `gascoigne-jarnam`).
A repo's own `.harness/rules.md` adds to these; it never weakens them. Breaking one = change rejected.

## Dependencies
- Stdlib first. A new dependency only when the user explicitly asks; never to "save time".
- Each repo lists its approved dependencies in its own `rules.md`.

## Verification
- The repo's check command (`make check`, `mise run check`) must pass before you call work done.
  Never claim green without running it in this session.
- New behavior ships with tests. Table-driven where there are several cases.
- Bugs get a failing test first, then the fix.
- Fixtures use real tool or provider output, never invented samples.
- Never skip or delete a failing test, loosen an assertion to pass, or silence a linter without the
  user's approval.

## Design
- Table-driven designs (handler tables, dialect tables) over switch sprawl.
- No speculative abstractions, options or hooks "for later".
- Behavior a doc describes changes in the same commit as the doc.

## Hygiene
- No competitor or other token-tool names in code, docs, tasks or commits. Describe techniques
  generically ("command output filtering", "JSON compaction"). Exceptions: datasets, copyright,
  attribution and license notices where the source or its license requires naming it.
- No secrets, real user data or home paths in code, docs or fixtures. Secrets come from the
  environment only.
- Small focused commits (see `commit-style.md`); don't touch unrelated files; don't reformat
  untouched code.

## Worktrees
- Every repo is a bare repo (`.bare`) with one worktree per branch next to it (`master/` or `main/`,
  `<branch>/`; `/` in a branch name becomes `-`). Each agent works in its own worktree, never in
  another's.
- Create and remove with `wt new|rm <repo> <branch>` from the parent directory. It copies
  `.claude/settings.local.json`.
- Build output is ignored, so build per worktree.

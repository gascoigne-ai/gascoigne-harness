---
name: verify
description: Verify gascoigne changes before calling work done. Use after any code edit, before committing, or when asked to check/test the repo.
---

# Verify

1. Run the repo's check command (`make check` or `mise run check`; see its `CLAUDE.md`).
2. On failure: read the first error, fix the cause (not the test), rerun. Repeat until green.
3. Run the extra checks the repo's `rules.md` names for what you touched (for example `make eval`).
4. Report what ran and the result. Never claim green without running it in this session.

Never: skip or delete failing tests, add `t.Skip`, loosen assertions to pass, or
`//nolint`/ignore findings without the user's approval.

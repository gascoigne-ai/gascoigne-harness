# Common rules

Hard rules shared by every gascoigne repo (`gascoigne-cli`, `gascoigne-sdk`, `gascoigne-jarnam`).
A repo's own `.harness/rules.md` adds to these; it never weakens them. Breaking one = change rejected.

## Dependencies
- Stdlib first. A new dependency only when the user explicitly asks; never to "save time".
- Each repo lists its approved dependencies in its own `rules.md`.

## Verification
- The repo's check command (`make check`, `mise run check`) must pass before you call work done.
  Never claim green without running it in this session.
- Test first, then implement. For every new behavior or change of behavior, in this order:
  1. Write the test that states the behavior (named after it, table-driven when there are several
     inputs).
  2. Run it and watch it fail, for the reason you expect (an assertion about the missing behavior,
     not a compile error or a typo).
  3. Write the smallest code that makes it pass, then run the whole check.
  Say in your report that the test failed before and passes after. Tests written after the code,
  to match what it already does, do not count: they pin the implementation, not the behavior.
  A refactor keeps the tests green and changes none of them.
- Every bug found (by you, the user or a failing run) starts with a regression test: write it first,
  run it, see it fail for the reported reason, only then fix. A bug that cannot be reproduced in a
  test is not understood yet: keep investigating or say so; never ship a guess as a fix. A data bug
  also gets an eval or fixture case when a suite fits.
- What cannot be unit-tested (drawing on a GPU, a real window) is kept as thin as possible and
  checked by the repo's visual or run check (a screenshot, a smoke run); the logic around it still
  follows test first. Say which check you ran.
- Code that is already there without tests is covered the same way when you touch it: pin the
  current behavior with a test that passes, then change it test first.
- Fixtures use real tool or provider output, never invented samples.
- Never skip or delete a failing test, loosen an assertion to pass, or silence a linter without the
  user's approval.

## Working
- Finish the whole job before you stop. Do not offer to continue: continue.
- Ask the user before you delete anything. The one exception: a task file the loop finishes (git
  keeps it).
- End with a recap for someone who saw none of the work: key points first, in plain words.
- Do not write an unfamiliar feature from scratch. Search GitHub for open-source projects, compare
  their approaches, then propose 3 options: one from open source, one creative, one best. Wait for
  the user's pick before you start.
- Rate every bug you find from 1 to 10 for how often it would happen and from 1 to 10 for how bad it
  is. Multiplied scores below 5: file an issue and leave the code alone. 5 or more: fix it, test
  first (the regression-test rule above). Do not design for rare or future cases nobody asked about.
- Weekly, at least: run the `ci-report` skill (queue, setup and task time of the slowest jobs) and
  the `state-machines` skill (implicit state machines) and the `data-model` skill (audit mode).
  Each reports first and changes nothing until the user agrees.

## Data model
Wrong data leads to wrong solutions and complex designs, so the model comes before the logic.
- **Model before logic.** A task that adds or changes state starts with the types: fields, allowed
  values, invariants, owner, persistence. Logic is written against the types. If the logic needs a
  special case, the model is wrong: fix the model.
- **Choose the structure from the access pattern**, with `data-structures.md`. A task that adds or
  changes a collection, a record or persisted data names its access pattern, the structure chosen,
  the alternative rejected and the signal to revisit, in the design note (skill `data-model`).
  A change without it is rejected.
- **Illegal states are unrepresentable.** Enum or sum type over bool pairs and magic strings; one
  type per concept; optional fields only when absence is a real state; a status with a transition
  table instead of flags that change together.
- **One source of truth per fact.** A derived value is computed, not stored beside its source.
- **Parse at the boundary.** Raw input (JSON, tool output, config, provider response) becomes the
  typed model once, at the edge. Core code never sees an untyped map or a raw string status.
- **Name data by the domain**, not the transport: `Price`, not `row`.
- **Persisted and wire formats are versioned** and have a fixture of real output.
## Architecture
Layers and ports follow `architecture-style.md`: a core that knows nothing of the outside, adapters
behind small ports, a composition root, and a layer check in `make check`. A port exists only at a
boundary the core cannot control and has a second implementation (a test fake counts).
## Design
- Table-driven designs (handler tables, dialect tables) over switch sprawl.
- No speculative abstractions, options or hooks "for later".
- Behavior a doc describes changes in the same commit as the doc.
- Readability beats cleverness, performance and DRY; the rest of the style is in `code-style.md`.
- Extend by adding a component or table row, never by special-casing one inside core.

## Naming
- No one-letter names for parameters: `request`, not `r`; `message`, not `m`. A reader should not
  have to look up the signature to know what an argument is. Applies to functions, methods and
  closures, in every language.
- Narrow exceptions: `t`/`b` for `*testing.T`/`*testing.B`, loop indices (`i`, `j`), Go method
  receivers (`c *Client`: the receiver is one short name per type, as Go style asks), and type
  parameters (`T`, `K`, `V`).

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
- Create and remove with `wt new|rm <repo> <branch>` from the parent directory (the script is
  `scripts/wt` in the common harness). It copies `.claude/settings.local.json`.
- The task loop is no exception: it runs every task in its own worktree on branch `loop/<task>`.
- Build output is ignored, so build per worktree.

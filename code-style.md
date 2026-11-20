# Common code style

Shared by every gascoigne repo. A repo's own `.harness/code-style.md` adds language details (formatter,
line width, idioms); it never weakens this file. **Readability is number one**, over cleverness,
performance, DRY and consistency with bad code. If a reader has to pause, rewrite.

## Shape
- Early returns; keep the happy path flat and left-aligned. At most two levels of nesting.
- Small functions doing one thing. A function that needs a section comment wants splitting.
- Fewer lines beat abstractions: three similar lines are fine; extract on the third real copy.
- Names are short and exact: full words in wide scopes, short ones only in tiny scopes. Parameters
  follow the naming rule in `rules.md`.
- Named constants for protocol numbers, timeouts and thresholds; enums or small types over magic
  strings for states.
- Data model and structure choice: `rules.md` (Data model) and `data-structures.md`.
- No global mutable state; configuration flows in through constructors or factories.
- Context, deadline or timeout first on anything doing I/O.
- Interfaces only for real contracts, or once a second implementation exists (a test fake counts); see
  `architecture-style.md` for where ports belong. Generics only when they
  remove real duplication.

## Errors
- Wrap with context (`load <path>: <cause>`). Do not log and return the same error.
- Never swallow an error silently. A deliberate bypass or fallback is logged at debug, with the reason.

## Comments
- Say why, never what. If the code needs a "what" comment, rename or split instead.
- Public API gets a doc comment in the language's own form (godoc, docstring, TSDoc, Javadoc, XML
  doc, rustdoc), starting with what the thing is or does. A package or module gets one in its main
  file.
- No commented-out code. No TODO without a task file or a backlog entry.

## Docs
- Diagrams and flows are Mermaid (a fenced `mermaid` block), not ASCII art or images: they render
  on GitHub, diff as text and need no tool to regenerate. Short labels, quoted when they hold
  punctuation, node ids that are not Mermaid keywords (`end`, `graph`, `in`). Check a new diagram
  with Mermaid's parser (`mermaid.parse`, under jsdom in node) before committing.
- Screenshots stay images; tables stay tables.
- Docs describe behavior in the present tense.

## Tests
- Behavior, not implementation details. The test name states the behavior
  (`TestFillDaysEndsWithToday`).
- Table-driven with named cases where there are several inputs; the ecosystem's own style for
  grouping (`t.Run`, `describe`, parametrize).
- Fakes (tiny types implementing the contract) over mock frameworks; stub servers with the
  language's standard HTTP test tools.
- Tests never touch real user state: temp dirs for files, and `HOME`, `XDG_*` and other
  environment redirected to a sandbox. Setting only `HOME` is not enough when `XDG_CONFIG_HOME` is
  set: a test once overwrote a real user config.
- A bug fix carries a comment above its regression test saying what went wrong.

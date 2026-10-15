# Commit style

Same in every gascoigne repo, so the logs read alike. Run `git log -12` before the first commit in
a repo: its scopes are the examples to follow.

## Subject
`<type>(<scope>): <what changed, no full stop>`, at most 72 characters. The description starts lower
case unless it opens with a name or identifier.

- Types: `feat`, `fix`, `docs`, `test`, `refactor`, `build`, `ci`, `chore`, `release`.
- Scope is the area touched, short and lower case: a package, a language, a part (`spec`, `demos`,
  `harness`, `ci`). Drop it when a change spans everything: `docs: ...`.
- Say what the change does for a reader of the log, not how: `feat(python): auto() decorates MCP
  calls`, not `add auto.py`.
- Releases: `release: <version> <headline>`; the repo's release skill gives the exact form.

## Body
A short paragraph after a blank line, wrapped at 72 characters, that says **why**: the problem, the
behavior before, what changes now. Skip it when the subject says everything. No bullet dumps of files.

## Rules
- One focused change per commit; do not mix a refactor with a feature.
- Behavior changes update docs (the matching `architecture` section) and tests in the same commit.
- Changes to the shared harness (`.harness/common`) are committed in that repo first; the consuming
  repo then commits the bumped submodule pointer as `chore(harness): bump common harness`.
- End with the `Co-Authored-By` trailer when an assistant wrote the change.

```text
feat(spring-ai): @EnableGascoigne shortens every tool call

Tool results reached the model in full unless each tool was wrapped by
hand. One annotation now wraps ToolCallingManager, so @Tool methods,
function callbacks and MCP tools are covered. Nothing is decorated
without the annotation.

Co-Authored-By: Claude Sonnet 5.5 <noreply@anthropic.com>
```

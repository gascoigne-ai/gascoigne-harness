---
name: state-machines
description: Weekly audit of implicit state machines in the app. Use at least once a week, or when flags and statuses start to tangle.
---

# Implicit state machines

1. Find them: status or phase fields, booleans that change together, lifecycle code, retries,
   connection or session handling.
2. For each, list the states, the transitions, and the combinations that must never happen.
3. Report first as a table: machine, where it lives, states, illegal states reachable today.
4. Choose the change that improves all three at once, without breaking anything:
   - user experience: no stuck or contradictory screens and messages.
   - developer experience: one table of states and transitions, not flags spread around.
   - agent experience: states and errors an agent can read and act on.
5. After the user agrees, apply it test first: a table-driven transition test, then a transition
   table in the code (see `rules.md`, Design).

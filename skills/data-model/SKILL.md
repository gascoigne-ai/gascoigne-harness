---
name: data-model
description: Design the data model before code, and audit it weekly. Use before any task that adds or changes state, a collection, a record or persisted data, and at least once a week for the whole repo. Per-task mode writes a design note; audit mode reports only.
---
# Data model
Read `rules.md` (Data model) and `data-structures.md` first.

## Per task, before any code
Write a short design note (the loop saves it as `design.md`):
1. For every collection or record: the access pattern, the structure chosen, the alternative
   rejected, the signal that would make us revisit it.
2. Entities, their fields, allowed values and invariants. Who owns each value, where it is persisted.
3. State tables for anything with a lifecycle (states, transitions, combinations that must never occur).
4. The zone each type lives in (`architecture-style.md`): domain types in core, wire types in adapters.
5. Ports touched or added, each with the boundary that justifies it.
6. The test list, table-driven where several inputs exist.
If the logic starts to need a special case, stop: the model is wrong. Fix the model, or end with
`RESULT: blocked model-change` and say why.

## Weekly audit
Report first and change nothing until the user agrees.
1. Find the smells in `data-structures.md` section 4, plus: string-typed enums, bool flags that
   change together, structs whose optional fields differ per mode, one value computed in three
   places, types named after the transport.
2. Report as a table: smell, where, what it forces on callers, proposed type or structure, blast
   radius, frequency (1-10) x impact (1-10).
3. Scores below 5: file an issue. 5 or more: after the user agrees, fix test first, one commit each.

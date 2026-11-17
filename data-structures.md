# Data structure selection
Shared by every gascoigne repo. A wrong structure is cheap to pick and expensive to change once
callers and persisted data depend on it, so the choice is explicit, written down and reviewed.

## 1. Start from access patterns, not from the data
Before choosing, answer in the design note:
- How is it read: by key, by position, by range, scan all, by prefix?
- How is it written: append, insert in the middle, update in place, delete?
- How many items now, and at 100x?
- Must order be kept (insertion, sorted, none)? Are duplicates allowed?
- Does it cross goroutines or processes? Is it persisted or sent over the wire? How long does it live?

## 2. Decision table
| Need | Default | Switch when |
|---|---|---|
| Ordered sequence, scan, append | slice | frequent middle inserts on large N |
| Lookup by unique key | map keyed by a **typed** key | sorted iteration or range needed: sorted slice plus binary search; output order matters: sort keys at the edge, never rely on map order |
| Membership only | set (map to empty struct) | under about 20 items a slice is simpler and faster |
| Fixed small set of named things | enum plus array indexed by it, or a struct with named fields | never a map with string keys known at compile time |
| Record with named parts | struct | never a map or tuple; split by mode when fields are optional per mode |
| FIFO, LIFO, priority | queue, stack, heap from the standard library | bounded and concurrent: bounded channel |
| Hierarchy | tree of typed nodes | many cross-references: flat table by id, edges as ids |
| Many-to-many | two maps or an edge table keyed by typed ids | one side tiny: slice of ids |
| Text or bytes built step by step | builder or buffer | never string concatenation in a loop |
| Ranges, time windows | struct with start and end in a sorted slice | overlap queries at scale: interval tree, after measuring |
| Cache | bounded map with the eviction rule in its type | an unbounded map is a leak: ask for the bound |
| State with a lifecycle | enum plus transition table | see the `state-machines` skill |

## 3. Standard library and plain structures first
A specialised structure (tree, trie, skip list, bloom filter) needs a measurement or a stated
requirement in the design note. A new dependency still needs the user's approval.

## 4. Red flags: look again
- A map with fixed, known keys; `map[string]any` or untyped JSON inside core code.
- A slice searched linearly by key inside a loop (hidden O(n²)).
- Parallel slices or maps sharing one index.
- A map whose iteration order changes the output.
- A struct whose zero value is a valid but wrong state.
- A bool plus a time or error that only means something when the bool is set.
- A shared mutable structure with no owner; a "temporary" cache with no bound.
- A type that gains a new optional field for every task.

## 5. Design for the next change, not for imagined futures
Ask one question: what is the most likely next change to this data (a new variant, a new field, a
bigger N, a second consumer)? Does the structure absorb it by adding a row or a field, or by touching
every caller? If the second, choose the structure that does the first. This is not a speculative
abstraction: it picks among structures that already fit today's need.

## 6. Record the choice
The design note and the repo's `architecture` doc state: the structure chosen, the access pattern that
justified it, the alternative rejected, and the signal that would make us revisit it ("N above 10k:
switch to a sorted slice"). A persisted format also names its version.

## 7. Test the contract, not the internals
Table-driven tests for ordering, duplicates, empty and boundary sizes, and every invariant the type
promises.

# Architectural Decision Ledger

The ledger is the durable, high-level architectural guide for this repository.
It records material decisions that future humans and agents must understand to
change the system safely.

Task files explain what work happened. The ledger explains why the architecture
has its present shape and which constraints still govern it.

## What belongs here

Record a decision when it materially changes or establishes one of these:

- system boundaries, component ownership, or service responsibilities;
- public APIs, events, schemas, storage models, or compatibility contracts;
- data flow, control flow, consistency, or failure-handling strategy;
- security boundaries, trust assumptions, privacy, or authorization;
- runtime, deployment, infrastructure, platform, or major dependencies;
- a repository-wide convention that is expensive or risky to reverse.

Do not record routine implementation choices, task progress, file-by-file
changes, temporary experiments, or facts already obvious from the code. Those
belong in the relevant task leaf.

## Reading the architecture

Before proposing an architectural change:

1. Search all of `ledger/` for the affected domain and interface names.
2. Read relevant compacted ranges first; their `Architecture at ...` section is
   the fastest high-level view.
3. Read relevant uncompacted decisions for their full rationale.
4. Treat the newest non-superseded decision as authoritative when decisions
   conflict.

Compacted files and individual decisions are both first-class ledger records.
Search them together:

```sh
rg -n "domain term|interface name" ledger/
```

## Recording a decision

Ledger IDs are repository-wide, permanent, four-digit numbers.

1. Find the highest ID represented by either an individual file or a compacted
   range. The next ID is one greater than that value; never reuse an ID.
2. Copy `ledger/DECISION_TEMPLATE.md` to
   `ledger/NNNN-concise-kebab-title.md`.
3. Record only an accepted material decision. Keep unresolved options in an
   Exploration task until a decision is made.
4. State the architectural rule directly, its boundaries, and its consequences.
   Link the task or evidence that produced it.
5. Keep an individual decision concise—normally under 500 words.
6. Run `python3 scripts/validate_based.py`.

Decisions are append-only architectural history. If a later decision changes an
earlier one, create a new ID and mark the earlier decision `Superseded by NNNN`.
If the earlier ID is in a compacted file, update its decision-map row and the
compendium's supersession map. Do not rewrite old rationale to make it appear
current.

## Compaction

Compaction prevents many small decision documents from becoming expensive to
load. It distills a consecutive range such as individual decisions `0001` to
`0020` into one authoritative file named `0001-0020.md`.

Compaction is optional. Consider it when roughly 20 stable individual decisions
have accumulated or when agents repeatedly need to load the same set. Perform
it as explicit, reviewable work—not incidentally during an unrelated change.

### Compaction contract

1. Choose a consecutive, non-overlapping range of individual decision files.
   Do not include a proposed or unresolved decision. Compact only source files
   already preserved in Git history.
2. Read every source decision in full and copy
   `ledger/COMPACTION_TEMPLATE.md` to `ledger/NNNN-NNNN.md`.
3. Describe the architecture at the end of the range: boundaries, flows,
   contracts, invariants, approved technology, and lasting constraints.
4. Include every source ID exactly once in the decision map. Preserve its title,
   final status, source task, and one concise lasting rule or historical outcome.
5. Preserve supersession relationships and unresolved risks. When source
   decisions conflict, the higher decision ID wins unless the ledger explicitly
   says otherwise.
6. Do not introduce a new architectural decision during compaction. Create a new
   numbered decision instead.
7. Verify the compacted document against every source, then remove the covered
   individual files in the same change. Git history remains the detailed archive.
8. Run `python3 scripts/validate_based.py`. The validator rejects overlapping
   coverage, missing decision-map IDs, and individual files still covered by a
   compacted range.

After `0001-0020.md` exists, the next decision remains `0021`; compaction never
renumbers history.

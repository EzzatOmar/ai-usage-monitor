# BASED

## B ugs

- [~]: [B1](b/B1.md) - fix release actor isolation build

## A dditions

- [x]: [A1](a/A1.md) - add manual update check action
- [x]: [A2](a/A2.md) - add provider settings window

<!-- Example: - [ ]: [A1](a/A1.md) - concise addition title -->

## S ubtractions

- [x]: [S1](s/S1.md) - simplify the usage menu

## E xplorations

<!-- Example: - [ ]: [E1](e/E1.md) - concise exploration title -->

## D ebt

<!-- Example: - [ ]: [D1](d/D1.md) - concise debt title -->

## Introduction

Building software is exploratory, creative, and sometimes dull and repetitive.
This document outlines how to build software in a highly technical,
small and motivated team. The goal is to minimize management
and maximize throughput. The idea behind BASED is that programming is 90% context loading and 10% actual solving and coding. Therefore we should batch work for context loading and minimize context switching.
BASED skips the traditional agile ceremonies and focuses on the codebase and a glorified to-do list.
The to-do list is the heart of the project. No tickets, no boards, no sprints, no backlog.
Just a list of things to do. The list is grouped into 5 and must be ordered by
number, from low to high.
Every developer or agent picks an item, creates its leaf file, and records the
context and work there. Once the change is merged, mark the item closed and
keep its leaf file as durable project history.

Every change in the codebase can be grouped into one of the following categories:

B ugs: Something is not working as expected.
A dditions: New features or improvements.
S ubtractions: Removing or simplifying parts of the codebase.
E xplorations: Researching new technologies or ideas.
D ebt: Internal engineering work such as CI, scripts, test automation, tooling, maintenance, and technical debt.

Statuses are tagged:

- [ ]: open
- [x]: closed
- [?]: unsure
- [!]: urgent
- [~]: in progress
- [/]: blocked

Remember to keep the codebase small. Small is clean, small is fast. Delete often.

## Structure

BASED lives at the repository root in `tasks/`.

- `tasks/BASED.md`: overview, active index, and conventions.
- `tasks/TEMPLATE.md`: canonical starting point for a task leaf.
- `tasks/b/`: bug files.
- `tasks/a/`: addition files.
- `tasks/s/`: subtraction files.
- `tasks/e/`: exploration files.
- `tasks/d/`: debt files.

Each line in the overview stays short and links to one dedicated file.
Each dedicated file stores the task context, TODOs, notes, and logs.

## Format

Overview entries use this format:

`- [ ]: [B1](b/B1.md) - text: edit jumping`

Humans usually don't create leaf files. But agents do.

Create leaf files by copying `tasks/TEMPLATE.md` and replacing its example ID
and content. Every leaf file contains these sections in template order:

- `Context`: current behavior, motivation, constraints, and links to relevant
  repository files.
- `Scope`: what the task is allowed to change.
- `Non-goals`: adjacent work intentionally excluded from the task.
- `Acceptance Criteria`: observable, testable outcomes that define success.
- `Plan`: the ordered implementation approach.
- `TODOS`: implementation work derived from the plan.
- `Verification`: exact commands or manual checks and their recorded results.
- `NOTES`: non-trivial discoveries and decisions worth preserving.
- `LOGS`: a concise, dated execution history.

Acceptance criteria describe outcomes, while TODOs describe work. Do not mark an
acceptance criterion complete merely because its corresponding implementation
step is complete. Record the verification evidence that demonstrates the
outcome.

Logs are for meaningful actions, decisions, scope changes, discoveries,
blockers, and verification results. Do not log routine file reads, every shell
command, or information already clear from the diff. Use this format:

`- YYYY-MM-DD — concise event and, when relevant, its result`

Use the overview for scanning.
Use the leaf files for execution history and local context.
Never put a detailed plan in this file.
Never put leaf notes, lane breakdowns, execution history, or detailed task plans in this file.

## Validation

Run the dependency-free validator after changing the index, a leaf file, or the
task structure:

```sh
python3 scripts/validate_based.py
```

It checks entry syntax, valid status markers, category and numeric ordering,
unique IDs, index-to-leaf links, leaf titles, required sections, and orphaned
leaf files. It also checks ledger filenames, decision structure, unique ID
coverage, compacted ranges, and decision maps. A successful run prints
`BASED validation passed.` and exits with status 0.

## Architectural Decisions

Task logs record the execution history of a bounded piece of work. Material,
enduring architectural decisions belong in `ledger/`, whose
`ledger/README.md` defines materiality, decision format, supersession,
and optional compaction. Link a task to the decision it produces instead of copying
the full rationale into both places.

## Inline Plan Visuals

Task Markdown renders images and Mermaid diagrams inline, so visuals belong in
the leaf task's `## Plan` instead of living as detached references.

- Every supplied, external, or generated image used by a task must be copied
  next to that task's markdown file and embedded inside its `## Plan` with
  normal Markdown image syntax.
- Name the first image with the exact task id: `A100.md` -> `A100.png`. Name
  additional images `A100-2.png`, `A100-3.png`, and so on. Other task types use
  the same rule, for example `B12.png` or `E5-2.png`. Do not hotlink an external
  asset when a local task-owned copy can be stored.
- Use an inline fenced `mermaid` diagram in `## Plan` for flows, ownership,
  state transitions, service relationships, or multi-step interactions.
- Substantial Addition and Exploration plans should normally include at least
  one useful inline image or Mermaid diagram. Simple one-step tasks may omit a
  visual when it would add no information.
- Visuals supplement the written plan and acceptance criteria; when they
  disagree, the written task contract is authoritative.
- Keep relevant images supplied by the user, such as bug-report screenshots, in
  the task files you create or edit.
- Track task images and videos with Git LFS. Compression is still required:
  LFS prevents binary data from bloating ordinary Git objects, while compression
  reduces the asset itself.
- Compress every image and video before committing it. Use the verified CLI
  commands recorded below.

### Media tools in this repository

Task media must be compressed before commit. These tools are installed and
verified on macOS:

- PNG — oxipng 10.1.1:
  `find tasks -type f -name '*.png' -exec oxipng --strip safe --opt 4 -- {} +`
- Video — ffmpeg 8.1.2:
  `ffmpeg -n -i tasks/a/A1-source.mov -map_metadata -1 -c:v libx264 -crf 23 -preset medium -c:a aac -b:a 128k tasks/a/A1.mp4`

For the video command, replace `A1` and the source extension with the task
asset's actual ID and format. The `-n` flag prevents overwriting an existing
output; commit the compressed output, not the source export.

## Functional Core - Imperative Shell

Design software so that logic can be tested independently from effects. Split
each subsystem into a **functional core** that makes decisions and an
**imperative shell** that interacts with the outside world.

The domain already contains **essential complexity**: the rules and edge cases
the software exists to handle. Databases, networks, files, clocks, randomness,
frameworks, and process state introduce **accidental complexity** around those
rules. Mixing both kinds of complexity makes failures harder to reproduce and
forces logic tests to set up unrelated infrastructure. Separating them keeps
the essential behavior visible and allows meaningful subsections of the
software to be tested in isolation.

### Functional core

The core contains calculations, validation, transformations, state
transitions, and other domain decisions. Core functions must be deterministic:
given the same explicit inputs, they produce the same outputs.

- Do not read from or write to databases, networks, files, environment
  variables, clocks, random generators, global state, or mutable module state.
- Do not import an effectful client or service and call it from a core function.
  Dependency injection must never be implicit.
- Pass every value or capability on which a core function depends through its
  arguments. When time, randomness, or external data affects a decision, the
  shell obtains it and passes the resulting value into the core.
- Return decisions and descriptions of work as data. Let the shell interpret
  that data and perform the requested effects.

This boundary should make the core inexpensive to exercise with focused unit
tests, table-driven cases, property-based tests, and domain-specific
heuristics. Core tests should not require mocks, a running service, or other
infrastructure.

### Imperative shell

The shell owns effects and orchestration. It reads input, calls databases and
external services, obtains time or randomness, invokes the core with explicit
arguments, and applies the core's result.

Effectful code is inherently harder to test. Test it at the narrowest useful
boundary with integration tests, in-memory implementations, fakes, or mocks.
Keep decisions out of the shell so those tests verify wiring and external
contracts instead of re-testing domain logic through infrastructure.

### Make the boundary visible

The source layout must communicate which side of the boundary code belongs to.
Prefer separate files, and use names that make effects obvious, such as
`InvoiceCore.swift` and `InvoiceEffects.swift` or `InvoiceShell.swift`. Larger
subsystems should use corresponding `Core/` and `Effects/` directories.

Sometimes a small module must contain both logic and effects. Keep the two
parts visibly separated, preserve explicit argument passing, and split the
module once either part grows. A reader should never have to inspect a
function's implementation to discover that calling it may perform I/O.

## Code Style for Coding Agents

Agents usually navigate code with text search. Make important concepts easy to find, understand, and verify.

### 1. Use distinctive names

Include the domain in exported names. Aim for two or three meaningful words.

```swift
// Avoid
func create(key: String) {}

// Prefer
func createStripeClient(apiKey: String) {}
```

Use one spelling consistently—don’t mix `orgID` and `organizationID`.

### 2. Use precise types

Types let agents understand APIs without reading implementations and let the compiler catch mistakes.

```swift
// Avoid
func enrichUser(data: Any) -> Any { data }

// Prefer
func enrichUser(user: User) -> EnrichedUser {}
```

Use distinct types for otherwise interchangeable values:

```swift
struct UserID: RawRepresentable {
    let rawValue: String
}

struct OrganizationID: RawRepresentable {
    let rawValue: String
}

func transferUser(userID: UserID, organizationID: OrganizationID) {}
```

### 3. Keep code discoverable

- Name files after their responsibility: `StripeClient.swift`, not `Utilities.swift`.
- Keep modules focused; split large files by domain concept.
- Name tests after their source: `StripeClientTests.swift`.
- Avoid unnecessary import aliases and clever indirection.

### 4. Document where search lands

Place short comments directly above definitions. Explain constraints or intent—not obvious mechanics.

```swift
/// Uses full jitter to prevent synchronized retry spikes.
func calculateNotificationRetryDelay(attempt: Int) -> TimeInterval {}
```

Mark legacy APIs clearly:

```swift
@available(*, deprecated, renamed: "createStripeClient(apiKey:)")
func createClient() {}
```

Record repository-wide naming, layout, and testing conventions in `AGENTS.md`.

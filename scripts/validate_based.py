#!/usr/bin/env python3
"""Validate BASED tasks and the architectural ledger without dependencies."""

from __future__ import annotations

import re
import sys
from dataclasses import dataclass
from pathlib import Path


ROOT = Path(__file__).resolve().parents[1]
TASKS = ROOT / "tasks"
INDEX = TASKS / "BASED.md"
LEDGER = ROOT / "ledger"

CATEGORIES = {
  "B ugs": ("B", "b"),
  "A dditions": ("A", "a"),
  "S ubtractions": ("S", "s"),
  "E xplorations": ("E", "e"),
  "D ebt": ("D", "d"),
}
ENTRY_PATTERN = re.compile(
  r"^- \[([ x?!~/])\]: \[([BASE]\d+)\]\(([^)]+)\) - (.+)$"
)
REQUIRED_HEADINGS = [
  "## Context",
  "## Scope",
  "## Non-goals",
  "## Acceptance Criteria",
  "## Plan",
  "## TODOS",
  "## Verification",
  "## NOTES",
  "## LOGS",
]
DECISION_FILE_PATTERN = re.compile(
  r"^(\d{4})-([a-z0-9]+(?:-[a-z0-9]+)*)\.md$"
)
COMPACTION_FILE_PATTERN = re.compile(r"^(\d{4})-(\d{4})\.md$")
DECISION_HEADINGS = [
  "## Context",
  "## Decision",
  "## Architectural constraints",
  "## Consequences",
  "## Alternatives rejected",
  "## Evidence",
]
COMPACTION_HEADINGS = [
  "## Architecture at {end}",
  "## Decision map",
  "## Supersession map",
  "## Residual risks and follow-ups",
]


@dataclass(frozen=True)
class Entry:
  task_id: str
  title: str
  link: str
  line_number: int


def report(errors: list[str], path: Path, line_number: int, message: str) -> None:
  relative_path = path.relative_to(ROOT)
  errors.append(f"{relative_path}:{line_number}: {message}")


def validate_index(errors: list[str]) -> dict[str, Entry]:
  if not INDEX.is_file():
    errors.append("tasks/BASED.md: missing index")
    return {}

  lines = INDEX.read_text(encoding="utf-8").splitlines()
  headings = [
    (line.removeprefix("## "), line_number)
    for line_number, line in enumerate(lines, start=1)
    if line.startswith("## ") and line.removeprefix("## ") in CATEGORIES
  ]
  expected_headings = list(CATEGORIES)
  actual_headings = [heading for heading, _ in headings]
  if actual_headings != expected_headings:
    errors.append(
      "tasks/BASED.md: category headings must appear once in this order: "
      + ", ".join(expected_headings)
    )

  entries: dict[str, Entry] = {}
  current_category: str | None = None
  previous_numbers = {category: 0 for category in CATEGORIES}

  for line_number, line in enumerate(lines, start=1):
    if line.startswith("## "):
      heading = line.removeprefix("## ")
      current_category = heading if heading in CATEGORIES else None
      continue

    if current_category is None or not line.startswith("- ["):
      continue

    match = ENTRY_PATTERN.fullmatch(line)
    if match is None:
      report(errors, INDEX, line_number, "invalid task entry syntax")
      continue

    _, task_id, link, title = match.groups()
    expected_prefix, expected_directory = CATEGORIES[current_category]
    number = int(task_id[1:])

    if not task_id.startswith(expected_prefix):
      report(
        errors,
        INDEX,
        line_number,
        f"{task_id} is under the wrong category",
      )

    if number <= previous_numbers[current_category]:
      report(
        errors,
        INDEX,
        line_number,
        f"{task_id} is not in ascending numeric order",
      )
    previous_numbers[current_category] = number

    if task_id in entries:
      original_line = entries[task_id].line_number
      report(
        errors,
        INDEX,
        line_number,
        f"duplicate task ID {task_id}; first used on line {original_line}",
      )
      continue

    expected_link = f"{expected_directory}/{task_id}.md"
    if link != expected_link:
      report(
        errors,
        INDEX,
        line_number,
        f"{task_id} must link to {expected_link}, not {link}",
      )

    entries[task_id] = Entry(task_id, title, expected_link, line_number)

  return entries


def validate_leaf(errors: list[str], entry: Entry) -> None:
  leaf = TASKS / entry.link
  if not leaf.is_file():
    report(errors, INDEX, entry.line_number, f"linked leaf is missing: {entry.link}")
    return

  lines = leaf.read_text(encoding="utf-8").splitlines()
  expected_title = f"# {entry.task_id} - {entry.title}"
  if not lines or lines[0] != expected_title:
    report(errors, leaf, 1, f"expected title: {expected_title}")

  expected_overview = "[Overview](../BASED.md)"
  if len(lines) < 2 or lines[1] != expected_overview:
    report(errors, leaf, 2, f"expected overview link: {expected_overview}")

  heading_positions: list[int] = []
  for heading in REQUIRED_HEADINGS:
    matches = [
      line_number
      for line_number, line in enumerate(lines, start=1)
      if line == heading
    ]
    if len(matches) != 1:
      report(
        errors,
        leaf,
        matches[0] if matches else 1,
        f"expected exactly one {heading} heading",
      )
      continue
    heading_positions.append(matches[0])

  if len(heading_positions) == len(REQUIRED_HEADINGS):
    if heading_positions != sorted(heading_positions):
      report(errors, leaf, 1, "required headings are not in template order")


def validate_orphans(errors: list[str], entries: dict[str, Entry]) -> None:
  indexed_paths = {(TASKS / entry.link).resolve() for entry in entries.values()}
  for _, directory in CATEGORIES.values():
    category_directory = TASKS / directory
    if not category_directory.is_dir():
      errors.append(f"tasks/{directory}: missing category directory")
      continue

    for leaf in sorted(category_directory.glob("*.md")):
      if leaf.resolve() not in indexed_paths:
        report(errors, leaf, 1, "orphaned leaf is not linked from tasks/BASED.md")


def validate_ordered_headings(
  errors: list[str],
  path: Path,
  lines: list[str],
  headings: list[str],
) -> None:
  positions: list[int] = []
  for heading in headings:
    matches = [
      line_number
      for line_number, line in enumerate(lines, start=1)
      if line == heading
    ]
    if len(matches) != 1:
      report(
        errors,
        path,
        matches[0] if matches else 1,
        f"expected exactly one {heading} heading",
      )
      continue
    positions.append(matches[0])

  if len(positions) == len(headings) and positions != sorted(positions):
    report(errors, path, 1, "required headings are not in template order")


def validate_decision(errors: list[str], path: Path, decision_id: int) -> None:
  lines = path.read_text(encoding="utf-8").splitlines()
  padded_id = f"{decision_id:04d}"
  if not lines or not re.fullmatch(rf"# {padded_id} - .+", lines[0]):
    report(errors, path, 1, f"expected title: # {padded_id} - concise title")

  required_metadata = ["- Date:", "- Status:", "- Task:", "- Supersedes:"]
  for prefix in required_metadata:
    matches = [
      line_number
      for line_number, line in enumerate(lines, start=1)
      if line.startswith(prefix)
    ]
    if len(matches) != 1:
      report(
        errors,
        path,
        matches[0] if matches else 1,
        f"expected exactly one {prefix} metadata line",
      )

  status_lines = [line for line in lines if line.startswith("- Status:")]
  if len(status_lines) == 1:
    status = status_lines[0]
    if not re.fullmatch(r"- Status: (Active|Superseded by \d{4})", status):
      report(
        errors,
        path,
        lines.index(status) + 1,
        "status must be Active or Superseded by NNNN",
      )

  validate_ordered_headings(errors, path, lines, DECISION_HEADINGS)


def validate_compaction(
  errors: list[str],
  path: Path,
  start: int,
  end: int,
) -> None:
  lines = path.read_text(encoding="utf-8").splitlines()
  padded_start = f"{start:04d}"
  padded_end = f"{end:04d}"

  if start >= end:
    report(errors, path, 1, "compacted range end must be greater than its start")

  expected_title = f"# Decisions {padded_start}–{padded_end}"
  if not lines or lines[0] != expected_title:
    report(errors, path, 1, f"expected title: {expected_title}")

  expected_coverage = f"- Covers: {padded_start}–{padded_end}"
  if expected_coverage not in lines:
    report(errors, path, 1, f"expected coverage metadata: {expected_coverage}")

  headings = [
    heading.format(end=padded_end)
    for heading in COMPACTION_HEADINGS
  ]
  validate_ordered_headings(errors, path, lines, headings)

  mapped_ids: dict[int, int] = {}
  for line_number, line in enumerate(lines, start=1):
    row = re.match(r"^\|\s*(\d{4})\s*\|", line)
    if row is None:
      continue
    mapped_id = int(row.group(1))
    if mapped_id in mapped_ids:
      report(
        errors,
        path,
        line_number,
        f"decision map repeats {mapped_id:04d}",
      )
    mapped_ids[mapped_id] = line_number

  for decision_id in range(start, end + 1):
    if decision_id not in mapped_ids:
      report(
        errors,
        path,
        1,
        f"decision map is missing {decision_id:04d}",
      )

  for mapped_id, line_number in mapped_ids.items():
    if mapped_id < start or mapped_id > end:
      report(
        errors,
        path,
        line_number,
        f"decision map ID {mapped_id:04d} is outside the compacted range",
      )


def validate_ledger(errors: list[str]) -> None:
  if not LEDGER.is_dir():
    errors.append("ledger: missing architectural decision ledger")
    return

  required_files = {
    "README.md",
    "DECISION_TEMPLATE.md",
    "COMPACTION_TEMPLATE.md",
  }
  present_files = {path.name for path in LEDGER.glob("*.md")}
  for missing_file in sorted(required_files - present_files):
    errors.append(f"ledger/{missing_file}: missing ledger guide or template")

  individual_files: dict[int, Path] = {}
  compacted_ranges: list[tuple[int, int, Path]] = []

  for path in sorted(LEDGER.glob("*.md")):
    if path.name in required_files:
      continue

    compacted_match = COMPACTION_FILE_PATTERN.fullmatch(path.name)
    if compacted_match is not None:
      start, end = (int(value) for value in compacted_match.groups())
      compacted_ranges.append((start, end, path))
      validate_compaction(errors, path, start, end)
      continue

    decision_match = DECISION_FILE_PATTERN.fullmatch(path.name)
    if decision_match is not None:
      decision_id = int(decision_match.group(1))
      if decision_id in individual_files:
        report(
          errors,
          path,
          1,
          f"decision ID {decision_id:04d} has more than one file",
        )
      individual_files[decision_id] = path
      validate_decision(errors, path, decision_id)
      continue

    report(errors, path, 1, "invalid ledger filename")

  covered_ids: dict[int, Path] = {}
  for start, end, path in sorted(compacted_ranges):
    for decision_id in range(start, end + 1):
      if decision_id in covered_ids:
        other_path = covered_ids[decision_id]
        report(
          errors,
          path,
          1,
          f"compacted range overlaps {other_path.name} at {decision_id:04d}",
        )
      covered_ids[decision_id] = path

  for decision_id, path in individual_files.items():
    if decision_id in covered_ids:
      report(
        errors,
        path,
        1,
        f"individual decision is already covered by {covered_ids[decision_id].name}",
      )


def main() -> int:
  errors: list[str] = []
  entries = validate_index(errors)
  for entry in entries.values():
    validate_leaf(errors, entry)
  validate_orphans(errors, entries)
  validate_ledger(errors)

  if errors:
    print("BASED validation failed:", file=sys.stderr)
    for error in errors:
      print(f"- {error}", file=sys.stderr)
    return 1

  print("BASED validation passed.")
  return 0


if __name__ == "__main__":
  raise SystemExit(main())

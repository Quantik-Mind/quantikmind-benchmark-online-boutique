#!/usr/bin/env python3
"""Create a deterministic random benchmark test selection."""

from __future__ import annotations

import argparse
import json
import random
import sys
from pathlib import Path
from typing import Any


DEFAULT_LIBRARY = "qmind-test-library/online-boutique-playwright-51.json"
METHOD_LABELS = {
    "full-suite": "Traditional Approach (Full Suite)",
    "random": "Random Approach",
    "history-code-change": "History + Code Change Approach",
    "qmind": "Quantik Mind",
}
TEST_ID_KEYS = ("test_id", "id", "name", "title")
SELECTION_FIELDS = (
    "selected_tests",
    "selectedTests",
    "tests",
    "subset",
    "top_candidates",
    "topCandidates",
    "selected",
    "items",
)
NESTED_SELECTION_FIELDS = ("data", "result", "selection", "payload")


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(
        description="Select a deterministic random subset from the canonical test library."
    )
    parser.add_argument(
        "--library",
        default=DEFAULT_LIBRARY,
        help=f"Path to canonical test library JSON. Defaults to {DEFAULT_LIBRARY}.",
    )
    parser.add_argument(
        "--size",
        type=int,
        help="Number of unique tests to select. Required unless --same-size-as is provided.",
    )
    parser.add_argument(
        "--same-size-as",
        help="Selected tests JSON whose selected test count should be reused.",
    )
    parser.add_argument(
        "--seed",
        type=int,
        default=42,
        help="Deterministic random seed. Defaults to 42.",
    )
    parser.add_argument(
        "--method-name",
        default="random",
        help="Machine-readable method slug. Defaults to random.",
    )
    parser.add_argument("--output", help="Optional path to write the selected-test JSON.")
    return parser.parse_args()


def load_json(path: Path, label: str) -> Any:
    if not path.exists():
        raise SystemExit(f"{label} file does not exist: {path}")
    if not path.is_file():
        raise SystemExit(f"{label} path is not a file: {path}")

    try:
        return json.loads(path.read_text(encoding="utf-8"))
    except OSError as exc:
        raise SystemExit(f"Could not read {label} file {path}: {exc}") from exc
    except json.JSONDecodeError as exc:
        raise SystemExit(
            f"Invalid JSON in {label} file {path}: line {exc.lineno}, column {exc.colno}: {exc.msg}"
        ) from exc


def test_id_from_item(item: Any) -> str | None:
    if isinstance(item, (str, int, float, bool)):
        value = str(item).strip()
        return value or None
    if not isinstance(item, dict):
        return None

    for key in TEST_ID_KEYS:
        value = item.get(key)
        if value is not None:
            test_id = str(value).strip()
            if test_id:
                return test_id

    nested_test = item.get("test")
    if nested_test is not None:
        return test_id_from_item(nested_test)

    return None


def collect_test_ids(items: list[Any]) -> list[str]:
    return [test_id for item in items if (test_id := test_id_from_item(item))]


def selected_tests_from_object(data: dict[str, Any]) -> list[str]:
    for field in SELECTION_FIELDS:
        value = data.get(field)
        if isinstance(value, list):
            selected = collect_test_ids(value)
            if selected:
                return selected

    for field in NESTED_SELECTION_FIELDS:
        nested = data.get(field)
        if isinstance(nested, dict):
            selected = selected_tests_from_object(nested)
            if selected:
                return selected

    return []


def load_selected_count(path: Path) -> int:
    data = load_json(path, "Selected tests")
    if isinstance(data, list):
        selected = collect_test_ids(data)
    elif isinstance(data, dict):
        selected = selected_tests_from_object(data)
    else:
        raise SystemExit(
            "Selected tests JSON must be an array or an object containing a selected tests list."
        )

    selected_count = len(set(selected))
    if selected_count <= 0:
        raise SystemExit(f"No selected tests found in {path}.")
    return selected_count


def load_library_ids(path: Path) -> list[str]:
    data = load_json(path, "Library")
    if isinstance(data, dict):
        tests = data.get("tests")
    elif isinstance(data, list):
        tests = data
    else:
        raise SystemExit("Library JSON must be an object with a 'tests' list or an array.")

    if not isinstance(tests, list):
        raise SystemExit("Library JSON must contain a 'tests' list.")

    test_ids = sorted(set(collect_test_ids(tests)))
    if not test_ids:
        raise SystemExit(f"No test identifiers found in library: {path}")
    return test_ids


def selection_size(args: argparse.Namespace) -> int:
    if args.same_size_as:
        size = load_selected_count(Path(args.same_size_as))
    elif args.size is not None:
        size = args.size
    else:
        raise SystemExit("--size is required unless --same-size-as is provided.")

    if size <= 0:
        raise SystemExit("Selection size must be a positive integer.")
    return size


def write_output(path: Path, payload: str) -> None:
    try:
        path.parent.mkdir(parents=True, exist_ok=True)
        path.write_text(payload + "\n", encoding="utf-8")
    except OSError as exc:
        raise SystemExit(f"Could not write output file {path}: {exc}") from exc


def main() -> int:
    args = parse_args()
    library_path = Path(args.library)
    test_ids = load_library_ids(library_path)
    size = selection_size(args)

    if size > len(test_ids):
        raise SystemExit(
            f"Cannot select {size} tests from library with only {len(test_ids)} tests."
        )

    selected_tests = sorted(random.Random(args.seed).sample(test_ids, size))
    result = {
        "method": args.method_name,
        "method_label": METHOD_LABELS.get(args.method_name, args.method_name),
        "selection_size": size,
        "seed": args.seed,
        "source_library": str(library_path),
        "selected_tests": selected_tests,
    }
    payload = json.dumps(result, indent=2)

    print(payload)
    if args.output:
        write_output(Path(args.output), payload)
    return 0


if __name__ == "__main__":
    sys.exit(main())

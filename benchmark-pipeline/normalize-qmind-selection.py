#!/usr/bin/env python3
"""Normalize qmind subset output to canonical benchmark test IDs."""

from __future__ import annotations

import argparse
import json
import re
import sys
from pathlib import Path
from typing import Any, Iterable


TEST_ID_KEYS = ("test_id", "id", "testId", "name")
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
NUMERIC_ID_PATTERN = re.compile(r"^\d+$")


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(
        description="Normalize qmind subset output to canonical test IDs."
    )
    parser.add_argument("raw", help="Path to raw qmind subset output.")
    parser.add_argument("output", help="Path to write normalized selected tests JSON.")
    parser.add_argument(
        "--library-api",
        help=(
            "Path to a qmind library API/export JSON containing numeric 'id' and "
            "canonical 'test_id' fields."
        ),
    )
    return parser.parse_args()


def load_json_text(text: str) -> Any:
    try:
        return json.loads(text)
    except json.JSONDecodeError:
        start = text.find("{")
        end = text.rfind("}")
        if start == -1 or end == -1 or end <= start:
            raise
        return json.loads(text[start : end + 1])


def read_raw_selection(path: Path) -> Any:
    raw_text = path.read_text(encoding="utf-8").strip()
    if not raw_text:
        raise SystemExit(f"Raw qmind selection is empty: {path}")

    try:
        return load_json_text(raw_text)
    except json.JSONDecodeError:
        tokens = raw_text.split()
        if tokens and all(NUMERIC_ID_PATTERN.fullmatch(token) for token in tokens):
            return tokens
        raise SystemExit(
            "Could not parse qmind output as JSON or whitespace-separated numeric IDs."
        )


def test_id_from_item(item: Any) -> str | None:
    if isinstance(item, (str, int)):
        return str(item).strip()

    if not isinstance(item, dict):
        return None

    for key in TEST_ID_KEYS:
        value = item.get(key)
        if value is not None:
            text = str(value).strip()
            if text:
                return text

    test = item.get("test")
    if test is not None:
        return test_id_from_item(test)

    return None


def collect_test_ids(items: Iterable[Any]) -> list[str]:
    selected: list[str] = []
    for item in items:
        test_id = test_id_from_item(item)
        if test_id:
            selected.append(test_id)
    return selected


def selected_tests_from_object(data: dict[str, Any]) -> list[str]:
    for field in SELECTION_FIELDS:
        value = data.get(field)
        if isinstance(value, list):
            selected = collect_test_ids(value)
            if selected:
                return selected

    for nested_field in NESTED_SELECTION_FIELDS:
        nested = data.get(nested_field)
        if isinstance(nested, dict):
            selected = selected_tests_from_object(nested)
            if selected:
                return selected

    return []


def extract_selected_tests(raw: Any) -> list[str]:
    if isinstance(raw, list):
        return collect_test_ids(raw)
    if isinstance(raw, dict):
        return selected_tests_from_object(raw)
    raise SystemExit(
        "qmind selection must be JSON array, JSON object, or whitespace-separated numeric IDs."
    )


def mapping_items(data: Any) -> Iterable[Any]:
    if isinstance(data, list):
        return data
    if isinstance(data, dict):
        for field in ("data", "tests", "items", "results"):
            value = data.get(field)
            if isinstance(value, list):
                return value
    return []


def load_library_api_mapping(path: Path) -> dict[str, str]:
    if not path.exists() or not path.is_file():
        raise SystemExit("Missing library API mapping for qmind numeric IDs.")

    try:
        raw = path.read_bytes()
    except OSError as exc:
        raise SystemExit(f"Could not read library API mapping {path}: {exc}") from exc

    last_decode_error: UnicodeDecodeError | None = None
    for encoding in ("utf-8", "utf-8-sig", "utf-16"):
        try:
            data = json.loads(raw.decode(encoding))
            break
        except UnicodeDecodeError as exc:
            last_decode_error = exc
            continue
        except json.JSONDecodeError as exc:
            raise SystemExit(
                f"Invalid JSON in library API mapping {path}: line {exc.lineno}, column {exc.colno}: {exc.msg}"
            ) from exc
    else:
        raise SystemExit(f"Could not decode library API mapping {path}: {last_decode_error}")

    mapping: dict[str, str] = {}
    for item in mapping_items(data):
        if not isinstance(item, dict):
            continue
        raw_id = item.get("id")
        test_id = item.get("test_id")
        if raw_id is None or not isinstance(test_id, str) or not test_id.strip():
            continue
        mapping[str(raw_id).strip()] = test_id.strip()

    if not mapping:
        raise SystemExit("Missing library API mapping for qmind numeric IDs.")
    return mapping


def normalize_ids(selected: list[str], library_api: str | None) -> list[str]:
    numeric_ids = [test_id for test_id in selected if NUMERIC_ID_PATTERN.fullmatch(test_id)]
    if not numeric_ids:
        return sorted(set(selected))

    if not library_api:
        raise SystemExit("Missing library API mapping for qmind numeric IDs.")

    mapping = load_library_api_mapping(Path(library_api))
    missing = sorted(set(numeric_ids) - set(mapping))
    if missing:
        raise SystemExit("Missing library API mapping for qmind numeric IDs.")

    normalized = [mapping.get(test_id, test_id) for test_id in selected]
    return sorted(set(normalized))


def write_output(path: Path, selected: list[str]) -> str:
    payload = json.dumps({"selected_tests": selected}, indent=2)
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text(payload + "\n", encoding="utf-8")
    return payload


def main() -> int:
    args = parse_args()
    raw = read_raw_selection(Path(args.raw))
    selected = extract_selected_tests(raw)
    selected = normalize_ids(selected, args.library_api)

    if not selected:
        raise SystemExit(
            "Could not find selected tests in qmind output. "
            "Inspect qmind subset output and update normalize-qmind-selection.py."
        )

    print(write_output(Path(args.output), selected))
    return 0


if __name__ == "__main__":
    sys.exit(main())

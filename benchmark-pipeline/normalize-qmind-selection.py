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
BUSINESS_METRIC_FIELDS = (
    "risk_coverage",
    "top_risk_coverage",
    "residual_risk",
    "risk_efficiency",
)
TOP_LEVEL_RISK_FIELDS = BUSINESS_METRIC_FIELDS
NUMERIC_ID_PATTERN = re.compile(r"^\d+$")
CANONICAL_TEXT_ID_PATTERN = re.compile(r"^[A-Za-z0-9][A-Za-z0-9_-]*$")


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
        for line in raw_text.splitlines():
            line_tokens = line.strip().split()
            if (
                line_tokens
                and all(CANONICAL_TEXT_ID_PATTERN.fullmatch(token) for token in line_tokens)
                and any("-" in token for token in line_tokens)
            ):
                return line_tokens
        raise SystemExit(
            "Could not parse qmind output as JSON, whitespace-separated numeric IDs, "
            "or whitespace-separated canonical test IDs."
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
        "qmind selection must be JSON array, JSON object, whitespace-separated numeric IDs, "
        "or whitespace-separated canonical test IDs."
    )


def first_object_with_key(data: Any, key: str) -> dict[str, Any] | None:
    if isinstance(data, dict):
        if key in data and isinstance(data[key], dict):
            return data[key]
        for value in data.values():
            found = first_object_with_key(value, key)
            if found is not None:
                return found
    elif isinstance(data, list):
        for item in data:
            found = first_object_with_key(item, key)
            if found is not None:
                return found
    return None


def first_value_for_key(data: Any, key: str) -> Any:
    if isinstance(data, dict):
        if key in data:
            return data[key]
        for value in data.values():
            found = first_value_for_key(value, key)
            if found is not None:
                return found
    elif isinstance(data, list):
        for item in data:
            found = first_value_for_key(item, key)
            if found is not None:
                return found
    return None


def numeric_or_none(value: Any) -> int | float | None:
    if value is None or isinstance(value, bool):
        return None
    if isinstance(value, (int, float)):
        return value
    if isinstance(value, str):
        text = value.strip()
        if not text:
            return None
        try:
            return int(text)
        except ValueError:
            try:
                return float(text)
            except ValueError:
                return None
    return None


def extract_dynamic_risk_fields(raw: Any) -> dict[str, Any]:
    if not isinstance(raw, dict):
        return {}

    payload: dict[str, Any] = {}
    raw_business_metrics = first_object_with_key(raw, "business_metrics")
    business_metrics: dict[str, Any] = {}

    if raw_business_metrics:
        for field in BUSINESS_METRIC_FIELDS:
            value = numeric_or_none(raw_business_metrics.get(field))
            if value is not None:
                business_metrics[field] = value

    for field in TOP_LEVEL_RISK_FIELDS:
        value = numeric_or_none(raw.get(field))
        if value is None:
            value = numeric_or_none(first_value_for_key(raw, field))
        if value is not None:
            payload[field] = value
            business_metrics.setdefault(field, value)

    if business_metrics:
        payload["business_metrics"] = business_metrics
    return payload


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
        data = json.loads(path.read_text(encoding="utf-8"))
    except OSError as exc:
        raise SystemExit(f"Could not read library API mapping {path}: {exc}") from exc
    except json.JSONDecodeError as exc:
        raise SystemExit(
            f"Invalid JSON in library API mapping {path}: line {exc.lineno}, column {exc.colno}: {exc.msg}"
        ) from exc

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


def write_output(path: Path, selected: list[str], dynamic_risk_fields: dict[str, Any]) -> str:
    output = {"selected_tests": selected}
    output.update(dynamic_risk_fields)
    payload = json.dumps(output, indent=2)
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text(payload + "\n", encoding="utf-8")
    return payload


def main() -> int:
    args = parse_args()
    raw = read_raw_selection(Path(args.raw))
    selected = extract_selected_tests(raw)
    selected = normalize_ids(selected, args.library_api)
    dynamic_risk_fields = extract_dynamic_risk_fields(raw)

    if not selected:
        raise SystemExit(
            "Could not find selected tests in qmind output. "
            "Inspect qmind subset output and update normalize-qmind-selection.py."
        )

    print(write_output(Path(args.output), selected, dynamic_risk_fields))
    return 0


if __name__ == "__main__":
    sys.exit(main())

#!/usr/bin/env python3
"""Evaluate selected tests against the scenario defect oracle."""

from __future__ import annotations

import argparse
import json
import re
import sys
from pathlib import Path
from typing import Any, Iterable


DEFAULT_ORACLE = "defect-oracle/online-boutique-defect-oracle.v2.json"
NUMERIC_ID_PATTERN = re.compile(r"^\d+$")
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
        description="Evaluate selected tests against benchmark defect scenarios."
    )
    parser.add_argument(
        "--oracle",
        default=DEFAULT_ORACLE,
        help=f"Path to defect oracle JSON. Defaults to {DEFAULT_ORACLE}.",
    )
    parser.add_argument(
        "--selected",
        required=True,
        help="Path to selected tests JSON.",
    )
    parser.add_argument(
        "--method",
        required=True,
        help="Selection method name, for example qmind, random, historical-risk, or full-suite.",
    )
    parser.add_argument(
        "--use-validated",
        action="store_true",
        help="Use validated_detecting_tests instead of expected_detecting_tests.",
    )
    parser.add_argument(
        "--scenario",
        help="Optional benchmark case/scenario id to evaluate, for example OB-001.",
    )
    parser.add_argument(
        "--output",
        help="Optional path to write the JSON report.",
    )
    parser.add_argument(
        "--library-api",
        help=(
            "Optional qmind library API/export JSON used to map numeric qmind "
            "backend/API IDs to canonical test IDs."
        ),
    )
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


def string_list(value: Any, field_name: str) -> list[str]:
    if value is None:
        return []
    if not isinstance(value, list):
        raise SystemExit(f"Oracle field '{field_name}' must be a list.")
    return [str(item) for item in value]


def test_id_from_item(item: Any) -> str | None:
    if isinstance(item, (str, int, float, bool)):
        return str(item)
    if not isinstance(item, dict):
        return None

    for key in TEST_ID_KEYS:
        if key in item and item[key] is not None:
            value = str(item[key]).strip()
            if value:
                return value

    nested_test = item.get("test")
    if nested_test is not None:
        return test_id_from_item(nested_test)

    return None


def collect_test_ids(items: Iterable[Any]) -> list[str]:
    test_ids: list[str] = []
    for item in items:
        test_id = test_id_from_item(item)
        if test_id:
            test_ids.append(test_id)
    return test_ids


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


def load_selected_tests(path: Path) -> list[str]:
    data = load_json(path, "Selected tests")

    if isinstance(data, list):
        selected = collect_test_ids(data)
    elif isinstance(data, dict):
        selected = selected_tests_from_object(data)
    else:
        raise SystemExit(
            "Selected tests JSON must be an array or an object containing a selected tests list."
        )

    selected = sorted(set(selected))
    if not selected:
        raise SystemExit(f"No selected tests found in {path}.")
    return selected


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

    data = load_json(path, "Library API mapping")
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


def normalize_numeric_selected_tests(
    selected_tests: list[str], library_api: str | None
) -> list[str]:
    numeric_ids = [
        test_id for test_id in selected_tests if NUMERIC_ID_PATTERN.fullmatch(test_id)
    ]
    if not numeric_ids:
        return selected_tests

    if not library_api:
        raise SystemExit("Missing library API mapping for qmind numeric IDs.")

    mapping = load_library_api_mapping(Path(library_api))
    missing = sorted(set(numeric_ids) - set(mapping))
    if missing:
        raise SystemExit("Missing library API mapping for qmind numeric IDs.")

    return sorted(set(mapping.get(test_id, test_id) for test_id in selected_tests))


def load_oracle(path: Path) -> dict[str, Any]:
    data = load_json(path, "Oracle")
    if not isinstance(data, dict):
        raise SystemExit("Oracle JSON must be an object.")
    if not isinstance(data.get("scenarios"), list):
        raise SystemExit("Oracle JSON must contain a 'scenarios' list.")
    return data


def evaluate(
    oracle: dict[str, Any],
    selected_tests: list[str],
    method: str,
    use_validated: bool,
    scenario_id: str | None = None,
) -> dict[str, Any]:
    selected_set = set(selected_tests)
    detecting_field = "validated_detecting_tests" if use_validated else "expected_detecting_tests"
    full_suite_size = int(oracle.get("full_suite_size") or 0)
    if full_suite_size <= 0:
        raise SystemExit("Oracle field 'full_suite_size' must be a positive integer.")

    scenarios = sorted(oracle["scenarios"], key=lambda item: str(item.get("id", "")))
    if scenario_id:
        scenarios = [
            scenario
            for scenario in scenarios
            if str(scenario.get("id", "")).strip() == scenario_id
        ]
        if not scenarios:
            raise SystemExit(f"Scenario id not found in oracle: {scenario_id}")
    per_scenario: list[dict[str, Any]] = []

    for scenario in scenarios:
        if not isinstance(scenario, dict):
            raise SystemExit("Each oracle scenario must be an object.")

        detecting_tests = sorted(set(string_list(scenario.get(detecting_field), detecting_field)))
        selected_detecting = sorted(selected_set.intersection(detecting_tests))

        per_scenario.append(
            {
                "id": str(scenario.get("id", "")),
                "name": str(scenario.get("name", "")),
                "detected": bool(selected_detecting),
                "selected_detecting_tests": selected_detecting,
                "detecting_tests_used": detecting_tests,
                "validation_status": str(scenario.get("validation_status", "")),
            }
        )

    total_scenarios = len(per_scenario)
    detected_scenarios_count = sum(1 for item in per_scenario if item["detected"])
    missed_scenarios_count = total_scenarios - detected_scenarios_count
    selected_test_count = len(selected_tests)

    return {
        "method": method,
        "benchmark_case": scenario_id,
        "full_suite_size": full_suite_size,
        "selected_test_count": selected_test_count,
        "execution_reduction": 1 - selected_test_count / full_suite_size,
        "total_scenarios": total_scenarios,
        "detected_scenarios_count": detected_scenarios_count,
        "missed_scenarios_count": missed_scenarios_count,
        "defect_recall": detected_scenarios_count / total_scenarios if total_scenarios else 0,
        "per_scenario": per_scenario,
    }


def write_output(path: Path, payload: str) -> None:
    try:
        path.parent.mkdir(parents=True, exist_ok=True)
        path.write_text(payload + "\n", encoding="utf-8")
    except OSError as exc:
        raise SystemExit(f"Could not write output file {path}: {exc}") from exc


def main() -> int:
    args = parse_args()
    oracle = load_oracle(Path(args.oracle))
    selected_tests = load_selected_tests(Path(args.selected))
    selected_tests = normalize_numeric_selected_tests(selected_tests, args.library_api)
    report = evaluate(oracle, selected_tests, args.method, args.use_validated, args.scenario)
    payload = json.dumps(report, indent=2)

    print(payload)
    if args.output:
        write_output(Path(args.output), payload)
    return 0


if __name__ == "__main__":
    sys.exit(main())

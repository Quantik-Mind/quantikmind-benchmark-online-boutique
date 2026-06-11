#!/usr/bin/env python3
"""Validate the defect oracle against the canonical test library."""

from __future__ import annotations

import argparse
import json
import sys
from pathlib import Path
from typing import Any


DEFAULT_ORACLE = "defect-oracle/online-boutique-defect-oracle.v2.json"
DEFAULT_LIBRARY = "qmind-test-library/online-boutique-playwright-50.json"
TEST_ID_KEYS = ("test_id", "id", "name", "title")


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(
        description="Check that defect oracle test identifiers match the canonical test library."
    )
    parser.add_argument(
        "--oracle",
        default=DEFAULT_ORACLE,
        help=f"Path to defect oracle JSON. Defaults to {DEFAULT_ORACLE}.",
    )
    parser.add_argument(
        "--library",
        default=DEFAULT_LIBRARY,
        help=f"Path to canonical qmind test library JSON. Defaults to {DEFAULT_LIBRARY}.",
    )
    parser.add_argument(
        "--strict",
        action="store_true",
        help="Treat warnings as failures. Unknown expected_unaffected_tests labels become errors.",
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


def load_oracle(path: Path) -> dict[str, Any]:
    data = load_json(path, "Oracle")
    if not isinstance(data, dict):
        raise SystemExit("Oracle JSON must be an object.")
    if not isinstance(data.get("scenarios"), list):
        raise SystemExit("Oracle JSON must contain a 'scenarios' list.")
    return data


def id_from_item(item: Any) -> str | None:
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
    return None


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

    test_ids = [test_id for item in tests if (test_id := id_from_item(item))]
    if not test_ids:
        raise SystemExit(f"No test identifiers found in library: {path}")
    return sorted(set(test_ids))


def list_field(
    scenario: dict[str, Any],
    field_name: str,
    errors: list[str],
    *,
    required: bool = False,
) -> list[str]:
    if field_name not in scenario:
        if required:
            errors.append(f"Missing required field '{field_name}'.")
        return []

    value = scenario[field_name]
    if not isinstance(value, list):
        errors.append(f"Field '{field_name}' must be a list.")
        return []

    values: list[str] = []
    for index, item in enumerate(value):
        if isinstance(item, (str, int, float, bool)):
            text = str(item).strip()
            if text:
                values.append(text)
            else:
                errors.append(f"Field '{field_name}' item {index} is empty.")
        else:
            errors.append(f"Field '{field_name}' item {index} must be a test ID string.")
    return values


def duplicate_values(values: list[str]) -> list[str]:
    seen: set[str] = set()
    duplicates: set[str] = set()
    for value in values:
        if value in seen:
            duplicates.add(value)
        seen.add(value)
    return sorted(duplicates)


def scenario_label(scenario: dict[str, Any], fallback_index: int) -> str:
    scenario_id = str(scenario.get("id", "")).strip()
    if scenario_id:
        return scenario_id
    return f"scenario[{fallback_index}]"


def add_prefixed(
    target: list[str],
    scenario: dict[str, Any],
    fallback_index: int,
    messages: list[str],
) -> None:
    label = scenario_label(scenario, fallback_index)
    for message in messages:
        target.append(f"{label}: {message}")


def check_scenario(
    scenario: Any,
    index: int,
    library_ids: set[str],
    strict: bool,
) -> dict[str, Any]:
    errors: list[str] = []
    warnings: list[str] = []

    if not isinstance(scenario, dict):
        return {
            "id": "",
            "name": "",
            "validation_status": "",
            "errors": [f"Scenario item {index} must be an object."],
            "warnings": [],
            "checks": {
                "has_id": False,
                "has_name": False,
                "has_validation_status": False,
                "expected_detecting_tests_exist": False,
                "validated_detecting_tests_allowed": False,
            },
        }

    scenario_id = str(scenario.get("id", "")).strip()
    name = str(scenario.get("name", "")).strip()
    validation_status = str(scenario.get("validation_status", "")).strip()

    if not scenario_id:
        errors.append("Missing required field 'id'.")
    if not name:
        errors.append("Missing required field 'name'.")
    if not validation_status:
        errors.append("Missing required field 'validation_status'.")

    expected_detecting = list_field(
        scenario,
        "expected_detecting_tests",
        errors,
        required=True,
    )
    validated_detecting = list_field(scenario, "validated_detecting_tests", errors)
    expected_unaffected = list_field(scenario, "expected_unaffected_tests", errors)

    duplicate_expected = duplicate_values(expected_detecting)
    if duplicate_expected:
        errors.append(
            "Duplicate expected_detecting_tests: " + ", ".join(duplicate_expected)
        )

    duplicate_validated = duplicate_values(validated_detecting)
    if duplicate_validated:
        errors.append(
            "Duplicate validated_detecting_tests: " + ", ".join(duplicate_validated)
        )

    missing_expected = sorted(set(expected_detecting).difference(library_ids))
    if missing_expected:
        errors.append(
            "expected_detecting_tests not found in library: " + ", ".join(missing_expected)
        )

    missing_validated = sorted(set(validated_detecting).difference(library_ids))
    if missing_validated:
        errors.append(
            "validated_detecting_tests not found in library: " + ", ".join(missing_validated)
        )

    missing_unaffected = sorted(set(expected_unaffected).difference(library_ids))
    if missing_unaffected:
        message = (
            "expected_unaffected_tests values not found in library; these may be broad labels: "
            + ", ".join(missing_unaffected)
        )
        if strict:
            errors.append(message)
        else:
            warnings.append(message)

    if validation_status == "validated" and not validated_detecting:
        errors.append(
            "validation_status is 'validated' but validated_detecting_tests is empty."
        )

    validated_allowed = validation_status == "planned" or bool(validated_detecting)

    return {
        "id": scenario_id,
        "name": name,
        "validation_status": validation_status,
        "errors": errors,
        "warnings": warnings,
        "checks": {
            "has_id": bool(scenario_id),
            "has_name": bool(name),
            "has_validation_status": bool(validation_status),
            "expected_detecting_tests_exist": "expected_detecting_tests" in scenario,
            "expected_detecting_tests_all_in_library": not missing_expected,
            "expected_unaffected_tests_all_in_library": not missing_unaffected,
            "validated_detecting_tests_all_in_library": not missing_validated,
            "no_duplicate_expected_detecting_tests": not duplicate_expected,
            "no_duplicate_validated_detecting_tests": not duplicate_validated,
            "validated_detecting_tests_allowed": validated_allowed,
        },
    }


def build_report(
    oracle_path: Path,
    library_path: Path,
    oracle: dict[str, Any],
    library_test_ids: list[str],
    strict: bool,
) -> dict[str, Any]:
    library_ids = set(library_test_ids)
    scenarios = sorted(
        oracle["scenarios"],
        key=lambda item: str(item.get("id", "")) if isinstance(item, dict) else "",
    )

    per_scenario = [
        check_scenario(scenario, index, library_ids, strict)
        for index, scenario in enumerate(scenarios)
    ]

    errors: list[str] = []
    warnings: list[str] = []
    for index, scenario_report in enumerate(per_scenario):
        scenario = scenarios[index] if index < len(scenarios) else {}
        add_prefixed(errors, scenario if isinstance(scenario, dict) else {}, index, scenario_report["errors"])
        add_prefixed(
            warnings,
            scenario if isinstance(scenario, dict) else {},
            index,
            scenario_report["warnings"],
        )

    if errors or (strict and warnings):
        status = "fail"
    elif warnings:
        status = "warn"
    else:
        status = "pass"

    return {
        "status": status,
        "oracle": str(oracle_path),
        "library": str(library_path),
        "total_library_tests": len(library_test_ids),
        "total_scenarios": len(scenarios),
        "strict": strict,
        "errors": errors,
        "warnings": warnings,
        "per_scenario": per_scenario,
    }


def main() -> int:
    args = parse_args()
    oracle_path = Path(args.oracle)
    library_path = Path(args.library)
    oracle = load_oracle(oracle_path)
    library_test_ids = load_library_ids(library_path)
    report = build_report(oracle_path, library_path, oracle, library_test_ids, args.strict)

    print(json.dumps(report, indent=2, sort_keys=True))
    return 1 if report["status"] == "fail" else 0


if __name__ == "__main__":
    sys.exit(main())

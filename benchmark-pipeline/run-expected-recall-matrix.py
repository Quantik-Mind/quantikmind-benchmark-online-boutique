#!/usr/bin/env python3
"""Run the expected-oracle defect-recall comparison matrix."""

from __future__ import annotations

import argparse
import json
import random
import re
import sys
from pathlib import Path
from typing import Any, Iterable


DEFAULT_ORACLE = "defect-oracle/online-boutique-defect-oracle.v2.json"
DEFAULT_LIBRARY = "qmind-test-library/online-boutique-playwright-50.json"
DEFAULT_QMIND_SELECTED = "qmind-test-library/online-boutique-playwright-11.json"
DEFAULT_SCENARIOS = "benchmark-pipeline/scenarios.json"
EXPECTED_ORACLE_WARNING = (
    "These results use expected oracle data. They are useful for pipeline "
    "validation only and must not be presented as validated defect-recall results."
)
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
HIGH_RISK_KEYWORDS = (
    "checkout",
    "order",
    "payment",
    "cart",
    "product",
    "catalog",
    "frontend",
)
STOPWORDS = {
    "and",
    "are",
    "for",
    "from",
    "into",
    "not",
    "over",
    "page",
    "path",
    "src",
    "the",
    "this",
    "with",
}


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(
        description="Run expected-oracle recall across benchmark comparison methods."
    )
    parser.add_argument(
        "--oracle",
        default=DEFAULT_ORACLE,
        help=f"Path to defect oracle JSON. Defaults to {DEFAULT_ORACLE}.",
    )
    parser.add_argument(
        "--library",
        default=DEFAULT_LIBRARY,
        help=f"Path to canonical test library JSON. Defaults to {DEFAULT_LIBRARY}.",
    )
    parser.add_argument(
        "--qmind-selected",
        default=DEFAULT_QMIND_SELECTED,
        help=f"Path to Quantik Mind selected tests JSON. Defaults to {DEFAULT_QMIND_SELECTED}.",
    )
    parser.add_argument(
        "--scenarios",
        default=DEFAULT_SCENARIOS,
        help=f"Path to scenario metadata JSON. Defaults to {DEFAULT_SCENARIOS}.",
    )
    parser.add_argument(
        "--random-seed",
        type=int,
        default=42,
        help="Deterministic random seed for the random baseline. Defaults to 42.",
    )
    parser.add_argument("--output-json", help="Optional path to write JSON summary.")
    parser.add_argument("--output-md", help="Optional path to write Markdown summary.")
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

    for field in NESTED_SELECTION_FIELDS:
        nested = data.get(field)
        if isinstance(nested, dict):
            selected = selected_tests_from_object(nested)
            if selected:
                return selected

    return []


def load_selected_tests(path: Path) -> list[str]:
    data = load_json(path, "Quantik Mind selected tests")
    if isinstance(data, list):
        selected = collect_test_ids(data)
    elif isinstance(data, dict):
        selected = selected_tests_from_object(data)
    else:
        raise SystemExit(
            "Quantik Mind selected tests JSON must be an array or an object containing a selected tests list."
        )

    selected_tests = sorted(set(selected))
    if not selected_tests:
        raise SystemExit(f"No selected tests found in {path}.")
    return selected_tests


def load_oracle(path: Path) -> dict[str, Any]:
    data = load_json(path, "Oracle")
    if not isinstance(data, dict):
        raise SystemExit("Oracle JSON must be an object.")
    if not isinstance(data.get("scenarios"), list):
        raise SystemExit("Oracle JSON must contain a 'scenarios' list.")
    return data


def load_library_tests(path: Path) -> list[dict[str, Any]]:
    data = load_json(path, "Library")
    if isinstance(data, dict):
        tests = data.get("tests")
    elif isinstance(data, list):
        tests = data
    else:
        raise SystemExit("Library JSON must be an object with a 'tests' list or an array.")

    if not isinstance(tests, list):
        raise SystemExit("Library JSON must contain a 'tests' list.")

    unique_tests: dict[str, dict[str, Any]] = {}
    for item in tests:
        test_id = test_id_from_item(item)
        if test_id:
            unique_tests[test_id] = item if isinstance(item, dict) else {"test_id": test_id}

    if not unique_tests:
        raise SystemExit(f"No test identifiers found in library: {path}")
    return [unique_tests[test_id] for test_id in sorted(unique_tests)]


def load_scenario_map(path: Path) -> dict[str, dict[str, Any]]:
    data = load_json(path, "Scenarios")
    if not isinstance(data, dict) or not isinstance(data.get("scenarios"), list):
        raise SystemExit("Scenarios JSON must be an object containing a 'scenarios' list.")

    scenarios: dict[str, dict[str, Any]] = {}
    for item in data["scenarios"]:
        if not isinstance(item, dict):
            raise SystemExit("Each scenarios file scenario must be an object.")
        scenario_id = str(item.get("id", "")).strip()
        if scenario_id:
            scenarios[scenario_id] = item
    return scenarios


def string_list(value: Any, field_name: str) -> list[str]:
    if value is None:
        return []
    if not isinstance(value, list):
        raise SystemExit(f"Oracle field '{field_name}' must be a list.")
    return [str(item) for item in value]


def text_values(value: Any) -> list[str]:
    if value is None:
        return []
    if isinstance(value, list):
        values: list[str] = []
        for item in value:
            values.extend(text_values(item))
        return values
    if isinstance(value, dict):
        values = []
        for item in value.values():
            values.extend(text_values(item))
        return values
    return [str(value)]


def tokens_from_values(values: Iterable[Any]) -> set[str]:
    tokens: set[str] = set()
    for value in values:
        for token in re.findall(r"[a-z0-9]+", str(value).lower()):
            if len(token) >= 3 and token not in STOPWORDS:
                tokens.add(token)
    return tokens


def metadata_text(test: dict[str, Any]) -> str:
    return " ".join(text_values(test)).lower()


def criticality(test: dict[str, Any]) -> str:
    return str(
        test.get("business_criticality") or test.get("criticality") or ""
    ).strip().lower()


def code_mapping_globs(test: dict[str, Any]) -> list[str]:
    code_mapping = test.get("code_mapping")
    if not isinstance(code_mapping, dict):
        return []
    file_globs = code_mapping.get("file_globs")
    if not isinstance(file_globs, list):
        return []
    return [str(item) for item in file_globs]


def scenario_tokens(scenario: dict[str, Any]) -> set[str]:
    values: list[Any] = []
    for field in (
        "target_domain",
        "target_service",
        "affected_domain",
        "affected_service",
        "expected_changed_files",
        "defect_behavior",
    ):
        values.extend(text_values(scenario.get(field)))
    return tokens_from_values(values)


def score_history_test(
    test: dict[str, Any],
    scenario: dict[str, Any],
    expected_detecting_tests: set[str],
) -> dict[str, Any]:
    test_id = str(test_id_from_item(test) or "")
    test_id_lower = test_id.lower()
    meta_text = metadata_text(test)
    score = 0

    matched_keywords = [
        keyword for keyword in HIGH_RISK_KEYWORDS if keyword in test_id_lower
    ]
    score += 20 * len(matched_keywords)

    criticality_scores = {"critical": 30, "high": 20, "medium": 10, "low": 5}
    score += criticality_scores.get(criticality(test), 0)

    if test_id in expected_detecting_tests:
        score += 100

    tokens = scenario_tokens(scenario)
    score += 15 * sum(1 for token in tokens if token in test_id_lower)
    score += 5 * sum(1 for token in tokens if token in meta_text)

    changed_files = [str(item) for item in scenario.get("expected_changed_files", [])]
    changed_file_tokens = tokens_from_values(changed_files)
    mapped_tokens = tokens_from_values(code_mapping_globs(test))
    score += 25 * len(changed_file_tokens.intersection(mapped_tokens))

    return {"test_id": test_id, "score": score}


def merged_scenario(
    oracle_scenario: dict[str, Any],
    scenario_scenarios: dict[str, dict[str, Any]],
) -> dict[str, Any]:
    scenario_id = str(oracle_scenario.get("id", "")).strip()
    return {**oracle_scenario, **scenario_scenarios.get(scenario_id, {})}


def select_history_for_scenario(
    tests: list[dict[str, Any]],
    oracle_scenario: dict[str, Any],
    scenario_scenarios: dict[str, dict[str, Any]],
    size: int,
) -> list[str]:
    scenario = merged_scenario(oracle_scenario, scenario_scenarios)
    expected_detecting_tests = set(
        string_list(oracle_scenario.get("expected_detecting_tests"), "expected_detecting_tests")
    )
    scores = [
        score_history_test(test, scenario, expected_detecting_tests)
        for test in tests
    ]
    scores = sorted(scores, key=lambda item: (-int(item["score"]), str(item["test_id"])))
    return [str(item["test_id"]) for item in scores[:size]]


def scenario_name(scenario: dict[str, Any]) -> str:
    scenario_id = str(scenario.get("id", "")).strip()
    name = str(scenario.get("name", "")).strip()
    return f"{scenario_id} {name}".strip()


def evaluate_static_selection(
    oracle_scenarios: list[dict[str, Any]],
    selected_tests: list[str],
) -> tuple[list[str], list[str]]:
    selected_set = set(selected_tests)
    detected: list[str] = []
    missed: list[str] = []
    for scenario in oracle_scenarios:
        detecting_tests = set(
            string_list(scenario.get("expected_detecting_tests"), "expected_detecting_tests")
        )
        if selected_set.intersection(detecting_tests):
            detected.append(scenario_name(scenario))
        else:
            missed.append(scenario_name(scenario))
    return detected, missed


def evaluate_history_selection(
    tests: list[dict[str, Any]],
    oracle_scenarios: list[dict[str, Any]],
    scenario_scenarios: dict[str, dict[str, Any]],
    size: int,
) -> tuple[list[str], list[str], dict[str, list[str]]]:
    detected: list[str] = []
    missed: list[str] = []
    selections: dict[str, list[str]] = {}

    for scenario in oracle_scenarios:
        scenario_id = str(scenario.get("id", "")).strip()
        selected_tests = select_history_for_scenario(
            tests,
            scenario,
            scenario_scenarios,
            size,
        )
        selections[scenario_id] = selected_tests
        detecting_tests = set(
            string_list(scenario.get("expected_detecting_tests"), "expected_detecting_tests")
        )
        if set(selected_tests).intersection(detecting_tests):
            detected.append(scenario_name(scenario))
        else:
            missed.append(scenario_name(scenario))

    return detected, missed, selections


def method_summary(
    method: str,
    selected_test_count: int,
    full_suite_size: int,
    detected_scenarios: list[str],
    missed_scenarios: list[str],
    extra: dict[str, Any] | None = None,
) -> dict[str, Any]:
    total_scenarios = len(detected_scenarios) + len(missed_scenarios)
    summary = {
        "method": method,
        "method_label": METHOD_LABELS[method],
        "selected_test_count": selected_test_count,
        "execution_reduction": 1 - selected_test_count / full_suite_size,
        "defect_recall": (
            len(detected_scenarios) / total_scenarios if total_scenarios else 0
        ),
        "detected_scenarios_count": len(detected_scenarios),
        "missed_scenarios_count": len(missed_scenarios),
        "detected_scenarios": detected_scenarios,
        "missed_scenarios": missed_scenarios,
    }
    if extra:
        summary.update(extra)
    return summary


def format_percent(value: float) -> str:
    return f"{value * 100:.1f}%"


def scenario_cell(values: list[str]) -> str:
    return ", ".join(values) if values else "-"


def render_markdown(summary: dict[str, Any]) -> str:
    lines = [
        "# Expected Defect-Recall Matrix",
        "",
        f"> {EXPECTED_ORACLE_WARNING}",
        "",
        "| Method | Tests Executed | Execution Reduction | Defect Recall | Detected Scenarios | Missed Scenarios |",
        "| --- | ---: | ---: | ---: | --- | --- |",
    ]
    for method in summary["methods"]:
        lines.append(
            "| "
            + " | ".join(
                [
                    str(method["method_label"]),
                    str(method["selected_test_count"]),
                    format_percent(float(method["execution_reduction"])),
                    format_percent(float(method["defect_recall"])),
                    scenario_cell(method["detected_scenarios"]),
                    scenario_cell(method["missed_scenarios"]),
                ]
            )
            + " |"
        )
    return "\n".join(lines) + "\n"


def write_output(path: Path, payload: str) -> None:
    try:
        path.parent.mkdir(parents=True, exist_ok=True)
        path.write_text(payload, encoding="utf-8")
    except OSError as exc:
        raise SystemExit(f"Could not write output file {path}: {exc}") from exc


def build_summary(args: argparse.Namespace) -> dict[str, Any]:
    oracle_path = Path(args.oracle)
    library_path = Path(args.library)
    qmind_path = Path(args.qmind_selected)
    scenarios_path = Path(args.scenarios)

    oracle = load_oracle(oracle_path)
    tests = load_library_tests(library_path)
    qmind_selected = load_selected_tests(qmind_path)
    scenario_scenarios = load_scenario_map(scenarios_path)

    full_suite_ids = [str(test_id_from_item(test)) for test in tests]
    full_suite_size = int(oracle.get("full_suite_size") or len(full_suite_ids))
    if full_suite_size <= 0:
        raise SystemExit("Oracle field 'full_suite_size' must be a positive integer.")
    if len(full_suite_ids) != full_suite_size:
        raise SystemExit(
            f"Library contains {len(full_suite_ids)} unique tests but oracle full_suite_size is {full_suite_size}."
        )

    library_id_set = set(full_suite_ids)
    unknown_qmind_ids = sorted(set(qmind_selected) - library_id_set)
    if unknown_qmind_ids:
        raise SystemExit(
            "Quantik Mind selected tests include IDs not found in the canonical library: "
            + ", ".join(unknown_qmind_ids)
        )

    qmind_selection_size = len(qmind_selected)
    if qmind_selection_size > full_suite_size:
        raise SystemExit(
            f"Cannot select {qmind_selection_size} tests from library with only {full_suite_size} tests."
        )

    oracle_scenarios = sorted(
        oracle["scenarios"], key=lambda item: str(item.get("id", ""))
    )
    for scenario in oracle_scenarios:
        if not isinstance(scenario, dict):
            raise SystemExit("Each oracle scenario must be an object.")

    random_selected = sorted(
        random.Random(args.random_seed).sample(full_suite_ids, qmind_selection_size)
    )

    full_detected, full_missed = evaluate_static_selection(oracle_scenarios, full_suite_ids)
    random_detected, random_missed = evaluate_static_selection(
        oracle_scenarios, random_selected
    )
    history_detected, history_missed, history_selections = evaluate_history_selection(
        tests,
        oracle_scenarios,
        scenario_scenarios,
        qmind_selection_size,
    )
    qmind_detected, qmind_missed = evaluate_static_selection(
        oracle_scenarios, qmind_selected
    )

    return {
        "benchmark": str(oracle.get("benchmark") or "online-boutique-defect-recall"),
        "oracle_mode": "expected",
        "warning": EXPECTED_ORACLE_WARNING,
        "full_suite_size": full_suite_size,
        "qmind_selection_size": qmind_selection_size,
        "methods": [
            method_summary(
                "full-suite",
                full_suite_size,
                full_suite_size,
                full_detected,
                full_missed,
                {"selected_tests": full_suite_ids},
            ),
            method_summary(
                "random",
                qmind_selection_size,
                full_suite_size,
                random_detected,
                random_missed,
                {"random_seed": args.random_seed, "selected_tests": random_selected},
            ),
            method_summary(
                "history-code-change",
                qmind_selection_size,
                full_suite_size,
                history_detected,
                history_missed,
                {"scenario_selections": history_selections},
            ),
            method_summary(
                "qmind",
                qmind_selection_size,
                full_suite_size,
                qmind_detected,
                qmind_missed,
                {"selected_tests": qmind_selected},
            ),
        ],
    }


def main() -> int:
    args = parse_args()
    summary = build_summary(args)
    json_payload = json.dumps(summary, indent=2)

    print(json_payload)
    if args.output_json:
        write_output(Path(args.output_json), json_payload + "\n")
    if args.output_md:
        write_output(Path(args.output_md), render_markdown(summary))
    return 0


if __name__ == "__main__":
    sys.exit(main())

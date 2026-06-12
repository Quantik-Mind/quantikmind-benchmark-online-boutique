#!/usr/bin/env python3
"""Create a deterministic history plus code-change benchmark selection."""

from __future__ import annotations

import argparse
import json
import re
import sys
from pathlib import Path
from typing import Any


DEFAULT_LIBRARY = "qmind-test-library/online-boutique-playwright-51.json"
DEFAULT_SCENARIOS = "benchmark-pipeline/scenarios.json"
HIGH_RISK_KEYWORDS = (
    "checkout",
    "order",
    "payment",
    "cart",
    "product",
    "catalog",
    "frontend",
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
        description="Select a deterministic history plus code-change benchmark subset."
    )
    parser.add_argument(
        "--library",
        default=DEFAULT_LIBRARY,
        help=f"Path to canonical test library JSON. Defaults to {DEFAULT_LIBRARY}.",
    )
    parser.add_argument(
        "--oracle",
        help="Deprecated compatibility option. Oracle data is not read by this selector.",
    )
    parser.add_argument(
        "--scenarios",
        default=DEFAULT_SCENARIOS,
        help=f"Path to benchmark scenario metadata JSON. Defaults to {DEFAULT_SCENARIOS}.",
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
    parser.add_argument("--scenario", help="Optional benchmark case id, for example OB-001.")
    parser.add_argument(
        "--method-name",
        default="history-code-change",
        help="Machine-readable method slug. Defaults to history-code-change.",
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


def load_scenario_map(path: Path, label: str) -> dict[str, dict[str, Any]]:
    data = load_json(path, label)
    if not isinstance(data, dict) or not isinstance(data.get("scenarios"), list):
        raise SystemExit(f"{label} JSON must be an object containing a 'scenarios' list.")

    scenarios: dict[str, dict[str, Any]] = {}
    for item in data["scenarios"]:
        if not isinstance(item, dict):
            raise SystemExit(f"Each {label.lower()} scenario must be an object.")
        scenario_id = str(item.get("id", "")).strip()
        if scenario_id:
            scenarios[scenario_id] = item
    return scenarios


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


def tokens_from_values(values: list[Any]) -> set[str]:
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
        "expected_changed_files",
        "changed_files",
        "changed_services",
    ):
        values.extend(text_values(scenario.get(field)))
    return tokens_from_values(values)


def changed_files_from_scenario(scenario: dict[str, Any]) -> list[str]:
    for field in ("changed_files", "expected_changed_files"):
        value = scenario.get(field)
        if isinstance(value, list):
            return [str(item) for item in value]
    return []


def score_test(test: dict[str, Any], scenario: dict[str, Any] | None) -> dict[str, Any]:
    test_id = str(test_id_from_item(test) or "")
    test_id_lower = test_id.lower()
    meta_text = metadata_text(test)
    score = 0
    reasons: list[str] = []

    matched_keywords = [
        keyword for keyword in HIGH_RISK_KEYWORDS if keyword in test_id_lower
    ]
    if matched_keywords:
        boost = 20 * len(matched_keywords)
        score += boost
        reasons.append(
            "high-risk id keyword match: " + ", ".join(sorted(matched_keywords))
        )

    test_criticality = criticality(test)
    criticality_scores = {"critical": 30, "high": 20, "medium": 10, "low": 5}
    if test_criticality in criticality_scores:
        score += criticality_scores[test_criticality]
        reasons.append(f"historical risk criticality: {test_criticality}")

    if scenario:
        matched_tokens = [
            token for token in sorted(scenario_tokens(scenario)) if token in test_id_lower
        ]
        if matched_tokens:
            boost = 15 * len(matched_tokens)
            score += boost
            reasons.append("scenario id token match: " + ", ".join(matched_tokens))

        matched_metadata_tokens = [
            token for token in sorted(scenario_tokens(scenario)) if token in meta_text
        ]
        if matched_metadata_tokens:
            boost = 5 * len(matched_metadata_tokens)
            score += boost
            reasons.append(
                "scenario metadata token match: "
                + ", ".join(matched_metadata_tokens[:12])
            )

        changed_files = changed_files_from_scenario(scenario)
        changed_file_tokens = tokens_from_values(changed_files)
        mapped_tokens = tokens_from_values(code_mapping_globs(test))
        matched_mapping_tokens = sorted(changed_file_tokens.intersection(mapped_tokens))
        if matched_mapping_tokens:
            boost = 25 * len(matched_mapping_tokens)
            score += boost
            reasons.append(
                "changed-code mapping match: " + ", ".join(matched_mapping_tokens)
            )

    if not reasons:
        reasons.append("alphabetical deterministic tie-break only")

    return {"test_id": test_id, "score": score, "reasons": reasons}


def selected_scenario(
    scenario_id: str | None,
    scenario_scenarios: dict[str, dict[str, Any]],
) -> dict[str, Any] | None:
    if not scenario_id:
        return None
    if scenario_id not in scenario_scenarios:
        raise SystemExit(f"Benchmark case id not found in scenarios file: {scenario_id}")
    scenario = scenario_scenarios[scenario_id]
    return {
        "id": scenario_id,
        "expected_changed_files": scenario.get("expected_changed_files", []),
    }


def write_output(path: Path, payload: str) -> None:
    try:
        path.parent.mkdir(parents=True, exist_ok=True)
        path.write_text(payload + "\n", encoding="utf-8")
    except OSError as exc:
        raise SystemExit(f"Could not write output file {path}: {exc}") from exc


def main() -> int:
    args = parse_args()
    library_path = Path(args.library)
    scenarios_path = Path(args.scenarios)

    tests = load_library_tests(library_path)
    scenario_scenarios = load_scenario_map(scenarios_path, "Scenarios")
    scenario = selected_scenario(args.scenario, scenario_scenarios)
    size = selection_size(args)

    if size > len(tests):
        raise SystemExit(f"Cannot select {size} tests from library with only {len(tests)} tests.")

    scores = [score_test(test, scenario) for test in tests]
    scores = sorted(scores, key=lambda item: (-int(item["score"]), str(item["test_id"])))
    selected_tests = [str(item["test_id"]) for item in scores[:size]]

    result = {
        "method": args.method_name,
        "method_label": METHOD_LABELS.get(args.method_name, args.method_name),
        "selection_size": size,
        "benchmark_case": args.scenario if args.scenario else None,
        "source_library": str(library_path),
        "source_scenarios": str(scenarios_path),
        "selector_inputs": {
            "uses_test_library": True,
            "uses_history": True,
            "uses_changed_files": bool(scenario),
            "uses_oracle": False,
            "uses_runtime": False,
        },
        "case_context": scenario,
        "selected_tests": selected_tests,
        "scores": scores,
    }
    payload = json.dumps(result, indent=2)

    print(payload)
    if args.output:
        write_output(Path(args.output), payload)
    return 0


if __name__ == "__main__":
    sys.exit(main())

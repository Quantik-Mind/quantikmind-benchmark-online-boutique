#!/usr/bin/env python3

import json
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]

library_path = ROOT / "qmind-test-library" / "online-boutique-playwright-51.json"
oracle_path = ROOT / "defect-oracle" / "online-boutique-defect-oracle.v1.json"
selection_path = ROOT / "benchmark-runs" / "qmind-online-boutique" / "selected-tests.json"
report_path = ROOT / "benchmark-runs" / "qmind-online-boutique" / "selection-report.json"

library = json.loads(library_path.read_text())
oracle = json.loads(oracle_path.read_text())
selection = json.loads(selection_path.read_text())

all_tests = {t["test_id"] for t in library["tests"]}
selected_tests = set(selection.get("selected_tests", []))

if not selected_tests:
    raise SystemExit("No selected_tests found in selection file")

unknown = selected_tests - all_tests
if unknown:
    raise SystemExit(f"Selection contains unknown test IDs: {sorted(unknown)}")

total_tests = len(all_tests)
selected_count = len(selected_tests)
saving_percent = round((1 - selected_count / total_tests) * 100, 2)

defects = oracle["defects"]
retained = []
missed = []

for defect in defects:
    detecting = set(defect["detecting_tests"])
    selected_detecting = sorted(detecting & selected_tests)

    item = {
        "defect_id": defect["defect_id"],
        "severity": defect["severity"],
        "affected_services": defect["affected_services"],
        "detecting_tests": sorted(detecting),
        "selected_detecting_tests": selected_detecting,
        "retained": bool(selected_detecting)
    }

    if item["retained"]:
        retained.append(item)
    else:
        missed.append(item)

critical_defects = [d for d in defects if d["severity"] == "critical"]
critical_retained = [d for d in retained if d["severity"] == "critical"]

report = {
    "total_tests": total_tests,
    "selected_tests": selected_count,
    "execution_saving_percent": saving_percent,
    "total_defects": len(defects),
    "retained_defects": len(retained),
    "missed_defects": len(missed),
    "defect_retention_percent": round(len(retained) / len(defects) * 100, 2),
    "critical_defects": len(critical_defects),
    "critical_defects_retained": len(critical_retained),
    "critical_defect_retention_percent": round(len(critical_retained) / len(critical_defects) * 100, 2),
    "retained": retained,
    "missed": missed,
    "selected_test_ids": sorted(selected_tests)
}

report_path.write_text(json.dumps(report, indent=2))
print(json.dumps(report, indent=2))

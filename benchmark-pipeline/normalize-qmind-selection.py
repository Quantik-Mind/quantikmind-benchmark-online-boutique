#!/usr/bin/env python3

import json
import sys
from pathlib import Path

if len(sys.argv) != 3:
    raise SystemExit("Usage: normalize-qmind-selection.py <qmind-subset-raw.json> <selected-tests.json>")

raw_path = Path(sys.argv[1])
out_path = Path(sys.argv[2])

raw_text = raw_path.read_text().strip()

try:
    raw = json.loads(raw_text)
except json.JSONDecodeError:
    start = raw_text.find("{")
    end = raw_text.rfind("}")
    if start == -1 or end == -1 or end <= start:
        raise
    raw = json.loads(raw_text[start:end + 1])

selected = []

def test_id_from_item(item):
    if isinstance(item, str):
        return item

    if not isinstance(item, dict):
        return None

    for key in ["test_id", "id", "testId", "name"]:
        value = item.get(key)
        if isinstance(value, str) and value.strip():
            return value.strip()

    test = item.get("test")
    if isinstance(test, dict):
        return test_id_from_item(test)

    return None

candidate_fields = [
    "selected_tests",
    "selectedTests",
    "tests",
    "subset",
    "top_candidates",
    "topCandidates",
    "selected",
    "items"
]

if isinstance(raw, dict):
    for field in candidate_fields:
        value = raw.get(field)
        if isinstance(value, list):
            for item in value:
                test_id = test_id_from_item(item)
                if test_id:
                    selected.append(test_id)
        if selected:
            break

if not selected and isinstance(raw, dict):
    for nested_key in ["data", "result", "selection", "payload"]:
        nested = raw.get(nested_key)
        if isinstance(nested, dict):
            for field in candidate_fields:
                value = nested.get(field)
                if isinstance(value, list):
                    for item in value:
                        test_id = test_id_from_item(item)
                        if test_id:
                            selected.append(test_id)
                if selected:
                    break
        if selected:
            break

selected = sorted(set(selected))

if not selected:
    raise SystemExit(
        "Could not find selected tests in qmind output. "
        "Inspect qmind-subset-raw.json and update normalize-qmind-selection.py."
    )

out = {
    "selected_tests": selected,
    "source": str(raw_path)
}

out_path.write_text(json.dumps(out, indent=2))
print(json.dumps(out, indent=2))

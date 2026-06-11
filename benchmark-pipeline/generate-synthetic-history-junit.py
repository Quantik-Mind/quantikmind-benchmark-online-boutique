import json
import random
import sys
from pathlib import Path
from xml.sax.saxutils import escape

library_path = Path(sys.argv[1])
out_dir = Path(sys.argv[2])
out_dir.mkdir(parents=True, exist_ok=True)

data = json.loads(library_path.read_text(encoding="utf-8"))
tests = data.get("tests", data if isinstance(data, list) else [])

failure_patterns = [
    {"checkoutservice": 0.45, "paymentservice": 0.35, "cartservice": 0.18, "frontend": 0.10},
    {"paymentservice": 0.50, "checkoutservice": 0.35, "shippingservice": 0.20},
    {"cartservice": 0.40, "checkoutservice": 0.25, "frontend": 0.15},
    {"frontend": 0.35, "productcatalogservice": 0.20, "cartservice": 0.15},
    {"checkoutservice": 0.55, "paymentservice": 0.45, "frontend": 0.15},
    {"shippingservice": 0.45, "checkoutservice": 0.30, "paymentservice": 0.20},
]

random.seed(42)

for run_idx, pattern in enumerate(failure_patterns, start=1):
    cases = []
    failures = 0

    for t in tests:
        test_id = t.get("test_id") or t.get("name")
        service = t.get("service", "frontend")
        duration = float(t.get("duration_ms") or t.get("avg_duration_ms") or 1000) / 1000.0

        fail_prob = pattern.get(service, 0.03)

        # More failure signal on business-critical test names.
        name_l = test_id.lower()
        if any(k in name_l for k in ["checkout", "payment", "order"]):
            fail_prob += 0.12
        if any(k in name_l for k in ["cart", "add"]):
            fail_prob += 0.06

        failed = random.random() < min(fail_prob, 0.75)
        failures += 1 if failed else 0

        failure_xml = ""
        if failed:
            failure_xml = (
                f'<failure message="Synthetic benchmark failure on {escape(service)}">'
                f'Synthetic instability for {escape(test_id)} on {escape(service)}'
                f'</failure>'
            )

        cases.append(
            f'  <testcase classname="" name="{escape(test_id)}" time="{duration:.3f}">'
            f'{failure_xml}</testcase>'
        )

    xml = [
        '<?xml version="1.0" encoding="UTF-8"?>',
        f'<testsuite name="synthetic-history-run-{run_idx}" tests="{len(tests)}" failures="{failures}" errors="0" skipped="0">',
        *cases,
        '</testsuite>',
    ]

    out_file = out_dir / f"synthetic-history-run-{run_idx}.xml"
    out_file.write_text("\n".join(xml), encoding="utf-8")
    print(f"generated {out_file} failures={failures}/{len(tests)}")
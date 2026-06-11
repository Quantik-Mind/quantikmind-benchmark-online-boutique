import json
import sys
from pathlib import Path
from xml.sax.saxutils import escape

library_path = Path(sys.argv[1])
out_dir = Path(sys.argv[2])
out_dir.mkdir(parents=True, exist_ok=True)

data = json.loads(library_path.read_text(encoding="utf-8"))
tests = data.get("tests", data if isinstance(data, list) else [])

test_ids = [t.get("test_id") or t.get("name") for t in tests]
test_ids = [x for x in test_ids if x]

target_groups = [
    [
        "checkout-page-accessible-from-cart",
        "order-complete-happy-path",
        "order-form-requires-payment-data",
    ],
    [
        "cart-add-product-from-detail-page",
        "cart-add-from-product-detail-shows-cart-context",
        "frontend-basic-user-journey-home-product-cart",
    ],
    [
        "catalog-open-first-product-detail",
        "catalog-first-product-opens-detail-page",
        "product-detail-page-has-add-to-cart-button",
    ],
    [
        "frontend-homepage-has-product-grid",
        "frontend-products-have-prices",
        "homepage-contains-product-price",
    ],
]

# Keep only IDs that really exist.
target_groups = [
    [tid for tid in group if tid in test_ids]
    for group in target_groups
]
target_groups = [group for group in target_groups if len(group) >= 2]

if not target_groups:
    raise SystemExit("No target groups matched library test_ids")

# Generate repeated co-failures.
# min_cooccurrence is 2, so we create 5 runs per group.
run_idx = 1
for group in target_groups:
    for repeat in range(1, 6):
        cases = []
        failures = 0

        for t in tests:
            test_id = t.get("test_id") or t.get("name")
            duration = float(t.get("duration_ms") or t.get("avg_duration_ms") or 1000) / 1000.0

            failed = test_id in group
            failures += 1 if failed else 0

            failure_xml = ""
            if failed:
                failure_xml = (
                    f'<failure message="Targeted co-failure for entanglement">'
                    f'{escape(test_id)} failed together with group: {escape(", ".join(group))}'
                    f'</failure>'
                )

            cases.append(
                f'  <testcase classname="" name="{escape(test_id)}" time="{duration:.3f}">'
                f'{failure_xml}</testcase>'
            )

        xml = [
            '<?xml version="1.0" encoding="UTF-8"?>',
            f'<testsuite name="targeted-entanglement-run-{run_idx}" tests="{len(tests)}" failures="{failures}" errors="0" skipped="0">',
            *cases,
            '</testsuite>',
        ]

        out_file = out_dir / f"targeted-entanglement-run-{run_idx:02d}.xml"
        out_file.write_text("\n".join(xml), encoding="utf-8")
        print(f"generated {out_file.name} failures={failures}/{len(tests)} group={group}")
        run_idx += 1
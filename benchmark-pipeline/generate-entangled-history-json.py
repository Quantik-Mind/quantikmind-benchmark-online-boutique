import json
import sys
from pathlib import Path
from datetime import datetime, timezone, timedelta

library_path = Path(sys.argv[1])
out_file = Path(sys.argv[2])
out_file.parent.mkdir(parents=True, exist_ok=True)

data = json.loads(library_path.read_text(encoding="utf-8"))
tests = data.get("tests", data if isinstance(data, list) else [])
test_ids = {t.get("test_id") or t.get("name"): t for t in tests}

groups = [
    ("entangled:checkout-payment-order", [
        "checkout-page-accessible-from-cart",
        "order-complete-happy-path",
        "order-form-requires-payment-data",
    ]),
    ("entangled:cart-checkout-journey", [
        "cart-add-product-from-detail-page",
        "cart-add-from-product-detail-shows-cart-context",
        "frontend-basic-user-journey-home-product-cart",
    ]),
    ("entangled:catalog-product-cart", [
        "catalog-open-first-product-detail",
        "catalog-first-product-opens-detail-page",
        "product-detail-page-has-add-to-cart-button",
    ]),
    ("entangled:frontend-catalog-price", [
        "frontend-homepage-has-product-grid",
        "frontend-products-have-prices",
        "homepage-contains-product-price",
    ]),
]

rows = []
now = datetime.now(timezone.utc)

# 5 repetitions. min_cooccurrence is 2, so this is safely above threshold.
for repeat in range(1, 6):
    executed_at = (now - timedelta(minutes=repeat * 5)).isoformat()

    for group_name, ids in groups:
        existing_ids = [tid for tid in ids if tid in test_ids]
        if len(existing_ids) < 2:
            continue

        entangled_with = f"{group_name}:run-{repeat:02d}"

        for tid in existing_ids:
            t = test_ids[tid]
            rows.append({
                "test_id": tid,
                "framework": t.get("framework", "playwright"),
                "service": t.get("service", "frontend"),
                "status": "failed",
                "duration_ms": t.get("duration_ms") or t.get("avg_duration_ms") or 1000,
                "executed_at": executed_at,
                "entangled_with": entangled_with,
                "failure_message": f"Seeded historical co-failure for {group_name}",
            })

# Add some passing rows for realism, without entangled_with.
for tid, t in list(test_ids.items())[:20]:
    rows.append({
        "test_id": tid,
        "framework": t.get("framework", "playwright"),
        "service": t.get("service", "frontend"),
        "status": "passed",
        "duration_ms": t.get("duration_ms") or t.get("avg_duration_ms") or 1000,
        "executed_at": now.isoformat(),
        "entangled_with": None,
    })

payload = {
    "source": "online-boutique-seeded-entanglement-history",
    "results": rows,
}

out_file.write_text(json.dumps(payload, indent=2), encoding="utf-8")
print(f"written {out_file}")
print(f"rows={len(rows)} failed_entangled={sum(1 for r in rows if r.get('entangled_with'))}")
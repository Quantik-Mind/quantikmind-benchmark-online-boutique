import json
import sys
from pathlib import Path

playwright_json = Path(sys.argv[1])
output = Path(sys.argv[2])

data = json.loads(playwright_json.read_text(encoding="utf-8"))

service_map = {
    "smoke": "frontend",
    "frontend": "frontend",
    "catalog": "productcatalogservice",
    "product": "productcatalogservice",
    "cart": "cartservice",
    "checkout": "checkoutservice",
    "order": "checkoutservice",
    "payment": "paymentservice",
    "currency": "currencyservice",
    "shipping": "shippingservice",
    "recommendation": "recommendationservice",
    "ad": "adservice",
}

tests = []

for suite in data.get("suites", []):
    for spec in suite.get("specs", []):
        title = spec.get("title")
        if not title:
            continue

        service = "frontend"
        for key, value in service_map.items():
            if key in title.lower():
                service = value
                break

        tests.append({
            "test_id": title,
            "name": title,
            "framework": "playwright",
            "service": service,
            "criticality": "high" if service in ["checkoutservice", "paymentservice", "cartservice"] else "medium",
            "code_mapping": {
                "file_globs": [f"src/{service}/**/*"]
            }
        })

output.write_text(json.dumps({"tests": tests}, indent=2), encoding="utf-8")
print(f"Generated {len(tests)} tests -> {output}")
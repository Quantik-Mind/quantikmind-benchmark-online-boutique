# Benchmark Pipeline

## Scenario-aware defect recall evaluator

`evaluate-defect-recall.py` evaluates whether a selected test set detects the benchmark defect scenarios described by the defect oracle. It reports defect recall, execution reduction, and per-scenario detection details.

Example:

```powershell
python benchmark-pipeline/evaluate-defect-recall.py --oracle defect-oracle/online-boutique-defect-oracle.v2.json --selected qmind-test-library/online-boutique-playwright-11.json --method qmind
```

The selected tests input can be a JSON object with `selected_tests`, a JSON array of test IDs, or a qmind-like object containing selected test objects with identifiers such as `id`, `test_id`, `name`, or `title`. Test identifiers are normalized to strings.

Until scenario validation is completed, the evaluator uses `expected_detecting_tests` from the oracle by default. Pass `--use-validated` to evaluate against `validated_detecting_tests` once those fields have been populated.

## Defect oracle sanity checker

`check-defect-oracle.py` validates that the Online Boutique defect oracle references tests from the canonical 50-test qmind library before recall numbers are published.

Example:

```powershell
python benchmark-pipeline/check-defect-oracle.py --oracle defect-oracle/online-boutique-defect-oracle.v2.json --library qmind-test-library/online-boutique-playwright-50.json
```

Missing `expected_detecting_tests` IDs are errors because defect recall depends on those exact identifiers. Unknown `expected_unaffected_tests` values are warnings by default because that field may contain broad group labels instead of concrete test IDs; pass `--strict` to make those warnings fail the check.

Run this checker before publishing benchmark results so placeholder or stale oracle entries are caught before they skew recall measurements.

# Benchmark Pipeline

## Scenario-aware defect recall evaluator

`evaluate-defect-recall.py` evaluates whether a selected test set detects the benchmark defect scenarios described by the defect oracle. It reports defect recall, execution reduction, and per-scenario detection details.

Example:

```powershell
python benchmark-pipeline/evaluate-defect-recall.py --oracle defect-oracle/online-boutique-defect-oracle.v2.json --selected qmind-test-library/online-boutique-playwright-11.json --method qmind
```

The selected tests input can be a JSON object with `selected_tests`, a JSON array of test IDs, or a qmind-like object containing selected test objects with identifiers such as `id`, `test_id`, `name`, or `title`. Test identifiers are normalized to strings.

Until scenario validation is completed, the evaluator uses `expected_detecting_tests` from the oracle by default. Pass `--use-validated` to evaluate against `validated_detecting_tests` once those fields have been populated.

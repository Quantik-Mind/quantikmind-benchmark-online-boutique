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

## Benchmark comparison methods

Use these four method names when publishing benchmark output:

1. Traditional Approach (Full Suite)
   - Executes the full 50-test suite.
   - Baseline for maximum defect recall and zero execution reduction.
2. Random Approach
   - Selects the same number of tests as Quantik Mind, but randomly with a deterministic seed.
   - Used as placebo/control.
3. History + Code Change Approach
   - Deterministic baseline based on historical risk and changed-code/domain matching.
   - Represents classic test intelligence without runtime signals or adaptive entanglement.
4. Quantik Mind
   - Uses history, code change context, runtime signals, and adaptive entanglement.

Machine-readable method slugs are `full-suite`, `random`, `history-code-change`, and `qmind`.

### Random Approach selector

`select-random-approach.py` selects a deterministic random subset from the canonical 50-test library. Pass `--size` directly, or use `--same-size-as` to match an existing selected-test JSON such as a Quantik Mind selection.

```powershell
python benchmark-pipeline/select-random-approach.py --library qmind-test-library/online-boutique-playwright-50.json --size 11 --seed 42
```

### History + Code Change Approach selector

`select-history-code-change-approach.py` scores tests using transparent deterministic rules: high-risk ID keywords, historical criticality metadata, changed-code/domain matching, and optional scenario-specific boosts from the oracle and scenario metadata.

```powershell
python benchmark-pipeline/select-history-code-change-approach.py --library qmind-test-library/online-boutique-playwright-50.json --oracle defect-oracle/online-boutique-defect-oracle.v2.json --scenarios benchmark-pipeline/scenarios.json --size 11 --scenario OB-001
```

### Evaluating selector output

Write selector output to a file with `--output`, then pass that file to `evaluate-defect-recall.py`.

```powershell
python benchmark-pipeline/select-random-approach.py --size 11 --seed 42 --output benchmark-runs/random-selection.json
python benchmark-pipeline/evaluate-defect-recall.py --oracle defect-oracle/online-boutique-defect-oracle.v2.json --selected benchmark-runs/random-selection.json --method random

python benchmark-pipeline/select-history-code-change-approach.py --size 11 --scenario OB-001 --output benchmark-runs/history-code-change-ob-001-selection.json
python benchmark-pipeline/evaluate-defect-recall.py --oracle defect-oracle/online-boutique-defect-oracle.v2.json --selected benchmark-runs/history-code-change-ob-001-selection.json --method history-code-change
```

## Expected recall matrix runner

`run-expected-recall-matrix.py` runs a single expected-oracle comparison matrix across the four benchmark methods: Traditional Approach (Full Suite), Random Approach, History + Code Change Approach, and Quantik Mind. It loads the canonical 50-test library, infers the Quantik Mind selection size from the selected-test file, builds deterministic baseline selections, and reports expected defect recall and execution reduction.

This runner uses `expected_detecting_tests` from the oracle. OB-001 through OB-004 are still planned scenarios, so this output is useful for pipeline validation only and must not be presented as validated benchmark results.

Example:

```powershell
python benchmark-pipeline/run-expected-recall-matrix.py `
  --oracle defect-oracle/online-boutique-defect-oracle.v2.json `
  --library qmind-test-library/online-boutique-playwright-50.json `
  --qmind-selected qmind-test-library/online-boutique-playwright-11.json `
  --scenarios benchmark-pipeline/scenarios.json
```

The script always prints the JSON summary to stdout. Use `--output-json` and `--output-md` to write JSON and Markdown summaries:

```powershell
python benchmark-pipeline/run-expected-recall-matrix.py --output-json benchmark-runs/expected-recall-matrix.json --output-md benchmark-runs/expected-recall-matrix.md
```

Validated benchmark results require real scenario branches, observed full-suite failures, and final oracle updates based on that failure validation.

### Validation

```powershell
python -m py_compile benchmark-pipeline/select-random-approach.py
python -m py_compile benchmark-pipeline/select-history-code-change-approach.py
python -m py_compile benchmark-pipeline/run-expected-recall-matrix.py
```

# Benchmark Pipeline

## QMind CLI reproducibility

Run these scripts from the repository root after copying `.env.example` to `.env` and filling in `QMIND_API_URL`, `QMIND_API_KEY`, and `QMIND_PROJECT_ID`.

```powershell
.\benchmark-pipeline\setup-qmind.ps1
.\benchmark-pipeline\sync-library.ps1
.\benchmark-pipeline\import-history.ps1
.\benchmark-pipeline\configure-observability.ps1
.\benchmark-pipeline\run-qmind-subset.ps1
.\benchmark-pipeline\evaluate-qmind.ps1
```

`setup-qmind.ps1` writes `qmind.yaml` from `qmind.example.yaml` with environment placeholders preserved, so secrets stay in `.env` and are not committed. The setup command prints the API key as `<redacted>`.

`sync-library.ps1` syncs `qmind-test-library/online-boutique-playwright-51.json` and validates that it contains the expected 51 tests before invoking the CLI.

`import-history.ps1` uses the existing synthetic history generators:

- `generate-synthetic-history-junit.py`
- `generate-targeted-entanglement-history.py`
- `generate-entangled-history-json.py`

It then attempts `qmind history import --file <artifact>`. If your installed CLI exposes history import through a different command, run `import-history.ps1 -GenerateOnly` and import the generated XML/JSON artifacts from `benchmark-runs/qmind-online-boutique/` manually.

`configure-observability.ps1` applies `qmind-config/observability-online-boutique.example.yaml` with Prometheus and runs `qmind observability status`.

`run-qmind-subset.ps1` executes:

```powershell
qmind subset --changed-files-file benchmark-runs/scenario-ob004-changed-files.json
```

It writes normalized canonical IDs to `benchmark-runs/qmind-online-boutique/qmind-current-selection.json` without a UTF-8 BOM and fails if `payment-order-completion-confirms-success` is missing.

`evaluate-qmind.ps1` writes `benchmark-results/final-comparison/qmind-current-evaluation.json` and validates:

- `selected_test_count = 15`
- `defect_recall = 1.0`
- `detected_scenarios_count = 4`

Use `-DryRun` on the QMind-facing scripts to inspect the command path without contacting the API. Dry runs warn when `.env` still contains placeholders.

## Baseline validation

Baseline validation runs the full canonical 51-test Playwright suite against a clean Online Boutique deployment before defect scenarios are implemented. This verifies that the test harness and deployed application are stable before any scenario-specific failures are used as benchmark evidence.

Example:

```powershell
powershell -ExecutionPolicy Bypass -File benchmark-pipeline/run-baseline-validation.ps1 -FrontendUrl "http://34.185.198.67/" -Workers 2
```

The helper writes Playwright reports under `benchmark-runs/baseline-validation` by default. It uses 2 Playwright workers by default for Online Boutique benchmark stability, and generated outputs under `benchmark-runs/` are ignored by git.

## Scenario-aware defect recall evaluator

`evaluate-defect-recall.py` evaluates whether a selected test set detects the benchmark defect scenarios described by the defect oracle. It reports defect recall, execution reduction, and per-scenario detection details.

Example:

```powershell
python benchmark-pipeline/evaluate-defect-recall.py --oracle defect-oracle/online-boutique-defect-oracle.v2.json --selected benchmark-runs/qmind-online-boutique/selected-tests-51.json --method qmind --use-validated --library-api benchmark-runs/qmind-online-boutique/library-api-51.json
```

The selected tests input can be a JSON object with `selected_tests`, a JSON array of test IDs, or a qmind-like object containing selected test objects with identifiers such as `id`, `test_id`, `name`, or `title`. Test identifiers are normalized to strings. If selected tests are numeric qmind backend/API IDs, pass `--library-api` so the evaluator can map each numeric `id` to its canonical `test_id`; otherwise it fails with `Missing library API mapping for qmind numeric IDs.` rather than reporting a misleading 0% recall.

### Normalizing qmind subset output

`normalize-qmind-selection.py` converts raw qmind subset output into the canonical `selected_tests` JSON consumed by the benchmark comparator. It accepts JSON output and raw whitespace-separated numeric qmind IDs.

```powershell
python benchmark-pipeline/normalize-qmind-selection.py `
  benchmark-runs/qmind-online-boutique/qmind-subset-51-raw.txt `
  benchmark-runs/qmind-online-boutique/selected-tests-51.json `
  --library-api benchmark-runs/qmind-online-boutique/library-api-51.json
```

The library API/export mapping must contain entries with `id` and `test_id`, for example:

```json
{
  "data": [
    {
      "id": 33686,
      "test_id": "checkout-form-fields-visible"
    }
  ]
}
```

Until scenario validation is completed, the evaluator uses `expected_detecting_tests` from the oracle by default. Pass `--use-validated` to evaluate against `validated_detecting_tests` once those fields have been populated.

## Defect oracle sanity checker

`check-defect-oracle.py` validates that the Online Boutique defect oracle references tests from the canonical 51-test qmind library before recall numbers are published.

Example:

```powershell
python benchmark-pipeline/check-defect-oracle.py --oracle defect-oracle/online-boutique-defect-oracle.v2.json --library qmind-test-library/online-boutique-playwright-51.json
```

Missing `expected_detecting_tests` IDs are errors because defect recall depends on those exact identifiers. Unknown `expected_unaffected_tests` values are warnings by default because that field may contain broad group labels instead of concrete test IDs; pass `--strict` to make those warnings fail the check.

Run this checker before publishing benchmark results so placeholder or stale oracle entries are caught before they skew recall measurements.

## Benchmark comparison methods

Use these four method names when publishing benchmark output:

1. Traditional Approach (Full Suite)
   - Executes the full 51-test suite.
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

`select-random-approach.py` selects a deterministic random subset from the canonical 51-test library. Pass `--size` directly, or use `--same-size-as` to match an existing selected-test JSON such as a Quantik Mind selection.

```powershell
python benchmark-pipeline/select-random-approach.py --library qmind-test-library/online-boutique-playwright-51.json --size 11 --seed 42
```

### History + Code Change Approach selector

`select-history-code-change-approach.py` scores tests using transparent deterministic rules: high-risk ID keywords, historical criticality metadata, changed-code/domain matching, and optional scenario-specific boosts from the oracle and scenario metadata.

```powershell
python benchmark-pipeline/select-history-code-change-approach.py --library qmind-test-library/online-boutique-playwright-51.json --oracle defect-oracle/online-boutique-defect-oracle.v2.json --scenarios benchmark-pipeline/scenarios.json --size 11 --scenario OB-001
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

`run-expected-recall-matrix.py` runs a single expected-oracle comparison matrix across the four benchmark methods: Traditional Approach (Full Suite), Random Approach, History + Code Change Approach, and Quantik Mind. It loads the canonical 51-test library, infers the Quantik Mind selection size from the selected-test file, builds deterministic baseline selections, and reports expected defect recall and execution reduction.

This runner uses `expected_detecting_tests` from the oracle. OB-001 through OB-004 are still planned scenarios, so this output is useful for pipeline validation only and must not be presented as validated benchmark results.

Example:

```powershell
python benchmark-pipeline/run-expected-recall-matrix.py `
  --oracle defect-oracle/online-boutique-defect-oracle.v2.json `
  --library qmind-test-library/online-boutique-playwright-51.json `
  --qmind-selected benchmark-runs/qmind-online-boutique/selected-tests-51.json `
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
python -m py_compile benchmark-pipeline/normalize-qmind-selection.py benchmark-pipeline/evaluate-defect-recall.py
foreach ($file in Get-ChildItem benchmark-pipeline -Filter *.ps1) {
  $tokens = $null
  $errors = $null
  [System.Management.Automation.Language.Parser]::ParseFile($file.FullName, [ref]$tokens, [ref]$errors) | Out-Null
  if ($errors.Count -gt 0) { throw "$($file.Name) has parser errors" }
}
python -m json.tool benchmark-results/final-comparison/final-comparison.json
```

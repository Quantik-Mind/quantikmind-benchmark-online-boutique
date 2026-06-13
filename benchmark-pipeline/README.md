# Benchmark Pipeline

## QMind CLI reproducibility

Run these scripts from the repository root after copying `.env.example` to `.env` and filling in `QMIND_API_URL`, `QMIND_API_KEY`, and `QMIND_PROJECT_ID`.

```powershell
.\benchmark-pipeline\setup-qmind.ps1
.\benchmark-pipeline\sync-library.ps1
.\benchmark-pipeline\import-history.ps1
.\benchmark-pipeline\configure-observability.ps1
.\benchmark-pipeline\generate-final-comparison.ps1
```

`setup-qmind.ps1` writes `qmind.yaml` from `qmind.example.yaml` with environment placeholders preserved, so secrets stay in `.env` and are not committed. The setup command prints the API key as `<redacted>`.

`sync-library.ps1` syncs `qmind-test-library/online-boutique-playwright-51.json` and validates that it contains the expected 51 tests before invoking the CLI.

`import-history.ps1` uses the existing synthetic history generators:

- `generate-synthetic-history-junit.py`
- `generate-targeted-entanglement-history.py`
- `generate-entangled-history-json.py`

It then attempts `qmind history import --file <artifact>`. If your installed CLI exposes history import through a different command, run `import-history.ps1 -GenerateOnly` and import the generated XML/JSON artifacts from `benchmark-runs/qmind-online-boutique/` manually.

`configure-observability.ps1` applies `qmind-config/observability-online-boutique.example.yaml` with Prometheus and runs `qmind observability status`.

`generate-final-comparison.ps1` is the main benchmark entry point. In normal mode it invokes `run-qmind-subset.ps1` once per benchmark case, derives changed files from `benchmark-pipeline/scenarios.json`, writes per-case QMind selections, evaluates every method against the matching case oracle, and regenerates the final comparison artifacts.

`run-qmind-subset.ps1` can also be run directly for debugging a single QMind changed-files subset:

```powershell
.\benchmark-pipeline\run-qmind-subset.ps1 -BenchmarkCase OB-001 -SelectionOutput benchmark-runs/qmind-online-boutique/qmind-selection-ob-001.json
.\benchmark-pipeline\run-qmind-subset.ps1 -BenchmarkCase OB-002 -SelectionOutput benchmark-runs/qmind-online-boutique/qmind-selection-ob-002.json
.\benchmark-pipeline\run-qmind-subset.ps1 -BenchmarkCase OB-003 -SelectionOutput benchmark-runs/qmind-online-boutique/qmind-selection-ob-003.json
.\benchmark-pipeline\run-qmind-subset.ps1 -BenchmarkCase OB-004 -SelectionOutput benchmark-runs/qmind-online-boutique/qmind-selection-ob-004.json
.\benchmark-pipeline\run-qmind-subset.ps1 -BenchmarkCase OB-005 -SelectionOutput benchmark-runs/qmind-online-boutique/qmind-selection-ob-005.json
.\benchmark-pipeline\run-qmind-subset.ps1 -BenchmarkCase OB-006 -SelectionOutput benchmark-runs/qmind-online-boutique/qmind-selection-ob-006.json
```

It writes normalized canonical IDs without a UTF-8 BOM and validates them against `qmind-test-library/online-boutique-playwright-51.json`. For OB-004 it fails if `payment-order-completion-confirms-success` is missing.

When the QMind CLI/API returns dynamic risk diagnostics, `run-qmind-subset.ps1` preserves `business_metrics.risk_coverage`, `business_metrics.top_risk_coverage`, `business_metrics.residual_risk`, and `business_metrics.risk_efficiency` in the saved selection artifact. These diagnostics are not synthesized by the benchmark pipeline; they require QMind CLI/API subset artifacts that include `business_metrics` or equivalent risk fields.

`evaluate-qmind.ps1` writes a QMind evaluation JSON. Pass `-Scenario OB-001` to evaluate one benchmark case.

Use `-DryRun` on the QMind-facing scripts to inspect the command path without contacting the API. Dry runs warn when `.env` still contains placeholders.

## Baseline validation

Baseline validation runs the full canonical 51-test Playwright suite against a clean Online Boutique deployment before defect scenarios are implemented. This verifies that the test harness and deployed application are stable before any scenario-specific failures are used as benchmark evidence.

Example:

```powershell
powershell -ExecutionPolicy Bypass -File benchmark-pipeline/run-baseline-validation.ps1 -FrontendUrl "http://34.185.198.67/" -Workers 2
```

The helper writes Playwright reports under `benchmark-runs/baseline-validation` by default. It uses 2 Playwright workers by default for Online Boutique benchmark stability, and generated outputs under `benchmark-runs/` are ignored by git.

## Scenario-aware defect recall evaluator

`evaluate-defect-recall.py` evaluates whether a selected test set detects the benchmark defect scenarios described by the defect oracle. It reports defect recall, execution reduction, and per-scenario detection details. Pass `--scenario OB-001` to score one benchmark case at a time after selection.

Example:

```powershell
python benchmark-pipeline/evaluate-defect-recall.py --oracle defect-oracle/online-boutique-defect-oracle.v2.json --selected benchmark-runs/qmind-online-boutique/selected-tests-51.json --method qmind --use-validated --library-api benchmark-runs/qmind-online-boutique/library-api-51.json
```

The selected tests input can be a JSON object with `selected_tests`, a JSON array of test IDs, or a qmind-like object containing selected test objects with identifiers such as `id`, `test_id`, `name`, or `title`. Test identifiers are normalized to canonical strings before scoring.

### Normalizing qmind subset output

`normalize-qmind-selection.py` converts raw qmind subset output into the canonical `selected_tests` JSON consumed by the benchmark comparator. If raw JSON contains QMind dynamic risk diagnostics, the normalizer carries those fields through alongside the normalized test IDs.

```powershell
python benchmark-pipeline/normalize-qmind-selection.py `
  benchmark-runs/qmind-online-boutique/qmind-subset-51-raw.txt `
  benchmark-runs/qmind-online-boutique/selected-tests-51.json `
  --library-api benchmark-runs/qmind-online-boutique/library-api-51.json
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
   - Selects 26 tests, approximately 50% of the 51-test suite, with deterministic seed 42.
   - Used as placebo/control.
3. History + Code Change Approach
   - Deterministic baseline based on historical risk metadata and changed-file matching.
   - Represents classic test intelligence without runtime signals or adaptive entanglement.
4. Quantik Mind
   - Uses history, code change context, runtime signals, and adaptive entanglement.

Machine-readable method slugs are `full-suite`, `random`, `history-code-change`, and `qmind`.

### Final comparison generator

`generate-final-comparison.ps1` regenerates the published final comparison artifacts from committed inputs:

```powershell
.\benchmark-pipeline\generate-final-comparison.ps1
```

It writes `benchmark-results/final-comparison/final-comparison.json`, `docs/final-benchmark-comparison.md`, aggregate method evaluations, and per-case Full Suite, Random, History + Code Change, and QMind scoring artifacts for OB-001 through OB-006.

The generator treats OB-001 through OB-006 as benchmark cases. OB-001 through OB-004 are code-change controls, OB-005 is runtime-aware, and OB-006 is combined-signal. Random uses 26 tests with seed 42 and writes a per-case selection artifact. History + Code Change uses 15 tests per case and reads only the canonical library, history-style metadata, and changed files from `benchmark-pipeline/scenarios.json`; oracle detecting tests are used only by `evaluate-defect-recall.py`.

Interpret final comparison output as recall first, execution reduction second, with category breakdowns always shown. It is not a "lowest test count wins" report: History + Code Change gets 4/6 recall with 15 average tests and 70.6% execution reduction, while QMind gets 6/6 recall with 16.2 average tests and 68.3% execution reduction. Quantik Mind spends 1.2 extra tests on average to recover runtime-aware and combined-signal defect classes that History + Code Change misses.

QMind is also evaluated per benchmark case. Normal mode calls the live QMind subset path and creates:

- `benchmark-runs/qmind-online-boutique/qmind-selection-ob-001.json`
- `benchmark-runs/qmind-online-boutique/qmind-selection-ob-002.json`
- `benchmark-runs/qmind-online-boutique/qmind-selection-ob-003.json`
- `benchmark-runs/qmind-online-boutique/qmind-selection-ob-004.json`
- `benchmark-runs/qmind-online-boutique/qmind-selection-ob-005.json`
- `benchmark-runs/qmind-online-boutique/qmind-selection-ob-006.json`

It fails clearly if QMind configuration is missing, the CLI is unavailable, the API is unreachable, observability is not configured, or the library/project state is not synced. It also fails if a QMind selection contains non-canonical test IDs, or if the OB-004 QMind selection does not include `payment-order-completion-confirms-success`.

To reuse previously generated per-case QMind selections instead of calling live QMind:

```powershell
.\benchmark-pipeline\generate-final-comparison.ps1 -UseExistingQMindSelections
```

That mode requires all five per-case QMind artifacts to exist and validate.

### Random Approach selector

`select-random-approach.py` selects a deterministic random subset from the canonical 51-test library. Pass `--size` directly, or use `--same-size-as` to match an existing selected-test JSON such as a Quantik Mind selection.

```powershell
python benchmark-pipeline/select-random-approach.py --library qmind-test-library/online-boutique-playwright-51.json --size 11 --seed 42
```

### History + Code Change Approach selector

`select-history-code-change-approach.py` scores tests using transparent deterministic rules: high-risk ID keywords, historical criticality metadata, changed-file tokens, and code-mapping overlap. It does not read the defect oracle; the `--oracle` option is retained only as deprecated compatibility input and is ignored.

```powershell
python benchmark-pipeline/select-history-code-change-approach.py --library qmind-test-library/online-boutique-playwright-51.json --scenarios benchmark-pipeline/scenarios.json --size 15 --scenario OB-001
```

### Evaluating selector output

Write selector output to a file with `--output`, then pass that file to `evaluate-defect-recall.py`.

```powershell
python benchmark-pipeline/select-random-approach.py --size 26 --seed 42 --benchmark-case OB-001 --output benchmark-runs/random-ob-001-selection.json
python benchmark-pipeline/evaluate-defect-recall.py --oracle defect-oracle/online-boutique-defect-oracle.v2.json --selected benchmark-runs/random-ob-001-selection.json --method random --scenario OB-001 --use-validated

python benchmark-pipeline/select-history-code-change-approach.py --size 11 --scenario OB-001 --output benchmark-runs/history-code-change-ob-001-selection.json
python benchmark-pipeline/evaluate-defect-recall.py --oracle defect-oracle/online-boutique-defect-oracle.v2.json --selected benchmark-runs/history-code-change-ob-001-selection.json --method history-code-change --scenario OB-001 --use-validated
```

## Expected recall matrix runner

`run-expected-recall-matrix.py` runs a single expected-oracle comparison matrix across the four benchmark methods: Traditional Approach (Full Suite), Random Approach, History + Code Change Approach, and Quantik Mind. It loads the canonical 51-test library, infers the Quantik Mind selection size from the selected-test file, builds deterministic baseline selections, and reports expected defect recall and execution reduction.

This runner uses `expected_detecting_tests` from the oracle. The final comparison path uses per-case validated oracle entries for OB-001 through OB-006; the expected runner is retained for pipeline validation only and must not be presented as the final benchmark result.

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

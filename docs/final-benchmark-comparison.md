# Final Benchmark Comparison Run 001

## Scope

This run compares defect recall for the canonical Online Boutique 51-test Playwright library:

- Canonical library: `qmind-test-library/online-boutique-playwright-51.json`
- Defect oracle: `defect-oracle/online-boutique-defect-oracle.v2.json`
- Oracle mode: `validated_detecting_tests`
- Defect universe: `OB-001`, `OB-002`, `OB-003`, `OB-004`
- Primary KPI: `Defect Recall = Detected Defects / Full Suite Defects`

The four validated scenarios are:

| Scenario | Name | Validation status |
| --- | --- | --- |
| OB-001 | Checkout Regression | validated |
| OB-002 | Cart Regression | validated |
| OB-003 | Product Detail Regression | validated |
| OB-004 | Payment Regression | validated |

## Comparison Table

| Method | Status | Tests Executed | Execution Reduction | Defects Detected | Defect Recall |
| --- | --- | ---: | ---: | ---: | ---: |
| Traditional Approach / Full Suite | measured | 51 | 0.0% | 4 / 4 | 100.0% |
| Random Approach | measured | 11 | 78.4% | 1 / 4 | 25.0% |
| History + Code Change Approach | measured | 11 per scenario | 78.4% | 4 / 4 | 100.0% |
| Quantik Mind | pending live selection artifact | pending | pending | pending | pending |

## Methodology

Traditional Approach / Full Suite executes all 51 canonical tests and is the recall baseline. It detected all four validated scenario defects.

Random Approach uses `benchmark-pipeline/select-random-approach.py` against the canonical 51-test library with size `11` and seed `42`. The selected tests are recorded in `benchmark-results/final-comparison/random-selection.json`.

History + Code Change Approach uses `benchmark-pipeline/select-history-code-change-approach.py` with each scenario's changed-file and domain context from `benchmark-pipeline/scenarios.json`. This models the baseline as it would be used on a scenario branch where changed files are known. Each scenario uses an 11-test selection.

Quantik Mind is not reported as measured in this run. Existing QMind raw files under `benchmark-runs/qmind-online-boutique/` contain numeric CLI IDs such as `33686`, `33685`, and `33688`; those IDs do not map to the canonical 51-test library test IDs. Reporting QMind recall from those artifacts would not be reproducible against the validated oracle.

## Per-Method Notes

### Traditional Approach / Full Suite

- Tests executed: 51
- Execution reduction: 0.0%
- Detected scenarios: OB-001, OB-002, OB-003, OB-004
- Artifact: `benchmark-results/final-comparison/full-suite-evaluation.json`

### Random Approach

- Tests executed: 11
- Seed: 42
- Execution reduction: 78.4%
- Detected scenarios: OB-003
- Missed scenarios: OB-001, OB-002, OB-004
- Artifact: `benchmark-results/final-comparison/random-evaluation.json`

### History + Code Change Approach

- Tests executed: 11 per scenario
- Execution reduction: 78.4%
- Detected scenarios: OB-001, OB-002, OB-003, OB-004
- Selection artifacts:
  - `benchmark-results/final-comparison/history-code-change-ob-001-selection.json`
  - `benchmark-results/final-comparison/history-code-change-ob-002-selection.json`
  - `benchmark-results/final-comparison/history-code-change-ob-003-selection.json`
  - `benchmark-results/final-comparison/history-code-change-ob-004-selection.json`

This baseline is intentionally documented as a deterministic comparator, not as Quantik Mind. Its result depends on scenario-specific changed-file and domain metadata.

### Quantik Mind

Status: pending live selection artifact.

Required reproducibility flow:

```bash
bash benchmark-pipeline/run-online-boutique-qmind-benchmark.sh
python benchmark-pipeline/normalize-qmind-selection.py <raw-qmind-output> <canonical-selected-tests.json>
python benchmark-pipeline/evaluate-defect-recall.py --oracle defect-oracle/online-boutique-defect-oracle.v2.json --selected <canonical-selected-tests.json> --method qmind --use-validated --output <qmind-evaluation.json>
```

The final QMind row should be filled only after `<canonical-selected-tests.json>` contains test IDs from `qmind-test-library/online-boutique-playwright-51.json`.

## Reproducibility Commands

```powershell
python benchmark-pipeline/select-random-approach.py --library qmind-test-library/online-boutique-playwright-51.json --size 11 --seed 42 --output benchmark-results/final-comparison/random-selection.json
python benchmark-pipeline/evaluate-defect-recall.py --oracle defect-oracle/online-boutique-defect-oracle.v2.json --selected qmind-test-library/online-boutique-playwright-51.json --method full-suite --use-validated --output benchmark-results/final-comparison/full-suite-evaluation.json
python benchmark-pipeline/evaluate-defect-recall.py --oracle defect-oracle/online-boutique-defect-oracle.v2.json --selected benchmark-results/final-comparison/random-selection.json --method random --use-validated --output benchmark-results/final-comparison/random-evaluation.json
python benchmark-pipeline/select-history-code-change-approach.py --library qmind-test-library/online-boutique-playwright-51.json --oracle defect-oracle/online-boutique-defect-oracle.v2.json --scenarios benchmark-pipeline/scenarios.json --size 11 --scenario OB-001 --output benchmark-results/final-comparison/history-code-change-ob-001-selection.json
python benchmark-pipeline/select-history-code-change-approach.py --library qmind-test-library/online-boutique-playwright-51.json --oracle defect-oracle/online-boutique-defect-oracle.v2.json --scenarios benchmark-pipeline/scenarios.json --size 11 --scenario OB-002 --output benchmark-results/final-comparison/history-code-change-ob-002-selection.json
python benchmark-pipeline/select-history-code-change-approach.py --library qmind-test-library/online-boutique-playwright-51.json --oracle defect-oracle/online-boutique-defect-oracle.v2.json --scenarios benchmark-pipeline/scenarios.json --size 11 --scenario OB-003 --output benchmark-results/final-comparison/history-code-change-ob-003-selection.json
python benchmark-pipeline/select-history-code-change-approach.py --library qmind-test-library/online-boutique-playwright-51.json --oracle defect-oracle/online-boutique-defect-oracle.v2.json --scenarios benchmark-pipeline/scenarios.json --size 11 --scenario OB-004 --output benchmark-results/final-comparison/history-code-change-ob-004-selection.json
python benchmark-pipeline/run-expected-recall-matrix.py --oracle defect-oracle/online-boutique-defect-oracle.v2.json --library qmind-test-library/online-boutique-playwright-51.json --qmind-selected qmind-test-library/online-boutique-playwright-11.json --scenarios benchmark-pipeline/scenarios.json --random-seed 42 --output-json benchmark-results/final-comparison/expected-recall-matrix.json --output-md benchmark-results/final-comparison/expected-recall-matrix.md
```

## Limitations

- Quantik Mind final performance is pending and not claimed in this report.
- The random and history/code-change baselines use a provisional 11-test comparison size until the live QMind artifact determines the final same-size comparison.
- `benchmark-results/final-comparison/expected-recall-matrix.json` is a pipeline sanity check that uses expected oracle data. It is not the validated final comparison.

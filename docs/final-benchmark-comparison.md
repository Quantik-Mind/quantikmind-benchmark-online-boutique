# Blocked Final Benchmark Comparison Status

## Scope

This is a diagnostic pre-final comparison status, not the final investor/public benchmark result. The final comparison is blocked until Quantik Mind is run against the canonical 51-test library.

Current benchmark scope:

- Canonical library: `qmind-test-library/online-boutique-playwright-51.json`
- Defect oracle: `defect-oracle/online-boutique-defect-oracle.v2.json`
- Oracle mode: `validated_detecting_tests`
- Defect universe: `OB-001`, `OB-002`, `OB-003`, `OB-004`
- Primary KPI: `Defect Recall = Detected Defects / Full Suite Defects`
- Comparison status: `blocked_pending_qmind_51_selection`

The active benchmark uses exactly one canonical library:

```text
qmind-test-library/online-boutique-playwright-51.json
```

Historical 11/22-test experiments are archived and are not part of final benchmark scoring.

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
| Random Approach | provisional comparator | 11 | 78.4% | 1 / 4 | 25.0% |
| History + Code Change Approach | provisional comparator | 11 per scenario | 78.4% | 4 / 4 | 100.0% |
| Quantik Mind | blocked pending 51-test selection | pending | pending | pending | pending |

## Methodology

Traditional Approach / Full Suite executes all 51 canonical tests and is the recall baseline. It detected all four validated scenario defects.

Random Approach uses `benchmark-pipeline/select-random-approach.py` against the canonical 51-test library with size `11` and seed `42`. The selected tests are recorded in `benchmark-results/final-comparison/random-selection.json`. This row is provisional until the regenerated 51-test QMind selection determines the final same-size comparison.

History + Code Change Approach uses `benchmark-pipeline/select-history-code-change-approach.py` with each scenario's changed-file and domain context from `benchmark-pipeline/scenarios.json`. This models the baseline as it would be used on a scenario branch where changed files are known. Each scenario uses an 11-test selection. This row is also provisional until the regenerated 51-test QMind selection determines the final same-size comparison.

Quantik Mind is not reported as measured in this run. Historical QMind raw outputs are not part of the active benchmark and must not be used for final scoring. The final comparison must be generated only after running QMind against `qmind-test-library/online-boutique-playwright-51.json`.

## Verified Root Cause

- Active canonical library: `qmind-test-library/online-boutique-playwright-51.json`
- Historical QMind raw outputs exist under `benchmark-runs/qmind-online-boutique/`.
- Historical QMind selection IDs may map correctly through historical API library exports.
- Historical 11/22-test experiments are no longer part of active final benchmark scoring.

The blocker is not ID mapping. The blocker is that no current Quantik Mind selection artifact has been generated from the canonical 51-test library.

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

Status: blocked pending 51-test selection artifact.

Required command sequence:

```bash
qmind sync library --file qmind-test-library/online-boutique-playwright-51.json

qmind subset --framework playwright > benchmark-runs/qmind-online-boutique/qmind-subset-51-raw.txt

python benchmark-pipeline/normalize-qmind-selection.py \
  benchmark-runs/qmind-online-boutique/qmind-subset-51-raw.txt \
  benchmark-runs/qmind-online-boutique/selected-tests-51.json \
  --library-api benchmark-runs/qmind-online-boutique/library-api-51.json

python benchmark-pipeline/evaluate-defect-recall.py \
  --oracle defect-oracle/online-boutique-defect-oracle.v2.json \
  --selected benchmark-runs/qmind-online-boutique/selected-tests-51.json \
  --method qmind \
  --use-validated \
  --library-api benchmark-runs/qmind-online-boutique/library-api-51.json \
  --output benchmark-results/final-comparison/qmind-51-evaluation.json
```

The final QMind row should be filled only after `benchmark-runs/qmind-online-boutique/selected-tests-51.json` contains test IDs from `qmind-test-library/online-boutique-playwright-51.json`. If qmind subset returns backend/API numeric IDs, normalize them through `benchmark-runs/qmind-online-boutique/library-api-51.json`, whose entries must include `id` and `test_id`.

## Reproducibility Commands

```powershell
python benchmark-pipeline/select-random-approach.py --library qmind-test-library/online-boutique-playwright-51.json --size 11 --seed 42 --output benchmark-results/final-comparison/random-selection.json
python benchmark-pipeline/evaluate-defect-recall.py --oracle defect-oracle/online-boutique-defect-oracle.v2.json --selected qmind-test-library/online-boutique-playwright-51.json --method full-suite --use-validated --output benchmark-results/final-comparison/full-suite-evaluation.json
python benchmark-pipeline/evaluate-defect-recall.py --oracle defect-oracle/online-boutique-defect-oracle.v2.json --selected benchmark-results/final-comparison/random-selection.json --method random --use-validated --output benchmark-results/final-comparison/random-evaluation.json
python benchmark-pipeline/select-history-code-change-approach.py --library qmind-test-library/online-boutique-playwright-51.json --oracle defect-oracle/online-boutique-defect-oracle.v2.json --scenarios benchmark-pipeline/scenarios.json --size 11 --scenario OB-001 --output benchmark-results/final-comparison/history-code-change-ob-001-selection.json
python benchmark-pipeline/select-history-code-change-approach.py --library qmind-test-library/online-boutique-playwright-51.json --oracle defect-oracle/online-boutique-defect-oracle.v2.json --scenarios benchmark-pipeline/scenarios.json --size 11 --scenario OB-002 --output benchmark-results/final-comparison/history-code-change-ob-002-selection.json
python benchmark-pipeline/select-history-code-change-approach.py --library qmind-test-library/online-boutique-playwright-51.json --oracle defect-oracle/online-boutique-defect-oracle.v2.json --scenarios benchmark-pipeline/scenarios.json --size 11 --scenario OB-003 --output benchmark-results/final-comparison/history-code-change-ob-003-selection.json
python benchmark-pipeline/select-history-code-change-approach.py --library qmind-test-library/online-boutique-playwright-51.json --oracle defect-oracle/online-boutique-defect-oracle.v2.json --scenarios benchmark-pipeline/scenarios.json --size 11 --scenario OB-004 --output benchmark-results/final-comparison/history-code-change-ob-004-selection.json
```

## Limitations

- This document is a blocked pre-final status report, not the final benchmark comparison.
- Quantik Mind final performance is pending and not claimed in this report.
- The random and history/code-change baselines use a provisional 11-test comparison size until the regenerated 51-test QMind artifact determines the final same-size comparison.
- Expected-matrix artifacts are not included in this final-comparison result set because no 51-test QMind selection artifact exists yet.

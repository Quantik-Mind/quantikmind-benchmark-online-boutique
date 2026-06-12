# Final Benchmark Comparison

## Scope

This comparison uses the canonical 51-test Online Boutique library and the validated defect oracle.

- Canonical library: `qmind-test-library/online-boutique-playwright-51.json`
- Defect oracle: `defect-oracle/online-boutique-defect-oracle.v2.json`
- Oracle mode: `validated_detecting_tests`
- Generator: `benchmark-pipeline/generate-final-comparison.ps1`
- QMind selection artifact: `benchmark-runs/qmind-online-boutique/qmind-current-selection.json`
- QMind evaluation artifact: `benchmark-results/final-comparison/qmind-current-evaluation.json`
- QMind selection result: selection executed successfully, 15/51 tests selected
- QMind scoring status: measured with canonical test IDs

QMind selected 15/51 tests, detected all 4 validated defect scenarios, and achieved 70.6% execution reduction with 100.0% defect recall. OB-004 is detected by `payment-order-completion-confirms-success`.

## Comparison Table

| Method | Status | Tests | Execution Reduction | Defects Detected | Defect Recall |
| --- | --- | ---: | ---: | ---: | ---: |
| Traditional / Full Suite | measured | 51 | 0.0% | 4 / 4 | 100.0% |
| Random | measured | 15 | 70.6% | 1 / 4 | 25.0% |
| History + Code Change | measured | 15 per scenario | 70.6% | 4 / 4 | 100.0% |
| Quantik Mind | measured | 15 | 70.6% | 4 / 4 | 100.0% |

## Method Notes

Traditional / Full Suite uses all `test_id` values from `qmind-test-library/online-boutique-playwright-51.json` and detects all four validated scenarios.

Random uses a deterministic 15-test sample from the canonical library with seed 42. It detects OB-003.

History + Code Change uses scenario-specific changed-file/domain context with a 15-test selection for each scenario. Each scenario is scored against its own corresponding selection and detects OB-001, OB-002, OB-003, OB-004.

Quantik Mind uses the validated current selection in `benchmark-runs/qmind-online-boutique/qmind-current-selection.json`. The selection contains canonical test IDs, detects OB-001, OB-002, OB-003, OB-004, and detects OB-004 through `payment-order-completion-confirms-success`.

## Reproduction

Regenerate all final comparison artifacts from committed inputs:

```powershell
.\benchmark-pipeline\generate-final-comparison.ps1
```

The generator writes:

- `benchmark-results/final-comparison/final-comparison.json`
- `docs/final-benchmark-comparison.md`
- `benchmark-results/final-comparison/full-suite-evaluation.json`
- `benchmark-results/final-comparison/random-selection.json`
- `benchmark-results/final-comparison/random-evaluation.json`
- `benchmark-results/final-comparison/qmind-current-evaluation.json`
- `history-code-change` selection and evaluation artifacts for OB-001 through OB-004

It fails if any expected artifact is missing or if the QMind evaluation is not exactly 15 selected tests, 4 detected scenarios, and 100.0% defect recall.

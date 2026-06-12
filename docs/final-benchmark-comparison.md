# Final Benchmark Comparison

## Scope

This comparison uses the canonical 51-test Online Boutique library and the validated defect oracle.

- Canonical library: `qmind-test-library/online-boutique-playwright-51.json`
- Defect oracle: `defect-oracle/online-boutique-defect-oracle.v2.json`
- Oracle mode: `validated_detecting_tests`
- QMind selection artifact: `benchmark-runs/qmind-online-boutique/qmind-current-selection.json`
- QMind evaluation artifact: `benchmark-results/final-comparison/qmind-current-evaluation.json`
- QMind selection result: selection executed successfully, 15/51 tests selected
- QMind scoring status: measured with canonical test IDs

QMind selected 15/51 tests, detected all 4 validated defect scenarios, and achieved 70.6% execution reduction with 100.0% defect recall. This comparison uses canonical `test_id` values, not backend numeric IDs.

## Comparison Table

| Method | Status | Tests | Execution Reduction | Defects Detected | Defect Recall |
| --- | --- | ---: | ---: | ---: | ---: |
| Traditional / Full Suite | measured | 51 | 0.0% | 4 / 4 | 100.0% |
| Random | measured | 22 | 56.9% | 2 / 4 | 50.0% |
| History + Code Change | measured | 22 per scenario | 56.9% | 4 / 4 | 100.0% |
| Quantik Mind | measured | 15 | 70.6% | 4 / 4 | 100.0% |

## Method Notes

Traditional / Full Suite uses all `test_id` values from `qmind-test-library/online-boutique-playwright-51.json` and detects all four validated scenarios.

Random uses a deterministic 22-test sample from the canonical library with seed 42. It detects OB-003 and OB-004.

History + Code Change uses scenario-specific changed-file/domain context with a 22-test selection for each scenario. Each scenario is scored against its own corresponding selection and all four validated scenarios are detected.

Quantik Mind uses the validated current selection in `benchmark-runs/qmind-online-boutique/qmind-current-selection.json`. The selection contains canonical test IDs, detects OB-001, OB-002, OB-003, and OB-004, and detects OB-004 through `payment-order-completion-confirms-success`.

## Reproduction Commands

```powershell
python benchmark-pipeline/evaluate-defect-recall.py --oracle defect-oracle/online-boutique-defect-oracle.v2.json --selected qmind-test-library/online-boutique-playwright-51.json --method full-suite --use-validated --output benchmark-results/final-comparison/full-suite-evaluation.json
python benchmark-pipeline/select-random-approach.py --library qmind-test-library/online-boutique-playwright-51.json --size 22 --seed 42 --output benchmark-results/final-comparison/random-selection.json
python benchmark-pipeline/evaluate-defect-recall.py --oracle defect-oracle/online-boutique-defect-oracle.v2.json --selected benchmark-results/final-comparison/random-selection.json --method random --use-validated --output benchmark-results/final-comparison/random-evaluation.json
python benchmark-pipeline/select-history-code-change-approach.py --library qmind-test-library/online-boutique-playwright-51.json --oracle defect-oracle/online-boutique-defect-oracle.v2.json --scenarios benchmark-pipeline/scenarios.json --size 22 --scenario OB-001 --output benchmark-results/final-comparison/history-code-change-ob-001-selection.json
python benchmark-pipeline/select-history-code-change-approach.py --library qmind-test-library/online-boutique-playwright-51.json --oracle defect-oracle/online-boutique-defect-oracle.v2.json --scenarios benchmark-pipeline/scenarios.json --size 22 --scenario OB-002 --output benchmark-results/final-comparison/history-code-change-ob-002-selection.json
python benchmark-pipeline/select-history-code-change-approach.py --library qmind-test-library/online-boutique-playwright-51.json --oracle defect-oracle/online-boutique-defect-oracle.v2.json --scenarios benchmark-pipeline/scenarios.json --size 22 --scenario OB-003 --output benchmark-results/final-comparison/history-code-change-ob-003-selection.json
python benchmark-pipeline/select-history-code-change-approach.py --library qmind-test-library/online-boutique-playwright-51.json --oracle defect-oracle/online-boutique-defect-oracle.v2.json --scenarios benchmark-pipeline/scenarios.json --size 22 --scenario OB-004 --output benchmark-results/final-comparison/history-code-change-ob-004-selection.json
```

QMind reproduction artifacts:

- Selection: `benchmark-runs/qmind-online-boutique/qmind-current-selection.json`
- Evaluation: `benchmark-results/final-comparison/qmind-current-evaluation.json`

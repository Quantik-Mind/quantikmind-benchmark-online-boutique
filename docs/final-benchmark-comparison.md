# Final Benchmark Comparison

## Scope

This comparison uses the canonical 51-test Online Boutique library and the validated defect oracle.

- Canonical library: `qmind-test-library/online-boutique-playwright-51.json`
- Defect oracle: `defect-oracle/online-boutique-defect-oracle.v2.json`
- Oracle mode: `validated_detecting_tests`
- QMind raw selection: `benchmark-runs/qmind-online-boutique/qmind-subset-51-raw.txt`
- QMind selection result: selection executed successfully, 22/51 tests selected
- QMind scoring status: normalization error

QMind selection executed successfully: 22/51 tests selected. QMind scoring blocked by normalization mapping, not by selection failure. No QMind recall is claimed.

## Comparison Table

| Method | Status | Tests | Execution Reduction | Defects Detected | Defect Recall |
| --- | --- | ---: | ---: | ---: | ---: |
| Traditional / Full Suite | measured | 51 | 0.0% | 4 / 4 | 100.0% |
| Random | measured | 22 | 56.9% | 2 / 4 | 50.0% |
| History + Code Change | measured | 22 per scenario | 56.9% | 4 / 4 | 100.0% |
| Quantik Mind | normalization_error | 22 selected | n/a | n/a | not claimed |

## QMind Normalization

The real qmind subset output contains backend numeric IDs:

```text
33723 33693 33698 33721 33684 33707 33687 33686 33685 33699 33728 33690 33701 33694 33712 33700 33688 33708 33689 33717 33679 33680
```

The available mapping artifact checked was `benchmark-runs/qmind-online-boutique/library-api.json`. It does not map every selected numeric ID to a canonical `test_id`.

Unmapped numeric IDs:

```text
33690, 33693, 33694, 33698, 33699, 33700, 33701, 33707, 33708, 33712, 33717, 33721, 33723, 33728
```

Because normalization is incomplete, QMind selected tests are not compared against oracle detecting tests. This avoids treating unmapped numeric IDs as missed defects and avoids inventing QMind recall.

## Method Notes

Traditional / Full Suite uses all `test_id` values from `qmind-test-library/online-boutique-playwright-51.json` and detects all four validated scenarios.

Random uses a deterministic 22-test sample from the canonical library with seed 42. It detects OB-003 and OB-004.

History + Code Change uses scenario-specific changed-file/domain context with a 22-test selection for each scenario. Each scenario is scored against its own corresponding selection and all four validated scenarios are detected.

Quantik Mind produced a real 22-test subset, but the subset is numeric backend/API IDs. Since the available mapping artifact is incomplete, QMind scoring is blocked by normalization mapping.

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

# Benchmark Methodology Review

## Old Methodology

The previous final comparison treated OB-001 through OB-004 as selector-specific scenario runs. Full Suite and Random were evaluated as broad selections, while History + Code Change generated one selection per scenario and the final comparison aggregated those scenario-specific results.

That shape made the benchmark easy to reproduce, but it did not cleanly model a CI/CD validation workflow. In a real pull request or commit validation run, a selector sees the test library, historical signals, changed files, and sometimes runtime/observability signals. It does not know which injected defect exists or which tests the oracle expects to fail.

## Issues Found

The audit found privileged information leakage in `benchmark-pipeline/select-history-code-change-approach.py`.

- The selector loaded the defect oracle.
- It boosted tests listed in `expected_detecting_tests`.
- It used scenario defect-behavior text when scoring candidate tests.
- Final aggregation mixed scenario-specific selector outputs without clearly modeling each scenario as an independent benchmark case.

That made the History + Code Change baseline scientifically too strong: it could select tests using outcome knowledge that should only be available to the evaluator.

`select-random-approach.py` did not use changed files, oracle data, or runtime data. `evaluate-defect-recall.py` correctly used oracle data for scoring, but it lacked a case-specific mode. `generate-final-comparison.ps1` reproduced the artifacts, but it encoded the old selector-specific scenario aggregation.

## Changes Applied

The benchmark now treats OB-001 through OB-006 as first-class benchmark cases. OB-001 through OB-004 form the code-change control group. OB-005 is the first runtime-aware case. OB-006 is the first combined-signal case.

Each case has:

- commit context
- changed files
- injected defect
- oracle detecting tests

Selection happens before oracle scoring. The oracle is used only by `evaluate-defect-recall.py`.

Implementation changes:

- `evaluate-defect-recall.py` now supports `--scenario` to score a single benchmark case.
- `select-random-approach.py` records its allowed selector inputs and still uses only the library plus deterministic seed.
- `select-history-code-change-approach.py` no longer reads the oracle and no longer uses oracle detecting tests or defect-behavior text.
- `run-qmind-subset.ps1` supports `-BenchmarkCase` and derives the correct changed-files input from `benchmark-pipeline/scenarios.json`.
- `generate-final-comparison.ps1` now generates per-case selections/evaluations, invokes QMind per case in normal mode, and aggregates case-level results only after all methods have been evaluated.
- `generate-final-comparison.ps1 -UseExistingQMindSelections` is the only mode that may reuse already generated per-case QMind artifacts.
- `docs/final-benchmark-comparison.md` reports the live QMind configuration blocker when the final comparison cannot be regenerated.

The defect oracle was also tightened to minimal direct validated detecting tests:

- OB-001 keeps direct checkout page/form detectors and drops broader order-flow assertions.
- OB-002 keeps the direct cart-state detector and drops checkout/order downstream symptoms.
- OB-003 keeps product-detail and catalog-detail detectors and drops cart, checkout, order, navigation, and broad frontend symptom tests.
- OB-004 keeps the single payment completion detector.
- OB-005 adds direct homepage detectors for a runtime-visible currency data corruption.

This precision pass keeps the oracle defensible: a selected test receives credit only when it directly validates the affected behavior, not merely because it can fail downstream from a broader user journey.

## Benchmark-Case Model

For each benchmark case, the generator:

1. Builds one selection for Full Suite, Random, and History + Code Change.
2. Runs QMind for the same case and writes one per-case QMind selection artifact.
3. Evaluates each selection against only that case's oracle entry.
4. Records selected tests, execution reduction, whether the defect was detected, and case recall.
5. Aggregates detected cases across all six benchmark cases and by category.

This is closer to a CI/CD workflow: a commit arrives with changed files, a selector chooses tests, then test execution and oracle validation determine whether the defect was caught.

## Selector Inputs

Full Suite uses:

- canonical test library

Random uses:

- canonical test library
- deterministic seed 42

History + Code Change uses:

- canonical test library
- historical risk metadata in the test library
- changed files from `benchmark-pipeline/scenarios.json`

Quantik Mind uses:

- canonical test library
- history
- changed files
- runtime metrics
- observability

QMind produces one canonical artifact per benchmark case in normal generator mode:

- `benchmark-results/qmind-selections/qmind-selection-ob-001.json`
- `benchmark-results/qmind-selections/qmind-selection-ob-002.json`
- `benchmark-results/qmind-selections/qmind-selection-ob-003.json`
- `benchmark-results/qmind-selections/qmind-selection-ob-004.json`
- `benchmark-results/qmind-selections/qmind-selection-ob-005.json`
- `benchmark-results/qmind-selections/qmind-selection-ob-006.json`

The generator does not reuse `benchmark-runs/qmind-online-boutique/qmind-current-selection.json` for all cases. Existing committed per-case artifacts may be reused only with `-UseExistingQMindSelections`.

## Oracle Inputs

Only the evaluator uses:

- defect identity
- validated detecting tests
- expected benchmark outcome

The final comparison uses `validated_detecting_tests` from `defect-oracle/online-boutique-defect-oracle.v2.json`.

## Aggregation Model

The aggregate result for each method is:

- detected benchmark cases / total benchmark cases
- detected benchmark cases / category benchmark cases
- case recall
- average selected tests
- average execution reduction

The aggregate should be interpreted as recall first, execution reduction second, with the category breakdown always shown. It is not a "lowest test count wins" comparison. After OB-006, History + Code Change is more aggressive at 15.0 average tests, 70.6% execution reduction, and 5/6 recall. Quantik Mind is slightly more conservative at 15.8 average tests, 69.0% execution reduction, and 6/6 recall.

| Method | Recall | Avg tests | Execution reduction | Interpretation |
|---|---:|---:|---:|---|
| H+CC | 5/6 | 15.0 | 70.6% | More aggressive, misses the runtime-aware defect |
| QMind | 6/6 | 15.8 | 69.0% | Slightly more conservative, preserves full recall |

Quantik Mind spends 0.8 more tests on average to recover the case that History + Code Change misses entirely. In code-change scenarios, QMind matches H+CC: 4/4 vs 4/4. In runtime-aware scenarios, QMind adds coverage: 1/1 vs 0/1. In combined-signal scenarios, QMind matches H+CC: 1/1 vs 1/1. The value claim is not "QMind always runs fewer tests"; it is that QMind keeps execution reduction high while avoiding blind spots from code-change-only selection.

Normal mode cannot produce a fresh live-QMind aggregate unless QMind configuration is available and QMind produces selections for all six benchmark cases. Reusing the OB-004-oriented `qmind-current-selection.json` for other cases would make the aggregate QMind result invalid. The committed comparison can be regenerated with `-UseExistingQMindSelections`, which validates the six committed per-case QMind artifacts before scoring them.

The committed OB-005 and OB-006 QMind artifacts currently select the same 17-test frontend/homepage risk cluster and report identical business metrics. This supports a transparent combined-signal case, but it should not be described as independent proof of an additional runtime-aware win until distinct live OB-006 runtime evidence is captured.

## Benchmark Limitations

Normal reproduction is one command:

```powershell
.\benchmark-pipeline\generate-final-comparison.ps1
```

That command requires a configured QMind CLI, synced library, imported history, and observability configuration. In this workspace it currently stops with:

```text
Missing required QMIND_API_URL in .env.
```

The committed QMind selection artifacts may be reused for reproducibility checks with:

```powershell
.\benchmark-pipeline\generate-final-comparison.ps1 -UseExistingQMindSelections
```

That mode still validates that every QMind selection contains canonical test IDs and that OB-004 includes `payment-order-completion-confirms-success`.

OB-005 is intentionally different from the code-change controls. Its changed file is `src/currencyservice/data/currency_conversion.json`, while the direct oracle tests are frontend homepage tests. The History + Code Change selector therefore misses OB-005 for transparent scoring reasons, while QMind can detect it only when runtime observability surfaces the currencyservice/frontend error signal.

The History + Code Change baseline is deterministic and transparent, but it is still a simplified local proxy for a static history/code-change-aware selection service. It uses local test metadata and changed-file matching rather than a production-trained model.

Random uses one deterministic seed. A seed sweep would give a distribution, but this benchmark intentionally keeps one reproducible control.

## Why This Better Reflects CI/CD

The new methodology separates selection from scoring. Selectors receive only the information a CI test-selection system should have before tests run. The oracle is applied afterward, exactly where defect detection should be measured.

This makes the comparison more defensible:

- no selector can select directly from oracle detecting tests
- each case represents one commit validation event
- per-case results are auditable
- aggregate recall is computed from case outcomes
- generated artifacts can be regenerated from committed inputs with one script

If a reviewer argues that H+CC has better savings, the response is: yes, but it achieves that by missing OB-005 and OB-006. The meaningful comparison is not saving alone; it is recall at a given execution budget. QMind trades 0.5 additional tests on average for two additional detected cases in the current six-case artifact set, while OB-006 remains subject to the duplicate-selection limitation above.

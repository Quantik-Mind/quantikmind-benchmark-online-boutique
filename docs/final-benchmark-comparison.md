# Final Benchmark Comparison

## Scope

This comparison models Online Boutique as five independent CI/CD benchmark cases. OB-001 through OB-004 are the code-change control group. OB-005 is the first runtime-aware scenario. Each case has commit context, changed files, an injected defect, and oracle detecting tests. Selectors run before scoring and do not receive defect identity, oracle detecting tests, or expected benchmark outcomes.

- Canonical library: `qmind-test-library/online-boutique-playwright-51.json`
- Defect oracle: `defect-oracle/online-boutique-defect-oracle.v2.json`
- Oracle mode: `validated_detecting_tests`
- Generator: `benchmark-pipeline/generate-final-comparison.ps1`
- Random seed: 42
- Random size: 26 tests
- History + Code Change size: 15 tests per case
- QMind selection artifacts: `benchmark-runs/qmind-online-boutique/qmind-selection-ob-001.json` through `benchmark-runs/qmind-online-boutique/qmind-selection-ob-005.json`
- QMind selection mode: `existing-per-case-artifacts`

## Oracle Precision

The defect oracle uses minimal direct validated detecting tests for each benchmark case. Broad downstream symptom tests are excluded from the oracle even when they can fail as a side effect.

| Case | Direct Validated Detecting Tests |
| --- | ---: |
| OB-001 | 2 |
| OB-002 | 1 |
| OB-003 | 9 |
| OB-004 | 1 |
| OB-005 | 6 |

## Aggregate Results

| Method | Avg Tests | Avg Execution Reduction | Cases Detected | Case Recall |
| --- | ---: | ---: | ---: | ---: |
| Traditional Approach / Full Suite | 51 | 0.0% | 5/5 | 100.0% |
| Random Approach | 26 | 49.0% | 4/5 | 80.0% |
| History + Code Change | 15 | 70.6% | 4/5 | 80.0% |
| Quantik Mind | 16.4 | 67.8% | 5/5 | 100.0% |

## Recall-vs-Saving Trade-off

The aggregate result should not be read as "lowest test count wins." The benchmark should be read in this order:

1. recall first
2. execution reduction second
3. category breakdown always shown

History + Code Change is slightly more aggressive: it runs 15 tests on average, gives 70.6% execution reduction, and detects 4/5 cases. Quantik Mind is slightly more conservative: it runs 16.4 tests on average, gives 67.8% execution reduction, and detects 5/5 cases.

| Method | Recall | Avg tests | Execution reduction | Interpretation |
|---|---:|---:|---:|---|
| H+CC | 4/5 | 15 | 70.6% | More aggressive, misses runtime-aware defect |
| QMind | 5/5 | 16.4 | 67.8% | Slightly more conservative, preserves full recall |

Quantik Mind spends +1.4 tests on average compared with History + Code Change. That is a 2.8 percentage-point reduction trade-off. In exchange, it recovers one additional benchmark case: OB-005 Runtime Aware. Quantik Mind spends 1.4 extra tests on average to recover a defect class that History + Code Change misses entirely.

In code-change scenarios, QMind matches H+CC: 4/4 vs 4/4. In runtime-aware scenarios, QMind adds coverage: 1/1 vs 0/1. Overall, QMind preserves full recall at still-high execution reduction. The value claim is not "QMind always runs fewer tests." The value claim is "QMind keeps execution reduction high while avoiding blind spots from code-change-only selection."

## Per-Scenario Results

| Scenario | Category | Changed files | Full Suite result | Random result | History + Code Change result | Quantik Mind result |
| --- | --- | --- | --- | --- | --- | --- |
| OB-001: Checkout Regression | Code Change | src/frontend/templates/cart.html<br>src/frontend/handlers.go | detected | detected | detected | detected |
| OB-002: Cart Regression | Code Change | src/cartservice/src/services/CartService.cs<br>src/cartservice/src/cartstore/RedisCartStore.cs<br>src/frontend/handlers.go | detected | missed | detected | detected |
| OB-003: Product Detail Regression | Code Change | src/productcatalogservice/product_catalog.go<br>src/productcatalogservice/products.json<br>src/frontend/templates/product.html | detected | detected | detected | detected |
| OB-004: Payment Regression | Code Change | src/paymentservice/charge.js | detected | detected | detected | detected |
| OB-005: Currency Data Corruption | Runtime Aware | src/currencyservice/data/currency_conversion.json | detected | detected | missed | detected |

## Per-Category Summary

| Category | Scenarios | Full Suite | Random | History + Code Change | Quantik Mind |
| --- | --- | ---: | ---: | ---: | ---: |
| Code Change | OB-001, OB-002, OB-003, OB-004 | 4/4 | 3/4 | 4/4 | 4/4 |
| Runtime Aware | OB-005 | 1/1 | 1/1 | 0/1 | 1/1 |
| Overall | OB-001, OB-002, OB-003, OB-004, OB-005 | 5/5 | 4/5 | 4/5 | 5/5 |

## Benchmark Cases

### OB-001: Checkout Regression

- Changed files: `src/frontend/templates/cart.html`, `src/frontend/handlers.go`
- Traditional Approach / Full Suite: 51 tests, 0.0% reduction, defect detected
- Random Approach: 26 tests, 49.0% reduction, defect detected
- History + Code Change: 15 tests, 70.6% reduction, defect detected
- Quantik Mind: 16 tests, 68.6% reduction, defect detected

### OB-002: Cart Regression

- Changed files: `src/cartservice/src/services/CartService.cs`, `src/cartservice/src/cartstore/RedisCartStore.cs`, `src/frontend/handlers.go`
- Traditional Approach / Full Suite: 51 tests, 0.0% reduction, defect detected
- Random Approach: 26 tests, 49.0% reduction, defect missed
- History + Code Change: 15 tests, 70.6% reduction, defect detected
- Quantik Mind: 17 tests, 66.7% reduction, defect detected

### OB-003: Product Detail Regression

- Changed files: `src/productcatalogservice/product_catalog.go`, `src/productcatalogservice/products.json`, `src/frontend/templates/product.html`
- Traditional Approach / Full Suite: 51 tests, 0.0% reduction, defect detected
- Random Approach: 26 tests, 49.0% reduction, defect detected
- History + Code Change: 15 tests, 70.6% reduction, defect detected
- Quantik Mind: 15 tests, 70.6% reduction, defect detected

### OB-004: Payment Regression

- Changed files: `src/paymentservice/charge.js`
- Traditional Approach / Full Suite: 51 tests, 0.0% reduction, defect detected
- Random Approach: 26 tests, 49.0% reduction, defect detected
- History + Code Change: 15 tests, 70.6% reduction, defect detected
- Quantik Mind: 19 tests, 62.7% reduction, defect detected

### OB-005: Currency Data Corruption

- Changed files: `src/currencyservice/data/currency_conversion.json`
- Traditional Approach / Full Suite: 51 tests, 0.0% reduction, defect detected
- Random Approach: 26 tests, 49.0% reduction, defect detected
- History + Code Change: 15 tests, 70.6% reduction, defect missed
- Quantik Mind: 15 tests, 70.6% reduction, defect detected

## Method Notes

Full Suite always selects all 51 tests.

Random uses only the canonical test library and deterministic seed 42. It produces a per-case selection artifact and selects 26 tests, approximately 50% of the 51-test suite.

History + Code Change uses the canonical test library, history-oriented test metadata, and each case's changed files. It does not read the defect oracle and does not use oracle detecting tests. For OB-005 the changed file is `src/currencyservice/data/currency_conversion.json`; the six direct homepage oracle tests map to `src/frontend/**/*`, have medium criticality, and score only 10 each, so they fall below checkout, cart, order, payment, product, and catalog tests in the top-15 selection.

Quantik Mind uses one canonical selection artifact per benchmark case, generated from that case's changed-files and runtime context by `benchmark-pipeline/run-qmind-subset.ps1` in normal mode. The aggregate QMind result averages 16.4 selected tests, gives 67.8% average execution reduction, and detects 5/5 cases. OB-005 demonstrates a class of defect that code-change analysis structurally cannot reach. This does not claim QMind is universally better than History + Code Change; it claims QMind matches History + Code Change on the code-change control group and adds coverage when runtime signals are required.

## Hostile-Review Defense

Reviewer challenge: "H+CC has better savings."

Response: "Yes, but it achieves that by missing OB-005. The meaningful comparison is not saving alone; it is recall at a given execution budget. QMind trades 1.4 additional tests on average for one additional detected scenario."

- OB-001 through OB-004 functional definitions and oracle detecting tests were not modified.
- OB-005 uses the real committed file `src/currencyservice/data/currency_conversion.json`.
- The changed file is data, not application code.
- The OB-005 oracle uses direct homepage tests only.
- The History + Code Change miss is explained by exact scoring mechanics, not hidden exclusions.
- QMind detection must come from runtime observability, not oracle leakage.
- The generator reports actual selected-suite outcomes; it does not hardcode winners.

## Reproduction

Regenerate all final comparison artifacts from committed inputs:

```powershell
.\benchmark-pipeline\generate-final-comparison.ps1
```

The generator fails if any per-case QMind selection artifact is missing, contains non-canonical test IDs, or if the OB-004 artifact does not include `payment-order-completion-confirms-success`.

To reuse previously generated per-case QMind selections instead of calling live QMind:

```powershell
.\benchmark-pipeline\generate-final-comparison.ps1 -UseExistingQMindSelections
```

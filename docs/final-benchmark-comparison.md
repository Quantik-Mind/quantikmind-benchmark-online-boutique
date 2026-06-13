# Final Benchmark Comparison

## Scope

This comparison models Online Boutique as six independent CI/CD benchmark cases. OB-001 through OB-004 are the code-change control group. OB-005 is the first runtime-aware scenario. OB-006 is the first combined-signal scenario, where code change and runtime observability point to different parts of the system. Each case has commit context, changed files, an injected defect, and oracle detecting tests. Selectors run before scoring and do not receive defect identity, oracle detecting tests, or expected benchmark outcomes.

- Canonical library: `qmind-test-library/online-boutique-playwright-51.json`
- Defect oracle: `defect-oracle/online-boutique-defect-oracle.v2.json`
- Oracle mode: `validated_detecting_tests`
- Generator: `benchmark-pipeline/generate-final-comparison.ps1`
- Random seed: 42
- Random size: 26 tests
- History + Code Change size: 15 tests per case
- QMind selection artifacts: `benchmark-runs/qmind-online-boutique/qmind-selection-ob-001.json` through `benchmark-runs/qmind-online-boutique/qmind-selection-ob-006.json`
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
| OB-006 | 6 |

## Aggregate Results

| Method | Avg Tests | Avg Execution Reduction | Cases Detected | Case Recall |
| --- | ---: | ---: | ---: | ---: |
| Traditional Approach / Full Suite | 51 | 0.0% | 6/6 | 100.0% |
| Random Approach | 26 | 49.0% | 5/6 | 83.3% |
| History + Code Change | 15 | 70.6% | 4/6 | 66.7% |
| Quantik Mind | 15.5 | 69.6% | 6/6 | 100.0% |

## Per-Scenario Results

| Scenario | Category | Changed files | Full Suite result | Random result | History + Code Change result | Quantik Mind result |
| --- | --- | --- | --- | --- | --- | --- |
| OB-001: Checkout Regression | Code Change | src/frontend/templates/cart.html<br>src/frontend/handlers.go | detected | detected | detected | detected |
| OB-002: Cart Regression | Code Change | src/cartservice/src/services/CartService.cs<br>src/cartservice/src/cartstore/RedisCartStore.cs<br>src/frontend/handlers.go | detected | missed | detected | detected |
| OB-003: Product Detail Regression | Code Change | src/productcatalogservice/product_catalog.go<br>src/productcatalogservice/products.json<br>src/frontend/templates/product.html | detected | detected | detected | detected |
| OB-004: Payment Regression | Code Change | src/paymentservice/charge.js | detected | detected | detected | detected |
| OB-005: Currency Data Corruption | Runtime Aware | src/currencyservice/data/currency_conversion.json | detected | detected | missed | detected |
| OB-006: Ad Service Latency Cascades Into Homepage Rendering | Combined Signal | src/adservice/src/main/java/hipstershop/AdService.java | detected | detected | missed | detected |

## Per-Category Summary

| Category | Scenarios | Full Suite | Random | History + Code Change | Quantik Mind |
| --- | --- | ---: | ---: | ---: | ---: |
| Code Change | OB-001, OB-002, OB-003, OB-004 | 4/4 | 3/4 | 4/4 | 4/4 |
| Runtime Aware | OB-005 | 1/1 | 1/1 | 0/1 | 1/1 |
| Combined Signal | OB-006 | 1/1 | 1/1 | 0/1 | 1/1 |
| Overall | OB-001, OB-002, OB-003, OB-004, OB-005, OB-006 | 6/6 | 5/6 | 4/6 | 6/6 |

## Quantik Mind Dynamic Risk Intelligence

Unlike baseline approaches, Quantik Mind also evaluates dynamic risk at selection time using historical signals, code changes and live runtime observability.

Observed Risk Coverage: How much of the currently observed risk mass is covered by the selected tests.

Critical Risk Captured: How much of the highest-priority risk band is captured by the selected tests.

Residual Risk: How much observed risk remains uncovered after the selected tests.

Risk Density: How much risk information is captured per executed test. A value above 1.0 means the selected tests are denser in risk information than the average test set.

Current QMind selection artifacts include dynamic risk diagnostics for 6 of 6 benchmark cases.

| Scenario | Observed Risk Coverage | Critical Risk Captured | Residual Risk | Risk Density |
| --- | ---: | ---: | ---: | ---: |
| OB-001 | 24.02% | 50.00% | 75.98% | 1.36x |
| OB-002 | 43.44% | 66.67% | 56.56% | 1.30x |
| OB-003 | 37.21% | 91.67% | 62.79% | 1.27x |
| OB-004 | 42.06% | 91.67% | 57.94% | 1.19x |
| OB-005 | 40.46% | 91.67% | 59.54% | 1.21x |
| OB-006 | 40.46% | 91.67% | 59.54% | 1.21x |

### How to interpret these risk metrics

Observed Risk Coverage is the percentage of currently observed system risk covered by the selected tests.

Critical Risk Captured is the percentage of the highest-priority risk band captured by the selected tests.

Residual Risk is the observed risk left uncovered after selection. This is not random leftover risk; it is mostly lower-priority risk that Quantik Mind intentionally leaves uncovered when the execution cost outweighs the expected value.

Risk Density is the amount of risk information captured per executed test. A value above 1.0 means the selected set is denser in risk information than an average test set.

In this benchmark, Quantik Mind executed 15.5 tests on average out of 51, reduced execution by 69.6%, detected 6/6 benchmark defects, and captured 80.56% of critical observed risk. This shows that Quantik Mind is not simply executing fewer tests; it is concentrating execution on the tests that cover the highest-value dynamic risk.

Full Suite executes everything and therefore does not prioritize risk. Random has no risk model. History + Code Change estimates risk from historical and code-change signals. Quantik Mind adds runtime observability, so it can evaluate risk based on what is happening in the system at selection time. The baseline approaches do not calculate dynamic runtime risk because they do not consume observability signals.

These metrics are not included in the benchmark comparison table because equivalent dynamic risk diagnostics are not available for Full Suite, Random, or History + Code Change. They are reported as Quantik Mind product diagnostics.

## Benchmark Cases

### OB-001: Checkout Regression

- Changed files: `src/frontend/templates/cart.html`, `src/frontend/handlers.go`
- Traditional Approach / Full Suite: 51 tests, 0.0% reduction, defect detected
- Random Approach: 26 tests, 49.0% reduction, defect detected
- History + Code Change: 15 tests, 70.6% reduction, defect detected
- Quantik Mind: 9 tests, 82.4% reduction, defect detected

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
- Quantik Mind: 18 tests, 64.7% reduction, defect detected

### OB-005: Currency Data Corruption

- Changed files: `src/currencyservice/data/currency_conversion.json`
- Traditional Approach / Full Suite: 51 tests, 0.0% reduction, defect detected
- Random Approach: 26 tests, 49.0% reduction, defect detected
- History + Code Change: 15 tests, 70.6% reduction, defect missed
- Quantik Mind: 17 tests, 66.7% reduction, defect detected

### OB-006: Ad Service Latency Cascades Into Homepage Rendering

- Changed files: `src/adservice/src/main/java/hipstershop/AdService.java`
- Traditional Approach / Full Suite: 51 tests, 0.0% reduction, defect detected
- Random Approach: 26 tests, 49.0% reduction, defect detected
- History + Code Change: 15 tests, 70.6% reduction, defect missed
- Quantik Mind: 17 tests, 66.7% reduction, defect detected

## Method Notes

Full Suite always selects all 51 tests.

Random uses only the canonical test library and deterministic seed 42. It produces a per-case selection artifact and selects 26 tests, approximately 50% of the 51-test suite.

History + Code Change uses the canonical test library, history-oriented test metadata, and each case's changed files. It does not read the defect oracle and does not use oracle detecting tests. For OB-005 the changed file is `src/currencyservice/data/currency_conversion.json`; the six direct homepage oracle tests map to `src/frontend/**/*`, have medium criticality, and score only 10 each, so they fall below checkout, cart, order, payment, product, and catalog tests in the top-15 selection. For OB-006 the changed file is `src/adservice/src/main/java/hipstershop/AdService.java`; the canonical 51-test library has no direct adservice tests, so the same homepage smoke tests are not reachable from code-change context alone.

Quantik Mind uses one canonical selection artifact per benchmark case, generated from that case's changed-files and runtime context by `benchmark-pipeline/run-qmind-subset.ps1` in normal mode. The aggregate QMind result averages 15.5 selected tests, gives 69.6% average execution reduction, and detects 6/6 cases. OB-005 demonstrates a runtime-aware defect class that code-change analysis structurally cannot reach. OB-006 adds a combined-signal defect class where the code change points to adservice while runtime observability points to frontend homepage impact. This does not claim QMind is universally better than History + Code Change; it claims QMind matches History + Code Change on the code-change control group and adds coverage when runtime or combined signals are required.

## Hostile-Review Defense

- OB-001 through OB-004 functional definitions and oracle detecting tests were not modified.
- OB-005 uses the real committed file `src/currencyservice/data/currency_conversion.json`.
- The changed file is data, not application code.
- The OB-005 oracle uses direct homepage tests only.
- OB-006 uses the real upstream file `src/adservice/src/main/java/hipstershop/AdService.java` through a reversible injector.
- The OB-006 oracle uses direct homepage tests only; there are no direct adservice tests in the canonical 51-test library.
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

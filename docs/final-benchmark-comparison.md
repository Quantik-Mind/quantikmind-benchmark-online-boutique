# Final Benchmark Comparison

## Scope

This comparison models Online Boutique as seven independent CI/CD benchmark cases. OB-001 through OB-004 are the code-change control group. OB-005 and OB-007 are runtime-aware scenarios where the changed file does not token-match the oracle test, so History + Code Change misses them. OB-006 is the combined-signal scenario. Each case has commit context, changed files, an injected defect, and oracle detecting tests. Selectors run before scoring and do not receive defect identity, oracle detecting tests, or expected benchmark outcomes.

- Canonical library: `qmind-test-library/online-boutique-playwright-51.json`
- Defect oracle: `defect-oracle/online-boutique-defect-oracle.v2.json`
- Oracle mode: `validated_detecting_tests`
- Generator: `benchmark-pipeline/generate-final-comparison.ps1`
- Random seed: 42
- Random size: 26 tests
- History + Code Change size: 15 tests per case
- QMind selection artifacts: `benchmark-results/qmind-selections/qmind-selection-ob-001.json` through `benchmark-results/qmind-selections/qmind-selection-ob-007.json`
- QMind selection mode: `generated-by-run-qmind-subset`
- OB-006 runtime evidence: `benchmark-results/runtime-evidence/ob-006`
- OB-007 runtime evidence: `benchmark-results/runtime-evidence/ob-007`

## Oracle Precision

The defect oracle uses minimal direct validated detecting tests for each benchmark case. Broad downstream symptom tests are excluded from the oracle even when they can fail as a side effect.

| Case | Direct Validated Detecting Tests |
| --- | ---: |
| OB-001 | 2 |
| OB-002 | 1 |
| OB-003 | 9 |
| OB-004 | 1 |
| OB-005 | 6 |
| OB-006 | 19 |
| OB-007 | 1 |

## Aggregate Results

| Method | Avg Tests | Avg Execution Reduction | Cases Detected | Case Recall |
| --- | ---: | ---: | ---: | ---: |
| Traditional Approach / Full Suite | 52 | 0.0% | 7/7 | 100.0% |
| Random Approach | 26 | 50.0% | 5/7 | 71.4% |
| History + Code Change | 15 | 71.2% | 5/7 | 71.4% |
| Quantik Mind | 19.3 | 62.9% | 7/7 | 100.0% |

## Per-Scenario Results

| Scenario | Category | Changed files | Full Suite result | Random result | History + Code Change result | Quantik Mind result |
| --- | --- | --- | --- | --- | --- | --- |
| OB-001: Checkout Regression | Code Change | src/frontend/templates/cart.html<br>src/frontend/handlers.go | detected | detected | detected | detected |
| OB-002: Cart Regression | Code Change | src/cartservice/src/services/CartService.cs<br>src/cartservice/src/cartstore/RedisCartStore.cs<br>src/frontend/handlers.go | detected | missed | detected | detected |
| OB-003: Product Detail Regression | Code Change | src/productcatalogservice/product_catalog.go<br>src/productcatalogservice/products.json<br>src/frontend/templates/product.html | detected | detected | detected | detected |
| OB-004: Payment Regression | Code Change | src/paymentservice/charge.js | detected | missed | detected | detected |
| OB-005: Currency Data Corruption | Runtime Aware | src/currencyservice/data/currency_conversion.json | detected | detected | missed | detected |
| OB-006: Product Catalog ListProducts Cascades Into Homepage Rendering | Combined Signal | src/productcatalogservice/product_catalog.go | detected | detected | detected | detected |
| OB-007: Recommendation Runtime Behavioral Degradation Causes Graceful Section Disappearance | Runtime Aware | src/recommendationservice/logger.py | detected | detected | missed | detected |

## Per-Category Summary

| Category | Scenarios | Full Suite | Random | History + Code Change | Quantik Mind |
| --- | --- | ---: | ---: | ---: | ---: |
| Code Change | OB-001, OB-002, OB-003, OB-004 | 4/4 | 2/4 | 4/4 | 4/4 |
| Runtime Aware | OB-005, OB-007 | 2/2 | 2/2 | 0/2 | 2/2 |
| Combined Signal | OB-006 | 1/1 | 1/1 | 1/1 | 1/1 |
| Overall | OB-001, OB-002, OB-003, OB-004, OB-005, OB-006, OB-007 | 7/7 | 5/7 | 5/7 | 7/7 |

## Quantik Mind Runtime Risk Analysis

Quantik Mind uses runtime observability as part of a broader multi-signal risk model. In the committed benchmark artifacts, selected tests expose dynamic risk fields — including observed risk coverage, critical risk captured, residual risk, and risk density — that reflect how the final selected suite was produced. These fields show Quantik Mind's internal risk view but should not be interpreted as proving that runtime observability was the sole cause of every selected test. Quantik Mind is a multi-signal selector that may combine runtime observability with code-change impact, historical evidence, service dependency context, adaptive entanglement, risk scoring, guardrails, and uncertainty handling.

The baseline selectors (Full Suite, Random, History + Code Change) do not produce a comparable dynamic runtime risk model. This is therefore a Quantik Mind product capability view, not an additional competitive scoring metric.

**Metric definitions:**

- **Observed Risk Coverage**: Percentage of currently observed system risk mass covered by the selected tests.
- **Critical Risk Captured**: Percentage of the highest-priority risk band captured by the selected tests.
- **Residual Risk**: Observed risk that remains uncovered after the selected tests run. This is not random leftover risk and is not expected to be zero; it is mostly lower-priority risk intentionally left uncovered when execution cost outweighs expected value.
- **Risk Density**: Risk information captured per executed test. A value above 1.0 means the selected tests are denser in risk information than the average test set would be.

The committed QMind selection artifacts include dynamic risk diagnostics for all 7 of 7 benchmark cases, sourced from the `business_metrics` fields in each `benchmark-results/qmind-selections/qmind-selection-ob-*.json` artifact.

**Aggregate (across 7 benchmark cases):**

| Metric | Average |
| --- | ---: |
| Observed Risk Coverage | 45.2% |
| Critical Risk Captured | 72.5% |
| Residual Risk | 54.8% |
| Risk Density | 1.23 |

**Per-scenario:**

| Scenario | Observed Risk Coverage | Critical Risk Captured | Residual Risk | Risk Density |
| --- | ---: | ---: | ---: | ---: |
| OB-001 | 42.2% | 38.5% | 57.8% | 1.22 |
| OB-002 | 38.7% | 84.6% | 61.3% | 1.34 |
| OB-003 | 39.1% | 76.9% | 60.9% | 1.27 |
| OB-004 | 47.7% | 76.9% | 52.3% | 1.18 |
| OB-005 | 48.6% | 84.6% | 51.4% | 1.20 |
| OB-006 | 50.3% | 61.5% | 49.7% | 1.19 |
| OB-007 | 50.0% | 84.6% | 50.0% | 1.18 |

These metrics are not included in the main benchmark comparison table because the other selectors do not produce a comparable dynamic runtime risk model. They are Quantik Mind product diagnostics derived from the committed selection artifacts.

## Benchmark Cases

### OB-001: Checkout Regression

- Changed files: `src/frontend/templates/cart.html`, `src/frontend/handlers.go`
- Traditional Approach / Full Suite: 52 tests, 0.0% reduction, defect detected
- Random Approach: 26 tests, 50.0% reduction, defect detected
- History + Code Change: 15 tests, 71.2% reduction, defect detected
- Quantik Mind: 18 tests, 65.4% reduction, defect detected

### OB-002: Cart Regression

- Changed files: `src/cartservice/src/services/CartService.cs`, `src/cartservice/src/cartstore/RedisCartStore.cs`, `src/frontend/handlers.go`
- Traditional Approach / Full Suite: 52 tests, 0.0% reduction, defect detected
- Random Approach: 26 tests, 50.0% reduction, defect missed
- History + Code Change: 15 tests, 71.2% reduction, defect detected
- Quantik Mind: 15 tests, 71.2% reduction, defect detected

### OB-003: Product Detail Regression

- Changed files: `src/productcatalogservice/product_catalog.go`, `src/productcatalogservice/products.json`, `src/frontend/templates/product.html`
- Traditional Approach / Full Suite: 52 tests, 0.0% reduction, defect detected
- Random Approach: 26 tests, 50.0% reduction, defect detected
- History + Code Change: 15 tests, 71.2% reduction, defect detected
- Quantik Mind: 16 tests, 69.2% reduction, defect detected

### OB-004: Payment Regression

- Changed files: `src/paymentservice/charge.js`
- Traditional Approach / Full Suite: 52 tests, 0.0% reduction, defect detected
- Random Approach: 26 tests, 50.0% reduction, defect missed
- History + Code Change: 15 tests, 71.2% reduction, defect detected
- Quantik Mind: 21 tests, 59.6% reduction, defect detected

### OB-005: Currency Data Corruption

- Changed files: `src/currencyservice/data/currency_conversion.json`
- Traditional Approach / Full Suite: 52 tests, 0.0% reduction, defect detected
- Random Approach: 26 tests, 50.0% reduction, defect detected
- History + Code Change: 15 tests, 71.2% reduction, defect missed
- Quantik Mind: 21 tests, 59.6% reduction, defect detected

### OB-006: Product Catalog ListProducts Cascades Into Homepage Rendering

- Changed files: `src/productcatalogservice/product_catalog.go`
- Traditional Approach / Full Suite: 52 tests, 0.0% reduction, defect detected
- Random Approach: 26 tests, 50.0% reduction, defect detected
- History + Code Change: 15 tests, 71.2% reduction, defect detected
- Quantik Mind: 22 tests, 57.7% reduction, defect detected

### OB-007: Recommendation Runtime Behavioral Degradation Causes Graceful Section Disappearance

- Changed files: `src/recommendationservice/logger.py`
- Traditional Approach / Full Suite: 52 tests, 0.0% reduction, defect detected
- Random Approach: 26 tests, 50.0% reduction, defect detected
- History + Code Change: 15 tests, 71.2% reduction, defect missed
- Quantik Mind: 22 tests, 57.7% reduction, defect detected

## Method Notes

Full Suite always selects all 52 tests from the canonical library.

Random uses only the canonical test library and deterministic seed 42. It produces a per-case selection artifact and selects 26 tests, exactly 50% of the 52-test suite.

History + Code Change uses the canonical test library, history-oriented test metadata, and each case's changed files. It does not read the defect oracle and does not use oracle detecting tests. For OB-005 the changed file is `src/currencyservice/data/currency_conversion.json`; the six direct homepage oracle tests map to `src/frontend/**/*`, have medium criticality, and score only 10 each, so they fall below checkout, cart, order, payment, product, and catalog tests in the top-15 selection. For OB-006 the changed file is `src/productcatalogservice/product_catalog.go`; QMind must use the productcatalogservice code-change signal together with live frontend impact rather than oracle detecting tests.

Quantik Mind uses one canonical selection artifact per benchmark case, generated from that case's changed-files and runtime context by `benchmark-pipeline/run-qmind-subset.ps1` in normal mode. The aggregate QMind result averages 19.3 selected tests, gives 62.9% average execution reduction, and detects 7/7 cases. OB-005 demonstrates a runtime-aware defect class that code-change analysis structurally cannot reach. OB-006 adds a combined-signal defect class where the code change points to productcatalogservice while runtime observability points to frontend homepage/product-grid impact. This does not claim QMind is universally better than History + Code Change; it claims QMind matches History + Code Change on the code-change control group and preserves coverage for the combined-signal case while adding coverage for the runtime-aware case.

OB-006 is included in the headline aggregate only when `benchmark-pipeline/generate-final-comparison.ps1` can validate tracked runtime evidence under `benchmark-results/runtime-evidence/ob-006`. That evidence must show material productcatalogservice movement and material frontend movement in the same validation window, and the OB-006 QMind artifact must not be substantively identical to OB-005. QMind selected OB-006 from the productcatalogservice changed-file input plus runtime observability evidence, not from oracle detecting tests.

## Benchmark Integrity Controls

- OB-001 through OB-004 functional definitions and oracle detecting tests were not modified.
- OB-005 uses the real committed file `src/currencyservice/data/currency_conversion.json`.
- The changed file is data, not application code.
- The OB-005 oracle uses direct homepage tests only.
- OB-006 uses the real upstream file `src/productcatalogservice/product_catalog.go` through a reversible injector.
- The OB-006 oracle uses 19 homepage, product-grid, catalog, and product-detail detectors for the ProductCatalog ListProducts cascade.
- OB-006 runtime evidence is stored under `benchmark-results/runtime-evidence/ob-006` and is required by the final comparison generator.
- The History + Code Change miss is explained by exact scoring mechanics, not hidden exclusions.
- QMind detection must come from runtime observability, not oracle leakage.
- The generator reports actual selected-suite outcomes; it does not hardcode winners.

## Reproduction

Regenerate all final comparison artifacts using live QMind plus committed benchmark inputs:

```powershell
.\benchmark-pipeline\generate-final-comparison.ps1
```

The generator fails if any per-case QMind selection artifact is missing, contains non-canonical test IDs, or if the OB-004 artifact does not include `payment-order-completion-confirms-success`.

To reuse committed canonical per-case QMind selections instead of calling live QMind:

```powershell
.\benchmark-pipeline\generate-final-comparison.ps1 -UseExistingQMindSelections
```

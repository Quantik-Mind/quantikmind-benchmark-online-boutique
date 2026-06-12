# Final Benchmark Comparison

## Scope

This comparison models Online Boutique as four independent CI/CD benchmark cases. Each case has commit context, changed files, an injected defect, and oracle detecting tests. Selectors run before scoring and do not receive defect identity, oracle detecting tests, or expected benchmark outcomes.

- Canonical library: `qmind-test-library/online-boutique-playwright-51.json`
- Defect oracle: `defect-oracle/online-boutique-defect-oracle.v2.json`
- Oracle mode: `validated_detecting_tests`
- Generator: `benchmark-pipeline/generate-final-comparison.ps1`
- Random seed: 42
- Random size: 26 tests
- History + Code Change size: 15 tests per case
- QMind selection artifacts: `benchmark-runs/qmind-online-boutique/qmind-selection-ob-001.json` through `benchmark-runs/qmind-online-boutique/qmind-selection-ob-004.json`
- QMind selection mode: `generated-by-run-qmind-subset`

## Oracle Precision

The defect oracle uses minimal direct validated detecting tests for each benchmark case. Broad downstream symptom tests are excluded from the oracle even when they can fail as a side effect.

| Case | Direct Validated Detecting Tests |
| --- | ---: |
| OB-001 | 2 |
| OB-002 | 1 |
| OB-003 | 9 |
| OB-004 | 1 |

## Aggregate Results

| Method | Avg Tests | Avg Execution Reduction | Cases Detected | Case Recall |
| --- | ---: | ---: | ---: | ---: |
| Traditional Approach / Full Suite | 51 | 0.0% | 4 / 4 | 100.0% |
| Random Approach | 26 | 49.0% | 3 / 4 | 75.0% |
| History + Code Change | 15 | 70.6% | 4 / 4 | 100.0% |
| Quantik Mind | 16.8 | 67.2% | 4 / 4 | 100.0% |

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

## Method Notes

Full Suite always selects all 51 tests.

Random uses only the canonical test library and deterministic seed 42. It produces a per-case selection artifact and selects 26 tests, approximately 50% of the 51-test suite.

History + Code Change uses the canonical test library, history-oriented test metadata, and each case's changed files. It does not read the defect oracle and does not use oracle detecting tests.

Quantik Mind uses one canonical selection artifact per benchmark case, generated from that case's changed-files context by `benchmark-pipeline/run-qmind-subset.ps1` in normal mode. The aggregate QMind result averages 16.8 selected tests, gives 67.2% average execution reduction, detects 4/4 cases, and requires OB-004 to include `payment-order-completion-confirms-success`.

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

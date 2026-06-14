# Defect-Recall Benchmark Scenarios

## 1. Benchmark Goal

This benchmark evaluates whether Quantik Mind can execute fewer Playwright tests while still detecting the same defects as the full suite.

The central question is:

```text
Can Quantik Mind execute fewer tests while still detecting the same defects as the full suite?
```

The main KPI is defect recall:

```text
defects_detected_by_selected_tests / defects_detected_by_full_suite
```

The selection methods to compare are:

1. Full Suite
2. Random same-size selection
3. Historical Risk Selection
4. Quantik Mind selection

The benchmark should report both defect recall and execution reduction:

```text
execution_reduction = 1 - selected_test_count / full_suite_test_count
```

## 2. Repository Boundary

This repository is the benchmark scaffold. It owns the benchmark harness, qmind configuration, test library metadata, defect oracle, pipeline scripts, runtime scenario assets, and benchmark documentation.

The upstream Google Online Boutique source repository is intentionally not committed here. A local `microservices-demo` clone may exist beside the benchmark assets for development and validation, but it is external state and must not be treated as part of this repository.

Do not commit:

- `microservices-demo/`
- `node_modules/`
- `benchmark-runs/`
- `runtime-snapshots/`
- `test-results/`
- Playwright reports
- raw generated qmind outputs
- external application build or deployment artifacts

The defect scenarios should be implemented later as Git states in the external Online Boutique repository, not by vendoring application code into this benchmark repo.

## 3. Test/Domain Mapping

The Playwright suite under `qmind-test-harness/playwright/tests` currently contains 52 E2E tests (the canonical library `qmind-test-library/online-boutique-playwright-51.json` uses a historical name but holds 52 entries). The following grouping should be used as the benchmark's domain map.

### Frontend / Catalog Browsing

- `smoke-homepage-loads`
- `smoke-product-links-visible`
- `frontend-homepage-has-product-grid`
- `catalog-multiple-products-visible`
- `catalog-first-product-link-has-valid-href`
- `frontend-page-has-navigation-links`
- `homepage-shows-google-cloud-branding`
- `cart-link-is-reachable-from-homepage`
- `homepage-has-visible-text-content`
- `frontend-logo-or-home-link-visible`
- `frontend-products-have-prices`
- `frontend-page-loads-under-basic-navigation`
- `homepage-body-is-not-empty`
- `homepage-contains-product-price`
- `homepage-has-at-least-one-product-link`
- `homepage-has-multiple-links`
- `homepage-title-is-available`
- `frontend-static-assets-do-not-break-homepage`
- `navigation-cart-to-home`

### Product Catalog / Product Detail

- `catalog-open-first-product-detail`
- `catalog-product-detail-has-price`
- `product-detail-page-has-body-content`
- `product-detail-allows-return-navigation`
- `catalog-product-detail-can-be-opened-twice`
- `catalog-product-detail-keeps-product-context`
- `catalog-product-link-href-starts-with-product`
- `catalog-first-product-opens-detail-page`
- `product-detail-page-has-add-to-cart-button`
- `product-detail-page-has-price`
- `product-detail-page-has-non-empty-body`
- `product-detail-refresh-keeps-content`
- `navigation-home-to-product-to-home`
- `catalog-two-product-links-visible-if-present`

### Cart

- `cart-add-product-from-detail-page`
- `cart-page-is-accessible`
- `cart-empty-page-shows-cart-context`
- `cart-add-product-and-view-cart`
- `cart-survives-home-navigation`
- `cart-page-loads-without-product`
- `cart-page-has-cart-context`
- `cart-add-from-product-detail-shows-cart-context`
- `cart-add-from-product-detail-keeps-price-context`
- `frontend-basic-user-journey-home-product-cart`

### Checkout

- `checkout-page-accessible-from-cart`
- `checkout-form-fields-visible`
- `checkout-empty-cart-does-not-complete-order`
- `checkout-page-does-not-crash-with-empty-cart`
- `order-flow-does-not-complete-with-empty-data`

### Payment

- `payment-order-completion-confirms-success`
- `order-form-requires-payment-data`
- `order-complete-happy-path`

### Order / Business Flow

- `order-complete-happy-path`
- `frontend-basic-user-journey-home-product-cart`
- `cart-add-product-and-view-cart`
- `checkout-page-accessible-from-cart`
- `checkout-form-fields-visible`

## 4. Scenario Catalog

The benchmark uses seven independent benchmark cases:

- `OB-001 Checkout Regression`
- `OB-002 Cart Regression`
- `OB-003 Product Detail Regression`
- `OB-004 Payment Regression`
- `OB-005 Currency Data Corruption`
- `OB-006 Product Catalog ListProducts Cascades Into Homepage Rendering`
- `OB-007 Recommendation Runtime Behavioral Degradation Causes Graceful Section Disappearance`

Each scenario should be represented by a separate branch or tag in the external Online Boutique repository. Each scenario should contain exactly one intentionally introduced defect.

## 5. Scenario Details

### OB-001 Checkout Regression

Target domain:

- Checkout page and checkout frontend flow.

Validated upstream file:

- `src/frontend/templates/cart.html`

Defect behavior:

- After a product is added to the cart, the checkout form no longer renders the required checkout fields or actions.
- The defect should preserve homepage, product listing, and basic cart access so the failure signal remains checkout-specific.
- A deterministic UI-level break is preferred over a crash or timing-sensitive service failure.

Expected failing tests:

- `checkout-page-accessible-from-cart`
- `checkout-form-fields-visible`
- `order-complete-happy-path`
- `order-form-requires-payment-data`

Expected unaffected tests:

- Homepage smoke tests.
- Catalog browsing tests.
- Product detail price/link tests.
- Empty-cart tests.
- Basic cart accessibility tests.

Risk notes:

- Historical validation on 2026-06-11 used the then-current 50-test Playwright suite: 4 failed, 46 passed. The current canonical benchmark library has 52 tests.
- Validated external scenario commit `e5234240` against baseline commit `5096a85b`.
- If implemented by renaming only one label, the signal may be too narrow.
- If implemented as a service crash, unrelated tests may fail through HTTP 500s or slow recovery.

### OB-002 Cart Regression

Target domain:

- Cart service and add-to-cart flow.

Expected upstream files to modify later:

- `src/cartservice/src/services/CartService.cs`
- Optional: `src/cartservice/src/cartstore/RedisCartStore.cs`
- Optional alternative: `src/frontend/handlers.go`

Defect behavior:

- Adding a product to the cart fails deterministically.
- The preferred implementation is for `AddItem` to return a service error instead of storing the item.
- A silent no-op should be avoided because several tests only assert generic cart text and may still pass on an empty-cart page.

Expected failing tests:

- `cart-add-product-from-detail-page`
- `cart-add-product-and-view-cart`
- `cart-add-from-product-detail-shows-cart-context`
- `cart-add-from-product-detail-keeps-price-context`
- `frontend-basic-user-journey-home-product-cart`
- `checkout-page-accessible-from-cart`
- `checkout-form-fields-visible`
- `order-complete-happy-path`

Validated failing tests:

- `checkout-page-accessible-from-cart`
- `checkout-form-fields-visible`
- `order-complete-happy-path`
- `order-form-requires-payment-data`
- `cart-add-from-product-detail-keeps-price-context`

Validation notes:

- Historical validation on 2026-06-11 used the then-current 50-test Playwright suite: 5 failed, 45 passed. The current canonical benchmark library has 52 tests.
- Validated external scenario commit `f7bac607` against baseline commit `5096a85b`.
- Only one direct cart assertion failed; several expected cart tests remained green, so broad/soft cart tests should not be treated as validated detecting tests.

Expected unaffected tests:

- Homepage tests.
- Product detail tests that stop before cart mutation.
- Empty cart page tests.
- Catalog link and price tests.

Risk notes:

- If the defect silently drops cart state, some current tests may still pass because empty-cart pages contain cart-related words.
- A service error gives a clearer detection signal but may create frontend error-page assertions in multiple tests.
- This scenario is expected to have a medium-to-broad failure signal because checkout and order flows depend on cart state.

### OB-003 Product Detail Regression

Target domain:

- Product catalog service and product detail pages.

Expected upstream files to modify later:

- `src/productcatalogservice/product_catalog.go`
- Optional: `src/productcatalogservice/products.json`
- Optional: `src/frontend/templates/product.html`

Defect behavior:

- Product detail lookup for valid product IDs fails or returns unusable product data.
- Homepage product listing should remain intact.
- The preferred implementation is to break `GetProduct` while leaving `ListProducts` healthy.

Expected failing tests:

- `catalog-open-first-product-detail`
- `catalog-product-detail-has-price`
- `cart-add-product-from-detail-page`
- `checkout-page-accessible-from-cart`
- `checkout-form-fields-visible`
- `order-complete-happy-path`
- `order-form-requires-payment-data`
- `catalog-product-detail-can-be-opened-twice`
- `catalog-product-detail-keeps-product-context`
- `cart-add-product-and-view-cart`
- `cart-survives-home-navigation`
- `catalog-first-product-opens-detail-page`
- `product-detail-page-has-add-to-cart-button`
- `product-detail-page-has-price`
- `product-detail-page-has-non-empty-body`
- `product-detail-refresh-keeps-content`
- `cart-add-from-product-detail-shows-cart-context`
- `cart-add-from-product-detail-keeps-price-context`
- `navigation-home-to-product-to-home`
- `frontend-basic-user-journey-home-product-cart`

Expected unaffected tests:

- Homepage load tests.
- Product links visible tests.
- Multiple products visible tests.
- Homepage price tests, if `ListProducts` remains intact.
- Empty cart tests.

Risk notes:

- Breaking product data globally may also break homepage tests and make the scenario too broad.
- Changing only product template text may create a frontend-only scenario rather than a product catalog scenario.
- The cleanest signal is a deterministic `GetProduct` regression with product listing preserved.

Validation notes:

- Historical validation on 2026-06-11 used the then-current 50-test Playwright suite: 20 failed, 30 passed. The current canonical benchmark library has 52 tests.
- External scenario commit `381043a6`; baseline commit `5096a85b`.
- Failure scope is product detail and downstream flows depending on product detail; homepage/catalog listing remained sufficiently healthy because 30 tests passed.

### OB-004 Payment Regression

Target domain:

- Payment authorization and checkout/payment integration.

Expected upstream files to modify later:

- `src/paymentservice/charge.js`

Defect behavior:

- `paymentservice` `Charge` always fails, so valid Visa/Mastercard payments are rejected.
- Cart, checkout form rendering, shipping quote, and product browsing should remain healthy.
- The preferred implementation is to reject otherwise valid cards after normal validation in `charge.js`.

Expected failing tests:

- `payment-order-completion-confirms-success`

Validated failing tests:

- `payment-order-completion-confirms-success`

Validation notes:

- Validated on 2026-06-11 against the then-current 51-test Playwright suite: 1 failed, 50 passed.
- Baseline validation passed with 51 passed at that time.
- Validated external scenario commit `b7ecc963` on `benchmark/scenario-ob004`.
- Failing test: `payment-order-completion-confirms-success`.
- OB-004 originally exposed a real coverage gap: the payment service failed correctly, but the previous benchmark suite did not verify successful payment completion.
- The new payment-aware test now detects the regression.

Expected unaffected tests:

- Homepage tests.
- Catalog and product detail tests.
- Cart add/view tests.
- Checkout form visibility tests.
- Empty-cart negative tests.

Risk notes:

- This is intentionally narrow and depends heavily on a payment-aware successful order assertion.
- Payment validation has date-sensitive logic, so tests should avoid relying on expiration edge cases.
- If `payment-order-completion-confirms-success` is flaky, this scenario becomes unreliable; baseline stability matters.

### OB-005 Currency Data Corruption

OB-005 is the first runtime-aware scenario. It corrupts the real committed Online Boutique data file `src/currencyservice/data/currency_conversion.json` by zeroing or corrupting the USD exchange rate.

The changed file is not application code. Under standard traffic, the expected runtime effect is elevated currencyservice error rate plus elevated frontend error rate because homepage price rendering depends on currency conversion. The expected user-visible effect is that the homepage fails to load correctly or renders invalid content.

The direct oracle is limited to homepage tests:

- `smoke-homepage-loads`
- `homepage-body-is-not-empty`
- `homepage-title-is-available`
- `homepage-has-visible-text-content`
- `homepage-shows-google-cloud-branding`
- `homepage-has-multiple-links`

This scenario demonstrates a class of defects that code-change-only selection cannot reach structurally. History + Code Change sees `src/currencyservice/data/currency_conversion.json`; the direct homepage oracle tests map to `src/frontend/**/*`, have medium criticality, and do not contain high-risk ID keywords. Their score is therefore only 10, below the top-15 checkout/cart/order/payment/product/catalog-heavy tests. QMind should detect OB-005 only through runtime observability, not oracle leakage.

### OB-006 Product Catalog ListProducts Cascades Into Homepage Rendering

OB-006 is the first combined-signal scenario. It injects deterministic latency or failure into the upstream Online Boutique file `src/productcatalogservice/product_catalog.go`.

The code-change signal points to `productcatalogservice`, but the direct user-visible failure is frontend homepage/product-grid rendering. The scenario is defensible only when runtime evidence shows both sides of the cascade: elevated productcatalogservice latency and/or errors, plus elevated frontend latency and/or homepage rendering failure during the same traffic window.

Product catalog listing is homepage-critical because `homeHandler` calls `getProducts`, which calls `ProductCatalogService/ListProducts`; a failure there returns an error before the product grid is built.

The direct oracle contains 19 homepage, product-grid, catalog, and product-detail detectors:

- `frontend-homepage-has-product-grid`
- `frontend-products-have-prices`
- `homepage-contains-product-price`
- `homepage-has-at-least-one-product-link`
- `smoke-product-links-visible`
- `catalog-multiple-products-visible`
- `catalog-first-product-link-has-valid-href`
- `catalog-product-link-href-starts-with-product`
- `catalog-open-first-product-detail`
- `catalog-product-detail-has-price`
- `catalog-product-detail-can-be-opened-twice`
- `catalog-product-detail-keeps-product-context`
- `catalog-first-product-opens-detail-page`
- `product-detail-page-has-body-content`
- `product-detail-allows-return-navigation`
- `product-detail-page-has-add-to-cart-button`
- `product-detail-page-has-price`
- `product-detail-page-has-non-empty-body`
- `product-detail-refresh-keeps-content`

History + Code Change sees `src/productcatalogservice/product_catalog.go` without runtime observability or oracle detecting tests. QMind should detect OB-006 only by combining the productcatalogservice code-change context with runtime observability showing frontend homepage/product-grid impact.

## 6. External Online Boutique Branch/Tag Strategy

Use Git states in the external Online Boutique repository as the reproducibility model.

Baseline:

- `benchmark-baseline`

Scenario branches or tags:

- `benchmark/scenario-ob001`
- `benchmark/scenario-ob002`
- `benchmark/scenario-ob003`
- `benchmark/scenario-ob004`

Recommended flow:

1. Choose a known-good upstream Online Boutique commit.
2. Deploy it and run the full Playwright suite.
3. If the baseline is sufficiently stable, tag it as `benchmark-baseline`.
4. Create each scenario branch from `benchmark-baseline`.
5. Introduce exactly one defect per scenario branch.
6. Deploy each scenario branch independently.
7. Run the full Playwright suite against each scenario.
8. Store generated raw results under ignored benchmark run directories.
9. Copy only the validated failure sets into the committed defect oracle.

Scenario branches should not stack defects on top of each other.

## 7. Defect Oracle Strategy

The current oracle has evolved from generic service defects into scenario-specific entries for `OB-001` through `OB-007`.

Each scenario entry should include:

- Scenario ID.
- Scenario name.
- External branch or tag.
- Target service/domain.
- Expected upstream changed files.
- Validated full-suite failing tests.
- Expected unaffected tests.
- Severity.
- Notes about flaky or ambiguous tests.

The oracle should use validated full-suite failures as the source of truth:

```text
full_suite_detecting_tests = tests that fail when the full suite runs against the scenario branch
```

A selected suite detects a scenario when:

```text
selected_tests intersects full_suite_detecting_tests
```

Predicted failing tests are useful during design, but the final oracle should be based on observed full-suite behavior.

## 8. Recall Metric Strategy

For each scenario and each selection method:

1. Load the scenario's validated full-suite failing tests from the oracle.
2. Load the selected tests for the method.
3. Compute the intersection between selected tests and full-suite failing tests.
4. Mark the scenario detected if the intersection is non-empty.

Per-scenario recall:

```text
1 if selected_tests intersects full_suite_detecting_tests else 0
```

Overall defect recall:

```text
detected_scenarios / scenarios_detected_by_full_suite
```

Because each scenario should contain exactly one defect, the denominator is seven after all current benchmark scenarios are validated:

```text
detected_scenarios / 7
```

Execution reduction should be reported beside recall:

```text
1 - selected_test_count / full_suite_test_count
```

The comparison should include:

- Full Suite: all tests, expected recall 1.0 for validated scenarios.
- Random same-size selection: deterministic seed, same selected count as Quantik Mind for the comparable run.
- Historical Risk Selection: deterministic service/domain/risk baseline using metadata, changed files, and historical failure data.
- Quantik Mind selection: normalized from qmind output using the benchmark pipeline.

## 9. Benchmark Artifacts Strategy

Files that should be committed here later:

- Scenario documentation.
- Scenario metadata, for example `benchmark-pipeline/scenarios.json`.
- Scenario-specific oracle, for example `defect-oracle/online-boutique-defect-oracle.v2.json`.
- Recall evaluator, for example `benchmark-pipeline/evaluate-defect-recall.py`.
- Comparator selection scripts for random same-size and historical risk selection.
- README or report template describing how to run the matrix.

Files that should remain generated and ignored:

- `benchmark-runs/**`
- `runtime-snapshots/**`
- `qmind-test-harness/playwright/test-results/**`
- Playwright HTML/blob reports.
- raw qmind output.
- selected-test output files.
- deployed application logs.
- external `microservices-demo/**`.

No `.gitignore` change is currently required for this plan.

## 10. Implementation Order

1. Validate the external Online Boutique baseline.
   - Deploy the external app at the intended baseline.
   - Run the full 52-test Playwright suite.
   - Identify unstable or invalid baseline tests before introducing defects.

2. Freeze canonical test metadata.
   - Use the 52-test Playwright library for the final recall benchmark.
   - Correct service/domain metadata if needed before final evaluation.

3. Create scenario metadata in the benchmark repo.
   - Record scenario IDs, branch names, target domains, and expected changed files.

4. Implement scenario branches in the external Online Boutique repo.
   - One defect per branch.
   - Do not vendor application code into this repository.

5. Run the full suite against each scenario branch.
   - Save raw output only under ignored generated directories.
   - Convert observed failures into oracle entries.

6. Implement scenario-aware recall evaluation.
   - Evaluate selected tests against validated full-suite detecting tests.
   - Report recall and execution reduction together.

7. Implement comparator methods.
   - Full suite.
   - Random same-size selection.
   - Historical risk selection.
   - Quantik Mind normalized selection.

8. Run the full benchmark matrix.
   - Seven benchmark cases by four selection methods.
   - Keep raw outputs ignored.
   - Commit only source, config, oracle, and documentation.

## 11. Risks and Mitigations

Risk: Some tests are broad and may pass despite a defect.

Mitigation: Use full-suite observed failures as the oracle, not predictions alone.

Risk: Some baseline tests may already be unstable or invalid.

Mitigation: Run and review the baseline before creating scenario branches. Exclude or fix unstable benchmark tests in a separate, explicit change if needed.

Risk: Cart no-op defects may not be detected because current assertions check generic cart text.

Mitigation: Prefer deterministic cart service errors for OB-002, or later strengthen cart assertions in a separate change.

Risk: Product catalog defects can become too broad if homepage listing is broken.

Mitigation: Prefer breaking `GetProduct` while preserving `ListProducts`.

Risk: Payment regression has a narrow signal.

Mitigation: Treat the narrowness as intentional, but ensure `order-complete-happy-path` is stable and high priority in test metadata.

Risk: Generated outputs or external app files could be committed accidentally.

Mitigation: Keep generated paths ignored and run `git status --short` before any commit.

Risk: qmind library metadata may not accurately represent all 52 tests.

Mitigation: Review and correct the 52-test library metadata before final benchmark runs, especially service mappings inferred from test names.

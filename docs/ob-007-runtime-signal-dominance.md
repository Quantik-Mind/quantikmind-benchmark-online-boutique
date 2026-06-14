# OB-007 Runtime Signal Dominance — Scenario Design

## Purpose

Demonstrate that runtime observability can materially change test selection beyond History + Code Change. Specifically: show a scenario where a code change in Service A causes runtime degradation in Service B, History + Code Change focuses on Service A and misses, and Quantik Mind detects by selecting Service B tests driven by runtime metrics.

OB-005 established runtime-aware detection via historical entanglement. OB-006 validated combined-signal evidence but did not differentiate from History + Code Change. OB-007 must show a case where runtime metrics — RPC call rate, CPU utilization, p99 latency — drive QMind to select tests that H+CC structurally cannot reach given the changed file.

---

## A. Scenario Description

The recommendation service receives a "quality improvement" commit that replaces its single `ListProducts` bulk fetch with one `ListProducts` call followed by N individual `GetProduct` calls — one per catalog product — to enable richer per-product recommendation scoring before filtering to five results.

This changes the RPC fan-out from 1 call per `ListRecommendations` request to approximately 19 calls (1 `ListProducts` + 18 `GetProduct`), multiplying `productcatalogservice`'s `GetProduct` load by roughly 18× under production traffic.

Under load-generator traffic (~10–20 concurrent users), `productcatalogservice` saturates on the `GetProduct` handler: CPU spikes, p99 latency climbs, and product-detail pages begin failing with timeouts or errors. `ListProducts` (used by the homepage product grid) remains functional because it issues only ~10 calls/second versus ~180 GetProduct calls/second from the fan-out.

The homepage and catalog listing appear healthy. Product detail pages are broken. The defect passes code review because "fetch full metadata for richer recommendation scoring" is a plausible feature intent.

---

## B. Service Chosen for Code Change

`recommendationservice` (Python)

Changed file: `src/recommendationservice/recommendation_server.py`

---

## C. Service Chosen for Runtime Degradation

`productcatalogservice` (Go)

Specifically the `GetProduct` RPC handler, which is overwhelmed by the recommendation fan-out. The `ListProducts` handler experiences moderate CPU contention but remains within acceptable latency for homepage rendering.

---

## D. Exact Injected Defect

In `ListRecommendations`, replace the current single-`ListProducts` implementation with a `ListProducts` + N sequential `GetProduct` calls pattern:

```python
def ListRecommendations(self, request, context):
    max_responses = 5
    # Enhancement: fetch full product metadata for richer recommendation scoring
    cat_response = self.stub.ListProducts(demo_pb2.Empty())
    enriched = []
    for p in cat_response.products:
        try:
            detail = self.stub.GetProduct(
                demo_pb2.GetProductRequest(id=p.id),
                timeout=5.0
            )
            enriched.append(detail)
        except grpc.RpcError:
            pass
    filtered = [p.id for p in enriched if p.id != request.product_id]
    sample = random.sample(filtered, min(len(filtered), max_responses))
    return demo_pb2.ListRecommendationsResponse(product_ids=sample)
```

Net effect: 1 `ListProducts` + 18 `GetProduct` RPCs per `ListRecommendations` call instead of 1 `ListProducts` only. The output (5 product IDs) is functionally correct. Unit and integration tests that verify recommendation output pass. The defect is a load efficiency regression, not a correctness regression.

---

## E. Expected Runtime Signals

| Signal | Source | Expected Change |
|---|---|---|
| `GetProduct` RPC call rate | productcatalogservice | +1,700–1,900% vs baseline |
| CPU utilization | productcatalogservice pod | +60–85% absolute |
| p99 `GetProduct` latency | productcatalogservice | +200–500% |
| p99 `ListRecommendations` latency | recommendationservice | +150–300% (sequential fan-out) |
| `ListProducts` latency | productcatalogservice | Moderately elevated (shared CPU), functionally intact |
| `GetProduct` deadline-exceeded errors | productcatalogservice | Rises under sustained load |
| Distributed trace fan-out | Jaeger / OpenTelemetry | Each `ListRecommendations` trace shows 18 child `GetProduct` spans |

The primary signal is `productcatalogservice` `GetProduct` call rate and CPU — both unambiguous and not noise at 18× baseline. Any runtime observability system monitoring per-service RPC call rates would surface this.

---

## F. User-Visible Failure

The homepage and catalog listing load normally: product tiles appear, prices render. Clicking any product tile navigates to the product detail page, which hangs for several seconds and then returns an error (gRPC deadline exceeded propagated to the frontend). The failure mode is "catalog browsing works, product interaction fails" — visible, frustrating, and not immediately connected to a recommendation service change by a casual observer.

Under higher load, the catalog listing itself may begin showing degraded or stale data as `productcatalogservice` CPU saturation affects `ListProducts` as well, widening the blast radius.

---

## G. Oracle Detector Set

Four tests, all directly exercising the `productcatalogservice` `GetProduct` path:

| Test ID | Why Direct |
|---|---|
| `catalog-open-first-product-detail` | Opens product detail from catalog; GetProduct invoked directly |
| `catalog-product-detail-has-price` | Asserts price on product detail page; requires GetProduct success |
| `product-detail-page-has-price` | Direct product-detail price assertion |
| `product-detail-page-has-non-empty-body` | Confirms product detail body is not empty; fails on error page |

These tests fail when `productcatalogservice.GetProduct` is overwhelmed. They do not fail when `ListProducts` is healthy (homepage, catalog listing tests pass). The set is intentionally narrow: multi-step browsing journey tests (e.g., `catalog-first-product-opens-detail-page`) are excluded as downstream symptom tests per the benchmark's "minimal direct validated detecting tests" methodology.

---

## H. Why H+CC Would Miss

**Grounded in OB-005 scoring data** (`benchmark-results/final-comparison/history-code-change-ob-005-selection.json`):

H+CC scoring is keyword-based. For `src/recommendationservice/recommendation_server.py`, the tokens are "recommendation", "server", "py". None of these appear in any of the 51 test IDs. H+CC therefore falls back to intrinsic criticality — the same profile it produces for a currencyservice data change in OB-005.

OB-005 score tiers (from the committed artifact):

| Score | Tests (examples) | Selected? |
|---|---|---|
| 80 | checkout-empty-cart-does-not-complete-order | ✓ |
| 70 | frontend-basic-user-journey-home-product-cart | ✓ |
| 60 | checkout-page-accessible-from-cart, payment-order-completion-confirms-success | ✓ |
| 50 | cart-add-* (5 tests), catalog-first-product-link-has-valid-href, catalog-first-product-opens-detail-page, catalog-multiple-products-visible | ✓ (slots 8–15, alphabetically first) |
| 50 | **catalog-open-first-product-detail**, **catalog-product-detail-has-price**, catalog-product-detail-can-be-opened-twice, frontend-homepage-has-product-grid … | ✗ (slots 16–24, alphabetically later) |
| 30 | **product-detail-page-has-price**, **product-detail-page-has-non-empty-body**, smoke-product-links-visible … | ✗ (slots ~35–43) |
| 10 | smoke-homepage-loads, homepage-* smoke tests | ✗ |

Bold entries are the four oracle tests. All four fall outside the top-15 cutoff.

For a recommendationservice code change, OB-007 scoring would be identical to OB-005 with one minor difference: `order-form-requires-payment-data` and `order-flow-does-not-complete-with-empty-data` lose the OB-005 "data" token bonus (the word "data" appeared in the OB-005 changed file path). This slightly shuffles internal ranks but does not move any oracle test into the top-15; the oracle tests are at score 50 (slots 16–17 after the alphabetical cutoff) and score 30 (slots 35–40).

**Result: 0 of 4 oracle tests in H+CC's 15-test selection → definitive miss.**

This is not probabilistic. It follows from the committed H+CC scoring data.

---

## I. Why Quantik Mind Should Detect

Runtime evidence collection during the load window surfaces:

1. `productcatalogservice` CPU utilization: +75% absolute spike
2. `productcatalogservice` `GetProduct` RPC call rate: +1,800% vs baseline
3. Distributed traces: each `ListRecommendations` span contains 18 `GetProduct` child spans

QMind's reasoning path:
- Metric anomaly detected on `productcatalogservice` (CPU + RPC rate)
- Service dependency map: `productcatalogservice.GetProduct` → product detail page rendering
- Risk signal propagated to product-detail test domain
- Selection: QMind scores `catalog-open-first-product-detail`, `catalog-product-detail-has-price`, `product-detail-page-has-price`, `product-detail-page-has-non-empty-body` as high-risk based on the anomaly

The inference chain is two hops beyond the changed file: recommendationservice code change → productcatalogservice metric anomaly → product-detail test selection. This multi-hop, cross-service inference is exactly what runtime observability enables and what static code-change analysis cannot replicate.

Unlike OB-005 (one-hop: currency error rate → homepage tests) and OB-006 (zero-hop: productcatalogservice change → productcatalogservice tests), OB-007 requires QMind to bridge a service boundary in a direction not visible from the changed file.

---

## J. Potential Reviewer Criticisms

**1. "A code reviewer would immediately spot the N+1 loop."**

The loop is visible. However, "fetch full product metadata for richer recommendation scoring" is a plausible product requirement and the code is functionally correct. Performance impact at 10+ req/s is non-obvious without load modeling. N+1 bugs routinely ship through code review in distributed systems precisely because they look correct and the performance cost only materializes at scale.

**2. "An integration test for recommendationservice would catch this via RPC count assertions."**

Standard recommendation service tests verify output correctness (returns valid product IDs) and do not assert downstream RPC call counts. Catching the fan-out requires a test specifically instrumented for outbound call volume. The 51-test Playwright suite does not include such a test, and most CI pipelines do not either.

**3. "catalog-first-product-opens-detail-page is in H+CC's selection AND fails — H+CC detects it."**

This test is NOT an oracle test. The benchmark methodology uses "minimal direct validated detecting tests" and excludes multi-step browsing-journey tests as downstream symptoms (`catalog-first-product-opens-detail-page` requires: homepage load → catalog render → click navigation → product detail load). The oracle uses single-step product-detail assertions. H+CC selecting a failing non-oracle test does not count as detection under the evaluator. This is consistent with how OB-001 through OB-004 handle downstream symptom tests.

**4. "Both GetProduct and ListProducts share a process — both degrade under CPU pressure."**

True at high load. At moderate load (~15 concurrent users), `GetProduct` receives ~180 calls/second versus `ListProducts`'s ~15 calls/second. The CPU budget is dominated by `GetProduct`. `ListProducts` latency increases moderately but remains within Playwright's 30-second timeout. The scenario requires concurrency calibration to achieve this separation — it is an implementation concern, not a design flaw.

**5. "The oracle overlaps with OB-006."**

`catalog-open-first-product-detail` and `catalog-product-detail-has-price` also appear in OB-006's oracle. The same test can detect different defects. What distinguishes OB-007 from OB-006: the changed service is recommendationservice (not productcatalogservice), the defect mechanism is load fan-out (not sleep injection or gRPC error), and the runtime signal source is productcatalogservice metrics observed from OUTSIDE the changed service boundary. Oracle test overlap across scenarios is expected and is not an integrity concern.

**6. "This is just OB-005 with a different service."**

Three structural differences make OB-007 genuinely distinct:

| Dimension | OB-005 | OB-007 |
|---|---|---|
| Changed artifact | Data file (currency_conversion.json) | Application code (recommendation_server.py) |
| Runtime signal source | currencyservice error rate | productcatalogservice CPU + RPC rate |
| QMind inference hops | 1 (currency → homepage) | 2 (recommendation → productcatalog → product-detail) |
| Defect class | Data corruption | Load fan-out / N+1 |
| Oracle tests | Homepage smoke tests (score 10) | Product-detail tests (scores 30–50) |

**7. "The loadgenerator must be active — this isn't a static defect."**

Correct and intentional. OB-007 is categorized `runtime-aware`. Load-induced saturation is the class of defect that runtime observability is most suited to detect. The loadgenerator is part of the scenario setup, as it is for OB-005 and OB-006.

---

## K. How to Defend the Scenario

**The H+CC miss is empirically grounded.** The OB-005 scoring artifact (`benchmark-results/final-comparison/history-code-change-ob-005-selection.json`) records exact scores and selection outcomes for all 51 tests under a changed file that produces zero keyword matches. A recommendationservice change produces the same profile. The oracle tests appear at score 50 (positions 16–17 in the tie group, outside the 15-test cutoff) and score 30 (positions 35–40). This is not a designed weakness — it follows from the committed scoring data.

**The oracle curation is methodologically consistent.** The benchmark's "minimal direct validated detecting tests" principle has been applied in OB-001 through OB-006. Multi-step journey tests are excluded as downstream symptoms; direct endpoint-exercising tests are included. `catalog-open-first-product-detail` tests the GetProduct endpoint directly (no catalog browsing prerequisite in its Playwright implementation). `catalog-first-product-opens-detail-page` tests the full navigation journey. This distinction aligns with existing benchmark practice.

**The defect is realistic and survives code review.** N+1 RPC patterns in recommendation/search services are among the most common distributed-systems performance regressions. The feature framing ("richer product metadata for better recommendations") is a real product request pattern. The functional correctness of the output makes the defect invisible to correctness tests.

**The runtime signal is unambiguous.** A 1,800% increase in `productcatalogservice.GetProduct` call rate is not measurement noise. It is visible in any Prometheus dashboard monitoring RPC call rates. The connection from "GetProduct is saturated" to "product-detail tests are at risk" requires a service dependency map, which Quantik Mind maintains as part of its observability layer.

---

## L. Difficulty Estimate

**Medium**

The H+CC miss is deterministic (grounded in committed scoring data). The defect injection is simple (Python, single-function change). The implementation challenge is concurrency calibration: the loadgenerator must produce enough concurrent recommendation requests to saturate `productcatalogservice.GetProduct` while leaving `ListProducts` marginally functional for homepage rendering. This requires empirical tuning of concurrency settings and may need iteration. The runtime evidence infrastructure (Prometheus, OpenTelemetry, distributed traces) is already established by OB-006.

---

## M. Recommended Implementation Approach

1. **Branch**: Create `benchmark/scenario-ob007` in the external `microservices-demo` repository from `benchmark-baseline`.

2. **Inject defect**: Modify `src/recommendationservice/recommendation_server.py` — add the N+1 `GetProduct` loop inside `ListRecommendations` as specified in section D.

3. **Calibrate load**: Start the system with the loadgenerator at 10–20 concurrent users. Target: `productcatalogservice` `GetProduct` RPC rate exceeds 150 calls/second, CPU exceeds 70%; `ListProducts` p99 latency stays below 5 seconds.

4. **Collect runtime evidence**: Record `productcatalogservice` CPU, `GetProduct` call rate, and p99 latency over a 2-minute window. Capture distributed traces confirming the 18× fan-out. Store under `benchmark-results/runtime-evidence/ob-007/` following the OB-006 structure.

5. **Validate oracle**: Run the full 51-test Playwright suite against the defective system under load. Confirm:
   - `catalog-open-first-product-detail`, `catalog-product-detail-has-price`, `product-detail-page-has-price`, `product-detail-page-has-non-empty-body` → FAIL
   - `catalog-multiple-products-visible`, `frontend-homepage-has-product-grid`, `smoke-homepage-loads` → PASS

6. **Validate H+CC miss**: Run `select-history-code-change-approach.py` with changed file `src/recommendationservice/recommendation_server.py`. Confirm none of the 4 oracle tests appear in the 15-test selection.

7. **Generate QMind selection**: Run `run-qmind-subset.ps1 -BenchmarkCase OB-007` with `productcatalogservice` runtime evidence injected into the observability context. Confirm QMind selects at least one oracle test.

8. **Add to scenarios.json**: Add OB-007 with `signal_type: "runtime"`, `category: "runtime-aware"`, `expected_changed_files: ["src/recommendationservice/recommendation_server.py"]`, and the 4 oracle detecting tests.

9. **Extend the pipeline**: Update `generate-final-comparison.ps1` to include OB-007. Add OB-007 runtime evidence validation alongside OB-006.

10. **Update docs**: Add OB-007 row to the per-scenario comparison table. If H+CC misses and QMind detects as designed, the aggregate becomes H+CC 5/7 vs QMind 7/7.

---

## Notes and Open Questions

- **Concurrency calibration is the main implementation risk.** If the loadgenerator concurrency is too low, `productcatalogservice` stays healthy and oracle tests pass (scenario fails to inject the defect). If too high, `ListProducts` also fails and homepage tests are affected (bloating the oracle). Target the "sweet spot" where GetProduct fails and ListProducts survives.

- **Oracle size**: Four tests is intentionally narrow, consistent with OB-004 (1 test) and OB-005 (6 tests). A narrow oracle keeps the scenario precise and avoids the risk of including tests that H+CC accidentally selects.

- **Defect motivation framing matters**: The commit message for the recommendationservice change should say something like "Add product metadata enrichment to recommendation scoring" — not "fetch each product individually." The framing makes the code review path realistic.

- **If empirical calibration fails**: If `ListProducts` cannot be kept healthy under any reasonable load setting, fall back to an alternative oracle using only tests that navigate directly to a product detail URL (bypassing catalog listing entirely). These tests would not require `ListProducts` to succeed and would isolate the GetProduct failure more cleanly.

# OB-006 Combined Signal Validation

## Scenario

OB-006 introduces deterministic latency or failure in the upstream Online Boutique product catalog listing path:

```text
src/productcatalogservice/product_catalog.go
```

The injected method is:

```text
func (p *productCatalog) ListProducts(context.Context, *pb.Empty) (*pb.ListProductsResponse, error)
```

The direct detecting tests are the 19 homepage, product-grid, catalog, and product-detail checks in the OB-006 oracle:

```text
frontend-homepage-has-product-grid
frontend-products-have-prices
homepage-contains-product-price
homepage-has-at-least-one-product-link
smoke-product-links-visible
catalog-multiple-products-visible
catalog-first-product-link-has-valid-href
catalog-product-link-href-starts-with-product
catalog-open-first-product-detail
catalog-product-detail-has-price
catalog-product-detail-can-be-opened-twice
catalog-product-detail-keeps-product-context
catalog-first-product-opens-detail-page
product-detail-page-has-body-content
product-detail-allows-return-navigation
product-detail-page-has-add-to-cart-button
product-detail-page-has-price
product-detail-page-has-non-empty-body
product-detail-refresh-keeps-content
```

This is a combined-signal case because code change points to `productcatalogservice`, while runtime observability must show the impact crossing into `frontend` homepage/product-grid behavior.

## Why OB-006 Was Redesigned

The original adservice version was rejected because frontend treats ads as optional, uses a 100 ms timeout, and ignores ad errors. Product catalog listing is homepage-critical because `homeHandler` calls `getProducts`, which calls `ProductCatalogService/ListProducts`; if that call fails, the frontend returns an error before building the homepage product grid.

## Reproducible Defect Injection

Use the helper against an external Online Boutique checkout:

```powershell
.\runtime-scenarios\ob-006-productcatalog-listproducts-cascade\apply-ob006-productcatalog-listproducts.ps1 -SourceRoot microservices-demo
```

The default mode returns a deterministic gRPC `Unavailable` error from `ListProducts`. The helper also supports deterministic latency above Playwright's 30 second test timeout:

```powershell
.\runtime-scenarios\ob-006-productcatalog-listproducts-cascade\apply-ob006-productcatalog-listproducts.ps1 `
  -SourceRoot microservices-demo `
  -Mode latency `
  -LatencyMs 35000
```

Restore:

```powershell
.\runtime-scenarios\ob-006-productcatalog-listproducts-cascade\apply-ob006-productcatalog-listproducts.ps1 -SourceRoot microservices-demo -Restore
```

## Live Runtime Validation

Live runtime validation must capture Prometheus movement for both `productcatalogservice` and `frontend` in the same validation window used for homepage traffic and the live OB-006 QMind subset. Evidence is copied to:

```text
benchmark-results/runtime-evidence/ob-006/
```

only after runtime movement and QMind selection checks pass.

Current live runtime evidence status: `committed under benchmark-results/runtime-evidence/ob-006`.

External publication readiness: `evidence-backed for the committed comparison`.

## Live Runtime Validation Procedure

Start from a clean Online Boutique deployment, a reachable frontend URL, and Prometheus available at `http://localhost:19090`. If Prometheus is in Kubernetes, port-forward it before running the validation script.

Prerequisites:

- `docker` is installed and authenticated to push to the writable `-ImageRepository`.
- `kubectl` context points to the Online Boutique cluster.
- `gcloud` is installed when `-ImageRepository` uses Artifact Registry.
- For Artifact Registry, run `gcloud auth configure-docker <region>-docker.pkg.dev` if Docker is not already authenticated.
- Prometheus port-forward is active on `localhost:19090`.
- QMind CLI is installed and configured.
- `SourceRoot` points to the Online Boutique source checkout.

```powershell
.\benchmark-pipeline\validate-ob006-live-runtime.ps1 `
  -FrontendUrl "http://34.185.198.67/" `
  -PrometheusUrl "http://localhost:19090" `
  -SourceRoot "microservices-demo" `
  -ImageRepository "europe-west3-docker.pkg.dev/quantik-mind/online-boutique-benchmark/productcatalogservice"
```

The script performs these phases:

1. Fails fast if required files or tools are missing: `docker`, `kubectl`, `qmind`, `python`, and `gcloud` when the active image repository requires it.
2. Fails fast if Prometheus, `FrontendUrl`, `SourceRoot`, the product catalog source file, kubectl context, namespace, or deployment is unavailable.
3. Derives the current running productcatalogservice image from Kubernetes.
4. Uses `-ImageRepository` for injected and clean image tags. If it is omitted, the script derives the repository from the running image only when that repository is not a read-only upstream such as `google-samples`.
5. Runs baseline homepage traffic against `-FrontendUrl`.
6. Captures baseline Prometheus snapshots for `productcatalogservice` and `frontend`.
7. Applies the OB-006 injector locally.
8. Builds and pushes the injected productcatalogservice image from `SourceRoot/src/productcatalogservice`.
9. Deploys the injected image with `kubectl set image` and waits for rollout.
10. Runs injected homepage traffic and captures injected Prometheus snapshots.
11. Fails unless material productcatalogservice movement and material frontend movement are both present.
12. Backs up any existing `benchmark-results/qmind-selections/qmind-selection-ob-006.json`.
13. Runs `run-qmind-subset.ps1 -BenchmarkCase OB-006`.
14. Verifies that QMind used the OB-006 productcatalogservice changed-files artifact, observability was enabled, runtime signal was present, and the new run ID differs from the previous OB-006 artifact.
15. Verifies QMind detection by intersecting selected tests with OB-006 oracle detectors. At least one detector is required; missing non-selected detectors are warnings.
16. Fails if the live OB-006 QMind selection is substantively identical to OB-005 in selected tests, business metrics, risk coverage, and risk density.
17. Publishes the publication-safe runtime evidence under `benchmark-results/runtime-evidence/ob-006/`.
18. Regenerates final comparison artifacts with `generate-final-comparison.ps1 -UseExistingQMindSelections`.
19. Restores the source file in a `finally` block unless `-SkipRestore` is set. If the injected image reached the cluster, the script also builds and pushes `<ImageRepository>:ob006-clean-<timestamp>`, deploys it, and waits for rollout.

If only runtime snapshots are needed and QMind/final comparison should not run:

```powershell
.\benchmark-pipeline\validate-ob006-live-runtime.ps1 `
  -FrontendUrl "http://34.185.198.67/" `
  -PrometheusUrl "http://localhost:19090" `
  -SourceRoot "microservices-demo" `
  -ImageRepository "europe-west3-docker.pkg.dev/quantik-mind/online-boutique-benchmark/productcatalogservice" `
  -SkipQMind `
  -SkipComparison
```

## Evidence To Capture

The validation script writes scratch runtime artifacts under:

```text
benchmark-runs/ob-006-live-runtime-validation/
```

After all checks pass, it copies only publication-safe evidence into:

```text
benchmark-results/runtime-evidence/ob-006/
```

Required evidence fields:

| Evidence | Status | Artifact or value |
| --- | --- | --- |
| Baseline productcatalogservice p95/error | Committed | `baseline-prometheus-snapshot.json` |
| Injected productcatalogservice p95/error | Committed | `injected-prometheus-snapshot.json` |
| Baseline frontend p95/error | Committed | `baseline-prometheus-snapshot.json` |
| Injected frontend p95/error | Committed | `injected-prometheus-snapshot.json` |
| Baseline homepage traffic | Committed | `baseline-homepage-traffic.json` |
| Injected homepage traffic | Committed | `injected-homepage-traffic.json` |
| Runtime movement summary | Committed | `runtime-movement-summary.json` |
| QMind selected tests | Committed | `benchmark-results/qmind-selections/qmind-selection-ob-006.json` |
| QMind detection summary | Committed | `qmind-ob006-detection-summary.json` |
| Final comparison result | Committed | `benchmark-results/final-comparison/final-comparison.json` |

Material movement thresholds are explicit script parameters. Defaults require productcatalogservice p95 latency to increase by at least `5.0x` and `1.0s`, or productcatalogservice error rate to increase by at least `0.05`; frontend p95 latency must increase by at least `1.5x` and `0.2s`, or frontend error rate must increase by at least `0.02`.

## Publication Gate

OB-006 can be published externally only if all of the following are true:

- Full suite detects OB-006.
- History + Code Change result is reported from the committed selection artifact, without oracle leakage.
- QMind detects OB-006 using a live `qmind subset` artifact generated during the validation window.
- The live OB-006 selection uses `benchmark-runs/scenario-ob-006-changed-files.json`, and that file contains only `src/productcatalogservice/product_catalog.go`.
- The live OB-006 artifact shows `observability_enabled=true`, `has_runtime_signal=true`, and a new QMind run ID.
- The live OB-006 selected tests, business metrics, risk coverage, and risk density are not substantively identical to OB-005.
- Prometheus shows material productcatalogservice movement and material frontend movement in the same validation window.
- Publication-safe evidence is committed under `benchmark-results/runtime-evidence/ob-006/`.

If a future rerun cannot satisfy those conditions from live runtime evidence, OB-006 must not be published as external combined-signal evidence from that rerun.

## Benchmark Integrity Controls

- No Quantik Mind algorithm code was changed.
- No benchmark scoring logic was changed.
- OB-001 through OB-005 definitions and oracle detecting tests were not changed.
- The H+CC selector explicitly reports `uses_runtime: false` and `uses_oracle: false`.
- The OB-006 H+CC selector receives no runtime metrics or oracle detecting tests as input.
- The OB-006 QMind artifact must contain canonical test IDs only and detect by intersecting selected tests with the OB-006 oracle.
- Runtime evidence is not inferred from local JSON artifacts; live Prometheus snapshots are required before external publication.

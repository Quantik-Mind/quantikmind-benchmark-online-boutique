# OB-006 Combined Signal Validation

## Scenario

OB-006 introduces deterministic adservice latency or failure in the upstream Online Boutique file:

```text
src/adservice/src/main/java/hipstershop/AdService.java
```

The direct detecting tests are homepage/frontend smoke checks:

```text
smoke-homepage-loads
homepage-body-is-not-empty
homepage-title-is-available
homepage-has-visible-text-content
homepage-shows-google-cloud-branding
homepage-has-multiple-links
```

This is a combined-signal case because code change points to `adservice`, while runtime observability must show the impact crossing into `frontend`.

## Reproducible Defect Injection

Use the helper against an external Online Boutique checkout:

```powershell
.\runtime-scenarios\ob-006-adservice-latency-cascade\apply-ob006-adservice-latency.ps1 -SourceRoot microservices-demo
```

The default mode injects a 35 second sleep in `getAds`, which is intentionally above the Playwright 30 second test timeout. The helper also supports deterministic gRPC failure:

```powershell
.\runtime-scenarios\ob-006-adservice-latency-cascade\apply-ob006-adservice-latency.ps1 -SourceRoot microservices-demo -Mode failure
```

Restore:

```powershell
.\runtime-scenarios\ob-006-adservice-latency-cascade\apply-ob006-adservice-latency.ps1 -SourceRoot microservices-demo -Restore
```

## Local Artifact Validation

Local artifact validation checks committed benchmark inputs and generated comparison artifacts. It does not prove that the running Online Boutique deployment emitted live Prometheus evidence for OB-006.

The following checks were run locally from committed inputs:

```powershell
python -m json.tool benchmark-pipeline\scenarios.json
python -m json.tool defect-oracle\online-boutique-defect-oracle.v2.json
python benchmark-pipeline\check-defect-oracle.py --oracle defect-oracle\online-boutique-defect-oracle.v2.json --library qmind-test-library\online-boutique-playwright-51.json
.\benchmark-pipeline\generate-final-comparison.ps1 -UseExistingQMindSelections
```

Oracle/library validation status: `warn`, with only the existing broad `expected_unaffected_tests` label warnings. OB-006 detecting and validated detecting tests are all canonical library IDs.

OB-006 per-method results from local artifacts:

| Method | Result | Selected tests | Execution reduction |
| --- | --- | ---: | ---: |
| Full Suite | detected | 51 | 0.0% |
| Random | detected | 26 | 49.0% |
| History + Code Change | missed | 15 | 70.6% |
| Quantik Mind | detected | 15 | 70.6% |

Aggregate expected benchmark results after OB-006 from local artifacts:

| Method | Recall | Average selected tests | Average execution reduction |
| --- | ---: | ---: | ---: |
| Full Suite | 6/6 | 51.0 | 0.0% |
| Random | 5/6 | 26.0 | 49.0% |
| History + Code Change | 4/6 | 15.0 | 70.6% |
| Quantik Mind | 6/6 | 15.5 | 69.6% |

## Live Runtime Validation

Live runtime validation is the missing independent publication evidence for OB-006. It must capture Prometheus movement for both `adservice` and `frontend` in the same validation window used for homepage traffic and the live OB-006 QMind subset. The committed OB-006 QMind selection currently matches OB-005 exactly and reports identical business metrics, so it must not be presented as independent proof of an additional runtime-aware win until distinct live evidence is captured.

Current live runtime evidence status: `TBD`.

External publication readiness: `pending`.

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
  -ImageRepository "europe-west3-docker.pkg.dev/quantik-mind/online-boutique-benchmark/adservice"
```

The script performs these phases:

1. Fails fast if required files or tools are missing: `docker`, `kubectl`, `qmind`, `python`, and `gcloud` when the active image repository requires it.
2. Fails fast if Prometheus, `FrontendUrl`, `SourceRoot`, the adservice source file, kubectl context, namespace, or deployment is unavailable.
3. Derives the current running adservice image from Kubernetes with:

```powershell
kubectl -n <namespace> get deployment adservice -o jsonpath="{.spec.template.spec.containers[?(@.name=='server')].image}"
```

4. Uses `-ImageRepository` for injected and clean image tags. If it is omitted, the script derives the repository from the running image only when that repository is not a read-only upstream such as `google-samples`.
5. Runs baseline homepage traffic against `-FrontendUrl`.
6. Captures baseline Prometheus snapshots for `adservice` and `frontend`.
7. Applies the OB-006 injector locally.
8. Builds and pushes the injected adservice image from `SourceRoot/src/adservice`.
9. Deploys the injected image with `kubectl set image` and waits for rollout.
10. Runs injected homepage traffic and captures injected Prometheus snapshots.
11. Prints and saves a runtime movement summary.
12. Backs up any existing `benchmark-results/qmind-selections/qmind-selection-ob-006.json`.
13. Runs `run-qmind-subset.ps1 -BenchmarkCase OB-006`.
14. Verifies QMind detection by intersecting selected tests with OB-006 oracle detectors. At least one detector is required; missing non-selected detectors are warnings.
15. Regenerates final comparison artifacts with `generate-final-comparison.ps1 -UseExistingQMindSelections`.
16. Restores the source file in a `finally` block unless `-SkipRestore` is set. If the injected image reached the cluster, the script also builds and pushes `<ImageRepository>:ob006-clean-<timestamp>`, deploys it, and waits for rollout.

If only runtime snapshots are needed and QMind/final comparison should not run:

```powershell
.\benchmark-pipeline\validate-ob006-live-runtime.ps1 `
  -FrontendUrl "http://34.185.198.67/" `
  -PrometheusUrl "http://localhost:19090" `
  -SourceRoot "microservices-demo" `
  -ImageRepository "europe-west3-docker.pkg.dev/quantik-mind/online-boutique-benchmark/adservice" `
  -SkipQMind `
  -SkipComparison
```

Use `-SkipRestore` only for deliberate debugging. Without it, any failure after injection still attempts to restore the local source and redeploy a clean adservice image. If clean redeploy fails, the script prints manual recovery commands loudly.

## Evidence To Capture

The validation script writes runtime artifacts under:

```text
benchmark-runs/ob-006-live-runtime-validation/
```

Required evidence fields:

| Evidence | Status | Artifact or value |
| --- | --- | --- |
| Baseline adservice p95/error | TBD | `baseline-prometheus-snapshot.json` |
| Injected adservice p95/error | TBD | `injected-prometheus-snapshot.json` |
| Baseline frontend p95/error | TBD | `baseline-prometheus-snapshot.json` |
| Injected frontend p95/error | TBD | `injected-prometheus-snapshot.json` |
| Baseline homepage traffic | TBD | `baseline-homepage-traffic.json` |
| Injected homepage traffic | TBD | `injected-homepage-traffic.json` |
| Runtime movement summary | TBD | `runtime-movement-summary.json` |
| QMind selected tests | TBD | `benchmark-results/qmind-selections/qmind-selection-ob-006.json` |
| QMind detection summary | TBD | `qmind-ob006-detection-summary.json` |
| Final comparison result | TBD | `benchmark-results/final-comparison/final-comparison.json` |

Prometheus queries printed and captured by the script:

```promql
histogram_quantile(0.95, sum by (deployment, le) (rate(inbound_http_response_duration_seconds_bucket{namespace="default",deployment="adservice"}[2m])))
```

```promql
1 - (sum by (deployment) (rate(inbound_http_statuses_total{namespace="default",deployment="adservice",status=~"2..|3.."}[2m])) / sum by (deployment) (rate(inbound_http_statuses_total{namespace="default",deployment="adservice"}[2m])))
```

```promql
histogram_quantile(0.95, sum by (deployment, le) (rate(inbound_http_response_duration_seconds_bucket{namespace="default",deployment="frontend"}[2m])))
```

```promql
1 - (sum by (deployment) (rate(inbound_http_statuses_total{namespace="default",deployment="frontend",status=~"2..|3.."}[2m])) / sum by (deployment) (rate(inbound_http_statuses_total{namespace="default",deployment="frontend"}[2m])))
```

The script also captures request-rate queries for both services. If any metric query returns an empty Prometheus vector, the script prints `NO DATA`; such output is not publishable evidence for that metric.

## Publication Gate

OB-006 can be published externally only if all of the following are true:

- Full suite detects OB-006.
- History + Code Change misses OB-006.
- QMind detects OB-006 using a live `qmind subset` artifact generated during the validation window.
- The live OB-006 selection and business metrics are reviewed against OB-005 so any duplicate-selection behavior is disclosed.
- Prometheus shows adservice movement and frontend movement in the same validation window.

Until those conditions are met from live runtime evidence, OB-006 must be described as implemented and locally artifact-validated, with external publication readiness marked `pending`.

## Benchmark Integrity Controls

- No Quantik Mind algorithm code was changed.
- No benchmark scoring logic was changed.
- OB-001 through OB-005 definitions and oracle detecting tests were not changed.
- The H+CC selector explicitly reports `uses_runtime: false` and `uses_oracle: false`.
- The OB-006 H+CC selection contains no oracle detecting tests.
- The OB-006 QMind artifact must contain canonical test IDs only and detect by intersecting homepage tests with the oracle.
- The oracle uses direct homepage smoke checks only, not broad downstream failures.
- Runtime evidence is not inferred from local JSON artifacts; live Prometheus snapshots are required before external publication.

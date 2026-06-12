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

## Local Validation Output

The following checks were run locally from committed inputs:

```powershell
python -m json.tool benchmark-pipeline\scenarios.json
python -m json.tool defect-oracle\online-boutique-defect-oracle.v2.json
python benchmark-pipeline\check-defect-oracle.py --oracle defect-oracle\online-boutique-defect-oracle.v2.json --library qmind-test-library\online-boutique-playwright-51.json
.\benchmark-pipeline\generate-final-comparison.ps1 -UseExistingQMindSelections
```

Oracle/library validation status: `warn`, with only the existing broad `expected_unaffected_tests` label warnings. OB-006 detecting and validated detecting tests are all canonical library IDs.

OB-006 per-method results:

| Method | Result | Selected tests | Execution reduction |
| --- | --- | ---: | ---: |
| Full Suite | detected | 51 | 0.0% |
| Random | detected | 26 | 49.0% |
| History + Code Change | missed | 15 | 70.6% |
| Quantik Mind | detected | 15 | 70.6% |

Aggregate expected benchmark results after OB-006:

| Method | Recall | Average selected tests | Average execution reduction |
| --- | ---: | ---: | ---: |
| Full Suite | 6/6 | 51.0 | 0.0% |
| Random | 5/6 | 26.0 | 49.0% |
| History + Code Change | 4/6 | 15.0 | 70.6% |
| Quantik Mind | 6/6 | 16.2 | 68.3% |

## Runtime Evidence Required For Publication

Before publishing OB-006 as externally validated, capture Prometheus evidence for the same deployment window as the full-suite failure run.

Expected signals:

```promql
histogram_quantile(
  0.95,
  sum by (deployment, le) (
    rate(inbound_http_response_duration_seconds_bucket{namespace="default"}[2m])
  )
)
```

```promql
1 -
(
  sum by (deployment) (
    rate(inbound_http_statuses_total{namespace="default",status=~"2..|3.."}[2m])
  )
  /
  sum by (deployment) (
    rate(inbound_http_statuses_total{namespace="default"}[2m])
  )
)
```

Required proof:

- `adservice` latency and/or error rate increases after injection.
- `frontend` latency and/or error rate increases during the same homepage traffic window.
- Full suite detects OB-006 through homepage/frontend tests.
- History + Code Change still misses using only changed-file context.
- QMind detects from changed files plus runtime observability.

## Hostile-Review Defense

- No Quantik Mind algorithm code was changed.
- No benchmark scoring logic was changed.
- OB-001 through OB-005 definitions and oracle detecting tests were not changed.
- The H+CC selector explicitly reports `uses_runtime: false` and `uses_oracle: false`.
- The OB-006 H+CC selection contains no oracle detecting tests.
- The OB-006 QMind artifact contains canonical test IDs only and detects by intersecting homepage tests with the oracle.
- The oracle uses direct homepage smoke checks only, not broad downstream failures.
- The local QMind artifact under `benchmark-runs/` should be replaced by a live `qmind subset` run before external publication.

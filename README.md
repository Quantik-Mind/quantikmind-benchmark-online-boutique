# Quantik Mind Online Boutique Benchmark

This repository contains the reproducibility artifacts for the Quantik Mind Online Boutique benchmark.

The benchmark evaluates how different test selection strategies behave across seven independent CI/CD benchmark cases based on Google Online Boutique.

The primary purpose is to evaluate whether runtime observability signals can add useful selection value on top of static CI/CD inputs such as test history, test metadata and changed files.

This is a signal-class benchmark.

It is not a vendor head-to-head comparison.

No third-party proprietary test selection product is evaluated in this repository.

---

## What This Benchmark Shows

The benchmark compares four selection strategies:

| Strategy              | Signal Class                                 | Purpose                                                        |
| --------------------- | -------------------------------------------- | -------------------------------------------------------------- |
| Full Suite            | All tests                                    | Maximum-recall reference point                                 |
| Random                | Fixed random subset                          | Statistical control                                            |
| History + Code Change | Static CI/CD signals                         | Strong baseline using history, test metadata and changed files |
| Quantik Mind          | Static CI/CD signals + runtime observability | Runtime-aware selection based on current system risk           |

The benchmark should be read as:

> Can live runtime risk signals improve defect recall when static CI/CD inputs alone are not enough?

It should not be read as:

> Which strategy runs the fewest tests?

Recall is the primary metric.

Execution reduction is secondary.

A smaller test subset is useful only if the relevant defects are still detected.

---

## Final Result Summary

Across the seven benchmark cases:

| Strategy              | Defect Recall | Average Tests Selected | Execution Reduction |
| --------------------- | ------------: | ---------------------: | ------------------: |
| Full Suite            |         7 / 7 |                   52.0 |                0.0% |
| Random                |         5 / 7 |                   26.0 |               50.0% |
| History + Code Change |         5 / 7 |                   15.0 |               71.2% |
| Quantik Mind          |         7 / 7 |                   19.6 |               62.4% |

Quantik Mind detected all seven benchmark defects while executing 19.6 tests on average out of 52.

The static History + Code Change baseline selected fewer tests on average, but missed the two runtime-aware cases.

This is the key trade-off shown by the benchmark:

> Quantik Mind executes slightly more tests than the strongest static baseline, but captures runtime-driven failures that static CI/CD signals alone do not expose.

---

## Dynamic Risk Diagnostics

Quantik Mind does not only return a selected test subset.

It also returns dynamic risk diagnostics that explain how much currently observed system risk is covered by the selected tests.

These diagnostics are important because they turn test selection into risk coverage analysis.

Instead of only asking:

> How many tests did we select?

Quantik Mind also answers:

> How much of the currently observed risk did these tests cover?

### Aggregate Dynamic Risk Results

Across the seven benchmark cases, Quantik Mind reported the following aggregate dynamic risk diagnostics:

| Metric                 | Average Result | Meaning                                                                                 |
| ---------------------- | -------------: | --------------------------------------------------------------------------------------- |
| Observed Risk Coverage |          45.9% | Percentage of currently observed system risk covered by the selected tests              |
| Critical Risk Captured |          72.3% | Percentage of the highest-priority observed risk band captured by the selected tests    |
| Residual Risk          |          54.1% | Observed system risk left uncovered after selection                                     |
| Risk Density           |          1.22x | Amount of risk information captured per executed test compared with an average test set |

These values are returned by Quantik Mind from the selected test subset and the runtime risk model.

They are not oracle metrics.

The defect oracle is used only afterward to score whether the selected tests detected the benchmark defects.

### Per-Scenario Dynamic Risk Results

| Scenario | Observed Risk Coverage | Critical Risk Captured | Residual Risk | Risk Density |
| -------- | ---------------------: | ---------------------: | ------------: | -----------: |
| OB-001   |                  34.2% |                  38.5% |         65.8% |        1.27x |
| OB-002   |                  49.2% |                  76.9% |         50.8% |        1.28x |
| OB-003   |                  45.2% |                  76.9% |         54.8% |        1.24x |
| OB-004   |                  47.7% |                  76.9% |         52.3% |        1.18x |
| OB-005   |                  48.5% |                  84.6% |         51.5% |        1.20x |
| OB-006   |                  45.3% |                  75.0% |         54.7% |        1.22x |
| OB-007   |                  50.9% |                  76.9% |         49.1% |        1.15x |

The per-scenario values show that Quantik Mind did not simply maximize total observed risk coverage.

It prioritized critical observed risk more strongly than total observed risk.

That distinction matters.

A selector can leave part of the total observed risk uncovered while still capturing most of the highest-priority observed risk.

### Residual Risk Interpretation

Residual Risk is not a flat severity bucket.

It should not be interpreted as uniformly critical risk.

In this benchmark, Quantik Mind reports:

| Risk View                           | Result | Interpretation                                               |
| ----------------------------------- | -----: | ------------------------------------------------------------ |
| Total observed risk covered         |  45.9% | Total observed system risk covered by the selected tests     |
| Total residual observed risk        |  54.1% | Total observed system risk not covered by the selected tests |
| Critical observed risk captured     |  72.3% | Highest-priority observed risk covered by the selected tests |
| Critical observed risk not captured |  27.7% | Complement of Critical Risk Captured                         |

The 54.1% residual risk value represents total observed risk left uncovered.

The 27.7% critical risk not captured value is the complement of the Critical Risk Captured metric.

These two values should not be mixed.

The benchmark output does not currently split total residual risk into critical, medium and low residual bands.

Where risk-band information is available in future outputs, residual risk can be inspected more precisely as:

| Residual Risk Band     | Meaning                                                                                                 |
| ---------------------- | ------------------------------------------------------------------------------------------------------- |
| Critical residual risk | High-priority observed risk not covered by the selected subset                                          |
| Medium residual risk   | Relevant observed risk left uncovered after higher-priority areas were selected                         |
| Low residual risk      | Lower-priority observed risk intentionally left uncovered when execution cost outweighed expected value |

This distinction matters because not all residual risk has the same operational meaning.

A small amount of uncovered critical risk is more important than a larger amount of uncovered low-priority risk.

For this benchmark, the safe interpretation is:

> Quantik Mind covered 45.9% of total observed risk, captured 72.3% of critical observed risk, and left 54.1% total observed residual risk. The residual value should not be read as uniformly critical.

### Risk Coverage Summary

In this benchmark, Quantik Mind:

* detected 7 / 7 benchmark defects;
* executed 19.6 tests on average out of 52;
* reduced execution volume by 62.4%;
* covered 45.9% of observed runtime risk;
* captured 72.3% of critical observed risk;
* left 54.1% total residual observed risk;
* achieved 1.22x risk density.

These results suggest that runtime risk signals can add useful selection value in benchmark cases where static CI/CD signals alone are incomplete.

They do not claim universal superiority across all applications, defect classes, traffic profiles or observability configurations.

---

## Benchmark Cases

The benchmark models seven independent CI/CD benchmark cases.

OB-001 through OB-004 are code-change control cases.

OB-005 and OB-007 are runtime-aware cases.

OB-006 is a combined-signal case.

Each strategy receives only the allowed pre-execution inputs.

The defect oracle is applied only afterward for scoring.

| Scenario                                    | Category        | Changed Area                                                      | Injected Defect                                                                                         | Expected Detecting Area                                                                                                           |
| ------------------------------------------- | --------------- | ----------------------------------------------------------------- | ------------------------------------------------------------------------------------------------------- | --------------------------------------------------------------------------------------------------------------------------------- |
| OB-001 Checkout Regression                  | Code Change     | Frontend cart template and handlers                               | Checkout fields and actions no longer render after a product is added to the cart                       | Checkout page and checkout form rendering                                                                                         |
| OB-002 Cart Regression                      | Code Change     | Cart service storage/add-item path plus frontend handler          | Adding a product to the cart fails deterministically                                                    | Cart add/view behavior from product detail                                                                                        |
| OB-003 Product Detail Regression            | Code Change     | Product catalog service data/lookup and product template          | Valid product detail lookup fails or returns unusable product data while listing remains healthy        | Product detail pages and downstream flows that require product detail                                                             |
| OB-004 Payment Regression                   | Code Change     | Payment service charge path                                       | Valid Visa or Mastercard payments are rejected                                                          | Successful payment/order completion                                                                                               |
| OB-005 Currency Data Corruption             | Runtime Aware   | Currency conversion data                                          | Corrupted USD conversion data causes currencyservice/frontend homepage failures under standard traffic  | Homepage rendering checks informed by runtime error signals                                                                       |
| OB-006 Product Catalog ListProducts Cascade | Combined Signal | Product catalog ListProducts path                                 | Product catalog latency or errors cascade into frontend homepage/product-grid rendering failure         | Product catalog, product-detail, homepage and product-grid checks informed by productcatalogservice plus frontend runtime signals |
| OB-007 Runtime Observability Gap            | Runtime Aware   | Harmless declared source change with independent runtime pressure | Recommendation service latency causes the recommendation section to disappear from product detail pages | Recommendation-section checks informed by runtime latency evidence                                                                |

The runtime-aware cases are intentionally designed to isolate the value of runtime observability.

In OB-005, elevated currency and frontend error signals point toward user-visible homepage failures.

In OB-007, the declared code change alone does not point to the failing behavior. Runtime latency evidence is needed to prioritize the correct test area.

OB-006 combines both dimensions: the code change points to product catalog behavior, while runtime observability shows the user-visible impact through frontend rendering.

---

## Category-Level Recall

The category-level breakdown is important because the benchmark is not only about aggregate recall.

It also shows where each strategy succeeds or fails.

| Category        | Full Suite | Random | History + Code Change | Quantik Mind |
| --------------- | ---------: | -----: | --------------------: | -----------: |
| Code Change     |      4 / 4 |  2 / 4 |                 4 / 4 |        4 / 4 |
| Runtime Aware   |      2 / 2 |  2 / 2 |                 0 / 2 |        2 / 2 |
| Combined Signal |      1 / 1 |  1 / 1 |                 1 / 1 |        1 / 1 |
| Overall         |      7 / 7 |  5 / 7 |                 5 / 7 |        7 / 7 |

History + Code Change performs strongly on the code-change cases.

It misses the runtime-aware cases because those cases require live runtime evidence that is not available from static CI/CD inputs alone.

Quantik Mind captures both the code-change cases and the runtime-aware cases because it combines static CI/CD context with runtime observability.

---

## Reproducibility Modes

This repository supports two reproducibility modes.

### Mode 1: Recompute the Published Comparison from Committed Artifacts

Use this mode if you want to inspect or recompute the final comparison without running a live Quantik Mind selection.

This mode reuses the committed per-case Quantik Mind selections stored under:

```text
benchmark-results/qmind-selections/
```

It recomputes the aggregate comparison, supporting evaluation files and human-readable report from the committed benchmark artifacts.

It does not require:

* a live Quantik Mind project;
* a Quantik Mind API key;
* live observability configuration;
* re-running the Online Boutique application;
* regenerating the Quantik Mind selections.

Run:

```powershell
.\benchmark-pipeline\generate-final-comparison.ps1 -UseExistingQMindSelections
```

This is the recommended mode for reviewers who want to verify the published benchmark result from the repository artifacts.

The command regenerates:

```text
benchmark-results/final-comparison/final-comparison.json
docs/final-benchmark-comparison.md
benchmark-results/final-comparison/*-evaluation.json
```

This mode is useful for checking that the published aggregate numbers are derived from the committed per-case selections and the benchmark oracle.

### Mode 2: Live End-to-End Regeneration

Use this mode only if you want to regenerate the Quantik Mind selections from a live Quantik Mind project.

This mode requires:

* a Quantik Mind project;
* a Quantik Mind API key;
* the Quantik Mind CLI/API endpoint;
* the benchmark test library synced into the project;
* benchmark history imported into the project;
* observability configured for the benchmark environment;
* the Online Boutique benchmark environment running.

Run:

```powershell
.\benchmark-pipeline\generate-final-comparison.ps1
```

In normal mode, the script invokes Quantik Mind for each benchmark case and writes fresh per-case selections under:

```text
benchmark-results/qmind-selections/
```

The script intentionally refuses to reuse a single current selection for all benchmark cases.

Each benchmark case must have its own case-specific selection artifact.

---

## Repository Contents

This repository contains the artifacts needed to inspect, recompute or regenerate the benchmark.

| Path                                                    | Purpose                                                                          |
| ------------------------------------------------------- | -------------------------------------------------------------------------------- |
| `benchmark-pipeline/`                                   | Scripts for selection, evaluation, normalization and final comparison generation |
| `benchmark-results/final-comparison/`                   | Final aggregate comparison and per-strategy evaluation outputs                   |
| `benchmark-results/qmind-selections/`                   | Committed per-case Quantik Mind selection artifacts                              |
| `benchmark-results/runtime-evidence/`                   | Runtime evidence artifacts for the runtime-aware and combined-signal cases       |
| `docs/final-benchmark-comparison.md`                    | Human-readable final benchmark report                                            |
| `docs/benchmark-methodology-review.md`                  | Methodology notes and benchmark design explanation                               |
| `qmind-test-library/online-boutique-playwright-51.json` | Canonical Online Boutique Playwright test library artifact                       |
| `qmind-config/`                                         | Example Quantik Mind configuration templates                                     |
| `runtime-scenarios/`                                    | Runtime scenario helpers for benchmark-specific pressure and signal generation   |
| `docker-compose.benchmark.yml`                          | Local benchmark support services                                                 |

---

## Benchmark Methodology

The benchmark follows a pre-execution selection methodology.

For each benchmark case:

1. The case defines allowed CI/CD inputs.
2. Each strategy selects tests using only those allowed inputs.
3. The defect oracle is applied afterward.
4. Recall is scored based on whether the selected tests include the oracle-detecting tests.
5. Execution reduction is calculated from the selected test count.
6. Quantik Mind risk diagnostics are captured from the selection response.

This prevents the selector from using oracle knowledge during selection.

The oracle is used only for evaluation.

---

## Selector Input Policy

The benchmark uses a strict input policy.

| Strategy              | Allowed Inputs                                                          |
| --------------------- | ----------------------------------------------------------------------- |
| Full Suite            | Test library                                                            |
| Random                | Test library and fixed seed                                             |
| History + Code Change | Test library, history metadata and changed files                        |
| Quantik Mind          | Test library, history, changed files, runtime metrics and observability |
| Oracle                | Defect identity, oracle detecting tests and expected benchmark outcome  |

Oracle data is not used during selection.

It is used only after selection to score the result.

---

## Selection Strategies

### Full Suite

Full Suite executes every test in the canonical benchmark library.

It establishes the maximum-recall baseline.

It does not prioritize tests and does not reduce execution volume.

### Random

Random selects a fixed 26-test subset from the canonical benchmark library.

It provides a statistical control.

It does not use changed files, history, runtime signals or risk diagnostics.

### History + Code Change

History + Code Change uses:

* historical test/failure metadata;
* test metadata;
* changed files.

It is a strong static baseline.

It estimates likely test relevance from historical and code-change context.

It does not consume live runtime observability.

It therefore cannot react to current latency, error-rate, traffic or service-health signals.

### Quantik Mind

Quantik Mind uses:

* historical test/failure metadata;
* test metadata;
* changed files;
* live runtime observability;
* dynamic risk scoring.

It recalculates risk at selection time.

The selected test subset is driven by both static CI/CD context and currently observed system behavior.

Quantik Mind also returns risk diagnostics for the selected subset, including observed risk coverage, critical risk captured, residual risk and risk density.

---

## Interpreting the Results

The strongest interpretation of the benchmark is complementary:

* static signals explain what changed;
* history explains what failed before;
* runtime observability explains what is risky now;
* dynamic risk diagnostics explain how much observed risk the selected subset covers.

The benchmark does not claim that runtime-aware selection should replace static selection.

It shows that runtime-aware risk can add useful signal in cases where static inputs alone are incomplete.

The benchmark also shows that the smallest subset is not always the best subset.

In this benchmark, the static baseline executed fewer tests than Quantik Mind, but missed the runtime-aware cases.

Quantik Mind executed more tests than the static baseline, but captured all seven benchmark defects and reported risk coverage diagnostics for the selected tests.

---

## Runtime Evidence

Runtime evidence is published for the runtime-aware and combined-signal cases.

The final comparison includes verified runtime evidence for:

| Scenario | Runtime Evidence Status | Main Signal                                                         |
| -------- | ----------------------- | ------------------------------------------------------------------- |
| OB-006   | Verified                | Product catalog and frontend runtime movement                       |
| OB-007   | Verified                | Recommendation service latency and product-detail behavioral signal |

The runtime evidence artifacts are stored under:

```text
benchmark-results/runtime-evidence/
```

These artifacts support the benchmark claim that runtime observability contributed selection signal in the runtime-aware and combined-signal cases.

---

## Primary Outputs

The main machine-readable result is:

```text
benchmark-results/final-comparison/final-comparison.json
```

The main human-readable result is:

```text
docs/final-benchmark-comparison.md
```

The committed per-case Quantik Mind selection artifacts are:

```text
benchmark-results/qmind-selections/qmind-selection-ob-001.json
benchmark-results/qmind-selections/qmind-selection-ob-002.json
benchmark-results/qmind-selections/qmind-selection-ob-003.json
benchmark-results/qmind-selections/qmind-selection-ob-004.json
benchmark-results/qmind-selections/qmind-selection-ob-005.json
benchmark-results/qmind-selections/qmind-selection-ob-006.json
benchmark-results/qmind-selections/qmind-selection-ob-007.json
```

The final comparison generator can reuse these committed artifacts with:

```powershell
.\benchmark-pipeline\generate-final-comparison.ps1 -UseExistingQMindSelections
```

---

## Prerequisites

The required prerequisites depend on the reproducibility mode.

### For Artifact-Level Recalculation

To recompute the published comparison from committed artifacts:

* PowerShell;
* Python;
* this repository.

You do not need a live Quantik Mind project or API key.

You do not need to run Online Boutique.

You do not need to configure observability.

Run:

```powershell
.\benchmark-pipeline\generate-final-comparison.ps1 -UseExistingQMindSelections
```

### For Live End-to-End Regeneration

To regenerate live Quantik Mind selections:

* PowerShell;
* Python;
* Docker Compose;
* `git`;
* `kubectl`;
* Skaffold or equivalent Kubernetes deployment commands;
* access to a Quantik Mind project;
* a Quantik Mind API key;
* the Quantik Mind CLI/API endpoint;
* the pinned upstream Google Online Boutique checkout at commit `b7ecc96372238b0dda6cefaf95cc2c3e9118ea73`.

---

## Live End-to-End Regeneration

Use this section only if you want to regenerate the Quantik Mind selections live.

Clone the pinned upstream Online Boutique source next to this repository:

```powershell
git clone https://github.com/GoogleCloudPlatform/microservices-demo.git microservices-demo
git -C microservices-demo checkout b7ecc96372238b0dda6cefaf95cc2c3e9118ea73
```

The `microservices-demo/` directory is intentionally ignored by this repository.

Start Online Boutique from that checkout using Skaffold or the upstream Kubernetes manifests:

```powershell
Push-Location microservices-demo
skaffold run
Pop-Location
```

Expose the Online Boutique frontend on the host:

```powershell
kubectl port-forward service/frontend 8080:80
```

Copy the environment template:

```powershell
Copy-Item .env.example .env
```

Replace the Quantik Mind placeholder values in `.env`.

Leave this value unchanged if you use the port-forward above:

```text
ONLINE_BOUTIQUE_HOST_PORT=8080
```

Start the benchmark-owned local support services:

```powershell
docker compose -f docker-compose.benchmark.yml up -d online-boutique-frontend prometheus
```

Run standard warm-up traffic:

```powershell
docker compose -f docker-compose.benchmark.yml --profile traffic run --rm traffic-standard
```

Set up the Quantik Mind CLI configuration from `.env`:

```powershell
.\benchmark-pipeline\setup-qmind.ps1
```

Sync the canonical benchmark test library:

```powershell
.\benchmark-pipeline\sync-library.ps1
```

Generate and import benchmark history:

```powershell
.\benchmark-pipeline\import-history.ps1
```

Configure observability:

```powershell
.\benchmark-pipeline\configure-observability.ps1
```

Regenerate the final comparison live:

```powershell
.\benchmark-pipeline\generate-final-comparison.ps1
```

After a successful live run, you can validate the generated per-case selections without contacting Quantik Mind again:

```powershell
.\benchmark-pipeline\generate-final-comparison.ps1 -UseExistingQMindSelections
```

---

## Local Benchmark Stack

This repository does not vendor Google Online Boutique.

Online Boutique must be run from the pinned upstream checkout if live end-to-end regeneration is required.

The benchmark-owned compose stack provides supporting services used by the benchmark scripts.

Start the benchmark-owned services with:

```powershell
docker compose -f docker-compose.benchmark.yml up -d online-boutique-frontend prometheus
```

The `online-boutique-frontend` compose service is a small TCP proxy.

It forwards compose-network traffic from:

```text
http://online-boutique-frontend:8080
```

to:

```text
host.docker.internal:${ONLINE_BOUTIQUE_HOST_PORT:-8080}
```

This keeps benchmark scripts, traffic helpers and Prometheus probes on stable compose service names while Online Boutique itself runs from the pinned upstream checkout.

The compose file also defines profile-gated helper containers:

| Helper              | Purpose                                                                          |
| ------------------- | -------------------------------------------------------------------------------- |
| `playwright-runner` | Lists or runs the benchmark Playwright harness once Online Boutique is reachable |
| `traffic-standard`  | Generates normal warm-up traffic                                                 |
| `traffic-spike`     | Generates focused product-page traffic                                           |
| `qmind-runner`      | Placeholder for a future packaged Quantik Mind CLI path                          |

Run the Playwright helper profile:

```powershell
docker compose -f docker-compose.benchmark.yml --profile tools run --rm playwright-runner
```

Run standard warm-up traffic:

```powershell
docker compose -f docker-compose.benchmark.yml --profile traffic run --rm traffic-standard
```

Run local spike traffic:

```powershell
docker compose -f docker-compose.benchmark.yml --profile spike run --rm traffic-spike
```

---

## Prometheus Observability

Prometheus is exposed at:

| Context         | URL                      |
| --------------- | ------------------------ |
| Host            | `http://localhost:9090`  |
| Compose network | `http://prometheus:9090` |

The benchmark Prometheus configuration scrapes:

* `prometheus:9090`;
* `blackbox-exporter:9115`;
* blackbox HTTP probes for:

  * `http://online-boutique-frontend:8080/`;
  * `/product/OLJCESPC7Z`;
  * `/cart`.

Useful verification queries:

```promql
up
probe_success{job="online-boutique-probes"}
probe_duration_seconds{job="online-boutique-probes"}
```

The observability templates under `qmind-config/` describe the higher-fidelity service metrics expected from the Kubernetes benchmark environment.

Examples include service-level request rate, latency, error rate and health signals.

The local compose foundation adds reproducible probing and traffic.

It does not synthesize full per-service metrics for every Online Boutique service.

---

## Quantik Mind Configuration

Copy the environment template:

```powershell
Copy-Item .env.example .env
```

Copy the Quantik Mind configuration template if your CLI expects `qmind.yaml` in the repository root:

```powershell
Copy-Item qmind.example.yaml qmind.yaml
```

The template uses environment placeholders such as:

```text
${QMIND_API_URL}
${QMIND_API_KEY}
${QMIND_PROJECT_ID}
```

If the installed Quantik Mind CLI does not interpolate environment variables in YAML configuration, replace the placeholders manually before running:

```powershell
qmind init
```

---

## Quantik Mind Benchmark Scripts

The reproducible Quantik Mind-side scripts live under:

```text
benchmark-pipeline/
```

| Script                          | Purpose                                                                                                                                          |
| ------------------------------- | ------------------------------------------------------------------------------------------------------------------------------------------------ |
| `setup-qmind.ps1`               | Loads `.env`, validates required Quantik Mind settings, writes `qmind.yaml` from the template without embedding secrets, and runs initialization |
| `sync-library.ps1`              | Validates and syncs the canonical benchmark test library                                                                                         |
| `import-history.ps1`            | Generates synthetic benchmark history and imports it when supported                                                                              |
| `configure-observability.ps1`   | Configures Prometheus observability from the benchmark template and checks status                                                                |
| `run-qmind-subset.ps1`          | Runs a changed-files subset and normalizes output to canonical test IDs                                                                          |
| `evaluate-qmind.ps1`            | Evaluates a Quantik Mind selection for one benchmark case                                                                                        |
| `generate-final-comparison.ps1` | Generates the aggregate comparison across all strategies and benchmark cases                                                                     |

Most scripts support:

```powershell
-DryRun
```

Use this option to inspect the command path without contacting Quantik Mind.

Real live runs require:

```text
QMIND_API_URL
QMIND_API_KEY
QMIND_PROJECT_ID
```

---

## Limitations

This benchmark is intentionally scoped.

It demonstrates runtime-aware selection behavior on seven defined Online Boutique benchmark cases.

It does not demonstrate universal superiority across:

* all applications;
* all defect classes;
* all test suites;
* all traffic profiles;
* all observability configurations;
* all CI/CD environments.

The static baseline is intentionally strong and transparent.

The benchmark value appears specifically in the runtime-aware and combined-signal cases, where code-change and history signals alone do not fully explain current system risk.

The benchmark is also not a full product onboarding guide.

Product onboarding is included only to the extent needed for live regeneration.

---

## Not Yet Automated

The following areas are intentionally left for future improvements:

* one-command Online Boutique startup across Docker Desktop, minikube, kind and Skaffold variants;
* local per-service Prometheus metrics equivalent to the Kubernetes observability profile;
* packaged Quantik Mind CLI execution through the benchmark runner container;
* one-command end-to-end startup across Online Boutique, Prometheus, Quantik Mind, Playwright and the evaluator.

---

## About

Reproducible benchmark artifacts for Quantik Mind using Google Online Boutique, Playwright, Prometheus, runtime signals and defect-recall evaluation.

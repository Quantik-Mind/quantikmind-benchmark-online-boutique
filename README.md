# Quantik Mind Online Boutique Benchmark

This repository contains the reproducibility artifacts for the Quantik Mind Online Boutique benchmark.

Final validated benchmark result:

- Quantik Mind selected 15 of 51 tests
- 70.6% execution reduction
- 4 of 4 validated defect scenarios detected
- 100.0% defect recall

This PR creates the local Docker Compose foundation for fresh-user reproducibility, including Prometheus, frontend probing, traffic helpers, and safe configuration templates. It does not implement the full one-command benchmark automation yet, and it does not change the benchmark logic, defect oracle, canonical 51-test library, evaluation logic, or final benchmark numbers.

## Fresh-User Flow

1. Create or log in to Quantik Mind.
2. Verify your email address.
3. Create a project for the Online Boutique benchmark.
4. Create or copy an API key for that project.
5. Clone this benchmark repository.
6. Clone the pinned upstream Online Boutique source next to this runbook:

   ```powershell
   git clone https://github.com/GoogleCloudPlatform/microservices-demo.git microservices-demo
   git -C microservices-demo checkout b7ecc96372238b0dda6cefaf95cc2c3e9118ea73
   ```

   `microservices-demo/` is intentionally ignored by git so this benchmark repo does not vendor the upstream application.

7. Start Online Boutique locally with Skaffold or the upstream Kubernetes manifests:

   ```powershell
   Push-Location microservices-demo
   skaffold run
   Pop-Location
   ```

   For local clusters that require a remote image repository, run the equivalent Skaffold command with your environment's image repository settings. The pinned upstream checkout does not contain a Docker Compose stack.

8. Expose the Online Boutique frontend on the host:

   ```powershell
   kubectl port-forward service/frontend 8080:80
   ```

9. Copy `.env.example` to `.env` and replace the Quantik Mind placeholder values. Leave `ONLINE_BOUTIQUE_HOST_PORT=8080` if using the port-forward above.
10. Start the local benchmark stack foundation:

   ```powershell
   docker compose -f docker-compose.benchmark.yml up -d online-boutique-frontend prometheus
   ```

11. Verify Prometheus at `http://localhost:9090` from the host. Inside compose, services use `http://prometheus:9090`.
12. Run standard warm-up traffic:

   ```powershell
   docker compose -f docker-compose.benchmark.yml --profile traffic run --rm traffic-standard
   ```

13. Set up the Quantik Mind CLI config from `.env`:

   ```powershell
   .\benchmark-pipeline\setup-qmind.ps1
   ```

14. Sync the canonical 51-test library:

   ```powershell
   .\benchmark-pipeline\sync-library.ps1
   ```

15. Generate and import benchmark history:

   ```powershell
   .\benchmark-pipeline\import-history.ps1
   ```

   If your installed CLI uses a different history import command, run the script with `-GenerateOnly` and import the generated artifacts from `benchmark-runs/qmind-online-boutique/` manually.

16. Configure Prometheus observability and check status:

   ```powershell
   .\benchmark-pipeline\configure-observability.ps1
   ```

17. Run the Quantik Mind changed-files subset:

   ```powershell
   .\benchmark-pipeline\run-qmind-subset.ps1
   ```

   This reads `benchmark-runs/scenario-ob004-changed-files.json` and writes canonical test IDs to `benchmark-runs/qmind-online-boutique/qmind-current-selection.json`.

18. Evaluate the Quantik Mind selection:

   ```powershell
   .\benchmark-pipeline\evaluate-qmind.ps1
   ```

The current compose file intentionally starts the services that are under this repository's control. Prometheus is included and runs on the compose network as `http://prometheus:9090`.

## Local Stack

This repository does not vendor Google Online Boutique. Use the pinned upstream clone:

```powershell
git clone https://github.com/GoogleCloudPlatform/microservices-demo.git microservices-demo
git -C microservices-demo checkout b7ecc96372238b0dda6cefaf95cc2c3e9118ea73
```

Start Online Boutique from that checkout using Skaffold or the upstream Kubernetes manifests, then expose the frontend to the host:

```powershell
kubectl port-forward service/frontend 8080:80
```

Start the benchmark-owned compose services:

```powershell
docker compose -f docker-compose.benchmark.yml up -d online-boutique-frontend prometheus
```

Check the rendered compose configuration:

```powershell
docker compose -f docker-compose.benchmark.yml config
```

The `online-boutique-frontend` compose service is a small TCP proxy. It forwards compose-network traffic from `http://online-boutique-frontend:8080` to `host.docker.internal:${ONLINE_BOUTIQUE_HOST_PORT:-8080}`. This keeps Prometheus, Playwright, and traffic commands on stable compose service names while Online Boutique itself runs from the pinned upstream checkout.

The compose file also defines profile-gated runner containers:

- `playwright-runner`: a Playwright container mounted on this repo for listing or running the harness once Online Boutique is reachable.
- `traffic-standard`: a normal warm-up traffic helper that hits home, product, and cart pages.
- `traffic-spike`: a focused product-page spike helper for local compose-network traffic.
- `qmind-runner`: a placeholder container for the future packaged Quantik Mind CLI path.

Run the Playwright helper profile when the Online Boutique frontend is available on the compose network:

```powershell
docker compose -f docker-compose.benchmark.yml --profile tools run --rm playwright-runner
```

Run normal warm-up traffic:

```powershell
docker compose -f docker-compose.benchmark.yml --profile traffic run --rm traffic-standard
```

Run local spike traffic:

```powershell
docker compose -f docker-compose.benchmark.yml --profile spike run --rm traffic-spike
```

The Kubernetes-only adaptive spike helper remains at `runtime-scenarios/adaptive-entanglement/run-adaptive-scenario.ps1`. Use it only when Online Boutique is running in Kubernetes and you want the spike pod inside the cluster:

```powershell
.\runtime-scenarios\adaptive-entanglement\run-adaptive-scenario.ps1
```

PR 3 or PR 4 should decide whether the local compose spike helper fully replaces that Kubernetes scenario or whether both remain as first-class runbook paths.

## Prometheus

Prometheus is exposed at:

- Host: `http://localhost:9090`
- Compose network: `http://prometheus:9090`

The benchmark Prometheus config avoids private LAN IPs. It scrapes:

- `prometheus:9090`
- `blackbox-exporter:9115`
- blackbox HTTP probes for `http://online-boutique-frontend:8080/`, `/product/OLJCESPC7Z`, and `/cart`

Useful verification queries:

```promql
up
probe_success{job="online-boutique-probes"}
probe_duration_seconds{job="online-boutique-probes"}
```

The observability templates in `qmind-config/` still describe the higher-fidelity service metrics expected from the Linkerd/Kubernetes benchmark environment, such as `inbound_http_requests_total`. The compose foundation adds reproducible local probing and traffic; it does not yet synthesize per-service request-rate/error-rate metrics for every Online Boutique service.

## Configuration Templates

Copy the environment template:

```powershell
Copy-Item .env.example .env
```

Copy the qmind template if your CLI expects `qmind.yaml` in the repo root:

```powershell
Copy-Item qmind.example.yaml qmind.yaml
```

`qmind.example.yaml` uses environment placeholders such as `${QMIND_API_URL}`. If the current Quantik Mind CLI does not interpolate environment variables in YAML config, copy the file and replace those placeholders manually before running `qmind init`.

## Benchmark Artifacts

The canonical test library is `qmind-test-library/online-boutique-playwright-51.json`.

The final comparison result is `benchmark-results/final-comparison/final-comparison.json`.

Evaluation helpers and runbook details live in `benchmark-pipeline/README.md`.

## QMind CLI Scripts

The reproducible QMind-side scripts live under `benchmark-pipeline/`:

- `setup-qmind.ps1`: loads `.env`, validates required QMind settings, writes `qmind.yaml` from the template without embedding secrets, and runs `qmind init`.
- `sync-library.ps1`: validates and syncs the canonical 51-test library.
- `import-history.ps1`: generates synthetic benchmark history and imports it through the CLI when supported.
- `configure-observability.ps1`: configures Prometheus observability from `qmind-config/observability-online-boutique.example.yaml` and runs status.
- `run-qmind-subset.ps1`: runs the changed-files subset and normalizes the output to canonical test IDs.
- `evaluate-qmind.ps1`: evaluates the current QMind selection and validates the expected measured benchmark values.

Most scripts support `-DryRun` to print the command path without contacting QMind. Real runs require `.env` values for `QMIND_API_URL`, `QMIND_API_KEY`, and `QMIND_PROJECT_ID`.

## Not Yet Automated

This foundation deliberately leaves the following for later PRs:

- One-command Online Boutique startup across Docker Desktop, minikube, kind, and Skaffold image-building variants.
- Local per-service Prometheus metrics equivalent to the Linkerd/Kubernetes observability profile.
- Packaging the Quantik Mind CLI in the `qmind-runner` container.
- End-to-end orchestration across Online Boutique, Prometheus, qmind, Playwright, and the evaluator.

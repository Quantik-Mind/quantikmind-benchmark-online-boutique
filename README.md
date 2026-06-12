# Quantik Mind Online Boutique Benchmark

This repository contains the reproducibility artifacts for the Quantik Mind Online Boutique benchmark.

Final validated benchmark result:

- Quantik Mind selected 15 of 51 tests
- 70.6% execution reduction
- 4 of 4 validated defect scenarios detected
- 100.0% defect recall

This PR creates the local Docker Compose foundation for fresh-user reproducibility, including Prometheus and safe configuration templates. It does not implement the full one-command benchmark automation yet, and it does not change the benchmark logic, defect oracle, canonical 51-test library, evaluation logic, or final benchmark numbers.

## Fresh-User Flow

1. Create or log in to Quantik Mind.
2. Verify your email address.
3. Create a project for the Online Boutique benchmark.
4. Create or copy an API key for that project.
5. Clone this benchmark repository.
6. Copy `.env.example` to `.env` and replace the placeholder values.
7. Start the local benchmark stack foundation:

   ```powershell
   docker compose -f docker-compose.benchmark.yml up -d prometheus
   ```

8. Run `qmind init` using the project values from `.env` and the paths from `qmind.example.yaml`.
9. Configure observability with Prometheus using `qmind-config/observability-online-boutique.example.yaml`.
10. Sync the canonical 51-test library from `qmind-test-library/online-boutique-playwright-51.json`.
11. Generate or import benchmark history for the project.
12. Run the Quantik Mind subset selection using the changed-files scenario context.
13. Run the evaluations and final comparison scripts under `benchmark-pipeline/`.

The current compose file intentionally starts the services that are under this repository's control. Prometheus is included and runs on the compose network as `http://prometheus:9090`.

## Local Stack

Start Prometheus:

```powershell
docker compose -f docker-compose.benchmark.yml up -d prometheus
```

Check the rendered compose configuration:

```powershell
docker compose -f docker-compose.benchmark.yml config
```

The compose file also defines profile-gated runner containers:

- `playwright-runner`: a Playwright container mounted on this repo for listing or running the harness once Online Boutique is reachable.
- `qmind-runner`: a placeholder container for the future packaged Quantik Mind CLI path.

Run the Playwright helper profile when the Online Boutique frontend is available on the compose network:

```powershell
docker compose -f docker-compose.benchmark.yml --profile tools run --rm playwright-runner
```

The upstream Online Boutique `microservices-demo` source is not vendored in this repository; it is ignored by git. PR 2 should pin or bring in a reproducible local Online Boutique compose dependency and wire it to this benchmark network. Until then, start Online Boutique separately and make its frontend reachable as `online-boutique-frontend:8080`, or adjust `ONLINE_BOUTIQUE_FRONTEND_URL` in `.env`.

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

## Not Yet Automated

This foundation deliberately leaves the following for later PRs:

- Pinning or vendoring a reproducible local Online Boutique compose stack.
- Packaging the Quantik Mind CLI in the `qmind-runner` container.
- One-command history generation, subset selection, and comparison.
- End-to-end orchestration across Online Boutique, Prometheus, qmind, Playwright, and the evaluator.

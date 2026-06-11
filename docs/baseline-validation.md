# Baseline Validation

## Purpose

Baseline validation confirms that the canonical Online Boutique Playwright suite is stable against a clean Online Boutique deployment before any benchmark defect scenarios are implemented.

The baseline run is the clean-control check for the benchmark. It answers one question: can the full canonical 50-test library run successfully against the application when no benchmark defect has been injected?

## Why baseline validation is required before defect injection

Defect recall measurements only make sense if the clean system is already understood. If the full suite fails before a scenario is introduced, later failures cannot be attributed confidently to the scenario.

Run baseline validation before scenario work so that:

- clean-deployment failures are separated from injected-defect failures
- flaky tests are identified before they pollute scenario evidence
- the canonical 50-test library is confirmed runnable in the current harness
- later oracle validation can compare scenario failures against a known stable baseline

Defect scenarios must not be implemented until the clean baseline is stable.

## Preconditions

- Online Boutique is deployed and reachable.
- `FRONTEND_URL` is known, for example `http://YOUR_FRONTEND_URL`.
- Playwright dependencies are installed under `qmind-test-harness/playwright`.
- The canonical 50-test library exists at `qmind-test-library/online-boutique-playwright-50.json`.

## Run the full 50-test suite

Use the baseline validation helper from the repository root:

```powershell
powershell -ExecutionPolicy Bypass -File benchmark-pipeline/run-baseline-validation.ps1 -FrontendUrl http://YOUR_FRONTEND_URL
```

By default, the helper runs the `chromium` project with 2 Playwright workers and writes outputs under `benchmark-runs/baseline-validation`. The 2-worker default improves stability for the Online Boutique benchmark compared with Playwright's higher default worker count.

To choose a different output directory, Playwright project, or worker count:

```powershell
powershell -ExecutionPolicy Bypass -File benchmark-pipeline/run-baseline-validation.ps1 `
  -FrontendUrl http://YOUR_FRONTEND_URL `
  -OutputDir benchmark-runs/baseline-validation `
  -Project chromium `
  -Workers 2
```

The helper sets `FRONTEND_URL` for the current process, changes into `qmind-test-harness/playwright`, and runs:

```powershell
npx playwright test --project=chromium --workers=2 --reporter=json,junit
```

Override `-Workers` only when validating an intentional concurrency change.

Reporter output paths are configured through Playwright reporter environment variables:

- `PLAYWRIGHT_JUNIT_OUTPUT_NAME`
- `PLAYWRIGHT_JSON_OUTPUT_NAME`

## Expected output locations

The default output files are:

- `benchmark-runs/baseline-validation/playwright-junit.xml`
- `benchmark-runs/baseline-validation/playwright-results.json`

Playwright failure artifacts such as traces and screenshots may also be produced under the harness test-results directory, depending on the Playwright configuration.

`benchmark-runs/` is ignored by git and is intended for generated local run evidence.

## Interpreting results

If all tests pass, the clean deployment and canonical test suite are stable enough to proceed toward scenario implementation and later scenario-specific validation.

If known flaky failures appear, record the failing test IDs, failure modes, and rerun evidence before treating the baseline as usable. Flakiness should be understood well enough that scenario failures can still be interpreted safely.

If baseline failures are reproducible and not known flakes, fix the deployment, harness, or test-library issue before any defect scenario work. These failures are baseline blockers because they would make later defect-detection evidence ambiguous.

## Relationship to later oracle validation

Baseline validation validates the test suite against the clean application. It does not validate defect recall.

Scenario branches validate detecting tests. Once a defect scenario exists, the full suite must be run against that scenario branch, observed failures must be mapped to the oracle, and `validated_detecting_tests` must be updated from real evidence.

## Expected recall matrix warning

Expected recall matrix results are not validated benchmark evidence yet.

The expected recall matrix runner uses planned oracle expectations to validate the comparison pipeline. Validated benchmark evidence requires stable clean-baseline results, implemented scenario branches, observed scenario failures, and final oracle updates based on those observed failures.

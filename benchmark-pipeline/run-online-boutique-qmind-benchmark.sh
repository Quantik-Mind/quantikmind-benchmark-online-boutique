#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="${ROOT_DIR:-/workspace}"
RUN_DIR="$ROOT_DIR/benchmark-runs/qmind-online-boutique"

PROJECT_NAME="${PROJECT_NAME:-google-online-boutique}"
PROJECT_ID="${PROJECT_ID:-}"
QMIND_API_URL="${QMIND_API_URL:-}"
QMIND_API_KEY="${QMIND_API_KEY:-}"

TEST_LIBRARY="${TEST_LIBRARY:-$ROOT_DIR/qmind-test-library/online-boutique-playwright-51.json}"
OBSERVABILITY_CONFIG="$ROOT_DIR/qmind-config/observability-online-boutique.container.yaml"
PROMETHEUS_URL="${PROMETHEUS_URL:-http://34.185.226.81:9090}"

COMMIT_SHA="${COMMIT_SHA:-benchmark-payment-checkout-001}"
COMMIT_BRANCH="${COMMIT_BRANCH:-benchmark/online-boutique}"
COMMIT_MESSAGE="${COMMIT_MESSAGE:-Change payment validation and checkout order handling}"

mkdir -p "$RUN_DIR"

echo "== Quantik Mind Online Boutique benchmark =="
echo "Root: $ROOT_DIR"
echo "Run dir: $RUN_DIR"
echo "Project name: $PROJECT_NAME"
echo "Test library: $TEST_LIBRARY"
echo "Prometheus: $PROMETHEUS_URL"
echo

echo "== 1. qmind init =="
INIT_ARGS=(
  init
  --framework playwright
  --test-dir "$ROOT_DIR/qmind-test-harness/playwright/tests"
  --results-dir "$ROOT_DIR/qmind-test-harness/playwright/test-results"
  --non-interactive
)

if [[ -n "$QMIND_API_URL" ]]; then
  INIT_ARGS+=(--api-url "$QMIND_API_URL")
fi

if [[ -n "$QMIND_API_KEY" ]]; then
  INIT_ARGS+=(--api-key "$QMIND_API_KEY")
fi

if [[ -n "$PROJECT_ID" ]]; then
  INIT_ARGS+=(--project-id "$PROJECT_ID")
else
  INIT_ARGS+=(--project-name "$PROJECT_NAME")
fi

qmind "${INIT_ARGS[@]}" | tee "$RUN_DIR/qmind-init.log"
echo

echo "== 2. qmind status =="
qmind status | tee "$RUN_DIR/qmind-status.log" || true
echo

echo "== 3. sync test library =="
qmind sync library \
  --file "$TEST_LIBRARY" \
  | tee "$RUN_DIR/qmind-sync-library.log"
echo

echo "== 4. configure Prometheus observability =="
qmind observability configure prometheus \
  --url "$PROMETHEUS_URL" \
  --file "$OBSERVABILITY_CONFIG" \
  --service-label "deployment" \
  | tee "$RUN_DIR/qmind-observability-configure.log"
echo

echo "== 5. check observability status =="
qmind observability status \
  | tee "$RUN_DIR/qmind-observability-status.log"
echo

echo "== 6. record build context =="
qmind record build \
  --commit "$COMMIT_SHA" \
  --branch "$COMMIT_BRANCH" \
  --message "$COMMIT_MESSAGE" \
  | tee "$RUN_DIR/qmind-record-build.log"
echo

echo "== 7. select test subset =="
qmind subset \
  --framework playwright \
  | tee "$RUN_DIR/qmind-subset-raw.txt"
echo

echo "== 8. normalize selected tests =="
python3 "$ROOT_DIR/benchmark-pipeline/normalize-qmind-selection.py" \
  "$RUN_DIR/qmind-subset-raw.txt" \
  "$RUN_DIR/selected-tests.json"
echo

echo "== 9. evaluate defect retention =="
python3 "$ROOT_DIR/benchmark-pipeline/evaluate-selection.py" \
  | tee "$RUN_DIR/selection-report.pretty.json"
echo

echo "== Benchmark completed =="
echo "Raw selection: $RUN_DIR/qmind-subset-raw.txt"
echo "Selected tests: $RUN_DIR/selected-tests.json"
echo "Report: $RUN_DIR/selection-report.json"

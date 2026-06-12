param(
    [string]$Selection = "benchmark-runs/qmind-online-boutique/qmind-current-selection.json",
    [string]$Output = "benchmark-results/final-comparison/qmind-current-evaluation.json",
    [string]$Oracle = "defect-oracle/online-boutique-defect-oracle.v2.json",
    [switch]$DryRun
)

$ErrorActionPreference = "Stop"

if (-not (Test-Path -LiteralPath $Selection -PathType Leaf)) {
    throw "Missing QMind selection file: $Selection. Run benchmark-pipeline/run-qmind-subset.ps1 first."
}
if (-not (Test-Path -LiteralPath $Oracle -PathType Leaf)) {
    throw "Missing defect oracle: $Oracle"
}

$args = @(
    "benchmark-pipeline/evaluate-defect-recall.py",
    "--oracle", $Oracle,
    "--selected", $Selection,
    "--method", "qmind",
    "--use-validated",
    "--output", $Output
)

Write-Host ("python " + ($args -join " "))
if ($DryRun) {
    Write-Host "Dry run complete; evaluation was not written."
    exit 0
}

& python @args
if ($LASTEXITCODE -ne 0) {
    throw "QMind evaluation failed."
}

$evaluation = Get-Content -LiteralPath $Output -Raw | ConvertFrom-Json
if ([int]$evaluation.selected_test_count -ne 15) {
    throw "Expected selected_test_count = 15, found $($evaluation.selected_test_count)."
}
if ([double]$evaluation.defect_recall -ne 1.0) {
    throw "Expected defect_recall = 1.0, found $($evaluation.defect_recall)."
}
if ([int]$evaluation.detected_scenarios_count -ne 4) {
    throw "Expected detected_scenarios_count = 4, found $($evaluation.detected_scenarios_count)."
}

Write-Host "QMind evaluation validated: 15 selected tests, 4 detected scenarios, defect recall 1.0."

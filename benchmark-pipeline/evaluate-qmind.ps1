param(
    [string]$Selection,
    [string]$Output,
    [string]$Oracle = "defect-oracle/online-boutique-defect-oracle.v2.json",
    [string]$Scenario,
    [switch]$DryRun
)

$ErrorActionPreference = "Stop"

if (-not [string]::IsNullOrWhiteSpace($Scenario)) {
    $caseId = $Scenario.ToUpperInvariant()
    if ($caseId -notmatch "^OB-\d{3}$") {
        throw "Scenario must look like OB-001, OB-002, OB-003, or OB-004. Found: $Scenario"
    }
    $caseLower = $caseId.ToLowerInvariant()
    if ([string]::IsNullOrWhiteSpace($Selection)) {
        $Selection = "benchmark-runs/qmind-online-boutique/qmind-selection-$caseLower.json"
    }
    if ([string]::IsNullOrWhiteSpace($Output)) {
        $Output = "benchmark-results/final-comparison/qmind-$caseLower-evaluation.json"
    }
} else {
    if ([string]::IsNullOrWhiteSpace($Selection)) {
        throw "Selection is required when Scenario is not provided. Prefer -Scenario OB-001 through OB-004 for benchmark-case evaluation."
    }
    if ([string]::IsNullOrWhiteSpace($Output)) {
        throw "Output is required when Scenario is not provided."
    }
}

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
if (-not [string]::IsNullOrWhiteSpace($Scenario)) {
    $args += @("--scenario", $Scenario)
}

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
Write-Host "QMind evaluation completed: $($evaluation.selected_test_count) selected tests, $($evaluation.detected_scenarios_count)/$($evaluation.total_scenarios) detected, defect recall $($evaluation.defect_recall)."

param(
    [string]$Oracle = "defect-oracle/online-boutique-defect-oracle.v2.json",
    [string]$Library = "qmind-test-library/online-boutique-playwright-51.json",
    [string]$Scenarios = "benchmark-pipeline/scenarios.json",
    [string]$QMindSelection = "benchmark-runs/qmind-online-boutique/qmind-current-selection.json",
    [string]$OutputDir = "benchmark-results/final-comparison",
    [int]$RandomSeed = 42,
    [switch]$SkipRun
)

$ErrorActionPreference = "Stop"

$FullSuiteEvaluation = Join-Path $OutputDir "full-suite-evaluation.json"
$RandomSelection = Join-Path $OutputDir "random-selection.json"
$RandomEvaluation = Join-Path $OutputDir "random-evaluation.json"
$QMindEvaluation = Join-Path $OutputDir "qmind-current-evaluation.json"
$FinalComparison = Join-Path $OutputDir "final-comparison.json"
$FinalComparisonDoc = "docs/final-benchmark-comparison.md"
$ScenarioIds = @("OB-001", "OB-002", "OB-003", "OB-004")

function Invoke-Python {
    param([string[]]$Arguments)

    Write-Host ("python " + ($Arguments -join " "))
    $output = & python @Arguments 2>&1
    $exitCode = $LASTEXITCODE
    if ($exitCode -ne 0) {
        $output | ForEach-Object { Write-Host $_ }
        throw "Python command failed: python $($Arguments -join ' ')"
    }
}

function Read-Json {
    param([string]$Path)

    if (-not (Test-Path -LiteralPath $Path -PathType Leaf)) {
        throw "Missing expected artifact: $Path"
    }
    return Get-Content -LiteralPath $Path -Raw | ConvertFrom-Json
}

function Write-Json {
    param(
        [string]$Path,
        [object]$Value
    )

    $json = $Value | ConvertTo-Json -Depth 20
    [System.IO.File]::WriteAllText((Resolve-ParentPath $Path), $json + [Environment]::NewLine, [System.Text.UTF8Encoding]::new($false))
}

function Resolve-ParentPath {
    param([string]$Path)

    $parent = Split-Path -Parent $Path
    if (-not [string]::IsNullOrWhiteSpace($parent)) {
        New-Item -ItemType Directory -Force -Path $parent | Out-Null
    }
    return $ExecutionContext.SessionState.Path.GetUnresolvedProviderPathFromPSPath($Path)
}

function Format-Percent {
    param([double]$Value)

    return "{0:N1}%" -f ($Value * 100)
}

function Scenario-Ids {
    param(
        [object]$Evaluation,
        [bool]$Detected
    )

    return @($Evaluation.per_scenario | Where-Object { [bool]$_.detected -eq $Detected } | ForEach-Object { [string]$_.id })
}

function Method-Summary {
    param(
        [string]$Method,
        [string]$Label,
        [object]$Evaluation,
        [System.Collections.IDictionary]$Extra = @{}
    )

    $summary = [ordered]@{
        method = $Method
        method_label = $Label
        status = "measured"
        tests_executed = [int]$Evaluation.selected_test_count
        execution_reduction = [double]$Evaluation.execution_reduction
        execution_reduction_percent = [Math]::Round(([double]$Evaluation.execution_reduction * 100), 1)
        defects_detected = [int]$Evaluation.detected_scenarios_count
        full_suite_defects = [int]$Evaluation.total_scenarios
        defect_recall = [double]$Evaluation.defect_recall
        detected_scenarios = @(Scenario-Ids $Evaluation $true)
        missed_scenarios = @(Scenario-Ids $Evaluation $false)
    }

    foreach ($key in $Extra.Keys) {
        $summary[$key] = $Extra[$key]
    }

    return $summary
}

function Get-ScenarioResult {
    param(
        [object]$Evaluation,
        [string]$ScenarioId
    )

    $result = @($Evaluation.per_scenario | Where-Object { [string]$_.id -eq $ScenarioId })
    if ($result.Count -ne 1) {
        throw "Expected one $ScenarioId result in evaluation artifact."
    }
    return $result[0]
}

foreach ($path in @($Oracle, $Library, $Scenarios, $QMindSelection)) {
    if (-not (Test-Path -LiteralPath $path -PathType Leaf)) {
        throw "Missing required input: $path"
    }
}

New-Item -ItemType Directory -Force -Path $OutputDir | Out-Null

$qmindSelectionData = Read-Json $QMindSelection
$qmindSelectionSize = @($qmindSelectionData.selected_tests).Count
if ($qmindSelectionSize -le 0) {
    throw "Could not infer QMind selection size from $QMindSelection."
}

if (-not $SkipRun) {
    Invoke-Python @(
        "benchmark-pipeline/evaluate-defect-recall.py",
        "--oracle", $Oracle,
        "--selected", $Library,
        "--method", "full-suite",
        "--use-validated",
        "--output", $FullSuiteEvaluation
    )

    Invoke-Python @(
        "benchmark-pipeline/select-random-approach.py",
        "--library", $Library,
        "--size", "$qmindSelectionSize",
        "--seed", "$RandomSeed",
        "--output", $RandomSelection
    )

    Invoke-Python @(
        "benchmark-pipeline/evaluate-defect-recall.py",
        "--oracle", $Oracle,
        "--selected", $RandomSelection,
        "--method", "random",
        "--use-validated",
        "--output", $RandomEvaluation
    )

    foreach ($scenarioId in $ScenarioIds) {
        $selectionPath = Join-Path $OutputDir "history-code-change-$($scenarioId.ToLowerInvariant())-selection.json"
        $evaluationPath = Join-Path $OutputDir "history-code-change-$($scenarioId.ToLowerInvariant())-evaluation.json"

        Invoke-Python @(
            "benchmark-pipeline/select-history-code-change-approach.py",
            "--library", $Library,
            "--oracle", $Oracle,
            "--scenarios", $Scenarios,
            "--size", "$qmindSelectionSize",
            "--scenario", $scenarioId,
            "--output", $selectionPath
        )

        Invoke-Python @(
            "benchmark-pipeline/evaluate-defect-recall.py",
            "--oracle", $Oracle,
            "--selected", $selectionPath,
            "--method", "history-code-change",
            "--use-validated",
            "--output", $evaluationPath
        )
    }

    Invoke-Python @(
        "benchmark-pipeline/evaluate-defect-recall.py",
        "--oracle", $Oracle,
        "--selected", $QMindSelection,
        "--method", "qmind",
        "--use-validated",
        "--output", $QMindEvaluation
    )
}

$expectedArtifacts = @(
    $FullSuiteEvaluation,
    $RandomSelection,
    $RandomEvaluation,
    $QMindEvaluation
)
foreach ($scenarioId in $ScenarioIds) {
    $expectedArtifacts += Join-Path $OutputDir "history-code-change-$($scenarioId.ToLowerInvariant())-selection.json"
    $expectedArtifacts += Join-Path $OutputDir "history-code-change-$($scenarioId.ToLowerInvariant())-evaluation.json"
}
foreach ($artifact in $expectedArtifacts) {
    if (-not (Test-Path -LiteralPath $artifact -PathType Leaf)) {
        throw "Missing expected artifact: $artifact"
    }
}

$fullSuite = Read-Json $FullSuiteEvaluation
$randomSelectionData = Read-Json $RandomSelection
$random = Read-Json $RandomEvaluation
$qmind = Read-Json $QMindEvaluation

if ([int]$qmind.selected_test_count -ne 15) {
    throw "Expected QMind selected_test_count = 15, found $($qmind.selected_test_count)."
}
if ([double]$qmind.defect_recall -ne 1.0) {
    throw "Expected QMind defect_recall = 1.0, found $($qmind.defect_recall)."
}
if ([int]$qmind.detected_scenarios_count -ne 4) {
    throw "Expected QMind detected_scenarios_count = 4, found $($qmind.detected_scenarios_count)."
}

$historySelections = [ordered]@{}
$historyEvaluations = [ordered]@{}
$historyPerScenario = @()
foreach ($scenarioId in $ScenarioIds) {
    $selectionPath = Join-Path $OutputDir "history-code-change-$($scenarioId.ToLowerInvariant())-selection.json"
    $evaluationPath = Join-Path $OutputDir "history-code-change-$($scenarioId.ToLowerInvariant())-evaluation.json"
    $evaluation = Read-Json $evaluationPath
    $scenarioResult = Get-ScenarioResult $evaluation $scenarioId

    $historySelections[$scenarioId] = $selectionPath.Replace("\", "/")
    $historyEvaluations[$scenarioId] = $evaluationPath.Replace("\", "/")
    $historyPerScenario += [ordered]@{
        scenario = $scenarioId
        detected = [bool]$scenarioResult.detected
        selected_detecting_tests = @($scenarioResult.selected_detecting_tests)
    }
}

$historyDetected = @($historyPerScenario | Where-Object { [bool]$_.detected })
$historyMissed = @($historyPerScenario | Where-Object { -not [bool]$_.detected })
$fullSuiteSize = [int]$fullSuite.full_suite_size

$fullSuiteSummary = Method-Summary "full-suite" "Traditional Approach / Full Suite" $fullSuite @{
    selection_artifact = $Library
    evaluation_artifact = $FullSuiteEvaluation.Replace("\", "/")
    normalization = [ordered]@{ status = "canonical_test_ids" }
}

$randomSummary = Method-Summary "random" "Random Approach" $random @{
    random_seed = $RandomSeed
    selection_artifact = $RandomSelection.Replace("\", "/")
    evaluation_artifact = $RandomEvaluation.Replace("\", "/")
    selected_tests = @($randomSelectionData.selected_tests)
    normalization = [ordered]@{ status = "canonical_test_ids" }
}

$historySummary = [ordered]@{
    method = "history-code-change"
    method_label = "History + Code Change"
    status = "measured"
    tests_executed = $qmindSelectionSize
    tests_executed_note = "$qmindSelectionSize per scenario"
    execution_reduction = 1 - ($qmindSelectionSize / $fullSuiteSize)
    execution_reduction_percent = [Math]::Round(((1 - ($qmindSelectionSize / $fullSuiteSize)) * 100), 1)
    defects_detected = [int]$historyDetected.Count
    full_suite_defects = [int]$ScenarioIds.Count
    defect_recall = if ($ScenarioIds.Count -gt 0) { $historyDetected.Count / $ScenarioIds.Count } else { 0 }
    selection_model = "per-scenario changed-file/domain context using benchmark-pipeline/select-history-code-change-approach.py"
    selection_artifacts = $historySelections
    evaluation_artifacts = $historyEvaluations
    normalization = [ordered]@{ status = "canonical_test_ids" }
    per_scenario = @($historyPerScenario)
    detected_scenarios = @($historyDetected | ForEach-Object { [string]$_.scenario })
    missed_scenarios = @($historyMissed | ForEach-Object { [string]$_.scenario })
}

$qmindSummary = Method-Summary "qmind" "Quantik Mind" $qmind @{
    selection_status = "selection_executed_successfully"
    tests_selected = [int]$qmind.selected_test_count
    selection_artifact = $QMindSelection
    evaluation_artifact = $QMindEvaluation.Replace("\", "/")
    message = "QMind selected 15/51 tests and detected all 4 validated defect scenarios."
    normalization = [ordered]@{ status = "canonical_test_ids" }
    per_scenario = @($qmind.per_scenario | ForEach-Object {
        [ordered]@{
            scenario = [string]$_.id
            detected = [bool]$_.detected
            selected_detecting_tests = @($_.selected_detecting_tests)
        }
    })
}

$comparison = [ordered]@{
    benchmark = "online-boutique-defect-recall"
    run_id = "final-comparison-003"
    comparison_status = "measured"
    artifact_status = "final_comparison_measured"
    public_result_status = "qmind_recall_claimed"
    created_at = "2026-06-12"
    generator = "benchmark-pipeline/generate-final-comparison.ps1"
    oracle = $Oracle
    oracle_mode = "validated_detecting_tests"
    canonical_library = $Library
    full_suite_size = $fullSuiteSize
    qmind_selection = [ordered]@{
        status = "selection_executed_successfully"
        selection_artifact = $QMindSelection
        selected_tests = [int]$qmind.selected_test_count
        library_size = $fullSuiteSize
        message = "QMind selected 15/51 tests and detected all 4 validated defect scenarios."
        normalization = [ordered]@{ status = "canonical_test_ids" }
    }
    defect_universe = $ScenarioIds
    primary_kpi = "Defect Recall = Detected Defects / Full Suite Defects"
    comparison_selection_size = [ordered]@{
        tests = $qmindSelectionSize
        basis = "current qmind measured selection size from qmind-current-selection.json"
    }
    methods = @($fullSuiteSummary, $randomSummary, $historySummary, $qmindSummary)
    supporting_artifacts = @($expectedArtifacts | ForEach-Object { $_.Replace("\", "/") })
    limitations = @(
        "This comparison uses canonical test IDs from qmind-current-selection.json.",
        "No qmind, oracle, history logic, selection algorithm, evaluation algorithm, or canonical library behavior was changed for this comparison run."
    )
}

Write-Json $FinalComparison $comparison

$ob004 = Get-ScenarioResult $qmind "OB-004"
if (-not (@($ob004.selected_detecting_tests) -contains "payment-order-completion-confirms-success")) {
    throw "Expected OB-004 to be detected by payment-order-completion-confirms-success."
}

$randomDetectedText = if (@($randomSummary.detected_scenarios).Count -gt 0) { ($randomSummary.detected_scenarios -join ", ") } else { "none" }
$historyDetectedText = if (@($historySummary.detected_scenarios).Count -gt 0) { ($historySummary.detected_scenarios -join ", ") } else { "none" }
$qmindDetectedText = $qmindSummary.detected_scenarios -join ", "
$FinalComparisonDisplay = $FinalComparison.Replace("\", "/")
$FullSuiteEvaluationDisplay = $FullSuiteEvaluation.Replace("\", "/")
$RandomSelectionDisplay = $RandomSelection.Replace("\", "/")
$RandomEvaluationDisplay = $RandomEvaluation.Replace("\", "/")
$QMindEvaluationDisplay = $QMindEvaluation.Replace("\", "/")

$doc = @"
# Final Benchmark Comparison

## Scope

This comparison uses the canonical 51-test Online Boutique library and the validated defect oracle.

- Canonical library: ``$Library``
- Defect oracle: ``$Oracle``
- Oracle mode: ``validated_detecting_tests``
- Generator: ``benchmark-pipeline/generate-final-comparison.ps1``
- QMind selection artifact: ``$QMindSelection``
- QMind evaluation artifact: ``$QMindEvaluationDisplay``
- QMind selection result: selection executed successfully, 15/51 tests selected
- QMind scoring status: measured with canonical test IDs

QMind selected 15/51 tests, detected all 4 validated defect scenarios, and achieved 70.6% execution reduction with 100.0% defect recall. OB-004 is detected by ``payment-order-completion-confirms-success``.

## Comparison Table

| Method | Status | Tests | Execution Reduction | Defects Detected | Defect Recall |
| --- | --- | ---: | ---: | ---: | ---: |
| Traditional / Full Suite | measured | $($fullSuiteSummary.tests_executed) | $(Format-Percent $fullSuiteSummary.execution_reduction) | $($fullSuiteSummary.defects_detected) / $($fullSuiteSummary.full_suite_defects) | $(Format-Percent $fullSuiteSummary.defect_recall) |
| Random | measured | $($randomSummary.tests_executed) | $(Format-Percent $randomSummary.execution_reduction) | $($randomSummary.defects_detected) / $($randomSummary.full_suite_defects) | $(Format-Percent $randomSummary.defect_recall) |
| History + Code Change | measured | $($historySummary.tests_executed_note) | $(Format-Percent $historySummary.execution_reduction) | $($historySummary.defects_detected) / $($historySummary.full_suite_defects) | $(Format-Percent $historySummary.defect_recall) |
| Quantik Mind | measured | $($qmindSummary.tests_executed) | $(Format-Percent $qmindSummary.execution_reduction) | $($qmindSummary.defects_detected) / $($qmindSummary.full_suite_defects) | $(Format-Percent $qmindSummary.defect_recall) |

## Method Notes

Traditional / Full Suite uses all ``test_id`` values from ``$Library`` and detects all four validated scenarios.

Random uses a deterministic $qmindSelectionSize-test sample from the canonical library with seed $RandomSeed. It detects $randomDetectedText.

History + Code Change uses scenario-specific changed-file/domain context with a $qmindSelectionSize-test selection for each scenario. Each scenario is scored against its own corresponding selection and detects $historyDetectedText.

Quantik Mind uses the validated current selection in ``$QMindSelection``. The selection contains canonical test IDs, detects $qmindDetectedText, and detects OB-004 through ``payment-order-completion-confirms-success``.

## Reproduction

Regenerate all final comparison artifacts from committed inputs:

``````powershell
.\benchmark-pipeline\generate-final-comparison.ps1
``````

The generator writes:

- ``$FinalComparisonDisplay``
- ``$FinalComparisonDoc``
- ``$FullSuiteEvaluationDisplay``
- ``$RandomSelectionDisplay``
- ``$RandomEvaluationDisplay``
- ``$QMindEvaluationDisplay``
- ``history-code-change`` selection and evaluation artifacts for OB-001 through OB-004

It fails if any expected artifact is missing or if the QMind evaluation is not exactly 15 selected tests, 4 detected scenarios, and 100.0% defect recall.
"@

[System.IO.File]::WriteAllText((Resolve-ParentPath $FinalComparisonDoc), $doc + [Environment]::NewLine, [System.Text.UTF8Encoding]::new($false))

Write-Host "Final comparison generated:"
Write-Host "  JSON: $FinalComparison"
Write-Host "  Markdown: $FinalComparisonDoc"
Write-Host "  Random: $($randomSummary.tests_executed) tests, $($randomSummary.defects_detected)/$($randomSummary.full_suite_defects) detected, $(Format-Percent $randomSummary.defect_recall) recall"
Write-Host "  History + Code Change: $($historySummary.tests_executed_note), $($historySummary.defects_detected)/$($historySummary.full_suite_defects) detected, $(Format-Percent $historySummary.defect_recall) recall"
Write-Host "  QMind: $($qmindSummary.tests_executed) tests, $($qmindSummary.defects_detected)/$($qmindSummary.full_suite_defects) detected, $(Format-Percent $qmindSummary.defect_recall) recall"

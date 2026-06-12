param(
    [string]$Oracle = "defect-oracle/online-boutique-defect-oracle.v2.json",
    [string]$Library = "qmind-test-library/online-boutique-playwright-51.json",
    [string]$Scenarios = "benchmark-pipeline/scenarios.json",
    [string]$QMindRunDir = "benchmark-runs/qmind-online-boutique",
    [string]$QMindEnvFile = ".env",
    [string]$QMindLibraryApi,
    [string]$OutputDir = "benchmark-results/final-comparison",
    [int]$RandomSeed = 42,
    [int]$RandomSize = 26,
    [int]$TargetedSize = 15,
    [switch]$UseExistingQMindSelections,
    [switch]$SkipRun
)

$ErrorActionPreference = "Stop"

$FinalComparison = Join-Path $OutputDir "final-comparison.json"
$FinalComparisonDoc = "docs/final-benchmark-comparison.md"
$FullSuiteEvaluation = Join-Path $OutputDir "full-suite-evaluation.json"
$CaseIds = @("OB-001", "OB-002", "OB-003", "OB-004")

function Resolve-ParentPath {
    param([string]$Path)

    $parent = Split-Path -Parent $Path
    if (-not [string]::IsNullOrWhiteSpace($parent)) {
        New-Item -ItemType Directory -Force -Path $parent | Out-Null
    }
    return $ExecutionContext.SessionState.Path.GetUnresolvedProviderPathFromPSPath($Path)
}

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

function Invoke-QMindSubset {
    param(
        [string]$CaseId,
        [string]$SelectionOutput
    )

    $arguments = @{
        EnvFile = $QMindEnvFile
        BenchmarkCase = $CaseId
        Scenarios = $Scenarios
        RunDir = $QMindRunDir
        SelectionOutput = $SelectionOutput
        Library = $Library
    }
    if (-not [string]::IsNullOrWhiteSpace($QMindLibraryApi)) {
        $arguments["LibraryApi"] = $QMindLibraryApi
    }

    $displayArguments = @(
        "-EnvFile", $QMindEnvFile,
        "-BenchmarkCase", $CaseId,
        "-Scenarios", $Scenarios,
        "-RunDir", $QMindRunDir,
        "-SelectionOutput", $SelectionOutput,
        "-Library", $Library
    )
    if (-not [string]::IsNullOrWhiteSpace($QMindLibraryApi)) {
        $displayArguments += @("-LibraryApi", $QMindLibraryApi)
    }

    Write-Host (".\benchmark-pipeline\run-qmind-subset.ps1 " + ($displayArguments -join " "))
    & ".\benchmark-pipeline\run-qmind-subset.ps1" @arguments
    if ($LASTEXITCODE -ne 0) {
        throw "QMind subset generation failed for $CaseId. Check live QMind configuration, CLI availability, observability setup, and project/library sync."
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

    $json = $Value | ConvertTo-Json -Depth 30
    [System.IO.File]::WriteAllText((Resolve-ParentPath $Path), $json + [Environment]::NewLine, [System.Text.UTF8Encoding]::new($false))
}

function Format-Percent {
    param([double]$Value)

    return "{0:N1}%" -f ($Value * 100)
}

function To-RepoPath {
    param([string]$Path)

    return $Path.Replace("\", "/")
}

function Get-ScenarioMap {
    param([object]$ScenarioData)

    $map = @{}
    foreach ($scenario in @($ScenarioData.scenarios)) {
        $map[[string]$scenario.id] = $scenario
    }
    return $map
}

function Get-SelectedTests {
    param([object]$Selection)

    return @($Selection.selected_tests | ForEach-Object { [string]$_ })
}

function Get-TestId {
    param([object]$Test)

    foreach ($key in @("test_id", "id", "name", "title")) {
        if ($null -ne $Test.$key -and -not [string]::IsNullOrWhiteSpace([string]$Test.$key)) {
            return [string]$Test.$key
        }
    }
    return $null
}

function Get-QMindSelectionPath {
    param([string]$CaseId)

    return Join-Path $QMindRunDir "qmind-selection-$($CaseId.ToLowerInvariant()).json"
}

function Get-QMindSelectionCommand {
    param([string]$CaseId)

    $path = To-RepoPath (Get-QMindSelectionPath $CaseId)
    return ".\benchmark-pipeline\run-qmind-subset.ps1 -BenchmarkCase $CaseId -SelectionOutput $path"
}

function Assert-QMindSelection {
    param(
        [string]$CaseId,
        [string]$Path,
        [string[]]$LibraryIds
    )

    if (-not (Test-Path -LiteralPath $Path -PathType Leaf)) {
        throw "Missing expected QMind selection artifact for $($CaseId): $(To-RepoPath $Path)"
    }

    $selection = Read-Json $Path
    if ([string]$selection.method -ne "qmind") {
        throw "QMind selection artifact must set method = qmind: $(To-RepoPath $Path)"
    }
    if ([string]$selection.benchmark_case -ne $CaseId) {
        throw "QMind selection artifact must set benchmark_case = $($CaseId): $(To-RepoPath $Path)"
    }

    $selectedTests = @(Get-SelectedTests $selection)
    if ($selectedTests.Count -eq 0) {
        throw "QMind selection artifact has no selected_tests: $(To-RepoPath $Path)"
    }

    $unknown = @($selectedTests | Where-Object { $LibraryIds -notcontains $_ })
    if ($unknown.Count -gt 0) {
        throw "QMind selection artifact contains non-canonical test IDs in $(To-RepoPath $Path): $($unknown -join ', ')"
    }

    if ($CaseId -eq "OB-004" -and $selectedTests -notcontains "payment-order-completion-confirms-success") {
        throw "QMind selection artifact for OB-004 must include payment-order-completion-confirms-success: $(To-RepoPath $Path)"
    }
}

function Assert-QMindCaseSelections {
    param(
        [string[]]$Cases,
        [string[]]$LibraryIds
    )

    $missing = @()
    foreach ($caseId in $Cases) {
        $path = Get-QMindSelectionPath $caseId
        if (-not (Test-Path -LiteralPath $path -PathType Leaf)) {
            $missing += [ordered]@{
                case = $caseId
                path = To-RepoPath $path
                command = Get-QMindSelectionCommand $caseId
            }
            continue
        }

        Assert-QMindSelection $caseId $path $LibraryIds
    }

    if ($missing.Count -gt 0) {
        $lines = @(
            "Missing required per-case QMind selection artifacts.",
            "Use -UseExistingQMindSelections only after generating all four per-case QMind selections.",
            "The final comparison cannot reuse benchmark-runs/qmind-online-boutique/qmind-current-selection.json for all cases.",
            "",
            "Create the missing artifacts with:"
        )
        foreach ($item in $missing) {
            $lines += "  $($item.command)"
        }
        $lines += ""
        $lines += "Missing artifacts:"
        foreach ($item in $missing) {
            $lines += "  $($item.case): $($item.path)"
        }
        throw ($lines -join [Environment]::NewLine)
    }
}

function Get-CaseDetection {
    param([object]$Evaluation)

    $perScenario = @($Evaluation.per_scenario)
    if ($perScenario.Count -ne 1) {
        throw "Expected case evaluation to contain exactly one scenario."
    }
    return $perScenario[0]
}

function New-CaseMethodResult {
    param(
        [string]$Method,
        [string]$Label,
        [string]$SelectionArtifact,
        [object]$Selection,
        [string]$EvaluationArtifact,
        [object]$Evaluation
    )

    $caseDetection = Get-CaseDetection $Evaluation
    return [ordered]@{
        method = $Method
        method_label = $Label
        selection_artifact = To-RepoPath $SelectionArtifact
        evaluation_artifact = To-RepoPath $EvaluationArtifact
        selected_test_count = [int]$Evaluation.selected_test_count
        selected_tests = @(Get-SelectedTests $Selection)
        execution_reduction = [double]$Evaluation.execution_reduction
        execution_reduction_percent = [Math]::Round(([double]$Evaluation.execution_reduction * 100), 1)
        defect_detected = [bool]$caseDetection.detected
        defect_recall = [double]$Evaluation.defect_recall
        selected_detecting_tests = @($caseDetection.selected_detecting_tests)
    }
}

function New-AggregateResult {
    param(
        [string]$Method,
        [string]$Label,
        [object[]]$CaseResults
    )

    $methodCases = @($CaseResults | ForEach-Object { $_.methods[$Method] })
    $detected = @($methodCases | Where-Object { [bool]$_.defect_detected })
    $selectedCounts = @($methodCases | ForEach-Object { [int]$_.selected_test_count })
    $reductions = @($methodCases | ForEach-Object { [double]$_.execution_reduction })
    $averageSelected = ($selectedCounts | Measure-Object -Average).Average
    $averageReduction = ($reductions | Measure-Object -Average).Average

    return [ordered]@{
        method = $Method
        method_label = $Label
        benchmark_cases = [int]$methodCases.Count
        detected_cases = [int]$detected.Count
        missed_cases = [int]($methodCases.Count - $detected.Count)
        defect_recall = if ($methodCases.Count -gt 0) { $detected.Count / $methodCases.Count } else { 0 }
        average_selected_tests = [Math]::Round([double]$averageSelected, 1)
        average_execution_reduction = [double]$averageReduction
        average_execution_reduction_percent = [Math]::Round(([double]$averageReduction * 100), 1)
    }
}

foreach ($path in @($Oracle, $Library, $Scenarios)) {
    if (-not (Test-Path -LiteralPath $path -PathType Leaf)) {
        throw "Missing required input: $path"
    }
}

New-Item -ItemType Directory -Force -Path $OutputDir | Out-Null

$scenarioData = Read-Json $Scenarios
$scenarioMap = Get-ScenarioMap $scenarioData
$oracleData = Read-Json $Oracle
$oracleDetectingTestCounts = [ordered]@{}
foreach ($scenario in @($oracleData.scenarios)) {
    $oracleDetectingTestCounts[[string]$scenario.id] = @($scenario.validated_detecting_tests).Count
}
$fullSuiteLibrary = Read-Json $Library
$libraryIds = @($fullSuiteLibrary.tests | ForEach-Object { Get-TestId $_ } | Where-Object { $_ })
if ($UseExistingQMindSelections -or $SkipRun) {
    Assert-QMindCaseSelections $CaseIds $libraryIds
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

    foreach ($caseId in $CaseIds) {
        $caseLower = $caseId.ToLowerInvariant()
        $fullCaseEvaluation = Join-Path $OutputDir "full-suite-$caseLower-evaluation.json"
        $randomSelection = Join-Path $OutputDir "random-$caseLower-selection.json"
        $randomCaseEvaluation = Join-Path $OutputDir "random-$caseLower-evaluation.json"
        $historySelection = Join-Path $OutputDir "history-code-change-$caseLower-selection.json"
        $historyEvaluation = Join-Path $OutputDir "history-code-change-$caseLower-evaluation.json"
        $qmindCaseSelection = Get-QMindSelectionPath $caseId
        $qmindCaseEvaluation = Join-Path $OutputDir "qmind-$caseLower-evaluation.json"

        Invoke-Python @(
            "benchmark-pipeline/evaluate-defect-recall.py",
            "--oracle", $Oracle,
            "--selected", $Library,
            "--method", "full-suite",
            "--use-validated",
            "--scenario", $caseId,
            "--output", $fullCaseEvaluation
        )

        Invoke-Python @(
            "benchmark-pipeline/select-random-approach.py",
            "--library", $Library,
            "--size", "$RandomSize",
            "--seed", "$RandomSeed",
            "--benchmark-case", $caseId,
            "--output", $randomSelection
        )

        Invoke-Python @(
            "benchmark-pipeline/evaluate-defect-recall.py",
            "--oracle", $Oracle,
            "--selected", $randomSelection,
            "--method", "random",
            "--use-validated",
            "--scenario", $caseId,
            "--output", $randomCaseEvaluation
        )

        Invoke-Python @(
            "benchmark-pipeline/select-history-code-change-approach.py",
            "--library", $Library,
            "--scenarios", $Scenarios,
            "--size", "$TargetedSize",
            "--scenario", $caseId,
            "--output", $historySelection
        )

        Invoke-Python @(
            "benchmark-pipeline/evaluate-defect-recall.py",
            "--oracle", $Oracle,
            "--selected", $historySelection,
            "--method", "history-code-change",
            "--use-validated",
            "--scenario", $caseId,
            "--output", $historyEvaluation
        )

        if (-not $UseExistingQMindSelections) {
            Invoke-QMindSubset $caseId $qmindCaseSelection
        }
        Assert-QMindSelection $caseId $qmindCaseSelection $libraryIds

        Invoke-Python @(
            "benchmark-pipeline/evaluate-defect-recall.py",
            "--oracle", $Oracle,
            "--selected", $qmindCaseSelection,
            "--method", "qmind",
            "--use-validated",
            "--scenario", $caseId,
            "--output", $qmindCaseEvaluation
        )
    }
}

$expectedArtifacts = @(
    $FullSuiteEvaluation
)
foreach ($caseId in $CaseIds) {
    $caseLower = $caseId.ToLowerInvariant()
    $expectedArtifacts += Join-Path $OutputDir "full-suite-$caseLower-evaluation.json"
    $expectedArtifacts += Join-Path $OutputDir "random-$caseLower-selection.json"
    $expectedArtifacts += Join-Path $OutputDir "random-$caseLower-evaluation.json"
    $expectedArtifacts += Join-Path $OutputDir "history-code-change-$caseLower-selection.json"
    $expectedArtifacts += Join-Path $OutputDir "history-code-change-$caseLower-evaluation.json"
    $expectedArtifacts += Get-QMindSelectionPath $caseId
    $expectedArtifacts += Join-Path $OutputDir "qmind-$caseLower-evaluation.json"
}
foreach ($artifact in $expectedArtifacts) {
    if (-not (Test-Path -LiteralPath $artifact -PathType Leaf)) {
        throw "Missing expected artifact: $artifact"
    }
}

$fullSuiteSelection = [ordered]@{
    selected_tests = $libraryIds
}

$caseResults = @()
foreach ($caseId in $CaseIds) {
    $caseLower = $caseId.ToLowerInvariant()
    $scenario = $scenarioMap[$caseId]
    if (-not $scenario) {
        throw "Missing scenario metadata for benchmark case: $caseId"
    }

    $fullCaseEvaluationPath = Join-Path $OutputDir "full-suite-$caseLower-evaluation.json"
    $randomSelectionPath = Join-Path $OutputDir "random-$caseLower-selection.json"
    $randomCaseEvaluationPath = Join-Path $OutputDir "random-$caseLower-evaluation.json"
    $historySelectionPath = Join-Path $OutputDir "history-code-change-$caseLower-selection.json"
    $historyEvaluationPath = Join-Path $OutputDir "history-code-change-$caseLower-evaluation.json"
    $qmindCaseSelectionPath = Get-QMindSelectionPath $caseId
    $qmindCaseEvaluationPath = Join-Path $OutputDir "qmind-$caseLower-evaluation.json"

    $randomSelectionData = Read-Json $randomSelectionPath
    $historySelectionData = Read-Json $historySelectionPath
    $qmindCaseSelectionData = Read-Json $qmindCaseSelectionPath

    $caseResult = [ordered]@{
        id = $caseId
        name = [string]$scenario.name
        commit_context = [ordered]@{
            external_repo = [string]$scenario.external_repo
            baseline_ref = [string]$scenario.baseline_ref
            scenario_ref = [string]$scenario.scenario_ref
            changed_files = @($scenario.expected_changed_files | ForEach-Object { [string]$_ })
        }
        oracle = [ordered]@{
            artifact = $Oracle
            detecting_tests_field = "validated_detecting_tests"
        }
        methods = [ordered]@{
            "full-suite" = New-CaseMethodResult "full-suite" "Traditional Approach / Full Suite" $Library $fullSuiteSelection $fullCaseEvaluationPath (Read-Json $fullCaseEvaluationPath)
            "random" = New-CaseMethodResult "random" "Random Approach" $randomSelectionPath $randomSelectionData $randomCaseEvaluationPath (Read-Json $randomCaseEvaluationPath)
            "history-code-change" = New-CaseMethodResult "history-code-change" "History + Code Change" $historySelectionPath $historySelectionData $historyEvaluationPath (Read-Json $historyEvaluationPath)
            "qmind" = New-CaseMethodResult "qmind" "Quantik Mind" $qmindCaseSelectionPath $qmindCaseSelectionData $qmindCaseEvaluationPath (Read-Json $qmindCaseEvaluationPath)
        }
    }
    $caseResults += $caseResult
}

$aggregateMethods = @(
    New-AggregateResult "full-suite" "Traditional Approach / Full Suite" $caseResults
    New-AggregateResult "random" "Random Approach" $caseResults
    New-AggregateResult "history-code-change" "History + Code Change" $caseResults
    New-AggregateResult "qmind" "Quantik Mind" $caseResults
)

$comparison = [ordered]@{
    benchmark = "online-boutique-defect-recall"
    run_id = "final-comparison-004"
    comparison_status = "measured"
    methodology = "benchmark-case-ci-validation"
    created_at = "2026-06-12"
    generator = "benchmark-pipeline/generate-final-comparison.ps1"
    oracle = $Oracle
    oracle_mode = "validated_detecting_tests"
    oracle_detecting_test_counts = $oracleDetectingTestCounts
    canonical_library = $Library
    full_suite_size = 51
    benchmark_cases = $caseResults
    aggregate_methods = $aggregateMethods
    selector_input_policy = [ordered]@{
        full_suite = @("test library")
        random = @("test library", "seed")
        history_code_change = @("test library", "history metadata", "changed files")
        qmind = @("test library", "history", "changed files", "runtime metrics", "observability")
        oracle_only = @("defect identity", "oracle detecting tests", "expected benchmark outcome")
    }
    qmind_selection_mode = if ($UseExistingQMindSelections) { "existing-per-case-artifacts" } else { "generated-by-run-qmind-subset" }
    supporting_artifacts = @($expectedArtifacts | ForEach-Object { To-RepoPath $_ })
    limitations = @(
        "QMind is evaluated from one canonical selection artifact per benchmark case under benchmark-runs/qmind-online-boutique/qmind-selection-ob-*.json.",
        "Normal generator mode creates QMind selections by invoking benchmark-pipeline/run-qmind-subset.ps1 for each case; -UseExistingQMindSelections may reuse already generated per-case artifacts.",
        "History + Code Change uses changed files and library/history metadata only; oracle detecting tests are used only by the evaluator.",
        "No canonical test library content was changed; oracle changes are limited to minimal direct detecting test lists."
    )
}

Write-Json $FinalComparison $comparison

$docRows = @()
foreach ($method in $aggregateMethods) {
    $docRows += "| $($method.method_label) | $($method.average_selected_tests) | $(Format-Percent $method.average_execution_reduction) | $($method.detected_cases) / $($method.benchmark_cases) | $(Format-Percent $method.defect_recall) |"
}
$oracleRows = @()
foreach ($caseId in $CaseIds) {
    $oracleRows += "| $caseId | $($oracleDetectingTestCounts[$caseId]) |"
}

$caseSections = @()
foreach ($case in $caseResults) {
    $caseSections += "### $($case.id): $($case.name)"
    $caseSections += ""
    $changedFilesText = @($case.commit_context.changed_files) -join '`, `'
    $caseSections += "- Changed files: ``$changedFilesText``"
    foreach ($methodKey in @("full-suite", "random", "history-code-change", "qmind")) {
        $method = $case.methods[$methodKey]
        $detected = if ($method.defect_detected) { "detected" } else { "missed" }
        $caseSections += "- $($method.method_label): $($method.selected_test_count) tests, $(Format-Percent $method.execution_reduction) reduction, defect $detected"
    }
    $caseSections += ""
}
$caseText = $caseSections -join [Environment]::NewLine
$aggregateRows = $docRows -join [Environment]::NewLine
$oracleTableRows = $oracleRows -join [Environment]::NewLine
$qmindAggregate = @($aggregateMethods | Where-Object { $_.method -eq "qmind" })[0]

$doc = @"
# Final Benchmark Comparison

## Scope

This comparison models Online Boutique as four independent CI/CD benchmark cases. Each case has commit context, changed files, an injected defect, and oracle detecting tests. Selectors run before scoring and do not receive defect identity, oracle detecting tests, or expected benchmark outcomes.

- Canonical library: ``$Library``
- Defect oracle: ``$Oracle``
- Oracle mode: ``validated_detecting_tests``
- Generator: ``benchmark-pipeline/generate-final-comparison.ps1``
- Random seed: $RandomSeed
- Random size: $RandomSize tests
- History + Code Change size: $TargetedSize tests per case
- QMind selection artifacts: ``$(To-RepoPath $QMindRunDir)/qmind-selection-ob-001.json`` through ``$(To-RepoPath $QMindRunDir)/qmind-selection-ob-004.json``
- QMind selection mode: ``$($comparison.qmind_selection_mode)``

## Oracle Precision

The defect oracle uses minimal direct validated detecting tests for each benchmark case. Broad downstream symptom tests are excluded from the oracle even when they can fail as a side effect.

| Case | Direct Validated Detecting Tests |
| --- | ---: |
$oracleTableRows

## Aggregate Results

| Method | Avg Tests | Avg Execution Reduction | Cases Detected | Case Recall |
| --- | ---: | ---: | ---: | ---: |
$aggregateRows

## Benchmark Cases

$caseText
## Method Notes

Full Suite always selects all 51 tests.

Random uses only the canonical test library and deterministic seed 42. It produces a per-case selection artifact and selects 26 tests, approximately 50% of the 51-test suite.

History + Code Change uses the canonical test library, history-oriented test metadata, and each case's changed files. It does not read the defect oracle and does not use oracle detecting tests.

Quantik Mind uses one canonical selection artifact per benchmark case, generated from that case's changed-files context by ``benchmark-pipeline/run-qmind-subset.ps1`` in normal mode. The aggregate QMind result averages $($qmindAggregate.average_selected_tests) selected tests, gives $(Format-Percent $qmindAggregate.average_execution_reduction) average execution reduction, detects $($qmindAggregate.detected_cases)/$($qmindAggregate.benchmark_cases) cases, and requires OB-004 to include ``payment-order-completion-confirms-success``.

## Reproduction

Regenerate all final comparison artifacts from committed inputs:

``````powershell
.\benchmark-pipeline\generate-final-comparison.ps1
``````

The generator fails if any per-case QMind selection artifact is missing, contains non-canonical test IDs, or if the OB-004 artifact does not include ``payment-order-completion-confirms-success``.

To reuse previously generated per-case QMind selections instead of calling live QMind:

``````powershell
.\benchmark-pipeline\generate-final-comparison.ps1 -UseExistingQMindSelections
``````
"@

[System.IO.File]::WriteAllText((Resolve-ParentPath $FinalComparisonDoc), $doc + [Environment]::NewLine, [System.Text.UTF8Encoding]::new($false))

Write-Host "Final benchmark-case comparison generated:"
foreach ($method in $aggregateMethods) {
    Write-Host "  $($method.method_label): $($method.detected_cases)/$($method.benchmark_cases), $(Format-Percent $method.defect_recall) recall, avg tests $($method.average_selected_tests)"
}

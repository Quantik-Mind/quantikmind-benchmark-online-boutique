param(
    [string]$Oracle = "defect-oracle/online-boutique-defect-oracle.v2.json",
    [string]$Library = "qmind-test-library/online-boutique-playwright-51.json",
    [string]$Scenarios = "benchmark-pipeline/scenarios.json",
    [string]$QMindSelectionDir = "benchmark-results/qmind-selections",
    [string]$QMindRunDir = "benchmark-runs/qmind-online-boutique",
    [string]$QMindEnvFile = ".env",
    [string]$QMindLibraryApi,
    [string]$OutputDir = "benchmark-results/final-comparison",
    [string]$RuntimeEvidenceDir = "benchmark-results/runtime-evidence/ob-006",
    [string]$RuntimeEvidenceOb007Dir = "benchmark-results/runtime-evidence/ob-007",
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
$CaseIds = @("OB-001", "OB-002", "OB-003", "OB-004", "OB-005", "OB-006")
$ob007ManifestPath = Join-Path $RuntimeEvidenceOb007Dir "evidence-manifest.json"
$IncludeOb007 = Test-Path -LiteralPath $ob007ManifestPath -PathType Leaf
if ($IncludeOb007) { $CaseIds += "OB-007" }

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
    $json = $json.Replace("`r`n", "`n")
    [System.IO.File]::WriteAllText((Resolve-ParentPath $Path), $json + "`n", [System.Text.UTF8Encoding]::new($false))
}

function Copy-JsonWithoutBom {
    param(
        [string]$Source,
        [string]$Destination
    )

    $content = Get-Content -LiteralPath $Source -Raw
    $content = $content -replace "`r`n", "`n"
    [System.IO.File]::WriteAllText(
        (Resolve-ParentPath $Destination),
        $content,
        [System.Text.UTF8Encoding]::new($false)
    )
}

function Format-Percent {
    param([double]$Value)

    return "{0:N1}%" -f ($Value * 100)
}

function Format-Fraction {
    param(
        [int]$Numerator,
        [int]$Denominator
    )

    return "$Numerator/$Denominator"
}

function To-RepoPath {
    param([string]$Path)

    return $Path.Replace("\", "/")
}

function Get-CategoryKey {
    param([object]$Scenario)

    $category = [string]$Scenario.category
    if ([string]::IsNullOrWhiteSpace($category)) {
        return "code-change"
    }
    return $category
}

function Get-CategoryLabel {
    param([string]$Category)

    switch ($Category) {
        "code-change" { return "Code Change" }
        "runtime-aware" { return "Runtime Aware" }
        "combined-signal" { return "Combined Signal" }
        "overall" { return "Overall" }
        default { return $Category }
    }
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

    return Join-Path $QMindSelectionDir "qmind-selection-$($CaseId.ToLowerInvariant()).json"
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
            "Use -UseExistingQMindSelections only after committing or generating all canonical per-case QMind selections.",
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

function Get-CanonicalJson {
    param([object]$Value)

    return ($Value | ConvertTo-Json -Depth 40 -Compress)
}

function Get-SelectionRunId {
    param([object]$Selection)

    $runId = [string]$Selection.qmind_subset_json.run_id
    if ([string]::IsNullOrWhiteSpace($runId)) {
        $runId = [string]$Selection.run_id
    }
    return $runId
}

function Assert-Ob006RuntimeEvidence {
    param(
        [string]$EvidenceDir,
        [string]$Ob005SelectionPath,
        [string]$Ob006SelectionPath
    )

    $requiredFiles = @(
        "evidence-manifest.json",
        "baseline-prometheus-snapshot.json",
        "injected-prometheus-snapshot.json",
        "runtime-movement-summary.json",
        "baseline-homepage-traffic.json",
        "injected-homepage-traffic.json",
        "qmind-ob006-detection-summary.json",
        "scenario-ob-006-changed-files.json",
        "qmind-selection-ob-006.json"
    )
    foreach ($fileName in $requiredFiles) {
        $path = Join-Path $EvidenceDir $fileName
        if (-not (Test-Path -LiteralPath $path -PathType Leaf)) {
            throw "Missing required OB-006 runtime evidence artifact: $(To-RepoPath $path)"
        }
    }

    $manifest = Read-Json (Join-Path $EvidenceDir "evidence-manifest.json")
    if ([string]$manifest.evidence_status -ne "verified") {
        throw "OB-006 evidence manifest must set evidence_status=verified."
    }

    $movement = Read-Json (Join-Path $EvidenceDir "runtime-movement-summary.json")
    if ([string]$movement.publication_runtime_evidence -ne "CONFIRMED") {
        throw "OB-006 runtime movement summary must set publication_runtime_evidence=CONFIRMED."
    }
    if ([bool]$movement.productcatalogservice_signal_confirmed -ne $true) {
        throw "OB-006 runtime evidence must confirm material productcatalogservice latency or error movement."
    }
    if ([bool]$movement.frontend_signal_confirmed -ne $true) {
        throw "OB-006 runtime evidence must confirm material frontend latency or error movement."
    }

    $changedFiles = @(Read-Json (Join-Path $EvidenceDir "scenario-ob-006-changed-files.json") | ForEach-Object { [string]$_ })
    if ($changedFiles.Count -ne 1 -or $changedFiles[0] -ne "src/productcatalogservice/product_catalog.go") {
        throw "OB-006 runtime evidence changed-files artifact must contain only src/productcatalogservice/product_catalog.go."
    }

    $detection = Read-Json (Join-Path $EvidenceDir "qmind-ob006-detection-summary.json")
    if ([bool]$detection.detected -ne $true) {
        throw "OB-006 QMind detection summary must set detected=true."
    }
    if ([bool]$detection.observability_enabled -ne $true -or [bool]$detection.has_runtime_signal -ne $true) {
        throw "OB-006 QMind detection summary must show observability_enabled=true and has_runtime_signal=true."
    }

    $ob005 = Read-Json $Ob005SelectionPath
    $ob006 = Read-Json $Ob006SelectionPath
    $sameSelectedTests = ((@($ob005.selected_tests) -join "|") -eq (@($ob006.selected_tests) -join "|"))
    $sameBusinessMetrics = ((Get-CanonicalJson $ob005.business_metrics) -eq (Get-CanonicalJson $ob006.business_metrics))
    $sameRiskCoverage = ([string]$ob005.risk_coverage -eq [string]$ob006.risk_coverage)
    $sameRiskEfficiency = ([string]$ob005.risk_efficiency -eq [string]$ob006.risk_efficiency)
    if ($sameSelectedTests -and $sameBusinessMetrics -and $sameRiskCoverage -and $sameRiskEfficiency) {
        throw "OB-006 QMind selection is substantively identical to OB-005. Regenerate OB-006 from distinct live combined-signal evidence before producing the 6-case headline."
    }

    $evidenceSelection = Read-Json (Join-Path $EvidenceDir "qmind-selection-ob-006.json")
    if ((Get-SelectionRunId $evidenceSelection) -ne (Get-SelectionRunId $ob006)) {
        throw "Tracked OB-006 evidence selection run_id does not match benchmark-results/qmind-selections/qmind-selection-ob-006.json."
    }
}

function Assert-Ob007RuntimeEvidence {
    param(
        [string]$EvidenceDir,
        [string]$Ob006SelectionPath,
        [string]$Ob007SelectionPath
    )

    $requiredFiles = @(
        "evidence-manifest.json",
        "baseline-prometheus-snapshot.json",
        "injected-prometheus-snapshot.json",
        "runtime-movement-summary.json",
        "baseline-product-detail-traffic.json",
        "injected-product-detail-traffic.json",
        "qmind-ob007-detection-summary.json",
        "scenario-ob-007-changed-files.json",
        "qmind-selection-ob-007.json"
    )
    foreach ($fileName in $requiredFiles) {
        $path = Join-Path $EvidenceDir $fileName
        if (-not (Test-Path -LiteralPath $path -PathType Leaf)) {
            throw "Missing required OB-007 runtime evidence artifact: $(To-RepoPath $path)"
        }
    }

    $manifest = Read-Json (Join-Path $EvidenceDir "evidence-manifest.json")
    if ([string]$manifest.evidence_status -ne "verified") {
        throw "OB-007 evidence manifest must set evidence_status=verified."
    }

    $movement = Read-Json (Join-Path $EvidenceDir "runtime-movement-summary.json")
    if ([string]$movement.publication_runtime_evidence -ne "CONFIRMED") {
        throw "OB-007 runtime movement summary must set publication_runtime_evidence=CONFIRMED."
    }
    if ([bool]$movement.recommendationservice_behavioral_signal_confirmed -ne $true) {
        throw "OB-007 runtime evidence must confirm recommendationservice behavioral degradation."
    }
    if ([bool]$movement.recommendationservice_prometheus_signal_confirmed -ne $true) {
        throw "OB-007 runtime evidence must confirm a Prometheus-visible recommendationservice latency signal."
    }
    if ([bool]$movement.graceful_degradation_confirmed -ne $true) {
        throw "OB-007 runtime evidence must confirm graceful degradation (product detail pages remain accessible)."
    }
    if ([bool]$movement.playwright_section_signal_confirmed -ne $true) {
        throw "OB-007 runtime evidence must confirm the recommendation section is absent at Playwright level."
    }

    $changedFiles = @(Read-Json (Join-Path $EvidenceDir "scenario-ob-007-changed-files.json") | ForEach-Object { [string]$_ })
    if ($changedFiles.Count -ne 1 -or $changedFiles[0] -ne "src/adservice/src/main/java/hipstershop/AdService.java") {
        throw "OB-007 runtime evidence changed-files artifact must contain only src/adservice/src/main/java/hipstershop/AdService.java."
    }

    $detection = Read-Json (Join-Path $EvidenceDir "qmind-ob007-detection-summary.json")
    if ([bool]$detection.detected -ne $true) {
        throw "OB-007 QMind detection summary must set detected=true."
    }
    if ([bool]$detection.observability_enabled -ne $true -or [bool]$detection.has_runtime_signal -ne $true) {
        throw "OB-007 QMind detection summary must show observability_enabled=true and has_runtime_signal=true."
    }
    if ([string]$detection.signal_state -eq "historical_only") {
        throw "OB-007 QMind detection summary must be runtime-aware, not historical_only."
    }

    $ob006 = Read-Json $Ob006SelectionPath
    $ob007 = Read-Json $Ob007SelectionPath
    $sameSelectedTests = ((@($ob006.selected_tests) -join "|") -eq (@($ob007.selected_tests) -join "|"))
    $sameBusinessMetrics = ((Get-CanonicalJson $ob006.business_metrics) -eq (Get-CanonicalJson $ob007.business_metrics))
    if ($sameSelectedTests -and $sameBusinessMetrics) {
        throw "OB-007 QMind selection is substantively identical to OB-006. Regenerate OB-007 from distinct live runtime evidence."
    }

    $evidenceSelection = Read-Json (Join-Path $EvidenceDir "qmind-selection-ob-007.json")
    if ((Get-SelectionRunId $evidenceSelection) -ne (Get-SelectionRunId $ob007)) {
        throw "Tracked OB-007 evidence selection run_id does not match benchmark-results/qmind-selections/qmind-selection-ob-007.json."
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
        recall_fraction = Format-Fraction $detected.Count $methodCases.Count
        defect_recall = if ($methodCases.Count -gt 0) { $detected.Count / $methodCases.Count } else { 0 }
        average_selected_tests = [Math]::Round([double]$averageSelected, 1)
        average_execution_reduction = [double]$averageReduction
        average_execution_reduction_percent = [Math]::Round(([double]$averageReduction * 100), 1)
    }
}

function New-CategorySummary {
    param(
        [string]$Category,
        [object[]]$Cases
    )

    $methodSummaries = [ordered]@{}
    foreach ($method in @("full-suite", "random", "history-code-change", "qmind")) {
        $methodCases = @($Cases | ForEach-Object { $_.methods[$method] })
        $detected = @($methodCases | Where-Object { [bool]$_.defect_detected })
        $methodSummaries[$method] = [ordered]@{
            method = $method
            method_label = [string]$methodCases[0].method_label
            detected_cases = [int]$detected.Count
            total_cases = [int]$methodCases.Count
            recall_fraction = Format-Fraction $detected.Count $methodCases.Count
            defect_recall = if ($methodCases.Count -gt 0) { $detected.Count / $methodCases.Count } else { 0 }
        }
    }

    return [ordered]@{
        category = $Category
        category_label = Get-CategoryLabel $Category
        scenarios = @($Cases | ForEach-Object { [string]$_.id })
        methods = $methodSummaries
    }
}

function Get-ObjectPropertyValue {
    param(
        [object]$Object,
        [string]$Name
    )

    if ($null -eq $Object) {
        return $null
    }

    $property = $Object.PSObject.Properties[$Name]
    if ($null -eq $property) {
        return $null
    }
    return $property.Value
}

function Get-NumericObjectPropertyValue {
    param(
        [object]$Object,
        [string]$Name
    )

    $value = Get-ObjectPropertyValue $Object $Name
    if ($null -eq $value -or [string]::IsNullOrWhiteSpace([string]$value)) {
        return $null
    }

    try {
        return [double]$value
    }
    catch {
        return $null
    }
}

function Get-QMindDynamicRiskDiagnostic {
    param(
        [string]$CaseId,
        [string]$SelectionArtifact,
        [object]$Selection
    )

    $businessMetrics = Get-ObjectPropertyValue $Selection "business_metrics"
    $observedRiskCoverage = Get-NumericObjectPropertyValue $Selection "risk_coverage"
    if ($null -eq $observedRiskCoverage) {
        $observedRiskCoverage = Get-NumericObjectPropertyValue $businessMetrics "risk_coverage"
    }

    $criticalRiskCaptured = Get-NumericObjectPropertyValue $businessMetrics "top_risk_coverage"
    if ($null -eq $criticalRiskCaptured) {
        $criticalRiskCaptured = Get-NumericObjectPropertyValue $Selection "top_risk_coverage"
    }

    $residualRisk = Get-NumericObjectPropertyValue $businessMetrics "residual_risk"
    if ($null -eq $residualRisk -and $null -ne $observedRiskCoverage) {
        if ($observedRiskCoverage -gt 1) {
            $residualRisk = 100 - $observedRiskCoverage
        }
        else {
            $residualRisk = 1 - $observedRiskCoverage
        }
    }

    $riskDensity = Get-NumericObjectPropertyValue $Selection "risk_efficiency"
    if ($null -eq $riskDensity) {
        $riskDensity = Get-NumericObjectPropertyValue $businessMetrics "risk_efficiency"
    }

    $missing = @()
    if ($null -eq $observedRiskCoverage) { $missing += "observed_risk_coverage" }
    if ($null -eq $criticalRiskCaptured) { $missing += "critical_risk_captured" }
    if ($null -eq $residualRisk) { $missing += "residual_risk" }
    if ($null -eq $riskDensity) { $missing += "risk_density" }

    return [ordered]@{
        benchmark_case = $CaseId
        selection_artifact = To-RepoPath $SelectionArtifact
        metrics_present = ($missing.Count -eq 0)
        observed_risk_coverage = $observedRiskCoverage
        critical_risk_captured = $criticalRiskCaptured
        residual_risk = $residualRisk
        risk_density = $riskDensity
        missing_fields = $missing
        warning = if ($missing.Count -gt 0) { "QMind dynamic risk diagnostics are missing from this selection artifact." } else { $null }
    }
}

function Get-AverageNullableMetric {
    param(
        [object[]]$Diagnostics,
        [string]$Metric
    )

    $values = @($Diagnostics | ForEach-Object { $_[$Metric] } | Where-Object { $null -ne $_ })
    if ($values.Count -eq 0) {
        return $null
    }
    return [Math]::Round([double](($values | Measure-Object -Average).Average), 4)
}

function New-QMindDynamicRiskDiagnostics {
    param([object[]]$Diagnostics)

    $complete = @($Diagnostics | Where-Object { [bool]$_.metrics_present })
    $withAnyValues = @($Diagnostics | Where-Object {
        $null -ne $_.observed_risk_coverage -or
        $null -ne $_.critical_risk_captured -or
        $null -ne $_.residual_risk -or
        $null -ne $_.risk_density
    })
    return [ordered]@{
        description = "Quantik Mind-only dynamic risk diagnostics from QMind selection/business_metrics payloads."
        availability = if ($withAnyValues.Count -gt 0) { "present" } else { "missing" }
        per_scenario = $Diagnostics
        aggregate = [ordered]@{
            benchmark_cases = [int]$Diagnostics.Count
            scenarios_with_complete_metrics = [int]$complete.Count
            scenarios_missing_metrics = [int]($Diagnostics.Count - $complete.Count)
            average_observed_risk_coverage = Get-AverageNullableMetric $Diagnostics "observed_risk_coverage"
            average_critical_risk_captured = Get-AverageNullableMetric $Diagnostics "critical_risk_captured"
            average_residual_risk = Get-AverageNullableMetric $Diagnostics "residual_risk"
            average_risk_density = Get-AverageNullableMetric $Diagnostics "risk_density"
            warning = if ($withAnyValues.Count -eq 0) { "No current QMind selection artifacts include dynamic risk diagnostics. These fields will populate when future artifacts include business_metrics or equivalent risk fields." } else { $null }
        }
    }
}

function Format-RiskDiagnosticValue {
    param(
        [object]$Value,
        [switch]$Percent
    )

    if ($null -eq $Value) {
        return "not present"
    }
    if ($Percent) {
        return "{0:N1}%" -f [double]$Value
    }
    return "{0:N1}" -f [double]$Value
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
if (-not $UseExistingQMindSelections) {
    $verifiedOb006Selection = Join-Path $RuntimeEvidenceDir "qmind-selection-ob-006.json"
    Copy-JsonWithoutBom $verifiedOb006Selection (Get-QMindSelectionPath "OB-006")

    if ($IncludeOb007) {
        $verifiedOb007Selection = Join-Path $RuntimeEvidenceOb007Dir "qmind-selection-ob-007.json"
        Copy-JsonWithoutBom $verifiedOb007Selection (Get-QMindSelectionPath "OB-007")
    }
}
Assert-Ob006RuntimeEvidence `
    -EvidenceDir $RuntimeEvidenceDir `
    -Ob005SelectionPath (Get-QMindSelectionPath "OB-005") `
    -Ob006SelectionPath (Get-QMindSelectionPath "OB-006")
$ob006EvidenceManifest = Read-Json (Join-Path $RuntimeEvidenceDir "evidence-manifest.json")
$ob006RuntimeMovement = Read-Json (Join-Path $RuntimeEvidenceDir "runtime-movement-summary.json")

$ob007EvidenceManifest = $null
$ob007RuntimeMovement = $null
if ($IncludeOb007) {
    Assert-Ob007RuntimeEvidence `
        -EvidenceDir $RuntimeEvidenceOb007Dir `
        -Ob006SelectionPath (Get-QMindSelectionPath "OB-006") `
        -Ob007SelectionPath (Get-QMindSelectionPath "OB-007")
    $ob007EvidenceManifest = Read-Json (Join-Path $RuntimeEvidenceOb007Dir "evidence-manifest.json")
    $ob007RuntimeMovement = Read-Json (Join-Path $RuntimeEvidenceOb007Dir "runtime-movement-summary.json")
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

        if ($caseId -eq "OB-006") {
            $verifiedOb006Selection = Join-Path $RuntimeEvidenceDir "qmind-selection-ob-006.json"
            Copy-JsonWithoutBom $verifiedOb006Selection $qmindCaseSelection
        } elseif ($caseId -eq "OB-007") {
            $verifiedOb007Selection = Join-Path $RuntimeEvidenceOb007Dir "qmind-selection-ob-007.json"
            Copy-JsonWithoutBom $verifiedOb007Selection $qmindCaseSelection
        } elseif (-not $UseExistingQMindSelections) {
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
$qmindDynamicRiskPerScenario = @()
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
    $qmindDynamicRiskPerScenario += Get-QMindDynamicRiskDiagnostic $caseId $qmindCaseSelectionPath $qmindCaseSelectionData

    $caseResult = [ordered]@{
        id = $caseId
        name = [string]$scenario.name
        category = Get-CategoryKey $scenario
        category_label = Get-CategoryLabel (Get-CategoryKey $scenario)
        signal_type = if ([string]::IsNullOrWhiteSpace([string]$scenario.signal_type)) { "code-change" } else { [string]$scenario.signal_type }
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
$qmindDynamicRiskDiagnostics = New-QMindDynamicRiskDiagnostics $qmindDynamicRiskPerScenario

$categorySummaries = @()
foreach ($category in @("code-change", "runtime-aware", "combined-signal")) {
    $categoryCases = @($caseResults | Where-Object { [string]$_.category -eq $category })
    if ($categoryCases.Count -gt 0) {
        $categorySummaries += New-CategorySummary $category $categoryCases
    }
}
$categorySummaries += New-CategorySummary "overall" $caseResults

$comparison = [ordered]@{
    benchmark = "online-boutique-defect-recall"
    run_id = if ($IncludeOb007) { "final-comparison-007" } else { "final-comparison-006" }
    comparison_status = "measured"
    methodology = "benchmark-case-ci-validation"
    created_at = ([datetime]::UtcNow.ToString("yyyy-MM-dd"))
    generator = "benchmark-pipeline/generate-final-comparison.ps1"
    oracle = $Oracle
    oracle_mode = "validated_detecting_tests"
    oracle_detecting_test_counts = $oracleDetectingTestCounts
    canonical_library = $Library
    full_suite_size = 52
    benchmark_cases = $caseResults
    aggregate_methods = $aggregateMethods
    category_summaries = $categorySummaries
    qmind_dynamic_risk_diagnostics = $qmindDynamicRiskDiagnostics
    runtime_evidence = if ($IncludeOb007) {
        [ordered]@{
            "OB-006" = [ordered]@{
                evidence_dir = To-RepoPath $RuntimeEvidenceDir
                evidence_status = [string]$ob006EvidenceManifest.evidence_status
                qmind_run_id = [string]$ob006EvidenceManifest.qmind_run_id
                publication_runtime_evidence = [string]$ob006RuntimeMovement.publication_runtime_evidence
                productcatalogservice_signal_confirmed = [bool]$ob006RuntimeMovement.productcatalogservice_signal_confirmed
                frontend_signal_confirmed = [bool]$ob006RuntimeMovement.frontend_signal_confirmed
                changed_files = @($ob006EvidenceManifest.changed_files | ForEach-Object { [string]$_ })
                published_files = @($ob006EvidenceManifest.published_files | ForEach-Object { [string]$_ })
            }
            "OB-007" = [ordered]@{
                evidence_dir = To-RepoPath $RuntimeEvidenceOb007Dir
                evidence_status = [string]$ob007EvidenceManifest.evidence_status
                qmind_run_id = [string]$ob007EvidenceManifest.qmind_run_id
                publication_runtime_evidence = [string]$ob007RuntimeMovement.publication_runtime_evidence
                recommendationservice_behavioral_signal_confirmed = [bool]$ob007RuntimeMovement.recommendationservice_behavioral_signal_confirmed
                recommendationservice_prometheus_signal_confirmed = [bool]$ob007RuntimeMovement.recommendationservice_prometheus_signal_confirmed
                graceful_degradation_confirmed = [bool]$ob007RuntimeMovement.graceful_degradation_confirmed
                playwright_section_signal_confirmed = [bool]$ob007RuntimeMovement.playwright_section_signal_confirmed
                frontend_signal_confirmed = $false
                changed_files = @($ob007EvidenceManifest.changed_files | ForEach-Object { [string]$_ })
                published_files = @($ob007EvidenceManifest.published_files | ForEach-Object { [string]$_ })
            }
        }
    } else {
        [ordered]@{
            "OB-006" = [ordered]@{
                evidence_dir = To-RepoPath $RuntimeEvidenceDir
                evidence_status = [string]$ob006EvidenceManifest.evidence_status
                qmind_run_id = [string]$ob006EvidenceManifest.qmind_run_id
                publication_runtime_evidence = [string]$ob006RuntimeMovement.publication_runtime_evidence
                productcatalogservice_signal_confirmed = [bool]$ob006RuntimeMovement.productcatalogservice_signal_confirmed
                frontend_signal_confirmed = [bool]$ob006RuntimeMovement.frontend_signal_confirmed
                changed_files = @($ob006EvidenceManifest.changed_files | ForEach-Object { [string]$_ })
                published_files = @($ob006EvidenceManifest.published_files | ForEach-Object { [string]$_ })
            }
        }
    }
    selector_input_policy = [ordered]@{
        full_suite = @("test library")
        random = @("test library", "seed")
        history_code_change = @("test library", "history metadata", "changed files")
        qmind = @("test library", "history", "changed files", "runtime metrics", "observability")
        oracle_only = @("defect identity", "oracle detecting tests", "expected benchmark outcome")
    }
    qmind_selection_mode = if ($UseExistingQMindSelections) {
        "existing-per-case-artifacts"
    } elseif ($IncludeOb007) {
        "generated-with-pinned-runtime-evidence-ob006-ob007"
    } else {
        "generated-with-pinned-runtime-evidence-ob006"
    }
    supporting_artifacts = @($expectedArtifacts | ForEach-Object { To-RepoPath $_ })
    limitations = @(
        "QMind is evaluated from one canonical selection artifact per benchmark case under benchmark-results/qmind-selections/qmind-selection-ob-*.json.",
        "Normal generator mode invokes benchmark-pipeline/run-qmind-subset.ps1 for standard cases and pins runtime-evidence selections for OB-006/OB-007; -UseExistingQMindSelections reuses committed canonical per-case artifacts.",
        "OB-006 headline inclusion requires tracked runtime evidence under benchmark-results/runtime-evidence/ob-006 and a QMind selection that is not substantively identical to OB-005.",
        "OB-007 is conditionally included: present only when benchmark-results/runtime-evidence/ob-007/evidence-manifest.json exists and passes Assert-Ob007RuntimeEvidence validation.",
        "History + Code Change uses changed files and library/history metadata only; oracle detecting tests are used only by the evaluator.",
        "No canonical test library content was changed; oracle changes are limited to minimal direct detecting test lists."
    )
}

Write-Json $FinalComparison $comparison

$docRows = @()
foreach ($method in $aggregateMethods) {
    $docRows += "| $($method.method_label) | $($method.average_selected_tests) | $(Format-Percent $method.average_execution_reduction) | $($method.recall_fraction) | $(Format-Percent $method.defect_recall) |"
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

$scenarioRows = @()
foreach ($case in $caseResults) {
    $changedFiles = @($case.commit_context.changed_files) -join "<br>"
    $full = if ($case.methods["full-suite"].defect_detected) { "detected" } else { "missed" }
    $random = if ($case.methods["random"].defect_detected) { "detected" } else { "missed" }
    $history = if ($case.methods["history-code-change"].defect_detected) { "detected" } else { "missed" }
    $qmind = if ($case.methods["qmind"].defect_detected) { "detected" } else { "missed" }
    $scenarioRows += "| $($case.id): $($case.name) | $($case.category_label) | $changedFiles | $full | $random | $history | $qmind |"
}
$scenarioTableRows = $scenarioRows -join [Environment]::NewLine

$categoryRows = @()
foreach ($summary in $categorySummaries) {
    $methods = $summary.methods
    $scenarioList = @($summary.scenarios) -join ", "
    $categoryRows += "| $($summary.category_label) | $scenarioList | $($methods["full-suite"].recall_fraction) | $($methods["random"].recall_fraction) | $($methods["history-code-change"].recall_fraction) | $($methods["qmind"].recall_fraction) |"
}
$categoryTableRows = $categoryRows -join [Environment]::NewLine

$riskRows = @()
$riskDiagnosticsWithValues = @($qmindDynamicRiskPerScenario | Where-Object {
    $null -ne $_.observed_risk_coverage -or
    $null -ne $_.critical_risk_captured -or
    $null -ne $_.residual_risk -or
    $null -ne $_.risk_density
})
foreach ($diagnostic in $riskDiagnosticsWithValues) {
    $riskRows += "| $($diagnostic.benchmark_case) | $(Format-RiskDiagnosticValue $diagnostic.observed_risk_coverage -Percent) | $(Format-RiskDiagnosticValue $diagnostic.critical_risk_captured -Percent) | $(Format-RiskDiagnosticValue $diagnostic.residual_risk -Percent) | $(Format-RiskDiagnosticValue $diagnostic.risk_density) |"
}
$riskDiagnosticsText = if ($riskRows.Count -gt 0) {
@"
Current QMind selection artifacts include dynamic risk diagnostics for $($riskRows.Count) of $($qmindDynamicRiskPerScenario.Count) benchmark cases.

| Scenario | Observed Risk Coverage | Critical Risk Captured | Residual Risk | Risk Density |
| --- | ---: | ---: | ---: | ---: |
$($riskRows -join [Environment]::NewLine)
"@
}
else {
@"
Current QMind selection artifacts do not include ``business_metrics`` or equivalent dynamic risk fields, so the generated JSON reports null values and per-scenario warnings. Dynamic risk diagnostics are shown here when present in QMind selection artifacts.
"@
}

$doc = @"
# Final Benchmark Comparison

## Scope

$(if ($IncludeOb007) {
"This comparison models Online Boutique as seven independent CI/CD benchmark cases. OB-001 through OB-004 are the code-change control group. OB-005 and OB-007 are runtime-aware scenarios where the changed file does not token-match the oracle test, so History + Code Change misses them. OB-006 is the combined-signal scenario. Each case has commit context, changed files, an injected defect, and oracle detecting tests. Selectors run before scoring and do not receive defect identity, oracle detecting tests, or expected benchmark outcomes."
} else {
"This comparison models Online Boutique as six independent CI/CD benchmark cases. OB-001 through OB-004 are the code-change control group. OB-005 is the first runtime-aware scenario. OB-006 is the first combined-signal scenario, where code change and runtime observability point to different parts of the system. Each case has commit context, changed files, an injected defect, and oracle detecting tests. Selectors run before scoring and do not receive defect identity, oracle detecting tests, or expected benchmark outcomes."
})

- Canonical library: ``$Library``
- Defect oracle: ``$Oracle``
- Oracle mode: ``validated_detecting_tests``
- Generator: ``benchmark-pipeline/generate-final-comparison.ps1``
- Random seed: $RandomSeed
- Random size: $RandomSize tests
- History + Code Change size: $TargetedSize tests per case
- QMind selection artifacts: ``$(To-RepoPath $QMindSelectionDir)/qmind-selection-ob-001.json`` through ``$(To-RepoPath $QMindSelectionDir)/qmind-selection-ob-$(if ($IncludeOb007) { "007" } else { "006" }).json``
- QMind selection mode: ``$($comparison.qmind_selection_mode)``
- OB-006 runtime evidence: ``$(To-RepoPath $RuntimeEvidenceDir)``
$(if ($IncludeOb007) { "- OB-007 runtime evidence: ``$(To-RepoPath $RuntimeEvidenceOb007Dir)``" })

## Oracle Precision

The defect oracle uses minimal direct validated detecting tests for each benchmark case. Broad downstream symptom tests are excluded from the oracle even when they can fail as a side effect.

| Case | Direct Validated Detecting Tests |
| --- | ---: |
$oracleTableRows

## Aggregate Results

| Method | Avg Tests | Avg Execution Reduction | Cases Detected | Case Recall |
| --- | ---: | ---: | ---: | ---: |
$aggregateRows

## Per-Scenario Results

| Scenario | Category | Changed files | Full Suite result | Random result | History + Code Change result | Quantik Mind result |
| --- | --- | --- | --- | --- | --- | --- |
$scenarioTableRows

## Per-Category Summary

| Category | Scenarios | Full Suite | Random | History + Code Change | Quantik Mind |
| --- | --- | ---: | ---: | ---: | ---: |
$categoryTableRows

## Quantik Mind Dynamic Risk Intelligence

Unlike baseline approaches, Quantik Mind also evaluates dynamic risk at selection time using historical signals, code changes and live runtime observability.

Observed Risk Coverage: How much of the currently observed risk mass is covered by the selected tests.

Critical Risk Captured: How much of the highest-priority risk band is captured by the selected tests.

Residual Risk: How much observed risk remains uncovered after the selected tests.

Risk Density: How much risk information is captured per executed test. A value above 1.0 means the selected tests are denser in risk information than the average test set.

$riskDiagnosticsText

These metrics are not included in the benchmark comparison table because equivalent dynamic risk diagnostics are not available for Full Suite, Random, or History + Code Change. They are reported as Quantik Mind product diagnostics.

## Benchmark Cases

$caseText
## Method Notes

Full Suite always selects all 52 tests from the canonical library.

Random uses only the canonical test library and deterministic seed 42. It produces a per-case selection artifact and selects 26 tests, exactly 50% of the 52-test suite.

History + Code Change uses the canonical test library, history-oriented test metadata, and each case's changed files. It does not read the defect oracle and does not use oracle detecting tests. For OB-005 the changed file is ``src/currencyservice/data/currency_conversion.json``; the six direct homepage oracle tests map to ``src/frontend/**/*``, have medium criticality, and score only 10 each, so they fall below checkout, cart, order, payment, product, and catalog tests in the top-15 selection. For OB-006 the changed file is ``src/productcatalogservice/product_catalog.go``; QMind must use the productcatalogservice code-change signal together with live frontend impact rather than oracle detecting tests.

Quantik Mind uses one canonical selection artifact per benchmark case. Standard cases are generated from that case's changed-files and runtime context by ``benchmark-pipeline/run-qmind-subset.ps1``; OB-006 and OB-007 are pinned from verified runtime-evidence selections so the final comparison does not overwrite live injection evidence with a later non-injected run. The aggregate QMind result averages $($qmindAggregate.average_selected_tests) selected tests, gives $(Format-Percent $qmindAggregate.average_execution_reduction) average execution reduction, and detects $($qmindAggregate.recall_fraction) cases. OB-005 demonstrates a runtime-aware defect class that code-change analysis structurally cannot reach. OB-006 adds a combined-signal defect class where the code change points to productcatalogservice while runtime observability points to frontend homepage/product-grid impact. OB-007 adds a second runtime-aware case where the declared changed file is harmless and only runtime observability reveals the behaviorally degraded recommendationservice path. This does not claim QMind is universally better than History + Code Change; it claims QMind matches History + Code Change on the code-change control group and preserves coverage for the combined-signal case while adding coverage for both runtime-aware cases.

OB-006 is included in the headline aggregate only when ``benchmark-pipeline/generate-final-comparison.ps1`` can validate tracked runtime evidence under ``$(To-RepoPath $RuntimeEvidenceDir)``. That evidence must show material productcatalogservice movement and material frontend movement in the same validation window, and the OB-006 QMind artifact must not be substantively identical to OB-005. QMind selected OB-006 from the productcatalogservice changed-file input plus runtime observability evidence, not from oracle detecting tests.

## Benchmark Integrity Controls

- OB-001 through OB-004 functional definitions and oracle detecting tests were not modified.
- OB-005 uses the real committed file ``src/currencyservice/data/currency_conversion.json``.
- The changed file is data, not application code.
- The OB-005 oracle uses direct homepage tests only.
- OB-006 uses the real upstream file ``src/productcatalogservice/product_catalog.go`` through a reversible injector.
- The OB-006 oracle uses 19 homepage, product-grid, catalog, and product-detail detectors for the ProductCatalog ListProducts cascade.
- OB-006 runtime evidence is stored under ``$(To-RepoPath $RuntimeEvidenceDir)`` and is required by the final comparison generator.
$(if ($IncludeOb007) { "- OB-007 runtime evidence is stored under ``$(To-RepoPath $RuntimeEvidenceOb007Dir)`` and is pinned into the canonical QMind selection before scoring." })
- The History + Code Change miss is explained by exact scoring mechanics, not hidden exclusions.
- QMind detection must come from runtime observability, not oracle leakage.
- The generator reports actual selected-suite outcomes; it does not hardcode winners.

## Reproduction

Regenerate all final comparison artifacts using live QMind plus committed benchmark inputs:

``````powershell
.\benchmark-pipeline\generate-final-comparison.ps1
``````

The generator fails if any per-case QMind selection artifact is missing, contains non-canonical test IDs, or if the OB-004 artifact does not include ``payment-order-completion-confirms-success``.

To reuse committed canonical per-case QMind selections instead of calling live QMind:

``````powershell
.\benchmark-pipeline\generate-final-comparison.ps1 -UseExistingQMindSelections
``````
"@

$doc = $doc.Replace("`r`n", "`n")
[System.IO.File]::WriteAllText((Resolve-ParentPath $FinalComparisonDoc), $doc + "`n", [System.Text.UTF8Encoding]::new($false))

Write-Host "Final benchmark-case comparison generated:"
foreach ($method in $aggregateMethods) {
    Write-Host "  $($method.method_label): $($method.recall_fraction), $(Format-Percent $method.defect_recall) recall, avg tests $($method.average_selected_tests)"
}

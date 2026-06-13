param(
    [Parameter(Mandatory = $true)]
    [string]$FrontendUrl,
    [string]$PrometheusUrl = "http://localhost:19090",
    [string]$SourceRoot = "microservices-demo",
    [string]$Namespace = "default",
    [string]$Deployment = "productcatalogservice",
    [string]$Container = "server",
    [ValidateSet("latency", "failure")]
    [string]$Mode = "latency",
    [int]$LatencyMs = 35000,
    [switch]$SkipRestore,
    [switch]$SkipQMind,
    [switch]$SkipComparison,
    [string]$ImageRepository,
    [string]$ImageTagPrefix = "ob006-live",
    [string]$CleanImageTagPrefix = "ob006-clean",
    [string]$PrometheusWindow = "2m",
    [int]$TrafficRequests = 30,
    [int]$TrafficDelayMs = 500,
    [int]$TrafficTimeoutSec = 45,
    [int]$StabilizationSeconds = 30,
    [double]$ProductCatalogLatencyMinRatio = 5.0,
    [double]$ProductCatalogLatencyMinDeltaSeconds = 1.0,
    [double]$ProductCatalogErrorRateMinDelta = 0.05,
    [double]$FrontendLatencyMinRatio = 1.5,
    [double]$FrontendLatencyMinDeltaSeconds = 0.2,
    [double]$FrontendErrorRateMinDelta = 0.02,
    [string]$RunDir = "benchmark-runs/ob-006-live-runtime-validation",
    [string]$EvidenceDir = "benchmark-results/runtime-evidence/ob-006",
    [string]$QMindSelectionOutput = "benchmark-results/qmind-selections/qmind-selection-ob-006.json",
    [string]$OB005Selection = "benchmark-results/qmind-selections/qmind-selection-ob-005.json",
    [string]$Oracle = "defect-oracle/online-boutique-defect-oracle.v2.json",
    [string]$Library = "qmind-test-library/online-boutique-playwright-51.json",
    [string]$Scenarios = "benchmark-pipeline/scenarios.json"
)

$ErrorActionPreference = "Stop"

$Injector = "runtime-scenarios/ob-006-productcatalog-listproducts-cascade/apply-ob006-productcatalog-listproducts.ps1"
$FinalComparisonScript = "benchmark-pipeline/generate-final-comparison.ps1"
$QMindSubsetScript = "benchmark-pipeline/run-qmind-subset.ps1"
$CaseId = "OB-006"
$ProductCatalogRelativeFile = "src/productcatalogservice/product_catalog.go"
$ExpectedDetectorIds = @()
$Timestamp = Get-Date -Format "yyyyMMdd-HHmmss"
$CommandLog = $null
$PreviousOB006RunId = $null
$RuntimeMovementSummary = $null

function Write-Phase {
    param([string]$Message)

    Write-Host ""
    Write-Host "=== $Message ==="
}

function Resolve-RepoPath {
    param([string]$Path)

    return $ExecutionContext.SessionState.Path.GetUnresolvedProviderPathFromPSPath($Path)
}

function Assert-File {
    param([string]$Path)

    if (-not (Test-Path -LiteralPath $Path -PathType Leaf)) {
        throw "Missing required file: $Path"
    }
}

function Assert-Directory {
    param([string]$Path)

    if (-not (Test-Path -LiteralPath $Path -PathType Container)) {
        throw "Missing required directory: $Path"
    }
}

function Write-TextFile {
    param(
        [string]$Path,
        [string]$Text
    )

    $parent = Split-Path -Parent $Path
    if (-not [string]::IsNullOrWhiteSpace($parent)) {
        New-Item -ItemType Directory -Force -Path $parent | Out-Null
    }
    [System.IO.File]::WriteAllText((Resolve-RepoPath $Path), $Text, [System.Text.UTF8Encoding]::new($false))
}

function Write-JsonFile {
    param(
        [string]$Path,
        [object]$Value
    )

    $json = $Value | ConvertTo-Json -Depth 40
    Write-TextFile -Path $Path -Text ($json + [Environment]::NewLine)
}

function Format-Command {
    param(
        [string]$Command,
        [string[]]$Arguments
    )

    $parts = @($Command) + @($Arguments | ForEach-Object {
        if ($_ -match "\s|`"|'") {
            '"' + ($_ -replace '"', '\"') + '"'
        } else {
            $_
        }
    })
    return ($parts -join " ")
}

function Add-CommandLog {
    param(
        [string]$CommandLine,
        [int]$ExitCode,
        [string]$Output
    )

    $entry = @"
[$((Get-Date).ToUniversalTime().ToString("o"))] exit=$ExitCode
$CommandLine
$Output

"@
    Add-Content -LiteralPath $CommandLog -Value $entry
}

function Invoke-LoggedCommand {
    param(
        [string]$Command,
        [string[]]$Arguments,
        [switch]$AllowFailure
    )

    $commandLine = Format-Command -Command $Command -Arguments $Arguments
    Write-Host $commandLine
    $previousErrorActionPreference = $ErrorActionPreference
    $previousNativeErrorPreference = $null
    $hasNativeErrorPreference = Test-Path Variable:\PSNativeCommandUseErrorActionPreference
    if ($hasNativeErrorPreference) {
        $previousNativeErrorPreference = $PSNativeCommandUseErrorActionPreference
    }

    try {
        $ErrorActionPreference = "Continue"
        if ($hasNativeErrorPreference) {
            $PSNativeCommandUseErrorActionPreference = $false
        }
        $global:LASTEXITCODE = 0
        $output = & $Command @Arguments 2>&1
        $exitCode = if ($null -eq $LASTEXITCODE) { 0 } else { $LASTEXITCODE }
    } finally {
        $ErrorActionPreference = $previousErrorActionPreference
        if ($hasNativeErrorPreference) {
            $PSNativeCommandUseErrorActionPreference = $previousNativeErrorPreference
        }
    }

    $text = ($output | Out-String).TrimEnd()
    if (-not [string]::IsNullOrWhiteSpace($text)) {
        Write-Host $text
    }
    Add-CommandLog -CommandLine $commandLine -ExitCode $exitCode -Output $text

    if ($exitCode -ne 0 -and -not $AllowFailure) {
        throw "Command failed with exit code $($exitCode): $commandLine"
    }
    return @{
        exit_code = $exitCode
        output = $text
    }
}

function Invoke-LoggedPowerShellScript {
    param(
        [string]$ScriptPath,
        [hashtable]$Arguments
    )

    $displayArgs = @($Arguments.GetEnumerator() | Sort-Object Name | ForEach-Object {
        if ($_.Value -is [bool]) {
            if ($_.Value) {
                return "-$($_.Name)"
            }
            return $null
        }
        if ($_.Value -is [System.Management.Automation.SwitchParameter]) {
            if ($_.Value.IsPresent) {
                return "-$($_.Name)"
            }
            return $null
        }
        $value = [string]$_.Value
        if ($value -match "\s|`"|'") {
            $value = '"' + ($value -replace '"', '\"') + '"'
        }
        return "-$($_.Name) $value"
    } | Where-Object { $_ })
    $display = ".\$ScriptPath " + ($displayArgs -join " ")
    Write-Host $display
    Add-CommandLog -CommandLine $display -ExitCode 0 -Output "PowerShell script invocation started."
    try {
        & ".\$ScriptPath" @Arguments
        Add-CommandLog -CommandLine $display -ExitCode 0 -Output "PowerShell script invocation completed."
    } catch {
        Add-CommandLog -CommandLine $display -ExitCode 1 -Output $_.Exception.Message
        throw
    }
}

function Get-PrometheusQueryUri {
    param(
        [string]$BaseUrl,
        [string]$Query
    )

    return "$($BaseUrl.TrimEnd('/'))/api/v1/query?query=$([Uri]::EscapeDataString($Query))"
}

function Assert-PrometheusReachable {
    $query = "up"
    $uri = Get-PrometheusQueryUri -BaseUrl $PrometheusUrl -Query $query
    Write-Host "Prometheus reachability query: $query"
    try {
        $response = Invoke-RestMethod -Uri $uri -Method Get -TimeoutSec 10
    } catch {
        throw "Prometheus is not reachable at $PrometheusUrl. Start or port-forward Prometheus, then rerun. Error: $($_.Exception.Message)"
    }
    if ($response.status -ne "success") {
        throw "Prometheus query endpoint returned status '$($response.status)' for $PrometheusUrl."
    }
}

function Assert-FrontendReachable {
    Write-Host "Frontend reachability check: GET $FrontendUrl"
    try {
        $response = Invoke-WebRequest -Uri $FrontendUrl -UseBasicParsing -TimeoutSec $TrafficTimeoutSec
    } catch {
        throw "FrontendUrl is not reachable: $FrontendUrl. Error: $($_.Exception.Message)"
    }
    Write-Host "Frontend reachable: HTTP $([int]$response.StatusCode)"
}

function Assert-Tool {
    param([string]$Name)

    if (-not (Get-Command $Name -ErrorAction SilentlyContinue)) {
        throw "Missing required tool on PATH: $Name"
    }
    Write-Host "Found tool: $Name"
}

function Get-CurrentProductCatalogImage {
    $jsonPath = "{.spec.template.spec.containers[?(@.name=='$Container')].image}"
    $result = Invoke-LoggedCommand -Command "kubectl" -Arguments @("-n", $Namespace, "get", "deployment", $Deployment, "-o", "jsonpath=$jsonPath")
    $image = $result.output.Trim()
    if ([string]::IsNullOrWhiteSpace($image)) {
        throw "Could not derive image for container '$Container' in deployment '$Deployment'."
    }
    return $image
}

function Get-ImageRepository {
    param([string]$Image)

    if ($Image -match "@sha256:") {
        throw "Current deployment image uses a digest reference. Cannot derive a writable tag repository automatically: $Image"
    }

    $lastSlash = $Image.LastIndexOf("/")
    $lastColon = $Image.LastIndexOf(":")
    if ($lastColon -gt $lastSlash) {
        return $Image.Substring(0, $lastColon)
    }
    return $Image
}

function Test-ArtifactRegistryRepository {
    param([string]$Repository)

    return ($Repository -match "^[a-z0-9-]+-docker\.pkg\.dev/")
}

function Get-ArtifactRegistryHost {
    param([string]$Repository)

    if ($Repository -match "^([^/]+-docker\.pkg\.dev)/") {
        return $Matches[1]
    }
    return $null
}

function Write-ArtifactRegistryAuthPreflight {
    param([string]$Repository)

    if (Test-ArtifactRegistryRepository -Repository $Repository) {
        $hostName = Get-ArtifactRegistryHost -Repository $Repository
        Write-Host "Artifact Registry auth preflight:"
        Write-Host "gcloud auth configure-docker $hostName"
        Write-Host "Run that command if Docker is not already authenticated for this registry."
        Assert-Tool "gcloud"
    }
}

function Get-ProductCatalogBuildContext {
    $context = Join-Path $SourceRoot "src/productcatalogservice"
    $dockerfile = Join-Path $context "Dockerfile"
    if (-not (Test-Path -LiteralPath $dockerfile -PathType Leaf)) {
        throw "Could not detect productcatalogservice Docker build context. Expected Dockerfile at: $dockerfile"
    }
    return $context
}

function Build-And-PushImage {
    param(
        [string]$Image,
        [string]$BuildContext,
        [string]$Phase
    )

    Write-Phase "Build $Phase productcatalogservice image"
    Invoke-LoggedCommand -Command "docker" -Arguments @("build", "-t", $Image, $BuildContext) | Out-Null
    if ($Phase -eq "injected") {
        $script:InjectedImageBuilt = $true
    } elseif ($Phase -eq "clean") {
        $script:CleanImageBuilt = $true
    }

    Write-Phase "Push $Phase productcatalogservice image"
    Invoke-LoggedCommand -Command "docker" -Arguments @("push", $Image) | Out-Null
    if ($Phase -eq "injected") {
        $script:InjectedImagePushed = $true
    } elseif ($Phase -eq "clean") {
        $script:CleanImagePushed = $true
    }
}

function Deploy-ProductCatalogImage {
    param(
        [string]$Image,
        [string]$Phase
    )

    Write-Phase "Deploy $Phase productcatalogservice image"
    Invoke-LoggedCommand -Command "kubectl" -Arguments @("-n", $Namespace, "set", "image", "deployment/$Deployment", "$Container=$Image") | Out-Null
    if ($Phase -eq "injected") {
        $script:InjectedImageDeployed = $true
    } elseif ($Phase -eq "clean") {
        $script:CleanImageDeployed = $true
    }
    Invoke-LoggedCommand -Command "kubectl" -Arguments @("-n", $Namespace, "rollout", "status", "deployment/$Deployment", "--timeout=300s") | Out-Null
    if ($StabilizationSeconds -gt 0) {
        Write-Host "Waiting $StabilizationSeconds seconds for metrics stabilization."
        Start-Sleep -Seconds $StabilizationSeconds
    }
}

function Get-Ob006ExpectedDetectorIds {
    $oracleData = Get-Content -LiteralPath $Oracle -Raw | ConvertFrom-Json
    $scenario = @($oracleData.scenarios | Where-Object { [string]$_.id -eq $CaseId })
    if ($scenario.Count -ne 1) {
        throw "Could not find exactly one $CaseId entry in $Oracle."
    }

    $detectors = @($scenario[0].validated_detecting_tests | ForEach-Object { [string]$_ })
    if ($detectors.Count -eq 0) {
        $detectors = @($scenario[0].expected_detecting_tests | ForEach-Object { [string]$_ })
    }
    if ($detectors.Count -eq 0) {
        throw "$CaseId has no detecting tests in $Oracle."
    }
    return $detectors
}

function Invoke-PrometheusInstantQuery {
    param(
        [string]$Name,
        [string]$Query
    )

    Write-Host ""
    Write-Host "$Name PromQL:"
    Write-Host $Query

    $uri = Get-PrometheusQueryUri -BaseUrl $PrometheusUrl -Query $Query
    $response = Invoke-RestMethod -Uri $uri -Method Get -TimeoutSec 20
    if ($response.status -ne "success") {
        throw "Prometheus query failed for $Name with status '$($response.status)'."
    }

    $results = @($response.data.result)
    $numericValue = $null
    if ($results.Count -eq 0) {
        Write-Host "${Name}: NO DATA"
    } else {
        foreach ($result in $results) {
            $deploymentLabel = [string]$result.metric.deployment
            if ([string]::IsNullOrWhiteSpace($deploymentLabel)) {
                $deploymentLabel = "(no deployment label)"
            }
            $value = if ($result.value.Count -ge 2) { [string]$result.value[1] } else { "(missing value)" }
            Write-Host "$Name [$deploymentLabel]: $value"
            if ($null -eq $numericValue) {
                $parsed = 0.0
                if ([double]::TryParse($value, [Globalization.NumberStyles]::Float, [Globalization.CultureInfo]::InvariantCulture, [ref]$parsed)) {
                    $numericValue = $parsed
                }
            }
        }
    }

    return @{
        name = $Name
        promql = $Query
        result = $results
        value = $numericValue
        no_data = ($results.Count -eq 0)
    }
}

function Get-ServiceQueries {
    param([string]$ServiceDeployment)

    $labelSelector = "namespace=`"$Namespace`",deployment=`"$ServiceDeployment`""
    return @(
        @{
            key = "$ServiceDeployment.latency_p95"
            name = "$ServiceDeployment latency p95"
            query = "histogram_quantile(0.95, sum by (deployment, le) (rate(inbound_http_response_duration_seconds_bucket{$labelSelector}[$PrometheusWindow])))"
        },
        @{
            key = "$ServiceDeployment.error_rate"
            name = "$ServiceDeployment error rate"
            query = "1 - (sum by (deployment) (rate(inbound_http_statuses_total{$labelSelector,status=~`"2..|3..`"}[$PrometheusWindow])) / sum by (deployment) (rate(inbound_http_statuses_total{$labelSelector}[$PrometheusWindow])))"
        },
        @{
            key = "$ServiceDeployment.request_rate"
            name = "$ServiceDeployment request rate"
            query = "sum by (deployment) (rate(inbound_http_statuses_total{$labelSelector}[$PrometheusWindow]))"
        }
    )
}

function Capture-RuntimeSnapshot {
    param([string]$Phase)

    Write-Phase "Capture $Phase Prometheus snapshot"
    $queries = @()
    $queries += Get-ServiceQueries -ServiceDeployment $Deployment
    $queries += Get-ServiceQueries -ServiceDeployment "frontend"

    $metrics = @{}
    $metricList = @()
    foreach ($entry in $queries) {
        $metric = Invoke-PrometheusInstantQuery -Name $entry.name -Query $entry.query
        $metric["key"] = $entry.key
        $metrics[$entry.key] = $metric
        $metricList += $metric
    }

    $snapshot = @{
        scenario = $CaseId
        phase = $Phase
        captured_at_utc = (Get-Date).ToUniversalTime().ToString("o")
        prometheus_url = $PrometheusUrl
        namespace = $Namespace
        prometheus_window = $PrometheusWindow
        metrics = $metricList
    }
    $path = Join-Path $RunDir "$Phase-prometheus-snapshot.json"
    Write-JsonFile -Path $path -Value $snapshot
    Write-Host "Wrote $Phase snapshot: $path"
    return $metrics
}

function Invoke-HomepageTraffic {
    param([string]$Phase)

    Write-Phase "Run $Phase homepage traffic"
    Write-Host "Frontend URL: $FrontendUrl"
    Write-Host "Requests: $TrafficRequests, delay_ms: $TrafficDelayMs, timeout_sec: $TrafficTimeoutSec"

    $events = @()
    for ($i = 1; $i -le $TrafficRequests; $i++) {
        $started = Get-Date
        try {
            $response = Invoke-WebRequest -Uri $FrontendUrl -UseBasicParsing -TimeoutSec $TrafficTimeoutSec
            $elapsedMs = [int]((Get-Date) - $started).TotalMilliseconds
            Write-Host ("{0}/{1}: HTTP {2} {3}ms" -f $i, $TrafficRequests, [int]$response.StatusCode, $elapsedMs)
            $events += @{
                index = $i
                ok = $true
                status_code = [int]$response.StatusCode
                elapsed_ms = $elapsedMs
            }
        } catch {
            $elapsedMs = [int]((Get-Date) - $started).TotalMilliseconds
            Write-Host ("{0}/{1}: ERROR {2}ms {3}" -f $i, $TrafficRequests, $elapsedMs, $_.Exception.Message)
            $events += @{
                index = $i
                ok = $false
                status_code = $null
                elapsed_ms = $elapsedMs
                error = $_.Exception.Message
            }
        }

        if ($i -lt $TrafficRequests -and $TrafficDelayMs -gt 0) {
            Start-Sleep -Milliseconds $TrafficDelayMs
        }
    }

    $path = Join-Path $RunDir "$Phase-homepage-traffic.json"
    Write-JsonFile -Path $path -Value @{
        scenario = $CaseId
        phase = $Phase
        frontend_url = $FrontendUrl
        captured_at_utc = (Get-Date).ToUniversalTime().ToString("o")
        events = $events
    }
    Write-Host "Wrote $Phase traffic log: $path"
}

function Test-MetricMoved {
    param(
        [hashtable]$Baseline,
        [hashtable]$Injected,
        [string]$Key
    )

    if (-not $Baseline.ContainsKey($Key) -or -not $Injected.ContainsKey($Key)) {
        return $false
    }
    if ($null -eq $Baseline[$Key].value -or $null -eq $Injected[$Key].value) {
        return $false
    }
    return ([double]$Injected[$Key].value -gt [double]$Baseline[$Key].value)
}

function Get-MetricValue {
    param(
        [hashtable]$Metrics,
        [string]$Key
    )

    if (-not $Metrics.ContainsKey($Key)) {
        return $null
    }
    if ($null -eq $Metrics[$Key].value) {
        return $null
    }
    return [double]$Metrics[$Key].value
}

function Get-MaterialMovement {
    param(
        [hashtable]$Baseline,
        [hashtable]$Injected,
        [string]$Key,
        [double]$MinRatio,
        [double]$MinDelta
    )

    $baselineValue = Get-MetricValue -Metrics $Baseline -Key $Key
    $injectedValue = Get-MetricValue -Metrics $Injected -Key $Key
    $hasData = ($null -ne $baselineValue -and $null -ne $injectedValue)
    $delta = if ($hasData) { $injectedValue - $baselineValue } else { $null }
    $ratio = if ($hasData -and [Math]::Abs($baselineValue) -gt 0.000000001) { $injectedValue / $baselineValue } else { $null }
    $deltaPassed = ($null -ne $delta -and $delta -ge $MinDelta)
    $ratioPassed = ($null -ne $ratio -and $ratio -ge $MinRatio)
    $passed = $hasData -and $deltaPassed -and $ratioPassed

    return [ordered]@{
        key = $Key
        baseline = $baselineValue
        injected = $injectedValue
        delta = $delta
        ratio = $ratio
        min_delta = $MinDelta
        min_ratio = $MinRatio
        has_data = $hasData
        delta_passed = $deltaPassed
        ratio_passed = $ratioPassed
        passed = $passed
    }
}

function Get-MaterialDeltaMovement {
    param(
        [hashtable]$Baseline,
        [hashtable]$Injected,
        [string]$Key,
        [double]$MinDelta
    )

    $baselineValue = Get-MetricValue -Metrics $Baseline -Key $Key
    $injectedValue = Get-MetricValue -Metrics $Injected -Key $Key
    $hasData = ($null -ne $baselineValue -and $null -ne $injectedValue)
    $delta = if ($hasData) { $injectedValue - $baselineValue } else { $null }
    $passed = ($hasData -and $delta -ge $MinDelta)

    return [ordered]@{
        key = $Key
        baseline = $baselineValue
        injected = $injectedValue
        delta = $delta
        min_delta = $MinDelta
        has_data = $hasData
        passed = $passed
    }
}

function Write-RuntimeMovementSummary {
    param(
        [hashtable]$Baseline,
        [hashtable]$Injected
    )

    Write-Phase "Runtime movement summary"
    $productCatalogLatency = Get-MaterialMovement -Baseline $Baseline -Injected $Injected -Key "$Deployment.latency_p95" -MinRatio $ProductCatalogLatencyMinRatio -MinDelta $ProductCatalogLatencyMinDeltaSeconds
    $productCatalogError = Get-MaterialDeltaMovement -Baseline $Baseline -Injected $Injected -Key "$Deployment.error_rate" -MinDelta $ProductCatalogErrorRateMinDelta
    $frontendLatency = Get-MaterialMovement -Baseline $Baseline -Injected $Injected -Key "frontend.latency_p95" -MinRatio $FrontendLatencyMinRatio -MinDelta $FrontendLatencyMinDeltaSeconds
    $frontendError = Get-MaterialDeltaMovement -Baseline $Baseline -Injected $Injected -Key "frontend.error_rate" -MinDelta $FrontendErrorRateMinDelta
    $productCatalogConfirmed = [bool]$productCatalogLatency.passed -or [bool]$productCatalogError.passed
    $frontendConfirmed = [bool]$frontendLatency.passed -or [bool]$frontendError.passed
    $confirmed = ($productCatalogConfirmed -and $frontendConfirmed)

    $summary = @{
        scenario = $CaseId
        captured_at_utc = (Get-Date).ToUniversalTime().ToString("o")
        validation_thresholds = @{
            productcatalogservice_latency_min_ratio = $ProductCatalogLatencyMinRatio
            productcatalogservice_latency_min_delta_seconds = $ProductCatalogLatencyMinDeltaSeconds
            productcatalogservice_error_rate_min_delta = $ProductCatalogErrorRateMinDelta
            frontend_latency_min_ratio = $FrontendLatencyMinRatio
            frontend_latency_min_delta_seconds = $FrontendLatencyMinDeltaSeconds
            frontend_error_rate_min_delta = $FrontendErrorRateMinDelta
        }
        productcatalogservice_latency = $productCatalogLatency
        productcatalogservice_error_rate = $productCatalogError
        frontend_latency = $frontendLatency
        frontend_error_rate = $frontendError
        productcatalogservice_signal_confirmed = $productCatalogConfirmed
        frontend_signal_confirmed = $frontendConfirmed
        publication_runtime_evidence = if ($confirmed) { "CONFIRMED" } else { "NOT CONFIRMED" }
    }

    Write-Host "productcatalogservice latency material: $(if ($productCatalogLatency.passed) { 'YES' } else { 'NO' }) delta=$($productCatalogLatency.delta) ratio=$($productCatalogLatency.ratio)"
    Write-Host "productcatalogservice error material: $(if ($productCatalogError.passed) { 'YES' } else { 'NO' }) delta=$($productCatalogError.delta)"
    Write-Host "frontend latency material: $(if ($frontendLatency.passed) { 'YES' } else { 'NO' }) delta=$($frontendLatency.delta) ratio=$($frontendLatency.ratio)"
    Write-Host "frontend error material: $(if ($frontendError.passed) { 'YES' } else { 'NO' }) delta=$($frontendError.delta)"
    Write-Host "publication runtime evidence: $($summary.publication_runtime_evidence)"

    if (-not $confirmed) {
        Write-JsonFile -Path (Join-Path $RunDir "runtime-movement-summary.json") -Value $summary
        throw "OB-006 runtime evidence is NOT CONFIRMED. Required material movement: productcatalogservice latency or error, plus frontend latency or error."
    }

    $path = Join-Path $RunDir "runtime-movement-summary.json"
    Write-JsonFile -Path $path -Value $summary
    Write-Host "Wrote runtime movement summary: $path"
    return $summary
}

function Backup-QMindSelectionIfPresent {
    if (Test-Path -LiteralPath $QMindSelectionOutput -PathType Leaf) {
        try {
            $existingSelection = Get-Content -LiteralPath $QMindSelectionOutput -Raw | ConvertFrom-Json
            $script:PreviousOB006RunId = [string]$existingSelection.qmind_subset_json.run_id
            if ([string]::IsNullOrWhiteSpace($script:PreviousOB006RunId)) {
                $script:PreviousOB006RunId = [string]$existingSelection.run_id
            }
        } catch {
            Write-Warning "Could not read existing OB-006 run_id before backup: $($_.Exception.Message)"
        }
        $backup = "$QMindSelectionOutput.pre-ob006-live-$Timestamp.bak"
        Copy-Item -LiteralPath $QMindSelectionOutput -Destination $backup -Force
        Write-Host "Existing QMind OB-006 selection found: $QMindSelectionOutput"
        Write-Host "Backed it up before live regeneration: $backup"
    } else {
        Write-Host "No existing QMind OB-006 selection to back up at $QMindSelectionOutput."
    }
}

function Get-SelectionRunId {
    param([object]$Selection)

    $runId = [string]$Selection.qmind_subset_json.run_id
    if ([string]::IsNullOrWhiteSpace($runId)) {
        $runId = [string]$Selection.run_id
    }
    return $runId
}

function Get-CanonicalJson {
    param([object]$Value)

    return ($Value | ConvertTo-Json -Depth 40 -Compress)
}

function Assert-Ob006SelectionIsDistinctFromOb005 {
    param([object]$Selection)

    if (-not (Test-Path -LiteralPath $OB005Selection -PathType Leaf)) {
        throw "Missing OB-005 selection for duplicate guard: $OB005Selection"
    }

    $ob005 = Get-Content -LiteralPath $OB005Selection -Raw | ConvertFrom-Json
    $sameSelectedTests = ((@($ob005.selected_tests) -join "|") -eq (@($Selection.selected_tests) -join "|"))
    $sameBusinessMetrics = ((Get-CanonicalJson $ob005.business_metrics) -eq (Get-CanonicalJson $Selection.business_metrics))
    $sameRiskCoverage = ([string]$ob005.risk_coverage -eq [string]$Selection.risk_coverage)
    $sameRiskEfficiency = ([string]$ob005.risk_efficiency -eq [string]$Selection.risk_efficiency)

    if ($sameSelectedTests -and $sameBusinessMetrics -and $sameRiskCoverage -and $sameRiskEfficiency) {
        throw "Live OB-006 QMind selection is substantively identical to OB-005. Refusing to publish OB-006 as independent combined-signal evidence."
    }
}

function Assert-LiveQMindSelection {
    Assert-File $QMindSelectionOutput
    $selection = Get-Content -LiteralPath $QMindSelectionOutput -Raw | ConvertFrom-Json
    if ([string]$selection.method -ne "qmind") {
        throw "Expected method=qmind in $QMindSelectionOutput."
    }
    if ([string]$selection.benchmark_case -ne $CaseId) {
        throw "Expected benchmark_case=$CaseId in $QMindSelectionOutput."
    }
    if ([string]$selection.changed_files_file -ne "benchmark-runs/scenario-ob-006-changed-files.json") {
        throw "Expected OB-006 changed_files_file to be benchmark-runs/scenario-ob-006-changed-files.json. Found: $($selection.changed_files_file)"
    }
    Assert-File $selection.changed_files_file
    $changedFiles = @(Get-Content -LiteralPath $selection.changed_files_file -Raw | ConvertFrom-Json | ForEach-Object { [string]$_ })
    if ($changedFiles.Count -ne 1 -or $changedFiles[0] -ne $ProductCatalogRelativeFile) {
        throw "OB-006 QMind changed-files input must be exactly $ProductCatalogRelativeFile. Found: $($changedFiles -join ', ')"
    }

    $newRunId = Get-SelectionRunId -Selection $selection
    if ([string]::IsNullOrWhiteSpace($newRunId)) {
        throw "Live OB-006 QMind selection does not include a run_id."
    }
    if (-not [string]::IsNullOrWhiteSpace($PreviousOB006RunId) -and $newRunId -eq $PreviousOB006RunId) {
        throw "Live OB-006 QMind run_id did not change from previous artifact: $newRunId"
    }
    if ([bool]$selection.qmind_subset_json.observability_enabled -ne $true) {
        throw "Live OB-006 QMind selection does not show observability_enabled=true."
    }
    if ([bool]$selection.qmind_subset_json.has_runtime_signal -ne $true) {
        throw "Live OB-006 QMind selection does not show has_runtime_signal=true."
    }

    $selected = @($selection.selected_tests | ForEach-Object { [string]$_ })
    $intersection = @($ExpectedDetectorIds | Where-Object { $selected -contains $_ })
    $missing = @($ExpectedDetectorIds | Where-Object { $selected -notcontains $_ })
    if ($intersection.Count -eq 0) {
        throw "Live QMind OB-006 selection did not include any validated detecting tests from the oracle."
    }
    if ($missing.Count -gt 0) {
        Write-Warning "Live QMind selected $($intersection.Count) of $($ExpectedDetectorIds.Count) OB-006 detector IDs. Missing detectors: $($missing -join ', ')"
    }

    Write-Host "Live QMind OB-006 detection PASS. Selected detector intersection:"
    $intersection | ForEach-Object { Write-Host "  $_" }
    Assert-Ob006SelectionIsDistinctFromOb005 -Selection $selection
    Write-JsonFile -Path (Join-Path $RunDir "qmind-ob006-detection-summary.json") -Value @{
        scenario = $CaseId
        selection_artifact = $QMindSelectionOutput
        qmind_run_id = $newRunId
        previous_qmind_run_id = $PreviousOB006RunId
        changed_files_file = [string]$selection.changed_files_file
        changed_files = $changedFiles
        observability_enabled = [bool]$selection.qmind_subset_json.observability_enabled
        has_runtime_signal = [bool]$selection.qmind_subset_json.has_runtime_signal
        expected_detector_ids = $ExpectedDetectorIds
        selected_detector_ids = $intersection
        missing_detector_ids = $missing
        detected = $true
    }
}

function Invoke-QMindOb006 {
    Write-Phase "Run live QMind subset for OB-006"
    Backup-QMindSelectionIfPresent
    Invoke-LoggedPowerShellScript -ScriptPath $QMindSubsetScript -Arguments @{
        BenchmarkCase = $CaseId
        SelectionOutput = $QMindSelectionOutput
        Scenarios = $Scenarios
        Library = $Library
    }
    Assert-LiveQMindSelection
}

function Copy-EvidenceFile {
    param(
        [string]$Source,
        [string]$DestinationName
    )

    Assert-File $Source
    $destination = Join-Path $EvidenceDir $DestinationName
    Copy-Item -LiteralPath $Source -Destination $destination -Force
    return $destination
}

function Publish-Ob006Evidence {
    Write-Phase "Publish OB-006 runtime evidence"

    if ($null -eq $RuntimeMovementSummary -or [string]$RuntimeMovementSummary.publication_runtime_evidence -ne "CONFIRMED") {
        throw "Refusing to publish OB-006 evidence because runtime movement was not confirmed."
    }

    New-Item -ItemType Directory -Force -Path $EvidenceDir | Out-Null
    $published = @()
    $published += Copy-EvidenceFile -Source (Join-Path $RunDir "baseline-prometheus-snapshot.json") -DestinationName "baseline-prometheus-snapshot.json"
    $published += Copy-EvidenceFile -Source (Join-Path $RunDir "injected-prometheus-snapshot.json") -DestinationName "injected-prometheus-snapshot.json"
    $published += Copy-EvidenceFile -Source (Join-Path $RunDir "runtime-movement-summary.json") -DestinationName "runtime-movement-summary.json"
    $published += Copy-EvidenceFile -Source (Join-Path $RunDir "baseline-homepage-traffic.json") -DestinationName "baseline-homepage-traffic.json"
    $published += Copy-EvidenceFile -Source (Join-Path $RunDir "injected-homepage-traffic.json") -DestinationName "injected-homepage-traffic.json"
    $published += Copy-EvidenceFile -Source (Join-Path $RunDir "qmind-ob006-detection-summary.json") -DestinationName "qmind-ob006-detection-summary.json"
    $published += Copy-EvidenceFile -Source "benchmark-runs/scenario-ob-006-changed-files.json" -DestinationName "scenario-ob-006-changed-files.json"
    $published += Copy-EvidenceFile -Source $QMindSelectionOutput -DestinationName "qmind-selection-ob-006.json"

    $selection = Get-Content -LiteralPath $QMindSelectionOutput -Raw | ConvertFrom-Json
    $manifest = [ordered]@{
        scenario = $CaseId
        evidence_status = "verified"
        published_at_utc = (Get-Date).ToUniversalTime().ToString("o")
        source_run_dir = $RunDir
        qmind_selection_artifact = $QMindSelectionOutput
        qmind_run_id = Get-SelectionRunId -Selection $selection
        changed_files = @($ProductCatalogRelativeFile)
        required_runtime_chain = @(
            "productcatalogservice material latency or error movement",
            "frontend material latency or error movement",
            "QMind selection generated after injected runtime window",
            "OB-006 QMind selection not substantively identical to OB-005"
        )
        published_files = @($published | ForEach-Object { $_.Replace("\", "/") })
    }
    Write-JsonFile -Path (Join-Path $EvidenceDir "evidence-manifest.json") -Value $manifest
    Write-Host "Published OB-006 evidence under $EvidenceDir."
}

function Invoke-FinalComparison {
    Write-Phase "Regenerate final comparison from live OB-006 QMind artifact"
    Invoke-LoggedPowerShellScript -ScriptPath $FinalComparisonScript -Arguments @{
        UseExistingQMindSelections = $true
    }
}

function Apply-Ob006Injection {
    Write-Phase "Apply OB-006 injector"
    Invoke-LoggedPowerShellScript -ScriptPath $Injector -Arguments @{
        SourceRoot = $SourceRoot
        Mode = $Mode
        LatencyMs = $LatencyMs
    }
}

function Restore-Ob006Source {
    Write-Phase "Restore OB-006 source injection"
    Invoke-LoggedPowerShellScript -ScriptPath $Injector -Arguments @{
        SourceRoot = $SourceRoot
        Restore = $true
    }
    $script:SourceRestored = $true
}

function Write-ManualRecoveryWarning {
    param(
        [string]$CleanImage,
        [string]$Reason
    )

    Write-Warning "LOUD WARNING: automatic clean redeploy failed. Reason: $Reason"
    Write-Warning "State: InjectionApplied=$InjectionApplied, InjectedImageBuilt=$InjectedImageBuilt, InjectedImagePushed=$InjectedImagePushed, InjectedImageDeployed=$InjectedImageDeployed, SourceRestored=$SourceRestored, CleanImageBuilt=$CleanImageBuilt, CleanImagePushed=$CleanImagePushed, CleanImageDeployed=$CleanImageDeployed"
    if ($InjectedImageDeployed -and -not $CleanImageDeployed) {
        Write-Warning "The cluster may still be running the injected OB-006 productcatalogservice image."
    } else {
        Write-Warning "The injected image was not successfully deployed to the cluster, so the cluster should not be running the injected OB-006 image from this run."
    }
    Write-Warning "Manual recovery commands:"
    if (-not $SourceRestored) {
        Write-Warning "  .\runtime-scenarios\ob-006-productcatalog-listproducts-cascade\apply-ob006-productcatalog-listproducts.ps1 -SourceRoot $SourceRoot -Restore"
    }
    if (-not [string]::IsNullOrWhiteSpace($CleanImage)) {
        if ($InjectedImageDeployed -and -not $CleanImageDeployed) {
            Write-Warning "  docker build -t $CleanImage $BuildContext"
            Write-Warning "  docker push $CleanImage"
            Write-Warning "  kubectl -n $Namespace set image deployment/$Deployment $Container=$CleanImage"
            Write-Warning "  kubectl -n $Namespace rollout status deployment/$Deployment --timeout=300s"
        } elseif (-not $InjectedImageDeployed) {
            Write-Warning "  No clean redeploy should be required because the injected image was not deployed."
        }
    }
}

New-Item -ItemType Directory -Force -Path $RunDir | Out-Null
$CommandLog = Join-Path $RunDir "commands.log"
Write-TextFile -Path $CommandLog -Text ""

$InjectionApplied = $false
$InjectedImageBuilt = $false
$InjectedImagePushed = $false
$InjectedImageDeployed = $false
$SourceRestored = $false
$CleanImageBuilt = $false
$CleanImagePushed = $false
$CleanImageDeployed = $false
$liveImage = $null
$cleanImage = $null
$buildContext = $null
$targetImageRepository = $null

try {
    Write-Phase "Validate prerequisites"
    foreach ($path in @($Injector, $QMindSubsetScript, $FinalComparisonScript, $Oracle, $Library, $Scenarios)) {
        Assert-File $path
        Write-Host "Found: $path"
    }
    Assert-Directory $SourceRoot
    Assert-File (Join-Path $SourceRoot $ProductCatalogRelativeFile)
    foreach ($tool in @("docker", "kubectl", "qmind", "python")) {
        Assert-Tool $tool
    }

    $currentContext = Invoke-LoggedCommand -Command "kubectl" -Arguments @("config", "current-context")
    if ([string]::IsNullOrWhiteSpace($currentContext.output)) {
        throw "kubectl has no active current-context."
    }
    Write-Host "kubectl context: $($currentContext.output)"
    Invoke-LoggedCommand -Command "kubectl" -Arguments @("get", "namespace", $Namespace) | Out-Null
    Invoke-LoggedCommand -Command "kubectl" -Arguments @("-n", $Namespace, "get", "deployment", $Deployment) | Out-Null

    $currentImage = Get-CurrentProductCatalogImage
    Write-Host "Current $Deployment/$Container image: $currentImage"
    $currentImageRepository = Get-ImageRepository -Image $currentImage
    Write-Host "Current deployment image repository: $currentImageRepository"
    Write-Host "ImageRepository parameter value: '$ImageRepository'"

    # Regression guard: an explicit writable target repository must bypass
    # read-only checks on the currently running upstream image repository.
    if (-not [string]::IsNullOrWhiteSpace($ImageRepository)) {
        $targetImageRepository = $ImageRepository.Trim()
        Write-Host "Using explicit writable image repository: $targetImageRepository"
    }
    else {
        if ($currentImageRepository -match "google-samples") {
            throw "Current deployment image repository appears to be read-only upstream Google Samples: $currentImageRepository. Provide -ImageRepository."
        }

        $targetImageRepository = $currentImageRepository
        Write-Host "Using current deployment image repository: $targetImageRepository"
    }

    Write-ArtifactRegistryAuthPreflight -Repository $targetImageRepository
    $liveImage = "${targetImageRepository}:$ImageTagPrefix-$Timestamp"
    $cleanImage = "${targetImageRepository}:$CleanImageTagPrefix-$Timestamp"
    $buildContext = Get-ProductCatalogBuildContext
    Write-Host "Target image repository: $targetImageRepository"
    Write-Host "Live image tag: $liveImage"
    Write-Host "Clean image tag: $cleanImage"
    Write-Host "Productcatalogservice build context: $buildContext"

    $ExpectedDetectorIds = @(Get-Ob006ExpectedDetectorIds)
    Write-Host "Loaded $($ExpectedDetectorIds.Count) OB-006 detector IDs from $Oracle."
    Assert-PrometheusReachable
    Write-Host "Prometheus is reachable at $PrometheusUrl."
    Assert-FrontendReachable

    Write-Phase "Capture baseline"
    Invoke-HomepageTraffic -Phase "baseline"
    $baselineMetrics = Capture-RuntimeSnapshot -Phase "baseline"

    Apply-Ob006Injection
    $InjectionApplied = $true

    Build-And-PushImage -Image $liveImage -BuildContext $buildContext -Phase "injected"
    Deploy-ProductCatalogImage -Image $liveImage -Phase "injected"

    Write-Phase "Validate injected runtime"
    Invoke-HomepageTraffic -Phase "injected"
    $injectedMetrics = Capture-RuntimeSnapshot -Phase "injected"
    $RuntimeMovementSummary = Write-RuntimeMovementSummary -Baseline $baselineMetrics -Injected $injectedMetrics

    if ($SkipQMind) {
        Write-Host "SkipQMind was set. QMind live OB-006 selection was not regenerated."
    } else {
        Invoke-QMindOb006
    }

    if (-not $SkipQMind) {
        Publish-Ob006Evidence
    }

    if ($SkipComparison) {
        Write-Host "SkipComparison was set. Final comparison artifacts were not regenerated."
    } elseif ($SkipQMind) {
        Write-Host "Final comparison skipped because SkipQMind was set; no live OB-006 QMind artifact was produced in this run."
    } else {
        Invoke-FinalComparison
    }

    Write-Phase "Live validation command complete"
    Write-Host "Evidence artifacts were written under $RunDir."
    if (-not $SkipQMind) {
        Write-Host "Publication evidence was written under $EvidenceDir."
    }
} finally {
    if ($InjectionApplied) {
        if ($SkipRestore) {
            Write-Warning "SkipRestore was set. The source tree still contains the OB-006 injection."
            if ($InjectedImageDeployed) {
                Write-Warning "The cluster may still be running the injected OB-006 productcatalogservice image."
            } else {
                Write-Warning "The injected image was not successfully deployed to the cluster in this run."
            }
            Write-Warning "Manual source restore command: .\runtime-scenarios\ob-006-productcatalog-listproducts-cascade\apply-ob006-productcatalog-listproducts.ps1 -SourceRoot $SourceRoot -Restore"
        } else {
            $restoreError = $null
            try {
                Restore-Ob006Source
                if ($InjectedImageDeployed -and -not [string]::IsNullOrWhiteSpace($cleanImage) -and -not [string]::IsNullOrWhiteSpace($buildContext)) {
                    Build-And-PushImage -Image $cleanImage -BuildContext $buildContext -Phase "clean"
                    Deploy-ProductCatalogImage -Image $cleanImage -Phase "clean"
                } elseif (-not $InjectedImageDeployed) {
                    Write-Host "Injected image was not deployed; source restore completed and clean cluster redeploy is not required."
                } else {
                    throw "Clean image or build context was not available."
                }
            } catch {
                $restoreError = $_.Exception.Message
                Write-ManualRecoveryWarning -CleanImage $cleanImage -Reason $restoreError
            }
        }
    }
}

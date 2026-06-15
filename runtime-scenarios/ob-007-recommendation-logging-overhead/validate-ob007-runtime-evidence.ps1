param(
    [string]$FrontendUrl = "http://34.185.198.67",
    [string]$ProductPath = "/product/OLJCESPC7Z",
    [string]$PrometheusUrl = "http://localhost:19090",
    [string]$PrometheusNamespace = "default",
    [string]$PrometheusWindow = "2m",
    [string]$SourceRoot = "microservices-demo",
    [string]$DeclaredChangedFile = "src/adservice/src/main/java/hipstershop/AdService.java",
    [string]$RecommendationServerFile = "src/recommendationservice/recommendation_server.py",
    [string]$EvidenceDir = "benchmark-results/runtime-evidence/ob-007",
    [string]$QMindSelectionDir = "benchmark-results/qmind-selections",
    [string]$BenchmarkRunDir = "benchmark-runs",
    [string]$PlaywrightDir = "qmind-test-harness/playwright",
    [string]$EnvFile = ".env",
    [string]$Deployment = "recommendationservice",
    [string]$Container = "server",
    [string]$ImageRepository,
    [string]$ImageTagPrefix = "ob007-live",
    [int]$RolloutTimeoutSeconds = 300,
    [ValidateRange(1, 300)]
    [int]$LatencyMs = 200,
    [int]$TrafficProbes = 20,
    [int]$WaitAfterInjectionSeconds = 150,
    [double]$RecommendationLatencyMinDeltaSeconds = 0.05,
    [double]$RecommendationLatencyMinRatio = 1.5,
    [switch]$SkipDeploy,
    [switch]$RestoreOnly,
    [switch]$DryRun
)

$ErrorActionPreference = "Stop"

function Write-Step {
    param([string]$Message)
    Write-Host "`n=== $Message ===" -ForegroundColor Cyan
}

function Write-Utf8NoBom {
    param([string]$Path, [string]$Text)
    $resolved = $ExecutionContext.SessionState.Path.GetUnresolvedProviderPathFromPSPath($Path)
    [System.IO.File]::WriteAllText($resolved, $Text, [System.Text.UTF8Encoding]::new($false))
}

function Write-Json {
    param([string]$Path, [object]$Data)
    $json = ConvertTo-Json -InputObject $Data -Depth 20 -Compress:$false
    New-Item -ItemType Directory -Force -Path (Split-Path -Parent $Path) | Out-Null
    Write-Utf8NoBom -Path $Path -Text ($json + [Environment]::NewLine)
    Write-Host "  Written: $Path"
}

function Format-Command {
    param([string]$Command, [string[]]$Arguments)

    $parts = @($Command) + @($Arguments | ForEach-Object {
        Format-CommandArgument -Argument $_
    })
    return ($parts -join " ")
}

function Format-CommandArgument {
    param([string]$Argument)

    if ($Argument -match "\s|`"|'") {
        return '"' + ($Argument -replace '"', '\"') + '"'
    }
    return $Argument
}

function Format-CommandArguments {
    param([string[]]$Arguments)

    return (@($Arguments | ForEach-Object { Format-CommandArgument -Argument $_ }) -join " ")
}

function Invoke-NativeCommandExitCodeOnly {
    param([string]$Command, [string[]]$Arguments)

    $commandLine = Format-Command -Command $Command -Arguments $Arguments
    Write-Host "  $commandLine"

    $process = New-Object System.Diagnostics.Process
    $process.StartInfo = New-Object System.Diagnostics.ProcessStartInfo
    $process.StartInfo.FileName = $Command
    $process.StartInfo.Arguments = Format-CommandArguments -Arguments $Arguments
    $process.StartInfo.UseShellExecute = $false
    $process.StartInfo.RedirectStandardOutput = $true
    $process.StartInfo.RedirectStandardError = $true
    $process.StartInfo.CreateNoWindow = $true

    [void]$process.Start()
    $stdoutTask = $process.StandardOutput.ReadToEndAsync()
    $stderrTask = $process.StandardError.ReadToEndAsync()
    $process.WaitForExit()

    $capturedOutput = (($stdoutTask.Result, $stderrTask.Result) -join "").Trim()
    if (-not [string]::IsNullOrWhiteSpace($capturedOutput)) {
        $capturedOutput -split "`r?`n" | ForEach-Object { Write-Host "  $_" }
    }

    if ($process.ExitCode -ne 0) {
        throw "Command failed with exit code $($process.ExitCode): $commandLine`n$capturedOutput"
    }
    return $capturedOutput
}

function Assert-Tool {
    param([string]$Name)

    if (-not (Get-Command $Name -ErrorAction SilentlyContinue)) {
        throw "Missing required tool on PATH: $Name"
    }
    Write-Host "  ${Name}: available"
}

function Assert-DeclaredChangedFileGuard {
    $declaredFileTarget = Join-Path $SourceRoot $DeclaredChangedFile
    if (-not (Test-Path -LiteralPath $declaredFileTarget -PathType Leaf)) {
        throw "Cannot find declared changed file at $declaredFileTarget. Run from the benchmark repo root."
    }

    $declaredFileSource = Get-Content -LiteralPath $declaredFileTarget -Raw
    if ($declaredFileSource -match "(?i)OB-007") {
        throw "Declared changed file guard failed. $declaredFileTarget must not contain OB-007 injection markers."
    }
}

function Assert-RecommendationServerRestored {
    $serverTarget = Join-Path $SourceRoot $RecommendationServerFile
    if (-not (Test-Path -LiteralPath $serverTarget -PathType Leaf)) {
        throw "Cannot find recommendation_server.py at $serverTarget. Run from the benchmark repo root."
    }

    $serverSource = Get-Content -LiteralPath $serverTarget -Raw
    if ($serverSource -match "\[OB-007\] Injecting recommendationservice (ListRecommendations latency|gRPC unavailable|degraded recommendation response)") {
        throw "OB-007 injection remains in $serverTarget after restore."
    }
}

function Get-ImageRepository {
    param([string]$Image)

    if ($Image -match "@sha256:") {
        throw "Current deployment image uses a digest reference. Provide -ImageRepository for a writable tagged repository."
    }

    $lastSlash = $Image.LastIndexOf("/")
    $lastColon = $Image.LastIndexOf(":")
    if ($lastColon -gt $lastSlash) {
        return $Image.Substring(0, $lastColon)
    }
    return $Image
}

function Get-RecommendationBuildContext {
    $context = Join-Path $SourceRoot "src/recommendationservice"
    $dockerfile = Join-Path $context "Dockerfile"
    if (-not (Test-Path -LiteralPath $dockerfile -PathType Leaf)) {
        throw "Could not detect recommendationservice Docker build context. Expected Dockerfile at: $dockerfile"
    }
    return $context
}

function Get-DeploymentImage {
    $jsonPath = "{.spec.template.spec.containers[?(@.name=='$Container')].image}"
    $image = Invoke-NativeCommandExitCodeOnly -Command "kubectl" -Arguments @("-n", $PrometheusNamespace, "get", "deployment", $Deployment, "-o", "jsonpath=$jsonPath")
    if ([string]::IsNullOrWhiteSpace($image)) {
        throw "Could not derive image for container '$Container' in deployment '$Deployment'."
    }
    return $image.Trim()
}

function Get-RecommendationPodName {
    $podName = Invoke-NativeCommandExitCodeOnly -Command "kubectl" -Arguments @("-n", $PrometheusNamespace, "get", "pods", "-l", "app=$Deployment", "-o", "jsonpath={.items[0].metadata.name}")
    if ([string]::IsNullOrWhiteSpace($podName)) {
        throw "Could not find a running $Deployment pod. Ensure the rollout completed and the cluster is accessible."
    }
    return $podName.Trim()
}

function Deploy-RecommendationImage {
    param([string]$Image, [string]$Phase)

    Write-Host "  Deploying $Phase recommendationservice image: $Image"
    Invoke-NativeCommandExitCodeOnly -Command "kubectl" -Arguments @("-n", $PrometheusNamespace, "set", "image", "deployment/$Deployment", "$Container=$Image") | Out-Null
    if ($Phase -eq "injected") {
        $script:injectedImageDeployed = $true
    }
    Invoke-NativeCommandExitCodeOnly -Command "kubectl" -Arguments @("-n", $PrometheusNamespace, "rollout", "status", "deployment/$Deployment", "--timeout=${RolloutTimeoutSeconds}s") | Out-Null
    $podName = Get-RecommendationPodName
    Write-Host "  Active $Deployment pod after $Phase rollout: $podName"
    return $podName
}

function Restore-Ob007SourceAndDeployment {
    param([string]$Reason)

    Write-Step "Restore OB-007 injection"
    if ($Reason) {
        Write-Host "  Reason: $Reason"
    }
    & .\runtime-scenarios\ob-007-recommendation-logging-overhead\apply-ob007-recommendation-logging-overhead.ps1 `
        -SourceRoot $SourceRoot `
        -LoggerFile $LoggerFile `
        -RecommendationServerFile $RecommendationServerFile `
        -Restore
    Assert-DeclaredChangedFileGuard
    Assert-RecommendationServerRestored
    if (-not $SkipDeploy -and $injectedImageDeployed -and -not [string]::IsNullOrWhiteSpace($originalImage)) {
        Deploy-RecommendationImage -Image $originalImage -Phase "restore" | Out-Null
        Write-Host "  recommendationservice image restored to: $originalImage"
    }
    elseif (-not $SkipDeploy -and -not $injectedImageDeployed) {
        Write-Host "  Injected image was not deployed; source restore completed and deployment image restore is not required."
    }
    $script:restoreCompleted = $true
}

function Invoke-PrometheusQuery {
    param([string]$Query, [string]$Key, [string]$Name)
    $encoded = [Uri]::EscapeDataString($Query)
    $uri = "$PrometheusUrl/api/v1/query?query=$encoded"
    try {
        $response = Invoke-RestMethod -Uri $uri -Method Get -TimeoutSec 30
        if ($response.status -ne "success") {
            Write-Warning "Prometheus query returned non-success for ${Key}: $($response.status)"
            return @{ key = $Key; name = $Name; promql = $Query; no_data = $true; value = $null; result = @() }
        }
        $results = @($response.data.result)
        if ($results.Count -eq 0) {
            return @{ key = $Key; name = $Name; promql = $Query; no_data = $true; value = $null; result = @() }
        }
        $rawValue = [string]$results[0].value[1]
        $floatValue = if ($rawValue -match "^\d") { [double]$rawValue } else { $null }
        return @{
            key = $Key; name = $Name; promql = $Query; no_data = $false
            value = $floatValue; result = $results
        }
    }
    catch {
        Write-Warning "Prometheus query failed for ${Key}: $_"
        return @{ key = $Key; name = $Name; promql = $Query; no_data = $true; value = $null; result = @() }
    }
}

function Get-SnapshotMetric {
    param([object]$Snapshot, [string]$Key)

    return @($Snapshot.metrics | Where-Object { $_.key -eq $Key })[0]
}

function Get-MetricValueOrZero {
    param([object]$Metric)

    if ($Metric -and -not $Metric.no_data -and $null -ne $Metric.value) {
        return [double]$Metric.value
    }
    return 0.0
}

function Get-ObjectPropertyValue {
    param([object]$Object, [string]$Name)

    if ($null -eq $Object) { return $null }
    $property = $Object.PSObject.Properties[$Name]
    if ($null -eq $property) { return $null }
    return $property.Value
}

function Compare-ErrorSignal {
    param(
        [string]$Key,
        [object]$BaselineMetric,
        [object]$InjectedMetric,
        [double]$MinDelta,
        [double]$MinInjected,
        [string]$Note
    )

    $baseline = Get-MetricValueOrZero -Metric $BaselineMetric
    $injected = Get-MetricValueOrZero -Metric $InjectedMetric
    $delta = $injected - $baseline
    return [ordered]@{
        key = $Key
        baseline = $baseline
        injected = $injected
        delta = $delta
        min_delta = $MinDelta
        min_injected = $MinInjected
        has_baseline_data = [bool]($BaselineMetric -and -not $BaselineMetric.no_data)
        has_injected_data = [bool]($InjectedMetric -and -not $InjectedMetric.no_data)
        passed = ($injected -ge $MinInjected -and $delta -ge $MinDelta)
        note = $Note
    }
}

function Get-PrometheusSnapshot {
    param([string]$Phase)

    $ns = $PrometheusNamespace
    $w = $PrometheusWindow

    $metrics = @(
        Invoke-PrometheusQuery `
            "histogram_quantile(0.95, sum by (deployment, le) (rate(inbound_http_response_duration_seconds_bucket{namespace=`"$ns`",deployment=`"recommendationservice`"}[$w])))" `
            "recommendationservice.latency_p95" "recommendationservice latency p95"
        Invoke-PrometheusQuery `
            "1 - (sum by (deployment) (rate(inbound_http_statuses_total{namespace=`"$ns`",deployment=`"recommendationservice`",status=~`"2..|3..`"}[$w])) / sum by (deployment) (rate(inbound_http_statuses_total{namespace=`"$ns`",deployment=`"recommendationservice`"}[$w])))" `
            "recommendationservice.error_rate" "recommendationservice error rate"
        Invoke-PrometheusQuery `
            "sum by (deployment) (rate(inbound_http_statuses_total{namespace=`"$ns`",deployment=`"recommendationservice`"}[$w]))" `
            "recommendationservice.request_rate" "recommendationservice request rate"
        Invoke-PrometheusQuery `
            "sum(rate(response_total{dst_namespace=`"$ns`",dst_deployment=`"recommendationservice`",direction=`"inbound`",classification=`"failure`"}[$w]))" `
            "recommendationservice.grpc_failure_rate" "recommendationservice gRPC failure response rate"
        Invoke-PrometheusQuery `
            "sum(rate(response_total{dst_namespace=`"$ns`",dst_deployment=`"recommendationservice`",direction=`"inbound`",grpc_status!~`"OK|`"}[$w]))" `
            "recommendationservice.grpc_non_ok_rate" "recommendationservice gRPC non-OK response rate"
        Invoke-PrometheusQuery `
            "sum(rate(response_total{dst_namespace=`"$ns`",dst_deployment=`"recommendationservice`",direction=`"inbound`"}[$w]))" `
            "recommendationservice.grpc_request_rate" "recommendationservice gRPC response rate"
        Invoke-PrometheusQuery `
            "histogram_quantile(0.95, sum by (deployment, le) (rate(inbound_http_response_duration_seconds_bucket{namespace=`"$ns`",deployment=`"frontend`"}[$w])))" `
            "frontend.latency_p95" "frontend latency p95"
        Invoke-PrometheusQuery `
            "1 - (sum by (deployment) (rate(inbound_http_statuses_total{namespace=`"$ns`",deployment=`"frontend`",status=~`"2..|3..`"}[$w])) / sum by (deployment) (rate(inbound_http_statuses_total{namespace=`"$ns`",deployment=`"frontend`"}[$w])))" `
            "frontend.error_rate" "frontend error rate"
        Invoke-PrometheusQuery `
            "sum by (deployment) (rate(inbound_http_statuses_total{namespace=`"$ns`",deployment=`"frontend`"}[$w]))" `
            "frontend.request_rate" "frontend request rate"
    )

    return [ordered]@{
        prometheus_window = $PrometheusWindow
        namespace = $PrometheusNamespace
        prometheus_url = $PrometheusUrl
        scenario = "OB-007"
        metrics = $metrics
        phase = $Phase
        captured_at_utc = ([datetime]::UtcNow).ToString("o")
    }
}

function Invoke-HttpProbes {
    param([string]$Url, [string]$Phase)

    $events = @()
    for ($i = 1; $i -le $TrafficProbes; $i++) {
        $start = [datetime]::UtcNow
        try {
            $response = Invoke-WebRequest -Uri $Url -Method Get -TimeoutSec 45 -UseBasicParsing
            $elapsed = ([datetime]::UtcNow - $start).TotalMilliseconds
            $events += @{ ok = $true; elapsed_ms = [int]$elapsed; status_code = [int]$response.StatusCode; index = $i }
        }
        catch {
            $elapsed = ([datetime]::UtcNow - $start).TotalMilliseconds
            $statusCode = 0
            if ($_.Exception.Response) { $statusCode = [int]$_.Exception.Response.StatusCode }
            $events += @{ ok = $false; elapsed_ms = [int]$elapsed; status_code = $statusCode; index = $i; error = [string]$_.Exception.Message }
        }
    }

    return [ordered]@{
        scenario = "OB-007"
        events = $events
        phase = $Phase
        probe_url = $Url
        captured_at_utc = ([datetime]::UtcNow).ToString("o")
    }
}

function Compare-MetricMovement {
    param(
        [string]$Key, [string]$Label,
        [double]$Baseline, [double]$Injected,
        [double]$MinDelta, [double]$MinRatio,
        [bool]$RequiresDelta = $true, [bool]$RequiresRatio = $true,
        [string]$Note = $null
    )

    $delta = $Injected - $Baseline
    $ratio = if ($Baseline -gt 0) { $Injected / $Baseline } else { $null }
    $deltaPassed = $RequiresDelta -and $delta -ge $MinDelta
    $ratioPassed = $RequiresRatio -and ($null -ne $ratio) -and $ratio -ge $MinRatio

    $result = [ordered]@{
        key = $Key
        baseline = $Baseline
        injected = $Injected
        delta = $delta
        min_delta = $MinDelta
        has_data = $true
        passed = $deltaPassed
    }
    if ($RequiresRatio) {
        $result.ratio = $ratio
        $result.min_ratio = $MinRatio
        $result.delta_passed = $deltaPassed
        $result.ratio_passed = $ratioPassed
        $result.passed = $deltaPassed -and $ratioPassed
    }
    if ($Note) { $result.note = $Note }
    return $result
}

# --- RESTORE-ONLY ------------------------------------------------------------
if ($RestoreOnly) {
    Write-Step "Restoring OB-007 injection"
    & .\runtime-scenarios\ob-007-recommendation-logging-overhead\apply-ob007-recommendation-logging-overhead.ps1 `
        -SourceRoot $SourceRoot `
        -DeclaredChangedFile $DeclaredChangedFile `
        -RecommendationServerFile $RecommendationServerFile `
        -Restore
    Assert-DeclaredChangedFileGuard
    Assert-RecommendationServerRestored
    if (-not $SkipDeploy) {
        Write-Host "Restarting recommendationservice deployment..."
        Invoke-NativeCommandExitCodeOnly -Command "kubectl" -Arguments @("rollout", "restart", "deployment/recommendationservice", "-n", $PrometheusNamespace) | Out-Null
        Invoke-NativeCommandExitCodeOnly -Command "kubectl" -Arguments @("rollout", "status", "deployment/recommendationservice", "-n", $PrometheusNamespace, "--timeout=120s") | Out-Null
    }
    Write-Host "OB-007 restore complete."
    exit 0
}

# --- PRE-FLIGHT --------------------------------------------------------------
Write-Step "Pre-flight checks"

Assert-DeclaredChangedFileGuard
if (-not (Test-Path -LiteralPath "$SourceRoot/$RecommendationServerFile" -PathType Leaf)) {
    throw "Cannot find recommendation_server.py at $SourceRoot/$RecommendationServerFile. Run from the benchmark repo root."
}
if (-not (Test-Path -LiteralPath $PlaywrightDir -PathType Container)) {
    throw "Cannot find Playwright test harness at $PlaywrightDir."
}
if (-not (Test-Path -LiteralPath $EnvFile -PathType Leaf)) {
    throw "Missing .env file at $EnvFile. Required for QMind API configuration."
}

if (-not $SkipDeploy) {
    Assert-Tool "kubectl"
    Assert-Tool "docker"
}

Write-Host "  FrontendUrl: $FrontendUrl"
Write-Host "  ProductPath: $ProductPath"
Write-Host "  PrometheusUrl: $PrometheusUrl"
Write-Host "  EvidenceDir: $EvidenceDir"

New-Item -ItemType Directory -Force -Path $EvidenceDir | Out-Null
$productUrl = $FrontendUrl.TrimEnd('/') + $ProductPath
$timestamp = Get-Date -Format "yyyyMMdd-HHmmss"
$originalImage = $null
$targetImageRepository = $null
$injectedImage = $null
$buildContext = $null
$injectedImageDeployed = $false
$sourceInjectionApplied = $false
$restoreCompleted = $false

if (-not $SkipDeploy -and -not $DryRun) {
    $originalImage = Get-DeploymentImage
    $currentImageRepository = Get-ImageRepository -Image $originalImage
    if (-not [string]::IsNullOrWhiteSpace($ImageRepository)) {
        $targetImageRepository = $ImageRepository.Trim()
    }
    else {
        if ($currentImageRepository -match "google-samples") {
            throw "Current deployment image repository appears to be read-only upstream Google Samples: $currentImageRepository. Provide -ImageRepository."
        }
        $targetImageRepository = $currentImageRepository
    }
    $injectedImage = "${targetImageRepository}:$ImageTagPrefix-$timestamp"
    $buildContext = Get-RecommendationBuildContext
    Write-Host "  Current $Deployment/$Container image: $originalImage"
    Write-Host "  Target image repository: $targetImageRepository"
    Write-Host "  OB-007 injected image: $injectedImage"
    Write-Host "  recommendationservice build context: $buildContext"
}
elseif (-not $SkipDeploy) {
    $targetImageRepository = if ([string]::IsNullOrWhiteSpace($ImageRepository)) { "<derived-from-current-deployment-image>" } else { $ImageRepository.Trim() }
    $injectedImage = "${targetImageRepository}:$ImageTagPrefix-$timestamp"
    $buildContext = Get-RecommendationBuildContext
}

try {
# --- STEP 1: BASELINE PROMETHEUS SNAPSHOT ------------------------------------
Write-Step "Step 1: Baseline Prometheus snapshot"
$baselineSnapshot = Get-PrometheusSnapshot -Phase "baseline"
Write-Json "$EvidenceDir/baseline-prometheus-snapshot.json" $baselineSnapshot
Write-Host "  Captured $($baselineSnapshot.metrics.Count) baseline metrics."

$baselineRecSvc = Get-SnapshotMetric -Snapshot $baselineSnapshot -Key "recommendationservice.latency_p95"
$baselineRecSvcErrorRate = Get-SnapshotMetric -Snapshot $baselineSnapshot -Key "recommendationservice.error_rate"
$baselineRecSvcGrpcFailureRate = Get-SnapshotMetric -Snapshot $baselineSnapshot -Key "recommendationservice.grpc_failure_rate"
$baselineRecSvcGrpcNonOkRate = Get-SnapshotMetric -Snapshot $baselineSnapshot -Key "recommendationservice.grpc_non_ok_rate"
$baselineFrontendErrRate = Get-SnapshotMetric -Snapshot $baselineSnapshot -Key "frontend.error_rate"

# --- STEP 2: BASELINE PRODUCT DETAIL TRAFFIC PROBE ---------------------------
Write-Step "Step 2: Baseline product detail traffic probe"
$baselineTraffic = Invoke-HttpProbes -Url $productUrl -Phase "baseline"
Write-Json "$EvidenceDir/baseline-product-detail-traffic.json" $baselineTraffic
$baselineOkCount = ($baselineTraffic.events | Where-Object { $_.ok }).Count
Write-Host "  $baselineOkCount / $TrafficProbes probes OK at baseline."

# --- STEP 3: APPLY OB-007 INJECTION -----------------------------------------
Write-Step "Step 3: Apply OB-007 injection"
if ($SkipDeploy) {
    Write-Host "  -SkipDeploy set. Skipping local source injection; assuming recommendationservice is already running the OB-007 ListRecommendations latency injection."
}
elseif ($DryRun) {
    Write-Host "  [DRY RUN] Would inject OB-007 into $SourceRoot/$RecommendationServerFile"
}
else {
    & .\runtime-scenarios\ob-007-recommendation-logging-overhead\apply-ob007-recommendation-logging-overhead.ps1 `
        -SourceRoot $SourceRoot `
        -DeclaredChangedFile $DeclaredChangedFile `
        -RecommendationServerFile $RecommendationServerFile `
        -LatencyMs $LatencyMs
    $sourceInjectionApplied = $true
}

# --- STEP 4: DEPLOY INJECTED CODE TO CLUSTER ---------------------------------
Write-Step "Step 4: Deploy injected recommendationservice to cluster"
$serverTarget = Join-Path $SourceRoot $RecommendationServerFile
if ($SkipDeploy) {
    Write-Host "  -SkipDeploy set. No local source injection, image build, push, or rollout will be performed."
    Write-Host "  Expected runtime behavior: $serverTarget sleeps briefly in ListRecommendations and returns empty recommendations."
    Write-Host "  Press ENTER when the injected pod is Running and Ready..."
    if (-not $DryRun) { Read-Host | Out-Null }
}
elseif ($DryRun) {
    Write-Host "  [DRY RUN] Would build, push, and deploy injected recommendationservice image"
    Write-Host "  docker build -t $injectedImage $buildContext"
    Write-Host "  docker push $injectedImage"
    Write-Host "  kubectl -n $PrometheusNamespace set image deployment/$Deployment $Container=$injectedImage"
    Write-Host "  kubectl -n $PrometheusNamespace rollout status deployment/$Deployment --timeout=${RolloutTimeoutSeconds}s"
}
else {
    Invoke-NativeCommandExitCodeOnly -Command "docker" -Arguments @("build", "-t", $injectedImage, $buildContext) | Out-Null
    Invoke-NativeCommandExitCodeOnly -Command "docker" -Arguments @("push", $injectedImage) | Out-Null
    $newPodName = Deploy-RecommendationImage -Image $injectedImage -Phase "injected"
    $injectedImageDeployed = $true
    Write-Host "  Injected recommendationservice pod: $newPodName"
}

# --- STEP 5: WAIT FOR PROMETHEUS METRICS WINDOW -----------------------------
Write-Step "Step 5: Waiting $WaitAfterInjectionSeconds seconds for Prometheus metrics window"
if (-not $DryRun) {
    for ($i = $WaitAfterInjectionSeconds; $i -gt 0; $i -= 10) {
        Write-Host "  $i seconds remaining..."
        $sleepSeconds = if ($i -gt 10) { 10 } else { $i }
        Start-Sleep -Seconds $sleepSeconds
    }
}
else {
    Write-Host "  [DRY RUN] Skipping wait."
}

# --- STEP 6: INJECTED PROMETHEUS SNAPSHOT ------------------------------------
Write-Step "Step 6: Injected Prometheus snapshot"
$injectedSnapshot = Get-PrometheusSnapshot -Phase "injected"
Write-Json "$EvidenceDir/injected-prometheus-snapshot.json" $injectedSnapshot
Write-Host "  Captured $($injectedSnapshot.metrics.Count) injected metrics."

$injectedRecSvc = Get-SnapshotMetric -Snapshot $injectedSnapshot -Key "recommendationservice.latency_p95"
$injectedRecSvcErrorRate = Get-SnapshotMetric -Snapshot $injectedSnapshot -Key "recommendationservice.error_rate"
$injectedRecSvcGrpcFailureRate = Get-SnapshotMetric -Snapshot $injectedSnapshot -Key "recommendationservice.grpc_failure_rate"
$injectedRecSvcGrpcNonOkRate = Get-SnapshotMetric -Snapshot $injectedSnapshot -Key "recommendationservice.grpc_non_ok_rate"
$injectedFrontendErrRate = Get-SnapshotMetric -Snapshot $injectedSnapshot -Key "frontend.error_rate"

# --- STEP 7: INJECTED PRODUCT DETAIL TRAFFIC PROBE ---------------------------
Write-Step "Step 7: Injected product detail traffic probe"
$injectedTraffic = Invoke-HttpProbes -Url $productUrl -Phase "injected"
Write-Json "$EvidenceDir/injected-product-detail-traffic.json" $injectedTraffic
$injectedOkCount = ($injectedTraffic.events | Where-Object { $_.ok }).Count
Write-Host "  $injectedOkCount / $TrafficProbes probes OK after injection."

$gracefulDegradationConfirmed = $injectedOkCount -ge ($TrafficProbes * 0.8)
Write-Host "  Graceful degradation confirmed (>=80% 200s): $gracefulDegradationConfirmed"

# --- STEP 8: COMPUTE RUNTIME BEHAVIORAL SUMMARY ------------------------------
Write-Step "Step 8: Compute runtime behavioral summary"

$recSvcLatencyBaseline = if ($baselineRecSvc -and -not $baselineRecSvc.no_data) { [double]$baselineRecSvc.value } else { 0.0 }
$recSvcLatencyInjected = if ($injectedRecSvc -and -not $injectedRecSvc.no_data) { [double]$injectedRecSvc.value } else { 0.0 }
$frontendErrBaseline = if ($baselineFrontendErrRate -and -not $baselineFrontendErrRate.no_data) { [double]$baselineFrontendErrRate.value } else { 0.0 }
$frontendErrInjected = if ($injectedFrontendErrRate -and -not $injectedFrontendErrRate.no_data) { [double]$injectedFrontendErrRate.value } else { 0.0 }

$recSvcLatencySignal = Compare-MetricMovement `
    -Key "recommendationservice.latency_p95" -Label "recommendationservice latency p95" `
    -Baseline $recSvcLatencyBaseline -Injected $recSvcLatencyInjected `
    -MinDelta $RecommendationLatencyMinDeltaSeconds -MinRatio $RecommendationLatencyMinRatio
$recSvcLatencySignal.note = "Primary Prometheus signal for OB-007: small ListRecommendations-only latency increase without affecting health checks."

$recSvcHttpErrorSignal = Compare-ErrorSignal `
    -Key "recommendationservice.error_rate" `
    -BaselineMetric $baselineRecSvcErrorRate `
    -InjectedMetric $injectedRecSvcErrorRate `
    -MinDelta 0.01 `
    -MinInjected 0.01 `
    -Note "Informational only. OB-007 no longer gates publication on recommendationservice error rate."
$recSvcGrpcFailureSignal = Compare-ErrorSignal `
    -Key "recommendationservice.grpc_failure_rate" `
    -BaselineMetric $baselineRecSvcGrpcFailureRate `
    -InjectedMetric $injectedRecSvcGrpcFailureRate `
    -MinDelta 0.01 `
    -MinInjected 0.01 `
    -Note "Informational only. Linkerd has reported recommendationservice grpc_status=0/classification=success for this scenario."
$recSvcGrpcNonOkSignal = Compare-ErrorSignal `
    -Key "recommendationservice.grpc_non_ok_rate" `
    -BaselineMetric $baselineRecSvcGrpcNonOkRate `
    -InjectedMetric $injectedRecSvcGrpcNonOkRate `
    -MinDelta 0.01 `
    -MinInjected 0.01 `
    -Note "Informational only. OB-007 no longer uses context.abort or gRPC non-OK status as the required signal."
$recommendationservicePrometheusSignalConfirmed = $recSvcLatencySignal.passed

# Frontend error rate should NOT increase (graceful degradation)
$frontendErrDelta = $frontendErrInjected - $frontendErrBaseline
$frontendErrStable = [Math]::Abs($frontendErrDelta) -lt 0.05

$recommendationserviceBehavioralSignalConfirmed = $recommendationservicePrometheusSignalConfirmed
$publicationConfirmed = $false

$movement = [ordered]@{
    captured_at_utc = ([datetime]::UtcNow).ToString("o")
    scenario = "OB-007"
    validation_thresholds = [ordered]@{
        product_detail_ok_rate_min = 0.80
        recommendation_section_must_be_absent = $true
        recommendationservice_latency_min_delta_seconds = $RecommendationLatencyMinDeltaSeconds
        recommendationservice_latency_min_ratio = $RecommendationLatencyMinRatio
    }
    recommendationservice_latency = $recSvcLatencySignal
    recommendationservice_runtime_signal = [ordered]@{
        confirmed = $recommendationservicePrometheusSignalConfirmed
        primary = "recommendationservice.latency_p95"
        accepted_signals = @(
            "recommendationservice.latency_p95"
        )
        informational_signals = @(
            "recommendationservice.grpc_failure_rate",
            "recommendationservice.grpc_non_ok_rate",
            "recommendationservice.error_rate"
        )
        grpc_failure_rate = $recSvcGrpcFailureSignal
        grpc_non_ok_rate = $recSvcGrpcNonOkSignal
        http_error_rate = $recSvcHttpErrorSignal
    }
    frontend_error_rate = [ordered]@{
        key = "frontend.error_rate"
        baseline = $frontendErrBaseline
        injected = $frontendErrInjected
        delta = $frontendErrDelta
        stable = $frontendErrStable
        note = "Informational only; product detail HTTP probes are the graceful degradation gate."
        passed = $frontendErrStable
    }
    product_detail_ok_rate = [ordered]@{
        baseline_ok_count = $baselineOkCount
        injected_ok_count = $injectedOkCount
        total_probes = $TrafficProbes
        injected_ok_fraction = [double]$injectedOkCount / $TrafficProbes
        note = "Product detail pages must remain accessible (>=80% 200s) to confirm graceful degradation"
        passed = $gracefulDegradationConfirmed
    }
    recommendationservice_prometheus_signal_confirmed = $recommendationservicePrometheusSignalConfirmed
    recommendationservice_behavioral_signal_confirmed = $recommendationserviceBehavioralSignalConfirmed
    frontend_signal_confirmed = $false
    graceful_degradation_confirmed = $gracefulDegradationConfirmed
    playwright_section_signal_confirmed = $false
    publication_runtime_evidence = if ($publicationConfirmed) { "CONFIRMED" } else { "INSUFFICIENT" }
}
Write-Json "$EvidenceDir/runtime-movement-summary.json" $movement
Write-Host "  recommendationservice_prometheus_signal_confirmed: $recommendationservicePrometheusSignalConfirmed"
Write-Host "  recommendationservice_behavioral_signal_confirmed: $recommendationserviceBehavioralSignalConfirmed"
Write-Host "  graceful_degradation_confirmed: $gracefulDegradationConfirmed"
Write-Host "  publication_runtime_evidence: $($movement.publication_runtime_evidence)"

# --- STEP 9: PLAYWRIGHT TESTS ------------------------------------------------
Write-Step "Step 9: Playwright tests (injected cluster)"

$playwrightEnv = @{ FRONTEND_URL = $FrontendUrl }
$playwrightResult = $null
$playwrightOutput = $null
$playwrightSectionSignalConfirmed = $false

if ($DryRun) {
    Write-Host "  [DRY RUN] Would run Playwright test suite in $PlaywrightDir"
}
else {
    Push-Location $PlaywrightDir
    try {
        # Run the full test suite with workers=1 to avoid thundering herd.
        # The recommendation test (09-recommendation-baseline.spec.js) must FAIL.
        # Core product detail tests must PASS.
        $env:FRONTEND_URL = $FrontendUrl
        $playwrightOutput = npx playwright test --workers=1 2>&1
        $playwrightExitCode = $LASTEXITCODE
        $playwrightOutput | ForEach-Object { Write-Host "  [playwright] $_" }

        # Check that recommendation test failed specifically
        $playwrightText = ($playwrightOutput -join "`n")
        $recTestFailed = $playwrightText -match "recommendation-section-visible-on-detail" -and $playwrightText -match "(?m)^\s*x\s+\d+\s+\[chromium\].*recommendation-section-visible-on-detail|1 failed|failed"
        $coreTestsPassed = -not ($playwrightOutput -match "product-detail-page-has-add-to-cart-button.*FAILED|product-detail-page-has-price.*FAILED")

        $playwrightSectionSignalConfirmed = $recTestFailed
        Write-Host "  recommendation-section-visible-on-detail FAILED: $recTestFailed"
        Write-Host "  Core product-detail tests passed: $coreTestsPassed"
    }
    finally {
        Pop-Location
    }
}

# Update movement summary with playwright signal
$movement.playwright_section_signal_confirmed = $playwrightSectionSignalConfirmed
$recommendationserviceBehavioralSignalConfirmed = $recommendationservicePrometheusSignalConfirmed -and $gracefulDegradationConfirmed -and $playwrightSectionSignalConfirmed
$publicationConfirmed = $recommendationserviceBehavioralSignalConfirmed
$movement.recommendationservice_prometheus_signal_confirmed = $recommendationservicePrometheusSignalConfirmed
$movement.recommendationservice_behavioral_signal_confirmed = $recommendationserviceBehavioralSignalConfirmed
$movement.publication_runtime_evidence = if ($publicationConfirmed) { "CONFIRMED" } else { "INSUFFICIENT" }
Write-Json "$EvidenceDir/runtime-movement-summary.json" $movement

# --- STEP 10: QMIND SELECTION FOR OB-007 -------------------------------------
Write-Step "Step 10: QMind selection for OB-007"

$changedFilesPayload = ConvertTo-Json -InputObject @($DeclaredChangedFile) -Compress
$changedFilesFile = "$BenchmarkRunDir/scenario-ob-007-changed-files.json"
New-Item -ItemType Directory -Force -Path $BenchmarkRunDir | Out-Null
Write-Utf8NoBom -Path $changedFilesFile -Text ($changedFilesPayload + [Environment]::NewLine)
Write-Json "$EvidenceDir/scenario-ob-007-changed-files.json" @($DeclaredChangedFile)

$qmindSelectionOutput = "$QMindSelectionDir/qmind-selection-ob-007.json"
if ($DryRun) {
    Write-Host "  [DRY RUN] Would run: run-qmind-subset.ps1 -BenchmarkCase OB-007"
}
else {
    & .\benchmark-pipeline\run-qmind-subset.ps1 `
        -BenchmarkCase OB-007 `
        -SelectionOutput $qmindSelectionOutput `
        -EnvFile $EnvFile
    if ($LASTEXITCODE -ne 0) { throw "QMind selection failed for OB-007." }
}

$qmindDetected = $false
$qmindRunId = $null
$qmindHasRuntimeSignal = $false
$qmindSignalState = $null
$qmindSkipReason = $null
$qmindBusinessMetrics = $null
if (Test-Path -LiteralPath $qmindSelectionOutput -PathType Leaf) {
    $qmindSelection = Get-Content -LiteralPath $qmindSelectionOutput -Raw | ConvertFrom-Json
    $selectedTests = @($qmindSelection.selected_tests | ForEach-Object { [string]$_ })
    $qmindDetected = $selectedTests -contains "recommendation-section-visible-on-detail"
    $qmindRunId = [string]$qmindSelection.qmind_subset_json.run_id
    if ([string]::IsNullOrWhiteSpace($qmindRunId)) { $qmindRunId = [string]$qmindSelection.run_id }
    $qmindHasRuntimeSignalValue = Get-ObjectPropertyValue (Get-ObjectPropertyValue $qmindSelection "qmind_subset_json") "has_runtime_signal"
    if ($null -eq $qmindHasRuntimeSignalValue) { $qmindHasRuntimeSignalValue = Get-ObjectPropertyValue $qmindSelection "has_runtime_signal" }
    $qmindHasRuntimeSignal = [bool]$qmindHasRuntimeSignalValue
    $qmindSignalState = [string](Get-ObjectPropertyValue (Get-ObjectPropertyValue $qmindSelection "qmind_subset_json") "signal_state")
    if ([string]::IsNullOrWhiteSpace($qmindSignalState)) { $qmindSignalState = [string](Get-ObjectPropertyValue $qmindSelection "signal_state") }
    $qmindSkipReason = [string](Get-ObjectPropertyValue (Get-ObjectPropertyValue $qmindSelection "qmind_subset_json") "skip_reason")
    if ([string]::IsNullOrWhiteSpace($qmindSkipReason)) { $qmindSkipReason = [string](Get-ObjectPropertyValue $qmindSelection "skip_reason") }
    $qmindBusinessMetrics = Get-ObjectPropertyValue $qmindSelection "business_metrics"

    # Copy selection to evidence dir
    Copy-Item -LiteralPath $qmindSelectionOutput -Destination "$EvidenceDir/qmind-selection-ob-007.json" -Force

    Write-Host "  QMind selected $($selectedTests.Count) tests."
    Write-Host "  recommendation-section-visible-on-detail in selection: $qmindDetected"
    Write-Host "  QMind has_runtime_signal: $qmindHasRuntimeSignal"
    Write-Host "  QMind signal_state: $qmindSignalState"
    Write-Host "  QMind run_id: $qmindRunId"
}

if ((-not $qmindDetected -or -not $qmindHasRuntimeSignal -or $qmindSignalState -eq "historical_only") -and -not $DryRun) {
    Write-Warning @"
QMind did not produce a runtime-aware OB-007 detection.
detected=$qmindDetected has_runtime_signal=$qmindHasRuntimeSignal signal_state=$qmindSignalState skip_reason=$qmindSkipReason

Possible causes:
  1. The injection was not applied to the running cluster.
  2. Prometheus did not show recommendationservice latency p95 movement above the OB-007 threshold.
  3. QMind did not ingest the injected Prometheus window.
  4. The QMind observability window did not overlap with the injected traffic period.

Stopping. Fix the runtime signal before publishing evidence.
"@
    throw "QMind did not produce a runtime-aware OB-007 detection."
}

# --- STEP 11: H+CC VALIDATION ------------------------------------------------
Write-Step "Step 11: H+CC selection for OB-007 (verify miss)"

$hccSelectionOutput = "benchmark-results/final-comparison/history-code-change-ob-007-selection.json"
$hccDetectedOracleTest = $false
if (-not $DryRun) {
    & python benchmark-pipeline/select-history-code-change-approach.py `
        --library "qmind-test-library/online-boutique-playwright-51.json" `
        --scenarios benchmark-pipeline/scenarios.json `
        --size 15 `
        --scenario OB-007 `
        --output $hccSelectionOutput
    if ($LASTEXITCODE -ne 0) { throw "H+CC selection failed for OB-007." }

    $hccSelection = Get-Content -LiteralPath $hccSelectionOutput -Raw | ConvertFrom-Json
    $hccSelectedTests = @($hccSelection.selected_tests | ForEach-Object { [string]$_ })
    $hccDetectedOracleTest = $hccSelectedTests -contains "recommendation-section-visible-on-detail"
    Write-Host "  H+CC selected $($hccSelectedTests.Count) tests."
    Write-Host "  recommendation-section-visible-on-detail in H+CC selection: $hccDetectedOracleTest"
    if ($hccDetectedOracleTest) {
        Write-Warning "H+CC selected the oracle test ? OB-007 will NOT demonstrate an H+CC miss. Review the changed file tokenization."
    }
    else {
        Write-Host "  Confirmed: H+CC misses recommendation-section-visible-on-detail for OB-007."
    }
}


# --- STEP 12: DETECTION SUMMARY ----------------------------------------------
Write-Step "Step 12: QMind detection summary"

$detectionSummary = [ordered]@{
    detected = $qmindDetected
    scenario = "OB-007"
    qmind_run_id = $qmindRunId
    selection_artifact = "benchmark-results/qmind-selections/qmind-selection-ob-007.json"
    has_runtime_signal = $qmindHasRuntimeSignal
    signal_state = $qmindSignalState
    skip_reason = $qmindSkipReason
    business_metrics = $qmindBusinessMetrics
    observability_enabled = $true
    changed_files_file = $changedFilesFile
    changed_files = @($DeclaredChangedFile)
    expected_detector_ids = @("recommendation-section-visible-on-detail")
    selected_detector_ids = if ($qmindDetected) { @("recommendation-section-visible-on-detail") } else { @() }
    missing_detector_ids = if ($qmindDetected) { @() } else { @("recommendation-section-visible-on-detail") }
    recommendationservice_prometheus_signal_confirmed = $recommendationservicePrometheusSignalConfirmed
    playwright_section_confirmed = $playwrightSectionSignalConfirmed
    graceful_degradation_confirmed = $gracefulDegradationConfirmed
}
Write-Json "$EvidenceDir/qmind-ob007-detection-summary.json" $detectionSummary

# --- STEP 13: PUBLISH EVIDENCE MANIFEST --------------------------------------
Write-Step "Step 13: Evidence manifest"

$hccMissConfirmed = -not $hccDetectedOracleTest
$qmindRuntimeAwareConfirmed = $qmindDetected -and $qmindHasRuntimeSignal -and $qmindSignalState -ne "historical_only"
$evidenceStatus = if ($qmindRuntimeAwareConfirmed -and $recommendationserviceBehavioralSignalConfirmed -and $hccMissConfirmed) { "verified" } else { "insufficient" }
$manifest = [ordered]@{
    scenario = "OB-007"
    evidence_status = $evidenceStatus
    published_at_utc = ([datetime]::UtcNow).ToString("o")
    source_run_dir = $BenchmarkRunDir
    qmind_selection_artifact = "benchmark-results/qmind-selections/qmind-selection-ob-007.json"
    qmind_run_id = $qmindRunId
    changed_files = @($DeclaredChangedFile)
    required_runtime_chain = @(
        "product detail pages remain accessible (HTTP 200 - graceful degradation confirmed)",
        "recommendation section absent from product detail at Playwright level",
        "recommendationservice Prometheus latency p95 signal confirmed",
        "QMind selection generated after injected runtime window includes oracle test with has_runtime_signal=true",
        "History + Code Change selection does not include oracle test"
    )
    published_files = @(
        "benchmark-results/runtime-evidence/ob-007/baseline-prometheus-snapshot.json",
        "benchmark-results/runtime-evidence/ob-007/injected-prometheus-snapshot.json",
        "benchmark-results/runtime-evidence/ob-007/runtime-movement-summary.json",
        "benchmark-results/runtime-evidence/ob-007/baseline-product-detail-traffic.json",
        "benchmark-results/runtime-evidence/ob-007/injected-product-detail-traffic.json",
        "benchmark-results/runtime-evidence/ob-007/qmind-ob007-detection-summary.json",
        "benchmark-results/runtime-evidence/ob-007/scenario-ob-007-changed-files.json",
        "benchmark-results/runtime-evidence/ob-007/qmind-selection-ob-007.json"
    )
}
Write-Json "$EvidenceDir/evidence-manifest.json" $manifest

# --- STEP 14: RESTORE --------------------------------------------------------
Write-Step "Step 14: Restore OB-007 injection"
if ($DryRun) {
    Write-Host "  [DRY RUN] Would restore $SourceRoot/$RecommendationServerFile and restore recommendationservice deployment image to $originalImage"
}
else {
    Restore-Ob007SourceAndDeployment -Reason "normal completion"
}

# --- SUMMARY -----------------------------------------------------------------
Write-Step "OB-007 Evidence Validation Summary"
Write-Host "  Evidence status:                     $evidenceStatus"
Write-Host "  recommendationservice_behavioral:     $recommendationserviceBehavioralSignalConfirmed"
Write-Host "  recommendationservice_prometheus:     $recommendationservicePrometheusSignalConfirmed"
Write-Host "  graceful_degradation_confirmed:       $gracefulDegradationConfirmed"
Write-Host "  playwright_section_signal:            $playwrightSectionSignalConfirmed"
Write-Host "  QMind detected oracle test:           $qmindDetected"
Write-Host "  QMind runtime-aware signal:           $qmindRuntimeAwareConfirmed"
Write-Host "  H+CC missed oracle test:              $hccMissConfirmed"
Write-Host "  Evidence dir:                         $EvidenceDir"

if ($evidenceStatus -eq "verified") {
    Write-Host "`nEvidence verified. Next steps:" -ForegroundColor Green
    Write-Host "  1. Update defect-oracle/online-boutique-defect-oracle.v2.json: set OB-007 validated_detecting_tests and validation_status='validated-runtime-oracle'"
    Write-Host "  2. Run: benchmark-pipeline/generate-final-comparison.ps1 to regenerate the final comparison with OB-007"
}
else {
    Write-Warning "Evidence insufficient. Review the signals above before publishing OB-007."
}

} finally {
    if ($sourceInjectionApplied -and -not $restoreCompleted -and -not $DryRun) {
        try {
            Restore-Ob007SourceAndDeployment -Reason "cleanup after early exit"
        }
        catch {
            Write-Warning "Automatic OB-007 cleanup failed: $($_.Exception.Message)"
            Write-Warning "Manual source restore command: .\runtime-scenarios\ob-007-recommendation-logging-overhead\apply-ob007-recommendation-logging-overhead.ps1 -SourceRoot $SourceRoot -DeclaredChangedFile $DeclaredChangedFile -RecommendationServerFile $RecommendationServerFile -Restore"
            if ($injectedImageDeployed -and -not [string]::IsNullOrWhiteSpace($originalImage)) {
                Write-Warning "Manual deployment restore commands:"
                Write-Warning "  kubectl -n $PrometheusNamespace set image deployment/$Deployment $Container=$originalImage"
                Write-Warning "  kubectl -n $PrometheusNamespace rollout status deployment/$Deployment --timeout=${RolloutTimeoutSeconds}s"
            }
        }
    }
}




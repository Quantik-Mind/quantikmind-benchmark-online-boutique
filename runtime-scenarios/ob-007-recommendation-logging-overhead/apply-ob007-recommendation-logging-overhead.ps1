param(
    [string]$SourceRoot = "microservices-demo",
    [string]$DeclaredChangedFile = "src/adservice/src/main/java/hipstershop/AdService.java",
    [string]$RecommendationServerFile = "src/recommendationservice/recommendation_server.py",
    [string]$BackupPath,
    # Scoped ListRecommendations-only latency in milliseconds. Keep <=300ms to avoid health/liveness impact.
    [ValidateRange(1, 300)]
    [int]$LatencyMs = 200,
    [switch]$Restore
)

$ErrorActionPreference = "Stop"

function Resolve-RepoPath {
    param([string]$Path)
    return $ExecutionContext.SessionState.Path.GetUnresolvedProviderPathFromPSPath($Path)
}

function Write-Utf8NoBom {
    param(
        [string]$Path,
        [string]$Text
    )
    [System.IO.File]::WriteAllText(
        (Resolve-RepoPath $Path),
        $Text,
        [System.Text.UTF8Encoding]::new($false)
    )
}

function Assert-DeclaredChangedFileGuard {
    param([string]$Path)

    if (-not (Test-Path -LiteralPath $Path -PathType Leaf)) {
        throw "Missing declared changed file: $Path"
    }

    $declaredFileSource = Get-Content -LiteralPath $Path -Raw
    if ($declaredFileSource -match "(?i)OB-007") {
        throw "Declared changed file guard failed. $Path must not contain OB-007 injection markers."
    }
}

function Test-Ob007InjectionPresent {
    param([string]$Text)
    return $Text -match "\[OB-007\] Injecting recommendationservice (ListRecommendations latency|gRPC unavailable|degraded recommendation response)"
}

$target = Join-Path $SourceRoot $RecommendationServerFile
$declaredChangedFileTarget = Join-Path $SourceRoot $DeclaredChangedFile
if ([string]::IsNullOrWhiteSpace($BackupPath)) {
    $BackupPath = "$target.ob007.bak"
}

if (-not (Test-Path -LiteralPath $target -PathType Leaf)) {
    throw "Missing recommendationservice server file: $target"
}

if ($Restore) {
    $currentSource = Get-Content -LiteralPath $target -Raw
    if (Test-Path -LiteralPath $BackupPath -PathType Leaf) {
        Copy-Item -LiteralPath $BackupPath -Destination $target -Force
        Remove-Item -LiteralPath $BackupPath -Force
        Write-Host "Restored $target from $BackupPath."
    }
    elseif (Test-Ob007InjectionPresent -Text $currentSource) {
        throw "Missing OB-007 backup file: $BackupPath"
    }
    else {
        Write-Host "No OB-007 recommendation_server.py backup found and no active injection detected."
    }

    Assert-DeclaredChangedFileGuard -Path $declaredChangedFileTarget
    $restoredSource = Get-Content -LiteralPath $target -Raw
    if (Test-Ob007InjectionPresent -Text $restoredSource) {
        throw "OB-007 injection remains in $target after restore."
    }
    exit 0
}

Assert-DeclaredChangedFileGuard -Path $declaredChangedFileTarget

if (-not (Test-Path -LiteralPath $BackupPath -PathType Leaf)) {
    Copy-Item -LiteralPath $target -Destination $BackupPath
}

$source = Get-Content -LiteralPath $target -Raw
if (Test-Ob007InjectionPresent -Text $source) {
    throw "OB-007 injection is already present in $target. Restore first or inspect the file."
}

$pattern = '(?ms)(        logger\.info\("\[Recv ListRecommendations\] product_ids=\{\}"\.format\(prod_list\)\)\r?\n)(        # build and return response\r?\n        response = demo_pb2\.ListRecommendationsResponse\(\)\r?\n        response\.product_ids\.extend\(prod_list\)\r?\n        return response)'
if ($source -notmatch $pattern) {
    throw "Could not find the standard ListRecommendations response block in $target."
}

$injectedBlock = @'
        logger.warning("[OB-007] Injecting recommendationservice ListRecommendations latency and empty recommendation response")
        time.sleep(__LATENCY_SECONDS__)
        response = demo_pb2.ListRecommendationsResponse()
        return response
'@

$latencySeconds = ([double]$LatencyMs / 1000.0).ToString("0.###", [System.Globalization.CultureInfo]::InvariantCulture)
$updated = [regex]::Replace($source, $pattern, "`$1$($injectedBlock.Replace('__LATENCY_SECONDS__', $latencySeconds))", 1)
Write-Utf8NoBom -Path $target -Text $updated

Write-Host "Applied OB-007 recommendation runtime latency degradation to ${target}: ListRecommendations sleeps ${LatencyMs}ms and returns empty product_ids."
Write-Host "Declared changed file (CI trigger): $DeclaredChangedFile"
Write-Host "Restore with: .\runtime-scenarios\ob-007-recommendation-logging-overhead\apply-ob007-recommendation-logging-overhead.ps1 -Restore"

param(
    [string]$SourceRoot = "microservices-demo",
    [string]$AdServiceFile = "src/adservice/src/main/java/hipstershop/AdService.java",
    [string]$BackupPath,
    [ValidateSet("latency", "failure")]
    [string]$Mode = "latency",
    [int]$LatencyMs = 35000,
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

$target = Join-Path $SourceRoot $AdServiceFile
if ([string]::IsNullOrWhiteSpace($BackupPath)) {
    $BackupPath = "$target.ob006.bak"
}

if ($Restore) {
    if (-not (Test-Path -LiteralPath $BackupPath -PathType Leaf)) {
        throw "Missing OB-006 backup file: $BackupPath"
    }
    Copy-Item -LiteralPath $BackupPath -Destination $target -Force
    Write-Host "Restored $target from $BackupPath."
    exit 0
}

if (-not (Test-Path -LiteralPath $target -PathType Leaf)) {
    throw "Missing adservice file: $target"
}

if ($LatencyMs -lt 0) {
    throw "LatencyMs must be zero or greater."
}

if (-not (Test-Path -LiteralPath $BackupPath -PathType Leaf)) {
    Copy-Item -LiteralPath $target -Destination $BackupPath
}

$source = Get-Content -LiteralPath $target -Raw
if ($source -match "OB-006 Ad Service Latency Cascade") {
    throw "OB-006 injection is already present in $target. Restore first or inspect the file."
}

$injection = if ($Mode -eq "failure") {
@"
    // OB-006 Ad Service Latency Cascade: deterministic adservice failure for benchmark validation.
    responseObserver.onError(
        io.grpc.Status.UNAVAILABLE
            .withDescription("OB-006 deterministic adservice failure")
            .asRuntimeException());
    return;

"@
} else {
@"
    // OB-006 Ad Service Latency Cascade: deterministic latency above Playwright's 30s test timeout.
    try {
      Thread.sleep(${LatencyMs}L);
    } catch (InterruptedException e) {
      Thread.currentThread().interrupt();
      responseObserver.onError(
          io.grpc.Status.DEADLINE_EXCEEDED
              .withDescription("OB-006 adservice latency interrupted")
              .asRuntimeException());
      return;
    }

"@
}

$pattern = "(?ms)(public\s+void\s+getAds\s*\([^)]*responseObserver[^)]*\)\s*\{\s*)"
if ($source -notmatch $pattern) {
    throw "Could not find the adservice getAds method in $target. The helper expects the standard Online Boutique AdService.java shape."
}

$updated = [regex]::Replace($source, $pattern, "`$1$injection", 1)
Write-Utf8NoBom -Path $target -Text $updated

Write-Host "Applied OB-006 Ad Service Latency Cascade to ${target}: mode=$Mode latency_ms=$LatencyMs."
Write-Host "Restore with: .\runtime-scenarios\ob-006-adservice-latency-cascade\apply-ob006-adservice-latency.ps1 -Restore"

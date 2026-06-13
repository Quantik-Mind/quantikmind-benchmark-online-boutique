param(
    [string]$SourceRoot = "microservices-demo",
    [string]$ProductCatalogFile = "src/productcatalogservice/product_catalog.go",
    [string]$BackupPath,
    [ValidateSet("latency", "failure")]
    [string]$Mode = "failure",
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

$target = Join-Path $SourceRoot $ProductCatalogFile
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
    throw "Missing productcatalogservice file: $target"
}

if ($LatencyMs -lt 0) {
    throw "LatencyMs must be zero or greater."
}

if (-not (Test-Path -LiteralPath $BackupPath -PathType Leaf)) {
    Copy-Item -LiteralPath $target -Destination $BackupPath
}

$source = Get-Content -LiteralPath $target -Raw
if ($source -match "OB-006 ProductCatalog ListProducts Cascade") {
    throw "OB-006 injection is already present in $target. Restore first or inspect the file."
}

$injection = if ($Mode -eq "failure") {
@"
	// OB-006 ProductCatalog ListProducts Cascade: deterministic homepage-critical product listing failure.
	return nil, status.Errorf(codes.Unavailable, "OB-006 deterministic product catalog ListProducts failure")

"@
} else {
@"
	// OB-006 ProductCatalog ListProducts Cascade: deterministic latency above Playwright's 30s test timeout.
	time.Sleep(time.Duration(${LatencyMs}) * time.Millisecond)

"@
}

$pattern = "(?ms)(func\s+\(p\s+\*productCatalog\)\s+ListProducts\s*\(\s*context\.Context\s*,\s*\*pb\.Empty\s*\)\s*\(\s*\*pb\.ListProductsResponse\s*,\s*error\s*\)\s*\{\s*)"
if ($source -notmatch $pattern) {
    throw "Could not find productcatalogservice ListProducts in $target. The helper expects the standard Online Boutique product_catalog.go shape."
}

$updated = [regex]::Replace($source, $pattern, "`$1$injection", 1)
Write-Utf8NoBom -Path $target -Text $updated

Write-Host "Applied OB-006 ProductCatalog ListProducts Cascade to ${target}: mode=$Mode latency_ms=$LatencyMs."
Write-Host "Restore with: .\runtime-scenarios\ob-006-productcatalog-listproducts-cascade\apply-ob006-productcatalog-listproducts.ps1 -Restore"

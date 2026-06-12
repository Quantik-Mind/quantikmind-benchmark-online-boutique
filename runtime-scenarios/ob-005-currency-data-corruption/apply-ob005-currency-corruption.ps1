param(
    [string]$SourceRoot = "microservices-demo",
    [string]$CurrencyFile = "src/currencyservice/data/currency_conversion.json",
    [string]$BackupPath,
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

$target = Join-Path $SourceRoot $CurrencyFile
if ([string]::IsNullOrWhiteSpace($BackupPath)) {
    $BackupPath = "$target.ob005.bak"
}

if ($Restore) {
    if (-not (Test-Path -LiteralPath $BackupPath -PathType Leaf)) {
        throw "Missing OB-005 backup file: $BackupPath"
    }
    Copy-Item -LiteralPath $BackupPath -Destination $target -Force
    Write-Host "Restored $target from $BackupPath."
    exit 0
}

if (-not (Test-Path -LiteralPath $target -PathType Leaf)) {
    throw "Missing currency conversion file: $target"
}

if (-not (Test-Path -LiteralPath $BackupPath -PathType Leaf)) {
    Copy-Item -LiteralPath $target -Destination $BackupPath
}

$rates = Get-Content -LiteralPath $target -Raw | ConvertFrom-Json
if ($null -eq $rates.USD) {
    throw "Currency conversion file does not contain a USD rate: $target"
}

$rates.USD = "0"
$payload = $rates | ConvertTo-Json -Depth 5
Write-Utf8NoBom -Path $target -Text ($payload + [Environment]::NewLine)

Write-Host "Applied OB-005 Currency Data Corruption to ${target}: USD rate set to 0."
Write-Host "Restore with: .\runtime-scenarios\ob-005-currency-data-corruption\apply-ob005-currency-corruption.ps1 -Restore"

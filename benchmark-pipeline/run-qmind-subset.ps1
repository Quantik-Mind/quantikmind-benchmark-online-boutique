param(
    [string]$EnvFile = ".env",
    [string]$ChangedFilesFile = "benchmark-runs/scenario-ob004-changed-files.json",
    [string]$RunDir = "benchmark-runs/qmind-online-boutique",
    [string]$SelectionOutput = "benchmark-runs/qmind-online-boutique/qmind-current-selection.json",
    [string]$LibraryApi,
    [switch]$DryRun
)

$ErrorActionPreference = "Stop"

function Read-DotEnv {
    param([string]$Path)

    $values = @{}
    if (Test-Path -LiteralPath $Path -PathType Leaf) {
        foreach ($line in Get-Content -LiteralPath $Path) {
            $trimmed = $line.Trim()
            if (-not $trimmed -or $trimmed.StartsWith("#")) {
                continue
            }
            $parts = $trimmed -split "=", 2
            if ($parts.Count -eq 2) {
                $name = $parts[0].Trim()
                $value = $parts[1].Trim().Trim('"').Trim("'")
                $values[$name] = $value
                Set-Item -Path "Env:$name" -Value $value
            }
        }
    }
    return $values
}

function Assert-QmindConfig {
    param([hashtable]$Values)

    foreach ($name in @("QMIND_API_URL", "QMIND_API_KEY", "QMIND_PROJECT_ID")) {
        if (-not $Values.ContainsKey($name) -or [string]::IsNullOrWhiteSpace($Values[$name]) -or $Values[$name] -eq "replace-me") {
            if ($DryRun) {
                Write-Warning "Missing required $name in .env. A real run will fail until this is filled in."
                continue
            }
            throw "Missing required $name in .env. Run setup-qmind.ps1 after filling in .env."
        }
    }
}

function Write-TextUtf8NoBom {
    param([string]$Path, [string]$Text)

    $directory = Split-Path -Parent $Path
    if ($directory) {
        New-Item -ItemType Directory -Force -Path $directory | Out-Null
    }
    $encoding = [System.Text.UTF8Encoding]::new($false)
    [System.IO.File]::WriteAllText((Join-Path (Get-Location) $Path), $Text, $encoding)
}

$envValues = Read-DotEnv -Path $EnvFile
Assert-QmindConfig -Values $envValues

if (-not (Test-Path -LiteralPath $ChangedFilesFile -PathType Leaf)) {
    throw "Missing changed-files scenario input: $ChangedFilesFile"
}
New-Item -ItemType Directory -Force -Path $RunDir | Out-Null
$rawOutput = Join-Path $RunDir "qmind-subset-current.txt"
$args = @("subset", "--changed-files-file", $ChangedFilesFile)
Write-Host ("qmind " + ($args -join " "))

if ($DryRun) {
    Write-Host "Dry run complete; subset was not executed."
    exit 0
}

if (-not (Get-Command qmind -ErrorAction SilentlyContinue)) {
    throw "qmind CLI was not found on PATH. Install or activate the Quantik Mind CLI, then rerun this script."
}

$output = & qmind @args 2>&1
$exitCode = $LASTEXITCODE
$text = ($output | Out-String)
Write-TextUtf8NoBom -Path $rawOutput -Text $text
Write-Host $text

if ($exitCode -ne 0) {
    throw "qmind subset failed with exit code $exitCode. Confirm QMind setup and project history before rerunning."
}

if (-not $LibraryApi) {
    $preferred = Join-Path $RunDir "library-api-51.json"
    $fallback = Join-Path $RunDir "library-api.json"
    if (Test-Path -LiteralPath $preferred -PathType Leaf) {
        $LibraryApi = $preferred
    } elseif (Test-Path -LiteralPath $fallback -PathType Leaf) {
        $LibraryApi = $fallback
    }
}

$normalizeArgs = @("benchmark-pipeline/normalize-qmind-selection.py", $rawOutput, $SelectionOutput)
if ($LibraryApi) {
    $normalizeArgs += @("--library-api", $LibraryApi)
}

& python @normalizeArgs
if ($LASTEXITCODE -ne 0) {
    throw "Failed to normalize QMind subset output."
}

$selection = Get-Content -LiteralPath $SelectionOutput -Raw | ConvertFrom-Json
if ($selection.selected_tests -notcontains "payment-order-completion-confirms-success") {
    throw "QMind selection is missing required detector: payment-order-completion-confirms-success"
}

$canonicalPayload = @{
    method = "qmind"
    selected_tests = @($selection.selected_tests | Sort-Object)
} | ConvertTo-Json -Depth 5
Write-TextUtf8NoBom -Path $SelectionOutput -Text ($canonicalPayload + [Environment]::NewLine)

$bytes = [System.IO.File]::ReadAllBytes((Join-Path (Get-Location) $SelectionOutput))
if ($bytes.Length -ge 3 -and $bytes[0] -eq 239 -and $bytes[1] -eq 187 -and $bytes[2] -eq 191) {
    throw "Selection output has a UTF-8 BOM: $SelectionOutput"
}

Write-Host "Wrote canonical QMind selection to $SelectionOutput."

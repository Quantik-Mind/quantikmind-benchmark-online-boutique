param(
    [string]$EnvFile = ".env",
    [string]$Library = "qmind-test-library/online-boutique-playwright-51.json",
    [string]$RunDir = "benchmark-runs/qmind-online-boutique",
    [int]$ExpectedLibrarySize = 52,
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
            throw "Missing required $name in .env. Run benchmark-pipeline/setup-qmind.ps1 after filling in .env."
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

function Get-TestCount {
    param([object]$Payload)

    if ($Payload -is [array]) {
        return $Payload.Count
    }
    if ($Payload.tests -is [array]) {
        return $Payload.tests.Count
    }
    if ($Payload.data -is [array]) {
        return $Payload.data.Count
    }
    throw "Could not find a tests array in $Library."
}

$envValues = Read-DotEnv -Path $EnvFile
Assert-QmindConfig -Values $envValues

if (-not (Test-Path -LiteralPath $Library -PathType Leaf)) {
    throw "Missing QMind test library: $Library"
}

$libraryPayload = Get-Content -LiteralPath $Library -Raw | ConvertFrom-Json
$librarySize = Get-TestCount -Payload $libraryPayload
if ($librarySize -ne $ExpectedLibrarySize) {
    throw "Expected library size $ExpectedLibrarySize, found $librarySize in $Library."
}

New-Item -ItemType Directory -Force -Path $RunDir | Out-Null
Write-Host "Validated $Library contains $librarySize tests."

$args = @("sync", "library", "--file", $Library)
Write-Host ("qmind " + ($args -join " "))
if ($DryRun) {
    Write-Host "Dry run complete; library was not synced."
    exit 0
}

if (-not (Get-Command qmind -ErrorAction SilentlyContinue)) {
    throw "qmind CLI was not found on PATH. Install or activate the Quantik Mind CLI, then rerun this script."
}

$env:PYTHONIOENCODING = "utf-8"
$env:PYTHONUTF8 = "1"
$output = & qmind @args 2>&1
$exitCode = $LASTEXITCODE
$text = ($output | Out-String)
Write-TextUtf8NoBom -Path (Join-Path $RunDir "qmind-sync-library.log") -Text $text
Write-Host $text

if ($exitCode -ne 0) {
    throw "qmind sync library failed with exit code $exitCode. Confirm QMIND_API_URL, QMIND_API_KEY, and QMIND_PROJECT_ID in .env."
}

try {
    $jsonStart = $text.IndexOf("{")
    $jsonEnd = $text.LastIndexOf("}")
    if ($jsonStart -ge 0 -and $jsonEnd -gt $jsonStart) {
        $json = $text.Substring($jsonStart, $jsonEnd - $jsonStart + 1)
        $mapping = $json | ConvertFrom-Json
        $mappingSize = Get-TestCount -Payload $mapping
        if ($mappingSize -eq $ExpectedLibrarySize) {
            Write-TextUtf8NoBom -Path (Join-Path $RunDir "library-api-51.json") -Text ($json + [Environment]::NewLine)
            Write-Host "Saved qmind library API mapping to $RunDir/library-api-51.json."
        }
    }
} catch {
    Write-Host "Sync completed. Could not extract a 51-test JSON API mapping from CLI output; keep or export library-api-51.json manually if subset output uses numeric IDs."
}

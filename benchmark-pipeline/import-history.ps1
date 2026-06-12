param(
    [string]$EnvFile = ".env",
    [string]$Library = "qmind-test-library/online-boutique-playwright-51.json",
    [string]$RunDir = "benchmark-runs/qmind-online-boutique",
    [switch]$GenerateOnly,
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
                Write-Warning "Missing required $name in .env. A real import will fail until this is filled in."
                continue
            }
            throw "Missing required $name in .env. Generate-only mode is available with -GenerateOnly."
        }
    }
}

function Invoke-Checked {
    param([string]$Command, [string[]]$Arguments)

    Write-Host ($Command + " " + ($Arguments -join " "))
    if ($DryRun) {
        return
    }

    & $Command @Arguments
    if ($LASTEXITCODE -ne 0) {
        throw "$Command failed with exit code $LASTEXITCODE."
    }
}

if (-not (Test-Path -LiteralPath $Library -PathType Leaf)) {
    throw "Missing QMind test library: $Library"
}

$historySyntheticDir = Join-Path $RunDir "history-synthetic"
$historyTargetedDir = Join-Path $RunDir "history-entanglement-targeted"
$historyJson = Join-Path $RunDir "history-entanglement-targeted.json"
New-Item -ItemType Directory -Force -Path $historySyntheticDir, $historyTargetedDir | Out-Null

Invoke-Checked -Command "python" -Arguments @("benchmark-pipeline/generate-synthetic-history-junit.py", $Library, $historySyntheticDir)
Invoke-Checked -Command "python" -Arguments @("benchmark-pipeline/generate-targeted-entanglement-history.py", $Library, $historyTargetedDir)
Invoke-Checked -Command "python" -Arguments @("benchmark-pipeline/generate-entangled-history-json.py", $Library, $historyJson)

if ($DryRun) {
    Write-Host "Dry run complete; synthetic history artifacts were not generated."
} else {
    Write-Host "Generated synthetic history artifacts under $RunDir."
}

if ($GenerateOnly) {
    if ($DryRun) {
        Write-Host "Generate-only dry run complete. Run without -DryRun to generate artifacts, then import them with the QMind CLI command supported by your installed version."
    } else {
        Write-Host "Generate-only mode complete. Import the generated XML/JSON files with the QMind CLI command supported by your installed version."
    }
    exit 0
}

$envValues = Read-DotEnv -Path $EnvFile
Assert-QmindConfig -Values $envValues

if (-not (Get-Command qmind -ErrorAction SilentlyContinue)) {
    throw "qmind CLI was not found on PATH. Install or activate the Quantik Mind CLI, then rerun this script or import the generated history manually."
}

$historyFiles = @()
$historyFiles += Get-ChildItem -LiteralPath $historySyntheticDir -Filter "*.xml" | Sort-Object Name
$historyFiles += Get-ChildItem -LiteralPath $historyTargetedDir -Filter "*.xml" | Sort-Object Name
$historyFiles += Get-Item -LiteralPath $historyJson

foreach ($file in $historyFiles) {
    $args = @("history", "import", "--file", $file.FullName)
    Write-Host ("qmind " + ($args -join " "))
    if ($DryRun) {
        continue
    }

    & qmind @args
    if ($LASTEXITCODE -ne 0) {
        throw "qmind history import failed for $($file.FullName). If your CLI uses a different history import command, import the generated artifacts manually from $RunDir."
    }
}

Write-Host "Imported synthetic benchmark history into QMind."

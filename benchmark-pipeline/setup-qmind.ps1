param(
    [string]$EnvFile = ".env",
    [string]$ConfigTemplate = "qmind.example.yaml",
    [string]$ConfigOutput = "qmind.yaml",
    [switch]$DryRun,
    [switch]$SkipInit
)

$ErrorActionPreference = "Stop"

function Read-DotEnv {
    param([string]$Path)

    $values = @{}
    if (-not (Test-Path -LiteralPath $Path -PathType Leaf)) {
        throw "Missing environment file: $Path. Copy .env.example to .env and fill in QMind values."
    }

    foreach ($line in Get-Content -LiteralPath $Path) {
        $trimmed = $line.Trim()
        if (-not $trimmed -or $trimmed.StartsWith("#")) {
            continue
        }

        $parts = $trimmed -split "=", 2
        if ($parts.Count -ne 2) {
            continue
        }

        $name = $parts[0].Trim()
        $value = $parts[1].Trim().Trim('"').Trim("'")
        $values[$name] = $value
        Set-Item -Path "Env:$name" -Value $value
    }

    return $values
}

function Assert-RequiredConfig {
    param([hashtable]$Values)

    $required = @("QMIND_API_URL", "QMIND_API_KEY", "QMIND_PROJECT_ID")
    foreach ($name in $required) {
        if (-not $Values.ContainsKey($name) -or [string]::IsNullOrWhiteSpace($Values[$name]) -or $Values[$name] -eq "replace-me") {
            if ($DryRun) {
                Write-Warning "Missing required $name in .env. A real run will fail until this is filled in."
                continue
            }
            throw "Missing required $name in .env. Fill it in, then rerun benchmark-pipeline/setup-qmind.ps1."
        }
    }
}

function Write-TextUtf8NoBom {
    param(
        [string]$Path,
        [string]$Text
    )

    $encoding = [System.Text.UTF8Encoding]::new($false)
    $directory = Split-Path -Parent $Path
    if ($directory) {
        New-Item -ItemType Directory -Force -Path $directory | Out-Null
    }
    [System.IO.File]::WriteAllText((Join-Path (Get-Location) $Path), $Text, $encoding)
}

function Invoke-Qmind {
    param(
        [string[]]$Arguments,
        [string[]]$DisplayArguments = $Arguments
    )

    Write-Host ("qmind " + ($DisplayArguments -join " "))
    if ($DryRun) {
        return
    }

    if (-not (Get-Command qmind -ErrorAction SilentlyContinue)) {
        throw "qmind CLI was not found on PATH. Install or activate the Quantik Mind CLI, then rerun this script."
    }

    & qmind @Arguments
    if ($LASTEXITCODE -ne 0) {
        throw "qmind command failed with exit code $LASTEXITCODE."
    }
}

$envValues = Read-DotEnv -Path $EnvFile
Assert-RequiredConfig -Values $envValues

if (-not (Test-Path -LiteralPath $ConfigTemplate -PathType Leaf)) {
    throw "Missing QMind config template: $ConfigTemplate"
}

$templateText = Get-Content -LiteralPath $ConfigTemplate -Raw
if ($DryRun) {
    Write-Host "Would write $ConfigOutput from $ConfigTemplate with environment placeholders preserved."
} else {
    Write-TextUtf8NoBom -Path $ConfigOutput -Text $templateText
    Write-Host "Wrote $ConfigOutput from $ConfigTemplate with environment placeholders preserved."
}
Write-Host "No secret values were written to $ConfigOutput by this script."

if ($SkipInit) {
    Write-Host "Skipped qmind init because -SkipInit was supplied."
    exit 0
}

$initArgs = @(
    "init",
    "--framework", "playwright",
    "--test-dir", "qmind-test-harness/playwright/tests",
    "--results-dir", "qmind-test-harness/playwright/test-results",
    "--non-interactive",
    "--api-url", $envValues["QMIND_API_URL"],
    "--api-key", $envValues["QMIND_API_KEY"],
    "--project-id", $envValues["QMIND_PROJECT_ID"]
)

Invoke-Qmind -Arguments $initArgs -DisplayArguments @(
    "init",
    "--framework", "playwright",
    "--test-dir", "qmind-test-harness/playwright/tests",
    "--results-dir", "qmind-test-harness/playwright/test-results",
    "--non-interactive",
    "--api-url", $envValues["QMIND_API_URL"],
    "--api-key", "<redacted>",
    "--project-id", $envValues["QMIND_PROJECT_ID"]
)
Write-Host "QMind setup complete. If your CLI does not support non-interactive init, keep $ConfigOutput and run qmind init manually with the same .env values."

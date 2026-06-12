param(
    [string]$EnvFile = ".env",
    [string]$Config = "qmind-config/observability-online-boutique.example.yaml",
    [string]$PrometheusUrl,
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
            throw "Missing required $name in .env. Fill in .env before configuring QMind observability."
        }
    }
}

function Invoke-Qmind {
    param([string[]]$Arguments)

    Write-Host ("qmind " + ($Arguments -join " "))
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
Assert-QmindConfig -Values $envValues

if (-not $PrometheusUrl) {
    $PrometheusUrl = $envValues["PROMETHEUS_URL"]
}
if (-not $PrometheusUrl) {
    $PrometheusUrl = "http://prometheus:9090"
}
if (-not (Test-Path -LiteralPath $Config -PathType Leaf)) {
    throw "Missing observability config: $Config"
}
Invoke-Qmind -Arguments @("observability", "configure", "prometheus", "--url", $PrometheusUrl, "--file", $Config, "--service-label", "deployment")
Invoke-Qmind -Arguments @("observability", "status")
Write-Host "QMind observability configured and status command completed."

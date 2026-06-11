param(
    [string]$FrontendUrl,
    [string]$OutputDir = "benchmark-runs/baseline-validation",
    [string]$Project = "chromium",
    [int]$Workers = 2
)

$ErrorActionPreference = "Stop"

if ([string]::IsNullOrWhiteSpace($FrontendUrl)) {
    [Console]::Error.WriteLine("FrontendUrl is required. Example: powershell -ExecutionPolicy Bypass -File benchmark-pipeline/run-baseline-validation.ps1 -FrontendUrl http://YOUR_FRONTEND_URL")
    exit 2
}

$originalLocation = Get-Location
$scriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path
$repoRoot = Split-Path -Parent $scriptDir
$playwrightDir = Join-Path $repoRoot "qmind-test-harness/playwright"

if (-not (Test-Path -LiteralPath $playwrightDir -PathType Container)) {
    [Console]::Error.WriteLine("Playwright harness directory not found: $playwrightDir")
    exit 2
}

if ([System.IO.Path]::IsPathRooted($OutputDir)) {
    $resolvedOutputDir = $OutputDir
} else {
    $resolvedOutputDir = Join-Path $repoRoot $OutputDir
}

New-Item -ItemType Directory -Force -Path $resolvedOutputDir | Out-Null

$junitOutput = Join-Path $resolvedOutputDir "playwright-junit.xml"
$jsonOutput = Join-Path $resolvedOutputDir "playwright-results.json"

$env:FRONTEND_URL = $FrontendUrl
$env:PLAYWRIGHT_JUNIT_OUTPUT_NAME = $junitOutput
$env:PLAYWRIGHT_JSON_OUTPUT_NAME = $jsonOutput

$exitCode = 0

try {
    Set-Location -LiteralPath $playwrightDir

    Write-Host "Running Online Boutique baseline validation"
    Write-Host "Frontend URL: $FrontendUrl"
    Write-Host "Playwright project: $Project"
    Write-Host "Playwright workers: $Workers"
    Write-Host "Output directory: $resolvedOutputDir"
    Write-Host ""

    & npx playwright test "--project=$Project" "--workers=$Workers" "--reporter=json,junit"
    $exitCode = $LASTEXITCODE
} finally {
    Set-Location -LiteralPath $originalLocation

    Write-Host ""
    Write-Host "Baseline validation summary"
    Write-Host "Frontend URL: $FrontendUrl"
    Write-Host "Playwright project: $Project"
    Write-Host "Playwright workers: $Workers"
    Write-Host "JUnit XML: $junitOutput"
    Write-Host "JSON report: $jsonOutput"
    Write-Host "Exit code: $exitCode"
}

exit $exitCode

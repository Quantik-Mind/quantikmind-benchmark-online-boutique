param(
    [string]$EnvFile = ".env",
    [string]$BenchmarkCase,
    [string]$Scenarios = "benchmark-pipeline/scenarios.json",
    [string]$ChangedFilesFile,
    [string]$RunDir = "benchmark-runs/qmind-online-boutique",
    [string]$SelectionOutput,
    [string]$Library = "qmind-test-library/online-boutique-playwright-51.json",
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

function Assert-ChangedFilesArray {
    param([string]$Path)

    if (-not (Test-Path -LiteralPath $Path -PathType Leaf)) {
        throw "Missing changed-files file after write: $Path"
    }

    try {
        $raw = Get-Content -LiteralPath $Path -Raw
        $parsed = $raw | ConvertFrom-Json
    } catch {
        throw "Changed files file must contain valid JSON: $Path"
    }

    if ($null -eq $parsed) {
        throw "Changed files file must contain a JSON array of paths: $Path"
    }

    if ($parsed -is [System.Management.Automation.PSCustomObject]) {
        throw "Changed files file must contain a JSON array of paths, not an object: $Path"
    }

    $items = @($parsed)

    if ($items.Count -eq 0) {
        throw "Changed files file must contain at least one path: $Path"
    }

    foreach ($item in $items) {
        if ($item -isnot [string] -or [string]::IsNullOrWhiteSpace($item)) {
            throw "Changed files file must contain only non-empty string paths: $Path"
        }
    }
}

function Get-TestId {
    param([object]$Test)

    foreach ($key in @("test_id", "id", "name", "title")) {
        if ($null -ne $Test.$key -and -not [string]::IsNullOrWhiteSpace([string]$Test.$key)) {
            return [string]$Test.$key
        }
    }
    return $null
}

function Get-CanonicalLibraryIds {
    param([string]$Path)

    if (-not (Test-Path -LiteralPath $Path -PathType Leaf)) {
        throw "Missing canonical test library for QMind validation: $Path"
    }

    $libraryData = Get-Content -LiteralPath $Path -Raw | ConvertFrom-Json
    $tests = @($libraryData.tests)
    if ($tests.Count -eq 0) {
        throw "Canonical test library has no tests: $Path"
    }

    $ids = @($tests | ForEach-Object { Get-TestId $_ } | Where-Object { $_ } | Sort-Object -Unique)
    if ($ids.Count -eq 0) {
        throw "Canonical test library has no canonical test IDs: $Path"
    }
    return $ids
}

function Get-ObjectPropertyValue {
    param(
        [object]$Object,
        [string]$Name
    )

    if ($null -eq $Object) {
        return $null
    }

    $property = $Object.PSObject.Properties[$Name]
    if ($null -eq $property) {
        return $null
    }
    return $property.Value
}

function Get-NumericObjectPropertyValue {
    param(
        [object]$Object,
        [string]$Name
    )

    $value = Get-ObjectPropertyValue $Object $Name
    if ($null -eq $value -or [string]::IsNullOrWhiteSpace([string]$value)) {
        return $null
    }

    try {
        return [double]$value
    }
    catch {
        return $null
    }
}

function ConvertFrom-QMindJsonText {
    param([string]$Text)

    if ([string]::IsNullOrWhiteSpace($Text)) {
        return $null
    }

    try {
        return $Text | ConvertFrom-Json
    }
    catch {
        $start = $Text.IndexOf("{")
        $end = $Text.LastIndexOf("}")
        if ($start -lt 0 -or $end -le $start) {
            return $null
        }

        try {
            return $Text.Substring($start, $end - $start + 1) | ConvertFrom-Json
        }
        catch {
            return $null
        }
    }
}

function Add-PropertyIfPresent {
    param(
        [System.Collections.Specialized.OrderedDictionary]$Target,
        [string]$Name,
        [object]$Value
    )

    if ($null -ne $Value) {
        $Target[$Name] = $Value
    }
}

$caseId = $null
if (-not [string]::IsNullOrWhiteSpace($BenchmarkCase)) {
    $caseId = $BenchmarkCase.ToUpperInvariant()
    if ($caseId -notmatch "^OB-\d{3}$") {
        throw "BenchmarkCase must look like OB-001 through OB-007. Found: $BenchmarkCase"
    }
    if (-not (Test-Path -LiteralPath $Scenarios -PathType Leaf)) {
        throw "Missing scenarios file: $Scenarios"
    }

    $scenarioData = Get-Content -LiteralPath $Scenarios -Raw | ConvertFrom-Json
    $scenario = @($scenarioData.scenarios | Where-Object { [string]$_.id -eq $caseId })
    if ($scenario.Count -ne 1) {
        throw "Benchmark case $caseId not found in $Scenarios"
    }

    $changedFiles = @($scenario[0].expected_changed_files | ForEach-Object { [string]$_ })
    if ($changedFiles.Count -eq 0) {
        throw "Benchmark case $caseId has no expected_changed_files in $Scenarios"
    }

    $caseSlug = $caseId.ToLowerInvariant()
    $ChangedFilesFile = "benchmark-runs/scenario-$caseSlug-changed-files.json"
    if ([string]::IsNullOrWhiteSpace($SelectionOutput)) {
        $SelectionOutput = Join-Path $RunDir "qmind-selection-$caseSlug.json"
    }

    $changedFilesPayload = ConvertTo-Json -InputObject @($changedFiles) -Depth 5
    Write-TextUtf8NoBom -Path $ChangedFilesFile -Text ($changedFilesPayload + [Environment]::NewLine)
    Assert-ChangedFilesArray -Path $ChangedFilesFile
}

if ([string]::IsNullOrWhiteSpace($SelectionOutput)) {
    throw "SelectionOutput is required when BenchmarkCase is not provided. Use -BenchmarkCase OB-001 through OB-006 for benchmark reproduction."
}

if ([string]::IsNullOrWhiteSpace($ChangedFilesFile)) {
    throw "ChangedFilesFile is required when BenchmarkCase is not provided. Use -BenchmarkCase OB-001 through OB-006 for benchmark reproduction."
}

$envValues = Read-DotEnv -Path $EnvFile
Assert-QmindConfig -Values $envValues

if (-not (Test-Path -LiteralPath $ChangedFilesFile -PathType Leaf)) {
    throw "Missing changed-files scenario input: $ChangedFilesFile"
}
Assert-ChangedFilesArray -Path $ChangedFilesFile
New-Item -ItemType Directory -Force -Path $RunDir | Out-Null
$rawOutput = Join-Path $RunDir "qmind-subset-current.txt"
$args = @("subset", "--json", "--changed-files-file", $ChangedFilesFile)
Write-Host ("qmind " + ($args -join " "))

if ($DryRun) {
    Write-Host "Dry run complete; subset was not executed."
    exit 0
}

if (-not (Get-Command qmind -ErrorAction SilentlyContinue)) {
    throw "qmind CLI was not found on PATH. Install or activate the Quantik Mind CLI, then rerun this script."
}

$ErrorActionPreferenceBefore = $ErrorActionPreference
$ErrorActionPreference = "Continue"

$output = & qmind @args 2>&1
$exitCode = $LASTEXITCODE

$ErrorActionPreference = $ErrorActionPreferenceBefore
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
$qmindSubsetJson = ConvertFrom-QMindJsonText $text
$canonicalIds = @(Get-CanonicalLibraryIds $Library)
$selectedTests = @($selection.selected_tests | ForEach-Object { [string]$_ })
if ($selectedTests.Count -eq 0) {
    throw "QMind selection did not contain selected_tests after normalization: $SelectionOutput"
}
$unknown = @($selectedTests | Where-Object { $canonicalIds -notcontains $_ })
if ($unknown.Count -gt 0) {
    throw "QMind selection contains non-canonical test IDs: $($unknown -join ', ')"
}
if ($caseId -eq "OB-004" -and $selection.selected_tests -notcontains "payment-order-completion-confirms-success") {
    throw "QMind selection is missing required detector: payment-order-completion-confirms-success"
}

$businessMetrics = Get-ObjectPropertyValue $selection "business_metrics"
$canonicalBusinessMetrics = [ordered]@{}
foreach ($field in @("risk_coverage", "top_risk_coverage", "residual_risk", "risk_efficiency")) {
    $value = Get-NumericObjectPropertyValue $businessMetrics $field
    if ($null -eq $value) {
        $value = Get-NumericObjectPropertyValue $selection $field
    }
    Add-PropertyIfPresent $canonicalBusinessMetrics $field $value
}

$canonicalPayload = [ordered]@{
    method = "qmind"
    benchmark_case = $caseId
    changed_files_file = $ChangedFilesFile
    selected_tests = @($selectedTests | Sort-Object)
}

foreach ($field in @("risk_coverage", "risk_efficiency")) {
    $value = Get-NumericObjectPropertyValue $selection $field
    Add-PropertyIfPresent $canonicalPayload $field $value
}
if ($canonicalBusinessMetrics.Count -gt 0) {
    $canonicalPayload["business_metrics"] = $canonicalBusinessMetrics
}
if ($null -ne $qmindSubsetJson) {
    $canonicalPayload["qmind_subset_json"] = $qmindSubsetJson
}

$canonicalPayload = $canonicalPayload | ConvertTo-Json -Depth 30
Write-TextUtf8NoBom -Path $SelectionOutput -Text ($canonicalPayload + [Environment]::NewLine)

$bytes = [System.IO.File]::ReadAllBytes((Join-Path (Get-Location) $SelectionOutput))
if ($bytes.Length -ge 3 -and $bytes[0] -eq 239 -and $bytes[1] -eq 187 -and $bytes[2] -eq 191) {
    throw "Selection output has a UTF-8 BOM: $SelectionOutput"
}

Write-Host "Wrote canonical QMind selection to $SelectionOutput."

param(
    [string]$Case = "",
    [string]$GodotBin = "C:\_work\Godot_v4.6.3\Godot_v4.6.3-stable_win64_console.exe",
    [int]$TimeoutSeconds = 180,
    [switch]$SkipNegative
)

$ErrorActionPreference = "Continue"

$projectRoot = Split-Path -Parent (Split-Path -Parent $PSScriptRoot)
Set-Location $projectRoot

function Invoke-GodotProcess {
    param(
        [string]$Binary,
        [string[]]$ArgumentList,
        [int]$TimeoutSec
    )
    if (-not (Test-Path $Binary)) {
        return @{
            Finished = $false
            ExitCode = 1
            Timeout = $false
            Error = "Godot binary not found: $Binary"
        }
    }
    $formattedArgs = @()
    foreach ($arg in $ArgumentList) {
        if ($arg -match '[\s"]') {
            $formattedArgs += '"{0}"' -f ($arg -replace '"', '\"')
        } else {
            $formattedArgs += $arg
        }
    }
    $psi = New-Object System.Diagnostics.ProcessStartInfo
    $psi.FileName = $Binary
    $psi.Arguments = ($formattedArgs -join " ")
    $psi.UseShellExecute = $false
    $psi.CreateNoWindow = $true
    $process = [System.Diagnostics.Process]::Start($psi)
    $finished = $process.WaitForExit($TimeoutSec * 1000)
    if (-not $finished) {
        try { $process.Kill() } catch {}
        return @{
            Finished = $false
            ExitCode = -1
            Timeout = $true
            Error = "Timeout ($TimeoutSec s)"
        }
    }
    $process.WaitForExit()
    return @{
        Finished = $true
        ExitCode = $process.ExitCode
        Timeout = $false
        Error = ""
    }
}

function Read-JsonFile {
    param([string]$Path)
    if (-not (Test-Path $Path)) {
        return $null
    }
    try {
        return Get-Content -Path $Path -Raw -Encoding utf8 | ConvertFrom-Json
    } catch {
        return $null
    }
}

function Invoke-NegativeTests {
    param(
        [string]$RunDir,
        [string]$StatesDir,
        [string]$GodotBinary,
        [int]$TimeoutSec
    )

    $negativeDir = Join-Path $RunDir "negative"
    New-Item -ItemType Directory -Force -Path $negativeDir | Out-Null
    $validState = Join-Path $StatesDir "d2_morning.json"
    $validJson = Get-Content -Path $validState -Raw -Encoding utf8
    $validObject = $validJson | ConvertFrom-Json

    $malformedPath = Join-Path $negativeDir "malformed.json"
    Set-Content -Path $malformedPath -Value "{ not-json" -Encoding utf8

    $shapePath = Join-Path $negativeDir "invalid-shape.json"
    Set-Content -Path $shapePath -Value '{"run":{}}' -Encoding utf8

    $badDay = $validObject | ConvertTo-Json -Depth 30
    $badDayObject = $badDay | ConvertFrom-Json
    $badDayObject.run.day = 46
    $badDayPath = Join-Path $negativeDir "invalid-day.json"
    $badDayObject | ConvertTo-Json -Depth 30 | Set-Content -Path $badDayPath -Encoding utf8

    $badPhaseObject = $validJson | ConvertFrom-Json
    $badPhaseObject.run.phase = "invalid"
    $badPhasePath = Join-Path $negativeDir "invalid-phase.json"
    $badPhaseObject | ConvertTo-Json -Depth 30 | Set-Content -Path $badPhasePath -Encoding utf8

    $negativeDefs = @(
        @{ Id = "missing_state"; CaseId = "p1af_08_map_filter"; State = (Join-Path $negativeDir "missing.json"); IncludeRunDir = $true },
        @{ Id = "malformed_json"; CaseId = "p1af_08_map_filter"; State = $malformedPath; IncludeRunDir = $true },
        @{ Id = "invalid_shape"; CaseId = "p1af_08_map_filter"; State = $shapePath; IncludeRunDir = $true },
        @{ Id = "invalid_day"; CaseId = "p1af_08_map_filter"; State = $badDayPath; IncludeRunDir = $true },
        @{ Id = "invalid_phase"; CaseId = "p1af_08_map_filter"; State = $badPhasePath; IncludeRunDir = $true },
        @{ Id = "unknown_case"; CaseId = "case_does_not_exist"; State = ""; IncludeRunDir = $true },
        @{ Id = "missing_run_dir"; CaseId = "p1af_08_map_filter"; State = $validState; IncludeRunDir = $false }
    )

    $results = @()
    foreach ($negative in $negativeDefs) {
        $logPath = Join-Path $negativeDir ($negative.Id + ".log")
        $args = @(
            "--path", ".",
            "--script", "res://tests/ui_sim/qa_runner.gd",
            "--log-file", $logPath,
            "--",
            "--case", $negative.CaseId
        )
        if (-not [string]::IsNullOrEmpty($negative.State)) {
            $args += @("--state", $negative.State)
        }
        if ($negative.IncludeRunDir) {
            $args += @("--run-dir", $RunDir)
        }
        $runResult = Invoke-GodotProcess -Binary $GodotBinary -ArgumentList $args -TimeoutSec $TimeoutSec
        $logText = if (Test-Path $logPath) { Get-Content -Path $logPath -Raw -Encoding utf8 } else { "" }
        $leak = $logText -match "ObjectDB instances leaked|resources still in use"
        $ok = (-not $runResult.Timeout) -and ($runResult.ExitCode -ne 0) -and (-not $leak)
        $error = ""
        if ($runResult.Timeout) {
            $error = "unexpected timeout"
        } elseif ($runResult.ExitCode -eq 0) {
            $error = "invalid input unexpectedly exited 0"
        } elseif ($leak) {
            $error = "lifecycle warning leaked into negative diagnostic"
        }
        $results += [pscustomobject]@{
            Id = $negative.Id
            Ok = $ok
            ExitCode = $runResult.ExitCode
            Error = $error
        }
    }
    return $results
}

$runId = (Get-Date).ToString("yyyyMMdd-HHmmss-fff")
$qaDir = Join-Path $projectRoot "_qa"
$runDir = Join-Path $qaDir "runs\$runId"
$statesDir = Join-Path $runDir "states"
$dataVariantsDir = Join-Path $runDir "data_variants"

New-Item -ItemType Directory -Force -Path $statesDir | Out-Null
New-Item -ItemType Directory -Force -Path (Join-Path $runDir "dumps") | Out-Null
New-Item -ItemType Directory -Force -Path (Join-Path $runDir "shots") | Out-Null
New-Item -ItemType Directory -Force -Path (Join-Path $runDir "reports") | Out-Null
New-Item -ItemType Directory -Force -Path $dataVariantsDir | Out-Null

$gdignore = Join-Path $qaDir ".gdignore"
if (-not (Test-Path $gdignore)) {
    Set-Content -Path $gdignore -Value "" -Encoding utf8
}

Write-Host "=== ReturnFare UI Simulation Runner ===" -ForegroundColor Cyan
Write-Host "  Run ID:    $runId"
Write-Host "  Run Dir:   $runDir"
Write-Host "  Timeout:   $TimeoutSeconds s per process"

Write-Host ""
Write-Host "[1/4] Generating scenario states..." -ForegroundColor Yellow
$stateGenLog = Join-Path $runDir "make_states.log"
$stateArgs = @(
    "--headless",
    "--path", ".",
    "--script", "res://tests/ui_sim/make_states.gd",
    "--log-file", $stateGenLog,
    "--",
    "--output-dir", $statesDir
)
$stateRes = Invoke-GodotProcess -Binary $GodotBin -ArgumentList $stateArgs -TimeoutSec $TimeoutSeconds
if ($stateRes.Timeout -or $stateRes.ExitCode -ne 0) {
    Write-Host "ERROR: State generation failed (exit $($stateRes.ExitCode))." -ForegroundColor Red
    exit 1
}

Write-Host "[2/4] Creating isolated data variants and runner manifest..." -ForegroundColor Yellow
$dataSource = Join-Path $projectRoot "data"
$defaultData = Join-Path $dataVariantsDir "hand_size_default"
$smallData = Join-Path $dataVariantsDir "hand_size_small"
$locationDescData = Join-Path $dataVariantsDir "location_desc_positive"
Copy-Item -Path $dataSource -Destination $defaultData -Recurse -Force
Copy-Item -Path $dataSource -Destination $smallData -Recurse -Force
Copy-Item -Path $dataSource -Destination $locationDescData -Recurse -Force
$smallTuningPath = Join-Path $smallData "tuning.json"
$smallTuning = Get-Content -Path $smallTuningPath -Raw -Encoding utf8 | ConvertFrom-Json
$smallTuning.hand_size = 7
$smallTuning | ConvertTo-Json -Depth 30 | Set-Content -Path $smallTuningPath -Encoding utf8
$locationDescPath = Join-Path $locationDescData "locations.json"
$locationData = Get-Content -Path $locationDescPath -Raw -Encoding utf8 | ConvertFrom-Json
foreach ($location in @($locationData.day)) {
    if ([string]$location.id -eq "sanquan") {
        $location | Add-Member -MemberType NoteProperty -Name "desc" -Value "QA fixture description" -Force
    }
}
$locationData | ConvertTo-Json -Depth 30 | Set-Content -Path $locationDescPath -Encoding utf8

$manifestPath = Join-Path $runDir "case-manifest.json"
$manifestLog = Join-Path $runDir "case-manifest.log"
$manifestArgs = @(
    "--path", ".",
    "--script", "res://tests/ui_sim/qa_runner.gd",
    "--log-file", $manifestLog,
    "--",
    "--list-cases",
    "--output", $manifestPath
)
$manifestRes = Invoke-GodotProcess -Binary $GodotBin -ArgumentList $manifestArgs -TimeoutSec $TimeoutSeconds
if ($manifestRes.Timeout -or $manifestRes.ExitCode -ne 0) {
    Write-Host "ERROR: Case manifest generation failed." -ForegroundColor Red
    exit 1
}
$manifest = Read-JsonFile $manifestPath
if ($null -eq $manifest -or $null -eq $manifest.cases) {
    Write-Host "ERROR: Case manifest is missing or invalid." -ForegroundColor Red
    exit 1
}
$allCaseDefs = @($manifest.cases)
$contractCount = @($allCaseDefs | ForEach-Object { $_.contract_id } | Sort-Object -Unique).Count
if ($contractCount -ne 47) {
    Write-Host "ERROR: Runner contract count is $contractCount, expected 47." -ForegroundColor Red
    exit 1
}
$caseDefs = $allCaseDefs
if (-not [string]::IsNullOrEmpty($Case)) {
    $caseDefs = @($allCaseDefs | Where-Object { $_.id -eq $Case })
    if ($caseDefs.Count -eq 0) {
        Write-Host "ERROR: Case not found: $Case" -ForegroundColor Red
        exit 1
    }
}

Write-Host "[3/4] Executing $($caseDefs.Count) UI variants ($contractCount contracts)..." -ForegroundColor Yellow
$results = @()
$failedCount = 0
foreach ($caseDef in $caseDefs) {
    $caseId = [string]$caseDef.id
    $caseDesc = [string]$caseDef.description
    $stateFile = ""
    if (-not [string]::IsNullOrEmpty([string]$caseDef.required_state)) {
        $stateFile = Join-Path $statesDir ([string]$caseDef.required_state)
        if (-not (Test-Path $stateFile)) {
            Write-Host "  -> [$caseId] missing state" -ForegroundColor Red
            $failedCount++
            $results += [pscustomobject]@{ Id = $caseId; ContractId = $caseDef.contract_id; Ok = $false; ExitCode = 1; Errors = @("state file missing: $stateFile") }
            continue
        }
    }

    $caseLog = Join-Path $runDir "reports\$caseId.log"
    Write-Host "  -> Running [$caseId] ($caseDesc)... " -NoNewline
    $caseArgs = @(
        "--path", ".",
        "--script", "res://tests/ui_sim/qa_runner.gd",
        "--log-file", $caseLog,
        "--",
        "--case", $caseId,
        "--run-dir", $runDir
    )
    if (-not [string]::IsNullOrEmpty($stateFile)) {
        $caseArgs += @("--state", $stateFile)
    }
    if (-not [string]::IsNullOrEmpty([string]$caseDef.required_data_root)) {
        $variantPath = Join-Path $dataVariantsDir ([string]$caseDef.required_data_root)
        $caseArgs += @("--data-root", $variantPath)
    }

    $runResult = Invoke-GodotProcess -Binary $GodotBin -ArgumentList $caseArgs -TimeoutSec $TimeoutSeconds
    $reportPath = Join-Path $runDir "reports\$caseId.json"
    $report = Read-JsonFile $reportPath
    $caseOk = ($null -ne $report) -and [bool]$report.ok -and (-not $runResult.Timeout) -and ($runResult.ExitCode -eq 0)
    $caseErrors = @()
    if ($null -eq $report) {
        $caseErrors += "report file missing or invalid: $reportPath"
    } elseif ($report.errors) {
        $caseErrors = @($report.errors)
    }
    if ($runResult.Timeout) {
        $caseErrors += "Timeout ($TimeoutSeconds s)"
    }
    if ($caseOk) {
        Write-Host "OK" -ForegroundColor Green
    } else {
        Write-Host "FAIL (Exit code: $($runResult.ExitCode))" -ForegroundColor Red
        foreach ($errorText in $caseErrors) {
            Write-Host "     - $errorText" -ForegroundColor Red
        }
        $failedCount++
    }
    $results += [pscustomobject]@{
        Id = $caseId
        ContractId = [string]$caseDef.contract_id
        ComparisonGroup = [string]$caseDef.comparison_group
        Ok = $caseOk
        ExitCode = $runResult.ExitCode
        Errors = $caseErrors
    }
}

$comparisonResults = @()
$comparisonFailures = 0
$groups = @($caseDefs | Where-Object { -not [string]::IsNullOrEmpty([string]$_.comparison_group) } | Group-Object comparison_group)
foreach ($group in $groups) {
    $groupReports = @()
    foreach ($member in $group.Group) {
        $path = Join-Path $runDir "reports\$([string]$member.id).json"
        $memberReport = Read-JsonFile $path
        if ($null -ne $memberReport) {
            $groupReports += $memberReport
        }
    }
    $signatures = @($groupReports | ForEach-Object {
        if ($null -eq $_.observations.state_without_hand) { "" } else { $_.observations.state_without_hand | ConvertTo-Json -Compress -Depth 30 }
    } | Sort-Object -Unique)
    $same = ($groupReports.Count -eq $group.Group.Count) -and ($signatures.Count -eq 1) -and (-not [string]::IsNullOrEmpty($signatures[0]))
    $comparisonResults += [pscustomobject]@{ Group = $group.Name; Ok = $same; Cases = @($group.Group.id) }
    if (-not $same) {
        $comparisonFailures++
        Write-Host "  -> Comparison [$($group.Name)] FAIL" -ForegroundColor Red
    } else {
        Write-Host "  -> Comparison [$($group.Name)] OK" -ForegroundColor Green
    }
}

$negativeResults = @()
if ([string]::IsNullOrEmpty($Case) -and -not $SkipNegative) {
    Write-Host "[4/4] Executing formal negative tests..." -ForegroundColor Yellow
    $negativeResults = @(Invoke-NegativeTests -RunDir $runDir -StatesDir $statesDir -GodotBinary $GodotBin -TimeoutSec $TimeoutSeconds)
    foreach ($negative in $negativeResults) {
        if ($negative.Ok) {
            Write-Host "  -> Negative [$($negative.Id)] OK (expected failure)" -ForegroundColor Green
        } else {
            Write-Host "  -> Negative [$($negative.Id)] FAIL: $($negative.Error)" -ForegroundColor Red
        }
    }
} else {
    Write-Host "[4/4] Negative tests skipped." -ForegroundColor DarkGray
}

$negativeFailures = @($negativeResults | Where-Object { -not $_.Ok }).Count
$totalFailures = $failedCount + $comparisonFailures + $negativeFailures
$summary = [ordered]@{
    RunId = $runId
    Timestamp = (Get-Date).ToString("o")
    VariantCount = $caseDefs.Count
    ContractCount = $contractCount
    PassedVariants = $caseDefs.Count - $failedCount
    FailedVariants = $failedCount
    ComparisonFailures = $comparisonFailures
    NegativeFailures = $negativeFailures
    TotalFailures = $totalFailures
    Results = $results
    ComparisonResults = $comparisonResults
    NegativeTests = $negativeResults
}
$summaryPath = Join-Path $runDir "report.json"
$summary | ConvertTo-Json -Depth 30 | Set-Content -Path $summaryPath -Encoding utf8

Write-Host "=========================================" -ForegroundColor Cyan
Write-Host "UI Simulation Summary: variants $($caseDefs.Count), contracts $contractCount, failed checks $totalFailures"
Write-Host "Report saved to: $summaryPath"
Write-Host "=========================================" -ForegroundColor Cyan
if ($totalFailures -gt 0) {
    exit 1
}
exit 0

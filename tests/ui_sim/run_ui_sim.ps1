param(
    [string]$Case = "",
    [string]$GodotBin = "C:\_work\Godot_v4.6.3\Godot_v4.6.3-stable_win64_console.exe",
    [int]$TimeoutSeconds = 30
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
        Write-Host "ERROR: Godot binary not found at '$Binary'" -ForegroundColor Red
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
    $p = [System.Diagnostics.Process]::Start($psi)
    $finished = $p.WaitForExit($TimeoutSec * 1000)
    if (-not $finished) {
        try { $p.Kill() } catch {}
        return @{
            Finished = $false
            ExitCode = -1
            Timeout = $true
            Error = "Timeout ($TimeoutSec s)"
        }
    }
    $p.WaitForExit()
    return @{
        Finished = $true
        ExitCode = $p.ExitCode
        Timeout = $false
        Error = ""
    }
}

# 1. Setup run directories (with millisecond precision)
$runId = (Get-Date).ToString("yyyyMMdd-HHmmss-fff")
$qaDir = Join-Path $projectRoot "_qa"
$runDir = Join-Path $qaDir "runs\$runId"
$statesDir = Join-Path $runDir "states"

New-Item -ItemType Directory -Force -Path $statesDir | Out-Null
New-Item -ItemType Directory -Force -Path (Join-Path $runDir "dumps") | Out-Null
New-Item -ItemType Directory -Force -Path (Join-Path $runDir "shots") | Out-Null
New-Item -ItemType Directory -Force -Path (Join-Path $runDir "reports") | Out-Null

$gdignore = Join-Path $qaDir ".gdignore"
if (-not (Test-Path $gdignore)) {
    Set-Content -Path $gdignore -Value ""
}

Write-Host "=== ReturnFare UI Simulation Runner ===" -ForegroundColor Cyan
Write-Host "  Run ID:    $runId"
Write-Host "  Run Dir:   $runDir"

# 2. Generate scenario states
Write-Host "`n[1/3] Generating scenario states (make_states.gd)..." -ForegroundColor Yellow
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
if ($stateRes.Timeout) {
    Write-Host "ERROR: State generator timed out! ($TimeoutSeconds s)" -ForegroundColor Red
    exit 1
}
if ($stateRes.ExitCode -ne 0) {
    Write-Host "ERROR: Failed to generate scenario states! Exit code: $($stateRes.ExitCode)" -ForegroundColor Red
    exit 1
}
Write-Host "  Scenario states generated successfully." -ForegroundColor Green

# 3. Case definitions (17 variants covering all P1-G requirements)
$caseDefs = @(
    @{ Id = "p1g_case_01a_beats_ajie"; State = "d32_morning__ajie.json"; Desc = "Beats play one by one (Ajie invited)" },
    @{ Id = "p1g_case_01b_beats_alone"; State = "d32_morning__none.json"; Desc = "Beats play one by one (No invite)" },
    @{ Id = "p1g_case_02_lock_interaction_during_play"; State = "d32_morning__ajie.json"; Desc = "Lock interaction during play" },
    @{ Id = "p1g_case_03_reenter_no_duplicate_on_enter"; State = "d17_morning.json"; Desc = "Reenter no duplicate on_enter" },
    @{ Id = "p1g_case_04_slot_types"; State = "d22_afternoon.json"; Desc = "Slot type indicator (all 4 slots)" },
    @{ Id = "p1g_case_05_protagonist_slot_type"; State = "d22_afternoon.json"; Desc = "Protagonist slot type indicator" },
    @{ Id = "p1g_case_06_no_spoiler"; State = "d22_afternoon.json"; Desc = "No spoiler for specific card accepts" },
    @{ Id = "p1g_case_07_right_click_preview"; State = "d22_afternoon.json"; Desc = "Right click preview state unchanged" },
    @{ Id = "p1g_case_08_right_click_locked_preview"; State = "d22_afternoon.json"; Desc = "Right click locked slot preview with reason" },
    @{ Id = "p1g_case_09_preview_button_match_right_click"; State = "d22_afternoon.json"; Desc = "Preview button matches right click verbatim" },
    @{ Id = "p1g_case_10_preview_placement_consistent_positive"; State = "d22_afternoon.json"; Desc = "Preview placement positive" },
    @{ Id = "p1g_case_11_preview_placement_consistent_negative"; State = "d22_afternoon.json"; Desc = "Preview placement negative" },
    @{ Id = "p1g_case_12a_advance_d35"; State = "d35_afternoon.json"; Desc = "Advance hint (D35 choice-only)" },
    @{ Id = "p1g_case_12b_advance_d40"; State = "d40_morning.json"; Desc = "Advance hint (D40 choice-only)" },
    @{ Id = "p1g_case_12c_advance_d43"; State = "d43_afternoon.json"; Desc = "Advance hint (D43 choice-only)" },
    @{ Id = "p1g_case_13_night_same_model"; State = "d10_night.json"; Desc = "Night same interaction model" },
    @{ Id = "p1g_case_14_location_desc"; State = "d2_morning.json"; Desc = "Location desc fallback" }
)

if ($Case -ne "") {
    $caseDefs = @($caseDefs | Where-Object { $_.Id -eq $Case })
    if ($caseDefs.Count -eq 0) {
        Write-Host "ERROR: Case not found: $Case" -ForegroundColor Red
        exit 1
    }
}

Write-Host "`n[2/3] Executing test cases (Total: $($caseDefs.Count))..." -ForegroundColor Yellow

$results = @()
$failedCount = 0

foreach ($c in $caseDefs) {
    $cId = $c.Id
    $cDesc = $c.Desc
    $stateFile = Join-Path $statesDir $c.State
    $caseLog = Join-Path $runDir "reports\$cId.log"

    Write-Host "  -> Running [$cId] ($cDesc)... " -NoNewline

    $caseArgs = @(
        "--path", ".",
        "--script", "res://tests/ui_sim/qa_runner.gd",
        "--log-file", $caseLog,
        "--",
        "--case", $cId,
        "--state", $stateFile,
        "--run-dir", $runDir
    )

    $runRes = Invoke-GodotProcess -Binary $GodotBin -ArgumentList $caseArgs -TimeoutSec $TimeoutSeconds

    if ($runRes.Timeout) {
        Write-Host "TIMEOUT" -ForegroundColor Red
        $failedCount++
        $results += @{ Id = $cId; Ok = $false; Errors = @("Timeout ($TimeoutSeconds s)"); ExitCode = -1 }
        continue
    }

    $exitCode = $runRes.ExitCode
    $repJsonPath = Join-Path $runDir "reports\$cId.json"
    $caseOk = $false
    $caseErrors = @()

    if (Test-Path $repJsonPath) {
        try {
            $repObj = Get-Content -Path $repJsonPath -Raw -Encoding utf8 | ConvertFrom-Json
            $caseOk = [bool]$repObj.ok
            if ($repObj.errors) {
                $caseErrors = @($repObj.errors)
            }
        } catch {
            $caseOk = $false
            $caseErrors = @("Failed to parse report JSON: $_")
        }
    } else {
        $caseOk = $false
        $caseErrors = @("Report file not found: $repJsonPath")
    }

    if ($caseOk -and $exitCode -eq 0) {
        Write-Host "OK" -ForegroundColor Green
        $results += @{ Id = $cId; Ok = $true; Errors = @(); ExitCode = 0 }
    } else {
        Write-Host "FAIL (Exit code: $exitCode)" -ForegroundColor Red
        if ($caseErrors.Count -gt 0) {
            foreach ($err in $caseErrors) {
                Write-Host "     - $err" -ForegroundColor Red
            }
        }
        $failedCount++
        $results += @{ Id = $cId; Ok = $false; Errors = $caseErrors; ExitCode = $exitCode }
    }
}

# 4. Generate report.json
Write-Host "`n[3/3] Aggregating report..." -ForegroundColor Yellow
$reportData = @{
    RunId = $runId
    Timestamp = (Get-Date).ToString("o")
    TotalCases = $caseDefs.Count
    PassedCases = $caseDefs.Count - $failedCount
    FailedCases = $failedCount
    Results = $results
}

$summaryJson = Join-Path $runDir "report.json"
$reportData | ConvertTo-Json -Depth 5 | Set-Content -Path $summaryJson -Encoding utf8

Write-Host "========================================="
Write-Host "UI Simulation Summary: Total $($caseDefs.Count), Passed $($caseDefs.Count - $failedCount), Failed $failedCount"
Write-Host "Report saved to: $summaryJson"
Write-Host "========================================="

if ($failedCount -gt 0) {
    exit 1
} else {
    exit 0
}

param(
    [string]$Case = "",
    [string]$GodotBin = "C:\_work\Godot_v4.6.3\Godot_v4.6.3-stable_win64_console.exe",
    [int]$TimeoutSeconds = 30
)

$ErrorActionPreference = "Stop"

$projectRoot = Split-Path -Parent (Split-Path -Parent $PSScriptRoot)
Set-Location $projectRoot

# 1. Setup run directories
$runId = (Get-Date).ToString("yyyyMMdd-HHmmss")
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
    "--",
    "--output-dir", $statesDir
)

$proc = Start-Process -FilePath $GodotBin -ArgumentList $stateArgs -NoNewWindow -PassThru -Wait
if ($proc.ExitCode -ne 0) {
    Write-Host "ERROR: Failed to generate scenario states! Exit code: $($proc.ExitCode)" -ForegroundColor Red
    exit 1
}
Write-Host "  Scenario states generated successfully." -ForegroundColor Green

# 3. Case definitions
$caseDefs = @(
    @{ Id = "p1g_case_04_slot_types"; State = "d22_afternoon.json"; Desc = "Slot type indicator (equip, info)" },
    @{ Id = "p1g_case_05_protagonist_slot_type"; State = "d3_afternoon.json"; Desc = "Protagonist slot type indicator" },
    @{ Id = "p1g_case_06_no_spoiler"; State = "d3_afternoon.json"; Desc = "No spoiler for specific card accepts" },
    @{ Id = "p1g_case_07_right_click_preview"; State = "d22_afternoon.json"; Desc = "Right click preview state unchanged" },
    @{ Id = "p1g_case_08_right_click_locked_preview"; State = "d22_afternoon.json"; Desc = "Right click locked slot preview" },
    @{ Id = "p1g_case_09_preview_button_match_right_click"; State = "d22_afternoon.json"; Desc = "Preview button matches right click" },
    @{ Id = "p1g_case_10_preview_placement_consistent_positive"; State = "d22_afternoon.json"; Desc = "Preview placement positive" },
    @{ Id = "p1g_case_11_preview_placement_consistent_negative"; State = "d22_afternoon.json"; Desc = "Preview placement negative" },
    @{ Id = "p1g_case_01_beats_play_one_by_one"; State = "d32_morning__ajie.json"; Desc = "Beats play one by one" },
    @{ Id = "p1g_case_02_lock_interaction_during_play"; State = "d32_morning__ajie.json"; Desc = "Lock interaction during play" },
    @{ Id = "p1g_case_03_reenter_no_duplicate_on_enter"; State = "d17_morning.json"; Desc = "Reenter no duplicate on_enter" },
    @{ Id = "p1g_case_12_advance_hint"; State = "d35_afternoon.json"; Desc = "Advance hint" },
    @{ Id = "p1g_case_13_night_same_model"; State = "d10_night.json"; Desc = "Night same model" },
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

    $proc = Start-Process -FilePath $GodotBin -ArgumentList $caseArgs -NoNewWindow -PassThru -Wait
    $exitCode = $proc.ExitCode

    $repJsonPath = Join-Path $runDir "reports\$cId.json"
    $caseOk = $false
    $caseErrors = @()

    if (Test-Path $repJsonPath) {
        try {
            $repObj = Get-Content -Path $repJsonPath -Raw -Encoding utf8 | ConvertFrom-Json
            $caseOk = [bool]$repObj.ok
            if (-not $caseOk -and $repObj.errors) {
                $caseErrors = $repObj.errors
            }
        } catch {
            $caseOk = ($exitCode -eq 0)
        }
    } else {
        $caseOk = ($exitCode -eq 0)
    }

    if ($exitCode -eq 0 -and $caseOk) {
        Write-Host "OK" -ForegroundColor Green
        $results += @{ Id = $cId; Ok = $true; Error = "" }
    } else {
        Write-Host "FAIL (Exit code: $exitCode)" -ForegroundColor Red
        if ($caseErrors.Count -gt 0) {
            foreach ($err in $caseErrors) {
                Write-Host "     - $err" -ForegroundColor Red
            }
        }
        $failedCount++
        $results += @{ Id = $cId; Ok = $false; Error = "Exit code $exitCode" }
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

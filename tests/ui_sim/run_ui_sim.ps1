param(
    [string]$Case = "",
    [string]$GodotBin = "C:\_work\Godot_v4.6.3\Godot_v4.6.3-stable_win64_console.exe",
    [int]$TimeoutSeconds = 180,
    [switch]$SkipNegative
)

$ErrorActionPreference = "Continue"

$projectRoot = Split-Path -Parent (Split-Path -Parent $PSScriptRoot)
Set-Location $projectRoot

function Get-OwnedProcessTree {
    param([int]$RootPid)
    $tree = New-Object System.Collections.Generic.List[int]
    if ($RootPid -le 0) { return $tree }
    $tree.Add($RootPid)
    try {
        $allProc = @(Get-CimInstance Win32_Process -ErrorAction SilentlyContinue)
        if ($allProc.Count -gt 0) {
            $queue = New-Object System.Collections.Generic.Queue[int]
            $queue.Enqueue($RootPid)
            while ($queue.Count -gt 0) {
                $curr = $queue.Dequeue()
                $children = @($allProc | Where-Object { $_.ParentProcessId -eq $curr })
                foreach ($c in $children) {
                    $cid = [int]$c.ProcessId
                    if (-not $tree.Contains($cid)) {
                        $tree.Add($cid)
                        $queue.Enqueue($cid)
                    }
                }
            }
        }
    } catch {}
    return $tree
}

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
            RootPid = 0
            CleanupError = ""
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

    $process = $null
    $rootPid = 0
    $timeoutOccurred = $false
    $finished = $false
    $exitCode = -1
    $errorMsg = ""
    $cleanupError = ""

    try {
        $process = [System.Diagnostics.Process]::Start($psi)
        if ($null -eq $process) {
            return @{
                Finished = $false
                ExitCode = 1
                Timeout = $false
                Error = "Failed to start Godot process: $Binary"
                RootPid = 0
                CleanupError = ""
            }
        }
        $rootPid = $process.Id
        $finished = $process.WaitForExit($TimeoutSec * 1000)
        if (-not $finished) {
            $timeoutOccurred = $true
            $errorMsg = "Timeout ($TimeoutSec s)"
        } else {
            $process.WaitForExit()
            $exitCode = $process.ExitCode
        }
    } catch {
        $errorMsg = $_.Exception.Message
    } finally {
        if ($rootPid -gt 0) {
            $ownedPids = Get-OwnedProcessTree -RootPid $rootPid
            $pidsToKill = @()
            foreach ($pidItem in ($ownedPids | Sort-Object -Descending)) {
                try {
                    $procObj = [System.Diagnostics.Process]::GetProcessById($pidItem)
                    if (-not $procObj.HasExited) {
                        $pidsToKill += $procObj
                    }
                } catch {}
            }
            if ($timeoutOccurred -or -not $finished -or $pidsToKill.Count -gt 0) {
                foreach ($procObj in $pidsToKill) {
                    try {
                        $procObj.Kill()
                    } catch {}
                }
            }

            $deadline = (Get-Date).AddSeconds(3)
            $stillAlive = @()
            do {
                $stillAlive = @()
                foreach ($pidItem in $ownedPids) {
                    try {
                        $procObj = [System.Diagnostics.Process]::GetProcessById($pidItem)
                        if (-not $procObj.HasExited) {
                            $stillAlive += $pidItem
                        }
                    } catch {}
                }
                if ($stillAlive.Count -eq 0) { break }
                Start-Sleep -Milliseconds 100
            } while ((Get-Date) -lt $deadline)

            if ($stillAlive.Count -gt 0) {
                $cleanupError = "Failed to terminate owned process(es): PID(s) $($stillAlive -join ', ')"
            }
        }
        if ($null -ne $process) {
            try { $process.Dispose() } catch {}
        }
    }

    if ($timeoutOccurred) {
        return @{
            Finished = $false
            ExitCode = -1
            Timeout = $true
            Error = $errorMsg
            RootPid = $rootPid
            CleanupError = $cleanupError
        }
    }

    if (-not [string]::IsNullOrEmpty($cleanupError)) {
        return @{
            Finished = $false
            ExitCode = if ($exitCode -ne 0) { $exitCode } else { 1 }
            Timeout = $false
            Error = if (-not [string]::IsNullOrEmpty($errorMsg)) { "$errorMsg; $cleanupError" } else { $cleanupError }
            RootPid = $rootPid
            CleanupError = $cleanupError
        }
    }

    return @{
        Finished = $finished
        ExitCode = $exitCode
        Timeout = $false
        Error = $errorMsg
        RootPid = $rootPid
        CleanupError = ""
    }
}

function Assert-NoExistingGodotProcesses {
    $existing = @(Get-CimInstance Win32_Process -Filter "Name LIKE 'Godot%'" -ErrorAction SilentlyContinue)
    if ($existing.Count -gt 0) {
        Write-Host "ERROR: Preflight detected $($existing.Count) running Godot process(es). Runner cannot proceed safely." -ForegroundColor Red
        foreach ($proc in $existing) {
            Write-Host ("  -> PID {0}: {1}`n     Command: {2}" -f $proc.ProcessId, $proc.ExecutablePath, $proc.CommandLine) -ForegroundColor Red
        }
        Write-Host "Please close or wait for existing Godot editor/test instances before starting UI simulation." -ForegroundColor Yellow
        exit 1
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

function New-IsolatedRunDirectory {
    param([string]$Root)
    for ($attempt = 0; $attempt -lt 12; $attempt++) {
        $shortGuid = [Guid]::NewGuid().ToString("N").Substring(0, 8)
        $runIdCandidate = "{0}-p{1}-{2}" -f (Get-Date).ToString("yyyyMMdd-HHmmss-fff"), $PID, $shortGuid
        $path = Join-Path $Root $runIdCandidate
        try {
            # 不使用 -Force：同名時讓建立動作失敗並重試，避免平行 launcher 共用目錄。
            New-Item -ItemType Directory -Path $path -ErrorAction Stop | Out-Null
            return [pscustomobject]@{ Id = $runIdCandidate; Path = $path }
        } catch {
            if (-not (Test-Path $path)) {
                throw
            }
        }
    }
    throw "無法建立碰撞安全的 UI QA run directory: $Root"
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

    $negativeDefs = @(
        @{ Id = "missing_state"; CaseId = "p1af_08_map_filter"; StateKind = "missing"; ExpectedPattern = "--state 檔案不存在"; IncludeRunDir = $true },
        @{ Id = "malformed_json"; CaseId = "p1af_08_map_filter"; StateKind = "malformed"; ExpectedPattern = "--state JSON 解析失敗"; IncludeRunDir = $true },
        @{ Id = "invalid_shape"; CaseId = "p1af_08_map_filter"; StateKind = "shape"; ExpectedPattern = "必要欄位遺失"; IncludeRunDir = $true },
        @{ Id = "invalid_day"; CaseId = "p1af_08_map_filter"; StateKind = "day"; ExpectedPattern = "run.day 超出範圍"; IncludeRunDir = $true },
        @{ Id = "invalid_phase"; CaseId = "p1af_08_map_filter"; StateKind = "phase"; ExpectedPattern = "run.phase 不合法"; IncludeRunDir = $true },
        @{ Id = "invalid_noninteger"; CaseId = "p1af_08_map_filter"; StateKind = "noninteger"; ExpectedPattern = "應為有限整數|應為整數"; IncludeRunDir = $true },
        @{ Id = "state_case_mismatch"; CaseId = "p1af_01_boot"; StateKind = "valid"; ExpectedPattern = "案例不接受 --state"; IncludeRunDir = $true },
        @{ Id = "unknown_case"; CaseId = "case_does_not_exist"; StateKind = "none"; ExpectedPattern = "找不到案例 id"; IncludeRunDir = $true },
        @{ Id = "invalid_data_root"; CaseId = "p1af_01_boot"; StateKind = "none"; ExpectedPattern = "--data-root 資料不合法"; IncludeRunDir = $true; InvalidDataRoot = $true },
        @{ Id = "missing_case_arg"; CaseId = ""; StateKind = "none"; ExpectedPattern = "缺少必要參數 --case"; IncludeRunDir = $true },
        @{ Id = "missing_run_dir"; CaseId = "p1af_08_map_filter"; StateKind = "valid"; ExpectedPattern = "缺少必要參數 --run-dir"; IncludeRunDir = $false }
    )

    $results = @()
    foreach ($negative in $negativeDefs) {
        $negativeRunDir = Join-Path $negativeDir $negative.Id
        New-Item -ItemType Directory -Force -Path $negativeRunDir | Out-Null
        $negativeStatesDir = Join-Path $negativeRunDir "states"
        New-Item -ItemType Directory -Force -Path $negativeStatesDir | Out-Null
        $statePath = Join-Path $negativeStatesDir "d2_morning.json"
        switch ($negative.StateKind) {
            "valid" { Set-Content -Path $statePath -Value $validJson -Encoding utf8 }
            "malformed" { Set-Content -Path $statePath -Value "{ not-json" -Encoding utf8 }
            "shape" { Set-Content -Path $statePath -Value '{"run":{}}' -Encoding utf8 }
            "day" {
                $badDayObject = $validJson | ConvertFrom-Json
                $badDayObject.run.day = 46
                $badDayObject | ConvertTo-Json -Depth 30 | Set-Content -Path $statePath -Encoding utf8
            }
            "phase" {
                $badPhaseObject = $validJson | ConvertFrom-Json
                $badPhaseObject.run.phase = "invalid"
                $badPhaseObject | ConvertTo-Json -Depth 30 | Set-Content -Path $statePath -Encoding utf8
            }
            "noninteger" {
                $badNumberObject = $validJson | ConvertFrom-Json
                $badNumberObject.run.day = 2.5
                $badNumberObject | ConvertTo-Json -Depth 30 | Set-Content -Path $statePath -Encoding utf8
            }
        }
        $logPath = Join-Path $negativeRunDir ($negative.Id + ".log")
        $args = @(
            "--path", ".",
            "--script", "res://tests/ui_sim/qa_runner.gd",
            "--log-file", $logPath,
            "--"
        )
        if (-not [string]::IsNullOrEmpty($negative.CaseId)) {
            $args += @("--case", $negative.CaseId)
        }
        if ($negative.StateKind -in @("valid", "malformed", "shape", "day", "phase", "noninteger", "missing")) {
            $args += @("--state", $statePath)
        }
        if ($negative.IncludeRunDir) {
            $args += @("--run-dir", $negativeRunDir)
        }
        if ($negative.InvalidDataRoot) {
            $args += @("--data-root", (Join-Path $negativeRunDir "missing-data"))
        }
        $runResult = Invoke-GodotProcess -Binary $GodotBinary -ArgumentList $args -TimeoutSec $TimeoutSec
        if (-not [string]::IsNullOrEmpty($runResult.CleanupError)) {
            Write-Host "FATAL: Process cleanup failed during negative test [$($negative.Id)] for PID $($runResult.RootPid): $($runResult.CleanupError)." -ForegroundColor Red
            exit 1
        }
        $logText = if (Test-Path $logPath) { Get-Content -Path $logPath -Raw -Encoding utf8 } else { "" }
        $leak = $logText -match "ObjectDB instances leaked|resources still in use|SCRIPT ERROR"
        $expected = $logText -match $negative.ExpectedPattern
        $reportPath = Join-Path $negativeRunDir ("reports\{0}.json" -f $negative.CaseId)
        $report = Read-JsonFile $reportPath
        if (-not $expected -and $null -ne $report -and $report.errors) {
            $expected = (@($report.errors) -join "`n") -match $negative.ExpectedPattern
        }
        $ok = (-not $runResult.Timeout) -and ($runResult.ExitCode -ne 0) -and $expected -and (-not $leak)
        $error = ""
        if ($runResult.Timeout) {
            $error = "unexpected timeout"
        } elseif ($runResult.ExitCode -eq 0) {
            $error = "invalid input unexpectedly exited 0"
        } elseif (-not $expected) {
            $error = "expected error pattern not found: $($negative.ExpectedPattern)"
        } elseif ($leak) {
            $error = "lifecycle warning leaked into negative diagnostic"
        }
        $results += [pscustomobject]@{
            Id = $negative.Id
            Ok = $ok
            ExitCode = $runResult.ExitCode
            Error = $error
            ReportPath = $reportPath
            RunDir = $negativeRunDir
        }
    }
    return $results
}

Assert-NoExistingGodotProcesses

$qaDir = Join-Path $projectRoot "_qa"
$runRoot = Join-Path $qaDir "runs"
New-Item -ItemType Directory -Force -Path $runRoot | Out-Null
$runInfo = New-IsolatedRunDirectory -Root $runRoot
$runId = $runInfo.Id
$runDir = $runInfo.Path
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
if (-not [string]::IsNullOrEmpty($stateRes.CleanupError)) {
    Write-Host "FATAL: Process cleanup failed during state generation for PID $($stateRes.RootPid): $($stateRes.CleanupError)." -ForegroundColor Red
    exit 1
}
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

$longCardNameData = Join-Path $dataVariantsDir "long_card_name"
Copy-Item -Path $dataSource -Destination $longCardNameData -Recurse -Force
$longCardCardsPath = Join-Path $longCardNameData "cards.json"
$longCardData = Get-Content -Path $longCardCardsPath -Raw -Encoding utf8 | ConvertFrom-Json
foreach ($c in @($longCardData.cards)) {
    if ([string]$c.id -eq "info_husband_version") {
        $c.name = "這是一張名字非常非常非常長必定超出七格欄寬的測試情報卡說法"
    }
}
$longCardData | ConvertTo-Json -Depth 30 | Set-Content -Path $longCardCardsPath -Encoding utf8

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
if (-not [string]::IsNullOrEmpty($manifestRes.CleanupError)) {
    Write-Host "FATAL: Process cleanup failed during manifest generation for PID $($manifestRes.RootPid): $($manifestRes.CleanupError)." -ForegroundColor Red
    exit 1
}
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
$matrixContractIds = @($manifest.contract_matrix | ForEach-Object { [string]$_ } | Sort-Object -Unique)
$catalogContractCount = $matrixContractIds.Count
$actualCatalogIds = @($allCaseDefs | ForEach-Object { [string]$_.contract_id } | Sort-Object -Unique)
$missingCatalogIds = @($matrixContractIds | Where-Object { $_ -notin $actualCatalogIds })
$unexpectedCatalogIds = @($actualCatalogIds | Where-Object { $_ -notin $matrixContractIds })
if ($catalogContractCount -ne 58 -or $missingCatalogIds.Count -gt 0 -or $unexpectedCatalogIds.Count -gt 0) {
    Write-Host "ERROR: Contract matrix/catalog mismatch. matrix=$catalogContractCount missing=$($missingCatalogIds -join ',') unexpected=$($unexpectedCatalogIds -join ',')" -ForegroundColor Red
    exit 1
}
$caseDefs = $allCaseDefs
if (-not [string]::IsNullOrEmpty($Case)) {
    $matched = @($allCaseDefs | Where-Object { $_.id -eq $Case })
    if ($matched.Count -eq 0) {
        $matched = @($allCaseDefs | Where-Object { $_.contract_id -eq $Case })
    }
    if ($matched.Count -eq 0) {
        Write-Host "ERROR: Case/Contract not found: $Case" -ForegroundColor Red
        exit 1
    }
    $selectedGroup = [string]$matched[0].comparison_group
    $selectedContract = [string]$matched[0].contract_id
    if (-not [string]::IsNullOrEmpty($selectedGroup)) {
        $caseDefs = @($allCaseDefs | Where-Object { $_.comparison_group -eq $selectedGroup })
        Write-Host "  Case selection expands comparison group [$selectedGroup] to $($caseDefs.Count) variants." -ForegroundColor DarkGray
    } else {
        $caseDefs = @($allCaseDefs | Where-Object { $_.contract_id -eq $selectedContract })
        if ($caseDefs.Count -gt 1) {
            Write-Host "  Case selection expands contract [$selectedContract] to $($caseDefs.Count) variants." -ForegroundColor DarkGray
        }
    }
}
$executedContractCount = @($caseDefs | ForEach-Object { [string]$_.contract_id } | Sort-Object -Unique).Count

Write-Host "[3/4] Executing $($caseDefs.Count) UI variants (catalog $catalogContractCount, executed $executedContractCount contracts)..." -ForegroundColor Yellow
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
    if (-not [string]::IsNullOrEmpty($runResult.CleanupError)) {
        Write-Host "FATAL: Process cleanup failed for case [$caseId] (PID $($runResult.RootPid)): $($runResult.CleanupError). Halting suite to prevent failure contagion." -ForegroundColor Red
        exit 1
    }
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

$normalEvidenceFailures = @()
$contractEvidence = @{}
$contractCaseReports = @{}
$contractVariantEvidenceFailures = @{}
foreach ($caseDef in $caseDefs) {
    $caseId = [string]$caseDef.id
    $contractId = [string]$caseDef.contract_id
    $reportPath = Join-Path $runDir "reports\$caseId.json"
    $report = Read-JsonFile $reportPath
    if ($null -eq $report) {
        $normalEvidenceFailures += "[$caseId] report missing or invalid"
        continue
    }
    if (-not $contractCaseReports.ContainsKey($contractId)) {
        $contractCaseReports[$contractId] = @{}
        $contractEvidence[$contractId] = @()
    }
    $contractCaseReports[$contractId][$caseId] = $report
    $existingEvidence = @($contractEvidence[$contractId])
    $incomingEvidence = @($report.evidence)
    $contractEvidence[$contractId] = @($existingEvidence + $incomingEvidence) | Sort-Object -Unique
    # 變體層：每個變體要自己送齊分派給它的 token，不能靠同契約的其他變體補。
    $requiredVariantEvidence = @($caseDef.required_variant_evidence)
    $missingVariantEvidence = @($requiredVariantEvidence | Where-Object { $_ -notin $incomingEvidence })
    if ($missingVariantEvidence.Count -gt 0) {
        $normalEvidenceFailures += "[$caseId] missing variant evidence: $($missingVariantEvidence -join ',')"
        $contractVariantEvidenceFailures[$contractId] = $true
    }
    if (-not [bool]$report.ok) {
        $normalEvidenceFailures += "[$caseId] report is not ok"
    }
    if ([string]$report.contract_id -ne $contractId) {
        $normalEvidenceFailures += "[$caseId] contract_id mismatch"
    }
    foreach ($artifact in @("shot_file", "dump_file")) {
        $artifactPath = [string]$report.$artifact
        if ([string]::IsNullOrEmpty($artifactPath) -or -not (Test-Path $artifactPath)) {
            $normalEvidenceFailures += "[$caseId] missing $artifact"
        }
    }
}

$contractFailures = @()
$completedContractCount = 0
$executedContractIds = @($caseDefs | ForEach-Object { [string]$_.contract_id } | Sort-Object -Unique)
foreach ($contractId in $executedContractIds) {
    $catalogVariants = @($allCaseDefs | Where-Object { [string]$_.contract_id -eq $contractId })
    $executedVariants = @($caseDefs | Where-Object { [string]$_.contract_id -eq $contractId })
    $missingVariants = @($catalogVariants | Where-Object { $_.id -notin @($executedVariants | ForEach-Object { $_.id }) })
    $requiredEvidence = @($catalogVariants[0].required_evidence)
    $presentEvidence = @($contractEvidence[$contractId])
    $missingEvidence = @($requiredEvidence | Where-Object { $_ -notin $presentEvidence })
    # 這個契約一份報告都沒讀到時，$contractCaseReports 裡根本沒有這個 key。
    # 不補這個防護，下一行索引 $null 會讓 launcher 自己爆掉，
    # 蓋掉「子程序沒產出報告」這個最該看清楚的失敗。
    $contractReportMap = $contractCaseReports[$contractId]
    if ($null -eq $contractReportMap) { $contractReportMap = @{} }
    $failedVariants = @($executedVariants | Where-Object {
        $r = $contractReportMap[[string]$_.id]
        $null -eq $r -or -not [bool]$r.ok
    })
    $variantEvidenceFailed = [bool]$contractVariantEvidenceFailures[$contractId]
    if ($missingVariants.Count -eq 0 -and $failedVariants.Count -eq 0 -and $missingEvidence.Count -eq 0 -and -not $variantEvidenceFailed) {
        $completedContractCount++
    } else {
        $contractFailures += [pscustomobject]@{
            ContractId = $contractId
            MissingVariants = @($missingVariants | ForEach-Object { [string]$_.id })
            FailedVariants = @($failedVariants | ForEach-Object { [string]$_.id })
            MissingEvidence = $missingEvidence
            VariantEvidenceFailed = $variantEvidenceFailed
        }
    }
}

$comparisonResults = @()
$comparisonFailures = 0
$groups = @($caseDefs | Where-Object { -not [string]::IsNullOrEmpty([string]$_.comparison_group) } | Group-Object comparison_group)
foreach ($group in $groups) {
	$expectedGroup = @($allCaseDefs | Where-Object { $_.comparison_group -eq $group.Name })
	if ($group.Group.Count -lt $expectedGroup.Count) {
		$comparisonResults += [pscustomobject]@{ Group = $group.Name; Ok = $false; Status = "SKIPPED_INCOMPLETE_GROUP"; Cases = @($group.Group.id) }
		$comparisonFailures++
		Write-Host "  -> Comparison [$($group.Name)] SKIPPED_INCOMPLETE_GROUP" -ForegroundColor Red
		continue
	}
	$groupReports = @()
    foreach ($member in $group.Group) {
        $path = Join-Path $runDir "reports\$([string]$member.id).json"
        $memberReport = Read-JsonFile $path
        if ($null -ne $memberReport) {
            $groupReports += $memberReport
        }
    }
    $signatures = @($groupReports | ForEach-Object {
        # 比對簽章只認 choice_result_normalized（案例送出的完整 serialize()）。
        # 缺這個鍵就給空字串，讓下面的 $same 判定為 FAIL——寧可紅，不要靜靜比一個殘缺的投影。
        if ($null -ne $_.observations.choice_result_normalized) {
            $_.observations.choice_result_normalized | ConvertTo-Json -Compress -Depth 30
        } else {
            ""
        }
    } | Sort-Object -Unique)
    $same = ($groupReports.Count -eq $group.Group.Count) -and ($signatures.Count -eq 1) -and (-not [string]::IsNullOrEmpty($signatures[0]))
	$comparisonStatus = if ($same) { "OK" } else { "FAIL" }
	$comparisonResults += [pscustomobject]@{ Group = $group.Name; Ok = $same; Status = $comparisonStatus; Cases = @($group.Group.id) }
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
$contractFailureCount = $contractFailures.Count
$totalFailures = $failedCount + $comparisonFailures + $negativeFailures + $normalEvidenceFailures.Count + $contractFailureCount
$summary = [ordered]@{
    RunId = $runId
    Timestamp = (Get-Date).ToString("o")
    VariantCount = $caseDefs.Count
    CatalogContractCount = $catalogContractCount
    ExecutedContractCount = $executedContractCount
    CompletedContractCount = $completedContractCount
    PassedVariants = $caseDefs.Count - $failedCount
    FailedVariants = $failedCount
    ComparisonFailures = $comparisonFailures
    NegativeFailures = $negativeFailures
    EvidenceFailures = $normalEvidenceFailures.Count
    ContractFailures = $contractFailureCount
    TotalFailures = $totalFailures
    Results = $results
    ComparisonResults = $comparisonResults
    NegativeTests = $negativeResults
    NormalEvidenceFailures = $normalEvidenceFailures
    ContractFailureDetails = $contractFailures
}
$summaryPath = Join-Path $runDir "report.json"
$summary | ConvertTo-Json -Depth 30 | Set-Content -Path $summaryPath -Encoding utf8

Write-Host "=========================================" -ForegroundColor Cyan
Write-Host "UI Simulation Summary: variants $($caseDefs.Count), catalog contracts $catalogContractCount, executed contracts $executedContractCount, completed contracts $completedContractCount, failed checks $totalFailures"
Write-Host "Report saved to: $summaryPath"
Write-Host "=========================================" -ForegroundColor Cyan
if ($totalFailures -gt 0) {
    exit 1
}
exit 0

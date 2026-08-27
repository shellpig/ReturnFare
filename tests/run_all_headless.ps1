$tests = @(
    "scripts/verify_data.gd",
    "tests/headless/test_boot.gd",
    "tests/headless/test_game_state_p1a.gd",
    "tests/headless/test_hand_p1b.gd",
    "tests/headless/test_p1c.gd",
    "tests/headless/test_p1c_bugfix.gd",
    "tests/headless/test_p1d.gd",
    "tests/headless/test_p1e.gd",
    "tests/headless/test_p1f.gd",
    "tests/headless/test_p1g.gd",
    "tests/headless/test_p2a.gd",
    "tests/headless/test_p2b.gd",
    "tests/headless/test_p2c.gd",
    "tests/headless/test_p2d.gd",
    "tests/headless/test_p2_sim.gd",
    "tests/headless/playthrough_greedy.gd",
    "tests/headless/test_p3a.gd",
    "tests/headless/test_p3b.gd",
    "tests/headless/test_p3c.gd",
    "tests/headless/test_p3d.gd",
    "tests/headless/test_p3e.gd",
    "tests/headless/test_p3f.gd",
    "tests/headless/test_p4a.gd",
    "tests/headless/test_p4b.gd",
    "tests/headless/test_p4c.gd",
    "tests/headless/test_p4d.gd",
    "tests/headless/test_p4e.gd",
    "tests/headless/test_p4f.gd"
)

$godot = "C:\_work\Godot_v4.6.3\Godot_v4.6.3-stable_win64_console.exe"
$project = Split-Path -Parent $PSScriptRoot

foreach ($t in $tests) {
    Write-Host "=== Running $t ===" -ForegroundColor Cyan
    $outFile = [System.IO.Path]::GetTempFileName()
    $errFile = [System.IO.Path]::GetTempFileName()

    $cmdLine = "`"$godot`" --headless --path `"$project`" --script `"$t`" > `"$outFile`" 2> `"$errFile`""
    cmd.exe /c $cmdLine
    $exitCode = $LASTEXITCODE

    $outText = ""
    $errText = ""
    if (Test-Path $outFile) { $outText = [System.IO.File]::ReadAllText($outFile) }
    if (Test-Path $errFile) { $errText = [System.IO.File]::ReadAllText($errFile) }
    Remove-Item $outFile, $errFile -ErrorAction SilentlyContinue

    if ($outText) { Write-Host $outText -NoNewline }
    if ($errText) { Write-Host $errText -NoNewline }

    if ($exitCode -ne 0) {
        Write-Host "`nFAILED: $t (ExitCode: $exitCode)" -ForegroundColor Red
        exit 1
    }

    # K-144 Step 4 / K-149 / K-152: Gatekeep engine-level errors and test-level failures in stderr
    $hasEngineErr = ($errText.IndexOf("SCRIPT ERROR: Assertion failed") -ge 0) -or `
                    ($errText.IndexOf("Invalid access") -ge 0) -or `
                    ($errText.IndexOf("Invalid index") -ge 0) -or `
                    ($errText.IndexOf("Invalid call") -ge 0) -or `
                    ($errText -match "ERROR:\s+FAIL")

    if ($hasEngineErr) {
        Write-Host "`nFAILED: $t detected engine or test failure in stderr despite exit 0" -ForegroundColor Red
        exit 1
    }
}

Write-Host "`nALL HEADLESS TESTS PASSED!" -ForegroundColor Green
exit 0

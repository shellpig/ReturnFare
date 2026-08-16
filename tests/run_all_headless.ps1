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
    "tests/headless/playthrough_greedy.gd"
)

$godot = "C:\_work\Godot_v4.6.3\Godot_v4.6.3-stable_win64_console.exe"
$project = "C:\_work\AI_Work\Projects\ReturnFare"

foreach ($t in $tests) {
    Write-Host "=== Running $t ===" -ForegroundColor Cyan
    & $godot --headless --path $project --script $t
    if ($LASTEXITCODE -ne 0) {
        Write-Host "FAILED: $t (ExitCode: $LASTEXITCODE)" -ForegroundColor Red
        exit 1
    }
}

Write-Host "ALL HEADLESS TESTS PASSED!" -ForegroundColor Green
exit 0

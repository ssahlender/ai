# The contradictory-policy fixture must be rejected by the real validator.
$ErrorActionPreference = 'Stop'
$exe = Join-Path $env:SystemRoot 'System32\WindowsPowerShell\v1.0\powershell.exe'
$script = Join-Path $PSScriptRoot 'hard-task-answerability.ps1'
$root = Join-Path $env:TEMP ('answerability-' + [guid]::NewGuid().ToString('N'))
try {
    $pristine = & $exe -NoProfile -ExecutionPolicy Bypass -File $script -FixtureDir $root 2>&1 | Out-String
    if ($LASTEXITCODE -ne 0 -or $pristine -notmatch 'HARD-TASK ANSWERABILITY: PASS') { throw 'FAIL: pristine fixture did not pass the real validator' }
    $out = & $exe -NoProfile -ExecutionPolicy Bypass -File $script -RegressionFixture -FixtureDir $root 2>&1 | Out-String
    if ($LASTEXITCODE -eq 0) { throw 'FAIL: contradictory policy was accepted' }
    if ($out -notmatch 'expectation is not derivable') { throw 'FAIL: contradictory policy did not fail derivability' }
    Write-Output 'HARD-TASK ANSWERABILITY SELFTEST: PASS (contradictory policy rejected)'
} finally {
    Remove-Item $root -Recurse -Force -ErrorAction SilentlyContinue
    Remove-Item ($root + '.canonical') -Recurse -Force -ErrorAction SilentlyContinue
}

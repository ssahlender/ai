# The contradictory-policy fixture must be rejected by the real validator.
$ErrorActionPreference = 'Stop'
$exe = Join-Path $env:SystemRoot 'System32\WindowsPowerShell\v1.0\powershell.exe'
$script = Join-Path $PSScriptRoot 'hard-task-answerability.ps1'
$root = Join-Path $env:TEMP ('answerability-' + [guid]::NewGuid().ToString('N'))
try {
    $p = Start-Process -FilePath $exe -ArgumentList @('-NoProfile', '-ExecutionPolicy', 'Bypass', '-File', $script, '-RegressionFixture', '-FixtureDir', $root) -Wait -PassThru -NoNewWindow
    if ($p.ExitCode -eq 0) { throw 'FAIL: contradictory policy was accepted' }
    Write-Output 'HARD-TASK ANSWERABILITY SELFTEST: PASS (contradictory policy rejected)'
} finally {
    Remove-Item $root -Recurse -Force -ErrorAction SilentlyContinue
    Remove-Item ($root + '.canonical') -Recurse -Force -ErrorAction SilentlyContinue
}

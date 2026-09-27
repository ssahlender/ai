# Regression tests for fixture isolation, protected canonical tests, and byte-precise edits.
$ErrorActionPreference = 'Stop'
. (Join-Path (Split-Path $PSScriptRoot -Parent) 'lib\common.ps1')
. (Join-Path $PSScriptRoot 'quality-tasks.ps1')
. (Join-Path $PSScriptRoot 'quality-tasks-hard.ps1')

function Invoke-ProcessCapture {
    param([string]$Exe, [string[]]$Arguments, [string]$WorkDir, [int]$TimeoutMs = 60000)
    $p = Start-Process -FilePath $Exe -ArgumentList $Arguments -WorkingDirectory $WorkDir -Wait -PassThru -NoNewWindow
    return @{ ExitCode = $p.ExitCode; Out = ''; Err = ''; TimedOut = $false }
}
function Check { param([string]$Name, [bool]$Ok); if (-not $Ok) { throw "FAIL: $Name" }; Write-Output "ok  $Name" }

$root = Join-Path $env:TEMP ('quality-integrity-' + [guid]::NewGuid().ToString('N'))
try {
    # F1: candidate one makes only the definition change. Candidate two makes only the call-site
    # change. Rebuilding between them means candidate two cannot inherit candidate one's edit.
    New-QualityHardFixture -Dir $root | Out-Null
    $lib = Join-Path $root 'mini1\lib.ps1'
    (Get-Content $lib -Raw).Replace('Get-Total', 'Get-Sum') | Set-Content $lib -NoNewline
    New-QualityHardFixture -Dir $root | Out-Null
    $main = Join-Path $root 'mini1\main.ps1'
    (Get-Content $main -Raw).Replace('Get-Total', 'Get-Sum') | Set-Content $main -NoNewline
    $isolated = Assert-SuiteTest -FixtureDir $root -SubDir 'mini1'
    Check 'F1 partial then finishing candidate does not pass' (-not $isolated.Pass)

    # F2: a candidate can overwrite the obsolete in-fixture name, but the checker restores from
    # the sibling canonical store and still executes the real test.
    New-QualityHardFixture -Dir $root | Out-Null
    Set-Content (Join-Path $root 'mini1\test.canonical.ps1') 'Write-Output TEST-PASS; exit 0'
    $tamper = Assert-SuiteTest -FixtureDir $root -SubDir 'mini1'
    Check 'F2 in-fixture canonical tampering does not pass' (-not $tamper.Pass)

    # F6: exact source content with one changed line passes; a whitespace change elsewhere fails.
    New-QualityHardFixture -Dir $root | Out-Null
    $edit = Get-Content (Join-Path $root 'editme.txt') -Raw
    $good = $edit.Replace('retries=5', 'retries=3')
    Check 'F6 byte-identical one-line replacement passes' (Assert-OneLineChanged -Answer $good -OriginalPath (Join-Path $root 'editme.txt') -ExpectLine 'retries=3').Pass
    $bad = $good.Replace('enabled=true', 'enabled=true ')
    Check 'F6 whitespace change outside replacement fails' (-not (Assert-OneLineChanged -Answer $bad -OriginalPath (Join-Path $root 'editme.txt') -ExpectLine 'retries=3').Pass)
} finally {
    Remove-Item $root -Recurse -Force -ErrorAction SilentlyContinue
    Remove-Item ($root + '.canonical') -Recurse -Force -ErrorAction SilentlyContinue
}
Write-Output 'HARNESS-INTEGRITY SELFTEST: PASS'

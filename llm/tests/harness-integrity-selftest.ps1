# Regression tests for fixture isolation, protected canonical tests, and line-precise edits.
$ErrorActionPreference = 'Stop'
. (Join-Path (Split-Path $PSScriptRoot -Parent) 'lib\common.ps1')
. (Join-Path $PSScriptRoot 'quality-tasks.ps1')
. (Join-Path $PSScriptRoot 'quality-tasks-hard.ps1')
function Check { param([string]$Name, [bool]$Ok); if (-not $Ok) { throw "FAIL: $Name" }; Write-Output "ok  $Name" }

$root = Join-Path $env:TEMP ('quality-integrity-' + [guid]::NewGuid().ToString('N'))
try {
    # F1: drive quality-run itself twice. Each answer supplies half of the rename; candidate two
    # would pass only if it inherited candidate one's edit. MockAnswer is a runner test seam, so
    # this checks fixture reset and candidate execution rather than a hand-simulated reconstruction.
    $runner = Join-Path $PSScriptRoot 'quality-run.ps1'
    $out = Join-Path $root 'runs'
    New-Item -ItemType Directory -Path $out -Force | Out-Null
    $first = "(Get-Content 'lib.ps1' -Raw).Replace('Get-Total','Get-Sum') | Set-Content 'lib.ps1' -NoNewline"
    $second = "(Get-Content 'main.ps1' -Raw).Replace('Get-Total','Get-Sum') | Set-Content 'main.ps1' -NoNewline"
    & $runner -Mode first-half -TaskSet hard -Only hard-multifile-rename -FixtureDir $root -OutDir $out -MockAnswer $first | Out-Null
    & $runner -Mode second-half -TaskSet hard -Only hard-multifile-rename -FixtureDir $root -OutDir $out -MockAnswer $second | Out-Null
    $secondResult = Get-ChildItem $out -Filter 'quality-second-half-*.json' | Sort-Object LastWriteTime | Select-Object -Last 1
    $doc = Get-Content $secondResult.FullName -Raw | ConvertFrom-Json
    Check 'F1 second partial candidate does not inherit first candidate work' (-not $doc.results[0].pass)

    # F2: overwriting the live test is detected distinctly before it is restored from the safe copy.
    New-QualityHardFixture -Dir $root | Out-Null
    Set-Content (Join-Path $root 'mini1\test.ps1') 'Write-Output TEST-PASS; exit 0'
    $tamper = Assert-SuiteTest -FixtureDir $root -SubDir 'mini1'
    Check 'F2 live-test tampering has a distinct failure reason' ((-not $tamper.Pass) -and $tamper.Reason -match 'tampering')

    # F6: EOL style is not part of the contract; empty lines and all non-target text still are.
    New-QualityHardFixture -Dir $root | Out-Null
    $edit = Get-Content (Join-Path $root 'editme.txt') -Raw
    $good = $edit.Replace('retries=5', 'retries=3')
    $lf = $good -replace "`r`n", "`n"
    Check 'F6 LF-normalized one-line replacement passes' (Assert-OneLineChanged -Answer $lf -OriginalPath (Join-Path $root 'editme.txt') -ExpectLine 'retries=3').Pass
    $bad = $good.Replace('enabled=true', 'enabled=true ')
    Check 'F6 whitespace change outside replacement fails' (-not (Assert-OneLineChanged -Answer $bad -OriginalPath (Join-Path $root 'editme.txt') -ExpectLine 'retries=3').Pass)
    $extraEmpty = $good.Replace('enabled=true', "enabled=true`r`n")
    Check 'F6 added empty line fails' (-not (Assert-OneLineChanged -Answer $extraEmpty -OriginalPath (Join-Path $root 'editme.txt') -ExpectLine 'retries=3').Pass)
} finally {
    Remove-Item $root -Recurse -Force -ErrorAction SilentlyContinue
    Remove-Item ($root + '.canonical') -Recurse -Force -ErrorAction SilentlyContinue
}
Write-Output 'HARNESS-INTEGRITY SELFTEST: PASS'

# Answerability validator for the hard task set.
#
# Why this exists: five tasks (the three context tasks and both precision tasks) told the model to
# "Read <file>" while supplying neither the file's content nor a tool to read it with. They were
# impossible for ANY model, and the models that answered "I will read the file" were scored as failures.
# The checks had all been self-tested - but nothing ever verified that a task could be ANSWERED, which
# is a different property from "the check recognises a correct answer".
#
# Run before trusting any hard-set result:
#   powershell -ExecutionPolicy Bypass -File hard-task-answerability.ps1
#
# Exit 0 = every task has what it needs to be answered.

$ErrorActionPreference = 'Stop'
. (Join-Path $PSScriptRoot 'quality-tasks.ps1')
. (Join-Path $PSScriptRoot 'quality-tasks-hard.ps1')

$fixtureDir = 'C:\ProgramData\llm-quality-fixtures'
if ($env:FIXTURE_DIR) { $fixtureDir = $env:FIXTURE_DIR }
if (-not (Test-Path $fixtureDir)) { Write-Output "fixture dir missing: $fixtureDir (run the suite once first)"; exit 1 }

# Build/refresh the fixtures, then take the real task list the runner uses.
$null = New-QualityHardFixture -Dir $fixtureDir
$tasks = @(Get-QualityHardTaskList)
$fail = 0

function Report {
    param([string]$Id, [bool]$Ok, [string]$Detail)
    $mark = 'FAIL'
    if ($Ok) { $mark = 'ok  ' }
    Write-Output ("  $mark " + $Id.PadRight(24) + $Detail)
}
function Read-Fixture {
    param([string]$Rel)
    $p = Join-Path $fixtureDir $Rel
    if (-not (Test-Path $p)) { return $null }
    return (Get-Content $p -Raw)
}

foreach ($t in $tasks) {
    $ok = $true
    $detail = ''
    $check = "$($t.Check)"

    switch ($check) {
        'Assert-AnswerExact' {
            if (-not $t.ContextFile) { $ok = $false; $detail = 'no ContextFile -> model cannot read the file' }
            else {
                $content = Read-Fixture $t.ContextFile
                if ($null -eq $content) { $ok = $false; $detail = "fixture missing: $($t.ContextFile)" }
                elseif ($content -notlike "*$($t.Expect)*") { $ok = $false; $detail = "expected value '$($t.Expect)' NOT present in $($t.ContextFile) - unanswerable" }
                else { $detail = "$($t.ContextFile) inlined, answer present, " + [Math]::Round($content.Length/1KB,1) + ' KB' }
            }
        }
        'Assert-JsonShape' {
            if (-not $t.ContextFile) { $ok = $false; $detail = 'no ContextFile -> model cannot read the file' }
            else {
                $content = Read-Fixture $t.ContextFile
                if ($null -eq $content) { $ok = $false; $detail = "fixture missing: $($t.ContextFile)" }
                else {
                    # Expect is a HASHTABLE here: .PSObject.Properties would enumerate IsReadOnly, Keys,
                    # Count and friends instead of the expected values. Iterate the keys.
                    $missing = @()
                    foreach ($k in @($t.Expect.Keys)) {
                        $v = $t.Expect[$k]
                        if ($content -notlike "*$v*") { $missing += "$k=$v" }
                    }
                    if ($missing.Count) { $ok = $false; $detail = "values not in file: " + ($missing -join ', ') }
                    else { $detail = "$($t.ContextFile) has all expected values" }
                }
            }
        }
        'Assert-OneLineChanged' {
            if (-not $t.ContextFile) { $ok = $false; $detail = 'no ContextFile -> model cannot reproduce the other lines' }
            else {
                $content = Read-Fixture $t.ContextFile
                if ($null -eq $content) { $ok = $false; $detail = "fixture missing: $($t.ContextFile)" }
                else {
                    $lines = @($content -split "`r?`n" | Where-Object { $_ -ne '' })
                    if ($lines.Count -lt 3) { $ok = $false; $detail = "only $($lines.Count) non-empty lines - 'every other line identical' is not a real test" }
                    elseif ($content -notmatch 'retries') { $ok = $false; $detail = 'no retries line in the fixture' }
                    else { $detail = "$($lines.Count) lines, retries line present" }
                }
            }
        }
        'Assert-SuiteTest' {
            if (-not $t.SubDir) { $ok = $false; $detail = 'no SubDir' }
            else {
                $d = Join-Path $fixtureDir $t.SubDir
                if (-not (Test-Path $d)) { $ok = $false; $detail = "project dir missing: $($t.SubDir)" }
                elseif (-not (Test-Path (Join-Path $d 'test.ps1'))) { $ok = $false; $detail = "$($t.SubDir) has no test.ps1" }
                elseif (-not (Test-Path (Join-Path $d 'lib.ps1'))) { $ok = $false; $detail = "$($t.SubDir) has no lib.ps1" }
                else { $detail = "$($t.SubDir): lib.ps1 + test.ps1 present" }
            }
        }
        'Assert-ToolTask' {
            if (-not $t.Tools -or @($t.Tools).Count -eq 0) { $ok = $false; $detail = 'no tools offered but the task asks the model to read files' }
            else { $detail = (@($t.Tools).Count.ToString() + ' tools offered') }
        }
        'Assert-ExecOutput' {
            $ok = $true; $detail = 'base-set style task (generates code)'
        }
        default {
            $ok = $false; $detail = "unknown check '$check' - no answerability rule"
        }
    }

    if (-not $ok) { $fail++ }
    Report -Id $t.Id -Ok $ok -Detail $detail
}

Write-Output ""
$total = $tasks.Count
if ($fail -eq 0) {
    Write-Output "HARD-TASK ANSWERABILITY: PASS ($total/$total tasks have what they need)"
    exit 0
} else {
    Write-Output "HARD-TASK ANSWERABILITY: FAIL ($fail of $total tasks unanswerable)"
    exit 1
}

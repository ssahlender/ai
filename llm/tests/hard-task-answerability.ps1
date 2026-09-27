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

[CmdletBinding()]
param([switch]$RegressionFixture, [string]$FixtureDir)

$ErrorActionPreference = 'Stop'
. (Join-Path $PSScriptRoot 'quality-tasks.ps1')
. (Join-Path $PSScriptRoot 'quality-tasks-hard.ps1')

$fixtureDir = 'C:\ProgramData\llm-quality-fixtures'
if ($env:FIXTURE_DIR) { $fixtureDir = $env:FIXTURE_DIR }
if ($FixtureDir) { $fixtureDir = $FixtureDir }

# Build/refresh the fixtures, then take the real task list the runner uses.
$null = New-QualityHardFixture -Dir $fixtureDir
$tasks = @(Get-QualityHardTaskList)
$fail = 0
$sizeFail = 0
$deriveFail = 0
# A fixture that does not FIT the context is as unanswerable as a missing one, and the symptom is an
# instant HTTP 400 rather than anything that looks like a harness problem. Estimate at ~3.6 chars/token
# (measured: 44 KB -> 12180 tokens) and keep a margin below the 32 K window.
$ctxBudget = 20000

function Report {
    param([string]$Id, [bool]$Ok, [string]$Detail)
    $mark = 'FAIL'
    if ($Ok) { $mark = 'ok  ' }
    Write-Output ("  $mark " + $Id.PadRight(24) + $Detail)
}
# Every expected literal should be reachable from what the model is GIVEN: the prompt text or an
# inlined file (tasks that offer Tools can fetch files themselves, so they are exempt). A check can
# recognise a correct answer perfectly and still be measuring nothing if the answer was unreachable -
# that is how 'retries=3' shipped in a file whose only retry value was 5: both models invented a
# number and were scored as failures for it.
function Get-ExpectedLiterals {
    param($Task)
    $out = @()
    if ($null -eq $Task.Expect) { return $out }
    if ($Task.Expect -is [hashtable]) {
        foreach ($k in @($Task.Expect.Keys)) { $out += "$($Task.Expect[$k])" }
    } else { $out += "$($Task.Expect)" }
    return $out
}
function Read-Fixture {
    param([string]$Rel)
    $p = Join-Path $fixtureDir $Rel
    if (-not (Test-Path $p)) { return $null }
    return (Get-Content $p -Raw)
}
function Test-DerivableExpectation {
    # The one expected value intentionally absent from the fixture is retries=3.  It is derivable
    # only if the stated arithmetic policy and the stated attempts value actually produce it.
    param([string]$Expected, [string]$Text)
    if ($Expected -notmatch '^retries=(\d+)$') { return $false }
    if ($Text -notmatch '(?im)^\s*#\s*policy:\s*retries\s+must\s+equal\s+attempts\s*-\s*1\s*$') { return $false }
    if ($Text -notmatch '(?im)^\s*attempts=(\d+)\s*$') { return $false }
    return ([int]$Matches[1] - 1 -eq [int]$Expected.Split('=')[1])
}

if ($RegressionFixture) {
    # Deliberately contradict the policy-derived expectation.  The self-test invokes this mode and
    # requires the validator to fail, proving derivability is a gate rather than a warning.
    $edit = Join-Path $fixtureDir 'editme.txt'
    $text = Get-Content $edit -Raw
    $text = $text -replace 'retries must equal attempts - 1', 'retries must equal attempts'
    [IO.File]::WriteAllText($edit, $text, (New-Object System.Text.UTF8Encoding($false)))
}

foreach ($t in $tasks) {
    $ok = $true
    $detail = ''
    $check = "$($t.Check)"

    if ($t.ContextFile) {
        $cf = Join-Path $fixtureDir $t.ContextFile
        if (Test-Path $cf) {
            $len = (Get-Item $cf).Length
            $estTok = [Math]::Round(($len / 3.6), 0)
            if ($estTok -gt $ctxBudget) {
                $sizeFail++
                Write-Output ("  FAIL " + $t.Id.PadRight(24) + "context budget: ~" + $estTok + " tokens (" + [Math]::Round($len/1KB,1) + " KB) exceeds " + $ctxBudget + " of the 32 K window - the server rejects it with 400")
            }
        }
    }

    # Derivability: skip when tools are offered (the model reads files itself).
    $hasTools = ($t.Tools -and @($t.Tools).Count -gt 0)
    if (-not $hasTools) {
        $fileText = ''
        if ($t.ContextFile) { $fileText = Read-Fixture $t.ContextFile }
        if ($null -eq $fileText) { $fileText = '' }
        foreach ($lit in (Get-ExpectedLiterals $t)) {
            if (-not $lit) { continue }
            $inPrompt = ("$($t.Prompt)" -like "*$lit*")
            $inFile = ($fileText -like "*$lit*")
            if (-not $inPrompt -and -not $inFile) {
                if (Test-DerivableExpectation -Expected $lit -Text $fileText) {
                    $detail += " | '$lit' derivable from the stated policy"
                } else {
                    $deriveFail++
                    $ok = $false
                    $detail += " | expectation '$lit' is not derivable from the stated policy"
                }
            }
        }
    }

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
if ($fail -eq 0 -and $sizeFail -eq 0 -and $deriveFail -eq 0) {
    Write-Output "HARD-TASK ANSWERABILITY: PASS ($total/$total tasks have what they need and fit)"
    exit 0
} else {
    Write-Output "HARD-TASK ANSWERABILITY: FAIL ($fail of $total tasks unanswerable, $sizeFail oversized, $deriveFail non-derivable expectations)"
    exit 1
}

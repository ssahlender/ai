# Round 2: the HARD task set. Same rules as round 1 - every task machine-checkable, nothing scored by
# a model judging a model - but at a difficulty that can actually separate capable models.
#
# WHY THIS EXISTS: round 1 was passed 12/12 by BOTH candidates. A test both candidates ace has zero
# power to decide anything; that tie was a statement about task difficulty, not about the models.
#
# Four families, chosen to attack what round 1 could not reach:
#   A. multi-file consistency  - the answer must edit several files so a test passes
#   B. long-context retrieval  - one decisive fact buried in ~10-15k tokens of distractor text
#   C. tool chains with a fatal intermediate - a wrong argument, or an error that must be recovered
#   D. instruction precision   - exact schema; or change exactly one line and nothing else
#
# Dot-sourced by quality-run.ps1 -TaskSet hard. Reuses the round-1 checks and helpers.

# This file needs Write-Utf8NoBom from lib/common.ps1 (fixture construction). Load it HERE instead of
# relying on the caller: the first standalone caller (hard-task-answerability.ps1) died with
# 'Write-Utf8NoBom is not recognized' because quality-run.ps1 happened to load common first.
. (Join-Path (Split-Path $PSScriptRoot -Parent) 'lib\common.ps1')
. (Join-Path $PSScriptRoot 'quality-tasks.ps1')

function Write-FixtureFile {
    param([string]$Path, [string[]]$Lines)
    $dir = Split-Path $Path -Parent
    if ($dir -and -not (Test-Path $dir)) { New-Item -ItemType Directory -Path $dir -Force | Out-Null }
    Write-Utf8NoBom -Path $Path -Lines $Lines
}

function New-QualityHardFixture {
    # Four self-contained mini projects for family A, one per task, so a task can never be passed by
    # collateral damage to another task's files.
    #
    # INTEGRITY: canonical tests live beside, not inside, the candidate-writable fixture.  The
    # checker restores test.ps1 from there before it runs; rewriting test.ps1 (or an obsolete
    # in-fixture test.canonical.ps1) therefore cannot make a task pass.
    param([Parameter(Mandatory = $true)][string]$Dir)
    $root = $Dir
    $canonicalRoot = Join-Path (Split-Path $root -Parent) ((Split-Path $root -Leaf) + '.canonical')
    if (-not (Test-Path $canonicalRoot)) { New-Item -ItemType Directory -Path $canonicalRoot -Force | Out-Null }

    # ---- A1: rename a function, and both call sites with it ----
    $a1lib = @(
        'function Get-Total { param([array]$Items) $t = 0; foreach ($i in $Items) { $t += $i.amount }; return $t }'
    )
    $a1main = @(
        '. "$PSScriptRoot\lib.ps1"'
        '$items = @([pscustomobject]@{ amount = 10 }, [pscustomobject]@{ amount = 32 })'
        '$a = Get-Total -Items $items'
        '$b = Get-Total -Items @([pscustomobject]@{ amount = 8 })'
        'Write-Output ("a=" + $a + " b=" + $b)'
    )
    $a1test = @(
        '. "$PSScriptRoot\lib.ps1"'
        'if (-not (Get-Command Get-Sum -ErrorAction SilentlyContinue)) { Write-Output "TEST-FAIL Get-Sum is not defined"; exit 1 }'
        '$items = @([pscustomobject]@{ amount = 10 }, [pscustomobject]@{ amount = 32 })'
        'if ((Get-Sum -Items $items) -ne 42) { Write-Output "TEST-FAIL wrong total"; exit 1 }'
        '$main = & (Join-Path $PSScriptRoot "main.ps1")'
        'if ("$main" -ne "a=42 b=8") { Write-Output "TEST-FAIL call sites were not renamed"; exit 1 }'
        'Write-Output "TEST-PASS"'
        'exit 0'
    )
    Write-FixtureFile -Path (Join-Path $root 'mini1\lib.ps1') -Lines $a1lib
    Write-FixtureFile -Path (Join-Path $root 'mini1\main.ps1') -Lines $a1main
    Write-FixtureFile -Path (Join-Path $root 'mini1\test.ps1') -Lines $a1test
    Remove-Item (Join-Path $root 'mini1\test.canonical.ps1') -Force -ErrorAction SilentlyContinue
    Write-FixtureFile -Path (Join-Path $canonicalRoot 'mini1\test.ps1') -Lines $a1test

    # ---- A2: add a parameter with a default, then use it in one caller ----
    $a2lib = @(
        'function Format-Line { param([string]$Name, [int]$Amount) return ($Name + "=" + $Amount) }'
    )
    $a2main = @(
        '. "$PSScriptRoot\lib.ps1"'
        'Write-Output (Format-Line -Name "sum" -Amount 42)'
    )
    $a2test = @(
        '. "$PSScriptRoot\lib.ps1"'
        '$r = Format-Line -Name "sum" -Amount 42 -Unit "EUR"'
        'if ($r -ne "sum=42 EUR") { Write-Output ("TEST-FAIL got " + $r); exit 1 }'
        'Write-Output "TEST-PASS"'
        'exit 0'
    )
    Write-FixtureFile -Path (Join-Path $root 'mini2\lib.ps1') -Lines $a2lib
    Write-FixtureFile -Path (Join-Path $root 'mini2\main.ps1') -Lines $a2main
    Write-FixtureFile -Path (Join-Path $root 'mini2\test.ps1') -Lines $a2test
    Remove-Item (Join-Path $root 'mini2\test.canonical.ps1') -Force -ErrorAction SilentlyContinue
    Write-FixtureFile -Path (Join-Path $canonicalRoot 'mini2\test.ps1') -Lines $a2test

    # ---- A3: a defect that spans two files (arguments swapped at the call site) ----
    $a3lib = @(
        'function Format-Line { param([string]$Name, [int]$Amount) return ($Name + "=" + $Amount) }'
    )
    $a3main = @(
        '. "$PSScriptRoot\lib.ps1"'
        '# the definition above is authoritative; this call is wrong'
        'Write-Output (Format-Line -Name 42 -Amount "sum")'
    )
    $a3test = @(
        '. "$PSScriptRoot\lib.ps1"'
        '$r = & (Join-Path $PSScriptRoot "main.ps1")'
        'if ("$r" -ne "sum=42") { Write-Output ("TEST-FAIL got " + "$r"); exit 1 }'
        'Write-Output "TEST-PASS"'
        'exit 0'
    )
    Write-FixtureFile -Path (Join-Path $root 'mini3\lib.ps1') -Lines $a3lib
    Write-FixtureFile -Path (Join-Path $root 'mini3\main.ps1') -Lines $a3main
    Write-FixtureFile -Path (Join-Path $root 'mini3\test.ps1') -Lines $a3test
    Remove-Item (Join-Path $root 'mini3\test.canonical.ps1') -Force -ErrorAction SilentlyContinue
    Write-FixtureFile -Path (Join-Path $canonicalRoot 'mini3\test.ps1') -Lines $a3test

    # ---- A4: a constant lives in one file and a dependent computation ignores it ----
    $a4lib = @(
        '$script:Rate = 0.1'
    )
    $a4main = @(
        '. "$PSScriptRoot\lib.ps1"'
        '# BUG: this hardcodes 0.2 instead of using the constant defined in lib.ps1'
        '$rate = 0.2'
        'Write-Output ("rate=" + $rate)'
    )
    $a4test = @(
        '. "$PSScriptRoot\lib.ps1"'
        '$r = & (Join-Path $PSScriptRoot "main.ps1")'
        'if ("$r" -ne "rate=0.1") { Write-Output ("TEST-FAIL got " + "$r"); exit 1 }'
        'Write-Output "TEST-PASS"'
        'exit 0'
    )
    Write-FixtureFile -Path (Join-Path $root 'mini4\lib.ps1') -Lines $a4lib
    Write-FixtureFile -Path (Join-Path $root 'mini4\main.ps1') -Lines $a4main
    Write-FixtureFile -Path (Join-Path $root 'mini4\test.ps1') -Lines $a4test
    Remove-Item (Join-Path $root 'mini4\test.canonical.ps1') -Force -ErrorAction SilentlyContinue
    Write-FixtureFile -Path (Join-Path $canonicalRoot 'mini4\test.ps1') -Lines $a4test

    # ---- B1: a ~12k-token log with exactly one uppercase ERROR line, buried ----
    # The distractor is deliberate: lowercase "error" appears in prose many times, so a model that
    # greps case-insensitively finds noise and must reason about which line is the real one.
    $log = New-Object System.Collections.Generic.List[string]
    for ($i = 0; $i -lt 400; $i++) {
        if ($i -eq 270) {
            $log.Add('2026-09-27 03:14:22 ERROR request failed request_id=req-8f4c2b91 upstream timeout')
        } elseif ($i % 97 -eq 0) {
            $log.Add(('2026-09-27 03:{0:d2}:11 INFO  request {1} completed with no error observed' -f ($i % 60), $i))
        } else {
            $log.Add(('2026-09-27 03:{0:d2}:07 INFO  handler step {1} finished ok in {2}ms' -f ($i % 60), $i, (7 + ($i % 40))))
        }
    }
    Write-FixtureFile -Path (Join-Path $root 'big\app.log') -Lines $log.ToArray()

    # ---- B2: a ~15k-token config dump where one setting appears three times ----
    $cfg = New-Object System.Collections.Generic.List[string]
    $cfg.Add('# The sections below are applied in order. A KEY SET IN A LATER SECTION OVERRIDES')
    $cfg.Add('# EVERY EARLIER ONE. Only the last occurrence of a key is in effect.')
    $cfg.Add('')
    $cfg.Add('[legacy defaults]')
    $cfg.Add('max_connections = 64')
    for ($i = 0; $i -lt 300; $i++) { $cfg.Add(('legacy.option_{0} = {1}' -f $i, ($i * 3))) }
    $cfg.Add('')
    $cfg.Add('[included from site.conf]')
    $cfg.Add('max_connections = 128')
    for ($i = 0; $i -lt 300; $i++) { $cfg.Add(('site.option_{0} = {1}' -f $i, ($i * 5))) }
    $cfg.Add('')
    $cfg.Add('[operator overrides - applied last]')
    $cfg.Add('max_connections = 512')
    for ($i = 0; $i -lt 400; $i++) { $cfg.Add(('operator.option_{0} = {1}' -f $i, ($i * 7))) }
    Write-FixtureFile -Path (Join-Path $root 'big\config-dump.txt') -Lines $cfg.ToArray()

    # ---- B3: a changelog; exactly one entry introduces "retry on 429" ----
    $cl = New-Object System.Collections.Generic.List[string]
    $cl.Add('# Changelog')
    $vers = @('v3.1.0', 'v3.2.0', 'v3.3.0', 'v3.4.0', 'v3.4.1', 'v3.4.2', 'v3.5.0', 'v3.6.0', 'v4.0.0')
    foreach ($v in $vers) {
        $cl.Add('')
        $cl.Add("## $v")
        for ($i = 0; $i -lt 90; $i++) {
            if ($v -eq 'v3.4.2' -and $i -eq 41) {
                $cl.Add('- introduced retry on 429 responses with exponential backoff')
            } elseif ($v -eq 'v3.4.0' -and $i -eq 12) {
                $cl.Add('- retry logic reworked; no automatic retry on rate limiting yet')
            } elseif ($v -eq 'v3.6.0' -and $i -eq 30) {
                $cl.Add('- retry budget is now configurable per endpoint')
            } else {
                $cl.Add(('- internal cleanup item {0} for {1}' -f $i, $v))
            }
        }
    }
    Write-FixtureFile -Path (Join-Path $root 'big\CHANGELOG.txt') -Lines $cl.ToArray()

    # ---- C: distractor reports. The newest file overall is NOT a report. ----
    Write-FixtureFile -Path (Join-Path $root 'reports\report-2026-01-09.txt') -Lines @('period 2026-01-09', 'TOKEN-0109')
    Write-FixtureFile -Path (Join-Path $root 'reports\report-2026-03-01.txt') -Lines @('period 2026-03-01', 'TOKEN-0301')
    Write-FixtureFile -Path (Join-Path $root 'reports\report-2026-08-14.txt') -Lines @('period 2026-08-14', 'TOKEN-0814')
    Write-FixtureFile -Path (Join-Path $root 'reports\archive-2026-09-30.txt') -Lines @('archive index, not a report', 'TOKEN-0930')
    Write-FixtureFile -Path (Join-Path $root 'reports\pointer.txt') -Lines @('report-2026-08-14.txt')
    # NOTE: reports\latest.txt deliberately does NOT exist - the recovery task needs it missing.

    # ---- D: fixtures for precision tasks ----
    Write-FixtureFile -Path (Join-Path $root 'sum.txt') -Lines @('name: atlas', 'count: 7', 'total: 1284')
    Write-FixtureFile -Path (Join-Path $root 'editme.txt') -Lines @(
        '# retry configuration',
        '# policy: retries must equal attempts - 1',
        'enabled=true',
        'attempts=4',
        'retries=5',
        'backoff=exponential',
        'timeout_ms=2500'
    )
    return $root
}

function Assert-AnswerExact {
    # For retrieval and precision tasks: the answer text must CONTAIN the expected token. Containment,
    # not equality, because a model may wrap a correct short answer in a sentence - that is packaging,
    # and round 1 taught us not to score packaging.
    param(
        [Parameter(Mandatory = $true)][string]$Answer,
        [Parameter(Mandatory = $true)][string]$Expect
    )
    if ($Answer -match [regex]::Escape($Expect)) { return @{ Pass = $true; Reason = "answer contained $Expect" } }
    $short = "$Answer".Trim()
    if ($short.Length -gt 160) { $short = $short.Substring(0, 160) + '...' }
    return @{ Pass = $false; Reason = "expected [$Expect] not found in answer [$short]" }
}

function Assert-SuiteTest {
    # Family A: restore test.ps1 from the canonical copy outside the candidate-writable fixture.
    param(
        [Parameter(Mandatory = $true)][string]$FixtureDir,
        [Parameter(Mandatory = $true)][string]$SubDir
    )
    $dir = Join-Path $FixtureDir $SubDir
    $canonRoot = Join-Path (Split-Path $FixtureDir -Parent) ((Split-Path $FixtureDir -Leaf) + '.canonical')
    $canon = Join-Path $canonRoot (Join-Path $SubDir 'test.ps1')
    $live = Join-Path $dir 'test.ps1'
    if (-not (Test-Path $canon)) { return @{ Pass = $false; Reason = "canonical test missing in $SubDir" } }
    Copy-Item $canon $live -Force

    $exe = Join-Path $env:SystemRoot 'System32\WindowsPowerShell\v1.0\powershell.exe'
    $r = Invoke-ProcessCapture -Exe $exe -Arguments @('-NoProfile', '-ExecutionPolicy', 'Bypass', '-File', $live) `
        -WorkDir $dir -TimeoutMs 60000
    $out = ("$($r.Out)").Trim()
    if ($out -match 'TEST-PASS' -and $r.ExitCode -eq 0) { return @{ Pass = $true; Reason = 'test passed' } }
    $first = ($out -split "`n" | Where-Object { $_.Trim() } | Select-Object -First 1)
    return @{ Pass = $false; Reason = "test did not pass (exit $($r.ExitCode)): $first" }
}

function Assert-JsonShape {
    # Family D: extract the first JSON object from the answer, parse it, and require exact values.
    # Prose around it is tolerated; a missing or wrong field is not.
    param(
        [Parameter(Mandatory = $true)][string]$Answer,
        [Parameter(Mandatory = $true)]$Expect
    )
    $m = [regex]::Match("$Answer", '\{.*\}', 'Singleline')
    if (-not $m.Success) { return @{ Pass = $false; Reason = 'no JSON object found in the answer' } }
    $obj = $null
    try { $obj = $m.Value | ConvertFrom-Json } catch { return @{ Pass = $false; Reason = "JSON did not parse: $($_.Exception.Message)" } }
    foreach ($k in $Expect.Keys) {
        $want = "$($Expect[$k])"
        $got = ''
        if ($obj.PSObject.Properties.Name -contains $k) { $got = "$($obj.$k)" }
        if ($got -ne $want) { return @{ Pass = $false; Reason = "field $k expected [$want] got [$got]" } }
    }
    return @{ Pass = $true; Reason = 'JSON parsed and every required field matched' }
}

function Assert-OneLineChanged {
    # Family D: exactly one line may differ from the original, and it must be the corrected one.
    # This catches the model that "fixes" the file by rewriting the whole thing - which in real use
    # means an unreviewable diff.
    param(
        [Parameter(Mandatory = $true)][string]$Answer,
        [Parameter(Mandatory = $true)][string]$OriginalPath,
        [Parameter(Mandatory = $true)][string]$ExpectLine
    )
    # Preserve empty lines and each line ending.  The contract says byte-identical, so trimming
    # whitespace or normalising newlines would enforce a weaker, different task.
    $utf8 = New-Object System.Text.UTF8Encoding($false)
    $origText = [IO.File]::ReadAllText($OriginalPath, $utf8)
    $splitLines = {
        param([string]$Text)
        $lines = New-Object System.Collections.Generic.List[string]
        foreach ($m in [regex]::Matches($Text, '(?s).*?(?:\r\n|\n|\r|\z)')) {
            if ($m.Value.Length -gt 0) { $lines.Add($m.Value) }
        }
        return $lines.ToArray()
    }
    $cand = @(& $splitLines "$Answer")
    $o = @(& $splitLines $origText)
    if ($cand.Count -ne $o.Count) {
        return @{ Pass = $false; Reason = "expected $($o.Count) lines, got $($cand.Count) - line count or final newline changed" }
    }
    $diff = @()
    for ($i = 0; $i -lt $o.Count; $i++) { if ($cand[$i] -ne $o[$i]) { $diff += $i } }
    if ($diff.Count -eq 0) { return @{ Pass = $false; Reason = 'nothing was changed' } }
    if ($diff.Count -gt 1) { return @{ Pass = $false; Reason = "$($diff.Count) lines changed, exactly 1 allowed" } }
    $old = $o[$diff[0]]
    $eol = ''
    if ($old.EndsWith("`r`n")) { $eol = "`r`n" } elseif ($old.EndsWith("`n")) { $eol = "`n" } elseif ($old.EndsWith("`r")) { $eol = "`r" }
    if ($cand[$diff[0]] -ne ($ExpectLine + $eol)) {
        return @{ Pass = $false; Reason = "line $($diff[0]+1) is not the expected replacement with its original line ending" }
    }
    return @{ Pass = $true; Reason = 'exactly the incorrect line was corrected' }
}

function Get-QualityHardTaskList {
    $toolReadFile = @{
        type = 'function'
        function = @{
            name = 'read_file'
            description = 'Read a text file relative to the working directory and return its contents.'
            parameters = @{ type = 'object'; properties = @{ path = @{ type = 'string' } }; required = @('path') }
        }
    }
    $toolListDir = @{
        type = 'function'
        function = @{
            name = 'list_dir'
            description = 'List the file names inside a directory of the working directory.'
            parameters = @{ type = 'object'; properties = @{ path = @{ type = 'string' } }; required = @('path') }
        }
    }

    return @(
        # ---------- A: multi-file consistency ----------
        @{ Id = 'hard-multifile-rename'; Family = 'multifile'; MaxTokens = 900; SubDir = 'mini1'
           Prompt = 'In the subdirectory mini1 there is a small PowerShell project (lib.ps1, main.ps1, test.ps1). The function Get-Total must be renamed to Get-Sum in its definition AND at every call site, so that running test.ps1 reports TEST-PASS. Output a PowerShell script that performs the edits; it will be executed with mini1 as the working directory.'
           Check = 'Assert-SuiteTest' }

        @{ Id = 'hard-multifile-param'; Family = 'multifile'; MaxTokens = 900; SubDir = 'mini2'
           Prompt = 'In the subdirectory mini2 there is a small PowerShell project (lib.ps1, main.ps1, test.ps1). Add a parameter -Unit to Format-Line so that the test passes: calling Format-Line -Name "sum" -Amount 42 -Unit "EUR" must return the string "sum=42 EUR", while existing calls that omit -Unit keep working unchanged. Output a PowerShell script that performs the edits; it will be executed with mini2 as the working directory.'
           Check = 'Assert-SuiteTest' }

        @{ Id = 'hard-multifile-bug'; Family = 'multifile'; MaxTokens = 900; SubDir = 'mini3'
           Prompt = 'In the subdirectory mini3 there is a small PowerShell project (lib.ps1, main.ps1, test.ps1). Running test.ps1 currently fails. The function definition in lib.ps1 is authoritative; the defect is elsewhere. Fix it so test.ps1 reports TEST-PASS. Output a PowerShell script that performs the edit; it will be executed with mini3 as the working directory.'
           Check = 'Assert-SuiteTest' }

        @{ Id = 'hard-multifile-constant'; Family = 'multifile'; MaxTokens = 900; SubDir = 'mini4'
           Prompt = 'In the subdirectory mini4 there is a small PowerShell project (lib.ps1, main.ps1, test.ps1). A constant is defined in lib.ps1 but main.ps1 ignores it and hardcodes its own value. Make main.ps1 use the constant from lib.ps1 so that test.ps1 reports TEST-PASS. Output a PowerShell script that performs the edit; it will be executed with mini4 as the working directory.'
           Check = 'Assert-SuiteTest' }

        # ---------- B: long-context retrieval ----------
        # ContextFile makes the runner inline the fixture into the prompt. WITHOUT it these tasks say
        # 'Read <file>' while supplying neither the content nor a tool, so no model can answer them -
        # and the model that replies 'I will read the file' looks like it failed. Five tasks were
        # unanswerable on the first hard run for exactly this reason.
        @{ Id = 'hard-ctx-log'; Family = 'context'; MaxTokens = 300
           Prompt = 'Read big/app.log. Exactly one line is an ERROR (uppercase) line. Reply with only the request_id value from that line.
'
           ContextFile = 'big/app.log'; Check = 'Assert-AnswerExact'; Expect = 'req-8f4c2b91' }

        @{ Id = 'hard-ctx-config'; Family = 'context'; MaxTokens = 300
           Prompt = 'Read big/config-dump.txt. The setting max_connections appears in more than one section. Reply with only the single numeric value that is actually in effect, following the rule stated in the header of the file.'
           ContextFile = 'big/config-dump.txt'; Check = 'Assert-AnswerExact'; Expect = '512' }

        @{ Id = 'hard-ctx-changelog'; Family = 'context'; MaxTokens = 300
           Prompt = 'Read big/CHANGELOG.txt and reply with only the version that introduced retry on 429 responses.'
           ContextFile = 'big/CHANGELOG.txt'; Check = 'Assert-AnswerExact'; Expect = 'v3.4.2' }

        # ---------- C: tool chains with a fatal intermediate ----------
        @{ Id = 'hard-tool-newest-report'; Family = 'tool'; MaxTokens = 400
           Prompt = 'Use the tools to find the report file in the reports directory whose name contains the most recent date, and read it. Reply with only the token it contains. Read the file - do not guess.'
           Tools = @($toolListDir, $toolReadFile)
           Check = 'Assert-ToolTask'
           Expect = @{ MinCalls = 2; RequireCalls = @('list_dir', 'read_file'); PathLike = 'report-2026-08-14.txt'; AnswerContains = 'TOKEN-0814' } }

        @{ Id = 'hard-tool-recover'; Family = 'tool'; MaxTokens = 500
           Prompt = 'Try to read reports/latest.txt. If that file does not exist, find the most recent report in the reports directory instead and read that one. Reply with only the token it contains.'
           Tools = @($toolListDir, $toolReadFile)
           Check = 'Assert-ToolTask'
           Expect = @{ MinCalls = 2; RequireCalls = @('read_file'); PathLike = 'report-2026-08-14.txt'; AnswerContains = 'TOKEN-0814' } }

        @{ Id = 'hard-tool-multihop'; Family = 'tool'; MaxTokens = 400
           Prompt = 'Read reports/pointer.txt. It names another file. Read that file too and reply with only the token it contains.'
           Tools = @($toolReadFile, $toolListDir)
           Check = 'Assert-ToolTask'
           Expect = @{ MinCalls = 2; RequireCalls = @('read_file'); PathLike = 'report-2026-08-14.txt'; AnswerContains = 'TOKEN-0814' } }

        # ---------- D: instruction precision ----------
        @{ Id = 'hard-precision-json'; Family = 'precision'; MaxTokens = 300
           Prompt = 'Read sum.txt, in which every line has the form "key: value". Reply with ONLY a JSON object containing exactly the keys name, count and total, with count and total as numbers and the values taken from the file. No prose, no code fence.'
           ContextFile = 'sum.txt'; Check = 'Assert-JsonShape'
           Expect = @{ name = 'atlas'; count = '7'; total = '1284' } }

        @{ Id = 'hard-precision-oneline'; Family = 'precision'; MaxTokens = 400
           Prompt = 'Read editme.txt. Exactly one line violates the policy stated in the file header: the retry count is wrong. Reply with ONLY the complete corrected file content - every other line must be byte-identical to the original, and nothing may be added or removed.'
           Check = 'Assert-OneLineChanged'
           ContextFile = 'editme.txt'; Expect = 'retries=3'; OriginalFile = 'editme.txt' }
    )
}

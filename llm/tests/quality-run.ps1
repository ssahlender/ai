# Run the quality task set against ONE model and record raw evidence.
#
#   quality-run.ps1 -Mode katcoder25              # one model, 12 tasks, results as JSON
#
# Kept separate from quality-verdict.ps1 on purpose: this script only MEASURES (it never decides),
# and it writes one JSON per model so the verdict can be recomputed later from the same evidence.
#
# Safety posture: generated code is EXECUTED. It is denylisted, path-scoped to the fixture
# directory, and hard-timed-out before it runs (see quality-tasks.ps1). Tool calls are answered by
# local mocks reading the same fixture directory - nothing outbound, no network access by the model.

[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)][string]$Mode,
    [int]$Port = 9080,
    [int]$Replicates = 1,
    [string[]]$Only,
    # base = the round-1 12-task set (kept reproducible); hard = round 2, which is the one that can
    # actually separate capable models. Round 1 was passed 12/12 by both candidates.
    [ValidateSet('base', 'hard')][string]$TaskSet = 'base',
    # Passed straight through to start-llm.ps1. Exists so the same model can be served with and without
    # --no-reasoning-preserve: several Qwen templates prepend reasoning tokens by default, which roughly
    # doubles time-per-answer, and that flag turned out to be the measured cause of a 2x slowdown.
    [string[]]$ServerArgs,
    # Forwarded to start-llm.ps1 as --reasoning off. This is the flag that actually suppresses
    # chain-of-thought; the measured swing is 12/12 in 6.0 s (off) versus 5/12 in 32.9 s (on).
    [switch]$NoThinking,
    [string]$FixtureDir,
    [string]$LlmRoot,
    [string]$OutDir,
    # HTTP client timeout per request. 300 was too short: a 12 K-token context task prefills in ~4-5 min
    # on this CPU and was aborted mid-flight, which recorded as a model failure. A genuine hang is still
    # caught by the SYSTEM task's own cap.
    [int]$TimeoutSec = 1200,
    [int]$CodeTimeoutMs = 60000,
    [switch]$KeepServer
)

$ErrorActionPreference = 'Continue'
. (Join-Path (Split-Path $PSScriptRoot -Parent) 'lib\common.ps1')
. (Join-Path $PSScriptRoot 'quality-tasks.ps1')

$llmRoot = Get-LlmRoot -Override $LlmRoot
if (-not $FixtureDir) { $FixtureDir = Join-Path $env:ProgramData 'llm-quality-fixtures' }
if (-not $OutDir) { $OutDir = Get-RunLogDir -LlmRoot $llmRoot }
$stamp = (Get-Date).ToString('yyyyMMdd-HHmmss')
$resultPath = Join-Path $OutDir ("quality-$Mode-$stamp.json")

if ($TaskSet -eq 'hard') {
    . (Join-Path $PSScriptRoot 'quality-tasks-hard.ps1')
    $null = New-QualityHardFixture -Dir $FixtureDir
} else {
    $null = New-QualityFixture -Dir $FixtureDir
}

function Invoke-ProcessCapture {
    # Execute a child process with a HARD timeout. Invoke-NativeToFile has no timeout, and a
    # generated script that never exits would otherwise hang the whole run.
    param(
        [Parameter(Mandatory = $true)][string]$Exe,
        [string[]]$Arguments = @(),
        [string]$WorkDir,
        [int]$TimeoutMs = 60000
    )
    $psi = New-Object System.Diagnostics.ProcessStartInfo
    $psi.FileName = $Exe
    $quoted = @()
    foreach ($a in $Arguments) {
        if ($a -match '\s') { $quoted += ('"' + $a + '"') } else { $quoted += $a }
    }
    $psi.Arguments = ($quoted -join ' ')
    $psi.UseShellExecute = $false
    $psi.RedirectStandardOutput = $true
    $psi.RedirectStandardError = $true
    $psi.CreateNoWindow = $true
    if ($WorkDir) { $psi.WorkingDirectory = $WorkDir }
    $p = [System.Diagnostics.Process]::Start($psi)
    $outTask = $p.StandardOutput.ReadToEndAsync()
    $errTask = $p.StandardError.ReadToEndAsync()
    if (-not $p.WaitForExit($TimeoutMs)) {
        try { $p.Kill() } catch { }
        return @{ ExitCode = -1; Out = ''; Err = "timed out after ${TimeoutMs}ms"; TimedOut = $true }
    }
    return @{ ExitCode = $p.ExitCode; Out = $outTask.Result; Err = $errTask.Result; TimedOut = $false }
}

function Get-EffectivePrompt {
    # A task that says 'read <file>' must actually RECEIVE the file. With no tools and no content, the
    # prompt is unanswerable and the model is scored zero for something no model could do. ContextFile
    # inlines the fixture (that is the long-context and precision families' whole point).
    param($Task)
    $p = "$($Task.Prompt)".TrimEnd()
    if ($Task.ContextFile) {
        $cf = Join-Path $script:FixtureDir $Task.ContextFile
        if (Test-Path $cf) {
            $p = $p + "`n`n----- BEGIN " + $Task.ContextFile + " -----`n" + (Get-Content $cf -Raw) + "`n----- END " + $Task.ContextFile + " -----"
        } else {
            $p = $p + "`n`n[fixture " + $Task.ContextFile + " NOT FOUND]"
        }
    }
    return $p
}

function Invoke-Chat {
    param(
        [array]$Messages,
        [array]$Tools,
        [int]$MaxTokens = 400,
        [int]$Seed = 1
    )
    $body = [ordered]@{
        model       = 'local'
        messages    = $Messages
        temperature = 0
        seed        = $Seed
        max_tokens  = $MaxTokens
        stream      = $false
    }
    if ($Tools -and @($Tools).Count -gt 0) {
        $body['tools'] = @($Tools)
        $body['tool_choice'] = 'auto'
    }
    $json = $body | ConvertTo-Json -Depth 14 -Compress
    $sw = [Diagnostics.Stopwatch]::StartNew()
    try {
        $r = Invoke-RestMethod -Uri "http://127.0.0.1:$Port/v1/chat/completions" -Method Post `
            -ContentType 'application/json' -Body $json -TimeoutSec $TimeoutSec -ErrorAction Stop
        $sw.Stop()
        return @{ Ok = $true; Response = $r; Ms = $sw.ElapsedMilliseconds; Err = '' }
    } catch {
        $sw.Stop()
        return @{ Ok = $false; Response = $null; Ms = $sw.ElapsedMilliseconds; Err = $_.Exception.Message }
    }
}

function Get-MessageText {
    # Reasoning models (some templates preserve reasoning by default) may return an empty
    # content field with the work in reasoning_content. Scoring only `content` would fail such a
    # model for a packaging difference rather than a capability one, so fall back - and the raw
    # fields are kept in the evidence so this choice is auditable.
    param($Msg)
    $t = ''
    if ($Msg.content) { $t = "$($Msg.content)" }
    if ((-not $t.Trim()) -and $Msg.reasoning_content) { $t = "$($Msg.reasoning_content)" }
    return $t
}

function Get-ToolCalls {
    param($Msg)
    $res = @()
    $n = 0
    foreach ($tc in @($Msg.tool_calls)) {
        if (-not $tc) { continue }
        $n++
        $args = "$($tc.function.arguments)"
        $obj = $null
        if ($args.Trim()) {
            try { $obj = $args | ConvertFrom-Json } catch { $obj = $null }
        }
        $id = "$($tc.id)"
        if (-not $id.Trim()) { $id = "call_$n" }
        $res += [pscustomobject]@{ Id = $id; Name = "$($tc.function.name)"; Arguments = $args; ArgsObject = $obj }
    }
    return $res
}

function Resolve-FixturePath {
    param([string]$Relative)
    $root = [IO.Path]::GetFullPath($FixtureDir)
    $full = [IO.Path]::GetFullPath((Join-Path $root $Relative))
    if (-not $full.StartsWith($root, [StringComparison]::OrdinalIgnoreCase)) {
        throw 'path escapes the fixture directory'
    }
    return $full
}

function Invoke-MockTool {
    # The tools the model can call, answered from the fixture directory. Read-only by construction.
    param([string]$Name, $ArgsObject, [int]$CallId)
    $rel = ''
    if ($ArgsObject -and $ArgsObject.PSObject.Properties.Name -contains 'path') { $rel = "$($ArgsObject.path)" }
    try {
        switch ($Name) {
            'read_file' {
                if (-not $rel) { return '{"error":"path is required"}' }
                $f = Resolve-FixturePath -Relative $rel
                if (-not (Test-Path $f)) { return '{"error":"no such file"}' }
                $c = (Get-Content $f -Raw)
                return ((@{ path = $rel; contents = "$c".Trim() } | ConvertTo-Json -Compress))
            }
            'list_dir' {
                if (-not $rel) { return '{"error":"path is required"}' }
                $d = Resolve-FixturePath -Relative $rel
                if (-not (Test-Path $d)) { return '{"error":"no such directory"}' }
                return ((@{ path = $rel; entries = @(Get-ChildItem $d -File | Select-Object -ExpandProperty Name) } | ConvertTo-Json -Compress))
            }
            'get_time' { return '{"time":"2026-09-26T12:00:00Z"}' }
            default { return ('{"error":"unknown tool ' + $Name + '"}') }
        }
    } catch {
        return ('{"error":"' + ($_.Exception.Message -replace '"', "'") + '"}')
    }
}

function Invoke-GeneratedCode {
    # Write the answer (plus our trusted test block, for fix tasks) as a script and run it with a
    # timeout. -WorkDir is where it runs: the fixture root for a one-liner task, a project subdirectory
    # for the multi-file tasks, so relative paths in the answer resolve the way an agent would expect.
    param([string]$Code, [string]$AppendTest, [int]$TimeoutMs = 60000, [string]$WorkDir)
    if (-not $WorkDir) { $WorkDir = $FixtureDir }
    $script = Join-Path $WorkDir ('gen-' + [guid]::NewGuid().ToString('N') + '.ps1')
    $lines = @($Code)
    if ($AppendTest) { $lines += $AppendTest }
    Write-Utf8NoBom -Path $script -Lines $lines
    $exe = Join-Path $env:SystemRoot 'System32\WindowsPowerShell\v1.0\powershell.exe'
    $r = Invoke-ProcessCapture -Exe $exe -Arguments @('-NoProfile', '-ExecutionPolicy', 'Bypass', '-File', $script) -WorkDir $WorkDir -TimeoutMs $TimeoutMs
    Remove-Item $script -Force -ErrorAction SilentlyContinue
    return $r
}

function Invoke-ToolTask {
    # A real agentic loop: send, answer each tool call from the mocks, re-send, until the model
    # stops calling tools or we hit the turn cap. Judged on the calls it made AND its final text.
    param($Task, [int]$Seed)
    $messages = @(@{ role = 'user'; content = (Get-EffectivePrompt -Task $Task) })
    $calls = @()
    $final = ''
    $ms = 0
    $turns = 0
    while ($turns -lt 4) {
        $turns++
        $r = Invoke-Chat -Messages $messages -Tools $Task.Tools -MaxTokens $Task.MaxTokens -Seed $Seed
        $ms += $r.Ms
        if (-not $r.Ok) { return @{ Text = ''; Calls = $calls; Err = $r.Err; Ms = $ms } }
        $msg = $r.Response.choices[0].message
        $tc = @(Get-ToolCalls -Msg $msg)
        if ($tc.Count -eq 0) { $final = Get-MessageText -Msg $msg; break }
        $calls += $tc
        $assistantCalls = @()
        foreach ($c in $tc) {
            $assistantCalls += @{ id = $c.Id; type = 'function'; function = @{ name = $c.Name; arguments = $c.Arguments } }
        }
        $messages += @{ role = 'assistant'; content = (Get-MessageText -Msg $msg); tool_calls = $assistantCalls }
        foreach ($c in $tc) {
            $res = Invoke-MockTool -Name $c.Name -ArgsObject $c.ArgsObject -CallId 0
            $messages += @{ role = 'tool'; tool_call_id = $c.Id; content = $res }
        }
    }
    return @{ Text = $final; Calls = $calls; Err = ''; Ms = $ms }
}

function Invoke-TaskCheck {
    # One dispatcher, because each family needs different arguments and PowerShell rejects an unknown
    # parameter name - passing every possible argument to every check would fail outright.
    param($Task, [string]$Answer, $Calls, [string]$FixtureDir, [string]$ExecOut, [string]$ExecErr, [int]$ExitCode)
    switch ("$($Task.Check)") {
        'Assert-SuiteTest' {
            return (& $Task.Check -FixtureDir $FixtureDir -SubDir "$($Task.SubDir)")
        }
        'Assert-AnswerExact' {
            return (& $Task.Check -Answer $Answer -Expect "$($Task.Expect)")
        }
        'Assert-JsonShape' {
            return (& $Task.Check -Answer $Answer -Expect $Task.Expect)
        }
        'Assert-OneLineChanged' {
            return (& $Task.Check -Answer $Answer -OriginalPath (Join-Path $FixtureDir "$($Task.OriginalFile)") -Expect "$($Task.Expect)")
        }
        'Assert-ToolTask' {
            return (& $Task.Check -Answer $Answer -Calls @($Calls) -Expect $Task.Expect)
        }
        'Assert-ExecOutput' {
            return (& $Task.Check -Answer $Answer -FixtureDir $FixtureDir -Expect "$($Task.Expect)" `
                -ExecOutput $ExecOut -ExecError $ExecErr -ExitCode $ExitCode)
        }
        default { return @{ Pass = $false; Reason = "unknown check: $($Task.Check)" } }
    }
}

# ------------------------------------------------------------------ start the server
$startScript = Join-Path (Split-Path $PSScriptRoot -Parent) 'start-llm.ps1'
if (Test-PortOpen -Port $Port) {
    throw "port $Port is already in use - refusing to run against a server this script did not start. Stop it first."
}

Write-Host ''
Write-Host "=== quality run: $Mode ==="
Write-Host "  fixtures : $FixtureDir"
Write-Host "  results  : $resultPath"

$exitCode = 0
$taskCount = 0
$results = @()
try {
    $startOut = (& $startScript -Mode $Mode -Background -Port $Port -ExtraArgs $ServerArgs -NoThinking:$NoThinking 2>&1 | Out-String)
    foreach ($l in @($startOut.Trim() -split "`n")) {
        if ($l.Trim()) { Write-Host ("  start: " + $l.Trim()) }
    }
    $ready = Wait-ServerHealth -Port $Port -TimeoutSec 420 -IntervalSec 3
    if (-not $ready.Ok) {
        throw "model '$Mode' never became healthy on port $Port after $($ready.Waited)s (exited: $($ready.Exited))"
    }
    Write-Host "  model healthy after $($ready.Waited)s"

    $tasks = @(Get-QualityTaskList)
    if ($TaskSet -eq 'hard') { $tasks = @(Get-QualityHardTaskList) }
    if ($Only) {
        # -Only exists for smoke tests and for the pre-registered tie-breaker re-run of just the
        # discordant tasks. Wildcards are allowed ('tool-*').
        $keep = @()
        foreach ($t in $tasks) {
            foreach ($pat in $Only) { if ($t.Id -like $pat) { $keep += $t; break } }
        }
        $tasks = $keep
    }
    $taskCount = $tasks.Count
    Write-Host "  tasks to run: $taskCount"
    foreach ($t in $tasks) {
        for ($rep = 1; $rep -le $Replicates; $rep++) {
            Write-Host ("  [{0,-4}] {1,-20} rep {2}/{3}" -f $t.Family, $t.Id, $rep, $Replicates)
            $check = @{ Pass = $false; Reason = 'not run' }
            $text = ''
            $calls = @()
            $ms = 0
            $err = ''
            $candidateCount = 0

            if ($t.Family -eq 'tool') {
                $r = Invoke-ToolTask -Task $t -Seed $rep
                $text = $r.Text
                $ms = $r.Ms
                $err = $r.Err
                if ($err) {
                    $check = @{ Pass = $false; Reason = "request failed: $err" }
                } else {
                    $check = Invoke-TaskCheck -Task $t -Answer $text -Calls @($r.Calls) -FixtureDir $FixtureDir -ExecOut '' -ExecErr '' -ExitCode 0
                }
                $calls = @($r.Calls | ForEach-Object { @{ name = $_.Name; arguments = $_.Arguments } })
            } else {
                $r = Invoke-Chat -Messages @(@{ role = 'user'; content = (Get-EffectivePrompt -Task $t) }) -Tools $null -MaxTokens $t.MaxTokens -Seed $rep
                $ms = $r.Ms
                $err = $r.Err
                if (-not $r.Ok) {
                    $check = @{ Pass = $false; Reason = "request failed: $err" }
                } else {
                    $text = Get-MessageText -Msg $r.Response.choices[0].message
                    if ($t.Check -notin @('Assert-ExecOutput', 'Assert-SuiteTest')) {
                        # Text-only families (long-context retrieval, instruction precision): there is
                        # nothing to execute - the answer itself is the artifact under test.
                        $check = Invoke-TaskCheck -Task $t -Answer $text -Calls @() -FixtureDir $FixtureDir -ExecOut '' -ExecErr '' -ExitCode 0
                    } else {
                        # Try each alternative the model offered; the task passes if ANY of them
                        # produces the expected output. See Get-CodeCandidates for why.
                        $cands = @(Get-CodeCandidates -Text $text -Max 3)
                        $tried = 0
                        $unparseable = 0
                        $denied = ''
                        $check = @{ Pass = $false; Reason = 'no candidate produced the expected output' }
                        # Multi-file tasks run inside their project subdirectory, so relative paths in
                        # the answer resolve the way an agent would expect.
                        $workDir = $FixtureDir
                        if ($t.PSObject.Properties.Name -contains 'SubDir' -and $t.SubDir) { $workDir = Join-Path $FixtureDir $t.SubDir }
                        foreach ($cand in $cands) {
                            $deny = Get-CodeDenyReason -Code $cand
                            if ($deny) { $denied = $deny; continue }
                            # Skip candidates that are not even valid PowerShell (typically a fenced
                            # reasoning block) and move on to the next one the model offered.
                            if (-not (Test-CodeParses -Code $cand)) { $unparseable++; continue }
                            $tried++
                            $ex = Invoke-GeneratedCode -Code $cand -AppendTest $t.AppendTest -TimeoutMs $CodeTimeoutMs -WorkDir $workDir
                            $res = Invoke-TaskCheck -Task $t -Answer $cand -Calls @() -FixtureDir $FixtureDir -ExecOut $ex.Out -ExecErr $ex.Err -ExitCode $ex.ExitCode
                            $check = $res
                            if ($res.Pass) { break }
                        }
                        if ($tried -eq 0 -and $denied) { $check = @{ Pass = $false; Reason = $denied } }
                        $candidateCount = $tried
                    }
                }
            }

            $pass = [bool]$check.Pass
            $reason = "$($check.Reason)"
            $results += [ordered]@{
                id        = $t.Id
                family    = $t.Family
                replicate = $rep
                pass      = $pass
                reason    = $reason
                candidates = $candidateCount
                ms        = $ms
                calls     = $calls
                answer    = $text
            }
            $label = 'PASS'
            if (-not $pass) { $label = "FAIL: $reason" }
            Write-Host "        -> $label"
        }
    }
} catch {
    Write-Host ("  ABORTED: " + $_.Exception.Message)
    $exitCode = 1
} finally {
    if (-not $KeepServer) {
        $null = Stop-ServerOnPort -Port $Port -Confirm
    }
}

$familySummary = @{}
foreach ($fam in @($results | ForEach-Object { $_.family } | Select-Object -Unique)) {
    $of = @($results | Where-Object { $_.family -eq $fam })
    $pass = @($of | Where-Object { $_.pass }).Count
    $familySummary[$fam] = "$pass/$($of.Count)"
}

$doc = [ordered]@{
    mode        = $Mode
    stamp       = $stamp
    port        = $Port
    replicates  = $Replicates
    temperature = 0
    fixtureDir  = $FixtureDir
    taskSet     = $TaskSet
    serverArgs  = (($ServerArgs + $(if ($NoThinking) { @('--reasoning off') } else { @() })) -join ' ')
    taskCount   = $taskCount
    summary     = $familySummary
    results     = $results
}
[IO.File]::WriteAllText($resultPath, ($doc | ConvertTo-Json -Depth 14), (New-Object System.Text.UTF8Encoding($false)))

Write-Host ''
Write-Host "=== summary: $Mode ==="
foreach ($fam in @($results | ForEach-Object { $_.family } | Select-Object -Unique)) { Write-Host ("  {0,-5} {1}" -f $fam, $familySummary[$fam]) }
$requestFailures = @($results | Where-Object { $_.reason -like 'request failed*' }).Count
if ($requestFailures -gt 3) {
    Write-Host "  $requestFailures tasks failed at the HTTP layer - treating this run as invalid"
    $exitCode = 1
}
Write-Host "  evidence: $resultPath"
exit $exitCode

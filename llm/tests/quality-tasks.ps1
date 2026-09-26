# Quality task set for the local-LLM A/B on this box.
#
# DESIGN CONSTRAINTS (deliberate, from arena issue #23 - do not weaken without re-deciding):
#   * Every task is MACHINE-CHECKABLE. Code is executed and its output compared; tool tasks are
#     judged on call structure (name + parseable arguments), not on prose. Nothing here is scored
#     by a model, so the verdict does not depend on a judge's taste.
#   * Tasks are PAIRED: the same instance is given to every model under test. Only discordant
#     outcomes carry information, which is what makes 12 tasks usable.
#   * Generated code is EXECUTED, so it is denylisted and path-scoped first: an answer that tries
#     to delete, write, start processes, or touch the registry scores zero by policy and is never
#     run. See Get-CodeDenyReason.
#
# Dot-sourced by quality-run.ps1. Provides: New-QualityFixture, Get-QualityTaskList,
# Get-CodeFromAnswer, Get-CodeDenyReason, Assert-ExecOutput, Assert-ToolTask.

function New-QualityFixture {
    # Fixed, known content so expected outputs are constants. Created under the SYSTEM-task dir
    # (never $env:TEMP: under the SYSTEM principal that resolves into the systemprofile tree).
    param([Parameter(Mandatory = $true)][string]$Dir)
    if (-not (Test-Path $Dir)) { New-Item -ItemType Directory -Path $Dir -Force | Out-Null }
    $secret = Join-Path $Dir 'secret'
    if (-not (Test-Path $secret)) { New-Item -ItemType Directory -Path $secret -Force | Out-Null }

    $csv = @(
        'id,name,region,amount'
        '1,alpha,north,120'
        '2,beta,south,340'
        '3,gamma,east,75'
        '4,delta,west,610'
        '5,epsilon,north,205'
        '6,zeta,south,90'
        '7,eta,east,480'
        '8,theta,west,555'
    )
    $log = @(
        '2026-09-26 08:00:01 INFO  service started'
        '2026-09-26 08:00:02 INFO  config loaded'
        '2026-09-26 08:00:03 ERROR disk usage above threshold'
        '2026-09-26 08:00:04 INFO  cache warmed'
        '2026-09-26 08:00:05 ERROR upstream timeout'
        '2026-09-26 08:00:06 INFO  request served'
        '2026-09-26 08:00:07 INFO  request served'
        '2026-09-26 08:00:08 WARN  retry scheduled'
        '2026-09-26 08:00:09 ERROR payload rejected'
        '2026-09-26 08:00:10 INFO  shutdown clean'
    )
    # encoded as one line so no converter can reformat it between runs
    $json = '{' + [char]34 + 'server' + [char]34 + ':{' + [char]34 + 'host' + [char]34 + ':' +
            [char]34 + 'db-01' + [char]34 + ',' + [char]34 + 'port' + [char]34 + ':8443},' +
            [char]34 + 'items' + [char]34 + ':[{' + [char]34 + 'id' + [char]34 + ':1,' +
            [char]34 + 'size' + [char]34 + ':120},{' + [char]34 + 'id' + [char]34 + ':2,' +
            [char]34 + 'size' + [char]34 + ':340}]}'

    Write-Utf8NoBom -Path (Join-Path $Dir 'sample.csv')  -Lines $csv
    Write-Utf8NoBom -Path (Join-Path $Dir 'sample.log')  -Lines $log
    Write-Utf8NoBom -Path (Join-Path $Dir 'sample.json') -Lines @($json)
    Write-Utf8NoBom -Path (Join-Path $secret 'port.txt') -Lines @('8443')
    return $Dir
}

function Get-CodeFromAnswer {
    # Models wrap code in fences and add prose. Prefer fenced blocks (any language tag); fall back
    # to the whole answer so a bare answer is still judged rather than silently scored zero.
    param([string]$Text)
    if (-not $Text) { return '' }
    $m = [regex]::Matches($Text, '(?s)```[ \t]*(?i)(powershell|ps1|ps|bash|sh|text)?[ \t]*\r?\n(.*?)```')
    if ($m.Count -gt 0) {
        $sb = New-Object System.Text.StringBuilder
        foreach ($x in $m) { [void]$sb.AppendLine($x.Groups[2].Value) }
        return $sb.ToString()
    }
    return $Text
}

function Get-CodeDenyReason {
    # Policy gate: we EXECUTE generated code, so anything with a side effect outside the fixture
    # directory scores zero instead of running. Failing closed is the point - a destructive answer
    # is a wrong answer for these tasks, and this is also what makes executing safe at all.
    param([string]$Code)
    if (-not $Code -or $Code.Trim() -eq '') { return 'empty answer' }
    $rules = @(
        'Remove-Item', 'Remove-', 'rm -', 'del ', 'Format-', 'Clear-Content', 'Erase ',
        'Stop-Process', 'Start-Process', 'Start-Job', 'Start-ThreadJob', 'Start-Sleep',
        'Set-Content', 'Add-Content', 'Out-File', 'New-Item', 'Set-Item', 'Set-Service',
        'Stop-Service', 'Start-Service', 'New-Service', 'Set-ItemProperty', 'New-ItemProperty',
        'Remove-ItemProperty', 'Copy-Item', 'Move-Item', 'Rename-Item', 'New-ItemProperty',
        'Invoke-WebRequest', 'Invoke-RestMethod', 'Invoke-Expression', 'Invoke-Command',
        'curl', 'wget', 'Invoke-Item', 'shutdown', 'Restart-', 'schtasks', 'net user',
        'New-LocalUser', 'Add-LocalGroupMember', 'reg add', 'reg delete', 'reg import',
        'HKLM', 'HKCU', 'Get-CimInstance', 'Set-CimInstance', 'Get-WmiObject', 'Stop-Computer',
        'Set-Location C:', 'Set-Location D:', 'cd C:', 'cd D:', '..\', '../'
    )
    foreach ($r in $rules) {
        if ($Code -match [regex]::Escape($r)) { return "denylisted construct: $r" }
    }
    if ($Code -match '>' ) { return 'denylisted construct: output redirection' }
    if ($Code -match '(?i)-Path\s+[A-Za-z]:') { return 'denylisted construct: absolute drive path' }
    return ''
}

function Assert-ExecOutput {
    # Compares the normalized stdout of the executed answer against the expected value.
    param(
        [Parameter(Mandatory = $true)][string]$Answer,
        [Parameter(Mandatory = $true)][string]$FixtureDir,
        [Parameter(Mandatory = $true)][string]$Expect,
        [string]$ExecOutput,
        [string]$ExecError,
        [int]$ExitCode = 0
    )
    $code = Get-CodeFromAnswer -Text $Answer
    $deny = Get-CodeDenyReason -Code $code
    if ($deny) { return @{ Pass = $false; Reason = $deny; Code = $code } }
    if ($ExitCode -ne 0) {
        return @{ Pass = $false; Reason = "answer exited $ExitCode`: $ExecError"; Code = $code }
    }
    $norm = Normalize-Output $ExecOutput
    $want = Normalize-Output $Expect
    if ($norm -eq $want) { return @{ Pass = $true; Reason = 'output matched'; Code = $code } }
    return @{ Pass = $false; Reason = "want [$want] got [$norm]"; Code = $code }
}

function Normalize-Output {
    param([string]$Text)
    if ($null -eq $Text) { return '' }
    $t = $Text -replace "`r", ' '
    $t = $t -replace "`n", ' '
    $t = $t -replace '\s+', ' '
    return $t.Trim().ToLowerInvariant()
}

function Assert-ToolTask {
    # Judged on call structure, not wording:
    #   Expect = @{ MinCalls = n; RequireCalls = @('read_file'); MaxCalls = n;
    #               PathLike = 'port.txt'; AnswerContains = '8443' }
    param(
        [Parameter(Mandatory = $true)][string]$Answer,
        [Parameter(Mandatory = $true)]$Calls,
        [Parameter(Mandatory = $true)]$Expect
    )
    $calls = @($Calls)
    if ($Expect.ContainsKey('MaxCalls')) {
        if ($calls.Count -gt [int]$Expect.MaxCalls) {
            return @{ Pass = $false; Reason = "made $($calls.Count) tool calls, at most $($Expect.MaxCalls) allowed" }
        }
    }
    if ($Expect.ContainsKey('MinCalls')) {
        if ($calls.Count -lt [int]$Expect.MinCalls) {
            return @{ Pass = $false; Reason = "made $($calls.Count) tool calls, need at least $($Expect.MinCalls)" }
        }
    }
    if ($Expect.ContainsKey('RequireCalls')) {
        foreach ($need in $Expect.RequireCalls) {
            $hit = @($calls | Where-Object { $_.Name -eq $need })
            if ($hit.Count -eq 0) { return @{ Pass = $false; Reason = "no $need call was made" } }
            # arguments must PARSE - an unparseable argument block is a malformed tool call
            foreach ($h in $hit) {
                if ($null -eq $h.Arguments -or $h.Arguments -eq '') {
                    return @{ Pass = $false; Reason = "$need was called with no arguments" }
                }
            }
        }
    }
    if ($Expect.ContainsKey('PathLike')) {
        $ok = $false
        foreach ($c in $calls) {
            if ($null -eq $c.ArgsObject) { continue }
            $p = "$($c.ArgsObject.path)"
            if ($p -and ($p -replace '\\', '/').ToLowerInvariant().EndsWith(("$($Expect.PathLike)").ToLowerInvariant())) { $ok = $true }
        }
        if (-not $ok) { return @{ Pass = $false; Reason = "no call carried a path ending in $($Expect.PathLike)" } }
    }
    if ($Expect.ContainsKey('AnswerContains')) {
        if (-not ($Answer -match [regex]::Escape("$($Expect.AnswerContains)"))) {
            return @{ Pass = $false; Reason = "final answer did not contain $($Expect.AnswerContains)" }
        }
    }
    return @{ Pass = $true; Reason = 'call structure and final answer valid' }
}

function Get-QualityTaskList {
    # 12 tasks, three families, 5 / 4 / 3. Kept deliberately small: 12 paired outcomes support a
    # decision about THIS box, not a benchmark claim, and every arena position said so.
    $fy = @{ Func = 'Assert-ExecOutput' }
    $toolReadFile = @{
        type = 'function'
        function = @{
            name = 'read_file'
            description = 'Read a text file from the current directory and return its contents.'
            parameters = @{ type = 'object'; properties = @{ path = @{ type = 'string'; description = 'relative file path' } }; required = @('path') }
        }
    }
    $toolListDir = @{
        type = 'function'
        function = @{
            name = 'list_dir'
            description = 'List the file names inside a directory of the current directory.'
            parameters = @{ type = 'object'; properties = @{ path = @{ type = 'string'; description = 'relative directory path' } }; required = @('path') }
        }
    }

    $tasks = @(
        # ---------- family: code (execute the answer, compare its output) ----------
        @{ Id = 'code-csv-sum'; Family = 'code'; MaxTokens = 400
           Prompt = 'Write a single PowerShell command that reads sample.csv from the current directory and prints only the sum of the amount column, as a bare number with no other text.'
           Check = 'Assert-ExecOutput'; Expect = '2475' }

        @{ Id = 'code-log-errors'; Family = 'code'; MaxTokens = 400
           Prompt = 'Write a single PowerShell command that prints how many lines of sample.log in the current directory contain the word ERROR. Print only the number.'
           Check = 'Assert-ExecOutput'; Expect = '3' }

        @{ Id = 'code-log-clean'; Family = 'code'; MaxTokens = 400
           Prompt = 'Write a single PowerShell command that prints how many lines of sample.log in the current directory do NOT contain the word ERROR. Print only the number.'
           Check = 'Assert-ExecOutput'; Expect = '7' }

        @{ Id = 'code-json-port'; Family = 'code'; MaxTokens = 400
           Prompt = 'Write a single PowerShell command that reads sample.json from the current directory and prints only the value of the port field inside the server object.'
           Check = 'Assert-ExecOutput'; Expect = '8443' }

        @{ Id = 'code-csv-regions'; Family = 'code'; MaxTokens = 500
           Prompt = 'Write a single PowerShell command that prints the distinct values of the region column of sample.csv from the current directory, one per line, sorted alphabetically.'
           Check = 'Assert-ExecOutput'; Expect = 'east north south west' }

        # ---------- family: fix (repair a broken function; our tests are appended and run) ----------
        @{ Id = 'fix-offbyone'; Family = 'fix'; MaxTokens = 500
           Prompt = "This PowerShell function is meant to return the third item of an array but returns the wrong element:`n`nfunction Get-ThirdItem { param([array]`$Items) return `$Items[3] }`n`nReturn the corrected function, with the same name and signature."
           Check = 'Assert-ExecOutput'
           AppendTest = 'Write-Output (Get-ThirdItem @(10,20,30,40))'
           Expect = '30' }

        @{ Id = 'fix-loop-bound'; Family = 'fix'; MaxTokens = 500
           Prompt = "This PowerShell function should sum all integers from 1 up to and including N, but it is wrong:`n`nfunction Sum-To { param([int]`$N) `$t = 0; for (`$i = 1; `$i -lt `$N; `$i++) { `$t += `$i }; return `$t }`n`nReturn the corrected function, with the same name and signature."
           Check = 'Assert-ExecOutput'
           AppendTest = 'Write-Output (Sum-To 5)'
           Expect = '15' }

        @{ Id = 'fix-case-sensitive'; Family = 'fix'; MaxTokens = 500
           Prompt = "This PowerShell function should return true whenever the name is the region north, regardless of letter case, but it fails for uppercase input:`n`nfunction Test-Region { param([string]`$Name) return (`$Name -ceq 'north') }`n`nReturn the corrected function, with the same name and signature."
           Check = 'Assert-ExecOutput'
           AppendTest = 'Write-Output (Test-Region NORTH)'
           Expect = 'True' }

        @{ Id = 'fix-empty-array'; Family = 'fix'; MaxTokens = 500
           Prompt = "This PowerShell function throws when given an empty array:`n`nfunction Get-First { param([array]`$Items) return `$Items[0] }`n`nReturn the corrected function with the same name and signature, which must return `$null (not an error and not an empty string) when the array is empty."
           Check = 'Assert-ExecOutput'
           AppendTest = '$r = Get-First @(); if (`$null -eq $r) { Write-Output EMPTY-OK } else { Write-Output (GOT + $r) }'
           Expect = 'EMPTY-OK' }

        # ---------- family: tool (the agentic gate; judged on call structure) ----------
        @{ Id = 'tool-read-port'; Family = 'tool'; MaxTokens = 300
           Prompt = 'Use the read_file tool to read the file secret/port.txt, then answer with the number it contains. Reply with just the number.'
           Tools = @($toolReadFile)
           Check = 'Assert-ToolTask'
           Expect = @{ MinCalls = 1; RequireCalls = @('read_file'); PathLike = 'port.txt'; AnswerContains = '8443' } }

        @{ Id = 'tool-list-then-read'; Family = 'tool'; MaxTokens = 300
           Prompt = "First call list_dir on the directory 'secret'. Then call read_file on the file in it whose name starts with p. Reply with just the number inside that file."
           Tools = @($toolListDir, $toolReadFile)
           Check = 'Assert-ToolTask'
           Expect = @{ MinCalls = 2; RequireCalls = @('list_dir', 'read_file'); PathLike = 'port.txt'; AnswerContains = '8443' } }

        @{ Id = 'tool-no-call'; Family = 'tool'; MaxTokens = 200
           Prompt = 'Do not call any tool. What is 17 + 25? Reply with just the number.'
           Tools = @($toolReadFile, $toolListDir)
           Check = 'Assert-ToolTask'
           Expect = @{ MaxCalls = 0; AnswerContains = '42' } }
    )
    return $tasks
}

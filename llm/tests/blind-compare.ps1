<#
.SYNOPSIS
    Run one model through a fixed 5-prompt set and save its answers (for a blind A/B).

.DESCRIPTION
    Starts llama-server for a mode from start-llm.ps1, sends the same five prompts with
    identical sampling, writes the answers to a file, then stops the server.

    Run it once per mode, then present the two outputs side by side WITHOUT their labels
    and let the operator pick. The point is quality on real work, which no benchmark
    measures - the speed figures only say which model is affordable, not which is better.

    Sampling is fixed (temperature 0.2, top_p 0.95, max_tokens 320) and must not be
    varied between runs, or the comparison is meaningless.

.PARAMETER Mode
    Mode name from start-llm.ps1 (e.g. gemma4qat, qwen36u35b).

.PARAMETER OutFile
    Where to write the answers.

.EXAMPLE
    .\blind-compare.ps1 -Mode gemma4qat   -OutFile gemma.txt
    .\blind-compare.ps1 -Mode qwen36u35b  -OutFile qwen.txt
#>
[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)][string]$Mode,
    [Parameter(Mandatory = $true)][string]$OutFile,
    [int]$Port = 9080,
    [int]$MaxTokens = 320,
    [double]$Temperature = 0.2
)

$ErrorActionPreference = 'Stop'
$here = if ($PSScriptRoot) { $PSScriptRoot } else { Split-Path -Parent $MyInvocation.MyCommand.Path }
. (Join-Path (Split-Path -Parent $here) 'lib\common.ps1')
# start-llm.ps1 sits in llm\, this script in llm\tests\: probe BOTH instead of assuming a
# sibling, otherwise -File gets a path that does not exist and the launcher silently fails.
$startScript = @(
    (Join-Path $here 'start-llm.ps1')
    (Join-Path (Split-Path -Parent $here) 'start-llm.ps1')
) | Where-Object { Test-Path $_ } | Select-Object -First 1
if (-not $startScript) { throw "start-llm.ps1 not found beside $here or its parent" }

# Same prompts for every model. Covering: infra reasoning, shell scripting, German
# business writing, arithmetic, and code review.
$prompts = @(
    'Explain, in 5 short bullet points, how to safely put one node of a 3-node Proxmox VE cluster into maintenance without causing quorum loss.'
    'Write a bash one-liner that lists running Docker containers sorted by memory usage, showing only those over 2 GB.'
    'Schreibe eine kurze, freundliche E-Mail an einen Mieter, der die Miete drei Tage zu spaet bezahlt hat. Auf Deutsch, sachlich, ohne Drohung.'
    'A language model must read 2.3 GB of weights per generated token, and memory bandwidth is 89.6 GB/s. Show the arithmetic for the theoretical maximum tokens/s, then state which fraction is realistic in practice and why.'
    'Review this snippet and name the bug plus the fix: for f in $(ls /data/*.json); do jq -r .id $f >> ids.txt; done'
)

# Write the header and status BEFORE anything slow happens. A model load takes minutes and a
# long operation over WinRM can die with WSManFault 1359, so results are written as they arrive.
"# Answers: $Mode" | Set-Content $OutFile -Encoding UTF8
""                 | Add-Content $OutFile -Encoding UTF8
"starting server ($startScript)" | Set-Content "$OutFile.status" -Encoding UTF8

"=== $Mode : starting server ($startScript) ==="
# Do NOT pipe this to Out-Null: if the launcher cannot be found, that error is the only clue,
# and swallowing it turns a hard failure into a silent 300s wait for a port that never opens.
& powershell -NoProfile -ExecutionPolicy Bypass -File $startScript $Mode -Background -Port $Port 2>&1 |
    ForEach-Object { "  [start] $_" }
$health = Wait-ServerHealth -Port $Port -TimeoutSec 300 -IntervalSec 5
if (-not $health.Ok) {
    "FAILED: server did not become healthy after $($health.Waited)s ($($health.LastErr))" | Set-Content "$OutFile.status" -Encoding UTF8
    "FAILED: server did not become healthy after $($health.Waited)s ($($health.LastErr))"; exit 1
}
"  server healthy after ~$($health.Waited)s"

$sw = [Diagnostics.Stopwatch]::StartNew()
for ($i = 0; $i -lt $prompts.Count; $i++) {
    $n = $i + 1
    $body = @{
        model       = $Mode
        max_tokens  = $MaxTokens
        temperature = $Temperature
        top_p       = 0.95
        messages    = @(@{ role = 'user'; content = $prompts[$i] })
    } | ConvertTo-Json -Depth 6

    try {
        $sw2 = [Diagnostics.Stopwatch]::StartNew()
        $r = Invoke-RestMethod -Uri "http://127.0.0.1:$Port/v1/chat/completions" -Method Post `
                -ContentType 'application/json' -Body $body -TimeoutSec 600
        $sw2.Stop()
        $answer = $r.choices[0].message.content
        $tokens = $r.usage.completion_tokens
        $tps = if ($tokens -and $sw2.Elapsed.TotalSeconds -gt 0) {
                   [Math]::Round($tokens / $sw2.Elapsed.TotalSeconds, 2)
               } else { 'n/a' }
        "  prompt $n done ($tokens tok, $tps t/s)"
    } catch {
        $answer = "ERROR: $($_.Exception.Message)"
        "  prompt $n FAILED: $($_.Exception.Message)"
    }

    # append this answer immediately so partial progress is visible and survives a drop
    "## Prompt $n"                             | Add-Content $OutFile -Encoding UTF8
    ""                                         | Add-Content $OutFile -Encoding UTF8
    "> $($prompts[$i])"                        | Add-Content $OutFile -Encoding UTF8
    ""                                         | Add-Content $OutFile -Encoding UTF8
    "**Answer** ($tokens tokens, $tps t/s)"    | Add-Content $OutFile -Encoding UTF8
    ""                                         | Add-Content $OutFile -Encoding UTF8
    (($answer -replace "`r`n", "`n").Trim())   | Add-Content $OutFile -Encoding UTF8
    ""                                         | Add-Content $OutFile -Encoding UTF8
    "prompt $n/$($prompts.Count)"              | Set-Content "$OutFile.status" -Encoding UTF8
}
$sw.Stop()

# stop the server we started
Get-Process -Name llama-server -ErrorAction SilentlyContinue | Stop-Process -Force -ErrorAction SilentlyContinue
Start-Sleep -Seconds 2

"complete ($([Math]::Round($sw.Elapsed.TotalSeconds,1))s)" | Set-Content "$OutFile.status" -Encoding UTF8
"=== wrote $OutFile ($([Math]::Round($sw.Elapsed.TotalSeconds,1))s total) ==="

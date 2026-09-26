<#
.SYNOPSIS
    Ask a running llama-server the shared prompt suite and write the answers incrementally.

.DESCRIPTION
    Deliberately does NOT start or stop the server: the server lifecycle belongs to
    start-llm.ps1 and the executor to run-as-system-task.ps1. Nested launching inside a
    scheduled task hangs (Start-Process does not detach there), which is exactly how an
    earlier combined script ended up alive-but-blocked with a healthy server idle beside it.

    Prompt list comes from suite-prompts.txt so two models are provably asked the same
    thing. Sampling is fixed; do not vary it between runs or the comparison is meaningless.

.PARAMETER OutFile
    Where the answers are written. Written after EVERY prompt so a dropped session or a
    killed task cannot erase completed work.

.PARAMETER Label
    Name written into the header (e.g. the mode) - the operator must not see it when judging.

.PARAMETER Port
    Port of the already-running server. Default 9080.

.EXAMPLE
    .\ask-suite.ps1 -Label gemma4qat -OutFile C:\data\llm\blind-gemma.txt
#>
[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)][string]$OutFile,
    [Parameter(Mandatory = $true)][string]$Label,
    [int]$Port = 9080,
    [int]$MaxTokens = 320,
    [double]$Temperature = 0.2
)

$ErrorActionPreference = 'Stop'
$here = if ($PSScriptRoot) { $PSScriptRoot } else { Split-Path -Parent $MyInvocation.MyCommand.Path }

# prompts live beside this script, or one level up if it was moved into a subdirectory
$promptFile = @(
    (Join-Path $here 'suite-prompts.txt')
    (Join-Path (Split-Path -Parent $here) 'suite-prompts.txt')
) | Where-Object { Test-Path $_ } | Select-Object -First 1
if (-not $promptFile) { throw "suite-prompts.txt not found beside $here or its parent" }

$prompts = @(Get-Content $promptFile | Where-Object { $_.Trim() -ne '' })
if ($prompts.Count -eq 0) { throw "no prompts found in $promptFile" }

# fail fast and loudly if there is no usable server, rather than waiting for a timeout
$health = $null
try { $health = Invoke-RestMethod -Uri "http://127.0.0.1:$Port/health" -TimeoutSec 20 } catch { }
if (-not $health -or $health.status -ne 'ok') {
    "FAILED: no healthy server on port $Port (health: $($health | ConvertTo-Json -Compress))" |
        Set-Content "$OutFile.status" -Encoding UTF8
    throw "no healthy server on port $Port"
}

"# Answers: $Label" | Set-Content $OutFile -Encoding UTF8
""                  | Add-Content $OutFile -Encoding UTF8
"prompts: $promptFile" | Add-Content $OutFile -Encoding UTF8
""                  | Add-Content $OutFile -Encoding UTF8
"0/$($prompts.Count)" | Set-Content "$OutFile.status" -Encoding UTF8

$sw = [Diagnostics.Stopwatch]::StartNew()
for ($i = 0; $i -lt $prompts.Count; $i++) {
    $n = $i + 1
    $tokens = 'n/a'
    $tps = 'n/a'
    $body = @{
        model       = $Label
        max_tokens  = $MaxTokens
        temperature = $Temperature
        top_p       = 0.95
        messages    = @(@{ role = 'user'; content = $prompts[$i] })
    } | ConvertTo-Json -Depth 6

    try {
        $sw2 = [Diagnostics.Stopwatch]::StartNew()
        $r = Invoke-RestMethod -Uri "http://127.0.0.1:$Port/v1/chat/completions" -Method Post `
                -ContentType 'application/json' -Body $body -TimeoutSec 900
        $sw2.Stop()
        $answer = $r.choices[0].message.content
        $tokens = $r.usage.completion_tokens
        if ($tokens -and $sw2.Elapsed.TotalSeconds -gt 0) {
            $tps = [Math]::Round($tokens / $sw2.Elapsed.TotalSeconds, 2)
        }
        "  prompt $n done ($tokens tok, $tps t/s)"
    } catch {
        $answer = "ERROR: $($_.Exception.Message)"
        "  prompt $n FAILED: $($_.Exception.Message)"
    }

    # write immediately: partial progress must survive a dropped session
    "## Prompt $n"                            | Add-Content $OutFile -Encoding UTF8
    ""                                        | Add-Content $OutFile -Encoding UTF8
    "> $($prompts[$i])"                       | Add-Content $OutFile -Encoding UTF8
    ""                                        | Add-Content $OutFile -Encoding UTF8
    "**Answer** ($tokens tokens, $tps t/s)"   | Add-Content $OutFile -Encoding UTF8
    ""                                        | Add-Content $OutFile -Encoding UTF8
    (($answer -replace "`r`n", "`n").Trim())  | Add-Content $OutFile -Encoding UTF8
    ""                                        | Add-Content $OutFile -Encoding UTF8
    "$n/$($prompts.Count)"                    | Set-Content "$OutFile.status" -Encoding UTF8
}
$sw.Stop()

"complete ($([Math]::Round($sw.Elapsed.TotalSeconds,1))s)" | Set-Content "$OutFile.status" -Encoding UTF8
"=== wrote $OutFile ($([Math]::Round($sw.Elapsed.TotalSeconds,1))s total) ==="

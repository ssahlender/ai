<#
.SYNOPSIS
    Share the ProBook's local models with the home gateway through an outgoing SSH tunnel.

.DESCRIPTION
    Thin wrapper: the logic is llm\shared\share.py, the same code the i9 and the Mac run through
    llm/share.sh. llama-swap keeps listening on 127.0.0.1; the tunnel (ssh -R, Windows' own OpenSSH
    client) gives the gateway a port that leads to it. Runs in the foreground and reconnects when the tunnel
    ends (gateway restart, sleep, Wi-Fi change); Ctrl-C stops sharing. -Once: a single attempt.

.EXAMPLE
    .\share.ps1 -Init      # once: tunnel key + %USERPROFILE%\.config\llm\share.env, prints the gateway's key line
    .\share.ps1 -DryRun
    .\share.ps1
#>
[CmdletBinding()]
param(
    [switch]$Init,
    [switch]$DryRun,
    [switch]$Once
)

$ErrorActionPreference = 'Stop'
. (Join-Path $PSScriptRoot 'lib\common.ps1')

$pyArgs = @((Get-SharedFile 'share.py'))
if ($Init)   { $pyArgs += '--init' }
if ($DryRun) { $pyArgs += '--dry-run' }
if ($Once)   { $pyArgs += '--once' }
& (Resolve-Python) @pyArgs
# throw, not exit: exit would also end a calling session (PSRP, another script)
if ($LASTEXITCODE -ne 0) { throw "share.py failed (exit $LASTEXITCODE)" }

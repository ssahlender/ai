<#
.SYNOPSIS
    Wire the local model into every installed agent (OpenCode, Pi, Docker Agent) on the ProBook.

.DESCRIPTION
    Thin wrapper: the logic is llm\shared\setup_agents.py, the same code the i9 and the Mac run
    through llm/setup-agents.sh. Agents default to the llama-swap chain, http://127.0.0.1:9081/v1.

.EXAMPLE
    .\setup-agents.ps1 -DryRun
    .\setup-agents.ps1
    .\setup-agents.ps1 -BaseUrl http://127.0.0.1:9080/v1     # a bare start-llm.ps1 server instead
#>
[CmdletBinding()]
param(
    [switch]$DryRun,
    [string]$BaseUrl = ''
)

$ErrorActionPreference = 'Stop'
. (Join-Path $PSScriptRoot 'lib\common.ps1')

$pyArgs = @((Get-SharedFile 'setup_agents.py'), '--machine', 'probook')
if ($DryRun)  { $pyArgs += '--dry-run' }
if ($BaseUrl) { $pyArgs += @('--base-url', $BaseUrl) }
& (Resolve-Python) @pyArgs
exit $LASTEXITCODE

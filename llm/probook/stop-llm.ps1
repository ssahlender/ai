<#
.SYNOPSIS
    Stops the local model stack on the ProBook, whichever way it was started.

.DESCRIPTION
    llama-swap (if running), every llama-server.exe, and local-proxy.py (agent port 9081).
    Counterpart of llm/stop.sh (i9, Mac).

.EXAMPLE
    .\stop-llm.ps1
#>
[CmdletBinding()]
param()

$ErrorActionPreference = 'Stop'
. (Join-Path $PSScriptRoot 'lib\common.ps1')

foreach ($name in @('llama-swap', 'llama-server')) {
    $procs = Get-Process -Name $name -ErrorAction SilentlyContinue
    if ($procs) {
        $procs | Stop-Process -Force
        Write-Host ("{0} stopped (pid {1})" -f $name, ($procs.Id -join ', '))
    } else {
        Write-Host ("{0} not running" -f $name)
    }
}
$stopped = Stop-LocalProxyProcess
if ($stopped -gt 0) { Write-Host ("local-proxy stopped ({0} process(es))" -f $stopped) } else { Write-Host "local-proxy not running" }

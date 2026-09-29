<#
.SYNOPSIS
    Run one trusted script as a SYSTEM scheduled task and report its real scheduler state.

.DESCRIPTION
    Use this only for jobs that cannot survive a remote session. SYSTEM/Highest is a trust
    boundary: -Script must be an absolute .ps1 path in a directory writable only by
    administrators or SYSTEM. Do not hand it a checkout or download location writable by an
    untrusted user. The task is retained for inspection; remove it explicitly with -Unregister.

    The default 180-minute ceiling exceeds the longest expected model-load/benchmark job. Pass
    an explicit larger value when a job's documented worst case exceeds that ceiling.
#>
[CmdletBinding(DefaultParameterSetName = 'Run')]
param(
    [Parameter(Mandatory = $true, ParameterSetName = 'Run')][string]$Script,
    [string]$ScriptArgs = '',
    [string]$TaskName = 'llm-system-heavy-job',
    [int]$TimeoutMinutes = 180,
    [Parameter(Mandatory = $true, ParameterSetName = 'Unregister')][switch]$Unregister
)

$ErrorActionPreference = 'Stop'

if ($Unregister) {
    $old = Get-ScheduledTask -TaskName $TaskName -ErrorAction SilentlyContinue
    if (-not $old) { Write-Host "no task named '$TaskName' exists"; exit 0 }
    Unregister-ScheduledTask -TaskName $TaskName -Confirm:$false
    Write-Host "unregistered task '$TaskName' explicitly"
    exit 0
}

if (-not [IO.Path]::IsPathRooted($Script)) { throw "-Script must be an absolute path: $Script" }
if (-not (Test-Path -LiteralPath $Script -PathType Leaf)) { throw "script not found: $Script" }
if ($TimeoutMinutes -lt 1) { throw 'TimeoutMinutes must be positive' }
if (Get-ScheduledTask -TaskName $TaskName -ErrorAction SilentlyContinue) {
    throw "task '$TaskName' already exists. Inspect it, or remove it explicitly with -Unregister; it was not replaced."
}

# CreateNew is atomic. It is held by the SYSTEM action, so different task names cannot start
# two model loads at once. The ProgramData directory is admin/SYSTEM-owned on supported Windows.
$lockDir = Join-Path $env:ProgramData 'llm-system-tasks'
$lockPath = Join-Path $lockDir 'heavy-job.lock'
$quotedScript = $Script.Replace("'", "''")
$guard = "`$d='$lockDir'; `$l='$lockPath'; New-Item -ItemType Directory -Path `$d -Force | Out-Null; try { `$f=[IO.File]::Open(`$l,[IO.FileMode]::CreateNew,[IO.FileAccess]::Write,[IO.FileShare]::None) } catch { Write-Error 'another SYSTEM LLM job owns the single-instance lock'; exit 75 }; try { & '$quotedScript' $ScriptArgs; exit `$LASTEXITCODE } finally { `$f.Close(); Remove-Item -LiteralPath `$l -Force -ErrorAction SilentlyContinue }"
$encoded = [Convert]::ToBase64String([Text.Encoding]::Unicode.GetBytes($guard))
$action = New-ScheduledTaskAction -Execute 'powershell.exe' -Argument "-NoProfile -ExecutionPolicy Bypass -EncodedCommand $encoded" -WorkingDirectory (Split-Path $Script -Parent)
$principal = New-ScheduledTaskPrincipal -UserId 'SYSTEM' -LogonType ServiceAccount -RunLevel Highest
$settings = New-ScheduledTaskSettingsSet -AllowStartIfOnBatteries -DontStopIfGoingOnBatteries `
    -StartWhenAvailable -MultipleInstances IgnoreNew -ExecutionTimeLimit (New-TimeSpan -Minutes $TimeoutMinutes)

Register-ScheduledTask -TaskName $TaskName -Action $action -Principal $principal -Settings $settings | Out-Null
$before = Get-ScheduledTaskInfo -TaskName $TaskName
Start-ScheduledTask -TaskName $TaskName
Start-Sleep -Seconds 2
$task = Get-ScheduledTask -TaskName $TaskName
$info = Get-ScheduledTaskInfo -TaskName $TaskName
$started = $info.LastRunTime -gt $before.LastRunTime

Write-Host "task '$TaskName' registered; Start-ScheduledTask was accepted"
Write-Host ("  state          : {0}" -f $task.State)
Write-Host ("  last task code : {0}" -f $info.LastTaskResult)
Write-Host ("  actually started since registration: {0}" -f $started)
Write-Host ("  as SYSTEM/Highest; time limit: {0} min; global lock: {1}" -f $TimeoutMinutes, $lockPath)
if (-not $started) { Write-Warning "the scheduler did not record a start yet; this is NOT a success result. Inspect the task history." }
Write-Host ("  cleanup        : .\run-as-system-task.ps1 -TaskName '{0}' -Unregister" -f $TaskName)

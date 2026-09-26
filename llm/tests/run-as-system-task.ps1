<#
.SYNOPSIS
    Run a script as a SYSTEM scheduled task, for jobs too long to survive a remote session.

.DESCRIPTION
    A long-running operation over WinRM/PSRP can be terminated with WSManFault 1359
    ("An internal error occurred"), and anything started with Start-Process dies with the
    session anyway (Start-Process does not detach over WinRM). Multi-minute work - model
    loads, downloads, generation runs - therefore has to be handed to the task scheduler
    and polled by file, not run in the foreground of a remote shell.

    This registers the job as a SYSTEM task (no password needed, unlike a local user, for
    which S4U is refused on workgroup machines) and starts it. The script being run should
    write progress to a file so the caller can poll it - see blind-compare.ps1 for an
    example that writes <OutFile>.status as it goes.

.PARAMETER Script
    Full path of the .ps1 to run.

.PARAMETER ScriptArgs
    Argument string passed through to it, e.g. "-Mode gemma4qat -OutFile C:\x.txt".

.PARAMETER TaskName
    Task name; an existing task of the same name is replaced.

.PARAMETER TimeoutMinutes
    Execution time limit before the task is killed.

.EXAMPLE
    .\run-as-system-task.ps1 -Script C:\work\job.ps1 -ScriptArgs "-Mode gemma4qat" -TaskName my-job
#>
[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)][string]$Script,
    # A single argument STRING, not an array: 'powershell.exe -File' flattens arrays into
    # loose arguments, which then bind positionally and corrupt the callee's parameters.
    # Pass e.g. "-Mode gemma4qat -OutFile C:\data\llm\blind-gemma.txt".
    [string]$ScriptArgs = '',
    [string]$TaskName = 'hermes-long-job',
    [int]$TimeoutMinutes = 45
)

if (-not (Test-Path $Script)) { throw "script not found: $Script" }

$argString = "-NoProfile -ExecutionPolicy Bypass -File `"$Script`""
if ($ScriptArgs) { $argString = "$argString $ScriptArgs" }
$workDir = Split-Path $Script -Parent

$action = New-ScheduledTaskAction -Execute 'powershell.exe' -Argument $argString -WorkingDirectory $workDir
$principal = New-ScheduledTaskPrincipal -UserId 'SYSTEM' -LogonType ServiceAccount -RunLevel Highest
$settings = New-ScheduledTaskSettingsSet -AllowStartIfOnBatteries -DontStopIfGoingOnBatteries `
              -StartWhenAvailable -ExecutionTimeLimit (New-TimeSpan -Minutes $TimeoutMinutes)

Unregister-ScheduledTask -TaskName $TaskName -Confirm:$false -ErrorAction SilentlyContinue
Register-ScheduledTask -TaskName $TaskName -Action $action -Principal $principal -Settings $settings -Force | Out-Null
Start-ScheduledTask -TaskName $TaskName

"started task '$TaskName'"
"  runs : powershell.exe $argString"
"  as   : SYSTEM   limit: $TimeoutMinutes min"
"  poll : Get-ScheduledTaskInfo -TaskName '$TaskName'   (State / LastTaskResult)"

<#
.SYNOPSIS
    Report what the current interactive user can see/run, from inside a process running AS that user.

.DESCRIPTION
    Answers "does this user have tooling the automation account cannot reach?" on a box where the
    two are different accounts. Run it in the target account's context (e.g. from a scheduled task
    registered for that user) and read the report file.

    Everything is derived from the account's own environment - no username is hardcoded anywhere.

    Known failure on workgroup machines: registering that task as a LOCAL user with
    `-LogonType S4U` is refused with "Access is denied" - S4U requires a domain account. Use a
    password logon, or reach the account another way.

    Also reports whether the token is a full admin one: a group listed "deny only" / "Nur zur
    Verweigerung" means a filtered (UAC-limited) token.

.OUTPUTS
    Text report at $env:TEMP\user-context-probe.txt

.EXAMPLE
    powershell -NoProfile -ExecutionPolicy Bypass -File .\probe-user-context.ps1
#>
[CmdletBinding()]
param(
    [string]$OutFile = (Join-Path $env:TEMP 'user-context-probe.txt')
)

$ErrorActionPreference = 'Continue'
function Write-Report([string]$Line) { $Line | Out-File $OutFile -Append -Encoding utf8 }

"=== identity ===" | Out-File $OutFile -Encoding utf8
Write-Report "whoami      : $([System.Security.Principal.WindowsIdentity]::GetCurrent().Name)"
Write-Report "USERPROFILE : $env:USERPROFILE"
Write-Report "LOCALAPPDATA: $env:LOCALAPPDATA"
Write-Report "APPDATA     : $env:APPDATA"
Write-Report "computer    : $env:COMPUTERNAME"

Write-Report ""
Write-Report "=== admin-groups state (deny-only = filtered token) ==="
$groups = whoami /groups | Select-String -Pattern 'Administrators|Administratoren'
if ($groups) { $groups | ForEach-Object { Write-Report ("  " + $_.Line.Trim()) } }
else { Write-Report "  (no Administrators group membership)" }

Write-Report ""
Write-Report "=== uv-managed python / uv / uvx in this account ==="
foreach ($rel in @('.local\bin\python3.11.exe', '.local\bin\uv.exe', '.local\bin\uvx.exe')) {
    $full = Join-Path $env:USERPROFILE $rel
    if (Test-Path $full) {
        Write-Report ("{0} -> {1}" -f $rel, ((& $full --version 2>&1 | Out-String).Trim()))
    } else {
        Write-Report ("{0} -> MISSING" -f $rel)
    }
}

Write-Report ""
Write-Report "=== PATH as seen by this account ==="
Write-Report (($env:PATH -split ';' | Where-Object { $_ } | ForEach-Object { "  $_" }) -join "`n")

Write-Report ""
Write-Report "=== can this account's python import what the proxies need? ==="
$py = Join-Path $env:USERPROFILE '.local\bin\python3.11.exe'
if (Test-Path $py) {
    $code = "import sys, json, urllib.request; print('py', sys.version.split()[0]); print('ok')"
    Write-Report ((& $py -c $code 2>&1 | Out-String).Trim())
} else {
    Write-Report "  (no uv-managed python found)"
}

Write-Report ""
Write-Report "=== llama-server already running? ==="
$procs = Get-Process -Name llama* -ErrorAction SilentlyContinue
if ($procs) { $procs | ForEach-Object { Write-Report "  $($_.Name) pid=$($_.Id)" } }
else { Write-Report "  (none)" }

Write-Report ""
Write-Report "probe complete"
Write-Host "wrote $OutFile"

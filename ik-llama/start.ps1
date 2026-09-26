<#
.SYNOPSIS
    Starts ik_llama llama-server natively on Windows. PowerShell replacement for
    start.sh's probook block (which required WSL2 via /mnt/c and wslpath).

.DESCRIPTION
    Same flags and model table as start.sh <probook>, minus the WSL path mangling.
    Installs stay at the canonical C:\data\llm\ik_llama (start.sh's .tag location).

    Two deliberate improvements over the bash original:
      * the mode table uses NAMED fields, so the "NOSAMPLE in the YF column" bug
        (probook's qwen36u35b silently got sampling flags) cannot recur.
      * -Background uses Start-Process, so the server survives the session that
        started it. A server launched as a child of a PSRP runspace dies with it.

.PARAMETER Mode
    Model shortname. Run with no -Mode to list them.

.PARAMETER Background
    Start detached (survives the calling session), logging to -LogFile.

.EXAMPLE
    .\start.ps1
    .\start.ps1 qwen36u35b
    .\start.ps1 qwen36u35b -Background
#>
[CmdletBinding()]
param(
    [string]$Mode,
    [int]$Port      = 9080,
    [string]$Dir    = 'C:\data\llm\ik_llama',
    [string]$ModelDir = 'C:\data\llm\models',
    [string]$ChatTemplate = 'C:\data\git\ai-tools\ik-llama\qwen3-template.j2',
    [int]$Ctx, [int]$Cram, [int]$Threads = 8, [int]$ThreadsBatch = 8,
    [switch]$Background,
    [string]$LogFile = '',
    [string]$BindAddress = '127.0.0.1',
    [string]$ApiKey = '',
    [switch]$AllowNonLoopback
)

$ErrorActionPreference = 'Stop'
. (Join-Path (Split-Path $PSScriptRoot -Parent) 'llm\lib\common.ps1')
if ($BindAddress -ne '127.0.0.1') {
    if (-not $AllowNonLoopback -or -not $ApiKey) { throw 'non-loopback binding requires -AllowNonLoopback and a non-empty -ApiKey; the previous all-interface dummy-key default exposed the server unnecessarily' }
}

# ── model table (parity with start.sh probook block) ───────────────
# Named fields, no positional columns.
# NOTE: do not name this variable after a [string]-typed parameter — assigning an
# array to a type-constrained parameter silently coerces the array to one string,
# which makes the table empty and the model path garbage.
$ModeTable = @(
    [pscustomobject]@{
        Short  = 'qwen36u35b'
        Name   = 'Qwen3.6 35B-A3B Uncensored'
        File   = 'Qwen3.6-35B-A3B-Uncensored-HauhauCS-Aggressive-IQ4_NL.gguf'
        Ctx    = 32768; Cram = 8192
        Yarn   = $false; Sample = $false   # NOSAMPLE in start.sh
        Mmproj = $null
    }
    [pscustomobject]@{
        Short  = 'qwen3coder30b'
        Name   = 'Qwen3-Coder 30B-A3B Q4_K_M'
        File   = 'Qwen3-Coder-30B-A3B-Instruct-Q4_K_M.gguf'
        Ctx    = 65536; Cram = 16384
        Yarn   = $false; Sample = $true
        Mmproj = $null
    }
)

if (-not $Mode) {
    Write-Host "Usage: start.ps1 <mode> [-Background] [-Port N]"
    Write-Host "Modes:"
    foreach ($m in $ModeTable) {
        Write-Host ("  {0,-16} {1}" -f $m.Short, $m.Name)
    }
    exit 1
}

$sel = $ModeTable | Where-Object { $_.Short -eq $Mode }
if (-not $sel) { throw "Unknown mode: $Mode (run with no arguments to list modes)" }

$server = Join-Path $Dir 'llama-server.exe'
if (-not (Test-Path $server)) { throw "llama-server.exe not found at $server" }
if (-not (Test-Path $ChatTemplate)) { Write-Warning "Chat template not found: $ChatTemplate (--jinja will still be passed)" }

$modelPath = Join-Path $ModelDir $sel.File
if (-not (Test-Path $modelPath)) { throw "Model file not found: $modelPath" }

$running = Get-Process -Name 'llama-server' -ErrorAction SilentlyContinue
if ($running) { throw "llama-server.exe is already running (pid $($running.Id -join ', ')). Stop it first." }

if (-not $Ctx)  { $Ctx  = $sel.Ctx }
if (-not $Cram) { $Cram = $sel.Cram }

# $args is an automatic variable in PowerShell — never assign to it.
$serverArgs = @(
    '-m', $modelPath
    '-ngl', '0'
    '--threads', $Threads
    '--threads-batch', $ThreadsBatch
    '--parallel', 1
    '--ctx-size', $Ctx
    '-sps', 0.5
    '-cram', $Cram
    '-crs', 0.5
    '-ctk', 'q8_0'
    '-ctv', 'q8_0'
    '-dt', 0.1
    '--port', $Port
    '--host', $BindAddress
    '--jinja'
    '--context-shift', 'on'
    '-rea', 'off'
    '-v'
)
if (Test-Path $ChatTemplate) { $serverArgs += @('--chat-template-file', $ChatTemplate) }
if ($sel.Yarn)   { $serverArgs += @('--rope-scaling','yarn','--yarn-orig-ctx','32768','--yarn-beta-fast','32','--yarn-beta-slow','1') }
if ($sel.Sample) { $serverArgs += @('--temp','0.6','--top-p','0.95','--top-k','20') }
if ($sel.Mmproj) { $serverArgs += @('--mmproj', (Join-Path $ModelDir $sel.Mmproj)) }
if ($ApiKey) { $serverArgs += @('--api-key', $ApiKey) }

Write-Host ("Starting {0} on port {1} (ctx={2}, cram={3}MB, threads={4}/{5})..." -f `
    $sel.Name, $Port, $Ctx, $Cram, $Threads, $ThreadsBatch)

if ($Background) {
    if (-not $LogFile) { $LogFile = New-RunLogPath -Name 'ik-llama-server' }
    $p = Start-Process -FilePath $server -ArgumentList $serverArgs -PassThru -WindowStyle Hidden `
                       -RedirectStandardOutput $LogFile -RedirectStandardError "$LogFile.err"
    Write-Host ("Detached: pid {0}, log {1}" -f $p.Id, $LogFile)
} else {
    & $server @serverArgs
}

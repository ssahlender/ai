<#
.SYNOPSIS
    Launches a local llama-server on Windows for either engine.

.DESCRIPTION
    Engine-aware replacement for ik-llama/start.ps1 (kept as history — it only ever
    drove ik_llama and carried ik_llama-only flags). Same spirit, minus the WSL path
    mangling: native Windows, no /mnt/c, no wslpath.

    Engines live in SEPARATE directories because mainline llama.cpp and ik_llama each
    ship their own llama.dll / ggml.dll — mixing them in one folder loads the wrong
    kernels. Models are shared.

    Measured on this machine (2026-09-26; details live in the host-local skill):
      mainline b11201 CPU + gemma4qat   -> pp8 48.1 / pp128 72.7 / tg 17.8-19.4   <- BEST
      ik_llama b5311     + qwen36u35b   -> pp8 19.2 / pp128 60.1 / tg 12.5-15.8
    Engine choice follows the QUANT FAMILY, not taste:
      legacy quants (Q4_0, Q4_K_M ...) -> mainline llama.cpp
      i-quants     (IQ4_NL, IQ4_XS ...) -> ik_llama

    Speculative decoding is MEASURED DEAD on this machine (MTP 12-26% slower at k=2/4,
    n-gram neutral). Do not add --spec-* flags here.

.PARAMETER Mode
    Model shortname. Run with no -Mode (or -ListOnly) to list them.

.PARAMETER Background
    Start detached (survives the calling session) and log to -LogFile.
    A server launched as a child of a PSRP runspace dies when that session closes.

.PARAMETER ListOnly
    Print the mode table with resolved engine/model paths and exit without launching.

.EXAMPLE
    .\start-llm.ps1                    # list modes
    .\start-llm.ps1 gemma4qat -ListOnly
    .\start-llm.ps1 gemma4qat -Background
#>
[CmdletBinding()]
param(
    [string]$Mode,
    [int]$Port        = 9080,
    [string]$ModelDir = 'C:\data\llm\models',
    [string]$MainlineDir = 'C:\data\llm\llama.cpp-cpu',   # CPU build on purpose; the
    [string]$IkLlamaDir  = 'C:\data\llm\ik_llama',        # Vulkan build cannot even
                                                          # run CPU-only here (512 MiB heap)
    [string]$ChatTemplate = 'C:\data\git\ai-tools\ik-llama\qwen3-template.j2',
    [int]$Ctx, [int]$Threads = 8, [int]$ThreadsBatch = 8,
    [switch]$Background,
    [switch]$ListOnly,
    [switch]$DryRun,
    [string]$LogFile = '',
    [string]$BindAddress = '127.0.0.1',
    [string]$ApiKey = '',
    [switch]$AllowNonLoopback
)

$ErrorActionPreference = 'Stop'
. (Join-Path $PSScriptRoot 'lib\common.ps1')
if ($BindAddress -ne '127.0.0.1') {
    if (-not $AllowNonLoopback -or -not $ApiKey) { throw 'non-loopback binding requires -AllowNonLoopback and a non-empty -ApiKey; the previous all-interface dummy-key default exposed the server unnecessarily' }
}

# ── mode table ─────────────────────────────────────────────────────
# Named fields, no positional columns (the bash launcher's machine table had NOSAMPLE sitting
# in the sample-flag column, which silently applied sampling flags to a NOSAMPLE mode).
# NOTE: never name this variable after a [string]-typed parameter — assigning an array
# to a type-constrained parameter silently coerces it to a single string, emptying the
# table and corrupting the model path.
$ModeTable = @(
    [pscustomobject]@{
        Short  = 'gemma4qat'
        Name   = 'Gemma 4 26B-A4B QAT Q4_0  <- BEST measured combo'
        Engine = 'mainline'
        File   = 'gemma-4-26B_q4_0-it.gguf'
        Ctx    = 32768; Cram = 0
        Template = $null; Mmproj = $null
    }
    [pscustomobject]@{
        Short  = 'qwen36u35b'
        Name   = 'Qwen3.6 35B-A3B Uncensored IQ4_NL (i-quant -> ik_llama)'
        Engine = 'ik_llama'
        File   = 'Qwen3.6-35B-A3B-Uncensored-HauhauCS-Aggressive-IQ4_NL.gguf'
        Ctx    = 32768; Cram = 8192
        Template = 'C:\data\git\ai-tools\ik-llama\qwen3-template.j2'; Mmproj = $null
    }
    [pscustomobject]@{
        Short  = 'qwen3coder30b'
        Name   = 'Qwen3-Coder 30B-A3B Q4_K_M (legacy quant -> mainline; NOT downloaded yet)'
        Engine = 'mainline'
        File   = 'Qwen3-Coder-30B-A3B-Instruct-Q4_K_M.gguf'
        Ctx    = 65536; Cram = 0
        Template = $null; Mmproj = $null
    }
    [pscustomobject]@{
        Short  = 'katcoder25'
        Name   = 'Kwaipilot KAT-Coder V2.5 Dev Q3_K_M (verified download)'
        Engine = 'mainline'
        File   = 'Kwaipilot_KAT-Coder-V2.5-Dev-Q3_K_M.gguf'
        Ctx    = 32768; Cram = 0
        Template = $null; Mmproj = $null
    }
    [pscustomobject]@{
        Short  = 'ornith15'
        Name   = 'Ornith 1.5 35B-A3B Q3_K_M (verified download)'
        Engine = 'mainline'
        File   = 'Ornith-1.5-35B-A3B-Q3_K_M.gguf'
        Ctx    = 32768; Cram = 0
        Template = $null; Mmproj = $null
    }
)

$engineDirs = @{ 'mainline' = $MainlineDir; 'ik_llama' = $IkLlamaDir }

function Resolve-EngineServer($engine) {
    $dir = $engineDirs[$engine]
    if (-not $dir) { throw "Unknown engine '$engine' in mode table" }
    $exe = Join-Path $dir 'llama-server.exe'
    if (-not (Test-Path $exe)) { throw "llama-server.exe not found for engine '$engine' at $exe" }
    return $exe
}

if ($ListOnly -or -not $Mode) {
    Write-Host "Usage: start-llm.ps1 <mode> [-Background] [-Port N] [-Ctx N]"
    Write-Host ""
    foreach ($m in $ModeTable) {
        $exe = Join-Path $engineDirs[$m.Engine] 'llama-server.exe'
        $mdl = Join-Path $ModelDir $m.File
        if (Test-Path $exe) { $exeState = 'OK' } else { $exeState = 'MISSING' }
        if (Test-Path $mdl) { $mdlState = 'OK' } else { $mdlState = 'MISSING' }
        Write-Host ("  {0,-15} {1}" -f $m.Short, $m.Name)
        Write-Host ("  {0,-15} engine={1}  ctx={2}" -f '', $m.Engine, $m.Ctx)
        Write-Host ("  {0,-15} server: {1}  [{2}]" -f '', $exe, $exeState)
        Write-Host ("  {0,-15} model : {1}  [{2}]" -f '', $mdl, $mdlState)
    }
    exit 0
}

$sel = $ModeTable | Where-Object { $_.Short -eq $Mode }
if (-not $sel) { throw "Unknown mode: $Mode (run with no arguments to list modes)" }

$server    = Resolve-EngineServer $sel.Engine
$modelPath = Join-Path $ModelDir $sel.File
if (-not (Test-Path $modelPath)) { throw "Mode '$Mode' requires GGUF '$($sel.File)', but it is missing at $modelPath. Download or copy that model before starting." }
if (-not $Ctx) { $Ctx = $sel.Ctx }

$running = Get-Process -Name 'llama-server' -ErrorAction SilentlyContinue
if ($running) { throw "llama-server.exe is already running (pid $($running.Id -join ', ')). Stop it first." }

# $args is an automatic variable in PowerShell — never assign to it.
$serverArgs = @(
    '-m', $modelPath
    '-ngl', '0'
    '--threads', $Threads
    '--threads-batch', $ThreadsBatch
    '--parallel', 1
    '--ctx-size', $Ctx
    '-ctk', 'q8_0'
    '-ctv', 'q8_0'
    '--port', $Port
    '--host', $BindAddress
    '-v'
)

switch ($sel.Engine) {
    'mainline' {
        # mainline llama.cpp: --jinja + built-in template resolution; no ik_llama-only
        # flags (-cram/-crs/-sps/-dt/-rea/--context-shift do not exist here).
        $serverArgs += @('--jinja')
        if ($sel.Template -and (Test-Path $sel.Template)) {
            $serverArgs += @('--chat-template-file', $sel.Template)
        }
    }
    'ik_llama' {
        # ik_llama flags, preserved from the original launcher.
        $serverArgs += @(
            '-sps', '0.5'
            '-cram', $sel.Cram
            '-crs', '0.5'
            '-dt', '0.1'
            '--jinja'
            '--context-shift', 'on'
            '-rea', 'off'
        )
        if (Test-Path $ChatTemplate) { $serverArgs += @('--chat-template-file', $ChatTemplate) }
    }
}
if ($sel.Mmproj) { $serverArgs += @('--mmproj', (Join-Path $ModelDir $sel.Mmproj)) }
if ($ApiKey) { $serverArgs += @('--api-key', $ApiKey) }

if ($DryRun) {
    Write-Host ""
    Write-Host "DRY RUN - would execute:"
    Write-Host ("  {0}" -f $server)
    Write-Host ("    {0}" -f ($serverArgs -join ' '))
    exit 0
}

Write-Host ("Starting {0}" -f $sel.Name)
Write-Host ("  engine : {0}  ({1})" -f $sel.Engine, $server)
Write-Host ("  model  : {0}" -f $modelPath)
Write-Host ("  port={0} ctx={1} threads={2}/{3}" -f $Port, $Ctx, $Threads, $ThreadsBatch)

if ($Background) {
    if (-not $LogFile) { $LogFile = New-RunLogPath -Name 'llama-server' }
    $p = Start-Process -FilePath $server -ArgumentList $serverArgs -PassThru -WindowStyle Hidden `
                       -RedirectStandardOutput $LogFile -RedirectStandardError "$LogFile.err"
    Write-Host ("Detached: pid {0}, log {1}" -f $p.Id, $LogFile)
} else {
    & $server @serverArgs
}

<#
.SYNOPSIS
    Launches a local llama-server on Windows for either engine.

.DESCRIPTION
    Engine-aware replacement for the old ik-llama/start.ps1 (removed 2026-10-28, in git history — it only ever
    drove ik_llama and carried ik_llama-only flags). Same spirit, minus the WSL path
    mangling: native Windows, no /mnt/c, no wslpath.

    Engines live in SEPARATE directories because mainline llama.cpp and ik_llama each
    ship their own llama.dll / ggml.dll — mixing them in one folder loads the wrong
    kernels. Models are shared.

    One model is installed here: bartowski's vanilla Qwen3.6-35B-A3B IQ4_NL with draft-mtp, served by
    mainline (mode qwen36_35b_ml; chosen 2026-10-28, see llm/README.md).
    Measured on this machine (2026-09-26) and kept as history - both entries below are RETIRED
    as of 2026-09-27 (the gemma file was deleted, the ik_llama engine directory removed):
      mainline b11201 CPU + gemma4qat   -> pp8 48.1 / pp128 72.7 / tg 17.8-19.4   <- BEST
      ik_llama b5311     + qwen36u35b   -> pp8 19.2 / pp128 60.1 / tg 12.5-15.8
    Engine choice follows the QUANT FAMILY, not taste:
      legacy quants (Q4_0, Q4_K_M ...) -> mainline llama.cpp
      i-quants     (IQ4_NL, IQ4_XS ...) -> ik_llama   (mainline is the only engine left here)

    Do not add --spec-* flags here. Older builds measured MTP 12-26% slower; on b11588 `draft-mtp` does
    work (see README, "Speculative decoding"), but the only MTP file tested decodes slower than the
    incumbent when plain, so the speculated result does not beat it.

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
    # CPU build on purpose for MainlineDir; the Vulkan build cannot even run CPU-only here (512 MiB heap)
    [string]$ModelDir = (Join-Path $env:USERPROFILE '.local\share\llama.cpp\models'),
    [string]$MainlineDir = (Join-Path $env:USERPROFILE '.local\share\llama.cpp\llama.cpp-cpu'),
    [string]$IkLlamaDir  = (Join-Path $env:USERPROFILE '.local\share\llama.cpp\ik_llama'),
    [string]$ChatTemplate = '',   # default: llm\shared\qwen3-template.j2
    # Never compute this in the param block - $PSScriptRoot is EMPTY there under Windows
    # PowerShell 5.1 and Join-Path then throws on a null Path. Resolved in the body.
    [string]$ModelsJson = '',
    [int]$Ctx, [int]$Threads = 8, [int]$ThreadsBatch = 8,
    [switch]$Background,
    [switch]$ListOnly,
    [switch]$DryRun,
    [string]$LogFile = '',
    [string]$BindAddress = '127.0.0.1',
    [string]$ApiKey = '',
    [switch]$AllowNonLoopback,
    # Appended verbatim to llama-server's arguments. Kept generic on purpose: serving flags that change
    # results (e.g. --no-reasoning-preserve) must be explicit at the call site, not baked into a mode.
    [string[]]$ExtraArgs,
    # Thinking is OFF by default (`--reasoning off`, the mainline equivalent of ik_llama's -rea off),
    # matching the i9's start.sh. Measured: off was 12/12 in 6.0 s vs 5/12 in 32.9 s on here, and on
    # the i9 thinking was 8-9x slower with no quality gain. -Thinking turns it back on for one run.
    # --reasoning-preserve only governs whether reasoning is kept in the HISTORY, not whether it happens.
    [switch]$Thinking,
    # Obsolete: off is now the default. Still accepted so older calls keep working.
    [switch]$NoThinking
)

$ErrorActionPreference = 'Stop'
. (Join-Path $PSScriptRoot 'lib\common.ps1')
if (-not $ChatTemplate) { $ChatTemplate = Get-SharedFile 'qwen3-template.j2' }
if ($BindAddress -ne '127.0.0.1') {
    if (-not $AllowNonLoopback -or -not $ApiKey) { throw 'non-loopback binding requires -AllowNonLoopback and a non-empty -ApiKey; the previous all-interface dummy-key default exposed the server unnecessarily' }
}
$ModelsJson = Resolve-ModelsJsonPath -Explicit $ModelsJson -ScriptDir $PSScriptRoot

# ── mode table ─────────────────────────────────────────────────────
# Read from models.json (shared with the i9 bash scripts, and with
# llama-swap-setup.ps1 here) instead of a literal or
# regex-scraping this file's source text.
$ModeTable = Get-ProbookModeTable -ModelsJson $ModelsJson -ChatTemplate $ChatTemplate

# RETIRED MODES (2026-09-27). Each of these named a GGUF that is no longer on this box, so as a
# live entry it could only ever report [MISSING] and clutter -ListOnly. Kept here as the recipe:
# fetch the file first (llm/MODELS.md records repo, file and SHA-256), then restore the block.
#   gemma4qat      mainline  gemma-4-26B_q4_0-it.gguf                                    (deleted: provenance unverified)
#   qwen36u35b     ik_llama  Qwen3.6-35B-A3B-Uncensored-HauhauCS-Aggressive-IQ4_NL.gguf  (same file, retired engine)
#   qwen36u35b_ml  mainline  Qwen3.6-35B-A3B-Uncensored-HauhauCS-Aggressive-IQ4_NL.gguf  (deleted 2026-10-28: replaced by the vanilla family model)
#   qwen3coder30b  mainline  Qwen3-Coder-30B-A3B-Instruct-Q4_K_M.gguf                    (never downloaded)
#   qwen38distill  mainline  Qwen3.8-35B-A3B-Distill-IQ4_XS.gguf                         (deleted)
#   qwen36u35b_xs  mainline  Qwen3.6-35B-A3B-Uncensored-HauhauCS-Aggressive-IQ4_XS.gguf  (deleted)
#   ornith15       mainline  Ornith-1.5-35B-Q4_K_M.gguf                                  (deleted)
#   agentworld35b  mainline  Qwen-AgentWorld-35B-A3B-UD-IQ4_XS.gguf                      (deleted)
# The ik_llama engine directory went with them; `update-llm.ps1 -Engine ik_llama` restores it.
# The bare block for the one surviving engine+model pair is above; the incumbent's i-quant mode
# used `Ctx = 32768; Cram = 8192` and `Template = <llm\shared\qwen3-template.j2>`.

$engineDirs = @{ 'mainline' = $MainlineDir; 'ik_llama' = $IkLlamaDir }

if ($ListOnly -or -not $Mode) {
    Write-Host "Usage: start-llm.ps1 <mode> [-Background] [-Port N] [-Ctx N] [-Thinking]"
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

$running = Get-Process -Name 'llama-server' -ErrorAction SilentlyContinue
if ($running) { throw "llama-server.exe is already running (pid $($running.Id -join ', ')). Stop it first." }

$inv = Get-ServerInvocation -Mode $sel -Port $Port -ModelDir $ModelDir -EngineDirs $engineDirs `
    -ChatTemplate $ChatTemplate -Threads $Threads -ThreadsBatch $ThreadsBatch -Ctx $Ctx `
    -BindAddress $BindAddress -ApiKey $ApiKey -ExtraArgs $ExtraArgs -Thinking:$Thinking
$server = $inv.Server
$modelPath = $inv.ModelPath
$serverArgs = $inv.Args
if (-not (Test-Path $modelPath)) { throw "Mode '$Mode' requires GGUF '$($sel.File)', but it is missing at $modelPath. Run -ListOnly to see which modes are complete; every GGUF's repo, file and SHA-256 is recorded in llm/MODELS.md." }
if (-not $Ctx) { $Ctx = $sel.Ctx }

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

<#
.SYNOPSIS
    Generate the OpenCode provider config for the local llama-server (native Windows).

.DESCRIPTION
    Windows replacement for ik-llama/setup-agents.sh, which is bash-only. Reads the mode
    table out of ik-llama/models.json (shared with start-llm.ps1 and the i9/Mac bash
    scripts), keeps only the modes whose GGUF actually exists on disk, and merges an
    openai-compatible provider into the OpenCode global config.

    Global config path is ~/.config/opencode/opencode.json on every platform, including
    Windows (only the *managed* config differs: %ProgramData%\opencode).

    Base URL is loopback here, not a LAN address: llama-server runs natively on the same
    machine. (The bash script needed the Windows host IP only because its Claude Code ran
    inside WSL2.)

    Merging, never overwriting: existing config keys are preserved and only the provider
    entry is replaced. The previous file is kept as opencode.json.bak.

.PARAMETER DryRun
    Print the generated JSON and the target path; write nothing.

.PARAMETER Force
    Write even if no model files are found (default is to refuse, like the bash script).

.EXAMPLE
    .\setup-agent-providers.ps1 -DryRun
    .\setup-agent-providers.ps1

.NOTES
    Start a server first (.\start-llm.ps1 <mode> -Background), then pick the model in
    OpenCode as llamacpp/<shortname>.
#>
[CmdletBinding()]
param(
    # NOTE: never compute these in the param block - $PSScriptRoot is EMPTY there under
    # Windows PowerShell 5.1 and Join-Path then throws on a null Path. Resolved in the body.
    [string]$ModelsJson  = '',
    [string]$MainlineDir = '',
    [string]$IkLlamaDir  = '',
    [string]$ModelDir    = (Join-Path $env:USERPROFILE '.local\share\llama.cpp\models'),
    [string]$ConfigPath  = (Join-Path $env:USERPROFILE '.config\opencode\opencode.json'),
    [string]$BaseUrl     = 'http://127.0.0.1:9080/v1',
    [string]$ProviderKey = 'llamacpp',   # named for the engine that actually serves, not ik_llama which was retired 2026-09-27
    [int]$OutputLimit    = 8192,
    [switch]$Force,
    [switch]$DryRun
)

$ErrorActionPreference = 'Stop'

$root = if ($PSScriptRoot) { $PSScriptRoot } else { Split-Path -Parent $MyInvocation.MyCommand.Path }
if (-not $ModelsJson) {
    $ikLlamaDirPath = Join-Path (Split-Path $root -Parent) 'ik-llama'
    $localJson = Join-Path $ikLlamaDirPath 'models.local.json'
    if (Test-Path $localJson) { $ModelsJson = $localJson } else { $ModelsJson = Join-Path $ikLlamaDirPath 'models.json' }
}
# Same defaults start-llm.ps1 uses, so the two scripts cannot disagree about where an engine
# lives without an explicit -MainlineDir/-IkLlamaDir override on both.
if (-not $MainlineDir) { $MainlineDir = Join-Path $env:USERPROFILE '.local\share\llama.cpp\llama.cpp-cpu' }
if (-not $IkLlamaDir)  { $IkLlamaDir  = Join-Path $env:USERPROFILE '.local\share\llama.cpp\ik_llama' }

if (-not (Test-Path $ModelsJson)) { throw "models.json not found: $ModelsJson" }

# ── read the mode table out of models.json (shared with start-llm.ps1 and the i9/Mac
# bash scripts) instead of regex-scraping start-llm.ps1's source text ──
$modelsData = Get-Content $ModelsJson -Raw | ConvertFrom-Json
$engineDirs = @{ 'mainline' = $MainlineDir; 'ik_llama' = $IkLlamaDir }

$modes = @()
foreach ($m in $modelsData.machines.probook) {
    $eng = $m.engine
    if (-not $engineDirs.ContainsKey($eng)) { throw "models.json: probook mode '$($m.short)' has unknown engine '$eng'" }
    $modes += [pscustomobject]@{
        Short = $m.short; File = $m.file; Ctx = [int]$m.ctx; Name = $m.desc; Engine = $eng
        # A mode needs BOTH its GGUF and its engine's llama-server.exe. Checking only the
        # model used to advertise modes whose engine had been removed, which then fail at
        # launch. Same two-state check start-llm.ps1 -ListOnly performs.
        EngineOk = Test-Path (Join-Path $engineDirs[$eng] 'llama-server.exe')
        Exists   = (Test-Path (Join-Path $ModelDir $m.file)) -and (Test-Path (Join-Path $engineDirs[$eng] 'llama-server.exe'))
    }
}

if ($modes.Count -eq 0) { throw "models.json has zero probook modes" }

Write-Host ("modes found in models.json: {0}" -f $modes.Count)
$models = [ordered]@{}
foreach ($m in $modes) {
    if ($m.Exists) {
        $models[$m.Short] = [ordered]@{
            name  = $m.File
            limit = [ordered]@{ context = $m.Ctx; output = $OutputLimit }
        }
        Write-Host ("  + {0,-14} ctx {1,-6} {2}" -f $m.Short, $m.Ctx, $m.File)
    } else {
        Write-Host ("  - {0,-14} SKIPPED (model and/or its engine not present)" -f $m.Short)
    }
}

if ($models.Count -eq 0 -and -not $Force) {
    throw "no model files found in $ModelDir - nothing to configure (use -Force to write anyway)"
}

$provider = [ordered]@{
    npm     = '@ai-sdk/openai-compatible'
    name    = $ProviderKey
    options = [ordered]@{ baseURL = $BaseUrl; apiKey = 'dummy' }
    models  = $models
}

# ── merge into the existing config ─────────────────────────────────
$config = $null
if (Test-Path $ConfigPath) {
    $raw = Get-Content $ConfigPath -Raw
    if ($raw.Trim()) { $config = $raw | ConvertFrom-Json }
}
if (-not $config) { $config = [pscustomobject]@{ '$schema' = 'https://opencode.ai/config.json' } }

if (-not ($config.PSObject.Properties.Name -contains 'provider')) {
    $config | Add-Member -NotePropertyName provider -NotePropertyValue ([pscustomobject]@{}) -Force
}
$config.provider | Add-Member -NotePropertyName $ProviderKey -NotePropertyValue $provider -Force

$json = $config | ConvertTo-Json -Depth 12

if ($DryRun) {
    Write-Host ""
    Write-Host ("DRY RUN - would write {0}" -f $ConfigPath)
    Write-Host "(existing keys preserved; provider '$ProviderKey' replaced)"
    Write-Host ""
    Write-Host $json
    exit 0
}

$dir = Split-Path $ConfigPath -Parent
if (-not (Test-Path $dir)) { New-Item -ItemType Directory -Path $dir -Force | Out-Null }
if (Test-Path $ConfigPath) { Copy-Item $ConfigPath "$ConfigPath.bak" -Force }

$json | Set-Content $ConfigPath -Encoding UTF8
Write-Host ""
Write-Host ("wrote {0}" -f $ConfigPath)
if (Test-Path "$ConfigPath.bak") { Write-Host ("previous kept at {0}.bak" -f $ConfigPath) }
Write-Host "verify with: opencode models"

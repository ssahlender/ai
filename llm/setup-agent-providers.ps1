<#
.SYNOPSIS
    Generate the OpenCode provider config for the local llama-server (native Windows).

.DESCRIPTION
    Windows replacement for ik-llama/setup-agents.sh, which is bash-only. Reads the mode
    table out of start-llm.ps1, keeps only the modes whose GGUF actually exists on disk,
    and merges an openai-compatible provider into the OpenCode global config.

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
    OpenCode as ik-llama/<shortname>.
#>
[CmdletBinding()]
param(
    # NOTE: never compute this in the param block - $PSScriptRoot is EMPTY there under
    # Windows PowerShell 5.1 and Join-Path then throws on a null Path. Resolved in the body.
    [string]$StartScript = '',
    [string]$ModelDir    = 'C:\data\llm\models',
    [string]$ConfigPath  = (Join-Path $env:USERPROFILE '.config\opencode\opencode.json'),
    [string]$BaseUrl     = 'http://127.0.0.1:9080/v1',
    [string]$ProviderKey = 'ik-llama',
    [int]$OutputLimit    = 8192,
    [switch]$Force,
    [switch]$DryRun
)

$ErrorActionPreference = 'Stop'

if (-not $StartScript) {
    $root = if ($PSScriptRoot) { $PSScriptRoot } else { Split-Path -Parent $MyInvocation.MyCommand.Path }
    $StartScript = Join-Path $root 'start-llm.ps1'
}

if (-not (Test-Path $StartScript)) { throw "start-llm.ps1 not found: $StartScript" }

# ── read the mode table out of start-llm.ps1 ───────────────────────
# Each mode is a [pscustomobject]@{ Short=...; File=...; Ctx=... } block; parse those
# fields rather than sourcing the launcher (sourcing it would run its launch logic).
$text  = Get-Content $StartScript -Raw
$table = [regex]::Match($text, '(?s)\$ModeTable\s*=\s*@\((.*?)\n\)')
if (-not $table.Success) { throw "could not locate `$ModeTable in $StartScript" }

$modes = @()
foreach ($block in [regex]::Matches($table.Groups[1].Value, '(?s)\[pscustomobject\]@\{(.*?)\}')) {
    $body = $block.Groups[1].Value
    $short = [regex]::Match($body, "Short\s*=\s*'([^']+)'").Groups[1].Value
    $file  = [regex]::Match($body, "File\s*=\s*'([^']+)'").Groups[1].Value
    $ctx   = [regex]::Match($body, 'Ctx\s*=\s*(\d+)').Groups[1].Value
    $name  = [regex]::Match($body, "Name\s*=\s*'([^']+)'").Groups[1].Value
    if (-not $short -or -not $file -or -not $ctx -or -not $name) {
        throw "mode-table parse failed for a mode block in $StartScript; refusing to generate an incomplete provider config"
    }
    if ($short -and $file) {
        $modes += [pscustomobject]@{
            Short = $short; File = $file; Ctx = [int]$ctx; Name = $name
            Exists = Test-Path (Join-Path $ModelDir $file)
        }
    }
}

if ($modes.Count -eq 0) { throw "mode-table parse found zero usable modes in $StartScript; launcher syntax likely changed" }

Write-Host ("modes found in start-llm.ps1: {0}" -f $modes.Count)
$models = [ordered]@{}
foreach ($m in $modes) {
    if ($m.Exists) {
        $models[$m.Short] = [ordered]@{
            name  = $m.File
            limit = [ordered]@{ context = $m.Ctx; output = $OutputLimit }
        }
        Write-Host ("  + {0,-14} ctx {1,-6} {2}" -f $m.Short, $m.Ctx, $m.File)
    } else {
        Write-Host ("  - {0,-14} SKIPPED (file not present)" -f $m.Short)
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

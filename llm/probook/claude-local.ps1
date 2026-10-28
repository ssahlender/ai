<#
.SYNOPSIS
    Run Claude Code against the local model, natively on Windows.

.DESCRIPTION
    Uses the same chain as every other agent on this machine:
        claude -> local-proxy.py (9081) -> llama-swap (9082, web UI + stats) -> llama-server
    If nothing answers on 9081 it runs llama-swap-setup.ps1 first, then hands off to `claude`.

    Why the proxy: Claude CLI always sends max_tokens=32000. When input+32000 exceeds n_ctx,
    llama-server rejects the request. local-proxy.py caps max_tokens (default 16384), so
    ~87.5% of the context stays available for input, and sends keep-alives during long prefills.

    Why `--bare`: bypasses claude.ai OAuth so ANTHROPIC_API_KEY takes over.

    Also required (this is the 90%-slowdown trap): CLAUDE_CODE_ATTRIBUTION_HEADER=0 in
    ~/.claude/settings.json. Use -FixSettings once to write it, or paste:
        { "env": { "CLAUDE_CODE_ATTRIBUTION_HEADER": "0" } }

.PARAMETER Model
    The llama-swap model id, i.e. the mode's short name in models.json (default qwen36_35b_ml).

.PARAMETER NoStart
    Fail instead of starting the chain.

.PARAMETER FixSettings
    Add the attribution-header env var to ~/.claude/settings.json if missing.

.PARAMETER DryRun
    Print every step and the final command; start nothing.

.EXAMPLE
    .\claude-local.ps1 -DryRun
    .\claude-local.ps1 -FixSettings
    .\claude-local.ps1
#>
[CmdletBinding()]
param(
    [string]$Model        = 'qwen36_35b_ml',
    [int]$ProxyPort       = 9081,
    [switch]$NoStart,
    [switch]$FixSettings,
    [switch]$DryRun
)

$ErrorActionPreference = 'Stop'
$here = $PSScriptRoot
. (Join-Path $here 'lib\common.ps1')

Write-Host ("claude-local: model={0} agent port={1}" -f $Model, $ProxyPort)

# ── 1) the chain: local-proxy 9081 -> llama-swap 9082 -> llama-server ──
if (Test-EndpointReady -Url "http://127.0.0.1:$ProxyPort/health") {
    Write-Host ("  chain  : already serving on {0}" -f $ProxyPort)
} elseif ($NoStart) {
    throw "nothing listening on $ProxyPort and -NoStart was given"
} else {
    Write-Host "  chain  : starting it via llama-swap-setup.ps1"
    if (-not $DryRun) {
        & powershell -NoProfile -ExecutionPolicy Bypass -File (Join-Path $here 'llama-swap-setup.ps1')
        if (-not (Test-EndpointReady -Url "http://127.0.0.1:$ProxyPort/health")) { throw "the chain did not come up on $ProxyPort" }
    }
}
Write-Host "  note   : the first request loads the model (~1-1.5 min); llama-swap's UI shows it: http://127.0.0.1:9082/ui"

# ── 2) attribution header (the 90% trap) ───────────────────────────
$settingsPath = Join-Path $env:USERPROFILE '.claude\settings.json'
$needFix = $true
if (Test-Path $settingsPath) {
    $raw = Get-Content $settingsPath -Raw
    if ($raw -match 'CLAUDE_CODE_ATTRIBUTION_HEADER') { $needFix = $false }
}
if ($needFix) {
    Write-Warning "CLAUDE_CODE_ATTRIBUTION_HEADER is NOT set in $settingsPath - local servers run ~90% slower without it"
    if ($FixSettings) {
        if (-not $DryRun) {
            $dir = Split-Path $settingsPath -Parent
            if (-not (Test-Path $dir)) { New-Item -ItemType Directory -Path $dir -Force | Out-Null }
            if (Test-Path $settingsPath) {
                Copy-Item $settingsPath "$settingsPath.bak" -Force
                $json = Get-Content $settingsPath -Raw | ConvertFrom-Json
            } else {
                $json = [pscustomobject]@{}
            }
            if (-not ($json.PSObject.Properties.Name -contains 'env')) {
                $json | Add-Member -NotePropertyName env -NotePropertyValue ([pscustomobject]@{}) -Force
            }
            $json.env | Add-Member -NotePropertyName CLAUDE_CODE_ATTRIBUTION_HEADER -NotePropertyValue '0' -Force
            $newJson = $json | ConvertTo-Json -Depth 8
            $tempSettings = "$settingsPath.new"
            Write-Utf8NoBom -Path $tempSettings -Lines @($newJson)
            try { Get-Content $tempSettings -Raw | ConvertFrom-Json -ErrorAction Stop | Out-Null }
            catch { Remove-Item $tempSettings -Force -ErrorAction SilentlyContinue; throw "refusing to write invalid settings JSON: $($_.Exception.Message)" }
            Move-Item $tempSettings $settingsPath -Force
            Write-Host ("  settings: written {0} (backup at {0}.bak)" -f $settingsPath)
        } else {
            Write-Host ("  settings: would patch {0}" -f $settingsPath)
        }
    } else {
        Write-Host "  settings: re-run with -FixSettings to patch it automatically"
    }
} else {
    Write-Host "  settings: attribution header already disabled"
}

# ── 3) hand off to claude ──────────────────────────────────────────
$env:ANTHROPIC_BASE_URL = "http://localhost:$ProxyPort"
$env:ANTHROPIC_API_KEY = 'dummy'
$env:ANTHROPIC_CUSTOM_MODEL_OPTION = $Model
$env:ANTHROPIC_DEFAULT_SONNET_MODEL = $Model
$env:ANTHROPIC_DEFAULT_HAIKU_MODEL  = $Model

$claudeCmd = Get-Command claude -ErrorAction SilentlyContinue | Select-Object -First 1
if (-not $claudeCmd) { throw "claude not found in PATH" }

Write-Host ("  launch : claude --bare --model {0}   (base_url http://localhost:{1})" -f $Model, $ProxyPort)
if ($DryRun) {
    Write-Host ""
    Write-Host "DRY RUN - would execute:"
    Write-Host ("  {0} --bare --model {1}" -f $claudeCmd.Source, $Model)
    exit 0
}

& $claudeCmd.Source --bare --model $Model

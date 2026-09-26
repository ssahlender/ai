<#
.SYNOPSIS
    Run Claude Code against the local llama-server, natively on Windows.

.DESCRIPTION
    Windows replacement for claude-providers.sh's "local" path (bash + WSL-only).
    Brings up the two pieces Claude Code needs and hands off to `claude`.

    Why a proxy: Claude CLI always sends max_tokens=32000. When input+32000 exceeds
    n_ctx, llama-server rejects the request ("exceeds the available context size").
    local-proxy.py caps max_tokens (default 16384) and forwards to llama-server, so
    ~87.5% of context stays available for input. local-proxy.py is pure-stdlib Python
    — no port needed, it runs natively here.

    Why `--bare`: bypasses claude.ai OAuth so ANTHROPIC_API_KEY takes over.

    Also required (this is the 90%-slowdown trap): CLAUDE_CODE_ATTRIBUTION_HEADER=0 in
    ~/.claude/settings.json. Use -FixSettings once to write it, or paste:
        { "env": { "CLAUDE_CODE_ATTRIBUTION_HEADER": "0" } }

    Model naming: Claude Code must be given the GGUF filename stem, e.g.
    gemma-4-26B_q4_0-it. -ModelStem overrides it.

.PARAMETER Mode
    Mode for start-llm.ps1 (default gemma4qat) — used when the server is not up yet.

.PARAMETER NoStart
    Fail instead of starting llama-server / the proxy.

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
    [string]$Mode         = 'gemma4qat',
    [string]$ModelStem    = 'gemma-4-26B_q4_0-it',
    [int]$ServerPort      = 9080,
    [int]$ProxyPort       = 9081,
    [string]$ProxyScript  = '',
    [switch]$NoStart,
    [switch]$FixSettings,
    [switch]$DryRun
)

$ErrorActionPreference = 'Stop'
$here = $PSScriptRoot
. (Join-Path $here 'lib\common.ps1')

function Resolve-Python {
    $candidates = @(
        (Join-Path $env:USERPROFILE '.local\bin\python3.11.exe'),
        (Join-Path $env:USERPROFILE '.local\bin\python.exe')
    )
    foreach ($c in $candidates) { if (Test-Path $c) { return $c } }
    $cmd = Get-Command python -ErrorAction SilentlyContinue |
           Where-Object { $_.Source -notlike '*WindowsApps*' } | Select-Object -First 1
    if ($cmd) { return $cmd.Source }
    throw "no real Python found (the Microsoft Store alias does not count); install uv or Python"
}

Write-Host ("claude-local: mode={0} stem={1} server={2} proxy={3}" -f $Mode, $ModelStem, $ServerPort, $ProxyPort)

# ── 1) llama-server on 9080 ────────────────────────────────────────
if (Test-ServerHealth -Port $ServerPort) {
    Write-Host ("  server : healthy model already serving on {0}" -f $ServerPort)
} elseif (Test-PortOpen -Port $ServerPort) {
    throw "port $ServerPort is listening, but /health is not ok. Refusing to wire Claude Code to an unloaded or different server."
} elseif ($NoStart) {
    throw "nothing listening on $ServerPort and -NoStart was given"
} else {
    $starter = Join-Path $here 'start-llm.ps1'
    if (-not (Test-Path $starter)) { throw "start-llm.ps1 not found next to this script ($starter)" }
    Write-Host ("  server : starting '{0}' via start-llm.ps1 -Background" -f $Mode)
    if (-not $DryRun) {
        & powershell -NoProfile -ExecutionPolicy Bypass -File $starter $Mode -Background -Port $ServerPort
        $health = Wait-ServerHealth -Port $ServerPort -TimeoutSec 180 -IntervalSec 3
        if (-not $health.Ok) { throw "llama-server did not become healthy on $ServerPort after $($health.Waited)s ($($health.LastErr))" }
        Write-Host ("  server : healthy after ~{0}s" -f $health.Waited)
    }
}

# ── 2) local-proxy.py on 9081 ──────────────────────────────────────
if (Test-EndpointReady -Url "http://127.0.0.1:$ProxyPort/health") {
    Write-Host ("  proxy  : HTTP endpoint already serving on {0}" -f $ProxyPort)
} elseif ($NoStart) {
    throw "nothing listening on $ProxyPort and -NoStart was given"
} else {
    # local-proxy.py travels with the repo; the clone location differs per machine,
    # so probe the known layouts rather than guessing one.
    $proxyCandidates = @(
        (Join-Path $env:USERPROFILE 'git\ai-tools\ik-llama\local-proxy.py'),
        'C:\data\git\ai-tools\ik-llama\local-proxy.py',
        (Join-Path $here 'local-proxy.py'),
        (Join-Path $here '..\ik-llama\local-proxy.py')
    )
    if (-not $ProxyScript) {
        $ProxyScript = $proxyCandidates | Where-Object { Test-Path $_ } | Select-Object -First 1
    }
    if (-not $ProxyScript) {
        throw ("local-proxy.py not found. Looked in:`n  " + ($proxyCandidates -join "`n  "))
    }
    if (-not (Test-Path $ProxyScript)) { throw "proxy script not found: $ProxyScript" }
    $py = Resolve-Python
    Write-Host ("  proxy  : starting {0} with {1}" -f (Split-Path $ProxyScript -Leaf), $py)
    if (-not $DryRun) {
        $env:LOCAL_PROXY_PORT = "$ProxyPort"
        $env:LOCAL_PROXY_UPSTREAM = "http://127.0.0.1:$ServerPort"
        $log = Join-Path $env:TEMP 'local-proxy.log'
        Start-Process -FilePath $py -ArgumentList @($ProxyScript) -WindowStyle Hidden `
                      -RedirectStandardOutput $log -RedirectStandardError "$log.err"
        $waited = 0
        while (-not (Test-EndpointReady -Url "http://127.0.0.1:$ProxyPort/health") -and $waited -lt 30) { Start-Sleep -Seconds 1; $waited += 1 }
        if (-not (Test-EndpointReady -Url "http://127.0.0.1:$ProxyPort/health")) { throw "local-proxy did not expose an HTTP endpoint on $ProxyPort (see $log.err)" }
        Write-Host ("  proxy  : up, log {0}" -f $log)
    }
}

# ── 3) attribution header (the 90% trap) ───────────────────────────
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
            $json | ConvertTo-Json -Depth 8 | Set-Content $settingsPath -Encoding UTF8
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

# ── 4) hand off to claude ──────────────────────────────────────────
$env:ANTHROPIC_BASE_URL = "http://localhost:$ProxyPort"
$env:ANTHROPIC_API_KEY = 'dummy'
$env:ANTHROPIC_CUSTOM_MODEL_OPTION = $ModelStem
$env:ANTHROPIC_DEFAULT_SONNET_MODEL = $ModelStem
$env:ANTHROPIC_DEFAULT_HAIKU_MODEL  = $ModelStem

$claudeCmd = Get-Command claude -ErrorAction SilentlyContinue | Select-Object -First 1
if (-not $claudeCmd) { throw "claude not found in PATH" }

Write-Host ("  launch : claude --bare --model {0}   (base_url http://localhost:{1})" -f $ModelStem, $ProxyPort)
if ($DryRun) {
    Write-Host ""
    Write-Host "DRY RUN - would execute:"
    Write-Host ("  {0} --bare --model {1}" -f $claudeCmd.Source, $ModelStem)
    exit 0
}

& $claudeCmd.Source --bare --model $ModelStem

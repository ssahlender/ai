<#
.SYNOPSIS
    Download a model file resumably and report progress to a .status file.

.DESCRIPTION
    A multi-GB download over PSRP dies with the session (WSManFault 1359), so this is meant to be
    launched through run-as-system-task.ps1. curl is invoked with -C - so a rerun resumes instead
    of restarting - check "$OutFile.status" after any interruption, then simply run it again.

    -sS is deliberate: curl's progress bar goes to stderr, and a filled WSMan message is one of the
    ways this class of job dies. Only errors are shown.

.PARAMETER Url
    Direct download URL (e.g. a Hugging Face /resolve/main/ path).

.PARAMETER OutFile
    Full destination path. Its parent directory is created if missing.

.PARAMETER ExpectedBytes
    Optional exact size to verify after the download; a mismatch fails loudly rather than leaving a
    truncated file that looks complete.

.EXAMPLE
    .\download-model.ps1 -Url https://example/model.gguf -OutFile C:\models\model.gguf -ExpectedBytes 16230000000
#>
[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)][string]$Url,
    [Parameter(Mandatory = $true)][string]$OutFile,
    [long]$ExpectedBytes = 0
)

$ErrorActionPreference = 'Continue'
$status = "$OutFile.status"

$dir = Split-Path -Parent $OutFile
if ($dir -and -not (Test-Path $dir)) { New-Item -ItemType Directory -Path $dir -Force | Out-Null }

$have = 0
if (Test-Path $OutFile) { $have = (Get-Item $OutFile).Length }
"url: $Url"        | Set-Content $status -Encoding UTF8
"have: $have bytes (0 means fresh start)" | Add-Content $status -Encoding UTF8

# -C - resumes; -sS keeps progress bars away from the caller, errors still shown
& curl.exe -L -C - --retry 5 --retry-delay 5 -sS -o $OutFile $Url
$code = $LASTEXITCODE

$size = 0
if (Test-Path $OutFile) { $size = (Get-Item $OutFile).Length }

if ($code -ne 0) {
    "FAILED: curl exit $code, $size bytes on disk (rerun to resume)" | Set-Content $status -Encoding UTF8
    "FAILED: curl exit $code, $size bytes"
    exit 1
}
if ($ExpectedBytes -gt 0 -and $size -ne $ExpectedBytes) {
    "FAILED: size mismatch - expected $ExpectedBytes, got $size" | Set-Content $status -Encoding UTF8
    "FAILED: size mismatch - expected $ExpectedBytes, got $size"
    exit 1
}

"complete ($size bytes)" | Set-Content $status -Encoding UTF8
"=== downloaded $OutFile ($([Math]::Round($size / 1GB, 2)) GB) ==="

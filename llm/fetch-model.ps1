<#
.SYNOPSIS
    Resumable GGUF fetch with exact-size verification.

.DESCRIPTION
    Downloads one model file into the shared models directory, resuming a partial download, verifying
    the byte count, and only then renaming it into place.

    Why not Invoke-WebRequest: on PowerShell 5.1 it buffers the whole response in memory, which fails on
    multi-GB files. Why verify: a truncated .gguf is indistinguishable from a good one until llama.cpp
    tries to load it, and a resumed download that silently restarted produces exactly that file.

.EXAMPLE
    powershell -ExecutionPolicy Bypass -File fetch-model.ps1 `
        -Url "https://huggingface.co/<repo>/resolve/main/<file>.gguf" `
        -FileName "<file>.gguf" -ExpectedBytes 18728777856
#>
param(
    [Parameter(Mandatory = $true)][string]$Url,
    [Parameter(Mandatory = $true)][string]$FileName,
    [Parameter(Mandatory = $true)][long]$ExpectedBytes,
    [string]$ModelsDir = 'C:\data\llm\models'
)
$ErrorActionPreference = 'Stop'

$dest = Join-Path $ModelsDir $FileName
$part = "$dest.part"

if (Test-Path -LiteralPath $dest) {
    $have = (Get-Item -LiteralPath $dest).Length
    if ($have -eq $ExpectedBytes) { Write-Output "already complete: $FileName ($have bytes)"; exit 0 }
    Write-Output "existing file is $have of $ExpectedBytes bytes - downloading again into .part"
}

# --fail turns an HTTP error into a non-zero exit instead of saving an error page as a model.
# -C - resumes from the current .part size; the retries survive a flaky link without losing it.
$curlArgs = @(
    '--location', '--fail', '--retry', '8', '--retry-delay', '5', '--retry-all-errors',
    '--continue-at', '-', '--output', $part, $Url
)
$started = Get-Date
& curl.exe @curlArgs
if ($LASTEXITCODE -ne 0) { throw "curl exited $LASTEXITCODE - partial kept at $part for resume" }

$got = (Get-Item -LiteralPath $part).Length
if ($got -ne $ExpectedBytes) {
    throw "size mismatch: got $got, expected $ExpectedBytes - partial kept at $part for resume"
}
if (Test-Path -LiteralPath $dest) { Remove-Item -LiteralPath $dest -Force }
Move-Item -LiteralPath $part -Destination $dest
$mins = [Math]::Round(((Get-Date) - $started).TotalMinutes, 1)
Write-Output ("downloaded {0} ({1} bytes) in {2} min -> {3}" -f $FileName, $got, $mins, $dest)

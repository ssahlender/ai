# Publish a quality-run JSON without exposing its host-local provenance path.
[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)][string]$Source,
    [string]$Destination = (Join-Path (Split-Path $PSScriptRoot -Parent) 'evidence')
)

$ErrorActionPreference = 'Stop'
if (-not (Test-Path $Source -PathType Leaf)) { throw "evidence file not found: $Source" }
if (-not (Test-Path $Destination)) { New-Item -ItemType Directory -Path $Destination -Force | Out-Null }
$name = Split-Path $Source -Leaf
if ($name -notmatch '^quality-[A-Za-z0-9._-]+-\d{8}-\d{6}\.json$') { throw 'source must be a timestamped quality-run JSON' }
$out = Join-Path $Destination $name
if (Test-Path $out) { throw "refusing to overwrite published evidence: $out" }

$doc = Get-Content $Source -Raw | ConvertFrom-Json
function Remove-HostPaths {
    param($Value)
    if ($Value -is [string]) {
        # This is deliberately applied to every value, not selected field names: parse errors and
        # model answers can contain an absolute path too.
        return ($Value -replace '(?i)(?:[a-z]:[\\/]|\\\\\\\\|/home/)[^\s\"''`r`n,;\]\}\)]+', '[host-local path omitted]')
    }
    if ($null -eq $Value) { return $null }
    if ($Value -is [System.Collections.IDictionary]) {
        foreach ($key in @($Value.Keys)) { $Value[$key] = Remove-HostPaths $Value[$key] }
        return $Value
    }
    if ($Value -is [System.Collections.IList]) {
        for ($i = 0; $i -lt $Value.Count; $i++) { $Value[$i] = Remove-HostPaths $Value[$i] }
        return $Value
    }
    foreach ($property in @($Value.PSObject.Properties)) {
        if ($property.IsSettable) { $property.Value = Remove-HostPaths $property.Value }
    }
    return $Value
}
$doc = Remove-HostPaths $doc
$doc | Add-Member -NotePropertyName publishedSource -NotePropertyValue 'Original run is host-local; its path is intentionally omitted.' -Force
[IO.File]::WriteAllText($out, ($doc | ConvertTo-Json -Depth 14), (New-Object System.Text.UTF8Encoding($false)))
Write-Output "published: $out"

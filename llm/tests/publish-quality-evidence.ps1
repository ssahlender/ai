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
if ($doc.PSObject.Properties.Name -contains 'fixtureDir') {
    $doc.fixtureDir = 'Host-local fixture path omitted from published evidence.'
}
$doc | Add-Member -NotePropertyName publishedSource -NotePropertyValue 'Original run is host-local; its path is intentionally omitted.' -Force
[IO.File]::WriteAllText($out, ($doc | ConvertTo-Json -Depth 14), (New-Object System.Text.UTF8Encoding($false)))
Write-Output "published: $out"

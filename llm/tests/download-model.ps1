# Thin wrapper. The implementation lives in ../fetch-model.ps1 - one copy, so a fix cannot land
# in one and be missed in the other. Kept at this path because scripts and docs referred to it.
#
# Downloads one GGUF resumably, verifying the byte count, and only then renaming it into place.
# A multi-GB download over PSRP dies with the session (WSManFault 1359), so launch it through
# run-as-system-task.ps1; curl's -C - means a rerun resumes instead of restarting.
param(
    [Parameter(Mandatory = $true)][string]$Url,
    [Parameter(Mandatory = $true)][string]$OutFile,
    [long]$ExpectedBytes = 0
)
& (Join-Path (Split-Path $PSScriptRoot -Parent) 'fetch-model.ps1') @PSBoundParameters

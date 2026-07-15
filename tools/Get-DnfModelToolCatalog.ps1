[CmdletBinding()]
param(
    [switch]$AsJson
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
$OutputEncoding = [Console]::OutputEncoding = New-Object System.Text.UTF8Encoding($false)

Import-Module (Join-Path $PSScriptRoot 'DnfPatch.ModelTools.psm1') -Force

$result = Get-DnfModelToolCatalog
if ($AsJson) {
    $result | ConvertTo-Json -Depth 20
}
else {
    $result
}

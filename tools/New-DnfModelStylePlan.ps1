[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)]
    [string]$RequestPath,

    [string]$OutputPath,

    [string]$RepoRoot,

    [switch]$AsJson
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
$OutputEncoding = [Console]::OutputEncoding = New-Object System.Text.UTF8Encoding($false)

Import-Module (Join-Path $PSScriptRoot 'DnfPatch.ModelTools.psm1') -Force

$arguments = @{
    RequestPath = $RequestPath
}
if (-not [string]::IsNullOrWhiteSpace($OutputPath)) {
    $arguments['OutputPath'] = $OutputPath
}
if (-not [string]::IsNullOrWhiteSpace($RepoRoot)) {
    $arguments['RepositoryRoot'] = $RepoRoot
}

$result = New-DnfModelStylePlan @arguments
if ($AsJson) {
    $result | ConvertTo-Json -Depth 20
}
else {
    $result
}

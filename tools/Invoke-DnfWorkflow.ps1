[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)]
    [string]$WorkflowPath,

    [string]$RegistryPath,

    [string]$RepoRoot,

    [string]$RunId,

    [switch]$Execute,

    [switch]$Resume,

    [switch]$AllowNetwork,

    [switch]$AsJson
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
$OutputEncoding = [Console]::OutputEncoding = New-Object System.Text.UTF8Encoding($false)

Import-Module (Join-Path $PSScriptRoot 'workflow\DnfPatch.Workflow.psm1') -Force
$result = Invoke-DnfWorkflow -WorkflowPath $WorkflowPath -RegistryPath $RegistryPath `
    -RepositoryRoot $RepoRoot -RunId $RunId -Execute:$Execute -Resume:$Resume `
    -AllowNetwork:$AllowNetwork
if ($AsJson) {
    $result | ConvertTo-Json -Depth 20
}
else {
    $result
}

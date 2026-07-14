[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)]
    [string[]]$WorkflowPath,

    [string]$RegistryPath,

    [string]$RepoRoot,

    [switch]$AsJson
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
$OutputEncoding = [Console]::OutputEncoding = New-Object System.Text.UTF8Encoding($false)

Import-Module (Join-Path $PSScriptRoot 'workflow\DnfPatch.Workflow.psm1') -Force
$results = New-Object 'Collections.Generic.List[object]'
foreach ($path in $WorkflowPath) {
    $results.Add((Test-DnfWorkflowDefinition -WorkflowPath $path `
        -RegistryPath $RegistryPath -RepositoryRoot $RepoRoot))
}
$resultArray = $results.ToArray()
$failed = @($resultArray | Where-Object { [string]$_.status -ne 'passed' })
$result = [pscustomobject]@{
    schemaVersion = 1
    status = if ($failed.Count -eq 0) { 'passed' } else { 'failed' }
    workflowCount = $resultArray.Count
    failedCount = $failed.Count
    workflows = $resultArray
    deployment = [pscustomobject]@{
        authorized = $false
        performed = $false
        imagePacks2Write = $false
        processOperation = $false
    }
}
if ($AsJson) {
    $result | ConvertTo-Json -Depth 20
}
else {
    $result
}
if ($failed.Count -gt 0) {
    exit 1
}

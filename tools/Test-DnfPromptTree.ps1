[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)]
    [string]$ProfessionPath,

    [string]$ThemePath,

    [string]$SourcePath,

    [string]$ExpectedSourceSha256,

    [AllowEmptyCollection()]
    [string[]]$ExpectedPromptFileName = @(),

    [AllowEmptyCollection()]
    [string[]]$AllowedChangedRelativePath = @(),

    [AllowEmptyCollection()]
    [object[]]$BaselineChange = @(),

    [string]$RepoRoot
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
$OutputEncoding = [Console]::OutputEncoding = New-Object System.Text.UTF8Encoding($false)

$projectRoot = Split-Path -Parent $PSScriptRoot
$validator = Join-Path $projectRoot '.codex\skills\dnf-import-profession-text\scripts\Test-DnfPromptTree.ps1'
if (-not (Test-Path -LiteralPath $validator -PathType Leaf)) {
    throw "Prompt-tree validator was not found: $validator"
}

$arguments = @{
    ProfessionPath = $ProfessionPath
}
foreach ($name in @(
    'ThemePath',
    'SourcePath',
    'ExpectedSourceSha256',
    'ExpectedPromptFileName',
    'AllowedChangedRelativePath',
    'BaselineChange',
    'RepoRoot')) {
    if ($PSBoundParameters.ContainsKey($name)) {
        $arguments[$name] = $PSBoundParameters[$name]
    }
}

& $validator @arguments

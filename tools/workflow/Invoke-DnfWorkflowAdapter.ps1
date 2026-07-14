[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)]
    [string]$ScriptPath,

    [Parameter(Mandatory = $true)]
    [string]$ParameterJsonPath
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
$OutputEncoding = [Console]::OutputEncoding = New-Object System.Text.UTF8Encoding($false)

$repositoryRoot = (Resolve-Path -LiteralPath (Split-Path -Parent (Split-Path -Parent $PSScriptRoot))).Path
$repositoryPrefix = $repositoryRoot.TrimEnd(
    [IO.Path]::DirectorySeparatorChar,
    [IO.Path]::AltDirectorySeparatorChar) + [IO.Path]::DirectorySeparatorChar
$resolvedScript = (Resolve-Path -LiteralPath $ScriptPath).Path
$resolvedParameters = (Resolve-Path -LiteralPath $ParameterJsonPath).Path
foreach ($record in @(
    [pscustomobject]@{ path = $resolvedScript; label = 'Adapter script' },
    [pscustomobject]@{ path = $resolvedParameters; label = 'Adapter parameter file' })) {
    if (-not $record.path.StartsWith($repositoryPrefix, [StringComparison]::OrdinalIgnoreCase)) {
        throw "$($record.label) must stay inside the repository: $($record.path)"
    }
    $candidate = [IO.Path]::GetFullPath($record.path)
    while ($true) {
        if (Test-Path -LiteralPath $candidate) {
            $item = Get-Item -LiteralPath $candidate -Force
            if (($item.Attributes -band [IO.FileAttributes]::ReparsePoint) -ne 0) {
                throw "$($record.label) cannot traverse a reparse point: $($item.FullName)"
            }
        }
        if ($candidate.Equals($repositoryRoot, [StringComparison]::OrdinalIgnoreCase)) {
            break
        }
        $parent = Split-Path -Parent $candidate
        if ([string]::IsNullOrWhiteSpace($parent) -or $parent -eq $candidate) {
            throw "$($record.label) path ancestry could not be resolved: $($record.path)"
        }
        $candidate = $parent
    }
}
if ([IO.Path]::GetExtension($resolvedScript) -ine '.ps1') {
    throw "Adapter script must use the .ps1 extension: $resolvedScript"
}

$parameterObject = Get-Content -LiteralPath $resolvedParameters -Raw -Encoding UTF8 | ConvertFrom-Json
$parameters = @{}
foreach ($property in @($parameterObject.PSObject.Properties)) {
    $parameters[$property.Name] = $property.Value
}
& $resolvedScript @parameters

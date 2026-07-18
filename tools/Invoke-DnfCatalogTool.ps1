[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)]
    [string]$HostRequestPath
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
$OutputEncoding = [Console]::OutputEncoding = New-Object System.Text.UTF8Encoding($false)

function Resolve-FullPath {
    param([Parameter(Mandatory = $true)][string]$Path)

    return [IO.Path]::GetFullPath($Path)
}

function Assert-InsideRoot {
    param(
        [Parameter(Mandatory = $true)][string]$Path,
        [Parameter(Mandatory = $true)][string]$Root,
        [Parameter(Mandatory = $true)][string]$Label
    )

    $fullPath = Resolve-FullPath -Path $Path
    $fullRoot = (Resolve-FullPath -Path $Root).TrimEnd([IO.Path]::DirectorySeparatorChar, [IO.Path]::AltDirectorySeparatorChar)
    $prefix = $fullRoot + [IO.Path]::DirectorySeparatorChar
    if (-not ($fullPath.Equals($fullRoot, [StringComparison]::OrdinalIgnoreCase) -or
            $fullPath.StartsWith($prefix, [StringComparison]::OrdinalIgnoreCase))) {
        throw "$Label must stay inside the repository: $fullPath"
    }
}

function Assert-NoReparsePointInChain {
    param(
        [Parameter(Mandatory = $true)][string]$Path,
        [Parameter(Mandatory = $true)][string]$Root
    )

    $fullRoot = (Resolve-FullPath -Path $Root).TrimEnd([IO.Path]::DirectorySeparatorChar, [IO.Path]::AltDirectorySeparatorChar)
    $current = Get-Item -LiteralPath $Path -Force
    while ($null -ne $current) {
        if (($current.Attributes -band [IO.FileAttributes]::ReparsePoint) -ne 0) {
            throw "Catalog tool path cannot traverse a reparse point: $($current.FullName)"
        }
        if ($current.FullName.Equals($fullRoot, [StringComparison]::OrdinalIgnoreCase)) {
            return
        }
        $current = if ($current -is [IO.DirectoryInfo]) { $current.Parent } else { $current.Directory }
    }
    throw "Catalog tool path did not resolve to the repository root: $Path"
}

$requestPath = Resolve-FullPath -Path $HostRequestPath
if (-not (Test-Path -LiteralPath $requestPath -PathType Leaf)) {
    throw "Catalog host request was not found: $requestPath"
}
$request = Get-Content -LiteralPath $requestPath -Raw -Encoding UTF8 | ConvertFrom-Json
if ($request.schemaVersion -ne 1 -or [string]::IsNullOrWhiteSpace([string]$request.repositoryRoot) -or
    [string]::IsNullOrWhiteSpace([string]$request.scriptPath) -or
    [string]::IsNullOrWhiteSpace([string]$request.scriptSha256) -or
    [string]::IsNullOrWhiteSpace([string]$request.hostScriptSha256)) {
    throw 'Catalog host request identity is invalid.'
}

$actualHostHash = (Get-FileHash -LiteralPath $PSCommandPath -Algorithm SHA256).Hash
if ($actualHostHash -ne ([string]$request.hostScriptSha256).ToUpperInvariant()) {
    throw "Catalog host SHA-256 changed: actual=$actualHostHash expected=$($request.hostScriptSha256)"
}

$repositoryRoot = Resolve-FullPath -Path ([string]$request.repositoryRoot)
$scriptPath = Resolve-FullPath -Path ([string]$request.scriptPath)
Assert-InsideRoot -Path $requestPath -Root $repositoryRoot -Label 'Catalog host request'
Assert-InsideRoot -Path $scriptPath -Root $repositoryRoot -Label 'Catalog script'
if (-not (Test-Path -LiteralPath $scriptPath -PathType Leaf) -or
    -not $scriptPath.EndsWith('.ps1', [StringComparison]::OrdinalIgnoreCase)) {
    throw "Catalog script is not a PowerShell file: $scriptPath"
}
Assert-NoReparsePointInChain -Path $requestPath -Root $repositoryRoot
Assert-NoReparsePointInChain -Path $scriptPath -Root $repositoryRoot
$actualScriptHash = (Get-FileHash -LiteralPath $scriptPath -Algorithm SHA256).Hash
if ($actualScriptHash -ne ([string]$request.scriptSha256).ToUpperInvariant()) {
    throw "Catalog script SHA-256 changed: actual=$actualScriptHash expected=$($request.scriptSha256)"
}

$arguments = @{}
if ($null -ne $request.arguments) {
    foreach ($property in $request.arguments.PSObject.Properties) {
        $arguments[$property.Name] = $property.Value
    }
}

$global:LASTEXITCODE = 0
& $scriptPath @arguments
$scriptExitCode = $global:LASTEXITCODE
if ($scriptExitCode -ne 0) {
    exit $scriptExitCode
}

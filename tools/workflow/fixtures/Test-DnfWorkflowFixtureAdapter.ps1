[CmdletBinding()]
param(
    [string]$InputPath,
    [string]$OutputPath,
    [string]$Status = 'passed',
    [bool]$Ready = $true,

    [bool]$AllowExistingOutput = $false,

    [bool]$ReadyAfterExistingOutput = $false,

    [switch]$AsJson
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
$OutputEncoding = [Console]::OutputEncoding = New-Object System.Text.UTF8Encoding($false)

if (-not [string]::IsNullOrWhiteSpace($InputPath) -and
    -not (Test-Path -LiteralPath $InputPath -PathType Leaf)) {
    throw "Fixture input was not found: $InputPath"
}
$outputExisted = -not [string]::IsNullOrWhiteSpace($OutputPath) -and
    (Test-Path -LiteralPath $OutputPath -PathType Leaf)
if (-not [string]::IsNullOrWhiteSpace($OutputPath)) {
    if ($outputExisted -and -not $AllowExistingOutput) {
        throw "Fixture refuses to overwrite output: $OutputPath"
    }
    if (-not $outputExisted) {
        $directory = Split-Path -Parent $OutputPath
        New-Item -ItemType Directory -Path $directory -Force | Out-Null
        [IO.File]::WriteAllText($OutputPath, 'fixture-output',
            (New-Object Text.UTF8Encoding($false)))
    }
}
$effectiveReady = if ($ReadyAfterExistingOutput) { $outputExisted } else { $Ready }
$result = [pscustomobject]@{
    schemaVersion = 1
    status = $Status
    ready = $effectiveReady
    outputPath = $OutputPath
    deployment = [pscustomobject]@{
        authorized = $false
        performed = $false
        imagePacks2Write = $false
        processOperation = $false
    }
}
if ($AsJson) {
    $result | ConvertTo-Json -Depth 5
}
else {
    $result
}

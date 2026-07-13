[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)]
    [string]$SourceDirectory,

    [switch]$AllowUnsignedPersonalBuild
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$modulePath = Join-Path $PSScriptRoot 'DnfPatch.Toolchain.psm1'
Import-Module $modulePath -Force
$repoRoot = Get-DnfPatchRepositoryRoot
$sourcePath = (Resolve-Path -LiteralPath $SourceDirectory).Path
$sourceExecutable = Join-Path $sourcePath 'Aseprite.exe'
if (-not (Test-Path -LiteralPath $sourceExecutable -PathType Leaf)) {
    throw "Aseprite.exe was not found in the supplied directory: $sourcePath"
}

$targetRoot = Join-Path $repoRoot 'tools\bin\aseprite'
if ($sourcePath.StartsWith($targetRoot, [StringComparison]::OrdinalIgnoreCase)) {
    throw 'The Aseprite source directory must be outside the project-local import slot.'
}

$signature = Get-AuthenticodeSignature -LiteralPath $sourceExecutable
if (-not $AllowUnsignedPersonalBuild -and
    $signature.Status -ne [System.Management.Automation.SignatureStatus]::Valid) {
    throw "Aseprite signature is not valid. Use -AllowUnsignedPersonalBuild only for a personally compiled source build: $($signature.Status)"
}

$versionOutput = & $sourceExecutable --version 2>&1 | Out-String
if ($LASTEXITCODE -ne 0 -or [string]::IsNullOrWhiteSpace($versionOutput)) {
    throw "Aseprite --version failed: $versionOutput"
}
$version = $versionOutput.Trim()
$sourceCapability = Test-DnfAsepriteApiCapability -Executable $sourceExecutable -RepositoryRoot $repoRoot
$sourceHash = (Get-FileHash -LiteralPath $sourceExecutable -Algorithm SHA256).Hash
$safeVersion = [regex]::Replace($version, '[^A-Za-z0-9._-]+', '-')
$slotName = $safeVersion + '-' + $sourceHash.Substring(0, 12).ToLowerInvariant()
$slotPath = Join-Path $targetRoot $slotName
$slotExecutable = Join-Path $slotPath 'Aseprite.exe'

New-Item -ItemType Directory -Path $targetRoot -Force | Out-Null
if (Test-Path -LiteralPath $slotPath) {
    if (-not (Test-Path -LiteralPath $slotExecutable -PathType Leaf) -or
        (Get-FileHash -LiteralPath $slotExecutable -Algorithm SHA256).Hash -ne $sourceHash) {
        throw "An incompatible Aseprite slot already exists: $slotPath"
    }
}
else {
    $stagingPath = Join-Path $targetRoot ('.staging-' + [Guid]::NewGuid().ToString('N'))
    New-Item -ItemType Directory -Path $stagingPath | Out-Null
    try {
        foreach ($item in @(Get-ChildItem -LiteralPath $sourcePath -Force)) {
            Copy-Item -LiteralPath $item.FullName -Destination $stagingPath -Recurse
        }
        $stagingExecutable = Join-Path $stagingPath 'Aseprite.exe'
        if ((Get-FileHash -LiteralPath $stagingExecutable -Algorithm SHA256).Hash -ne $sourceHash) {
            throw 'Imported Aseprite executable differs from the supplied executable.'
        }
        $importedVersion = (& $stagingExecutable --version 2>&1 | Out-String).Trim()
        if ($LASTEXITCODE -ne 0 -or $importedVersion -ne $version) {
            throw "Imported Aseprite version check failed: '$importedVersion'/'$version'"
        }
        Move-Item -LiteralPath $stagingPath -Destination $slotPath
    }
    finally {
        if (Test-Path -LiteralPath $stagingPath) {
            Remove-Item -LiteralPath $stagingPath -Recurse -Force
        }
    }
}

$importedCapability = Test-DnfAsepriteApiCapability -Executable $slotExecutable -RepositoryRoot $repoRoot
$slotSignature = Get-AuthenticodeSignature -LiteralPath $slotExecutable
$provenance = [ordered]@{
    schemaVersion = 1
    importedAt = (Get-Date).ToString('o')
    application = 'Aseprite'
    version = $version
    sourceDirectory = $sourcePath
    sourceExecutable = $sourceExecutable
    importedExecutable = $slotExecutable
    length = [long](Get-Item -LiteralPath $slotExecutable).Length
    sha256 = $sourceHash
    authenticode = [ordered]@{
        status = $slotSignature.Status.ToString()
        signer = if ($null -ne $slotSignature.SignerCertificate) { $slotSignature.SignerCertificate.Subject } else { $null }
    }
    apiCapability = [ordered]@{
        source = $sourceCapability
        imported = $importedCapability
    }
    redistribution = 'project-local ignored copy only; do not commit or distribute to third parties'
}
$provenancePath = Join-Path $slotPath 'provenance.json'
$provenance | ConvertTo-Json -Depth 6 | Set-Content -LiteralPath $provenancePath -Encoding UTF8

$relativeExecutable = $slotExecutable.Substring($targetRoot.Length).TrimStart('\').Replace('\', '/')
$current = [ordered]@{
    schemaVersion = 1
    application = 'Aseprite'
    version = $version
    relativeExecutable = $relativeExecutable
    length = [long](Get-Item -LiteralPath $slotExecutable).Length
    sha256 = $sourceHash
    apiVersion = [int]$importedCapability.apiVersion
    minimumApiVersion = [int]$importedCapability.minimumApiVersion
    provenance = ($provenancePath.Substring($targetRoot.Length).TrimStart('\').Replace('\', '/'))
}
$currentPath = Join-Path $targetRoot 'current.json'
$temporaryCurrent = $currentPath + '.tmp-' + [Guid]::NewGuid().ToString('N')
try {
    $current | ConvertTo-Json -Depth 4 | Set-Content -LiteralPath $temporaryCurrent -Encoding UTF8
    Move-Item -LiteralPath $temporaryCurrent -Destination $currentPath -Force
}
finally {
    if (Test-Path -LiteralPath $temporaryCurrent) {
        Remove-Item -LiteralPath $temporaryCurrent -Force
    }
}

[pscustomobject]@{
    status = 'passed'
    executable = $slotExecutable
    version = $version
    apiVersion = [int]$importedCapability.apiVersion
    sha256 = $sourceHash
    currentManifest = $currentPath
    committed = $false
}
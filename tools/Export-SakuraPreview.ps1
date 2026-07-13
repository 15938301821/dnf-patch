[CmdletBinding()]
param(
    [ValidatePattern('^[A-Za-z0-9][A-Za-z0-9._-]*$')]
    [string]$RunId = 'sakura-preview-aseprite-v1',

    [string]$SourceFile,

    [string]$OutputFile,

    [string]$ProvenanceFile,

    [string]$AsepritePath
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

Import-Module (Join-Path $PSScriptRoot 'DnfPatch.Toolchain.psm1') -Force
$repoRoot = Get-DnfPatchRepositoryRoot
$themeRoot = Join-Path $repoRoot '气功师（女）\樱花主题'
$scriptPath = Join-Path $PSScriptRoot 'Export-SakuraPreview.lua'
if ([string]::IsNullOrWhiteSpace($SourceFile)) {
    $SourceFile = Join-Path $themeRoot 'frames\preview\全技能联系表.png'
}
if ([string]::IsNullOrWhiteSpace($OutputFile)) {
    $OutputFile = Join-Path $themeRoot (Join-Path 'frames\preview' (Join-Path $RunId '樱花粉预览.png'))
}
if ([string]::IsNullOrWhiteSpace($ProvenanceFile)) {
    $ProvenanceFile = Join-Path $themeRoot (Join-Path 'validation' (Join-Path $RunId 'preview-export.json'))
}

$aseprite = Resolve-DnfAsepriteExecutable -Path $AsepritePath -RepositoryRoot $repoRoot
$asepriteCapability = Test-DnfAsepriteApiCapability -Executable $aseprite -RepositoryRoot $repoRoot
$sourcePath = (Resolve-Path -LiteralPath $SourceFile).Path
$outputPath = [IO.Path]::GetFullPath($OutputFile)
$provenancePath = [IO.Path]::GetFullPath($ProvenanceFile)
$themePath = (Resolve-Path -LiteralPath $themeRoot).Path

foreach ($pathRecord in @(
    [pscustomobject]@{ path = $scriptPath; type = 'Leaf'; label = 'Aseprite Lua script' },
    [pscustomobject]@{ path = $sourcePath; type = 'Leaf'; label = 'source preview' }
)) {
    if (-not (Test-Path -LiteralPath $pathRecord.path -PathType $pathRecord.type)) {
        throw "$($pathRecord.label) was not found: $($pathRecord.path)"
    }
}
foreach ($candidate in @($outputPath, $provenancePath)) {
    if (-not $candidate.StartsWith($themePath + [IO.Path]::DirectorySeparatorChar, [StringComparison]::OrdinalIgnoreCase)) {
        throw "Output must remain inside the Sakura theme workspace: $candidate"
    }
    if (Test-Path -LiteralPath $candidate) {
        throw "Refusing to overwrite existing output: $candidate"
    }
}

$sourceBefore = Get-DnfFileSnapshot -Path $sourcePath
$asepriteSnapshot = Get-DnfFileSnapshot -Path $aseprite
$scriptSnapshot = Get-DnfFileSnapshot -Path $scriptPath
$asepriteVersion = (& $aseprite --version 2>&1 | Out-String).Trim()
if ($LASTEXITCODE -ne 0 -or [string]::IsNullOrWhiteSpace($asepriteVersion)) {
    throw "Aseprite --version failed: $asepriteVersion"
}

$outputDirectory = Split-Path -Parent $outputPath
$provenanceDirectory = Split-Path -Parent $provenancePath
New-Item -ItemType Directory -Path $outputDirectory -Force | Out-Null
New-Item -ItemType Directory -Path $provenanceDirectory -Force | Out-Null
$stagingDirectory = Join-Path $provenanceDirectory ('.preview-staging-' + [Guid]::NewGuid().ToString('N'))
$stagingOutput = Join-Path $stagingDirectory ([IO.Path]::GetFileName($outputPath))
New-Item -ItemType Directory -Path $stagingDirectory | Out-Null

try {
    $arguments = @(
        '--batch',
        '--script-param', ('source=' + $sourcePath),
        '--script-param', ('output=' + $stagingOutput),
        '--script', $scriptPath
    )
    $renderOutput = & $aseprite $arguments 2>&1 | Out-String
    if ($LASTEXITCODE -ne 0) {
        throw "Aseprite preview export failed: $renderOutput"
    }
    if ($renderOutput -notmatch 'SakuraPreviewExport=passed') {
        throw "Aseprite preview export did not emit its success marker: $renderOutput"
    }
    if (-not (Test-Path -LiteralPath $stagingOutput -PathType Leaf)) {
        throw "Aseprite did not create the staged preview: $stagingOutput"
    }

    Add-Type -AssemblyName System.Drawing
    $sourceImage = $null
    $outputImage = $null
    try {
        $sourceImage = [Drawing.Image]::FromFile($sourcePath)
        $outputImage = [Drawing.Image]::FromFile($stagingOutput)
        if ($sourceImage.Width -ne $outputImage.Width -or
            $sourceImage.Height -ne $outputImage.Height) {
            throw "Preview geometry changed: source=$($sourceImage.Width)x$($sourceImage.Height) output=$($outputImage.Width)x$($outputImage.Height)"
        }
        $width = [int]$outputImage.Width
        $height = [int]$outputImage.Height
    }
    finally {
        if ($null -ne $sourceImage) { $sourceImage.Dispose() }
        if ($null -ne $outputImage) { $outputImage.Dispose() }
    }

    $sourceAfter = Get-DnfFileSnapshot -Path $sourcePath
    if ($sourceAfter.length -ne $sourceBefore.length -or
        $sourceAfter.sha256 -ne $sourceBefore.sha256 -or
        $sourceAfter.lastWriteTime -ne $sourceBefore.lastWriteTime) {
        throw 'Source preview changed during Aseprite export.'
    }

    $stagedSnapshot = Get-DnfFileSnapshot -Path $stagingOutput
    Move-Item -LiteralPath $stagingOutput -Destination $outputPath
    $outputSnapshot = Get-DnfFileSnapshot -Path $outputPath
    if ($outputSnapshot.length -ne $stagedSnapshot.length -or
        $outputSnapshot.sha256 -ne $stagedSnapshot.sha256) {
        throw 'Published preview differs from the staged Aseprite output.'
    }

    $provenance = [ordered]@{
        schemaVersion = 1
        generatedAt = (Get-Date).ToString('o')
        status = 'passed'
        runId = $RunId
        mode = 'Aseprite batch PNG export; no NPK build or deployment'
        editor = [ordered]@{
            application = 'Aseprite'
            version = $asepriteVersion
            executable = $asepriteSnapshot
            apiCapability = $asepriteCapability
            script = $scriptSnapshot
        }
        source = $sourceBefore
        output = [ordered]@{
            path = $outputSnapshot.path
            length = $outputSnapshot.length
            sha256 = $outputSnapshot.sha256
            width = $width
            height = $height
            colorMode = 'RGBA PNG'
        }
        invariants = [ordered]@{
            sourceUnchanged = $true
            geometryPreserved = $true
            nonEmptyOutput = $outputSnapshot.length -gt 0
            overwriteRefused = $true
        }
        deployment = 'not-authorized-not-performed'
    }
    $temporaryProvenance = $provenancePath + '.tmp-' + [Guid]::NewGuid().ToString('N')
    try {
        $provenance | ConvertTo-Json -Depth 8 | Set-Content -LiteralPath $temporaryProvenance -Encoding UTF8
        $null = Get-Content -LiteralPath $temporaryProvenance -Raw -Encoding UTF8 | ConvertFrom-Json
        Move-Item -LiteralPath $temporaryProvenance -Destination $provenancePath
    }
    finally {
        if (Test-Path -LiteralPath $temporaryProvenance) {
            Remove-Item -LiteralPath $temporaryProvenance -Force
        }
    }

    [pscustomobject]@{
        status = 'passed'
        runId = $RunId
        output = $outputPath
        outputSha256 = $outputSnapshot.sha256
        width = $width
        height = $height
        provenance = $provenancePath
        deployment = 'not-authorized-not-performed'
    }
}
catch {
    if (Test-Path -LiteralPath $outputPath -PathType Leaf) {
        Remove-Item -LiteralPath $outputPath -Force
    }
    throw
}
finally {
    if (Test-Path -LiteralPath $stagingDirectory) {
        Remove-Item -LiteralPath $stagingDirectory -Recurse -Force
    }
}
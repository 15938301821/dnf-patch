[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)]
    [string]$ConfigFile,

    [Parameter(Mandatory = $true)]
    [ValidatePattern('^[A-Za-z0-9][A-Za-z0-9._-]*$')]
    [string]$RunId,

    [string]$ImagePacks2,

    [string]$ExtractorDirectory,

    [string]$OutputDirectory
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
$OutputEncoding = [Console]::OutputEncoding = New-Object System.Text.UTF8Encoding($false)

if ([IntPtr]::Size -ne 4) {
    throw 'Run this exporter with 32-bit PowerShell because ExtractorSharp uses x86 zlib.'
}

function Get-HashText {
    param([Parameter(Mandatory = $true)][byte[]]$Bytes)

    $sha = [Security.Cryptography.SHA256]::Create()
    try {
        return [BitConverter]::ToString($sha.ComputeHash($Bytes)).Replace('-', '')
    }
    finally {
        $sha.Dispose()
    }
}

function Get-FileHashText {
    param([Parameter(Mandatory = $true)][string]$Path)

    return (Get-FileHash -LiteralPath $Path -Algorithm SHA256).Hash
}

function ConvertTo-SafeSlug {
    param([Parameter(Mandatory = $true)][string]$Value)

    $slug = $Value.Trim().ToLowerInvariant() -replace '[^a-z0-9._-]+', '_'
    $slug = $slug.Trim('_')
    if ([string]::IsNullOrWhiteSpace($slug)) {
        throw "Could not create a safe slug for '$Value'."
    }
    return $slug
}

function Normalize-ImgPath {
    param([Parameter(Mandatory = $true)][string]$Value)

    $normalized = $Value.Trim().Replace('\\', '/')
    while ($normalized.StartsWith('/')) {
        $normalized = $normalized.Substring(1)
    }
    if ([string]::IsNullOrWhiteSpace($normalized) -or -not $normalized.EndsWith('.img', [StringComparison]::OrdinalIgnoreCase)) {
        throw "Invalid IMG path: $Value"
    }
    return $normalized
}

function Get-DdsInfo {
    param(
        [Parameter(Mandatory = $true)][byte[]]$Dds,
        [Parameter(Mandatory = $true)][int]$ExpectedWidth,
        [Parameter(Mandatory = $true)][int]$ExpectedHeight,
        [Parameter(Mandatory = $true)][string]$ExpectedFourCc
    )

    if ($Dds.Length -lt 136) {
        throw 'DDS payload is too short.'
    }
    $magic = [Text.Encoding]::ASCII.GetString($Dds, 0, 4)
    $height = [BitConverter]::ToInt32($Dds, 12)
    $width = [BitConverter]::ToInt32($Dds, 16)
    $mipLevels = [BitConverter]::ToInt32($Dds, 28)
    $fourCc = [Text.Encoding]::ASCII.GetString($Dds, 84, 4)
    if ($magic -ne 'DDS ') {
        throw 'DDS magic is invalid.'
    }
    if ($width -ne $ExpectedWidth -or $height -ne $ExpectedHeight) {
        throw "DDS dimensions changed: ${width}x${height}/expected ${ExpectedWidth}x${ExpectedHeight}."
    }
    if ($fourCc -ne $ExpectedFourCc) {
        throw "DDS FourCC changed: $fourCc/$ExpectedFourCc."
    }
    if ($mipLevels -ne 0 -and $mipLevels -ne 1) {
        throw "DDS mipLevels is invalid: $mipLevels"
    }
    $blockBytes = if ($fourCc -eq 'DXT1') { 8 } elseif ($fourCc -eq 'DXT5') { 16 } else { 0 }
    if ($blockBytes -eq 0) {
        throw "Unsupported DDS FourCC: $fourCc"
    }
    $blockCount = [int]([Math]::Ceiling($width / 4.0) * [Math]::Ceiling($height / 4.0))
    $expectedLength = 128 + $blockCount * $blockBytes
    if ($Dds.Length -ne $expectedLength) {
        throw "DDS block length is invalid: $($Dds.Length)/$expectedLength."
    }
    return [pscustomobject]@{
        magic      = $magic
        fourCc     = $fourCc
        width      = $width
        height     = $height
        mipLevels  = $mipLevels
        blockBytes = $blockBytes
        blockCount = $blockCount
        length     = $Dds.Length
        sha256     = Get-HashText -Bytes $Dds
    }
}

function Get-ImageStats {
    param(
        [Parameter(Mandatory = $true)][byte[]]$Pixels
    )

    $alphaPixels = 0L
    $opaquePixels = 0L
    $partialAlphaPixels = 0L
    $nonBlackVisiblePixels = 0L
    for ($index = 0; $index -lt $Pixels.Length; $index += 4) {
        $alpha = [int]$Pixels[$index + 3]
        if ($alpha -eq 0) {
            continue
        }
        $alphaPixels++
        if ($alpha -eq 255) { $opaquePixels++ } else { $partialAlphaPixels++ }
        if ($Pixels[$index] -ne 0 -or $Pixels[$index + 1] -ne 0 -or $Pixels[$index + 2] -ne 0) {
            $nonBlackVisiblePixels++
        }
    }
    return [pscustomobject]@{
        alphaPixels           = $alphaPixels
        opaquePixels          = $opaquePixels
        partialAlphaPixels    = $partialAlphaPixels
        nonBlackVisiblePixels = $nonBlackVisiblePixels
        fullyTransparent      = $alphaPixels -eq 0
        allVisiblePixelsBlack = $alphaPixels -gt 0 -and $nonBlackVisiblePixels -eq 0
    }
}

$themeRoot = Split-Path -Parent $PSScriptRoot
$professionRoot = Split-Path -Parent $themeRoot
$jobsRoot = Split-Path -Parent $professionRoot
$repoRoot = Split-Path -Parent $jobsRoot
Import-Module (Join-Path $repoRoot 'tools\DnfPatch.Toolchain.psm1') -Force

$configPath = (Resolve-Path -LiteralPath $ConfigFile).Path
$config = Get-Content -LiteralPath $configPath -Raw -Encoding UTF8 | ConvertFrom-Json
if ($config.schemaVersion -ne 1) {
    throw "Unsupported config schemaVersion: $($config.schemaVersion)"
}
if ($config.themeId -ne 'weaponmaster-vergil-dark-blue') {
    throw 'Config themeId must be weaponmaster-vergil-dark-blue.'
}
if ($null -eq $config.sourceNpk -or [string]::IsNullOrWhiteSpace([string]$config.sourceNpk.path)) {
    throw 'Config sourceNpk.path is required.'
}
if (@($config.allowedImgPaths).Count -eq 0) {
    throw 'Config allowedImgPaths must not be empty.'
}
if ($null -eq $config.PSObject.Properties['excludedFrameKeys']) {
    throw 'Config excludedFrameKeys must be present.'
}

$sourceNpk = Resolve-DnfSourceNpk -ConfiguredPath ([string]$config.sourceNpk.path) `
    -ImagePacks2 $ImagePacks2 -RepositoryRoot $repoRoot
$ExtractorDirectory = Resolve-DnfExtractorDirectory -Path $ExtractorDirectory -RepositoryRoot $repoRoot
$coreDll = Join-Path $ExtractorDirectory 'ExtractorSharp.Core.dll'
$jsonDll = Join-Path $ExtractorDirectory 'ExtractorSharp.Json.dll'

$sourceItem = Get-Item -LiteralPath $sourceNpk
$sourceHash = Get-FileHashText -Path $sourceNpk
$expectedHash = ([string]$config.sourceNpk.sha256).ToUpperInvariant()
if ($sourceHash -ne $expectedHash) {
    throw "Source SHA-256 changed: actual=$sourceHash expected=$expectedHash"
}
if ([long]$config.sourceNpk.length -gt 0 -and $sourceItem.Length -ne [long]$config.sourceNpk.length) {
    throw "Source length changed: actual=$($sourceItem.Length) expected=$($config.sourceNpk.length)"
}

if ([string]::IsNullOrWhiteSpace($OutputDirectory)) {
    $OutputDirectory = Join-Path $themeRoot (Join-Path 'frames\source' (Join-Path $RunId 'illusionslash'))
}
$outputPath = [IO.Path]::GetFullPath($OutputDirectory)
$themePath = (Resolve-Path -LiteralPath $themeRoot).Path
if (-not $outputPath.StartsWith($themePath + [IO.Path]::DirectorySeparatorChar, [StringComparison]::OrdinalIgnoreCase)) {
    throw "Source output must stay inside the current theme workspace: $outputPath"
}
if (Test-Path -LiteralPath $outputPath) {
    throw "Refusing to overwrite existing source output: $outputPath"
}

$allowedPaths = New-Object 'Collections.Generic.HashSet[string]' ([StringComparer]::OrdinalIgnoreCase)
foreach ($path in @($config.allowedImgPaths)) {
    [void]$allowedPaths.Add((Normalize-ImgPath -Value ([string]$path)))
}
$excludedFrames = New-Object 'Collections.Generic.HashSet[string]' ([StringComparer]::OrdinalIgnoreCase)
foreach ($frameKey in @($config.excludedFrameKeys)) {
    $text = [string]$frameKey
    $separator = $text.LastIndexOf('#')
    if ($separator -lt 1) { throw "Invalid excluded frame key: $text" }
    $path = Normalize-ImgPath -Value $text.Substring(0, $separator)
    if (-not $allowedPaths.Contains($path)) { throw "Excluded frame is outside allowed paths: $text" }
    [void]$excludedFrames.Add(($path + $text.Substring($separator)))
}
$matchedAllowed = New-Object 'Collections.Generic.HashSet[string]' ([StringComparer]::OrdinalIgnoreCase)
$matchedExcluded = New-Object 'Collections.Generic.HashSet[string]' ([StringComparer]::OrdinalIgnoreCase)

New-Item -ItemType Directory -Path $outputPath | Out-Null
$records = New-Object 'Collections.Generic.List[object]'
$albumsOut = New-Object 'Collections.Generic.List[object]'

$previousLocation = Get-Location
try {
    Set-Location -LiteralPath $ExtractorDirectory
    [void][Reflection.Assembly]::LoadFrom($jsonDll)
    [void][Reflection.Assembly]::LoadFrom($coreDll)
    [void][Reflection.Assembly]::LoadWithPartialName('System.Drawing')

    $albums = [ExtractorSharp.Core.Coder.NpkCoder]::Load($sourceNpk)
    foreach ($album in $albums) {
        $imgPath = Normalize-ImgPath -Value ([string]$album.Path)
        if (-not $allowedPaths.Contains($imgPath)) {
            continue
        }
        [void]$matchedAllowed.Add($imgPath)
        if ($album.Version.ToString() -ne 'Ver5') {
            throw "Allowed IMG is not Ver5: $imgPath"
        }
        $mapField = $album.Handler.GetType().GetField('_map', [Reflection.BindingFlags]'Instance,NonPublic')
        if ($null -eq $mapField) {
            throw "Ver5 texture map is unavailable: $imgPath"
        }
        $textureMap = $mapField.GetValue($album.Handler)
        if ($null -eq $textureMap) {
            throw "Ver5 texture map is empty: $imgPath"
        }

        $albumSlug = ConvertTo-SafeSlug -Value ($imgPath -replace '^sprite/character/swordman/effect/illusionslash/', '')
        $albumDir = Join-Path $outputPath $albumSlug
        New-Item -ItemType Directory -Path $albumDir | Out-Null
        $albumsOut.Add([ordered]@{
                imgPath    = $imgPath
                albumSlug  = $albumSlug
                imgVersion = $album.Version.ToString()
                frameCount = [int]$album.List.Count
            })

        foreach ($sprite in $album.List) {
            $frameKey = $imgPath + '#' + [int]$sprite.Index
            $excluded = $excludedFrames.Contains($frameKey)
            if ($excluded) { [void]$matchedExcluded.Add($frameKey) }
            if ($sprite.Type.ToString() -eq 'LINK') {
                throw "Unexpected LINK frame in allowed illusionslash scope: $frameKey"
            }
            if (-not $textureMap.ContainsKey($sprite.Index)) {
                throw "Missing texture map for frame: $frameKey"
            }
            $textureInfo = $textureMap[$sprite.Index]
            $texture = $textureInfo.Texture
            if ($null -eq $texture) {
                throw "Missing texture object for frame: $frameKey"
            }
            if ($sprite.CompressMode.ToString() -ne 'DDS_ZLIB') {
                throw "Unexpected compression at ${frameKey}: $($sprite.CompressMode)"
            }
            $textureType = $texture.Type.ToString()
            if ($textureType -ne $sprite.Type.ToString()) {
                throw "Sprite and texture type mismatch at ${frameKey}: $($sprite.Type)/$textureType"
            }
            $expectedFourCc = if ($textureType -eq 'DXT_1') { 'DXT1' } elseif ($textureType -eq 'DXT_5') { 'DXT5' } else { $null }
            if ($null -eq $expectedFourCc) {
                throw "Unsupported texture type at ${frameKey}: $textureType"
            }

            $picture = $null
            $textureBitmap = $null
            $graphics = $null
            try {
                $picture = $sprite.Picture
                if ($null -eq $picture) {
                    throw "ExtractorSharp could not decode frame: $frameKey"
                }
                if ($picture.Width -ne $sprite.Width -or $picture.Height -ne $sprite.Height) {
                    throw "Decoded frame geometry mismatch at $frameKey"
                }
                $pixels = [ExtractorSharp.Core.Lib.Bitmaps]::ToArray($picture)
                $stats = Get-ImageStats -Pixels $pixels

                $textureBitmap = New-Object Drawing.Bitmap ([int]$texture.Width), ([int]$texture.Height), ([Drawing.Imaging.PixelFormat]::Format32bppArgb)
                $graphics = [Drawing.Graphics]::FromImage($textureBitmap)
                $graphics.CompositingMode = [Drawing.Drawing2D.CompositingMode]::SourceCopy
                $graphics.Clear([Drawing.Color]::Transparent)
                $graphics.DrawImageUnscaled($picture, 0, 0)

                $pngName = 'frame-{0:D3}.png' -f [int]$sprite.Index
                $relativePng = ($albumSlug + '/' + $pngName)
                $pngPath = Join-Path $albumDir $pngName
                if (Test-Path -LiteralPath $pngPath) {
                    throw "Refusing to overwrite source PNG: $pngPath"
                }
                $textureBitmap.Save($pngPath, [Drawing.Imaging.ImageFormat]::Png)
                $pngItem = Get-Item -LiteralPath $pngPath

                $dds = [ExtractorSharp.Core.Lib.Zlib]::Decompress($texture.Data, $texture.FullLength)
                $ddsInfo = Get-DdsInfo -Dds $dds -ExpectedWidth ([int]$texture.Width) `
                    -ExpectedHeight ([int]$texture.Height) -ExpectedFourCc $expectedFourCc

                $records.Add([ordered]@{
                        frameKey              = $frameKey
                        imgPath               = $imgPath
                        albumSlug             = $albumSlug
                        frameIndex            = [int]$sprite.Index
                        sourcePng             = $pngPath
                        relativePng           = $relativePng
                        sourcePngBytes        = [long]$pngItem.Length
                        sourcePngSha256       = Get-FileHashText -Path $pngPath
                        runtimeRequired       = -not $excluded
                        excluded              = $excluded
                        width                 = [int]$sprite.Width
                        height                = [int]$sprite.Height
                        canvasWidth           = [int]$sprite.CanvasWidth
                        canvasHeight          = [int]$sprite.CanvasHeight
                        x                     = [int]$sprite.X
                        y                     = [int]$sprite.Y
                        hidden                = [bool]$sprite.Hidden
                        type                  = $sprite.Type.ToString()
                        compressMode          = $sprite.CompressMode.ToString()
                        textureType           = $textureType
                        textureVersion        = $texture.Version.ToString()
                        textureIndex          = [int]$texture.Index
                        textureWidth          = [int]$texture.Width
                        textureHeight         = [int]$texture.Height
                        atlasLeft             = [int]$textureInfo.LeftUp.X
                        atlasTop              = [int]$textureInfo.LeftUp.Y
                        atlasRight            = [int]$textureInfo.RightDown.X
                        atlasBottom           = [int]$textureInfo.RightDown.Y
                        rotation              = [int]$textureInfo.Top
                        unknown               = [int]$textureInfo.Unknown
                        dds                   = $ddsInfo
                        alphaPixels           = [long]$stats.alphaPixels
                        opaquePixels          = [long]$stats.opaquePixels
                        partialAlphaPixels    = [long]$stats.partialAlphaPixels
                        nonBlackVisiblePixels = [long]$stats.nonBlackVisiblePixels
                        fullyTransparent      = [bool]$stats.fullyTransparent
                        allVisiblePixelsBlack = [bool]$stats.allVisiblePixelsBlack
                    })
            }
            finally {
                if ($null -ne $graphics) { $graphics.Dispose() }
                if ($null -ne $textureBitmap) { $textureBitmap.Dispose() }
                if ($null -ne $picture) {
                    $picture.Dispose()
                    $sprite.Picture = $null
                }
                $pixels = $null
                $dds = $null
                [GC]::Collect()
                [GC]::WaitForPendingFinalizers()
            }
        }
    }
}
finally {
    Set-Location -LiteralPath $previousLocation
}

foreach ($path in $allowedPaths) {
    if (-not $matchedAllowed.Contains($path)) {
        throw "Allowed IMG path was not found in source NPK: $path"
    }
}
foreach ($frameKey in $excludedFrames) {
    if (-not $matchedExcluded.Contains($frameKey)) {
        throw "Excluded frame key was not found: $frameKey"
    }
}

$inventoryPath = Join-Path $outputPath 'frame-inventory.json'
$tsvPath = Join-Path $outputPath 'frame-inventory.tsv'
$summaryPath = Join-Path $outputPath 'source-summary.json'

$summary = [ordered]@{
    schemaVersion             = 1
    status                    = 'passed'
    runId                     = $RunId
    mode                      = 'official source NPK frame freeze for illusionslash model and Aseprite workflow'
    source                    = [ordered]@{
        path          = $sourceNpk
        length        = [long]$sourceItem.Length
        lastWriteTime = $sourceItem.LastWriteTime.ToString('o')
        sha256        = $sourceHash
    }
    config                    = [ordered]@{
        path   = $configPath
        sha256 = Get-FileHashText -Path $configPath
    }
    outputDirectory           = $outputPath
    allowedImgPaths           = @($allowedPaths)
    excludedFrameKeys         = @($excludedFrames)
    albums                    = $albumsOut.ToArray()
    frameCount                = $records.Count
    runtimeRequiredFrameCount = @($records | Where-Object { $_.runtimeRequired }).Count
    deployment                = 'not-authorized-not-performed'
}

$inventory = [ordered]@{
    schemaVersion = 1
    status        = 'passed'
    runId         = $RunId
    sourceSummary = 'source-summary.json'
    source        = $summary.source
    records       = $records.ToArray()
}

$inventory | ConvertTo-Json -Depth 20 | Set-Content -LiteralPath $inventoryPath -Encoding UTF8
$summary | ConvertTo-Json -Depth 20 | Set-Content -LiteralPath $summaryPath -Encoding UTF8

$headers = @('frameKey', 'imgPath', 'albumSlug', 'frameIndex', 'relativePng', 'runtimeRequired', 'excluded', 'textureWidth', 'textureHeight', 'width', 'height', 'type', 'textureType')
$lines = New-Object 'Collections.Generic.List[string]'
$lines.Add(($headers -join "`t"))
foreach ($record in $records) {
    $values = foreach ($header in $headers) {
        $value = [string]$record[$header]
        if ($value.Contains("`t") -or $value.Contains("`n") -or $value.Contains("`r")) {
            throw "TSV field contains a tab or newline: $header"
        }
        $value
    }
    $lines.Add(($values -join "`t"))
}
$lines | Set-Content -LiteralPath $tsvPath -Encoding UTF8

Write-Output "Source=$sourceNpk"
Write-Output "SourceSha256=$sourceHash"
Write-Output "OutputDirectory=$outputPath"
Write-Output "Inventory=$inventoryPath"
Write-Output "InventoryTsv=$tsvPath"
Write-Output "FrameCount=$($records.Count)"
Write-Output "RuntimeRequiredFrameCount=$(@($records | Where-Object { $_.runtimeRequired }).Count)"
Write-Output 'Deployment=not-authorized-not-performed'

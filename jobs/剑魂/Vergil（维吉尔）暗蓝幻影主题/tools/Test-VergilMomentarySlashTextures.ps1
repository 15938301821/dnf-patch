[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)]
    [string]$SourceFile,

    [Parameter(Mandatory = $true)]
    [string]$CandidateFile,

    [Parameter(Mandatory = $true)]
    [string]$OutputDirectory,

    [string]$ExtractorDirectory,

    [string]$TexdiagPath
)

$ErrorActionPreference = 'Stop'

if ([IntPtr]::Size -ne 4) {
    throw 'Run this validator with 32-bit PowerShell because ExtractorSharp uses x86 zlib.'
}

$themeRoot = Split-Path -Parent $PSScriptRoot
$professionRoot = Split-Path -Parent $themeRoot
$jobsRoot = Split-Path -Parent $professionRoot
$repoRoot = Split-Path -Parent $jobsRoot
Import-Module (Join-Path $repoRoot 'tools\DnfPatch.Toolchain.psm1') -Force
$ExtractorDirectory = Resolve-DnfExtractorDirectory -Path $ExtractorDirectory -RepositoryRoot $repoRoot
$TexdiagPath = Resolve-DnfDirectXTexTool -Name 'texdiag.exe' -Path $TexdiagPath -RepositoryRoot $repoRoot

$sourcePath = (Resolve-Path -LiteralPath $SourceFile).Path
$candidatePath = (Resolve-Path -LiteralPath $CandidateFile).Path
$outputPath = [IO.Path]::GetFullPath($OutputDirectory)
$coreDll = Join-Path $ExtractorDirectory 'ExtractorSharp.Core.dll'
$jsonDll = Join-Path $ExtractorDirectory 'ExtractorSharp.Json.dll'

foreach ($requiredFile in @($sourcePath, $candidatePath, $coreDll, $jsonDll, $TexdiagPath)) {
    if (-not (Test-Path -LiteralPath $requiredFile -PathType Leaf)) {
        throw "Required file was not found: $requiredFile"
    }
}

$expectedPaths = @(
    'sprite/character/swordman/effect/momentaryslash/drawingsword_blue_ldodge_under.img',
    'sprite/character/swordman/effect/momentaryslash/drawingsword_blue_ldodge_upper.img',
    'sprite/character/swordman/effect/momentaryslash/drawingsword_none_under.img',
    'sprite/character/swordman/effect/momentaryslash/drawingsword_none_upper.img',
    'sprite/character/swordman/effect/momentaryslash/drawingsword_red_ldodge_under.img',
    'sprite/character/swordman/effect/momentaryslash/drawingsword_red_ldodge_upper.img',
    'sprite/character/swordman/effect/momentaryslash/drawingsword_white_ldodge_under.img',
    'sprite/character/swordman/effect/momentaryslash/drawingsword_white_ldodge_upper.img'
)
$excludedFrames = New-Object 'Collections.Generic.HashSet[string]' ([StringComparer]::OrdinalIgnoreCase)
foreach ($path in @(
    'sprite/character/swordman/effect/momentaryslash/drawingsword_blue_ldodge_upper.img#0',
    'sprite/character/swordman/effect/momentaryslash/drawingsword_none_upper.img#0',
    'sprite/character/swordman/effect/momentaryslash/drawingsword_red_ldodge_upper.img#0',
    'sprite/character/swordman/effect/momentaryslash/drawingsword_white_ldodge_upper.img#0'
)) {
    [void]$excludedFrames.Add($path)
}

function Get-ByteSha256 {
    param([AllowNull()][byte[]]$Bytes)

    if ($null -eq $Bytes) {
        return 'null'
    }
    $sha = [Security.Cryptography.SHA256]::Create()
    try {
        return ([BitConverter]::ToString($sha.ComputeHash($Bytes))).Replace('-', '')
    }
    finally {
        $sha.Dispose()
    }
}

function Test-BytesEqual {
    param(
        [AllowNull()][byte[]]$Left,
        [AllowNull()][byte[]]$Right
    )

    if ([object]::ReferenceEquals($Left, $Right)) {
        return $true
    }
    if ($null -eq $Left -or $null -eq $Right -or $Left.Length -ne $Right.Length) {
        return $false
    }
    for ($index = 0; $index -lt $Left.Length; $index++) {
        if ($Left[$index] -ne $Right[$index]) {
            return $false
        }
    }
    return $true
}

function Get-DdsInfo {
    param([byte[]]$Dds)

    if ($null -eq $Dds -or $Dds.Length -lt 144) {
        throw 'DDS payload is too short.'
    }
    $magic = [Text.Encoding]::ASCII.GetString($Dds, 0, 4)
    $headerSize = [BitConverter]::ToInt32($Dds, 4)
    $height = [BitConverter]::ToInt32($Dds, 12)
    $width = [BitConverter]::ToInt32($Dds, 16)
    $mipMapCount = [BitConverter]::ToInt32($Dds, 28)
    $pixelFormatSize = [BitConverter]::ToInt32($Dds, 76)
    $fourCC = [Text.Encoding]::ASCII.GetString($Dds, 84, 4)
    if ($magic -ne 'DDS ' -or $headerSize -ne 124 -or $pixelFormatSize -ne 32 -or $fourCC -ne 'DXT5') {
        throw 'DDS is not a legacy DXT5 payload.'
    }
    if ($width -lt 1 -or $height -lt 1 -or ($mipMapCount -ne 0 -and $mipMapCount -ne 1)) {
        throw 'DDS dimensions or mip count are invalid.'
    }
    $blockCount = [int]([Math]::Ceiling($width / 4.0) * [Math]::Ceiling($height / 4.0))
    $expectedLength = 128 + $blockCount * 16
    if ($Dds.Length -ne $expectedLength) {
        throw "DDS block length mismatch: $($Dds.Length)/$expectedLength"
    }
    return [PSCustomObject]@{
        Width = $width
        Height = $height
        MipMapCountField = $mipMapCount
        FourCC = $fourCC
        DataOffset = 128
        BlockCount = $blockCount
        ExpectedLength = $expectedLength
    }
}

function Copy-ByteRange {
    param(
        [byte[]]$Bytes,
        [int]$Offset,
        [int]$Count
    )

    $result = New-Object byte[] $Count
    [Array]::Copy($Bytes, $Offset, $result, 0, $Count)
    return $result
}

function Get-AlphaBlocks {
    param(
        [byte[]]$Dds,
        $DdsInfo
    )

    $result = New-Object byte[] ($DdsInfo.BlockCount * 8)
    for ($block = 0; $block -lt $DdsInfo.BlockCount; $block++) {
        [Array]::Copy($Dds, $DdsInfo.DataOffset + $block * 16, $result, $block * 8, 8)
    }
    return $result
}

function Get-ChangedColorBlockCount {
    param(
        [byte[]]$SourceDds,
        [byte[]]$CandidateDds,
        $DdsInfo
    )

    $changed = 0
    for ($block = 0; $block -lt $DdsInfo.BlockCount; $block++) {
        $offset = $DdsInfo.DataOffset + $block * 16 + 8
        $blockChanged = $false
        for ($byteIndex = 0; $byteIndex -lt 8; $byteIndex++) {
            if ($SourceDds[$offset + $byteIndex] -ne $CandidateDds[$offset + $byteIndex]) {
                $blockChanged = $true
                break
            }
        }
        if ($blockChanged) {
            $changed++
        }
    }
    return $changed
}

function Get-AlphaPixels {
    param([byte[]]$Bgra)

    $result = New-Object byte[] ($Bgra.Length / 4)
    $target = 0
    for ($index = 3; $index -lt $Bgra.Length; $index += 4) {
        $result[$target] = $Bgra[$index]
        $target++
    }
    return $result
}

function Get-PixelStats {
    param([byte[]]$Bgra)

    $alphaPixels = 0L
    $warmVisiblePixels = 0L
    for ($index = 0; $index -lt $Bgra.Length; $index += 4) {
        $alpha = $Bgra[$index + 3]
        if ($alpha -eq 0) {
            continue
        }
        $alphaPixels++
        if ($alpha -ge 16 -and $Bgra[$index + 2] -gt $Bgra[$index] + 12) {
            $warmVisiblePixels++
        }
    }
    return [PSCustomObject]@{
        AlphaPixels = $alphaPixels
        WarmVisiblePixels = $warmVisiblePixels
    }
}

function Get-TextureMap {
    param($Album)

    $mapField = $Album.Handler.GetType().GetField(
        '_map',
        [Reflection.BindingFlags]'Instance,NonPublic')
    if ($null -eq $mapField) {
        throw "Ver5 texture map field is unavailable: $($Album.Path)"
    }
    $map = $mapField.GetValue($Album.Handler)
    if ($null -eq $map) {
        throw "Ver5 texture map is unavailable: $($Album.Path)"
    }
    return $map
}

function Assert-SpriteAndTextureMetadataEqual {
    param(
        $SourceAlbum,
        $SourceSprite,
        $SourceInfo,
        $CandidateAlbum,
        $CandidateSprite,
        $CandidateInfo
    )

    $key = "$($SourceAlbum.Path)#$($SourceSprite.Index)"
    if ($SourceAlbum.Path -ne $CandidateAlbum.Path -or
        $SourceAlbum.Version.ToString() -ne $CandidateAlbum.Version.ToString() -or
        $SourceSprite.Index -ne $CandidateSprite.Index -or
        $SourceSprite.Type.ToString() -ne $CandidateSprite.Type.ToString() -or
        $SourceSprite.CompressMode.ToString() -ne $CandidateSprite.CompressMode.ToString() -or
        $SourceSprite.Hidden -ne $CandidateSprite.Hidden -or
        $SourceSprite.Width -ne $CandidateSprite.Width -or
        $SourceSprite.Height -ne $CandidateSprite.Height -or
        $SourceSprite.CanvasWidth -ne $CandidateSprite.CanvasWidth -or
        $SourceSprite.CanvasHeight -ne $CandidateSprite.CanvasHeight -or
        $SourceSprite.X -ne $CandidateSprite.X -or
        $SourceSprite.Y -ne $CandidateSprite.Y -or
        $SourceSprite.Length -ne $CandidateSprite.Length) {
        throw "Sprite metadata changed: $key"
    }
    if (($null -ne $SourceSprite.Target) -or ($null -ne $CandidateSprite.Target)) {
        throw "Unexpected LINK target: $key"
    }
    if (-not (Test-BytesEqual $SourceSprite.Data $CandidateSprite.Data)) {
        throw "Sprite data changed: $key"
    }

    $sourceTexture = $SourceInfo.Texture
    $candidateTexture = $CandidateInfo.Texture
    if ($sourceTexture.Index -ne $candidateTexture.Index -or
        $sourceTexture.Width -ne $candidateTexture.Width -or
        $sourceTexture.Height -ne $candidateTexture.Height -or
        $sourceTexture.FullLength -ne $candidateTexture.FullLength -or
        $sourceTexture.Type.ToString() -ne $candidateTexture.Type.ToString() -or
        $sourceTexture.Version.ToString() -ne $candidateTexture.Version.ToString() -or
        $SourceInfo.LeftUp.X -ne $CandidateInfo.LeftUp.X -or
        $SourceInfo.LeftUp.Y -ne $CandidateInfo.LeftUp.Y -or
        $SourceInfo.RightDown.X -ne $CandidateInfo.RightDown.X -or
        $SourceInfo.RightDown.Y -ne $CandidateInfo.RightDown.Y -or
        $SourceInfo.Top -ne $CandidateInfo.Top -or
        $SourceInfo.Unknown -ne $CandidateInfo.Unknown) {
        throw "Texture metadata changed: $key"
    }
    if ($candidateTexture.Data.Length -ne $candidateTexture.Length) {
        throw "Candidate compressed texture length is inconsistent: $key"
    }
}

New-Item -ItemType Directory -Path $outputPath -Force | Out-Null
$ddsDirectory = Join-Path $outputPath 'dds'
New-Item -ItemType Directory -Path $ddsDirectory -Force | Out-Null

$previousLocation = Get-Location
try {
    Set-Location -LiteralPath $ExtractorDirectory
    [void][Reflection.Assembly]::LoadFrom($jsonDll)
    [void][Reflection.Assembly]::LoadFrom($coreDll)
    [void][Reflection.Assembly]::LoadWithPartialName('System.Drawing')

    $sourceAlbums = [ExtractorSharp.Core.Coder.NpkCoder]::Load($sourcePath)
    $candidateAlbums = [ExtractorSharp.Core.Coder.NpkCoder]::Load($candidatePath)
    if ($sourceAlbums.Count -ne 8 -or $candidateAlbums.Count -ne 8) {
        throw 'Source or candidate IMG count is not 8.'
    }

    $records = New-Object 'Collections.Generic.List[object]'
    $allowedCount = 0
    $excludedCount = 0
    $totalChangedColorBlocks = 0
    $totalAlphaBlocks = 0

    for ($albumIndex = 0; $albumIndex -lt 8; $albumIndex++) {
        $sourceAlbum = $sourceAlbums[$albumIndex]
        $candidateAlbum = $candidateAlbums[$albumIndex]
        if ($sourceAlbum.Path -ne $expectedPaths[$albumIndex] -or
            $candidateAlbum.Path -ne $expectedPaths[$albumIndex]) {
            throw "IMG order/path changed at index $albumIndex."
        }
        if ($sourceAlbum.Version.ToString() -ne 'Ver5' -or
            $candidateAlbum.Version.ToString() -ne 'Ver5' -or
            $sourceAlbum.List.Count -ne 5 -or
            $candidateAlbum.List.Count -ne 5) {
            throw "IMG version or frame count changed: $($sourceAlbum.Path)"
        }

        $sourceMap = Get-TextureMap $sourceAlbum
        $candidateMap = Get-TextureMap $candidateAlbum
        if ($sourceMap.Count -ne 5 -or $candidateMap.Count -ne 5) {
            throw "Texture map count changed: $($sourceAlbum.Path)"
        }

        for ($frameIndex = 0; $frameIndex -lt 5; $frameIndex++) {
            $globalIndex = $albumIndex * 5 + $frameIndex
            $sourceSprite = $sourceAlbum.List[$frameIndex]
            $candidateSprite = $candidateAlbum.List[$frameIndex]
            $sourceInfo = $sourceMap[$sourceSprite.Index]
            $candidateInfo = $candidateMap[$candidateSprite.Index]
            if ($null -eq $sourceInfo -or $null -eq $candidateInfo) {
                throw "Missing texture mapping: $($sourceAlbum.Path)#$frameIndex"
            }
            Assert-SpriteAndTextureMetadataEqual $sourceAlbum $sourceSprite $sourceInfo $candidateAlbum $candidateSprite $candidateInfo

            $sourceTexture = $sourceInfo.Texture
            $candidateTexture = $candidateInfo.Texture
            $sourceDds = [ExtractorSharp.Core.Lib.Zlib]::Decompress(
                $sourceTexture.Data,
                $sourceTexture.FullLength)
            $candidateDds = [ExtractorSharp.Core.Lib.Zlib]::Decompress(
                $candidateTexture.Data,
                $candidateTexture.FullLength)
            $sourceDdsInfo = Get-DdsInfo $sourceDds
            $candidateDdsInfo = Get-DdsInfo $candidateDds
            if ($sourceDdsInfo.Width -ne $candidateDdsInfo.Width -or
                $sourceDdsInfo.Height -ne $candidateDdsInfo.Height -or
                $sourceDdsInfo.ExpectedLength -ne $candidateDdsInfo.ExpectedLength) {
                throw "DDS geometry changed: $($sourceAlbum.Path)#$frameIndex"
            }

            $sourceHeader = Copy-ByteRange $sourceDds 0 128
            $candidateHeader = Copy-ByteRange $candidateDds 0 128
            if (-not (Test-BytesEqual $sourceHeader $candidateHeader)) {
                throw "DDS header changed: $($sourceAlbum.Path)#$frameIndex"
            }
            $sourceAlphaBlocks = Get-AlphaBlocks $sourceDds $sourceDdsInfo
            $candidateAlphaBlocks = Get-AlphaBlocks $candidateDds $candidateDdsInfo
            if (-not (Test-BytesEqual $sourceAlphaBlocks $candidateAlphaBlocks)) {
                throw "BC3 alpha blocks changed: $($sourceAlbum.Path)#$frameIndex"
            }

            $sourcePicture = $null
            $candidatePicture = $null
            try {
                $sourcePicture = $sourceTexture.Pictrue
                $candidatePicture = $candidateTexture.Pictrue
                if ($null -eq $sourcePicture -or $null -eq $candidatePicture) {
                    throw "Texture decode failed: $($sourceAlbum.Path)#$frameIndex"
                }
                $sourceBgra = [ExtractorSharp.Core.Lib.Bitmaps]::ToArray($sourcePicture)
                $candidateBgra = [ExtractorSharp.Core.Lib.Bitmaps]::ToArray($candidatePicture)
            }
            finally {
                if ($null -ne $sourcePicture) {
                    $sourcePicture.Dispose()
                    $sourceTexture.Pictrue = $null
                }
                if ($null -ne $candidatePicture) {
                    $candidatePicture.Dispose()
                    $candidateTexture.Pictrue = $null
                }
            }

            $sourceAlpha = Get-AlphaPixels $sourceBgra
            $candidateAlpha = Get-AlphaPixels $candidateBgra
            if (-not (Test-BytesEqual $sourceAlpha $candidateAlpha)) {
                throw "Decoded alpha changed: $($sourceAlbum.Path)#$frameIndex"
            }
            $sourcePixelStats = Get-PixelStats $sourceBgra
            $candidatePixelStats = Get-PixelStats $candidateBgra
            $changedColorBlocks = Get-ChangedColorBlockCount $sourceDds $candidateDds $sourceDdsInfo
            $frameKey = "$($sourceAlbum.Path)#$frameIndex"
            $excluded = $excludedFrames.Contains($frameKey)
            if ($excluded) {
                if (-not (Test-BytesEqual $sourceTexture.Data $candidateTexture.Data) -or
                    -not (Test-BytesEqual $sourceDds $candidateDds) -or
                    -not (Test-BytesEqual $sourceBgra $candidateBgra) -or
                    $changedColorBlocks -ne 0) {
                    throw "Excluded texture changed: $frameKey"
                }
                $excludedCount++
            }
            else {
                if ((Test-BytesEqual $sourceDds $candidateDds) -or
                    (Test-BytesEqual $sourceBgra $candidateBgra) -or
                    $changedColorBlocks -eq 0) {
                    throw "Allowed texture did not change as required: $frameKey"
                }
                if ($candidatePixelStats.AlphaPixels -eq 0 -or
                    $candidatePixelStats.WarmVisiblePixels -ne 0) {
                    throw "Allowed output texture is invisible or warm-shifted: $frameKey"
                }
                $allowedCount++
            }

            $ddsFile = Join-Path $ddsDirectory ('texture-{0:D4}.dds' -f $globalIndex)
            [IO.File]::WriteAllBytes($ddsFile, $candidateDds)
            $texdiagOutput = & $TexdiagPath info -nologo -- $ddsFile 2>&1
            $texdiagText = $texdiagOutput -join ([Environment]::NewLine)
            if ($LASTEXITCODE -ne 0 -or
                $texdiagText -notmatch 'format\s*=\s*BC3_UNORM' -or
                $texdiagText -notmatch 'mipLevels\s*=\s*1') {
                throw "texdiag rejected output DDS: $frameKey"
            }

            $records.Add([PSCustomObject]@{
                GlobalIndex = $globalIndex
                ImgPath = $sourceAlbum.Path
                FrameIndex = $frameIndex
                Excluded = $excluded
                ImgVersion = $sourceAlbum.Version.ToString()
                SpriteType = $sourceSprite.Type.ToString()
                CompressMode = $sourceSprite.CompressMode.ToString()
                Width = $sourceSprite.Width
                Height = $sourceSprite.Height
                CanvasWidth = $sourceSprite.CanvasWidth
                CanvasHeight = $sourceSprite.CanvasHeight
                X = $sourceSprite.X
                Y = $sourceSprite.Y
                TextureIndex = $sourceTexture.Index
                TextureType = $sourceTexture.Type.ToString()
                TextureVersion = $sourceTexture.Version.ToString()
                TextureWidth = $sourceTexture.Width
                TextureHeight = $sourceTexture.Height
                AtlasLeft = $sourceInfo.LeftUp.X
                AtlasTop = $sourceInfo.LeftUp.Y
                AtlasRight = $sourceInfo.RightDown.X
                AtlasBottom = $sourceInfo.RightDown.Y
                Rotation = $sourceInfo.Top
                Unknown = $sourceInfo.Unknown
                DdsFourCC = $sourceDdsInfo.FourCC
                DdsLength = $candidateDds.Length
                ExpectedDdsLength = $candidateDdsInfo.ExpectedLength
                SourceDdsSha256 = Get-ByteSha256 $sourceDds
                OutputDdsSha256 = Get-ByteSha256 $candidateDds
                SourceHeaderSha256 = Get-ByteSha256 $sourceHeader
                OutputHeaderSha256 = Get-ByteSha256 $candidateHeader
                SourceAlphaBlockSha256 = Get-ByteSha256 $sourceAlphaBlocks
                OutputAlphaBlockSha256 = Get-ByteSha256 $candidateAlphaBlocks
                SourceBgraSha256 = Get-ByteSha256 $sourceBgra
                OutputBgraSha256 = Get-ByteSha256 $candidateBgra
                SourceAlphaSha256 = Get-ByteSha256 $sourceAlpha
                OutputAlphaSha256 = Get-ByteSha256 $candidateAlpha
                SourceAlphaPixels = $sourcePixelStats.AlphaPixels
                OutputAlphaPixels = $candidatePixelStats.AlphaPixels
                ChangedColorBlocks = $changedColorBlocks
                OutputWarmVisiblePixels = $candidatePixelStats.WarmVisiblePixels
                Texdiag = 'BC3_UNORM single mip passed'
            })
            $totalChangedColorBlocks += $changedColorBlocks
            $totalAlphaBlocks += $sourceDdsInfo.BlockCount
        }
    }

    if ($allowedCount -ne 36 -or $excludedCount -ne 4 -or $records.Count -ne 40) {
        throw "Validation selection count mismatch: allowed=$allowedCount excluded=$excludedCount records=$($records.Count)"
    }

    $csvFile = Join-Path $outputPath 'texture-validation.csv'
    $records | Export-Csv -LiteralPath $csvFile -NoTypeInformation -Encoding UTF8
    $summary = [PSCustomObject]@{
        Status = 'passed'
        SourceFile = $sourcePath
        SourceSha256 = (Get-FileHash -LiteralPath $sourcePath -Algorithm SHA256).Hash
        CandidateFile = $candidatePath
        CandidateSha256 = (Get-FileHash -LiteralPath $candidatePath -Algorithm SHA256).Hash
        CheckedTextures = $records.Count
        AllowedChangedTextures = $allowedCount
        ExcludedByteIdenticalTextures = $excludedCount
        ChangedColorBlocks = $totalChangedColorBlocks
        PreservedAlphaBlocks = $totalAlphaBlocks
        HeaderMismatches = 0
        AlphaBlockMismatches = 0
        DecodedAlphaMismatches = 0
        WarmVisiblePixels = [long](($records | Measure-Object -Property OutputWarmVisiblePixels -Sum).Sum)
        TexdiagPassedTextures = $records.Count
        TextureReport = $csvFile
        DdsDirectory = $ddsDirectory
    }
    $summaryFile = Join-Path $outputPath 'texture-validation-summary.json'
    $summary | ConvertTo-Json -Depth 4 | Set-Content -LiteralPath $summaryFile -Encoding UTF8
    $summary
}
finally {
    Set-Location -LiteralPath $previousLocation
}

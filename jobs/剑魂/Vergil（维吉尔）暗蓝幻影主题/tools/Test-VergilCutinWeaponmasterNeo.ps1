[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)]
    [string]$SourceNpk,

    [Parameter(Mandatory = $true)]
    [string]$OutputNpk,

    [Parameter(Mandatory = $true)]
    [string]$OutputFile,

    [string]$ExtractorDirectory,

    [string]$ExpectedSourceSha256 = '51C7FF71615DB6982D55BFBFEEA1741F37778CD4B89BE2C8B5833DD329E61224'
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
$OutputEncoding = [Console]::OutputEncoding = New-Object System.Text.UTF8Encoding($false)

if ([IntPtr]::Size -ne 4) {
    throw 'Run this validator with 32-bit PowerShell because ExtractorSharp uses x86 zlib.'
}

$targetImg = 'sprite/character/swordman/effect/cutin/cutin_weaponmaster_neo.img'
$expectedEntryCount = 26
$expectedPackageFrameCount = 834
$repoRoot = [IO.Path]::GetFullPath((Join-Path $PSScriptRoot '..\..\..\..'))
Import-Module (Join-Path $repoRoot 'tools\DnfPatch.Toolchain.psm1') -Force
$extractorPath = Resolve-DnfExtractorDirectory -Path $ExtractorDirectory -RepositoryRoot $repoRoot
$sourcePath = (Resolve-Path -LiteralPath $SourceNpk).Path
$outputPath = (Resolve-Path -LiteralPath $OutputNpk).Path
$reportPath = [IO.Path]::GetFullPath($OutputFile)
$coreDll = Join-Path $extractorPath 'ExtractorSharp.Core.dll'
$jsonDll = Join-Path $extractorPath 'ExtractorSharp.Json.dll'

if (Test-Path -LiteralPath $reportPath) {
    throw "Refusing to overwrite an existing validation report: $reportPath"
}
if ($sourcePath.Equals($outputPath, [StringComparison]::OrdinalIgnoreCase)) {
    throw 'Source and output NPK paths must be different.'
}

function Assert-Condition {
    param([bool]$Condition, [string]$Message)

    if (-not $Condition) {
        throw $Message
    }
}

function ConvertTo-Hex {
    param([byte[]]$Bytes)

    return [BitConverter]::ToString($Bytes).Replace('-', '')
}

function Get-RangeSha256 {
    param(
        [IO.Stream]$Stream,
        [long]$Offset,
        [long]$Length
    )

    $Stream.Position = $Offset
    $sha = [Security.Cryptography.SHA256]::Create()
    $buffer = New-Object byte[] (1024 * 1024)
    $empty = New-Object byte[] 0
    $remaining = $Length
    try {
        while ($remaining -gt 0) {
            $requested = [int][Math]::Min([long]$buffer.Length, $remaining)
            $read = $Stream.Read($buffer, 0, $requested)
            if ($read -le 0) {
                throw "Unexpected end of NPK payload at offset $Offset."
            }
            $null = $sha.TransformBlock($buffer, 0, $read, $buffer, 0)
            $remaining -= $read
        }
        $null = $sha.TransformFinalBlock($empty, 0, 0)
        return ConvertTo-Hex -Bytes $sha.Hash
    }
    finally {
        $sha.Dispose()
    }
}

function Get-NpkPayloadInventory {
    param([string]$Path)

    $stream = [IO.File]::Open($Path, [IO.FileMode]::Open, [IO.FileAccess]::Read, [IO.FileShare]::Read)
    $reader = New-Object IO.BinaryReader($stream, [Text.Encoding]::ASCII, $true)
    $sha = [Security.Cryptography.SHA256]::Create()
    try {
        $magic = [Text.Encoding]::ASCII.GetString($reader.ReadBytes(16)).TrimEnd([char]0)
        Assert-Condition ($magic -eq 'NeoplePack_Bill') "Invalid NPK magic in ${Path}: $magic"
        $entryCount = $reader.ReadInt32()
        Assert-Condition ($entryCount -eq $expectedEntryCount) `
            "NPK entry count changed in ${Path}: $entryCount/$expectedEntryCount"
        $headerLength = 20L + 264L * $entryCount
        $dataStart = $headerLength + 32L
        Assert-Condition ($dataStart -lt $stream.Length) "NPK header exceeds file length: $Path"

        $nameKey = [Text.Encoding]::ASCII.GetBytes(
            'puchikon@neople dungeon and fighter ' + ('DNF' * 73) + [char]0)
        Assert-Condition ($nameKey.Length -eq 256) 'Unexpected NPK filename key length.'
        $entries = New-Object 'System.Collections.Generic.List[object]'
        $paths = New-Object 'System.Collections.Generic.HashSet[string]' ([StringComparer]::OrdinalIgnoreCase)
        for ($entryIndex = 0; $entryIndex -lt $entryCount; $entryIndex++) {
            $offset = [long]$reader.ReadInt32()
            $size = [long]$reader.ReadInt32()
            $encryptedName = $reader.ReadBytes(256)
            Assert-Condition ($encryptedName.Length -eq 256) "Truncated NPK path at entry $entryIndex."
            $plainName = New-Object byte[] 256
            for ($byteIndex = 0; $byteIndex -lt 256; $byteIndex++) {
                $plainName[$byteIndex] = $encryptedName[$byteIndex] -bxor $nameKey[$byteIndex]
            }
            $nullIndex = [Array]::IndexOf($plainName, [byte]0)
            Assert-Condition ($nullIndex -ge 0) "NPK path is not null terminated at entry $entryIndex."
            $internalPath = [Text.Encoding]::ASCII.GetString($plainName, 0, $nullIndex)
            Assert-Condition (-not [string]::IsNullOrWhiteSpace($internalPath)) `
                "NPK path is empty at entry $entryIndex."
            Assert-Condition ($paths.Add($internalPath)) "Duplicate NPK path: $internalPath"
            Assert-Condition ($offset -ge $dataStart -and $size -gt 0 -and $offset + $size -le $stream.Length) `
                "NPK entry is outside the file: $internalPath"
            $entries.Add([pscustomobject]@{
                index = $entryIndex
                offset = $offset
                size = $size
                path = $internalPath
            })
        }

        $storedHeaderHash = $reader.ReadBytes(32)
        Assert-Condition ($storedHeaderHash.Length -eq 32) 'NPK header SHA-256 is truncated.'
        $hashInputLength = [int]($headerLength - ($headerLength % 17L))
        $stream.Position = 0
        $hashInput = $reader.ReadBytes($hashInputLength)
        $computedHeaderHash = $sha.ComputeHash($hashInput)
        Assert-Condition ((ConvertTo-Hex $storedHeaderHash) -eq (ConvertTo-Hex $computedHeaderHash)) `
            "NPK header SHA-256 mismatch: $Path"

        foreach ($entry in $entries) {
            $entry | Add-Member -NotePropertyName payloadSha256 `
                -NotePropertyValue (Get-RangeSha256 -Stream $stream -Offset $entry.offset -Length $entry.size)
        }
        return [pscustomobject]@{
            path = $Path
            length = [long](Get-Item -LiteralPath $Path).Length
            sha256 = (Get-FileHash -LiteralPath $Path -Algorithm SHA256).Hash
            entryCount = $entryCount
            entries = $entries.ToArray()
        }
    }
    finally {
        $sha.Dispose()
        $reader.Dispose()
        $stream.Dispose()
    }
}

function Get-TextureMap {
    param([object]$Album)

    $mapField = $Album.Handler.GetType().GetField(
        '_map',
        [Reflection.BindingFlags]'Instance,NonPublic')
    Assert-Condition ($null -ne $mapField) "Ver5 texture map is unavailable: $($Album.Path)"
    $map = $mapField.GetValue($Album.Handler)
    Assert-Condition ($null -ne $map) "Ver5 texture map is null: $($Album.Path)"
    return $map
}

function Get-DdsInfo {
    param(
        [byte[]]$Dds,
        [string]$ExpectedFourCc,
        [int]$ExpectedWidth,
        [int]$ExpectedHeight
    )

    Assert-Condition ($null -ne $Dds -and $Dds.Length -ge 136) 'DDS payload is too short.'
    Assert-Condition ([BitConverter]::ToInt32($Dds, 0) -eq 0x20534444) 'DDS magic is invalid.'
    $headerSize = [BitConverter]::ToInt32($Dds, 4)
    $height = [BitConverter]::ToInt32($Dds, 12)
    $width = [BitConverter]::ToInt32($Dds, 16)
    $mipLevels = [BitConverter]::ToInt32($Dds, 28)
    $pixelFormatSize = [BitConverter]::ToInt32($Dds, 76)
    $fourCc = [Text.Encoding]::ASCII.GetString($Dds, 84, 4)
    Assert-Condition ($headerSize -eq 124 -and $pixelFormatSize -eq 32) 'DDS header size is invalid.'
    Assert-Condition ($fourCc -eq $ExpectedFourCc) "DDS FourCC changed: $fourCc/$ExpectedFourCc"
    Assert-Condition ($width -eq $ExpectedWidth -and $height -eq $ExpectedHeight) `
        "DDS geometry changed: ${width}x${height}/${ExpectedWidth}x${ExpectedHeight}"
    Assert-Condition ($mipLevels -in @(0, 1)) "DDS mip level count is invalid: $mipLevels"
    $blockBytes = if ($fourCc -eq 'DXT1') { 8 } else { 16 }
    $blockCount = [int]([Math]::Ceiling($width / 4.0) * [Math]::Ceiling($height / 4.0))
    $expectedLength = 128 + $blockCount * $blockBytes
    Assert-Condition ($Dds.Length -eq $expectedLength) `
        "DDS payload length changed: $($Dds.Length)/$expectedLength"
    return [pscustomobject]@{
        fourCc = $fourCc
        width = $width
        height = $height
        dataOffset = 128
        blockCount = $blockCount
        blockBytes = $blockBytes
    }
}

if ($null -eq ('DnfCutinByteValidation' -as [type])) {
    Add-Type -TypeDefinition @'
using System;

public sealed class DnfCutinBgraResult
{
    public long PixelCount;
    public long AlphaMismatchPixels;
    public long ChangedRgbPixels;
    public long ChangedVisibleRgbPixels;
    public long SourceVisiblePixels;
    public long OutputVisiblePixels;
    public long SourceNonBlackVisiblePixels;
    public long OutputNonBlackVisiblePixels;
    public long OutputOpaqueBlackPixels;
}

public sealed class DnfCutinBc3Result
{
    public int AlphaBlockMismatchCount;
    public int ChangedColorBlockCount;
}

public static class DnfCutinByteValidation
{
    public static bool Equal(byte[] left, byte[] right)
    {
        if (Object.ReferenceEquals(left, right)) return true;
        if (left == null || right == null || left.Length != right.Length) return false;
        for (int index = 0; index < left.Length; index++)
            if (left[index] != right[index]) return false;
        return true;
    }

    public static bool EqualRange(byte[] left, byte[] right, int offset, int count)
    {
        if (left == null || right == null || offset < 0 || count < 0 ||
            offset + count > left.Length || offset + count > right.Length) return false;
        for (int index = 0; index < count; index++)
            if (left[offset + index] != right[offset + index]) return false;
        return true;
    }

    public static DnfCutinBc3Result CompareBc3(byte[] source, byte[] output, int dataOffset, int blockCount)
    {
        DnfCutinBc3Result result = new DnfCutinBc3Result();
        for (int block = 0; block < blockCount; block++)
        {
            int offset = dataOffset + block * 16;
            bool alphaChanged = false;
            bool colorChanged = false;
            for (int index = 0; index < 8; index++)
                if (source[offset + index] != output[offset + index]) alphaChanged = true;
            for (int index = 8; index < 16; index++)
                if (source[offset + index] != output[offset + index]) colorChanged = true;
            if (alphaChanged) result.AlphaBlockMismatchCount++;
            if (colorChanged) result.ChangedColorBlockCount++;
        }
        return result;
    }

    public static DnfCutinBgraResult CompareBgra(byte[] source, byte[] output)
    {
        if (source == null || output == null || source.Length != output.Length || source.Length % 4 != 0)
            throw new ArgumentException("BGRA arrays must have equal four-byte pixel lengths.");
        DnfCutinBgraResult result = new DnfCutinBgraResult();
        result.PixelCount = source.Length / 4;
        for (int offset = 0; offset < source.Length; offset += 4)
        {
            byte sourceAlpha = source[offset + 3];
            byte outputAlpha = output[offset + 3];
            bool rgbChanged = source[offset] != output[offset] ||
                source[offset + 1] != output[offset + 1] ||
                source[offset + 2] != output[offset + 2];
            if (sourceAlpha != outputAlpha) result.AlphaMismatchPixels++;
            if (rgbChanged) result.ChangedRgbPixels++;
            if (rgbChanged && (sourceAlpha != 0 || outputAlpha != 0)) result.ChangedVisibleRgbPixels++;
            if (sourceAlpha != 0)
            {
                result.SourceVisiblePixels++;
                if (source[offset] != 0 || source[offset + 1] != 0 || source[offset + 2] != 0)
                    result.SourceNonBlackVisiblePixels++;
            }
            if (outputAlpha != 0)
            {
                result.OutputVisiblePixels++;
                if (output[offset] != 0 || output[offset + 1] != 0 || output[offset + 2] != 0)
                    result.OutputNonBlackVisiblePixels++;
                else if (outputAlpha == 255)
                    result.OutputOpaqueBlackPixels++;
            }
        }
        return result;
    }
}
'@
}

$expectedSourceHash = $ExpectedSourceSha256.ToUpperInvariant()
Assert-Condition ($expectedSourceHash -match '^[0-9A-F]{64}$') 'Expected source SHA-256 is invalid.'
$sourceInventory = Get-NpkPayloadInventory -Path $sourcePath
$outputInventory = Get-NpkPayloadInventory -Path $outputPath
Assert-Condition ($sourceInventory.sha256 -eq $expectedSourceHash) `
    "Source SHA-256 changed: $($sourceInventory.sha256)/$expectedSourceHash"
Assert-Condition ($sourceInventory.entryCount -eq $outputInventory.entryCount) 'NPK entry count changed.'

$nonTargetIdentical = 0
$targetPayloadChanged = $false
for ($entryIndex = 0; $entryIndex -lt $sourceInventory.entryCount; $entryIndex++) {
    $sourceEntry = $sourceInventory.entries[$entryIndex]
    $outputEntry = $outputInventory.entries[$entryIndex]
    Assert-Condition ([string]$sourceEntry.path -ieq [string]$outputEntry.path) `
        "NPK path order changed at entry $entryIndex."
    if ([string]$sourceEntry.path -ieq $targetImg) {
        $targetPayloadChanged = [string]$sourceEntry.payloadSha256 -ne [string]$outputEntry.payloadSha256
        Assert-Condition $targetPayloadChanged 'Target IMG payload did not change.'
    }
    else {
        Assert-Condition ([long]$sourceEntry.size -eq [long]$outputEntry.size -and
            [string]$sourceEntry.payloadSha256 -eq [string]$outputEntry.payloadSha256) `
            "Non-target IMG payload changed: $($sourceEntry.path)"
        $nonTargetIdentical++
    }
}
Assert-Condition ($nonTargetIdentical -eq 25) `
    "Non-target payload preservation count changed: $nonTargetIdentical/25"

$previousLocation = Get-Location
try {
    Set-Location -LiteralPath $extractorPath
    [void][Reflection.Assembly]::LoadFrom($jsonDll)
    [void][Reflection.Assembly]::LoadFrom($coreDll)
    [void][Reflection.Assembly]::LoadWithPartialName('System.Drawing')

    $sourceAlbums = @([ExtractorSharp.Core.Coder.NpkCoder]::Load($sourcePath))
    $outputAlbums = @([ExtractorSharp.Core.Coder.NpkCoder]::Load($outputPath))
    Assert-Condition ($sourceAlbums.Count -eq $expectedEntryCount -and
        $outputAlbums.Count -eq $expectedEntryCount) 'Decoded album count changed.'
    $sourcePackageFrames = 0
    $outputPackageFrames = 0
    $sourceTarget = $null
    $outputTarget = $null
    for ($albumIndex = 0; $albumIndex -lt $sourceAlbums.Count; $albumIndex++) {
        $sourceAlbum = $sourceAlbums[$albumIndex]
        $outputAlbum = $outputAlbums[$albumIndex]
        Assert-Condition ([string]$sourceAlbum.Path -ieq [string]$outputAlbum.Path) `
            "Decoded IMG path order changed at album $albumIndex."
        Assert-Condition ([string]$sourceAlbum.Version -eq [string]$outputAlbum.Version) `
            "IMG version changed: $($sourceAlbum.Path)"
        Assert-Condition ([int]$sourceAlbum.List.Count -eq [int]$outputAlbum.List.Count) `
            "IMG frame count changed: $($sourceAlbum.Path)"
        $sourcePackageFrames += [int]$sourceAlbum.List.Count
        $outputPackageFrames += [int]$outputAlbum.List.Count
        if ([string]$sourceAlbum.Path -ieq $targetImg) {
            Assert-Condition ($null -eq $sourceTarget) 'Duplicate target IMG in source NPK.'
            $sourceTarget = $sourceAlbum
            $outputTarget = $outputAlbum
        }
    }
    Assert-Condition ($sourcePackageFrames -eq $expectedPackageFrameCount -and
        $outputPackageFrames -eq $expectedPackageFrameCount) `
        "Decoded package frame count changed: $sourcePackageFrames/$outputPackageFrames/$expectedPackageFrameCount"
    Assert-Condition ($null -ne $sourceTarget -and $null -ne $outputTarget) 'Target IMG was not decoded.'
    Assert-Condition ([string]$sourceTarget.Version -eq 'Ver5' -and $sourceTarget.List.Count -eq 27) `
        'Target IMG must remain Ver5 with 27 frames.'

    $sourceMap = Get-TextureMap -Album $sourceTarget
    $outputMap = Get-TextureMap -Album $outputTarget
    $frameRecords = New-Object 'System.Collections.Generic.List[object]'
    $metadataDiffCount = 0
    $changedFrameCount = 0
    $preservedPlaceholderCount = 0
    $alphaMismatchPixelCount = 0L
    $targetPixelFailureCount = 0
    $bc3AlphaBlockMismatchCount = 0
    $totalChangedColorBlocks = 0L

    for ($frameIndex = 0; $frameIndex -lt 27; $frameIndex++) {
        $sourceSprite = $sourceTarget.List[$frameIndex]
        $outputSprite = $outputTarget.List[$frameIndex]
        Assert-Condition ($sourceMap.ContainsKey($frameIndex) -and $outputMap.ContainsKey($frameIndex)) `
            "Target texture map is missing frame $frameIndex."
        $sourceInfo = $sourceMap[$frameIndex]
        $outputInfo = $outputMap[$frameIndex]
        $sourceTexture = $sourceInfo.Texture
        $outputTexture = $outputInfo.Texture
        $sourceTargetIndex = if ($null -eq $sourceSprite.Target) { -1 } else { [int]$sourceSprite.Target.Index }
        $outputTargetIndex = if ($null -eq $outputSprite.Target) { -1 } else { [int]$outputSprite.Target.Index }
        $metadataEqual =
            [int]$sourceSprite.Index -eq [int]$outputSprite.Index -and
            [string]$sourceSprite.Type -eq [string]$outputSprite.Type -and
            [string]$sourceSprite.CompressMode -eq [string]$outputSprite.CompressMode -and
            [bool]$sourceSprite.Hidden -eq [bool]$outputSprite.Hidden -and
            $sourceTargetIndex -eq $outputTargetIndex -and
            [int]$sourceSprite.Width -eq [int]$outputSprite.Width -and
            [int]$sourceSprite.Height -eq [int]$outputSprite.Height -and
            [int]$sourceSprite.CanvasWidth -eq [int]$outputSprite.CanvasWidth -and
            [int]$sourceSprite.CanvasHeight -eq [int]$outputSprite.CanvasHeight -and
            [int]$sourceSprite.X -eq [int]$outputSprite.X -and
            [int]$sourceSprite.Y -eq [int]$outputSprite.Y -and
            [int]$sourceSprite.Length -eq [int]$outputSprite.Length -and
            [DnfCutinByteValidation]::Equal($sourceSprite.Data, $outputSprite.Data) -and
            [int]$sourceTexture.Index -eq [int]$outputTexture.Index -and
            [int]$sourceTexture.Width -eq [int]$outputTexture.Width -and
            [int]$sourceTexture.Height -eq [int]$outputTexture.Height -and
            [int]$sourceTexture.FullLength -eq [int]$outputTexture.FullLength -and
            [string]$sourceTexture.Type -eq [string]$outputTexture.Type -and
            [string]$sourceTexture.Version -eq [string]$outputTexture.Version -and
            [int]$sourceInfo.LeftUp.X -eq [int]$outputInfo.LeftUp.X -and
            [int]$sourceInfo.LeftUp.Y -eq [int]$outputInfo.LeftUp.Y -and
            [int]$sourceInfo.RightDown.X -eq [int]$outputInfo.RightDown.X -and
            [int]$sourceInfo.RightDown.Y -eq [int]$outputInfo.RightDown.Y -and
            [int]$sourceInfo.Top -eq [int]$outputInfo.Top -and
            [int]$sourceInfo.Unknown -eq [int]$outputInfo.Unknown
        if (-not $metadataEqual) {
            $metadataDiffCount++
        }
        Assert-Condition $metadataEqual "Target frame metadata changed: $frameIndex"

        $sourceDds = [ExtractorSharp.Core.Lib.Zlib]::Decompress(
            $sourceTexture.Data,
            $sourceTexture.FullLength)
        $outputDds = [ExtractorSharp.Core.Lib.Zlib]::Decompress(
            $outputTexture.Data,
            $outputTexture.FullLength)
        $placeholder = $frameIndex -le 2
        $expectedFourCc = if ($placeholder) { 'DXT1' } else { 'DXT5' }
        $sourceDdsInfo = Get-DdsInfo -Dds $sourceDds -ExpectedFourCc $expectedFourCc `
            -ExpectedWidth ([int]$sourceTexture.Width) -ExpectedHeight ([int]$sourceTexture.Height)
        $outputDdsInfo = Get-DdsInfo -Dds $outputDds -ExpectedFourCc $expectedFourCc `
            -ExpectedWidth ([int]$outputTexture.Width) -ExpectedHeight ([int]$outputTexture.Height)
        Assert-Condition ([DnfCutinByteValidation]::EqualRange($sourceDds, $outputDds, 0, 128)) `
            "DDS header changed at target frame $frameIndex."

        $sourcePicture = $null
        $outputPicture = $null
        try {
            $sourcePicture = $sourceSprite.Picture
            $outputPicture = $outputSprite.Picture
            Assert-Condition ($null -ne $sourcePicture -and $null -ne $outputPicture) `
                "Target frame could not be decoded: $frameIndex"
            Assert-Condition ($sourcePicture.Width -eq $outputPicture.Width -and
                $sourcePicture.Height -eq $outputPicture.Height) `
                "Decoded target frame geometry changed: $frameIndex"
            $sourcePixels = [ExtractorSharp.Core.Lib.Bitmaps]::ToArray($sourcePicture)
            $outputPixels = [ExtractorSharp.Core.Lib.Bitmaps]::ToArray($outputPicture)
            $pixelResult = [DnfCutinByteValidation]::CompareBgra($sourcePixels, $outputPixels)
            $alphaMismatchPixelCount += [long]$pixelResult.AlphaMismatchPixels

            if ($placeholder) {
                Assert-Condition ([DnfCutinByteValidation]::Equal($sourceDds, $outputDds)) `
                    "Transparent placeholder DDS changed: $frameIndex"
                Assert-Condition ([DnfCutinByteValidation]::Equal($sourcePixels, $outputPixels) -and
                    [long]$pixelResult.OutputVisiblePixels -eq 0) `
                    "Transparent placeholder pixels changed: $frameIndex"
                $preservedPlaceholderCount++
            }
            else {
                $bc3Result = [DnfCutinByteValidation]::CompareBc3(
                    $sourceDds,
                    $outputDds,
                    [int]$sourceDdsInfo.dataOffset,
                    [int]$sourceDdsInfo.blockCount)
                $bc3AlphaBlockMismatchCount += [int]$bc3Result.AlphaBlockMismatchCount
                $totalChangedColorBlocks += [int]$bc3Result.ChangedColorBlockCount
                $pixelPassed = [int]$bc3Result.AlphaBlockMismatchCount -eq 0 -and
                    [int]$bc3Result.ChangedColorBlockCount -gt 0 -and
                    [long]$pixelResult.AlphaMismatchPixels -eq 0 -and
                    [long]$pixelResult.ChangedVisibleRgbPixels -gt 0 -and
                    [long]$pixelResult.OutputVisiblePixels -gt 0 -and
                    [long]$pixelResult.OutputNonBlackVisiblePixels -gt 0 -and
                    [long]$pixelResult.OutputOpaqueBlackPixels -lt [long]$pixelResult.PixelCount
                if (-not $pixelPassed) {
                    $targetPixelFailureCount++
                }
                Assert-Condition $pixelPassed "Target pixel validation failed at frame $frameIndex."
                $changedFrameCount++
            }

            $frameRecords.Add([pscustomobject]@{
                frameIndex = $frameIndex
                disposition = if ($placeholder) { 'preserved-transparent-placeholder' } else { 'authorized-color-change' }
                metadata = 'identical'
                fourCc = $expectedFourCc
                ddsBytes = [int]$outputDds.Length
                changedBc3ColorBlocks = if ($placeholder) { 0 } else { [int]$bc3Result.ChangedColorBlockCount }
                alphaMismatchPixels = [long]$pixelResult.AlphaMismatchPixels
                changedVisibleRgbPixels = [long]$pixelResult.ChangedVisibleRgbPixels
                outputVisiblePixels = [long]$pixelResult.OutputVisiblePixels
                outputNonBlackVisiblePixels = [long]$pixelResult.OutputNonBlackVisiblePixels
                status = 'passed'
            })
        }
        finally {
            if ($null -ne $sourcePicture) {
                $sourcePicture.Dispose()
                $sourceSprite.Picture = $null
            }
            if ($null -ne $outputPicture) {
                $outputPicture.Dispose()
                $outputSprite.Picture = $null
            }
            $sourcePixels = $null
            $outputPixels = $null
            $sourceDds = $null
            $outputDds = $null
            [GC]::Collect()
            [GC]::WaitForPendingFinalizers()
        }
    }

    Assert-Condition ($metadataDiffCount -eq 0) 'Target metadata differences were found.'
    Assert-Condition ($changedFrameCount -eq 24) "Changed target frame count changed: $changedFrameCount/24"
    Assert-Condition ($preservedPlaceholderCount -eq 3) `
        "Preserved placeholder count changed: $preservedPlaceholderCount/3"
    Assert-Condition ($alphaMismatchPixelCount -eq 0 -and $bc3AlphaBlockMismatchCount -eq 0) `
        'Target alpha data changed.'
    Assert-Condition ($targetPixelFailureCount -eq 0) 'Target pixel failures were found.'

    $sourceItem = Get-Item -LiteralPath $sourcePath
    $outputItem = Get-Item -LiteralPath $outputPath
    $result = [ordered]@{
        schemaVersion = 1
        generatedAt = (Get-Date).ToString('o')
        status = 'passed'
        mode = 'read-only independent Cut-in source/output validation; no build or deployment'
        sourceNpk = [ordered]@{
            path = $sourcePath
            length = [long]$sourceItem.Length
            sha256 = [string]$sourceInventory.sha256
        }
        outputNpk = [ordered]@{
            path = $outputPath
            length = [long]$outputItem.Length
            sha256 = [string]$outputInventory.sha256
        }
        npk = [ordered]@{
            entryCount = $expectedEntryCount
            uniquePathCount = $expectedEntryCount
            pathOrderPreserved = $true
            nonTargetPayloadsByteIdentical = $nonTargetIdentical
            targetPayloadChanged = $targetPayloadChanged
        }
        albums = [ordered]@{
            sourceCount = $sourceAlbums.Count
            outputCount = $outputAlbums.Count
            sourceFrameCount = $sourcePackageFrames
            outputFrameCount = $outputPackageFrames
        }
        target = [ordered]@{
            imgPath = $targetImg
            version = 'Ver5'
            frameCount = 27
            changedFrames = @(3..26)
            preservedTransparentFrames = @(0..2)
            frames = $frameRecords.ToArray()
        }
        validation = [ordered]@{
            status = 'passed'
            metadataDiffCount = $metadataDiffCount
            changedFrameCount = $changedFrameCount
            preservedPlaceholderCount = $preservedPlaceholderCount
            nonTargetPayloadHashMismatchCount = 0
            alphaMismatchPixelCount = $alphaMismatchPixelCount
            bc3AlphaBlockMismatchCount = $bc3AlphaBlockMismatchCount
            changedBc3ColorBlocks = $totalChangedColorBlocks
            targetPixelFailureCount = $targetPixelFailureCount
            ddsHeaderValidatedFrames = 27
            decodedTargetFrames = 27
        }
        parser = [ordered]@{
            npk = 'PowerShell/.NET raw index and streaming payload SHA-256'
            img = 'ExtractorSharp 1.7.3.2 loaded through 32-bit PowerShell'
        }
        deployment = [ordered]@{
            authorized = $false
            performed = $false
            imagePacks2Write = $false
            processOperation = $false
            status = 'not-authorized-not-performed'
        }
    }

    $reportDirectory = Split-Path -Parent $reportPath
    New-Item -ItemType Directory -Path $reportDirectory -Force | Out-Null
    $temporaryReport = $reportPath + '.tmp-' + [Guid]::NewGuid().ToString('N')
    try {
        $json = $result | ConvertTo-Json -Depth 12
        $json | Set-Content -LiteralPath $temporaryReport -Encoding UTF8
        $null = Get-Content -LiteralPath $temporaryReport -Raw -Encoding UTF8 | ConvertFrom-Json
        [IO.File]::Move($temporaryReport, $reportPath)
        $json
    }
    finally {
        if (Test-Path -LiteralPath $temporaryReport) {
            Remove-Item -LiteralPath $temporaryReport -Force
        }
    }
}
finally {
    Set-Location -LiteralPath $previousLocation
}
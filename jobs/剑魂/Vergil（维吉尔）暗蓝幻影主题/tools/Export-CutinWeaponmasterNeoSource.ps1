param(
    [Parameter(Mandatory = $true)]
    [string]$SourceNpk,

    [Parameter(Mandatory = $true)]
    [string]$OutputDirectory,

    [Parameter(Mandatory = $true)]
    [string]$ExpectedSourceSha256,

    [string]$ExtractorDirectory
)

$ErrorActionPreference = 'Stop'
$ProgressPreference = 'SilentlyContinue'

if ([IntPtr]::Size -ne 4) {
    throw 'Run this exporter with 32-bit PowerShell because ExtractorSharp uses x86 zlib.'
}

$imgPath = 'sprite/character/swordman/effect/cutin/cutin_weaponmaster_neo.img'
$repoRoot = [IO.Path]::GetFullPath((Join-Path $PSScriptRoot '..\..\..\..'))
Import-Module (Join-Path $repoRoot 'tools\DnfPatch.Toolchain.psm1') -Force
$extractorDirectory = Resolve-DnfExtractorDirectory -Path $ExtractorDirectory -RepositoryRoot $repoRoot
$sourcePath = (Resolve-Path -LiteralPath $SourceNpk).Path
$outputPath = [IO.Path]::GetFullPath($OutputDirectory)
$outputParent = Split-Path -Parent $outputPath
$coreDll = Join-Path $extractorDirectory 'ExtractorSharp.Core.dll'
$jsonDll = Join-Path $extractorDirectory 'ExtractorSharp.Json.dll'

if (Test-Path -LiteralPath $outputPath) {
    throw "Refusing to overwrite existing output: $outputPath"
}

$sourceItem = Get-Item -LiteralPath $sourcePath
$sourceLength = $sourceItem.Length
$sourceMtime = $sourceItem.LastWriteTime.ToString('o')
$sourceSha = (Get-FileHash -LiteralPath $sourcePath -Algorithm SHA256).Hash
if ($sourceSha -ne $ExpectedSourceSha256.ToUpperInvariant()) {
    throw "Source SHA-256 mismatch. Expected $ExpectedSourceSha256, found $sourceSha."
}

New-Item -ItemType Directory -Path $outputParent -Force | Out-Null
$stagingPath = Join-Path $outputParent (
    '.' + [IO.Path]::GetFileName($outputPath) + '.staging-' + [Guid]::NewGuid().ToString('N'))
New-Item -ItemType Directory -Path $stagingPath | Out-Null

$previousLocation = Get-Location
try {
    Set-Location -LiteralPath $extractorDirectory
    [void][Reflection.Assembly]::LoadFrom($jsonDll)
    [void][Reflection.Assembly]::LoadFrom($coreDll)
    [void][Reflection.Assembly]::LoadWithPartialName('System.Drawing')

    $albums = [ExtractorSharp.Core.Coder.NpkCoder]::Load($sourcePath)
    $matches = @($albums | Where-Object { $_.Path -eq $imgPath })
    if ($matches.Count -ne 1) {
        throw "Expected exactly one IMG '$imgPath', found $($matches.Count)."
    }
    $album = $matches[0]
    if ($album.Version.ToString() -ne 'Ver5' -or $album.List.Count -ne 27) {
        throw "Expected Ver5 with 27 frames, found $($album.Version) with $($album.List.Count)."
    }

    $mapField = $album.Handler.GetType().GetField(
        '_map',
        [Reflection.BindingFlags]'Instance,NonPublic')
    if ($null -eq $mapField) {
        throw 'Ver5 texture map is unavailable.'
    }
    $textureMap = $mapField.GetValue($album.Handler)

    $textureFrameGroups = @{}
    foreach ($sprite in $album.List) {
        if (-not $textureMap.ContainsKey($sprite.Index)) {
            throw "Missing texture map for frame $($sprite.Index)."
        }
        $textureIndex = [int]$textureMap[$sprite.Index].Texture.Index
        if (-not $textureFrameGroups.ContainsKey($textureIndex)) {
            $textureFrameGroups[$textureIndex] = New-Object Collections.Generic.List[int]
        }
        $textureFrameGroups[$textureIndex].Add([int]$sprite.Index)
    }

    $frameRecords = New-Object Collections.Generic.List[object]
    foreach ($sprite in $album.List) {
        $picture = $null
        try {
            if ($sprite.Type.ToString() -eq 'LINK') {
                throw "Unexpected LINK frame at index $($sprite.Index)."
            }
            $picture = $sprite.Picture
            if ($null -eq $picture) {
                throw "Undecodable frame at index $($sprite.Index)."
            }
            if ($picture.Width -ne $sprite.Width -or $picture.Height -ne $sprite.Height) {
                throw "Decoded geometry mismatch at frame $($sprite.Index)."
            }

            $pixels = [ExtractorSharp.Core.Lib.Bitmaps]::ToArray($picture)
            $totalPixels = [long]($pixels.Length / 4)
            $transparentPixels = 0L
            $alphaPixels = 0L
            $opaquePixels = 0L
            $partialAlphaPixels = 0L
            $nonBlackVisiblePixels = 0L
            for ($pixel = 0; $pixel -lt $pixels.Length; $pixel += 4) {
                $alpha = $pixels[$pixel + 3]
                if ($alpha -eq 0) {
                    $transparentPixels++
                    continue
                }
                $alphaPixels++
                if ($alpha -eq 255) {
                    $opaquePixels++
                }
                else {
                    $partialAlphaPixels++
                }
                if ($pixels[$pixel] -ne 0 -or
                    $pixels[$pixel + 1] -ne 0 -or
                    $pixels[$pixel + 2] -ne 0) {
                    $nonBlackVisiblePixels++
                }
            }

            $pngName = 'frame-{0:D3}.png' -f [int]$sprite.Index
            $pngPath = Join-Path $stagingPath $pngName
            if (Test-Path -LiteralPath $pngPath) {
                throw "Refusing to overwrite frame output: $pngPath"
            }
            $picture.Save($pngPath, [Drawing.Imaging.ImageFormat]::Png)
            $pngItem = Get-Item -LiteralPath $pngPath

            $textureInfo = $textureMap[$sprite.Index]
            $texture = $textureInfo.Texture
            if ($sprite.CompressMode.ToString() -ne 'DDS_ZLIB') {
                throw "Unexpected compression at frame $($sprite.Index): $($sprite.CompressMode)"
            }
            $dds = [ExtractorSharp.Core.Lib.Zlib]::Decompress(
                $texture.Data,
                $texture.FullLength)
            $ddsMagic = [Text.Encoding]::ASCII.GetString($dds, 0, 4)
            $ddsFourCC = [Text.Encoding]::ASCII.GetString($dds, 84, 4)
            $ddsWidth = [BitConverter]::ToInt32($dds, 16)
            $ddsHeight = [BitConverter]::ToInt32($dds, 12)
            $blockBytes = if ($ddsFourCC -eq 'DXT1') {
                8
            }
            elseif ($ddsFourCC -in @('DXT3', 'DXT5')) {
                16
            }
            else {
                0
            }
            $expectedDdsLength = if ($blockBytes -gt 0) {
                128 + [int](
                    [Math]::Ceiling($ddsWidth / 4.0) *
                    [Math]::Ceiling($ddsHeight / 4.0) *
                    $blockBytes)
            }
            else {
                -1
            }
            if ($ddsMagic -ne 'DDS ' -or
                $ddsWidth -ne $texture.Width -or
                $ddsHeight -ne $texture.Height -or
                $dds.Length -ne $expectedDdsLength) {
                throw "Invalid DDS payload at frame $($sprite.Index)."
            }

            $ddsSha = [Security.Cryptography.SHA256]::Create()
            try {
                $ddsHash = [BitConverter]::ToString($ddsSha.ComputeHash($dds)).Replace('-', '')
            }
            finally {
                $ddsSha.Dispose()
            }

            $sharedFrames = @($textureFrameGroups[[int]$texture.Index] | Sort-Object)
            $frameRecords.Add([ordered]@{
                frameIndex = [int]$sprite.Index
                png = $pngName
                pngBytes = [long]$pngItem.Length
                pngSha256 = (Get-FileHash -LiteralPath $pngPath -Algorithm SHA256).Hash
                imgVersion = $album.Version.ToString()
                width = [int]$sprite.Width
                height = [int]$sprite.Height
                canvasWidth = [int]$sprite.CanvasWidth
                canvasHeight = [int]$sprite.CanvasHeight
                x = [int]$sprite.X
                y = [int]$sprite.Y
                hidden = [bool]$sprite.Hidden
                type = $sprite.Type.ToString()
                compressMode = $sprite.CompressMode.ToString()
                textureType = $texture.Type.ToString()
                textureVersion = $texture.Version.ToString()
                textureIndex = [int]$texture.Index
                textureWidth = [int]$texture.Width
                textureHeight = [int]$texture.Height
                textureReferenceGroup = ('texture-{0:D3}' -f [int]$texture.Index)
                sharedTexture = $sharedFrames.Count -gt 1
                sharedWithFrameIndexes = $sharedFrames
                atlasLeft = [int]$textureInfo.LeftUp.X
                atlasTop = [int]$textureInfo.LeftUp.Y
                atlasRight = [int]$textureInfo.RightDown.X
                atlasBottom = [int]$textureInfo.RightDown.Y
                rotation = [int]$textureInfo.Top
                unknown = [int]$textureInfo.Unknown
                ddsMagic = $ddsMagic
                ddsFourCC = $ddsFourCC
                ddsBytes = [int]$dds.Length
                expectedDdsBytes = [int]$expectedDdsLength
                ddsSha256 = $ddsHash
                totalPixels = $totalPixels
                transparentPixels = $transparentPixels
                alphaPixels = $alphaPixels
                opaquePixels = $opaquePixels
                partialAlphaPixels = $partialAlphaPixels
                nonBlackVisiblePixels = $nonBlackVisiblePixels
                fullyTransparent = $alphaPixels -eq 0
                allVisiblePixelsBlack = $alphaPixels -gt 0 -and $nonBlackVisiblePixels -eq 0
            })
        }
        finally {
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

    $panelWidth = 170
    $panelHeight = 96
    $panelGap = 6
    $labelHeight = 42
    $tileWidth = $panelGap * 4 + $panelWidth * 3
    $tileHeight = $panelHeight + $labelHeight + 12
    $columns = 3
    $rows = [int][Math]::Ceiling($frameRecords.Count / [double]$columns)
    $sheet = New-Object Drawing.Bitmap ($tileWidth * $columns), ($tileHeight * $rows)
    $graphics = [Drawing.Graphics]::FromImage($sheet)
    $font = New-Object Drawing.Font 'Consolas', 8
    $smallFont = New-Object Drawing.Font 'Consolas', 7
    $whiteBrush = New-Object Drawing.SolidBrush ([Drawing.Color]::White)
    $blackBrush = New-Object Drawing.SolidBrush ([Drawing.Color]::Black)
    $checkerLightBrush = New-Object Drawing.SolidBrush ([Drawing.Color]::FromArgb(195, 195, 195))
    $checkerDarkBrush = New-Object Drawing.SolidBrush ([Drawing.Color]::FromArgb(105, 105, 105))
    $tileBrush = New-Object Drawing.SolidBrush ([Drawing.Color]::FromArgb(28, 30, 34))
    $borderPen = New-Object Drawing.Pen ([Drawing.Color]::FromArgb(85, 90, 100))
    try {
        $graphics.Clear([Drawing.Color]::FromArgb(18, 20, 24))
        $graphics.InterpolationMode = [Drawing.Drawing2D.InterpolationMode]::HighQualityBicubic
        $graphics.PixelOffsetMode = [Drawing.Drawing2D.PixelOffsetMode]::HighQuality
        for ($index = 0; $index -lt $frameRecords.Count; $index++) {
            $record = $frameRecords[$index]
            $column = $index % $columns
            $row = [int][Math]::Floor($index / [double]$columns)
            $tileX = $column * $tileWidth
            $tileY = $row * $tileHeight
            $graphics.FillRectangle($tileBrush, $tileX, $tileY, $tileWidth - 1, $tileHeight - 1)
            $graphics.DrawRectangle($borderPen, $tileX, $tileY, $tileWidth - 1, $tileHeight - 1)

            $frameImage = [Drawing.Image]::FromFile((Join-Path $stagingPath $record.png))
            try {
                for ($panel = 0; $panel -lt 3; $panel++) {
                    $panelX = $tileX + $panelGap + $panel * ($panelWidth + $panelGap)
                    $panelY = $tileY + $panelGap
                    if ($panel -eq 0) {
                        $graphics.FillRectangle($blackBrush, $panelX, $panelY, $panelWidth, $panelHeight)
                    }
                    elseif ($panel -eq 1) {
                        $graphics.FillRectangle($whiteBrush, $panelX, $panelY, $panelWidth, $panelHeight)
                    }
                    else {
                        for ($checkerY = 0; $checkerY -lt $panelHeight; $checkerY += 8) {
                            for ($checkerX = 0; $checkerX -lt $panelWidth; $checkerX += 8) {
                                $checkerBrush = if (((($checkerX / 8) + ($checkerY / 8)) % 2) -eq 0) {
                                    $checkerLightBrush
                                }
                                else {
                                    $checkerDarkBrush
                                }
                                $graphics.FillRectangle(
                                    $checkerBrush,
                                    $panelX + $checkerX,
                                    $panelY + $checkerY,
                                    [Math]::Min(8, $panelWidth - $checkerX),
                                    [Math]::Min(8, $panelHeight - $checkerY))
                            }
                        }
                    }

                    $scale = [Math]::Min(
                        ($panelWidth - 4.0) / [Math]::Max(1, $frameImage.Width),
                        ($panelHeight - 4.0) / [Math]::Max(1, $frameImage.Height))
                    $drawWidth = [Math]::Max(1, [int]($frameImage.Width * $scale))
                    $drawHeight = [Math]::Max(1, [int]($frameImage.Height * $scale))
                    $drawX = $panelX + [int](($panelWidth - $drawWidth) / 2)
                    $drawY = $panelY + [int](($panelHeight - $drawHeight) / 2)
                    $graphics.DrawImage($frameImage, $drawX, $drawY, $drawWidth, $drawHeight)
                    $graphics.DrawRectangle($borderPen, $panelX, $panelY, $panelWidth, $panelHeight)
                }
            }
            finally {
                $frameImage.Dispose()
            }

            $status = if ($record.fullyTransparent) { 'TRANSPARENT' } else { 'VISIBLE' }
            $label1 = '#{0:D2} {1} {2}x{3} canvas={4}x{5} xy={6},{7}' -f
                $record.frameIndex, $status, $record.width, $record.height,
                $record.canvasWidth, $record.canvasHeight, $record.x, $record.y
            $label2 = '{0}/{1} tex={2} share=[{3}]' -f
                $record.type, $record.compressMode, $record.textureIndex,
                ($record.sharedWithFrameIndexes -join ',')
            $graphics.DrawString($label1, $font, $whiteBrush, $tileX + $panelGap, $tileY + $panelHeight + 10)
            $graphics.DrawString($label2, $smallFont, $whiteBrush, $tileX + $panelGap, $tileY + $panelHeight + 26)
        }

        $contactPath = Join-Path $stagingPath 'contact-sheet-black-white-checker.png'
        $sheet.Save($contactPath, [Drawing.Imaging.ImageFormat]::Png)
    }
    finally {
        $graphics.Dispose()
        $sheet.Dispose()
        foreach ($disposable in @(
            $font,
            $smallFont,
            $whiteBrush,
            $blackBrush,
            $checkerLightBrush,
            $checkerDarkBrush,
            $tileBrush,
            $borderPen)) {
            $disposable.Dispose()
        }
    }

    $contactItem = Get-Item -LiteralPath (Join-Path $stagingPath 'contact-sheet-black-white-checker.png')
    $relativeOutput = if ($outputPath.StartsWith($repoRoot, [StringComparison]::OrdinalIgnoreCase)) {
        $outputPath.Substring($repoRoot.Length).TrimStart('\').Replace('\', '/')
    }
    else {
        $outputPath
    }
    $inventory = [ordered]@{
        schemaVersion = 1
        generatedAt = (Get-Date).ToString('o')
        mode = 'read-only source evidence export'
        sourceNpk = [ordered]@{
            path = $sourcePath
            length = [long]$sourceLength
            lastWriteTime = $sourceMtime
            sha256 = $sourceSha
        }
        img = [ordered]@{
            path = $album.Path
            version = $album.Version.ToString()
            frameCount = [int]$album.List.Count
            decodedNonLinkFrames = [int]$frameRecords.Count
            linkFrames = 0
            hiddenFrames = 0
            transparentPlaceholderFrames = @(0, 1, 2)
            visibleFrames = @(3..26)
        }
        export = [ordered]@{
            relativeDirectory = $relativeOutput
            framePngCount = [int]$frameRecords.Count
            contactSheet = 'contact-sheet-black-white-checker.png'
            contactSheetBytes = [long]$contactItem.Length
            contactSheetSha256 = (Get-FileHash -LiteralPath $contactItem.FullName -Algorithm SHA256).Hash
            backgrounds = @('black', 'white', 'checkerboard')
        }
        frames = $frameRecords
    }
    $inventoryPath = Join-Path $stagingPath 'frame-inventory.json'
    $inventory | ConvertTo-Json -Depth 10 | Set-Content -LiteralPath $inventoryPath -Encoding UTF8
    $null = Get-Content -Raw -Encoding UTF8 -LiteralPath $inventoryPath | ConvertFrom-Json

    $framePngs = @(Get-ChildItem -LiteralPath $stagingPath -File -Filter 'frame-*.png')
    if ($framePngs.Count -ne 27) {
        throw "Expected 27 frame PNG files, found $($framePngs.Count)."
    }
    if (Test-Path -LiteralPath $outputPath) {
        throw "Output appeared during export; refusing to overwrite: $outputPath"
    }
    Move-Item -LiteralPath $stagingPath -Destination $outputPath

    $sourceItemAfter = Get-Item -LiteralPath $sourcePath
    $sourceShaAfter = (Get-FileHash -LiteralPath $sourcePath -Algorithm SHA256).Hash
    if ($sourceShaAfter -ne $sourceSha -or
        $sourceItemAfter.Length -ne $sourceLength -or
        $sourceItemAfter.LastWriteTime.ToString('o') -ne $sourceMtime) {
        throw 'Source NPK changed during export.'
    }

    $resultFiles = @(Get-ChildItem -LiteralPath $outputPath -File)
    [pscustomobject]@{
        OutputDirectory = $outputPath
        FramePngCount = @($resultFiles | Where-Object { $_.Name -like 'frame-*.png' }).Count
        TotalFileCount = $resultFiles.Count
        InventorySha256 = (Get-FileHash -LiteralPath (Join-Path $outputPath 'frame-inventory.json') -Algorithm SHA256).Hash
        ContactSheetSha256 = (Get-FileHash -LiteralPath (Join-Path $outputPath 'contact-sheet-black-white-checker.png') -Algorithm SHA256).Hash
        SourceSha256Before = $sourceSha
        SourceSha256After = $sourceShaAfter
        SourceUnchanged = $sourceSha -eq $sourceShaAfter
    } | Format-List
}
finally {
    Set-Location -LiteralPath $previousLocation
}

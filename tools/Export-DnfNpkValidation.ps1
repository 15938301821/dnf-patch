param(
    [Parameter(Mandatory = $true)]
    [string]$InputFile,

    [Parameter(Mandatory = $true)]
    [string]$OutputDirectory,

    [string]$ExtractorDirectory,

    [ValidateRange(16, 512)]
    [int]$FramesPerPage = 256
)

$ErrorActionPreference = 'Stop'

$repoRoot = Split-Path -Parent $PSScriptRoot
Import-Module (Join-Path $PSScriptRoot 'DnfPatch.Toolchain.psm1') -Force
$ExtractorDirectory = Resolve-DnfExtractorDirectory -Path $ExtractorDirectory -RepositoryRoot $repoRoot
$inputPath = (Resolve-Path -LiteralPath $InputFile).Path
$outputPath = [IO.Path]::GetFullPath($OutputDirectory)
$coreDll = Join-Path $ExtractorDirectory 'ExtractorSharp.Core.dll'
$jsonDll = Join-Path $ExtractorDirectory 'ExtractorSharp.Json.dll'

foreach ($dependency in @($coreDll, $jsonDll)) {
    if (-not (Test-Path -LiteralPath $dependency -PathType Leaf)) {
        throw "Missing ExtractorSharp dependency: $dependency"
    }
}

New-Item -ItemType Directory -Path $outputPath -Force | Out-Null
$sheetsPath = Join-Path $outputPath 'sheets'
New-Item -ItemType Directory -Path $sheetsPath -Force | Out-Null

$previousLocation = Get-Location
try {
    Set-Location -LiteralPath $ExtractorDirectory
    [void][Reflection.Assembly]::LoadFrom($jsonDll)
    [void][Reflection.Assembly]::LoadFrom($coreDll)
    [void][Reflection.Assembly]::LoadWithPartialName('System.Drawing')

    $albums = [ExtractorSharp.Core.Coder.NpkCoder]::Load($inputPath)
    $frames = New-Object 'Collections.Generic.List[object]'
    foreach ($album in $albums) {
        foreach ($sprite in $album.List) {
            $frames.Add([PSCustomObject]@{ Album = $album; Sprite = $sprite })
        }
    }

    $tileWidth = 192
    $tileHeight = 150
    $columns = 12
    $rowsPerPage = [int][Math]::Ceiling($FramesPerPage / [double]$columns)
    $sheetWidth = $tileWidth * $columns
    $sheetHeight = $tileHeight * $rowsPerPage
    $panelWidth = 58
    $panelHeight = 96
    $panelGap = 3
    $panelStartX = 6
    $panelStartY = 5

    $font = New-Object Drawing.Font 'Consolas', 7
    $smallFont = New-Object Drawing.Font 'Consolas', 6
    $whiteBrush = New-Object Drawing.SolidBrush ([Drawing.Color]::White)
    $blackBrush = New-Object Drawing.SolidBrush ([Drawing.Color]::Black)
    $grayBrush = New-Object Drawing.SolidBrush ([Drawing.Color]::FromArgb(42, 45, 50))
    $lightGrayBrush = New-Object Drawing.SolidBrush ([Drawing.Color]::FromArgb(205, 205, 205))
    $checkerBrush = New-Object Drawing.SolidBrush ([Drawing.Color]::FromArgb(105, 105, 105))
    $borderPen = New-Object Drawing.Pen ([Drawing.Color]::FromArgb(95, 100, 110))
    $linkPen = New-Object Drawing.Pen ([Drawing.Color]::FromArgb(255, 190, 70)), 2
    $hiddenPen = New-Object Drawing.Pen ([Drawing.Color]::FromArgb(120, 170, 220)), 2

    $frameRecords = New-Object 'Collections.Generic.List[object]'
    $albumRecords = New-Object 'Collections.Generic.List[object]'
    $decodedFrames = 0
    $linkFrames = 0
    $hiddenFrames = 0
    $pageCount = [int][Math]::Ceiling($frames.Count / [double]$FramesPerPage)

    for ($pageIndex = 0; $pageIndex -lt $pageCount; $pageIndex++) {
        $sheet = New-Object Drawing.Bitmap $sheetWidth, $sheetHeight
        $graphics = [Drawing.Graphics]::FromImage($sheet)
        try {
            $graphics.Clear([Drawing.Color]::FromArgb(25, 27, 31))
            $graphics.InterpolationMode = [Drawing.Drawing2D.InterpolationMode]::HighQualityBicubic
            $graphics.PixelOffsetMode = [Drawing.Drawing2D.PixelOffsetMode]::HighQuality

            $pageStart = $pageIndex * $FramesPerPage
            $pageEnd = [Math]::Min($pageStart + $FramesPerPage, $frames.Count)
            for ($globalIndex = $pageStart; $globalIndex -lt $pageEnd; $globalIndex++) {
                $pageFrameIndex = $globalIndex - $pageStart
                $column = $pageFrameIndex % $columns
                $row = [int][Math]::Floor($pageFrameIndex / [double]$columns)
                $tileX = $column * $tileWidth
                $tileY = $row * $tileHeight
                $album = $frames[$globalIndex].Album
                $sprite = $frames[$globalIndex].Sprite

                $graphics.FillRectangle($grayBrush, $tileX, $tileY, $tileWidth - 1, $tileHeight - 1)
                $graphics.DrawRectangle($borderPen, $tileX, $tileY, $tileWidth - 1, $tileHeight - 1)

                $textureType = $null
                $textureVersion = $null
                $textureIndex = $null
                $textureWidth = $null
                $textureHeight = $null
                $atlasLeft = $null
                $atlasTop = $null
                $atlasRight = $null
                $atlasBottom = $null
                $rotation = $null
                $mapField = $album.Handler.GetType().GetField(
                    '_map',
                    [Reflection.BindingFlags]'Instance,NonPublic')
                if ($null -ne $mapField) {
                    $textureMap = $mapField.GetValue($album.Handler)
                    if ($null -ne $textureMap -and $textureMap.ContainsKey($sprite.Index)) {
                        $textureInfo = $textureMap[$sprite.Index]
                        if ($null -ne $textureInfo -and $null -ne $textureInfo.Texture) {
                            $textureType = $textureInfo.Texture.Type.ToString()
                            $textureVersion = $textureInfo.Texture.Version.ToString()
                            $textureIndex = $textureInfo.Texture.Index
                            $textureWidth = $textureInfo.Texture.Width
                            $textureHeight = $textureInfo.Texture.Height
                            $atlasLeft = $textureInfo.LeftUp.X
                            $atlasTop = $textureInfo.LeftUp.Y
                            $atlasRight = $textureInfo.RightDown.X
                            $atlasBottom = $textureInfo.RightDown.Y
                            $rotation = $textureInfo.Top
                        }
                    }
                }

                $targetIndex = $null
                $status = 'VISIBLE'
                if ($sprite.Type.ToString() -eq 'LINK') {
                    $linkFrames++
                    $status = 'LINK'
                    if ($null -eq $sprite.Target) {
                        throw "LINK has no target: $($album.Path)#$($sprite.Index)"
                    }
                    $targetIndex = $sprite.Target.Index
                    if ($targetIndex -lt 0 -or $targetIndex -ge $album.List.Count -or
                        -not [object]::ReferenceEquals($album.List[$targetIndex], $sprite.Target) -or
                        $sprite.Target.Type.ToString() -eq 'LINK') {
                        throw "Invalid LINK target: $($album.Path)#$($sprite.Index) -> $targetIndex"
                    }
                    $graphics.DrawRectangle($linkPen, $tileX + 2, $tileY + 2, $tileWidth - 5, $tileHeight - 5)
                    $graphics.DrawString("LINK -> $targetIndex", $font, $whiteBrush, $tileX + 16, $tileY + 45)
                }
                else {
                    $picture = $null
                    try {
                        $picture = $sprite.Picture
                        if ($null -eq $picture) {
                            throw "Undecodable frame: $($album.Path)#$($sprite.Index)"
                        }
                        $decodedFrames++
                        if ($sprite.Hidden) {
                            $hiddenFrames++
                            $status = 'HIDDEN'
                            $graphics.DrawRectangle($hiddenPen, $tileX + 2, $tileY + 2, $tileWidth - 5, $tileHeight - 5)
                        }

                        for ($panel = 0; $panel -lt 3; $panel++) {
                            $panelX = $tileX + $panelStartX + $panel * ($panelWidth + $panelGap)
                            $panelY = $tileY + $panelStartY
                            if ($panel -eq 0) {
                                $graphics.FillRectangle($blackBrush, $panelX, $panelY, $panelWidth, $panelHeight)
                            }
                            elseif ($panel -eq 1) {
                                $graphics.FillRectangle($whiteBrush, $panelX, $panelY, $panelWidth, $panelHeight)
                            }
                            else {
                                $graphics.FillRectangle($lightGrayBrush, $panelX, $panelY, $panelWidth, $panelHeight)
                                for ($checkerY = 0; $checkerY -lt $panelHeight; $checkerY += 8) {
                                    for ($checkerX = 0; $checkerX -lt $panelWidth; $checkerX += 8) {
                                        if ((($checkerX / 8) + ($checkerY / 8)) % 2 -eq 0) {
                                            $graphics.FillRectangle(
                                                $checkerBrush,
                                                $panelX + $checkerX,
                                                $panelY + $checkerY,
                                                [Math]::Min(8, $panelWidth - $checkerX),
                                                [Math]::Min(8, $panelHeight - $checkerY))
                                        }
                                    }
                                }
                            }

                            $scale = [Math]::Min(
                                ($panelWidth - 4.0) / [Math]::Max(1, $picture.Width),
                                ($panelHeight - 4.0) / [Math]::Max(1, $picture.Height))
                            $drawWidth = [Math]::Max(1, [int]($picture.Width * $scale))
                            $drawHeight = [Math]::Max(1, [int]($picture.Height * $scale))
                            $drawX = $panelX + [int](($panelWidth - $drawWidth) / 2)
                            $drawY = $panelY + [int](($panelHeight - $drawHeight) / 2)
                            $graphics.DrawImage($picture, $drawX, $drawY, $drawWidth, $drawHeight)
                            $graphics.DrawRectangle($borderPen, $panelX, $panelY, $panelWidth, $panelHeight)
                        }
                    }
                    finally {
                        if ($null -ne $picture) {
                            $picture.Dispose()
                            $sprite.Picture = $null
                        }
                    }
                }

                $albumLabel = [IO.Path]::GetFileNameWithoutExtension($album.Path)
                if ($albumLabel.Length -gt 22) {
                    $albumLabel = $albumLabel.Substring(0, 22)
                }
                $label = "$albumLabel#$($sprite.Index) $status`n$($sprite.Type) $($sprite.Width)x$($sprite.Height)"
                $graphics.DrawString($label, $smallFont, $whiteBrush, $tileX + 5, $tileY + 106)

                $frameRecords.Add([PSCustomObject]@{
                    GlobalIndex = $globalIndex
                    Sheet = ('frames-{0:D4}.png' -f ($pageIndex + 1))
                    Tile = $pageFrameIndex
                    ImgPath = $album.Path
                    ImgVersion = $album.Version.ToString()
                    FrameIndex = $sprite.Index
                    Type = $sprite.Type.ToString()
                    CompressMode = $sprite.CompressMode.ToString()
                    Hidden = $sprite.Hidden
                    LinkTargetIndex = $targetIndex
                    Width = $sprite.Width
                    Height = $sprite.Height
                    CanvasWidth = $sprite.CanvasWidth
                    CanvasHeight = $sprite.CanvasHeight
                    X = $sprite.X
                    Y = $sprite.Y
                    TextureType = $textureType
                    TextureVersion = $textureVersion
                    TextureIndex = $textureIndex
                    TextureWidth = $textureWidth
                    TextureHeight = $textureHeight
                    AtlasLeft = $atlasLeft
                    AtlasTop = $atlasTop
                    AtlasRight = $atlasRight
                    AtlasBottom = $atlasBottom
                    Rotation = $rotation
                })
            }

            $sheetFile = Join-Path $sheetsPath ('frames-{0:D4}.png' -f ($pageIndex + 1))
            $sheet.Save($sheetFile, [Drawing.Imaging.ImageFormat]::Png)
            Write-Output "CreatedSheet=$sheetFile"
        }
        finally {
            $graphics.Dispose()
            $sheet.Dispose()
            [GC]::Collect()
            [GC]::WaitForPendingFinalizers()
        }
    }

    foreach ($album in $albums) {
        $albumRecords.Add([PSCustomObject]@{
            Path = $album.Path
            Version = $album.Version.ToString()
            FrameCount = $album.List.Count
            LinkCount = @($album.List | Where-Object { $_.Type.ToString() -eq 'LINK' }).Count
            HiddenCount = @($album.List | Where-Object { $_.Hidden }).Count
        })
    }

    $frameInventoryFile = Join-Path $outputPath 'frame-inventory.csv'
    $frameRecords | Export-Csv -LiteralPath $frameInventoryFile -NoTypeInformation -Encoding UTF8

    $albumInventoryFile = Join-Path $outputPath 'album-inventory.json'
    $albumInventory = [PSCustomObject]@{
        InputFile = $inputPath
        InputSha256 = (Get-FileHash -LiteralPath $inputPath -Algorithm SHA256).Hash
        AlbumCount = $albums.Count
        FrameCount = $frames.Count
        DecodedNonLinkFrames = $decodedFrames
        LinkFrames = $linkFrames
        HiddenFrames = $hiddenFrames
        SheetCount = $pageCount
        FramesPerPage = $FramesPerPage
        Backgrounds = @('black', 'white', 'checkerboard')
        Albums = $albumRecords
    }
    $albumInventory | ConvertTo-Json -Depth 5 | Set-Content -LiteralPath $albumInventoryFile -Encoding UTF8

    [PSCustomObject]@{
        InputFile = $inputPath
        AlbumCount = $albums.Count
        FrameCount = $frames.Count
        DecodedNonLinkFrames = $decodedFrames
        LinkFrames = $linkFrames
        HiddenFrames = $hiddenFrames
        SheetCount = $pageCount
        FrameInventory = $frameInventoryFile
        AlbumInventory = $albumInventoryFile
    } | Format-List
}
finally {
    foreach ($disposable in @(
        $font,
        $smallFont,
        $whiteBrush,
        $blackBrush,
        $grayBrush,
        $lightGrayBrush,
        $checkerBrush,
        $borderPen,
        $linkPen,
        $hiddenPen)) {
        if ($null -ne $disposable) {
            $disposable.Dispose()
        }
    }
    Set-Location -LiteralPath $previousLocation
}

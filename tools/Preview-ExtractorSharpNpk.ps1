param(
    [Parameter(Mandatory = $true)]
    [string[]]$InputFiles,

    [Parameter(Mandatory = $true)]
    [string]$OutputFile,

    [int]$MaxTiles = 60,

    [string]$PathPattern = '.*',

    [string]$ExtractorDirectory
)

$repoRoot = Split-Path -Parent $PSScriptRoot
Import-Module (Join-Path $PSScriptRoot 'DnfPatch.Toolchain.psm1') -Force
$extractorDir = Resolve-DnfExtractorDirectory -Path $ExtractorDirectory -RepositoryRoot $repoRoot
$previousLocation = Get-Location
Set-Location -LiteralPath $extractorDir
[void][Reflection.Assembly]::LoadFrom((Join-Path $extractorDir 'ExtractorSharp.Json.dll'))
[void][Reflection.Assembly]::LoadFrom((Join-Path $extractorDir 'ExtractorSharp.Core.dll'))
[void][Reflection.Assembly]::LoadWithPartialName('System.Drawing')

$tiles = New-Object 'System.Collections.Generic.List[object]'
foreach ($file in $InputFiles) {
    $albums = [ExtractorSharp.Core.Coder.NpkCoder]::Load($file)
    foreach ($album in $albums) {
        if ($album.Path -notmatch $PathPattern) {
            continue
        }
        $sprite = $album.List |
            Where-Object { $_.Type.ToString() -ne 'LINK' -and -not $_.Hidden } |
            Sort-Object { $_.Width * $_.Height } -Descending |
            Select-Object -First 1
        if ($null -ne $sprite -and $null -ne $sprite.Picture) {
            $tiles.Add([pscustomobject]@{
                Label = ([IO.Path]::GetFileNameWithoutExtension($file) -replace '^sprite_character_fighter_effect_', '') + "`n" + $album.Name
                Image = [Drawing.Bitmap]$sprite.Picture.Clone()
            })
            if ($tiles.Count -ge $MaxTiles) {
                break
            }
        }
    }
    if ($tiles.Count -ge $MaxTiles) {
        break
    }
}

$tileWidth = 320
$tileHeight = 260
$columns = 3
$rows = [int][Math]::Ceiling($tiles.Count / [double]$columns)
if ($rows -lt 1) {
    throw 'No decodable sprites were found.'
}
$sheet = New-Object Drawing.Bitmap ([int]($tileWidth * $columns)), ([int]($tileHeight * $rows))
$graphics = [Drawing.Graphics]::FromImage($sheet)
$graphics.Clear([Drawing.Color]::FromArgb(26, 28, 34))
$font = New-Object Drawing.Font 'Segoe UI', 9
$brush = [Drawing.Brushes]::White

for ($i = 0; $i -lt $tiles.Count; $i++) {
    $x = ($i % $columns) * $tileWidth
    $y = [Math]::Floor($i / $columns) * $tileHeight
    $image = $tiles[$i].Image
    $scale = [Math]::Min(280.0 / $image.Width, 205.0 / $image.Height)
    $width = [Math]::Max(1, [int]($image.Width * $scale))
    $height = [Math]::Max(1, [int]($image.Height * $scale))
    $drawX = $x + [int](($tileWidth - $width) / 2)
    $drawY = $y + 4 + [int]((210 - $height) / 2)
    $graphics.DrawImage($image, $drawX, $drawY, $width, $height)
    $graphics.DrawString($tiles[$i].Label, $font, $brush, $x + 8, $y + 214)
}

$outputDir = Split-Path -Parent $OutputFile
if ($outputDir) {
    New-Item -ItemType Directory -Path $outputDir -Force | Out-Null
}
$sheet.Save($OutputFile, [Drawing.Imaging.ImageFormat]::Png)

$graphics.Dispose()
$sheet.Dispose()
$font.Dispose()
foreach ($tile in $tiles) {
    $tile.Image.Dispose()
}
Set-Location -LiteralPath $previousLocation

Write-Output "Created $OutputFile with $($tiles.Count) representative images."

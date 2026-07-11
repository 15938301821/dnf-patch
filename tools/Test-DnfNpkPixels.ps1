param(
    [Parameter(Mandatory = $true)]
    [string]$InputFile,

    [Parameter(Mandatory = $true)]
    [string]$PathPattern,

    [string]$OutputFile,

    [string]$ExtractorDirectory
)

$ErrorActionPreference = 'Stop'

if ([IntPtr]::Size -ne 4) {
    throw 'Run this validator with 32-bit PowerShell because ExtractorSharp uses x86 zlib.'
}

$repoRoot = Split-Path -Parent $PSScriptRoot
Import-Module (Join-Path $PSScriptRoot 'DnfPatch.Toolchain.psm1') -Force
$ExtractorDirectory = Resolve-DnfExtractorDirectory -Path $ExtractorDirectory -RepositoryRoot $repoRoot
$inputPath = (Resolve-Path -LiteralPath $InputFile).Path
$coreDll = Join-Path $ExtractorDirectory 'ExtractorSharp.Core.dll'
$jsonDll = Join-Path $ExtractorDirectory 'ExtractorSharp.Json.dll'
$previousLocation = Get-Location

try {
    Set-Location -LiteralPath $ExtractorDirectory
    [void][Reflection.Assembly]::LoadFrom($jsonDll)
    [void][Reflection.Assembly]::LoadFrom($coreDll)
    [void][Reflection.Assembly]::LoadWithPartialName('System.Drawing')

    $albums = [ExtractorSharp.Core.Coder.NpkCoder]::Load($inputPath) |
        Where-Object { $_.Path -match $PathPattern }
    if (@($albums).Count -eq 0) {
        throw "No IMG paths matched '$PathPattern'."
    }

    $records = New-Object 'Collections.Generic.List[object]'
    foreach ($album in $albums) {
        foreach ($sprite in $album.List) {
            if ($sprite.Type.ToString() -eq 'LINK') {
                continue
            }

            $picture = $null
            try {
                $picture = $sprite.Picture
                if ($null -eq $picture) {
                    throw "Undecodable frame: $($album.Path)#$($sprite.Index)"
                }
                $pixels = [ExtractorSharp.Core.Lib.Bitmaps]::ToArray($picture)
                $alphaPixels = 0L
                $nonBlackVisiblePixels = 0L
                $opaqueBlackPixels = 0L
                for ($pixel = 0; $pixel -lt $pixels.Length; $pixel += 4) {
                    $alpha = $pixels[$pixel + 3]
                    if ($alpha -eq 0) {
                        continue
                    }
                    $alphaPixels++
                    $blue = $pixels[$pixel]
                    $green = $pixels[$pixel + 1]
                    $red = $pixels[$pixel + 2]
                    if ($red -ne 0 -or $green -ne 0 -or $blue -ne 0) {
                        $nonBlackVisiblePixels++
                    }
                    elseif ($alpha -eq 255) {
                        $opaqueBlackPixels++
                    }
                }

                $canvasPixels = [long]$picture.Width * $picture.Height
                $record = [PSCustomObject]@{
                    ImgPath = $album.Path
                    FrameIndex = $sprite.Index
                    Width = $picture.Width
                    Height = $picture.Height
                    AlphaPixels = $alphaPixels
                    NonBlackVisiblePixels = $nonBlackVisiblePixels
                    OpaqueBlackPixels = $opaqueBlackPixels
                    FullyTransparent = $alphaPixels -eq 0
                    AllVisiblePixelsBlack = $alphaPixels -gt 0 -and $nonBlackVisiblePixels -eq 0
                    FullCanvasOpaqueBlack = $opaqueBlackPixels -eq $canvasPixels
                }
                $records.Add($record)
            }
            finally {
                if ($null -ne $picture) {
                    $picture.Dispose()
                    $sprite.Picture = $null
                }
            }
        }
    }

    $failures = @($records | Where-Object {
        $_.FullyTransparent -or $_.AllVisiblePixelsBlack -or $_.FullCanvasOpaqueBlack
    })
    $result = [PSCustomObject]@{
        InputFile = $inputPath
        InputSha256 = (Get-FileHash -LiteralPath $inputPath -Algorithm SHA256).Hash
        PathPattern = $PathPattern
        CheckedFrameCount = $records.Count
        FailureCount = $failures.Count
        Records = $records
    }
    $json = $result | ConvertTo-Json -Depth 5
    if (-not [string]::IsNullOrWhiteSpace($OutputFile)) {
        $outputPath = [IO.Path]::GetFullPath($OutputFile)
        $outputDirectory = Split-Path -Parent $outputPath
        if (-not [string]::IsNullOrWhiteSpace($outputDirectory)) {
            New-Item -ItemType Directory -Path $outputDirectory -Force | Out-Null
        }
        $json | Set-Content -LiteralPath $outputPath -Encoding UTF8
    }
    $json
    if ($failures.Count -ne 0) {
        exit 2
    }
}
finally {
    Set-Location -LiteralPath $previousLocation
}

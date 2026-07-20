[CmdletBinding()]
param(
    [ValidatePattern('^[A-Za-z0-9][A-Za-z0-9._-]*$')]
    [string]$RunId = 'cutin-weaponmaster-neo-aseprite-v1',

    [string]$SourceDirectory,

    [string]$InventoryPath,

    [string]$BodyReference,

    [string]$CinemaReference,

    [string]$EditedDirectory,

    [string]$RuntimeDirectory,

    [string]$ValidationDirectory,

    [string]$AsepritePath
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$themeRoot = Split-Path -Parent $PSScriptRoot
$professionRoot = Split-Path -Parent $themeRoot
$jobsRoot = Split-Path -Parent $professionRoot
$repoRoot = Split-Path -Parent $jobsRoot
Import-Module (Join-Path $repoRoot 'tools\DnfPatch.Toolchain.psm1') -Force

$luaPath = Join-Path $PSScriptRoot 'Render-CutinWeaponmasterNeoVergil.lua'
if ([string]::IsNullOrWhiteSpace($SourceDirectory)) {
    $SourceDirectory = Join-Path $themeRoot 'frames\source\cutin_weaponmaster_neo'
}
if ([string]::IsNullOrWhiteSpace($InventoryPath)) {
    $InventoryPath = Join-Path $SourceDirectory 'frame-inventory.json'
}
if ([string]::IsNullOrWhiteSpace($BodyReference)) {
    $BodyReference = Join-Path $themeRoot 'referencediagram\DNF剑魂3觉立绘改维吉尔.png'
}
if ([string]::IsNullOrWhiteSpace($CinemaReference)) {
    $CinemaReference = Join-Path $themeRoot 'referencediagram\DNF剑魂3觉立绘改维吉尔 (1).png'
}
if ([string]::IsNullOrWhiteSpace($EditedDirectory)) {
    $EditedDirectory = Join-Path $themeRoot (Join-Path 'frames\edited' (Join-Path $RunId 'aseprite'))
}
if ([string]::IsNullOrWhiteSpace($RuntimeDirectory)) {
    $RuntimeDirectory = Join-Path $themeRoot (Join-Path 'frames\runtime' (Join-Path $RunId 'png'))
}
if ([string]::IsNullOrWhiteSpace($ValidationDirectory)) {
    $ValidationDirectory = Join-Path $themeRoot (Join-Path 'validation' $RunId)
}

$aseprite = Resolve-DnfAsepriteExecutable -Path $AsepritePath -RepositoryRoot $repoRoot
$asepriteCapability = Test-DnfAsepriteApiCapability -Executable $aseprite -RepositoryRoot $repoRoot
$sourcePath = (Resolve-Path -LiteralPath $SourceDirectory).Path
$inventoryFile = (Resolve-Path -LiteralPath $InventoryPath).Path
$bodyPath = (Resolve-Path -LiteralPath $BodyReference).Path
$cinemaPath = (Resolve-Path -LiteralPath $CinemaReference).Path
$editedPath = [IO.Path]::GetFullPath($EditedDirectory)
$runtimePath = [IO.Path]::GetFullPath($RuntimeDirectory)
$validationPath = [IO.Path]::GetFullPath($ValidationDirectory)
$themePath = (Resolve-Path -LiteralPath $themeRoot).Path

foreach ($requiredFile in @($luaPath, $inventoryFile, $bodyPath, $cinemaPath)) {
    if (-not (Test-Path -LiteralPath $requiredFile -PathType Leaf)) {
        throw "Required file was not found: $requiredFile"
    }
}
foreach ($output in @($editedPath, $runtimePath, $validationPath)) {
    if (-not $output.StartsWith($themePath + [IO.Path]::DirectorySeparatorChar, [StringComparison]::OrdinalIgnoreCase)) {
        throw "Output must remain inside the current theme workspace: $output"
    }
    if (Test-Path -LiteralPath $output) {
        throw "Refusing to overwrite existing run output: $output"
    }
}
if ($editedPath -eq $runtimePath -or $editedPath -eq $validationPath -or $runtimePath -eq $validationPath) {
    throw 'Edited, runtime, and validation directories must be distinct.'
}

$inventory = Get-Content -LiteralPath $inventoryFile -Raw -Encoding UTF8 | ConvertFrom-Json
if ($inventory.schemaVersion -ne 1 -or
    $inventory.img.path -ne 'sprite/character/swordman/effect/cutin/cutin_weaponmaster_neo.img' -or
    $inventory.img.version -ne 'Ver5' -or
    [int]$inventory.img.frameCount -ne 27) {
    throw 'Cut-in source inventory identity or structure is not the verified contract.'
}
if ((@($inventory.img.transparentPlaceholderFrames) -join ',') -ne '0,1,2' -or
    (@($inventory.img.visibleFrames) -join ',') -ne ((3..26) -join ',')) {
    throw 'Cut-in source inventory frame classification changed.'
}

$sourceFrameRecords = New-Object Collections.Generic.List[object]
foreach ($frameIndex in 3..26) {
    $matches = @($inventory.frames | Where-Object { [int]$_.frameIndex -eq $frameIndex })
    if ($matches.Count -ne 1) {
        throw "Expected one source inventory record for frame $frameIndex, found $($matches.Count)."
    }
    $record = $matches[0]
    if ([int]$record.width -ne 1067 -or [int]$record.height -ne 600 -or
        [int]$record.canvasWidth -ne 1067 -or [int]$record.canvasHeight -ne 600 -or
        [int]$record.x -ne 0 -or [int]$record.y -ne 0 -or
        $record.type -ne 'DXT_5' -or $record.compressMode -ne 'DDS_ZLIB' -or
        $record.textureType -ne 'DXT_5' -or
        [int]$record.textureWidth -ne 1068 -or [int]$record.textureHeight -ne 600) {
        throw "Verified source/runtime geometry or texture contract changed at frame $frameIndex."
    }
    $sourceFrame = Join-Path $sourcePath ('frame-{0:D3}.png' -f $frameIndex)
    if (-not (Test-Path -LiteralPath $sourceFrame -PathType Leaf)) {
        throw "Source frame was not found: $sourceFrame"
    }
    $snapshot = Get-DnfFileSnapshot -Path $sourceFrame
    if ($snapshot.length -ne [long]$record.pngBytes -or
        $snapshot.sha256 -ne ([string]$record.pngSha256).ToUpperInvariant()) {
        throw "Source frame differs from frozen inventory: $sourceFrame"
    }
    $sourceFrameRecords.Add([pscustomobject]@{
        frameIndex = $frameIndex
        inventory = $record
        source = $snapshot
    })
}

Add-Type -AssemblyName System.Drawing
function Get-ImageGeometry {
    param([Parameter(Mandatory = $true)][string]$Path)

    $image = $null
    try {
        $image = [Drawing.Image]::FromFile($Path)
        return [pscustomobject]@{
            width = [int]$image.Width
            height = [int]$image.Height
            pixelFormat = $image.PixelFormat.ToString()
        }
    }
    finally {
        if ($null -ne $image) { $image.Dispose() }
    }
}

$bodyGeometry = Get-ImageGeometry -Path $bodyPath
$cinemaGeometry = Get-ImageGeometry -Path $cinemaPath
foreach ($reference in @(
    [pscustomobject]@{ label = 'body'; geometry = $bodyGeometry },
    [pscustomobject]@{ label = 'cinema'; geometry = $cinemaGeometry }
)) {
    if ($reference.geometry.width -lt 1728 -or $reference.geometry.height -lt 1247) {
        throw "$($reference.label) reference is smaller than the verified crop envelope: $($reference.geometry.width)x$($reference.geometry.height)"
    }
}

$sourceInventoryBefore = Get-DnfFileSnapshot -Path $inventoryFile
$bodyBefore = Get-DnfFileSnapshot -Path $bodyPath
$cinemaBefore = Get-DnfFileSnapshot -Path $cinemaPath
$asepriteSnapshot = Get-DnfFileSnapshot -Path $aseprite
$luaSnapshot = Get-DnfFileSnapshot -Path $luaPath
$wrapperSnapshot = Get-DnfFileSnapshot -Path $PSCommandPath
$asepriteVersion = (& $aseprite --version 2>&1 | Out-String).Trim()
if ($LASTEXITCODE -ne 0 -or [string]::IsNullOrWhiteSpace($asepriteVersion)) {
    throw "Aseprite --version failed: $asepriteVersion"
}

$editedParent = Split-Path -Parent $editedPath
$runtimeParent = Split-Path -Parent $runtimePath
$validationParent = Split-Path -Parent $validationPath
foreach ($parent in @($editedParent, $runtimeParent, $validationParent)) {
    New-Item -ItemType Directory -Path $parent -Force | Out-Null
}
$token = [Guid]::NewGuid().ToString('N')
$stagingEdited = Join-Path $editedParent ('.' + [IO.Path]::GetFileName($editedPath) + '.staging-' + $token)
$stagingRuntime = Join-Path $runtimeParent ('.' + [IO.Path]::GetFileName($runtimePath) + '.staging-' + $token)
$stagingValidation = Join-Path $validationParent ('.' + [IO.Path]::GetFileName($validationPath) + '.staging-' + $token)
foreach ($staging in @($stagingEdited, $stagingRuntime, $stagingValidation)) {
    New-Item -ItemType Directory -Path $staging | Out-Null
}

$publishedEdited = $false
$publishedRuntime = $false
$publishedValidation = $false
try {
    $runPlan = [ordered]@{
        schemaVersion = 1
        createdAt = (Get-Date).ToString('o')
        runId = $RunId
        status = 'planned'
        fullSkillCoverageProven = $false
        mode = 'Aseprite batch raster adaptation; no NPK build or deployment'
        resource = [ordered]@{
            technicalId = 'cutin_weaponmaster_neo'
            imgPath = $inventory.img.path
            imgVersion = $inventory.img.version
            frameIndexes = @(3..26)
            excludedPlaceholderFrames = @(0..2)
        }
        geometry = [ordered]@{
            logicalSprite = '1067x600'
            runtimeTextureInput = '1068x600'
            padding = 'one transparent pixel at right before compositing'
        }
        inputs = [ordered]@{
            inventory = $sourceInventoryBefore
            bodyReference = [ordered]@{ snapshot = $bodyBefore; geometry = $bodyGeometry }
            cinemaReference = [ordered]@{ snapshot = $cinemaBefore; geometry = $cinemaGeometry }
            frames = @($sourceFrameRecords | ForEach-Object {
                [ordered]@{
                    frameIndex = $_.frameIndex
                    path = $_.source.path
                    length = $_.source.length
                    sha256 = $_.source.sha256
                }
            })
        }
        editor = [ordered]@{
            application = 'Aseprite'
            version = $asepriteVersion
            executable = $asepriteSnapshot
            apiCapability = $asepriteCapability
            script = $luaSnapshot
            wrapper = $wrapperSnapshot
        }
        outputs = [ordered]@{
            editedDirectory = $editedPath
            runtimeDirectory = $runtimePath
            validationDirectory = $validationPath
            overwriteExisting = $false
        }
        rendering = [ordered]@{
            referenceCropAndResize = 'fixed verified crops; bilinear resize to runtime canvas'
            sourceTimingLayer = 'source frame padded on right and blended as HSL luminosity'
            rasterLayers = @('background', 'references', 'vignette', 'spatial fractures', 'blade energy', 'fragments', 'source timing', 'cold grade')
            seedStrategy = 'deterministic frame-index arithmetic; no random generator'
            network = 'disabled-not-required'
        }
        deployment = 'not-authorized-not-performed'
    }
    $runPlanPath = Join-Path $stagingValidation 'run-plan.json'
    $runPlan | ConvertTo-Json -Depth 10 | Set-Content -LiteralPath $runPlanPath -Encoding UTF8
    $null = Get-Content -LiteralPath $runPlanPath -Raw -Encoding UTF8 | ConvertFrom-Json

    $commonArguments = @(
        '--batch',
        '--script-param', ('frameStart=3'),
        '--script-param', ('frameEnd=26'),
        '--script-param', ('canvasWidth=1068'),
        '--script-param', ('canvasHeight=600'),
        '--script-param', ('sourceWidth=1067'),
        '--script-param', ('sourceHeight=600'),
        '--script-param', ('projectDirectory=' + $stagingEdited),
        '--script-param', ('runtimeDirectory=' + $stagingRuntime)
    )
    $renderArguments = $commonArguments + @(
        '--script-param', 'mode=render',
        '--script-param', ('sourceDirectory=' + $sourcePath),
        '--script-param', ('bodyReference=' + $bodyPath),
        '--script-param', ('cinemaReference=' + $cinemaPath),
        '--script', $luaPath
    )
    $renderOutput = & $aseprite $renderArguments 2>&1 | Out-String
    $renderOutput | Set-Content -LiteralPath (Join-Path $stagingValidation 'aseprite-render-output.txt') -Encoding UTF8
    if ($LASTEXITCODE -ne 0) {
        throw "Aseprite Cut-in render failed: $renderOutput"
    }
    if ($renderOutput -notmatch 'CutinAsepriteRender=passed') {
        throw "Aseprite Cut-in render did not emit its success marker: $renderOutput"
    }

    $projects = @(Get-ChildItem -LiteralPath $stagingEdited -File -Filter 'frame-*.aseprite' | Sort-Object Name)
    $runtimePngs = @(Get-ChildItem -LiteralPath $stagingRuntime -File -Filter 'frame-*.png' | Sort-Object Name)
    if ($projects.Count -ne 24 -or $runtimePngs.Count -ne 24) {
        throw "Expected 24 layered projects and 24 runtime PNGs, found $($projects.Count)/$($runtimePngs.Count)."
    }
    if (@(Get-ChildItem -LiteralPath $stagingEdited -File).Count -ne 24 -or
        @(Get-ChildItem -LiteralPath $stagingRuntime -File).Count -ne 24) {
        throw 'Aseprite output directories contain unexpected files.'
    }

    $frameOutputs = New-Object Collections.Generic.List[object]
    foreach ($frameIndex in 3..26) {
        $frameName = 'frame-{0:D3}' -f $frameIndex
        $project = Join-Path $stagingEdited ($frameName + '.aseprite')
        $runtime = Join-Path $stagingRuntime ($frameName + '.png')
        if (-not (Test-Path -LiteralPath $project -PathType Leaf) -or
            -not (Test-Path -LiteralPath $runtime -PathType Leaf)) {
            throw "Missing deterministic Aseprite output pair: $frameName"
        }
        $geometry = Get-ImageGeometry -Path $runtime
        if ($geometry.width -ne 1068 -or $geometry.height -ne 600) {
            throw "Runtime PNG geometry mismatch for ${frameName}: $($geometry.width)x$($geometry.height)"
        }
        $sourceRecord = @($sourceFrameRecords | Where-Object { $_.frameIndex -eq $frameIndex })[0]
        $frameOutputs.Add([pscustomobject]@{
            frameIndex = $frameIndex
            source = $sourceRecord.source
            edited = Get-DnfFileSnapshot -Path $project
            runtime = Get-DnfFileSnapshot -Path $runtime
            runtimeGeometry = $geometry
        })
    }

    $validationArguments = $commonArguments + @(
        '--script-param', 'mode=validate',
        '--script', $luaPath
    )
    $validationOutput = & $aseprite $validationArguments 2>&1 | Out-String
    $validationOutput | Set-Content -LiteralPath (Join-Path $stagingValidation 'aseprite-validation-output.txt') -Encoding UTF8
    if ($LASTEXITCODE -ne 0) {
        throw "Aseprite layered-project validation failed: $validationOutput"
    }
    if ($validationOutput -notmatch 'CutinAsepriteValidation=passed') {
        throw "Aseprite validation did not emit its success marker: $validationOutput"
    }

    foreach ($inputRecord in @(
        [pscustomobject]@{ before = $sourceInventoryBefore; path = $inventoryFile; label = 'source inventory' },
        [pscustomobject]@{ before = $bodyBefore; path = $bodyPath; label = 'body reference' },
        [pscustomobject]@{ before = $cinemaBefore; path = $cinemaPath; label = 'cinema reference' }
    )) {
        $after = Get-DnfFileSnapshot -Path $inputRecord.path
        if ($after.length -ne $inputRecord.before.length -or
            $after.sha256 -ne $inputRecord.before.sha256 -or
            $after.lastWriteTime -ne $inputRecord.before.lastWriteTime) {
            throw "$($inputRecord.label) changed during Aseprite rendering."
        }
    }
    foreach ($sourceRecord in $sourceFrameRecords) {
        $after = Get-DnfFileSnapshot -Path $sourceRecord.source.path
        if ($after.length -ne $sourceRecord.source.length -or
            $after.sha256 -ne $sourceRecord.source.sha256 -or
            $after.lastWriteTime -ne $sourceRecord.source.lastWriteTime) {
            throw "Source frame changed during Aseprite rendering: $($sourceRecord.source.path)"
        }
    }

    Move-Item -LiteralPath $stagingEdited -Destination $editedPath
    $publishedEdited = $true
    Move-Item -LiteralPath $stagingRuntime -Destination $runtimePath
    $publishedRuntime = $true

    $publishedFrames = New-Object Collections.Generic.List[object]
    foreach ($frameOutput in $frameOutputs) {
        $frameName = 'frame-{0:D3}' -f $frameOutput.frameIndex
        $publishedProject = Join-Path $editedPath ($frameName + '.aseprite')
        $publishedRuntimeFile = Join-Path $runtimePath ($frameName + '.png')
        $projectSnapshot = Get-DnfFileSnapshot -Path $publishedProject
        $runtimeSnapshot = Get-DnfFileSnapshot -Path $publishedRuntimeFile
        if ($projectSnapshot.length -ne $frameOutput.edited.length -or
            $projectSnapshot.sha256 -ne $frameOutput.edited.sha256 -or
            $runtimeSnapshot.length -ne $frameOutput.runtime.length -or
            $runtimeSnapshot.sha256 -ne $frameOutput.runtime.sha256) {
            throw "Published output differs from staged output: $frameName"
        }
        $publishedFrames.Add([ordered]@{
            frameIndex = [int]$frameOutput.frameIndex
            source = [ordered]@{
                path = $frameOutput.source.path
                length = $frameOutput.source.length
                sha256 = $frameOutput.source.sha256
            }
            edited = [ordered]@{
                path = $projectSnapshot.path
                length = $projectSnapshot.length
                sha256 = $projectSnapshot.sha256
                format = 'layered .aseprite project'
            }
            runtime = [ordered]@{
                path = $runtimeSnapshot.path
                length = $runtimeSnapshot.length
                sha256 = $runtimeSnapshot.sha256
                width = 1068
                height = 600
                role = 'BC3 color encoder input; source BC3 alpha remains builder-controlled'
            }
        })
    }

    $summary = [ordered]@{
        schemaVersion = 1
        generatedAt = (Get-Date).ToString('o')
        runId = $RunId
        status = 'passed'
        fullSkillCoverageProven = $false
        mode = 'Aseprite batch raster adaptation; no NPK build or deployment'
        runPlan = [ordered]@{
            path = (Join-Path $validationPath 'run-plan.json')
            length = [long](Get-Item -LiteralPath $runPlanPath).Length
            sha256 = (Get-FileHash -LiteralPath $runPlanPath -Algorithm SHA256).Hash
        }
        editor = $runPlan.editor
        sourceInventory = $sourceInventoryBefore
        references = [ordered]@{
            body = [ordered]@{ snapshot = $bodyBefore; geometry = $bodyGeometry }
            cinema = [ordered]@{ snapshot = $cinemaBefore; geometry = $cinemaGeometry }
            watermarkPolicy = 'fixed upper crops exclude the lower-right generated watermark area; visual review remains required'
        }
        accounting = [ordered]@{
            expectedFrames = 24
            sourceFrames = 24
            layeredProjects = 24
            runtimePngs = 24
            missingFrames = 0
            duplicateFrames = 0
            geometryDrift = 0
            configurationDrift = 0
            reopenedProjectsValidated = 24
            runtimeMatchesLayeredRender = 24
        }
        frames = $publishedFrames.ToArray()
        validation = [ordered]@{
            sourceInputsUnchanged = 'passed'
            sourceInventoryHashes = 'passed'
            runtimeGeometry = 'passed-1068x600'
            layeredProjectsReopened = 'passed'
            layeredProjectRuntimePixelEquality = 'passed'
            alphaAndBcEncoding = 'not-performed-here; source BC3 alpha preservation and DirectXTex validation remain builder gates'
            fullSequenceVisualReview = 'pending'
            targetClient = 'pending'
        }
        deployment = 'not-authorized-not-performed'
    }
    $summaryPath = Join-Path $stagingValidation 'render-summary.json'
    $summary | ConvertTo-Json -Depth 12 | Set-Content -LiteralPath $summaryPath -Encoding UTF8
    $null = Get-Content -LiteralPath $summaryPath -Raw -Encoding UTF8 | ConvertFrom-Json
    Move-Item -LiteralPath $stagingValidation -Destination $validationPath
    $publishedValidation = $true

    [pscustomobject]@{
        status = 'passed'
        runId = $RunId
        editedDirectory = $editedPath
        runtimeDirectory = $runtimePath
        validationDirectory = $validationPath
        frameCount = 24
        fullSequenceVisualReview = 'pending'
        npkBuild = 'not-performed'
        deployment = 'not-authorized-not-performed'
    }
}
catch {
    if ($publishedValidation -and (Test-Path -LiteralPath $validationPath)) {
        Remove-Item -LiteralPath $validationPath -Recurse -Force
    }
    if ($publishedRuntime -and (Test-Path -LiteralPath $runtimePath)) {
        Remove-Item -LiteralPath $runtimePath -Recurse -Force
    }
    if ($publishedEdited -and (Test-Path -LiteralPath $editedPath)) {
        Remove-Item -LiteralPath $editedPath -Recurse -Force
    }
    throw
}
finally {
    foreach ($staging in @($stagingEdited, $stagingRuntime, $stagingValidation)) {
        if (Test-Path -LiteralPath $staging) {
            Remove-Item -LiteralPath $staging -Recurse -Force
        }
    }
}
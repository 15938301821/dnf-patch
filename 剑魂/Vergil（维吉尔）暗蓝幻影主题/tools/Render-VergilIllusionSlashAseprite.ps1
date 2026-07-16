[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)]
    [ValidatePattern('^[A-Za-z0-9][A-Za-z0-9._-]*$')]
    [string]$RunId,

    [string]$SourceDirectory,

    [string]$InventoryPath,

    [string]$EditedDirectory,

    [string]$RuntimeDirectory,

    [string]$ValidationDirectory,

    [string]$AsepritePath
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
$OutputEncoding = [Console]::OutputEncoding = New-Object System.Text.UTF8Encoding($false)

function Assert-InsideRoot {
    param(
        [Parameter(Mandatory = $true)][string]$Path,
        [Parameter(Mandatory = $true)][string]$Root,
        [Parameter(Mandatory = $true)][string]$Label
    )

    $fullPath = [IO.Path]::GetFullPath($Path)
    $fullRoot = [IO.Path]::GetFullPath($Root).TrimEnd([IO.Path]::DirectorySeparatorChar, [IO.Path]::AltDirectorySeparatorChar)
    $prefix = $fullRoot + [IO.Path]::DirectorySeparatorChar
    if (-not ($fullPath.Equals($fullRoot, [StringComparison]::OrdinalIgnoreCase) -or
            $fullPath.StartsWith($prefix, [StringComparison]::OrdinalIgnoreCase))) {
        throw "$Label must stay inside '$fullRoot': $fullPath"
    }
}

function Get-RelativePath {
    param(
        [Parameter(Mandatory = $true)][string]$Path,
        [Parameter(Mandatory = $true)][string]$Root
    )

    $fullPath = [IO.Path]::GetFullPath($Path)
    $fullRoot = [IO.Path]::GetFullPath($Root).TrimEnd([IO.Path]::DirectorySeparatorChar, [IO.Path]::AltDirectorySeparatorChar)
    Assert-InsideRoot -Path $fullPath -Root $fullRoot -Label 'relative path source'
    if ($fullPath.Equals($fullRoot, [StringComparison]::OrdinalIgnoreCase)) {
        return '.'
    }
    return $fullPath.Substring($fullRoot.Length + 1).Replace('\\', '/')
}

function Get-ImageGeometry {
    param([Parameter(Mandatory = $true)][string]$Path)

    $image = $null
    try {
        $image = [Drawing.Image]::FromFile($Path)
        return [pscustomobject]@{
            width       = [int]$image.Width
            height      = [int]$image.Height
            pixelFormat = $image.PixelFormat.ToString()
        }
    }
    finally {
        if ($null -ne $image) { $image.Dispose() }
    }
}

function Get-PublishedFileSnapshot {
    param(
        [Parameter(Mandatory = $true)][string]$CurrentPath,
        [Parameter(Mandatory = $true)][string]$PublishedPath
    )

    $snapshot = Get-DnfFileSnapshot -Path $CurrentPath
    return [pscustomobject]@{
        path          = [IO.Path]::GetFullPath($PublishedPath)
        length        = [long]$snapshot.length
        lastWriteTime = [string]$snapshot.lastWriteTime
        sha256        = [string]$snapshot.sha256
    }
}

function ConvertTo-RenderPlanTsv {
    param(
        [Parameter(Mandatory = $true)][object[]]$Records,
        [Parameter(Mandatory = $true)][string]$Path
    )

    $headers = @('frameKey', 'imgPath', 'albumSlug', 'frameIndex', 'sourcePng', 'textureWidth', 'textureHeight')
    $lines = New-Object 'Collections.Generic.List[string]'
    $lines.Add(($headers -join "`t"))
    foreach ($record in $Records) {
        $values = foreach ($header in $headers) {
            $value = [string]$record.$header
            if ($value.Contains("`t") -or $value.Contains("`n") -or $value.Contains("`r")) {
                throw "Render plan field contains a tab or newline: $header"
            }
            $value
        }
        $lines.Add(($values -join "`t"))
    }
    $lines | Set-Content -LiteralPath $Path -Encoding UTF8
}

$themeRoot = Split-Path -Parent $PSScriptRoot
$professionRoot = Split-Path -Parent $themeRoot
$repoRoot = Split-Path -Parent $professionRoot
Import-Module (Join-Path $repoRoot 'tools\DnfPatch.ModelTools.psm1') -Force
Import-Module (Join-Path $repoRoot 'tools\DnfPatch.Toolchain.psm1') -Force
Add-Type -AssemblyName System.Drawing

$luaPath = Join-Path $PSScriptRoot 'Render-VergilIllusionSlashAseprite.lua'
if ([string]::IsNullOrWhiteSpace($SourceDirectory)) {
    $SourceDirectory = Join-Path $themeRoot (Join-Path 'frames\source' (Join-Path $RunId 'illusionslash'))
}
if ([string]::IsNullOrWhiteSpace($InventoryPath)) {
    $InventoryPath = Join-Path $SourceDirectory 'frame-inventory.json'
}
if ([string]::IsNullOrWhiteSpace($EditedDirectory)) {
    $EditedDirectory = Join-Path $themeRoot (Join-Path 'frames\edited' (Join-Path $RunId 'illusionslash'))
}
if ([string]::IsNullOrWhiteSpace($RuntimeDirectory)) {
    $RuntimeDirectory = Join-Path $themeRoot (Join-Path 'frames\runtime' (Join-Path $RunId 'illusionslash'))
}
if ([string]::IsNullOrWhiteSpace($ValidationDirectory)) {
    $ValidationDirectory = Join-Path $themeRoot (Join-Path 'validation' (Join-Path $RunId 'redraw'))
}

$sourcePath = (Resolve-Path -LiteralPath $SourceDirectory).Path
$inventoryFile = (Resolve-Path -LiteralPath $InventoryPath).Path
$editedPath = [IO.Path]::GetFullPath($EditedDirectory)
$runtimePath = [IO.Path]::GetFullPath($RuntimeDirectory)
$validationPath = [IO.Path]::GetFullPath($ValidationDirectory)
$themePath = (Resolve-Path -LiteralPath $themeRoot).Path
foreach ($path in @($editedPath, $runtimePath, $validationPath)) {
    Assert-InsideRoot -Path $path -Root $themePath -Label 'Aseprite output'
    if (Test-Path -LiteralPath $path) {
        throw "Refusing to overwrite existing output: $path"
    }
}
foreach ($requiredFile in @($luaPath, $inventoryFile)) {
    if (-not (Test-Path -LiteralPath $requiredFile -PathType Leaf)) {
        throw "Required file was not found: $requiredFile"
    }
}

$inventory = Get-Content -LiteralPath $inventoryFile -Raw -Encoding UTF8 | ConvertFrom-Json
if ($inventory.schemaVersion -ne 1 -or $inventory.status -ne 'passed' -or $inventory.runId -ne $RunId) {
    throw 'Source inventory identity does not match the requested RunId.'
}
$records = @($inventory.records | Where-Object { $_.runtimeRequired -eq $true })
if ($records.Count -eq 0) {
    throw 'Source inventory has no runtime-required records.'
}

foreach ($record in $records) {
    $sourcePng = [IO.Path]::GetFullPath([string]$record.sourcePng)
    Assert-InsideRoot -Path $sourcePng -Root $sourcePath -Label 'source PNG'
    if (-not (Test-Path -LiteralPath $sourcePng -PathType Leaf)) {
        throw "Source PNG was not found: $sourcePng"
    }
    $snapshot = Get-DnfFileSnapshot -Path $sourcePng
    if ([long]$record.sourcePngBytes -ne [long]$snapshot.length -or
        ([string]$record.sourcePngSha256).ToUpperInvariant() -ne [string]$snapshot.sha256) {
        throw "Source PNG differs from frozen inventory: $sourcePng"
    }
    $geometry = Get-ImageGeometry -Path $sourcePng
    if ([int]$geometry.width -ne [int]$record.textureWidth -or [int]$geometry.height -ne [int]$record.textureHeight) {
        throw "Source PNG geometry differs from texture contract: $sourcePng"
    }
}

$illusionPromptName = [string]::Concat([char]0x5E7B, [char]0x5F71, [char]0x5251, [char]0x821E, '.md')
$themeAgentPath = Join-Path $themeRoot 'AGENTS.md'
$professionPromptPath = Join-Path (Join-Path $professionRoot 'prompts') $illusionPromptName
$themePromptPath = Join-Path (Join-Path $themeRoot 'prompts') $illusionPromptName
foreach ($requiredFile in @($themeAgentPath, $professionPromptPath, $themePromptPath)) {
    if (-not (Test-Path -LiteralPath $requiredFile -PathType Leaf)) {
        throw "Prompt binding file was not found: $requiredFile"
    }
}

$aseprite = Resolve-DnfAsepriteExecutable -Path $AsepritePath -RepositoryRoot $repoRoot
$asepriteCapability = Test-DnfAsepriteApiCapability -Executable $aseprite -RepositoryRoot $repoRoot
$asepriteSnapshot = Get-DnfFileSnapshot -Path $aseprite
$luaSnapshot = Get-DnfFileSnapshot -Path $luaPath
$wrapperSnapshot = Get-DnfFileSnapshot -Path $PSCommandPath
$inventorySnapshot = Get-DnfFileSnapshot -Path $inventoryFile
$asepriteVersion = (& $aseprite --version 2>&1 | Out-String).Trim()
if ($LASTEXITCODE -ne 0 -or [string]::IsNullOrWhiteSpace($asepriteVersion)) {
    throw "Aseprite --version failed: $asepriteVersion"
}

$validationParent = Split-Path -Parent $validationPath
$editedParent = Split-Path -Parent $editedPath
$runtimeParent = Split-Path -Parent $runtimePath
foreach ($parent in @($validationParent, $editedParent, $runtimeParent)) {
    New-Item -ItemType Directory -Path $parent -Force | Out-Null
}
$token = [Guid]::NewGuid().ToString('N')
$stagingValidation = Join-Path $validationParent ('.' + [IO.Path]::GetFileName($validationPath) + '.staging-' + $token)
$stagingEdited = Join-Path $editedParent ('.' + [IO.Path]::GetFileName($editedPath) + '.staging-' + $token)
$stagingRuntime = Join-Path $runtimeParent ('.' + [IO.Path]::GetFileName($runtimePath) + '.staging-' + $token)
foreach ($path in @($stagingValidation, $stagingEdited, $stagingRuntime)) {
    New-Item -ItemType Directory -Path $path | Out-Null
}
foreach ($record in $records) {
    New-Item -ItemType Directory -Path (Join-Path $stagingEdited ([string]$record.albumSlug)) -Force | Out-Null
    New-Item -ItemType Directory -Path (Join-Path $stagingRuntime ([string]$record.albumSlug)) -Force | Out-Null
}

$publishedEdited = $false
$publishedRuntime = $false
$publishedValidation = $false
try {
    $modelRequestPath = Join-Path $stagingValidation 'model-style-request.json'
    $stylePlanPath = Join-Path $stagingValidation 'model-style-plan.json'
    $renderPlanPath = Join-Path $stagingValidation 'aseprite-render-plan.tsv'
    $renderLogPath = Join-Path $stagingValidation 'aseprite-render-output.txt'
    $validateLogPath = Join-Path $stagingValidation 'aseprite-validate-output.txt'

    $modelRequest = [ordered]@{
        schemaVersion  = 1
        professionPath = Get-RelativePath -Path $professionRoot -Root $repoRoot
        themePath      = Get-RelativePath -Path $themeRoot -Root $repoRoot
        promptBinding  = [ordered]@{
            role                  = 'primary-skill-prompt'
            priority              = 1
            themeAgentPath        = Get-RelativePath -Path $themeAgentPath -Root $repoRoot
            professionPromptPath  = Get-RelativePath -Path $professionPromptPath -Root $repoRoot
            themePromptPath       = Get-RelativePath -Path $themePromptPath -Root $repoRoot
            uiFrameGeometryPolicy = 'strict-preserve-source-frame-position-size'
            scope                 = 'illusionslash-only'
        }
        styleIntent    = [ordered]@{
            palette    = @('#0A1633', '#1A8FFF', '#00D4FF', '#FFFFFF')
            operations = @(
                [ordered]@{ type = 'palette-map'; target = 'visible slash and sword silhouette pixels'; colorStops = @('#0A1633', '#1A8FFF', '#00D4FF', '#FFFFFF'); blend = 'source-preserving'; notes = 'preserve source alpha, frame geometry, and timing' },
                [ordered]@{ type = 'blade-core'; target = 'high-intensity inherited blade strips'; color = '#FFFFFF'; intensity = 'source-luminance-gated'; blend = 'source-preserving' },
                [ordered]@{ type = 'rim-light'; target = 'inherited blade edges and particle edges'; color = '#00D4FF'; intensity = 'edge-contrast-gated'; blend = 'source-preserving' },
                [ordered]@{ type = 'spatial-crack'; target = 'existing visible pixels only'; color = '#00D4FF'; density = 'sparse'; blend = 'source-preserving' },
                [ordered]@{ type = 'alpha-preserve'; target = 'all source pixels'; blend = 'source-preserving'; notes = 'no new opaque pixels and no alpha rewrite' }
            )
        }
    }
    $modelRequest | ConvertTo-Json -Depth 20 | Set-Content -LiteralPath $modelRequestPath -Encoding UTF8
    $stylePlan = New-DnfModelStylePlan -RequestPath (Get-RelativePath -Path $modelRequestPath -Root $repoRoot) `
        -OutputPath (Get-RelativePath -Path $stylePlanPath -Root $repoRoot) -RepositoryRoot $repoRoot
    if ($stylePlan.status -ne 'passed') {
        throw 'Model style plan did not pass normalization.'
    }

    $renderRows = @($records | ForEach-Object {
            [pscustomobject]@{
                frameKey      = [string]$_.frameKey
                imgPath       = [string]$_.imgPath
                albumSlug     = [string]$_.albumSlug
                frameIndex    = [int]$_.frameIndex
                sourcePng     = [string]$_.sourcePng
                textureWidth  = [int]$_.textureWidth
                textureHeight = [int]$_.textureHeight
            }
        })
    ConvertTo-RenderPlanTsv -Records $renderRows -Path $renderPlanPath

    $renderArgs = @(
        '--batch',
        '--script-param', 'mode=render',
        '--script-param', ('renderPlan=' + $renderPlanPath),
        '--script-param', ('projectDirectory=' + $stagingEdited),
        '--script-param', ('runtimeDirectory=' + $stagingRuntime),
        '--script', $luaPath
    )
    $renderOutput = & $aseprite $renderArgs 2>&1 | Out-String
    $renderOutput | Set-Content -LiteralPath $renderLogPath -Encoding UTF8
    if ($LASTEXITCODE -ne 0 -or $renderOutput -notmatch '(?m)^IllusionSlashAsepriteRender=passed\s*$') {
        throw "Aseprite render failed: $renderOutput"
    }

    $validateArgs = @(
        '--batch',
        '--script-param', 'mode=validate',
        '--script-param', ('renderPlan=' + $renderPlanPath),
        '--script-param', ('projectDirectory=' + $stagingEdited),
        '--script-param', ('runtimeDirectory=' + $stagingRuntime),
        '--script', $luaPath
    )
    $validateOutput = & $aseprite $validateArgs 2>&1 | Out-String
    $validateOutput | Set-Content -LiteralPath $validateLogPath -Encoding UTF8
    if ($LASTEXITCODE -ne 0 -or $validateOutput -notmatch '(?m)^IllusionSlashAsepriteValidation=passed\s*$') {
        throw "Aseprite validation failed: $validateOutput"
    }

    $frameSummaries = New-Object 'Collections.Generic.List[object]'
    foreach ($record in $records) {
        $baseName = 'frame-{0:D3}' -f [int]$record.frameIndex
        $albumSlug = [string]$record.albumSlug
        $projectFile = Join-Path (Join-Path $stagingEdited $albumSlug) ($baseName + '.aseprite')
        $runtimeFile = Join-Path (Join-Path $stagingRuntime $albumSlug) ($baseName + '.png')
        $publishedProjectFile = Join-Path (Join-Path $editedPath $albumSlug) ($baseName + '.aseprite')
        $publishedRuntimeFile = Join-Path (Join-Path $runtimePath $albumSlug) ($baseName + '.png')
        foreach ($requiredFile in @($projectFile, $runtimeFile)) {
            if (-not (Test-Path -LiteralPath $requiredFile -PathType Leaf)) {
                throw "Aseprite did not create expected output: $requiredFile"
            }
        }
        $runtimeGeometry = Get-ImageGeometry -Path $runtimeFile
        if ([int]$runtimeGeometry.width -ne [int]$record.textureWidth -or [int]$runtimeGeometry.height -ne [int]$record.textureHeight) {
            throw "Runtime geometry drifted for $($record.frameKey)"
        }
        $frameSummaries.Add([ordered]@{
                frameKey          = [string]$record.frameKey
                imgPath           = [string]$record.imgPath
                albumSlug         = $albumSlug
                frameIndex        = [int]$record.frameIndex
                source            = Get-DnfFileSnapshot -Path ([string]$record.sourcePng)
                layeredProject    = Get-PublishedFileSnapshot -CurrentPath $projectFile -PublishedPath $publishedProjectFile
                runtime           = [ordered]@{
                    snapshot    = Get-PublishedFileSnapshot -CurrentPath $runtimeFile -PublishedPath $publishedRuntimeFile
                    width       = [int]$runtimeGeometry.width
                    height      = [int]$runtimeGeometry.height
                    pixelFormat = [string]$runtimeGeometry.pixelFormat
                }
                textureWidth      = [int]$record.textureWidth
                textureHeight     = [int]$record.textureHeight
                sourceAlphaPixels = [long]$record.alphaPixels
            })
    }

    $renderSummary = [ordered]@{
        schemaVersion           = 1
        status                  = 'passed'
        runId                   = $RunId
        fullSkillCoverageProven = $false
        mode                    = 'model style plan plus Aseprite layered runtime generation; no NPK build or deployment'
        sourceInventory         = $inventorySnapshot
        promptBinding           = [ordered]@{
            priority              = 1
            uiFrameGeometryPolicy = 'strict-preserve-source-frame-position-size'
            themeAgent            = Get-DnfFileSnapshot -Path $themeAgentPath
            professionPrompt      = Get-DnfFileSnapshot -Path $professionPromptPath
            themePrompt           = Get-DnfFileSnapshot -Path $themePromptPath
            modelRequest          = Get-PublishedFileSnapshot -CurrentPath $modelRequestPath -PublishedPath (Join-Path $validationPath 'model-style-request.json')
            stylePlan             = Get-PublishedFileSnapshot -CurrentPath $stylePlanPath -PublishedPath (Join-Path $validationPath 'model-style-plan.json')
        }
        editor                  = [ordered]@{
            application   = 'Aseprite'
            version       = $asepriteVersion
            executable    = $asepriteSnapshot
            apiCapability = $asepriteCapability
            script        = $luaSnapshot
            wrapper       = $wrapperSnapshot
        }
        outputs                 = [ordered]@{
            editedDirectory     = $editedPath
            runtimeDirectory    = $runtimePath
            validationDirectory = $validationPath
            overwriteExisting   = $false
        }
        accounting              = [ordered]@{
            expectedFrames  = $records.Count
            layeredProjects = $frameSummaries.Count
            runtimePngs     = $frameSummaries.Count
            missingFrames   = 0
            duplicateFrames = 0
            geometryDrift   = 0
        }
        validation              = [ordered]@{
            sourceInputsUnchanged              = 'passed'
            runtimeGeometry                    = 'passed-texture-dimensions'
            sourceAlphaPreservedByRenderer     = 'passed'
            layeredProjectsReopened            = 'passed'
            layeredProjectRuntimePixelEquality = 'passed'
            promptStylePlanBound               = 'passed'
        }
        frames                  = $frameSummaries.ToArray()
        deployment              = [ordered]@{
            authorized       = $false
            performed        = $false
            imagePacks2Write = $false
            processOperation = $false
        }
    }
    $renderSummaryPath = Join-Path $stagingValidation 'render-summary.json'
    $renderSummary | ConvertTo-Json -Depth 20 | Set-Content -LiteralPath $renderSummaryPath -Encoding UTF8
    $null = Get-Content -LiteralPath $renderSummaryPath -Raw -Encoding UTF8 | ConvertFrom-Json

    Move-Item -LiteralPath $stagingEdited -Destination $editedPath
    $publishedEdited = $true
    Move-Item -LiteralPath $stagingRuntime -Destination $runtimePath
    $publishedRuntime = $true
    Move-Item -LiteralPath $stagingValidation -Destination $validationPath
    $publishedValidation = $true

    Write-Output "EditedDirectory=$editedPath"
    Write-Output "RuntimeDirectory=$runtimePath"
    Write-Output "RenderSummary=$(Join-Path $validationPath 'render-summary.json')"
    Write-Output "FrameCount=$($records.Count)"
    Write-Output 'Deployment=not-authorized-not-performed'
}
finally {
    foreach ($entry in @(
            [pscustomobject]@{ Path = $stagingEdited; Published = $publishedEdited },
            [pscustomobject]@{ Path = $stagingRuntime; Published = $publishedRuntime },
            [pscustomobject]@{ Path = $stagingValidation; Published = $publishedValidation }
        )) {
        if (-not $entry.Published -and (Test-Path -LiteralPath $entry.Path)) {
            Remove-Item -LiteralPath $entry.Path -Recurse -Force
        }
    }
}

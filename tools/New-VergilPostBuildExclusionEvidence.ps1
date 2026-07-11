[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)]
    [string]$ResourcePlanPath,

    [Parameter(Mandatory = $true)]
    [string]$OutputPath
)

$ErrorActionPreference = 'Stop'

function Assert-Condition {
    param(
        [Parameter(Mandatory = $true)][bool]$Condition,
        [Parameter(Mandatory = $true)][string]$Message
    )
    if (-not $Condition) {
        throw $Message
    }
}

function Resolve-RepoPath {
    param(
        [Parameter(Mandatory = $true)][string]$RepoRoot,
        [Parameter(Mandatory = $true)][string]$Value
    )
    $native = $Value.Replace('/', [IO.Path]::DirectorySeparatorChar)
    if (-not [IO.Path]::IsPathRooted($native)) {
        $native = Join-Path $RepoRoot $native
    }
    return [IO.Path]::GetFullPath($native)
}

function Get-RepoRelativePath {
    param(
        [Parameter(Mandatory = $true)][string]$RepoRoot,
        [Parameter(Mandatory = $true)][string]$Path
    )
    $rootPath = [IO.Path]::GetFullPath($RepoRoot).TrimEnd([IO.Path]::DirectorySeparatorChar) + [IO.Path]::DirectorySeparatorChar
    $fullPath = [IO.Path]::GetFullPath($Path)
    $rootUri = [Uri]::new($rootPath)
    $pathUri = [Uri]::new($fullPath)
    return [Uri]::UnescapeDataString($rootUri.MakeRelativeUri($pathUri).ToString()).Replace('\', '/')
}

function Get-FileSnapshot {
    param(
        [Parameter(Mandatory = $true)][string]$RepoRoot,
        [Parameter(Mandatory = $true)][string]$Path,
        [Parameter(Mandatory = $true)][string]$Kind
    )
    $item = Get-Item -LiteralPath $Path
    return [ordered]@{
        kind = $Kind
        path = Get-RepoRelativePath -RepoRoot $RepoRoot -Path $item.FullName
        length = $item.Length
        lastWriteTime = $item.LastWriteTime.ToString('o')
        sha256 = (Get-FileHash -LiteralPath $item.FullName -Algorithm SHA256).Hash
    }
}

function Get-StringSet {
    param([object[]]$Values)
    $set = [Collections.Generic.HashSet[string]]::new([StringComparer]::OrdinalIgnoreCase)
    foreach ($value in @($Values)) {
        if (-not [string]::IsNullOrWhiteSpace([string]$value)) {
            $null = $set.Add([string]$value)
        }
    }
    return ,$set
}

function Assert-SetEqual {
    param(
        [Parameter(Mandatory = $true)][AllowEmptyCollection()][Collections.Generic.HashSet[string]]$Expected,
        [Parameter(Mandatory = $true)][AllowEmptyCollection()][Collections.Generic.HashSet[string]]$Actual,
        [Parameter(Mandatory = $true)][string]$Label
    )
    $missing = @($Expected | Where-Object { -not $Actual.Contains($_) })
    $unexpected = @($Actual | Where-Object { -not $Expected.Contains($_) })
    Assert-Condition -Condition ($missing.Count -eq 0 -and $unexpected.Count -eq 0) `
        -Message "$Label mismatch. Missing=[$($missing -join ', ')] Unexpected=[$($unexpected -join ', ')]"
}

function Add-PartitionFrame {
    param(
        [Parameter(Mandatory = $true)][AllowEmptyCollection()][Collections.Generic.HashSet[string]]$Target,
        [Parameter(Mandatory = $true)][AllowEmptyCollection()][Collections.Generic.HashSet[string]]$OtherA,
        [Parameter(Mandatory = $true)][AllowEmptyCollection()][Collections.Generic.HashSet[string]]$OtherB,
        [Parameter(Mandatory = $true)][string]$FrameKey,
        [Parameter(Mandatory = $true)][string]$Label
    )
    Assert-Condition -Condition (-not $OtherA.Contains($FrameKey) -and -not $OtherB.Contains($FrameKey)) `
        -Message "$Label overlaps another frame partition: $FrameKey"
    Assert-Condition -Condition ($Target.Add($FrameKey)) -Message "$Label contains a duplicate frame reference: $FrameKey"
}

function Get-StringSetSha256 {
    param([Parameter(Mandatory = $true)][AllowEmptyCollection()][Collections.Generic.HashSet[string]]$Values)
    $text = (@($Values | Sort-Object) -join "`n")
    $bytes = [Text.UTF8Encoding]::new($false).GetBytes($text)
    $sha = [Security.Cryptography.SHA256]::Create()
    try {
        return ([BitConverter]::ToString($sha.ComputeHash($bytes))).Replace('-', '')
    } finally {
        $sha.Dispose()
    }
}

$repoRoot = Split-Path -Parent $PSScriptRoot
$planPath = Resolve-RepoPath -RepoRoot $repoRoot -Value $ResourcePlanPath
$outputPath = Resolve-RepoPath -RepoRoot $repoRoot -Value $OutputPath
$relativeOutput = Get-RepoRelativePath -RepoRoot $repoRoot -Path $outputPath
Assert-Condition -Condition (-not $relativeOutput.StartsWith('../') -and $relativeOutput -ne '..') `
    -Message 'OutputPath must remain inside the repository.'
Assert-Condition -Condition (-not (Test-Path -LiteralPath $outputPath)) `
    -Message "Evidence output already exists and will not be overwritten: $outputPath"

$plan = Get-Content -LiteralPath $planPath -Raw -Encoding UTF8 | ConvertFrom-Json
$components = @($plan.components)
Assert-Condition -Condition ($components.Count -eq 31) -Message "Expected 31 components, found $($components.Count)."

$allowedReasons = Get-StringSet @(
    'near-black',
    'no-visible-color-change',
    'warm-visible-after-safe-bc-merge'
)
$globalChanged = Get-StringSet @()
$globalExplicit = Get-StringSet @()
$globalDynamic = Get-StringSet @()
$dynamicGroups = [Collections.Generic.List[object]]::new()
$componentEvidence = [Collections.Generic.List[object]]::new()
$reasonTextureCounts = @{
    'near-black' = 0
    'no-visible-color-change' = 0
    'warm-visible-after-safe-bc-merge' = 0
}
$reasonFrameSets = @{
    'near-black' = Get-StringSet @()
    'no-visible-color-change' = Get-StringSet @()
    'warm-visible-after-safe-bc-merge' = Get-StringSet @()
}

foreach ($component in $components) {
    Assert-Condition -Condition ($component.selectedForAggregation -eq $true) `
        -Message "Component is not selected for aggregation: $($component.id)"
    $summaryPath = Resolve-RepoPath -RepoRoot $repoRoot -Value ([string]$component.output.buildSummaryPath)
    $componentPath = Resolve-RepoPath -RepoRoot $repoRoot -Value ([string]$component.output.componentNpkPath)
    Assert-Condition -Condition (Test-Path -LiteralPath $summaryPath -PathType Leaf) `
        -Message "Build summary was not found: $($component.id)"
    Assert-Condition -Condition (Test-Path -LiteralPath $componentPath -PathType Leaf) `
        -Message "Component NPK was not found: $($component.id)"
    $summary = Get-Content -LiteralPath $summaryPath -Raw -Encoding UTF8 | ConvertFrom-Json
    Assert-Condition -Condition ($summary.status -eq 'passed' -and $summary.deployment.performed -eq $false) `
        -Message "Component summary is not a non-deployed pass: $($component.id)"
    $plannedPaths = Get-StringSet @($component.selectedImgPaths)
    $summaryPaths = Get-StringSet @($summary.selection.allowedImgPaths)
    Assert-SetEqual -Expected $plannedPaths -Actual $summaryPaths -Label "$($component.id) selected IMG paths"
    $componentHash = (Get-FileHash -LiteralPath $componentPath -Algorithm SHA256).Hash
    Assert-Condition -Condition ($componentHash -eq ([string]$summary.output.sha256).ToUpperInvariant()) `
        -Message "Component output hash differs from its build summary: $($component.id)"

    $changed = Get-StringSet @()
    $explicit = Get-StringSet @()
    $dynamic = Get-StringSet @()
    $seenImgPaths = Get-StringSet @()
    $componentDynamicGroupCount = 0

    if ($null -ne $summary.PSObject.Properties['textures'] -and $null -ne $summary.textures) {
        $textures = @($summary.textures)
        Assert-Condition -Condition ($textures.Count -eq [int]$summary.counts.textures) `
            -Message "Texture count changed: $($component.id)"
        foreach ($texture in $textures) {
            $null = $seenImgPaths.Add([string]$texture.imgPath)
            $frameReferences = @($texture.frameReferences)
            Assert-Condition -Condition ($frameReferences.Count -gt 0) `
                -Message "Texture lacks frame references: $($component.id)/$($texture.imgPath)/$($texture.textureIndex)"
            if ($texture.decision -eq 'changed') {
                foreach ($frameKey in $frameReferences) {
                    Add-PartitionFrame -Target $changed -OtherA $explicit -OtherB $dynamic -FrameKey ([string]$frameKey) `
                        -Label "$($component.id) changed frames"
                }
                continue
            }
            Assert-Condition -Condition ($texture.decision -eq 'skipped') `
                -Message "Unexpected Texture decision: $($component.id)/$($texture.imgPath)/$($texture.textureIndex)"
            Assert-Condition -Condition ($texture.sourceCompressedSha256 -eq $texture.outputCompressedSha256 -and $texture.sourceDdsSha256 -eq $texture.outputDdsSha256 -and $texture.sourceBgraSha256 -eq $texture.outputBgraSha256) `
                -Message "Skipped Texture payload changed: $($component.id)/$($texture.imgPath)/$($texture.textureIndex)"
            Assert-Condition -Condition ([int]$texture.changedColorBlocks -eq 0 -and [int]$texture.visibleRgbChanges -eq 0) `
                -Message "Skipped Texture reports visible changes: $($component.id)/$($texture.imgPath)/$($texture.textureIndex)"
            if ($texture.skipReason -eq 'explicit-excluded-reference') {
                foreach ($frameKey in $frameReferences) {
                    Add-PartitionFrame -Target $explicit -OtherA $changed -OtherB $dynamic -FrameKey ([string]$frameKey) `
                        -Label "$($component.id) explicit frames"
                }
                continue
            }
            $reason = [string]$texture.skipReason
            Assert-Condition -Condition ($allowedReasons.Contains($reason)) `
                -Message "Unexpected dynamic Texture skip reason: $($component.id)/$reason"
            foreach ($frameKey in $frameReferences) {
                Add-PartitionFrame -Target $dynamic -OtherA $changed -OtherB $explicit -FrameKey ([string]$frameKey) `
                    -Label "$($component.id) dynamic frames"
                $null = $reasonFrameSets[$reason].Add([string]$frameKey)
            }
            $reasonTextureCounts[$reason]++
            $componentDynamicGroupCount++
            $dynamicGroups.Add([ordered]@{
                componentId = [string]$component.id
                imgPath = [string]$texture.imgPath
                textureGroupId = [int]$texture.textureGroupId
                textureIndex = [int]$texture.textureIndex
                format = [string]$texture.format
                reason = $reason
                frameReferences = @($frameReferences)
                sourceCompressedSha256 = [string]$texture.sourceCompressedSha256
                outputCompressedSha256 = [string]$texture.outputCompressedSha256
                sourceDdsSha256 = [string]$texture.sourceDdsSha256
                outputDdsSha256 = [string]$texture.outputDdsSha256
                sourceBgraSha256 = [string]$texture.sourceBgraSha256
                outputBgraSha256 = [string]$texture.outputBgraSha256
            })
        }
        Assert-Condition -Condition (@($textures | Where-Object decision -eq 'skipped').Count -eq [int]$summary.counts.skippedTextures) `
            -Message "Skipped Texture count changed: $($component.id)"
        Assert-Condition -Condition (@($textures | Where-Object skipReason -eq 'explicit-excluded-reference').Count -eq [int]$summary.counts.explicitExcludedTextures) `
            -Message "Explicit Texture count changed: $($component.id)"
        Assert-Condition -Condition (@($textures | Where-Object skipReason -eq 'near-black').Count -eq [int]$summary.counts.nearBlackTextures) `
            -Message "Near-black Texture count changed: $($component.id)"
        Assert-Condition -Condition (@($textures | Where-Object skipReason -eq 'no-visible-color-change').Count -eq [int]$summary.counts.noColorChangeTextures) `
            -Message "No-color-change Texture count changed: $($component.id)"
        Assert-Condition -Condition (@($textures | Where-Object skipReason -eq 'warm-visible-after-safe-bc-merge').Count -eq [int]$summary.counts.warmPreservedTextures) `
            -Message "Warm-preserved Texture count changed: $($component.id)"
    } elseif ($null -ne $summary.PSObject.Properties['frames'] -and $null -ne $summary.frames) {
        $frames = @($summary.frames)
        Assert-Condition -Condition ($frames.Count -eq [int]$summary.counts.frames) `
            -Message "Ver2 frame count changed: $($component.id)"
        foreach ($frame in $frames) {
            $null = $seenImgPaths.Add([string]$frame.imgPath)
            $frameKey = "$($frame.imgPath)#$($frame.frameIndex)"
            if ($frame.decision -eq 'changed') {
                Add-PartitionFrame -Target $changed -OtherA $explicit -OtherB $dynamic -FrameKey $frameKey `
                    -Label "$($component.id) changed frames"
            } elseif ($frame.decision -eq 'skipped' -and $frame.skipReason -eq 'explicit-excluded-reference') {
                Assert-Condition -Condition ($frame.sourceRawSha256 -eq $frame.outputRawSha256 -and $frame.sourceBgraSha256 -eq $frame.outputBgraSha256) `
                    -Message "Skipped Ver2 frame payload changed: $frameKey"
                Add-PartitionFrame -Target $explicit -OtherA $changed -OtherB $dynamic -FrameKey $frameKey `
                    -Label "$($component.id) explicit frames"
            } else {
                throw "Unexpected Ver2 frame decision: $frameKey/$($frame.decision)/$($frame.skipReason)"
            }
        }
        Assert-Condition -Condition ($changed.Count -eq [int]$summary.counts.changedFrames -and $explicit.Count -eq [int]$summary.counts.explicitExcludedFrames -and [int]$summary.counts.skippedFrames -eq $explicit.Count) `
            -Message "Ver2 frame decision counts changed: $($component.id)"
    } else {
        throw "Unsupported component summary schema: $($component.id)"
    }

    Assert-SetEqual -Expected $summaryPaths -Actual $seenImgPaths -Label "$($component.id) summary IMG coverage"
    $partitionCount = $changed.Count + $explicit.Count + $dynamic.Count
    Assert-Condition -Condition ($partitionCount -eq [int]$summary.counts.frames) `
        -Message "Frame partition is incomplete: $($component.id) $partitionCount/$($summary.counts.frames)"
    foreach ($frameKey in $changed) {
        Assert-Condition -Condition ($globalChanged.Add($frameKey)) -Message "Duplicate selected frame across components: $frameKey"
    }
    foreach ($frameKey in $explicit) {
        Assert-Condition -Condition ($globalExplicit.Add($frameKey)) -Message "Duplicate selected frame across components: $frameKey"
    }
    foreach ($frameKey in $dynamic) {
        Assert-Condition -Condition ($globalDynamic.Add($frameKey)) -Message "Duplicate selected frame across components: $frameKey"
    }

    $componentEvidence.Add([ordered]@{
        componentId = [string]$component.id
        imgVersion = [string]$component.imgVersion
        buildSummary = Get-FileSnapshot -RepoRoot $repoRoot -Path $summaryPath -Kind 'passed-build-summary'
        componentNpk = Get-FileSnapshot -RepoRoot $repoRoot -Path $componentPath -Kind 'passed-component-npk'
        selectedImgCount = $summaryPaths.Count
        frameCount = [int]$summary.counts.frames
        changedFrameReferenceCount = $changed.Count
        explicitExcludedFrameReferenceCount = $explicit.Count
        dynamicExcludedFrameReferenceCount = $dynamic.Count
        dynamicSkippedTextureGroupCount = $componentDynamicGroupCount
    })
}

foreach ($frameKey in $globalChanged) {
    Assert-Condition -Condition (-not $globalExplicit.Contains($frameKey) -and -not $globalDynamic.Contains($frameKey)) `
        -Message "Global changed frame overlaps an exclusion: $frameKey"
}
foreach ($frameKey in $globalExplicit) {
    Assert-Condition -Condition (-not $globalDynamic.Contains($frameKey)) `
        -Message "Global explicit and dynamic exclusions overlap: $frameKey"
}

$dynamicComponents = @($componentEvidence | Where-Object dynamicExcludedFrameReferenceCount -gt 0)
$dynamicComponentCount = $dynamicComponents.Count
$selectedFrameCount = $globalChanged.Count + $globalExplicit.Count + $globalDynamic.Count
$dynamicFrameReferences = @(foreach ($group in $dynamicGroups) {
    foreach ($frameKey in @($group.frameReferences)) {
        $separator = ([string]$frameKey).LastIndexOf('#')
        [ordered]@{
            frameKey = [string]$frameKey
            componentId = [string]$group.componentId
            imgPath = ([string]$frameKey).Substring(0, $separator)
            frameIndex = [int](([string]$frameKey).Substring($separator + 1))
            reason = [string]$group.reason
            textureGroupId = [int]$group.textureGroupId
            textureIndex = [int]$group.textureIndex
        }
    }
}) | Sort-Object frameKey
$evidence = [ordered]@{
    schemaVersion = 1
    generatedAt = (Get-Date).ToString('o')
    status = 'passed-build-summary-dynamic-exclusion-expansion'
    purpose = 'Expand every non-explicit skipped Texture into frame references and prove that source-preserved frames are disjoint from actually changed frames.'
    source = [ordered]@{
        resourcePlan = Get-FileSnapshot -RepoRoot $repoRoot -Path $planPath -Kind 'resource-plan-before-dynamic-exclusion-materialization'
        generator = Get-FileSnapshot -RepoRoot $repoRoot -Path $PSCommandPath -Kind 'evidence-generator'
        componentCount = $components.Count
        requiredSummaryStatus = 'passed'
    }
    reasonPolicy = [ordered]@{
        explicit = 'explicit-excluded-reference'
        dynamic = @('near-black', 'no-visible-color-change', 'warm-visible-after-safe-bc-merge')
    }
    components = @($dynamicComponents)
    dynamicSkippedTextureGroups = @($dynamicGroups)
    dynamicFrameReferences = @($dynamicFrameReferences)
    totals = [ordered]@{
        componentCount = $components.Count
        dynamicComponentCount = $dynamicComponentCount
        selectedFrameReferenceCount = $selectedFrameCount
        changedFrameReferenceCount = $globalChanged.Count
        explicitExcludedFrameReferenceCount = $globalExplicit.Count
        dynamicExcludedFrameReferenceCount = $globalDynamic.Count
        dynamicSkippedTextureGroupCount = $dynamicGroups.Count
        nearBlackTextureGroupCount = $reasonTextureCounts['near-black']
        nearBlackFrameReferenceCount = $reasonFrameSets['near-black'].Count
        noVisibleColorChangeTextureGroupCount = $reasonTextureCounts['no-visible-color-change']
        noVisibleColorChangeFrameReferenceCount = $reasonFrameSets['no-visible-color-change'].Count
        warmPreservedTextureGroupCount = $reasonTextureCounts['warm-visible-after-safe-bc-merge']
        warmPreservedFrameReferenceCount = $reasonFrameSets['warm-visible-after-safe-bc-merge'].Count
        sourceOutputCompressedHashMismatchCount = 0
        sourceOutputDdsHashMismatchCount = 0
        sourceOutputBgraHashMismatchCount = 0
        partitionOverlapCount = 0
    }
    framePartitions = [ordered]@{
        changedFrameKeyCount = $globalChanged.Count
        changedFrameKeySetSha256 = Get-StringSetSha256 -Values $globalChanged
        explicitExcludedFrameKeyCount = $globalExplicit.Count
        explicitExcludedFrameKeySetSha256 = Get-StringSetSha256 -Values $globalExplicit
        dynamicExcludedFrameKeys = @($globalDynamic | Sort-Object)
        dynamicExcludedFrameKeySetSha256 = Get-StringSetSha256 -Values $globalDynamic
    }
    deployment = [ordered]@{
        authorized = $false
        performed = $false
    }
}

$json = $evidence | ConvertTo-Json -Depth 12
$null = $json | ConvertFrom-Json -ErrorAction Stop
$outputDirectory = Split-Path -Parent $outputPath
if (-not (Test-Path -LiteralPath $outputDirectory -PathType Container)) {
    $null = New-Item -ItemType Directory -Path $outputDirectory
}
$temporaryPath = "$outputPath.tmp-$([guid]::NewGuid().ToString('N'))"
try {
    [IO.File]::WriteAllText($temporaryPath, $json + [Environment]::NewLine, [Text.UTF8Encoding]::new($false))
    $written = Get-Content -LiteralPath $temporaryPath -Raw -Encoding UTF8 | ConvertFrom-Json
    Assert-Condition -Condition ([int]$written.totals.selectedFrameReferenceCount -eq $selectedFrameCount) `
        -Message 'Written evidence failed its frame-count self-check.'
    Move-Item -LiteralPath $temporaryPath -Destination $outputPath
} finally {
    if (Test-Path -LiteralPath $temporaryPath) {
        Remove-Item -LiteralPath $temporaryPath -Force
    }
}

[pscustomobject]@{
    Status = 'passed'
    OutputPath = $outputPath
    OutputSha256 = (Get-FileHash -LiteralPath $outputPath -Algorithm SHA256).Hash
    ComponentCount = $components.Count
    DynamicComponentCount = $dynamicComponentCount
    DynamicSkippedTextureGroupCount = $dynamicGroups.Count
    DynamicExcludedFrameReferenceCount = $globalDynamic.Count
    ChangedFrameReferenceCount = $globalChanged.Count
    ExplicitExcludedFrameReferenceCount = $globalExplicit.Count
    SelectedFrameReferenceCount = $selectedFrameCount
} | ConvertTo-Json -Depth 4

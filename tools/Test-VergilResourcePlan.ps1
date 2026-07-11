[CmdletBinding()]
param(
    [string]$ResourcePlanPath
)

$ErrorActionPreference = 'Stop'

function Assert-Condition {
    param(
        [Parameter(Mandatory = $true)]
        [bool]$Condition,

        [Parameter(Mandatory = $true)]
        [string]$Message
    )

    if (-not $Condition) {
        throw $Message
    }
}

function Resolve-RepoPath {
    param(
        [Parameter(Mandatory = $true)]
        [string]$RepoRoot,

        [Parameter(Mandatory = $true)]
        [string]$Value
    )

    $native = $Value.Replace('/', [IO.Path]::DirectorySeparatorChar)
    if (-not [IO.Path]::IsPathRooted($native)) {
        $native = Join-Path $RepoRoot $native
    }
    return [IO.Path]::GetFullPath($native)
}

function Resolve-ConfigPath {
    param(
        [Parameter(Mandatory = $true)]
        [string]$ConfigDirectory,

        [Parameter(Mandatory = $true)]
        [string]$Value
    )

    $native = $Value.Replace('/', [IO.Path]::DirectorySeparatorChar)
    if (-not [IO.Path]::IsPathRooted($native)) {
        $native = Join-Path $ConfigDirectory $native
    }
    return [IO.Path]::GetFullPath($native)
}

function Get-NormalizedInternalPath {
    param([Parameter(Mandatory = $true)][string]$Value)
    return $Value.Replace('\', '/').TrimStart('/').ToLowerInvariant()
}

function Get-StringSet {
    param([object[]]$Values)

    $set = New-Object 'System.Collections.Generic.HashSet[string]' ([StringComparer]::OrdinalIgnoreCase)
    foreach ($value in @($Values)) {
        if (-not [string]::IsNullOrWhiteSpace([string]$value)) {
            $null = $set.Add([string]$value)
        }
    }
    return ,$set
}

function Assert-SetEqual {
    param(
        [Parameter(Mandatory = $true)]
        [AllowEmptyCollection()]
        [System.Collections.Generic.HashSet[string]]$Expected,

        [Parameter(Mandatory = $true)]
        [AllowEmptyCollection()]
        [System.Collections.Generic.HashSet[string]]$Actual,

        [Parameter(Mandatory = $true)]
        [string]$Label
    )

    $missing = @($Expected | Where-Object { -not $Actual.Contains($_) } | Sort-Object)
    $unexpected = @($Actual | Where-Object { -not $Expected.Contains($_) } | Sort-Object)
    if ($missing.Count -gt 0 -or $unexpected.Count -gt 0) {
        throw "$Label mismatch. Missing=[$($missing -join ', ')] Unexpected=[$($unexpected -join ', ')]"
    }
}

function Get-StringSetSha256 {
    param(
        [Parameter(Mandatory = $true)]
        [AllowEmptyCollection()]
        [System.Collections.Generic.HashSet[string]]$Values
    )

    $text = (@($Values | Sort-Object) -join "`n")
    $bytes = [Text.UTF8Encoding]::new($false).GetBytes($text)
    $sha = [Security.Cryptography.SHA256]::Create()
    try {
        return ([BitConverter]::ToString($sha.ComputeHash($bytes))).Replace('-', '')
    }
    finally {
        $sha.Dispose()
    }
}

function Get-BuildSummaryFramePartitions {
    param(
        [Parameter(Mandatory = $true)]
        [object]$Summary,

        [Parameter(Mandatory = $true)]
        [string]$ComponentId
    )

    $changed = New-Object 'System.Collections.Generic.HashSet[string]' ([StringComparer]::OrdinalIgnoreCase)
    $explicit = New-Object 'System.Collections.Generic.HashSet[string]' ([StringComparer]::OrdinalIgnoreCase)
    $dynamic = New-Object 'System.Collections.Generic.HashSet[string]' ([StringComparer]::OrdinalIgnoreCase)
    $dynamicReasons = Get-StringSet @('near-black', 'no-visible-color-change', 'warm-visible-after-safe-bc-merge')

    if ($Summary.PSObject.Properties['textures']) {
        Assert-Condition -Condition (@($Summary.textures).Count -eq [int]$Summary.counts.textures) `
            -Message "Texture record count mismatch: $ComponentId"
        foreach ($texture in @($Summary.textures)) {
            $frameReferences = @($texture.frameReferences)
            Assert-Condition -Condition ($frameReferences.Count -gt 0) `
                -Message "Texture has no frame references: $ComponentId/$($texture.imgPath)/$($texture.textureGroupId)"
            if ($texture.decision -eq 'changed') {
                Assert-Condition -Condition ([string]::IsNullOrWhiteSpace([string]$texture.skipReason) -and
                    [int]$texture.changedColorBlocks -gt 0 -and [int]$texture.visibleRgbChanges -gt 0 -and
                    $texture.sourceBgraSha256 -ne $texture.outputBgraSha256 -and
                    $texture.sourceAlphaSha256 -eq $texture.outputAlphaSha256) `
                    -Message "Changed Texture evidence is incomplete: $ComponentId/$($texture.imgPath)/$($texture.textureGroupId)"
                $target = $changed
            }
            elseif ($texture.decision -eq 'skipped') {
                Assert-Condition -Condition ($texture.skipReason -eq 'explicit-excluded-reference' -or
                    $dynamicReasons.Contains([string]$texture.skipReason)) `
                    -Message "Unexpected skipped Texture reason: $ComponentId/$($texture.skipReason)"
                Assert-Condition -Condition ([int]$texture.changedColorBlocks -eq 0 -and
                    [int]$texture.visibleRgbChanges -eq 0 -and
                    $texture.sourceCompressedSha256 -eq $texture.outputCompressedSha256 -and
                    $texture.sourceDdsSha256 -eq $texture.outputDdsSha256 -and
                    $texture.sourceBgraSha256 -eq $texture.outputBgraSha256 -and
                    $texture.sourceAlphaSha256 -eq $texture.outputAlphaSha256) `
                    -Message "Skipped Texture did not preserve its source payload: $ComponentId/$($texture.imgPath)/$($texture.textureGroupId)"
                if ($texture.skipReason -eq 'explicit-excluded-reference') {
                    $target = $explicit
                }
                else {
                    $target = $dynamic
                }
            }
            else {
                throw "Unexpected Texture decision: $ComponentId/$($texture.decision)"
            }

            foreach ($frameKey in $frameReferences) {
                Assert-Condition -Condition (-not [string]::IsNullOrWhiteSpace([string]$frameKey) -and
                    -not $changed.Contains([string]$frameKey) -and
                    -not $explicit.Contains([string]$frameKey) -and
                    -not $dynamic.Contains([string]$frameKey) -and
                    $target.Add([string]$frameKey)) `
                    -Message "Duplicate or overlapping frame partition: $ComponentId/$frameKey"
            }
        }
        $schema = 'textures'
    }
    elseif ($Summary.PSObject.Properties['frames']) {
        Assert-Condition -Condition (@($Summary.frames).Count -eq [int]$Summary.counts.frames) `
            -Message "Frame record count mismatch: $ComponentId"
        foreach ($frame in @($Summary.frames)) {
            $frameKey = "$($frame.imgPath)#$($frame.frameIndex)"
            if ($frame.decision -eq 'changed') {
                Assert-Condition -Condition ([string]::IsNullOrWhiteSpace([string]$frame.skipReason) -and
                    [int]$frame.changedVisiblePixels -gt 0 -and
                    $frame.sourceBgraSha256 -ne $frame.outputBgraSha256 -and
                    $frame.sourceAlphaSha256 -eq $frame.outputAlphaSha256) `
                    -Message "Changed frame evidence is incomplete: $ComponentId/$frameKey"
                $target = $changed
            }
            elseif ($frame.decision -eq 'skipped') {
                Assert-Condition -Condition ($frame.skipReason -eq 'explicit-excluded-reference' -or
                    $dynamicReasons.Contains([string]$frame.skipReason)) `
                    -Message "Unexpected skipped frame reason: $ComponentId/$($frame.skipReason)"
                Assert-Condition -Condition ($frame.sourceRawSha256 -eq $frame.outputRawSha256 -and
                    $frame.sourceBgraSha256 -eq $frame.outputBgraSha256 -and
                    $frame.sourceAlphaSha256 -eq $frame.outputAlphaSha256) `
                    -Message "Skipped frame did not preserve its source payload: $ComponentId/$frameKey"
                if ($frame.skipReason -eq 'explicit-excluded-reference') {
                    $target = $explicit
                }
                else {
                    $target = $dynamic
                }
            }
            else {
                throw "Unexpected frame decision: $ComponentId/$($frame.decision)"
            }
            Assert-Condition -Condition (-not $changed.Contains($frameKey) -and
                -not $explicit.Contains($frameKey) -and -not $dynamic.Contains($frameKey) -and
                $target.Add($frameKey)) `
                -Message "Duplicate or overlapping frame partition: $ComponentId/$frameKey"
        }
        $schema = 'frames'
    }
    else {
        throw "Unsupported build-summary schema: $ComponentId"
    }

    Assert-Condition -Condition ($changed.Count + $explicit.Count + $dynamic.Count -eq [int]$Summary.counts.frames) `
        -Message "Build-summary frame partition is incomplete: $ComponentId"
    return [pscustomobject]@{
        Schema = $schema
        Changed = $changed
        Explicit = $explicit
        Dynamic = $dynamic
    }
}

function Get-ExpectedExcludedFrameKeys {
    param(
        [Parameter(Mandatory = $true)]
        [object[]]$Images,

        [object[]]$SupplementalFrameKeys = @()
    )

    $excluded = New-Object 'System.Collections.Generic.HashSet[string]' ([StringComparer]::OrdinalIgnoreCase)
    foreach ($image in @($Images)) {
        foreach ($reason in @($image.hardExcludedByReason)) {
            foreach ($range in @($reason.ranges)) {
                $start = [int]$range.start
                $end = [int]$range.end
                Assert-Condition -Condition ($start -ge 0 -and $end -ge $start -and $end -lt [int]$image.frameCount) `
                    -Message "Invalid hard-exclusion range for $($image.path): $start..$end"
                for ($frameIndex = $start; $frameIndex -le $end; $frameIndex++) {
                    $null = $excluded.Add("$($image.path)#$frameIndex")
                }
            }
        }
    }

    $allowedImagePaths = Get-StringSet @($Images | ForEach-Object path)
    foreach ($value in @($SupplementalFrameKeys)) {
        $key = [string]$value
        $separator = $key.LastIndexOf('#')
        Assert-Condition -Condition ($separator -gt 0) -Message "Invalid supplemental excluded frame key: $key"
        $path = $key.Substring(0, $separator)
        $frameIndex = 0
        Assert-Condition -Condition ($allowedImagePaths.Contains($path) -and [int]::TryParse($key.Substring($separator + 1), [ref]$frameIndex)) `
            -Message "Supplemental excluded frame is outside selected IMG paths: $key"
        $image = @($Images | Where-Object path -eq $path)
        Assert-Condition -Condition ($image.Count -eq 1 -and $frameIndex -ge 0 -and $frameIndex -lt [int]$image[0].frameCount) `
            -Message "Supplemental excluded frame index is invalid: $key"
        $null = $excluded.Add($key)
    }

    do {
        $changed = $false
        foreach ($image in @($Images)) {
            foreach ($group in @($image.sharedTextureGroups)) {
                $groupHit = $false
                foreach ($frameIndex in @($group.frameIndexes)) {
                    if ($excluded.Contains("$($image.path)#$frameIndex")) {
                        $groupHit = $true
                        break
                    }
                }
                if ($groupHit) {
                    foreach ($frameIndex in @($group.frameIndexes)) {
                        if ($excluded.Add("$($image.path)#$frameIndex")) {
                            $changed = $true
                        }
                    }
                }
            }
        }
    } while ($changed)

    return ,$excluded
}

function Assert-FileSnapshot {
    param(
        [Parameter(Mandatory = $true)]
        [string]$RepoRoot,

        [Parameter(Mandatory = $true)]
        [object]$Snapshot,

        [Parameter(Mandatory = $true)]
        [string]$Label
    )

    $path = Resolve-RepoPath -RepoRoot $RepoRoot -Value ([string]$Snapshot.path)
    Assert-Condition -Condition (Test-Path -LiteralPath $path -PathType Leaf) -Message "$Label was not found: $path"
    $item = Get-Item -LiteralPath $path
    if ($Snapshot.PSObject.Properties['length']) {
        Assert-Condition -Condition ($item.Length -eq [long]$Snapshot.length) `
            -Message "$Label length changed: $($item.Length)/$($Snapshot.length)"
    }
    Assert-Condition -Condition (-not [string]::IsNullOrWhiteSpace([string]$Snapshot.sha256)) `
        -Message "$Label lacks a SHA-256 snapshot."
    $hash = (Get-FileHash -LiteralPath $path -Algorithm SHA256).Hash
    Assert-Condition -Condition ($hash -eq ([string]$Snapshot.sha256).ToUpperInvariant()) `
        -Message "$Label SHA-256 changed: $hash/$($Snapshot.sha256)"
    if ($Snapshot.PSObject.Properties['lastWriteTime']) {
        Assert-Condition -Condition ($item.LastWriteTime.ToString('o') -eq [string]$Snapshot.lastWriteTime) `
            -Message "$Label last-write time changed: $($item.LastWriteTime.ToString('o'))/$($Snapshot.lastWriteTime)"
    }
    return $path
}

$repoRoot = Split-Path -Parent $PSScriptRoot
if ([string]::IsNullOrWhiteSpace($ResourcePlanPath)) {
    $plans = @(
        Get-ChildItem -LiteralPath $repoRoot -Recurse -Filter 'resource-plan.json' -File |
            Where-Object { $_.FullName -like '*\configs\full-skill-v1\resource-plan.json' }
    )
    Assert-Condition -Condition ($plans.Count -eq 1) `
        -Message "Expected exactly one full-skill-v1 resource plan, found $($plans.Count)."
    $ResourcePlanPath = $plans[0].FullName
}
$planPath = (Resolve-Path -LiteralPath $ResourcePlanPath).Path
$plan = Get-Content -LiteralPath $planPath -Raw -Encoding UTF8 | ConvertFrom-Json

Assert-Condition -Condition ($plan.schemaVersion -eq 1) -Message 'Unsupported resource-plan schemaVersion.'
Assert-Condition -Condition ([string]$plan.planId -match '^weaponmaster-vergil-dark-blue-full-skill-v[0-9]+$') `
    -Message "Unexpected planId: $($plan.planId)"
Assert-Condition -Condition ($plan.themeId -eq 'weaponmaster-vergil-dark-blue') -Message 'Unexpected themeId.'
Assert-Condition -Condition ($plan.deployment.authorized -eq $false -and $plan.deployment.performed -eq $false) `
    -Message 'Resource plan must remain non-deploying.'
Assert-Condition -Condition ($plan.coverage.fullSkillCoverageProven -eq $false) `
    -Message 'fullSkillCoverageProven must remain false before final package gates.'
Assert-Condition -Condition ($plan.status -eq 'components-offline-validated-final-aggregation-pending' -and
    $plan.scope.operation -eq 'offline-components-validated-final-aggregation-pending' -and
    $plan.scope.npkBuildPerformed -eq $true -and [int]$plan.scope.componentBuildCount -eq 31 -and
    [int]$plan.scope.componentBuildPassedCount -eq 31 -and $plan.scope.finalAggregationPerformed -eq $false) `
    -Message 'Resource plan is not at the expected post-build/pre-aggregation gate.'

$accountingPath = Assert-FileSnapshot -RepoRoot $repoRoot -Snapshot $plan.evidence.postBuildFrameAccounting `
    -Label 'Post-build frame accounting'
$accounting = Get-Content -LiteralPath $accountingPath -Raw -Encoding UTF8 | ConvertFrom-Json
Assert-Condition -Condition ([int]$accounting.schemaVersion -eq 1 -and
    $accounting.status -eq 'passed-build-summary-dynamic-exclusion-expansion' -and
    [int]$accounting.source.componentCount -eq 31 -and $accounting.source.requiredSummaryStatus -eq 'passed') `
    -Message 'Post-build frame accounting identity changed.'
Assert-Condition -Condition ($accounting.source.resourcePlan.kind -eq 'resource-plan-before-dynamic-exclusion-materialization' -and
    $accounting.source.resourcePlan.sha256 -eq '40A414E03F5C6140E955FF97C0B6465163AD4C4F5EC43C9EC0981B48F1910E41') `
    -Message 'Post-build accounting no longer identifies the reviewed pre-materialization plan.'
$null = Assert-FileSnapshot -RepoRoot $repoRoot -Snapshot $accounting.source.generator `
    -Label 'Post-build accounting generator'
$expectedDynamicReasons = Get-StringSet @('near-black', 'no-visible-color-change', 'warm-visible-after-safe-bc-merge')
$actualDynamicReasons = Get-StringSet @($accounting.reasonPolicy.dynamic)
Assert-Condition -Condition ($accounting.reasonPolicy.explicit -eq 'explicit-excluded-reference') `
    -Message 'Explicit exclusion reason policy changed.'
Assert-SetEqual -Expected $expectedDynamicReasons -Actual $actualDynamicReasons -Label 'Dynamic exclusion reason policy'
Assert-Condition -Condition ($accounting.deployment.authorized -eq $false -and $accounting.deployment.performed -eq $false) `
    -Message 'Post-build accounting unexpectedly records deployment.'

$expectedAccountingTotals = [ordered]@{
    componentCount = 31
    dynamicComponentCount = 12
    selectedFrameReferenceCount = 3795
    changedFrameReferenceCount = 3593
    explicitExcludedFrameReferenceCount = 128
    dynamicExcludedFrameReferenceCount = 74
    dynamicSkippedTextureGroupCount = 70
    nearBlackTextureGroupCount = 18
    nearBlackFrameReferenceCount = 22
    noVisibleColorChangeTextureGroupCount = 16
    noVisibleColorChangeFrameReferenceCount = 16
    warmPreservedTextureGroupCount = 36
    warmPreservedFrameReferenceCount = 36
    sourceOutputCompressedHashMismatchCount = 0
    sourceOutputDdsHashMismatchCount = 0
    sourceOutputBgraHashMismatchCount = 0
    partitionOverlapCount = 0
}
foreach ($property in $expectedAccountingTotals.GetEnumerator()) {
    Assert-Condition -Condition ([int]$accounting.totals.($property.Key) -eq [int]$property.Value) `
        -Message "Post-build accounting total changed: $($property.Key)"
}

$accountingDynamicFrames = New-Object 'System.Collections.Generic.HashSet[string]' ([StringComparer]::OrdinalIgnoreCase)
$accountingDynamicFrameByKey = @{}
foreach ($frame in @($accounting.dynamicFrameReferences)) {
    $frameKey = [string]$frame.frameKey
    Assert-Condition -Condition ($frameKey -eq "$($frame.imgPath)#$($frame.frameIndex)" -and
        $actualDynamicReasons.Contains([string]$frame.reason) -and $accountingDynamicFrames.Add($frameKey)) `
        -Message "Invalid or duplicate accounting dynamic frame: $frameKey"
    $accountingDynamicFrameByKey[$frameKey] = $frame
}
Assert-Condition -Condition ($accountingDynamicFrames.Count -eq 74) `
    -Message 'Post-build accounting dynamic-frame record count changed.'
$partitionDynamicFrames = Get-StringSet @($accounting.framePartitions.dynamicExcludedFrameKeys)
Assert-Condition -Condition ($partitionDynamicFrames.Count -eq @($accounting.framePartitions.dynamicExcludedFrameKeys).Count) `
    -Message 'Post-build accounting dynamic partition contains duplicates.'
Assert-SetEqual -Expected $accountingDynamicFrames -Actual $partitionDynamicFrames `
    -Label 'Accounting dynamic frame records/partition'
Assert-Condition -Condition ((Get-StringSetSha256 -Values $accountingDynamicFrames) -eq
    [string]$accounting.framePartitions.dynamicExcludedFrameKeySetSha256) `
    -Message 'Post-build accounting dynamic-frame set hash changed.'

$accountingDynamicGroups = @($accounting.dynamicSkippedTextureGroups)
$accountingGroupKeys = New-Object 'System.Collections.Generic.HashSet[string]' ([StringComparer]::OrdinalIgnoreCase)
$groupExpandedFrames = New-Object 'System.Collections.Generic.HashSet[string]' ([StringComparer]::OrdinalIgnoreCase)
$reasonGroupCounts = @{}
$reasonFrameSets = @{}
foreach ($reason in $expectedDynamicReasons) {
    $reasonGroupCounts[$reason] = 0
    $reasonFrameSets[$reason] = New-Object 'System.Collections.Generic.HashSet[string]' ([StringComparer]::OrdinalIgnoreCase)
}
foreach ($group in $accountingDynamicGroups) {
    $reason = [string]$group.reason
    $groupKey = "$($group.componentId)|$($group.imgPath)|$($group.textureGroupId)"
    Assert-Condition -Condition ($expectedDynamicReasons.Contains($reason) -and $accountingGroupKeys.Add($groupKey)) `
        -Message "Invalid or duplicate accounting dynamic Texture group: $groupKey"
    Assert-Condition -Condition ($group.sourceCompressedSha256 -eq $group.outputCompressedSha256 -and
        $group.sourceDdsSha256 -eq $group.outputDdsSha256 -and
        $group.sourceBgraSha256 -eq $group.outputBgraSha256) `
        -Message "Accounting dynamic Texture group did not preserve source bytes: $groupKey"
    $reasonGroupCounts[$reason]++
    foreach ($frameKey in @($group.frameReferences)) {
        Assert-Condition -Condition ($accountingDynamicFrames.Contains([string]$frameKey) -and
            $groupExpandedFrames.Add([string]$frameKey) -and
            $reasonFrameSets[$reason].Add([string]$frameKey)) `
            -Message "Invalid or duplicate dynamic Texture frame reference: $groupKey/$frameKey"
        $frameRecord = $accountingDynamicFrameByKey[[string]$frameKey]
        Assert-Condition -Condition ($frameRecord.componentId -eq $group.componentId -and
            $frameRecord.reason -eq $reason -and
            [int]$frameRecord.textureGroupId -eq [int]$group.textureGroupId -and
            [int]$frameRecord.textureIndex -eq [int]$group.textureIndex) `
            -Message "Dynamic Texture/frame accounting mismatch: $groupKey/$frameKey"
    }
}
Assert-SetEqual -Expected $accountingDynamicFrames -Actual $groupExpandedFrames `
    -Label 'Accounting dynamic Texture groups/frame set'
Assert-Condition -Condition ($accountingDynamicGroups.Count -eq 70 -and
    $reasonGroupCounts['near-black'] -eq 18 -and $reasonFrameSets['near-black'].Count -eq 22 -and
    $reasonGroupCounts['no-visible-color-change'] -eq 16 -and $reasonFrameSets['no-visible-color-change'].Count -eq 16 -and
    $reasonGroupCounts['warm-visible-after-safe-bc-merge'] -eq 36 -and
    $reasonFrameSets['warm-visible-after-safe-bc-merge'].Count -eq 36) `
    -Message 'Dynamic exclusion reason accounting changed.'

$allowlistPath = Assert-FileSnapshot -RepoRoot $repoRoot -Snapshot $plan.evidence.proposedAllowlist -Label 'Proposed allowlist'
$scopeAuditPath = Assert-FileSnapshot -RepoRoot $repoRoot -Snapshot $plan.evidence.sourceScopeAudit -Label 'Source-scope audit'
$allowlist = Get-Content -LiteralPath $allowlistPath -Raw -Encoding UTF8 | ConvertFrom-Json
$scopeAudit = Get-Content -LiteralPath $scopeAuditPath -Raw -Encoding UTF8 | ConvertFrom-Json
foreach ($snapshot in @($plan.evidence.contractSnapshots)) {
    $snapshotPath = [string]$snapshot.path
    if ([IO.Path]::GetFileName($snapshotPath) -ieq 'manifest.json') {
        $manifestPath = Resolve-RepoPath -RepoRoot $repoRoot -Value $snapshotPath
        $manifestItem = Get-Item -LiteralPath $manifestPath
        $manifestHash = (Get-FileHash -LiteralPath $manifestPath -Algorithm SHA256).Hash
        if ($manifestItem.Length -eq [long]$snapshot.length -and
            $manifestHash -eq ([string]$snapshot.sha256).ToUpperInvariant()) {
            $null = Assert-FileSnapshot -RepoRoot $repoRoot -Snapshot $snapshot -Label "Contract $snapshotPath"
        }
        else {
            $manifest = Get-Content -LiteralPath $manifestPath -Raw -Encoding UTF8 | ConvertFrom-Json
            $release = $manifest.fullSkillRelease
            $transitionChecks = @(
                ([int]$manifest.schemaVersion -eq 1),
                (-not [string]::IsNullOrWhiteSpace([string]$manifest.profession)),
                ($manifest.coverage.fullSkillCoverageProven -eq $true),
                ($release.fullSkillCoverageProven -eq $true),
                ($release.status -eq 'offline-validated-client-pending'),
                ($release.deployment.authorized -eq $false),
                ($release.deployment.performed -eq $false)
            )
            $validReleaseTransition = @($transitionChecks | Where-Object { $_ -eq $false }).Count -eq 0
            Assert-Condition -Condition $validReleaseTransition `
                -Message "Profession manifest differs from its pre-release snapshot without a valid release transition: checks=$($transitionChecks -join ','), valid=$validReleaseTransition, schema=$($manifest.schemaVersion), profession=$($manifest.profession), topCoverage=$($manifest.coverage.fullSkillCoverageProven), releaseCoverage=$($release.fullSkillCoverageProven), status=$($release.status), authorized=$($release.deployment.authorized), performed=$($release.deployment.performed)."

            $manifestDirectory = Split-Path -Parent $manifestPath
            $currentPlanHash = (Get-FileHash -LiteralPath $planPath -Algorithm SHA256).Hash
            $releasePlanPath = Assert-FileSnapshot -RepoRoot $manifestDirectory -Snapshot $release.sourceEvidence.resourcePlan `
                -Label 'Post-release manifest resource plan'
            $releasePlanBindingChecks = @(
                ($releasePlanPath -eq $planPath),
                ([string]$release.sourceEvidence.resourcePlan.sha256 -eq $currentPlanHash),
                ($release.sourceEvidence.resourcePlan.fullSkillCoverageProvenAtValidationStart -eq $false)
            )
            $releasePlanBound = @($releasePlanBindingChecks | Where-Object { $_ -eq $false }).Count -eq 0
            Assert-Condition -Condition $releasePlanBound `
                -Message "Post-release manifest does not bind to this pre-release resource plan: checks=$($releasePlanBindingChecks -join ','), resolvedPath=$releasePlanPath, planPath=$planPath, snapshotSha=$($release.sourceEvidence.resourcePlan.sha256), planSha=$currentPlanHash, startCoverage=$($release.sourceEvidence.resourcePlan.fullSkillCoverageProvenAtValidationStart)."
            $null = Assert-FileSnapshot -RepoRoot $manifestDirectory -Snapshot $release.sourceEvidence.postBuildFrameAccounting `
                -Label 'Post-release manifest frame accounting'
            $artifactPath = Assert-FileSnapshot -RepoRoot $manifestDirectory -Snapshot $release.artifact `
                -Label 'Post-release manifest artifact'
            $packagePath = Assert-FileSnapshot -RepoRoot $manifestDirectory -Snapshot $release.packageSummary `
                -Label 'Post-release manifest package summary'
            $summaryPath = Assert-FileSnapshot -RepoRoot $manifestDirectory -Snapshot $release.validation.finalSummary `
                -Label 'Post-release manifest final summary'
            $summary = Get-Content -LiteralPath $summaryPath -Raw -Encoding UTF8 | ConvertFrom-Json
            $summaryChecks = @(
                ($summary.status -eq 'passed'),
                ($summary.validation.manifestScopeOfflineCoverage.eligibleForReleaseMetadataFullSkillCoverage -eq $true),
                ($summary.validation.manifestScopeOfflineCoverage.targetClientCompatibilityProven -eq $false),
                ($summary.resourcePlan.sha256 -eq $currentPlanHash),
                ($summary.finalArtifact.sha256 -eq [string]$release.artifact.sha256),
                ($summary.packageSummary.sha256 -eq [string]$release.packageSummary.sha256),
                ($summary.deployment.authorized -eq $false),
                ($summary.deployment.performed -eq $false)
            )
            $summaryAuthorizesTransition = @($summaryChecks | Where-Object { $_ -eq $false }).Count -eq 0
            Assert-Condition -Condition $summaryAuthorizesTransition `
                -Message "Post-release manifest final summary does not authorize the coverage transition: checks=$($summaryChecks -join ',')."

            $releaseReportPath = Resolve-ConfigPath -ConfigDirectory $manifestDirectory -Value ([string]$release.releaseReport)
            Assert-Condition -Condition (Test-Path -LiteralPath $releaseReportPath -PathType Leaf) `
                -Message 'Post-release manifest release report is missing.'
            $releaseReport = Get-Content -LiteralPath $releaseReportPath -Raw -Encoding UTF8 | ConvertFrom-Json
            $releaseReportBase = Split-Path -Parent $releaseReportPath
            $releaseArtifactPath = Resolve-ConfigPath -ConfigDirectory $releaseReportBase -Value ([string]$releaseReport.artifact.path)
            $releaseReportChecks = @(
                ($releaseReport.status -eq 'offline-validated-client-pending'),
                ($releaseReport.coverage.fullSkillCoverageProven -eq $true),
                ($releaseReport.coverage.clientCompatibilityProven -eq $false),
                ($releaseReport.deployment.authorized -eq $false),
                ($releaseReport.deployment.performed -eq $false),
                ($releaseArtifactPath -eq $artifactPath),
                ([long]$releaseReport.artifact.length -eq [long]$release.artifact.length),
                ($releaseReport.artifact.sha256 -eq [string]$release.artifact.sha256),
                ($releaseReport.validation.finalSummary.sha256 -eq [string]$release.validation.finalSummary.sha256)
            )
            $releaseReportConsistent = @($releaseReportChecks | Where-Object { $_ -eq $false }).Count -eq 0
            Assert-Condition -Condition $releaseReportConsistent `
                -Message "Post-release manifest and release.json are inconsistent: checks=$($releaseReportChecks -join ','), artifactPath=$artifactPath, packagePath=$packagePath, summaryPath=$summaryPath."
        }
    }
    else {
        $null = Assert-FileSnapshot -RepoRoot $repoRoot -Snapshot $snapshot -Label "Contract $snapshotPath"
    }
}
foreach ($snapshot in @($plan.evidence.builderSnapshots)) {
    $null = Assert-FileSnapshot -RepoRoot $repoRoot -Snapshot $snapshot -Label "Builder/config $($snapshot.path)"
}

$commonExact = Get-StringSet @(
    'sprite/character/swordman/effect/autoguard_ldodge.img',
    'sprite/character/swordman/effect/autoguard_none.img',
    'sprite/character/swordman/effect/momentaryslashblade.img',
    'sprite/character/swordman/effect/overdrive_part.img'
)
$structuralEntries = @($plan.hardExclusions.structuralRoundtripExcluded)
$noChangeEntries = @($plan.hardExclusions.noVisibleColorChangeExcluded)
$structuralRoundtripExcluded = Get-StringSet @($structuralEntries | ForEach-Object imgPath)
$noVisibleColorChangeExcluded = Get-StringSet @($noChangeEntries | ForEach-Object imgPath)
$expectedStructuralRoundtripExcluded = Get-StringSet @()
$expectedNoVisibleColorChangeExcluded = Get-StringSet @(
    'sprite/character/swordman/effect/chagecrashex/uppercircledodge.img',
    'sprite/character/swordman/effect/flowmindadvanced/longswordonebodytornatoan.img',
    'sprite/character/swordman/effect/flowmindadvanced/longswordonebodytornatobn.img',
    'sprite/character/swordman/effect/meteorsword/meteorsword_circle.img',
    'sprite/character/swordman/effect/swordofmind/dash.img',
    'sprite/character/swordman/effect/swordofmind/spin_eff.img'
)
Assert-SetEqual -Expected $expectedStructuralRoundtripExcluded -Actual $structuralRoundtripExcluded `
    -Label 'Structural round-trip exclusion set'
Assert-SetEqual -Expected $expectedNoVisibleColorChangeExcluded -Actual $noVisibleColorChangeExcluded `
    -Label 'No-visible-color-change exclusion set'

$stableRecoveries = @($plan.hardExclusions.stableOrderRecoveries)
$actualStableRecoveryPaths = Get-StringSet @($stableRecoveries.imgPath)
$expectedStableRecoveryPaths = Get-StringSet @(
    'sprite/character/swordman/effect/autoguard_none.img',
    'sprite/character/swordman/effect/illusionslash/finish/illusionslashsparkhead04.img',
    'sprite/character/swordman/effect/spritconversion/aura1.img',
    'sprite/character/swordman/effect/stateoflimit/state_of_limit_draw.img'
)
Assert-SetEqual -Expected $expectedStableRecoveryPaths -Actual $actualStableRecoveryPaths `
    -Label 'Stable-order recovered IMG set'
$stableHandlerSourcePath = Assert-FileSnapshot -RepoRoot $repoRoot -Snapshot $plan.evidence.stableFifthHandler.source `
    -Label 'StableFifthHandler source'
$null = Assert-FileSnapshot -RepoRoot $repoRoot -Snapshot $plan.evidence.stableFifthHandler.executable `
    -Label 'StableFifthHandler executable'
$stableValidationPath = Assert-FileSnapshot -RepoRoot $repoRoot -Snapshot $plan.evidence.stableFifthHandler.validationEvidence `
    -Label 'StableFifthHandler validation evidence'
Assert-Condition -Condition ($plan.evidence.stableFifthHandler.status -eq 'passed-real-out-of-order-texture-table-save-reopen-validation') `
    -Message 'StableFifthHandler validation status changed.'
Assert-Condition -Condition ($plan.evidence.stableFifthHandler.source.sha256 -eq 'C1DDBC0E2E5C31E2D078395B9DBACA65D996E1E60067650AA91FD392352EDAD6' -and $plan.evidence.stableFifthHandler.executable.sha256 -eq 'EB166E9F4221C578B214B5B443CFEE8C870EF22C22A7F97A0C2A0EAC9941BB97') `
    -Message 'StableFifthHandler tool identity changed.'
$stableHandlerSourceText = Get-Content -LiteralPath $stableHandlerSourcePath -Raw -Encoding UTF8
Assert-Condition -Condition ($stableHandlerSourceText.Contains('public sealed class StableFifthHandler') -and $stableHandlerSourceText.Contains('Handler.Regisity(ImgVersion.Ver5, typeof(StableFifthHandler));')) `
    -Message 'StableFifthHandler source registration changed.'
$stableValidation = Get-Content -LiteralPath $stableValidationPath -Raw -Encoding UTF8 | ConvertFrom-Json
Assert-Condition -Condition ([int]$stableValidation.schemaVersion -eq 1 -and $stableValidation.status -eq $plan.evidence.stableFifthHandler.status) `
    -Message 'StableFifthHandler validation evidence identity changed.'
Assert-Condition -Condition ($stableValidation.handler.name -eq 'StableFifthHandler' -and $stableValidation.handler.registration -eq 'Handler.Regisity(ImgVersion.Ver5, typeof(StableFifthHandler))') `
    -Message 'StableFifthHandler validation registration changed.'
foreach ($pair in @(
    @($stableValidation.handler.source, $plan.evidence.stableFifthHandler.source, 'source'),
    @($stableValidation.handler.executable, $plan.evidence.stableFifthHandler.executable, 'executable')
)) {
    $evidenceSnapshot = $pair[0]
    $planSnapshot = $pair[1]
    $label = [string]$pair[2]
    Assert-Condition -Condition ($evidenceSnapshot.path -eq $planSnapshot.path -and $evidenceSnapshot.sha256 -eq $planSnapshot.sha256) `
        -Message "StableFifthHandler $label evidence differs from the resource plan."
    $null = Assert-FileSnapshot -RepoRoot $repoRoot -Snapshot $evidenceSnapshot -Label "StableFifthHandler evidence $label"
}
foreach ($validator in @($stableValidation.validators.PSObject.Properties.Value)) {
    $null = Assert-FileSnapshot -RepoRoot $repoRoot -Snapshot $validator -Label "Stable-order validator $($validator.path)"
}
$metadataFields = Get-StringSet @($stableValidation.metadataFieldsCompared)
Assert-Condition -Condition ($metadataFields.Count -eq 22 -and $metadataFields.Count -eq @($stableValidation.metadataFieldsCompared).Count) `
    -Message 'Stable-order metadata field coverage changed.'
$stableCases = @($stableValidation.cases)
$stableCasePaths = Get-StringSet @($stableCases.imgPath)
Assert-SetEqual -Expected $expectedStableRecoveryPaths -Actual $stableCasePaths -Label 'Stable-order evidence IMG set'
$stableEvidenceSnapshotCount = 5
foreach ($case in $stableCases) {
    $recovery = @($stableRecoveries | Where-Object imgPath -eq $case.imgPath)
    Assert-Condition -Condition ($recovery.Count -eq 1 -and $case.componentId -eq $recovery[0].componentId) `
        -Message "Stable-order case identity mismatch: $($case.imgPath)"
    Assert-Condition -Condition ([int]$case.frameCount -eq [int]$recovery[0].frameCount -and $case.outOfFrameOrderTextureIndex -eq $true -and [int]$case.metadataDifferenceCount -eq 0) `
        -Message "Stable-order case result changed: $($case.imgPath)"
    Assert-Condition -Condition ((@($case.sourceFrameToTexture) -join ',') -eq (@($case.outputFrameToTexture) -join ',')) `
        -Message "Stable-order TextureIndex sequence changed: $($case.imgPath)"
    $componentPath = Assert-FileSnapshot -RepoRoot $repoRoot -Snapshot $case.component -Label "Stable-order component $($case.componentId)"
    $summaryPath = Assert-FileSnapshot -RepoRoot $repoRoot -Snapshot $case.buildSummary -Label "Stable-order summary $($case.componentId)"
    $summary = Get-Content -LiteralPath $summaryPath -Raw -Encoding UTF8 | ConvertFrom-Json
    Assert-Condition -Condition ($case.buildSummary.status -eq 'passed' -and $case.buildSummary.structureAndSharing -eq 'passed' -and $case.buildSummary.reopenedFromDisk -eq 'passed' -and $case.buildSummary.texdiagPerTexture -eq 'passed') `
        -Message "Stable-order summary gates changed: $($case.componentId)"
    Assert-Condition -Condition ($summary.status -eq 'passed' -and (Get-FileHash -LiteralPath $componentPath -Algorithm SHA256).Hash -eq $case.component.sha256) `
        -Message "Stable-order component/summary evidence changed: $($case.componentId)"
    Assert-Condition -Condition ($case.independentIndex.passed -eq $true -and $case.independentIndex.headerSha256Valid -eq $true -and [int]$case.independentIndex.entryCount -eq [int]$case.independentIndex.uniquePathCount -and [int]$case.independentIndex.imgMagicValidCount -eq [int]$case.independentIndex.entryCount) `
        -Message "Stable-order independent index result changed: $($case.componentId)"
    foreach ($snapshot in @(
        [pscustomobject]@{ path = $case.fullFrameValidation.albumInventoryPath; sha256 = $case.fullFrameValidation.albumInventorySha256 },
        [pscustomobject]@{ path = $case.fullFrameValidation.frameInventoryPath; sha256 = $case.fullFrameValidation.frameInventorySha256 },
        [pscustomobject]@{ path = $case.fullFrameValidation.sourceFrameInventoryPath; sha256 = $case.fullFrameValidation.sourceFrameInventorySha256 },
        [pscustomobject]@{ path = $case.fullFrameValidation.sheetPath; sha256 = $case.fullFrameValidation.sheetSha256 }
    )) {
        $null = Assert-FileSnapshot -RepoRoot $repoRoot -Snapshot $snapshot -Label "Stable-order full-frame evidence $($case.componentId)"
    }
    Assert-Condition -Condition ([int]$case.fullFrameValidation.decodedTargetFrames -eq [int]$case.frameCount) `
        -Message "Stable-order decoded frame count changed: $($case.componentId)"
    $stableEvidenceSnapshotCount += 6
}
Assert-Condition -Condition ($stableEvidenceSnapshotCount -eq 29) -Message 'Stable-order evidence snapshot coverage changed.'
Assert-Condition -Condition ([int]$stableValidation.totals.caseCount -eq 4 -and [int]$stableValidation.totals.outOfFrameOrderCaseCount -eq 4 -and [int]$stableValidation.totals.targetFrameCount -eq 55 -and [int]$stableValidation.totals.metadataFieldComparisons -eq 1210 -and [int]$stableValidation.totals.metadataDifferenceCount -eq 0 -and [int]$stableValidation.totals.decodedTargetFrameCount -eq 55 -and [int]$stableValidation.totals.independentIndexEntryCount -eq 16 -and [int]$stableValidation.totals.contactSheetCount -eq 4) `
    -Message 'Stable-order evidence totals changed.'
Assert-Condition -Condition ($stableValidation.deployment.authorized -eq $false -and $stableValidation.deployment.performed -eq $false) `
    -Message 'Stable-order evidence unexpectedly records deployment.'
foreach ($recovery in $stableRecoveries) {
    $inventoryEntry = @($allowlist.images | Where-Object path -eq $recovery.imgPath)
    Assert-Condition -Condition ($inventoryEntry.Count -eq 1 -and $recovery.handler -eq 'StableFifthHandler') `
        -Message "Invalid stable-order recovery: $($recovery.imgPath)"
    Assert-Condition -Condition ([int]$recovery.frameCount -eq [int]$inventoryEntry[0].frameCount -and $recovery.handlerSourceSha256 -eq $plan.evidence.stableFifthHandler.source.sha256 -and $recovery.handlerExecutableSha256 -eq $plan.evidence.stableFifthHandler.executable.sha256) `
        -Message "Stable-order recovery evidence mismatch: $($recovery.imgPath)"
}

$wholeImgGateExcluded = Get-StringSet @($structuralEntries + $noChangeEntries | ForEach-Object imgPath)
$wholeImgGateFrameCount = 0
foreach ($entry in @($structuralEntries + $noChangeEntries)) {
    $inventoryEntry = @($allowlist.images | Where-Object path -eq $entry.imgPath)
    Assert-Condition -Condition ($inventoryEntry.Count -eq 1) -Message "Gate exclusion is absent from allowlist: $($entry.imgPath)"
    $inventoryEntry = $inventoryEntry[0]
    Assert-Condition -Condition ($entry.technicalRoot -eq $inventoryEntry.root -and $entry.version -eq $inventoryEntry.version) `
        -Message "Gate exclusion root/version mismatch: $($entry.imgPath)"
    Assert-Condition -Condition ([int]$entry.frameCount -eq [int]$inventoryEntry.frameCount) `
        -Message "Gate exclusion frame count mismatch: $($entry.imgPath)"
    $wholeImgGateFrameCount += [int]$entry.frameCount

    $failureEvidencePath = Assert-FileSnapshot -RepoRoot $repoRoot -Snapshot $entry.failureEvidence `
        -Label "Gate rejection evidence $($entry.imgPath)"
    $failureEvidence = Get-Content -LiteralPath $failureEvidencePath -Raw -Encoding UTF8 | ConvertFrom-Json
    $evidencePaths = @()
    if ($failureEvidence.PSObject.Properties['rejectedImgPath']) {
        $evidencePaths += [string]$failureEvidence.rejectedImgPath
    }
    if ($failureEvidence.PSObject.Properties['rejectedImg']) {
        $evidencePaths += [string]$failureEvidence.rejectedImg.path
    }
    if ($failureEvidence.PSObject.Properties['failures']) {
        $evidencePaths += @($failureEvidence.failures.imgPath)
    }
    if ($failureEvidence.PSObject.Properties['failure']) {
        $evidencePaths += [string]$failureEvidence.failure.imgPath
    }
    Assert-Condition -Condition ($evidencePaths -contains [string]$entry.imgPath) `
        -Message "Gate rejection evidence does not contain IMG: $($entry.imgPath)"
    if ($entry.failureEvidence.kind -eq 'machine-readable-rejection') {
        $source = @($plan.sources | Where-Object id -eq $entry.componentId)
        Assert-Condition -Condition ($source.Count -eq 1 -and [int]$failureEvidence.schemaVersion -eq 1 -and $failureEvidence.status -eq 'rejected-hard-failure-no-output-preserved') `
            -Message "Machine-readable rejection identity changed: $($entry.imgPath)"
        Assert-Condition -Condition ($failureEvidence.componentId -eq $entry.componentId -and $failureEvidence.failure.imgPath -eq $entry.imgPath -and $failureEvidence.failure.type -eq 'no-visible-color-change') `
            -Message "Machine-readable rejection target changed: $($entry.imgPath)"
        Assert-Condition -Condition ($failureEvidence.attempt.builderSourceSha256 -eq $plan.evidence.stableFifthHandler.source.sha256 -and $failureEvidence.attempt.builderExecutableSha256 -eq $plan.evidence.stableFifthHandler.executable.sha256) `
            -Message "Machine-readable rejection builder identity changed: $($entry.imgPath)"
        Assert-Condition -Condition ($failureEvidence.source.path -eq $source[0].sourceNpk.path -and $failureEvidence.source.sha256 -eq $source[0].sourceNpk.sha256 -and [long]$failureEvidence.source.length -eq [long]$source[0].sourceNpk.length) `
            -Message "Machine-readable rejection source snapshot changed: $($entry.imgPath)"
        Assert-Condition -Condition ($failureEvidence.output.candidateNpkCreated -eq $false -and $failureEvidence.output.includedInRelease -eq $false -and $failureEvidence.deployment.performed -eq $false) `
            -Message "Machine-readable rejection unexpectedly created or released output: $($entry.imgPath)"
    }
    if ($failureEvidence.output.PSObject.Properties['created']) {
        Assert-Condition -Condition ($failureEvidence.output.created -eq $false) `
            -Message "Rejected gate evidence unexpectedly created output: $($entry.imgPath)"
    }
    if ($failureEvidence.output.PSObject.Properties['includedInRelease']) {
        Assert-Condition -Condition ($failureEvidence.output.includedInRelease -eq $false) `
            -Message "Rejected gate evidence unexpectedly entered release: $($entry.imgPath)"
    }
    if ($failureEvidence.output.PSObject.Properties['rejectedNpkPreserved']) {
        Assert-Condition -Condition ($failureEvidence.output.rejectedNpkPreserved -eq $false) `
            -Message "Rejected gate evidence unexpectedly preserved an NPK: $($entry.imgPath)"
    }
}

$postBuildFrameExclusions = @($plan.hardExclusions.postBuildFrameExclusions)
$actualPostBuildFrameKeys = Get-StringSet @($postBuildFrameExclusions.frameKey)
$expectedPostBuildFrameKeys = Get-StringSet @(
    'sprite/character/swordman/effect/chagecrashex/shockshapea.img#0',
    'sprite/character/swordman/effect/stateoflimit/tornadocloop.img#1'
)
Assert-SetEqual -Expected $expectedPostBuildFrameKeys -Actual $actualPostBuildFrameKeys `
    -Label 'Post-build preserving-source frame exclusions'
foreach ($entry in $postBuildFrameExclusions) {
    Assert-Condition -Condition ($entry.failureType -eq 'warm-visible-pixels-after-safe-bc-merge') `
        -Message "Unexpected post-build frame exclusion type: $($entry.frameKey)"
    Assert-Condition -Condition ($entry.frameKey -eq "$($entry.imgPath)#$($entry.frameIndex)") `
        -Message "Post-build frame exclusion key mismatch: $($entry.frameKey)"
    $failureEvidencePath = Assert-FileSnapshot -RepoRoot $repoRoot -Snapshot $entry.failureEvidence `
        -Label "Post-build frame rejection evidence $($entry.frameKey)"
    $failureEvidence = Get-Content -LiteralPath $failureEvidencePath -Raw -Encoding UTF8 | ConvertFrom-Json
    $matchedFailure = @($failureEvidence.failures | Where-Object {
        $_.imgPath -eq $entry.imgPath -and [int]$_.frame -eq [int]$entry.frameIndex
    })
    Assert-Condition -Condition ($matchedFailure.Count -eq 1 -and $matchedFailure[0].failureType -eq $entry.failureType) `
        -Message "Post-build frame rejection evidence mismatch: $($entry.frameKey)"
}

$ver5Candidates = @($allowlist.images | Where-Object {
    $_.root -ne 'atultimateblade' -and
    $_.version -eq 'Ver5' -and
    ([int]$_.genericAllowedFrameCount + [int]$_.specializedWeaponReviewFrameCount) -gt 0
})
$ver2Candidates = @($allowlist.images | Where-Object {
    $_.root -eq 'flowmindadvanced' -and
    $_.version -eq 'Ver2' -and
    [int]$_.pendingSameFormatFrameCount -gt 0
})
$selectedVer5 = @($ver5Candidates | Where-Object { -not $wholeImgGateExcluded.Contains([string]$_.path) })
$selectedVer2 = @($ver2Candidates | Where-Object { -not $wholeImgGateExcluded.Contains([string]$_.path) })

Assert-Condition -Condition (@($selectedVer5 | Where-Object root -eq 'atultimateblade').Count -eq 0) `
    -Message 'atultimateblade must be excluded in full.'
Assert-Condition -Condition (@($selectedVer5 | Where-Object { $_.classification -in @('character-risk', 'ui-risk', 'root-risk', 'shared-generic') }).Count -eq 0) `
    -Message 'Selected Ver5 set contains a character, UI, root-risk, or non-exclusive shared IMG.'
Assert-Condition -Condition (@($selectedVer5 | Where-Object version -eq 'Ver4').Count -eq 0) `
    -Message 'Selected set contains Ver4 IMG.'

$expectedCommonSelected = New-Object 'System.Collections.Generic.HashSet[string]' ([StringComparer]::OrdinalIgnoreCase)
foreach ($path in $commonExact) {
    if (-not $wholeImgGateExcluded.Contains($path)) {
        $null = $expectedCommonSelected.Add($path)
    }
}
$selectedCommon = Get-StringSet @($selectedVer5 | Where-Object root -eq 'common' | ForEach-Object path)
Assert-SetEqual -Expected $expectedCommonSelected -Actual $selectedCommon -Label 'Common final IMG allowlist'

foreach ($image in $selectedVer5) {
    $bucketTotal = [int]$image.genericAllowedFrameCount +
        [int]$image.specializedWeaponReviewFrameCount +
        [int]$image.hardExcludedFrameCount
    Assert-Condition -Condition ($bucketTotal -eq [int]$image.frameCount) `
        -Message "Selected Ver5 IMG bucket total changed: $($image.path)"
}
foreach ($image in $selectedVer2) {
    Assert-Condition -Condition ([int]$image.pendingSameFormatFrameCount -eq [int]$image.frameCount) `
        -Message "Selected Ver2 IMG is not wholly authorized for same-format recolor: $($image.path)"
}

$expectedVer5Roots = @($selectedVer5.root | Sort-Object -Unique)
Assert-Condition -Condition ($ver5Candidates.Count -eq 415) -Message "Unexpected candidate Ver5 IMG count: $($ver5Candidates.Count)/415"
Assert-Condition -Condition ($ver2Candidates.Count -eq 8 -and (($ver2Candidates | Measure-Object frameCount -Sum).Sum) -eq 47) `
    -Message 'Unexpected candidate Ver2 IMG/frame count.'
Assert-Condition -Condition ($expectedVer5Roots.Count -eq 28) -Message "Unexpected final Ver5 root count: $($expectedVer5Roots.Count)/28"
Assert-Condition -Condition ($selectedVer2.Count -eq 7) -Message "Unexpected final Ver2 IMG count: $($selectedVer2.Count)/7"
Assert-Condition -Condition ((($selectedVer2 | Measure-Object frameCount -Sum).Sum) -eq 42) -Message 'Unexpected final Ver2 frame count.'

$technicalRoots = @($plan.coverage.technicalRoots)
Assert-Condition -Condition ($technicalRoots.Count -eq 28) -Message 'Resource plan must contain 28 technical-root mappings.'
$expectedTechnicalRootNames = Get-StringSet @(
    @($scopeAudit.manifestReadyTechnicalRoots.technicalRoot) +
    @($scopeAudit.genericSwordmanBaseCandidates.technicalRoot) +
    @('common')
)
$actualTechnicalRootNames = Get-StringSet @($technicalRoots.technicalRoot)
Assert-SetEqual -Expected $expectedTechnicalRootNames -Actual $actualTechnicalRootNames -Label 'Technical-root coverage'
foreach ($root in $expectedTechnicalRootNames) {
    $actualMapping = @($technicalRoots | Where-Object technicalRoot -eq $root)
    Assert-Condition -Condition ($actualMapping.Count -eq 1) -Message "Missing or duplicate technical-root mapping: $root"
    $actualMapping = $actualMapping[0]
    if ($root -eq 'common') {
        $expectedCategory = 'shared-swordman-exact-img'
        $expectedReplaySkills = Get-StringSet @($scopeAudit.commonPackage.manifestReadyPaths.replaySkill | Sort-Object -Unique)
        $expectedIdentity = $true
    } else {
        $sourceMapping = @($scopeAudit.manifestReadyTechnicalRoots | Where-Object technicalRoot -eq $root)
        if ($sourceMapping.Count -eq 0) {
            $sourceMapping = @($scopeAudit.genericSwordmanBaseCandidates | Where-Object technicalRoot -eq $root)
        }
        Assert-Condition -Condition ($sourceMapping.Count -eq 1) -Message "Source-scope mapping changed: $root"
        $expectedCategory = [string]$sourceMapping[0].category
        $expectedReplaySkills = Get-StringSet @($sourceMapping[0].replaySkills)
        $expectedIdentity = [bool]$sourceMapping[0].resourceIdentityProven
    }
    Assert-Condition -Condition ($actualMapping.category -eq $expectedCategory) -Message "Technical-root category mismatch: $root"
    Assert-Condition -Condition ([bool]$actualMapping.resourceIdentityProven -eq $expectedIdentity) `
        -Message "Technical-root identity status mismatch: $root"
    $actualReplaySkills = Get-StringSet @($actualMapping.replaySkills)
    Assert-SetEqual -Expected $expectedReplaySkills -Actual $actualReplaySkills -Label "$root replay skills"
}
$expectedUnresolved = Get-StringSet @($scopeAudit.unresolved.replaySkill)
$actualUnresolved = Get-StringSet @($plan.coverage.unresolvedNoDedicatedVisualRoots.replaySkill)
Assert-SetEqual -Expected $expectedUnresolved -Actual $actualUnresolved -Label 'Unresolved/no-dedicated-visual roots'

$components = @($plan.components)
Assert-Condition -Condition ($components.Count -eq 31) -Message "Unexpected component count: $($components.Count)/31"
$componentIds = Get-StringSet @($components | ForEach-Object id)
Assert-Condition -Condition ($componentIds.Count -eq $components.Count) -Message 'Duplicate component ID in resource plan.'

$seenInternalPaths = New-Object 'System.Collections.Generic.HashSet[string]' ([StringComparer]::OrdinalIgnoreCase)
$actualConfigPaths = New-Object 'System.Collections.Generic.HashSet[string]' ([StringComparer]::OrdinalIgnoreCase)
$totalAllowedImgs = 0
$totalPreBuildAuthorizedFrames = 0
$totalEffectiveChangedFrames = 0
$totalExplicitExcludedFrames = 0
$totalDynamicPreservedFrames = 0
$totalSelectedFrames = 0
$globalChangedFrames = New-Object 'System.Collections.Generic.HashSet[string]' ([StringComparer]::OrdinalIgnoreCase)
$globalExplicitFrames = New-Object 'System.Collections.Generic.HashSet[string]' ([StringComparer]::OrdinalIgnoreCase)
$globalDynamicFrames = New-Object 'System.Collections.Generic.HashSet[string]' ([StringComparer]::OrdinalIgnoreCase)
$summaryEvidenceByComponent = @{}

$stableComponentIds = Get-StringSet @(
    'common-autoguard-none-stable',
    'illusionslash_finish-sparkhead04-stable',
    'spritconversion',
    'stateoflimit'
)
$ver5SeenPaths = New-Object 'System.Collections.Generic.HashSet[string]' ([StringComparer]::OrdinalIgnoreCase)
foreach ($root in $expectedVer5Roots) {
    $expectedComponentIds = if ($root -eq 'common') {
        @('common', 'common-autoguard-none-stable')
    } elseif ($root -eq 'illusionslash_finish') {
        @('illusionslash_finish', 'illusionslash_finish-sparkhead04-stable')
    } elseif ($root -eq 'flowmindadvanced') {
        @('flowmindadvanced-ver5')
    } else {
        @($root)
    }
    $rootSeenPaths = New-Object 'System.Collections.Generic.HashSet[string]' ([StringComparer]::OrdinalIgnoreCase)

    foreach ($componentId in $expectedComponentIds) {
        $component = @($components | Where-Object id -eq $componentId)
        Assert-Condition -Condition ($component.Count -eq 1) -Message "Missing or duplicate component: $componentId"
        $component = $component[0]
        $expectedHandler = if ($stableComponentIds.Contains($componentId)) {
            'ver5-dds-stable-order-preserving-recolor'
        } else {
            'ver5-dds-preserving-recolor'
        }
        Assert-Condition -Condition ($component.handler -eq $expectedHandler) -Message "Wrong handler for $componentId"
        Assert-Condition -Condition ($component.technicalRoot -eq $root -and $component.selectedForAggregation -eq $true) `
            -Message "Wrong technical root or aggregation selection for $componentId"

        $configPath = Resolve-RepoPath -RepoRoot $repoRoot -Value ([string]$component.configPath)
        Assert-Condition -Condition (Test-Path -LiteralPath $configPath -PathType Leaf) -Message "Config was not found: $configPath"
        $null = $actualConfigPaths.Add($configPath)
        $configDirectory = Split-Path -Parent $configPath
        $config = Get-Content -LiteralPath $configPath -Raw -Encoding UTF8 | ConvertFrom-Json
        Assert-Condition -Condition ($config.schemaVersion -eq 1 -and $config.themeId -eq $plan.themeId) `
            -Message "Config identity mismatch: $componentId"

        $plannedAllowed = Get-StringSet @($component.selectedImgPaths)
        $actualAllowed = Get-StringSet @($config.allowedImgPaths)
        Assert-Condition -Condition ($actualAllowed.Count -eq @($config.allowedImgPaths).Count) `
            -Message "Duplicate allowedImgPaths in $componentId"
        Assert-SetEqual -Expected $plannedAllowed -Actual $actualAllowed -Label "$componentId planned/config IMG paths"
        $images = @($selectedVer5 | Where-Object { $actualAllowed.Contains([string]$_.path) })
        Assert-Condition -Condition ($images.Count -eq $actualAllowed.Count -and @($images | Where-Object root -ne $root).Count -eq 0) `
            -Message "Component selected IMG scope mismatch: $componentId"

        $supplementalFrameKeys = @(
            $plan.hardExclusions.postBuildFrameExclusions |
                Where-Object { $actualAllowed.Contains([string]$_.imgPath) } |
                ForEach-Object frameKey
        )
        $baselineExcluded = Get-ExpectedExcludedFrameKeys -Images $images
        $expectedExcluded = Get-ExpectedExcludedFrameKeys -Images $images -SupplementalFrameKeys $supplementalFrameKeys
        $actualExcluded = Get-StringSet @($config.excludedFrameKeys)
        Assert-Condition -Condition ($actualExcluded.Count -eq @($config.excludedFrameKeys).Count) `
            -Message "Duplicate excludedFrameKeys in $componentId"
        Assert-SetEqual -Expected $expectedExcluded -Actual $actualExcluded -Label "$componentId excludedFrameKeys"

        foreach ($path in $actualAllowed) {
            $normalized = Get-NormalizedInternalPath $path
            Assert-Condition -Condition ($seenInternalPaths.Add($normalized)) -Message "Duplicate internal IMG across configs: $path"
            $null = $ver5SeenPaths.Add($path)
            $null = $rootSeenPaths.Add($path)
        }

        $source = @($plan.sources | Where-Object id -eq $component.sourceId)
        Assert-Condition -Condition ($source.Count -eq 1) -Message "Missing source snapshot for $componentId"
        $source = $source[0]
        $configSourcePath = Resolve-ConfigPath -ConfigDirectory $configDirectory -Value ([string]$config.sourceNpk.path)
        $planSourcePath = Resolve-RepoPath -RepoRoot $repoRoot -Value ([string]$source.sourceNpk.path)
        Assert-Condition -Condition ($configSourcePath -eq $planSourcePath) -Message "Config source path mismatch: $componentId"
        Assert-Condition -Condition (([string]$config.sourceNpk.sha256).ToUpperInvariant() -eq ([string]$source.sourceNpk.sha256).ToUpperInvariant()) `
            -Message "Config source SHA-256 mismatch: $componentId"
        Assert-Condition -Condition ([long]$config.sourceNpk.length -eq [long]$source.sourceNpk.length) `
            -Message "Config source length mismatch: $componentId"

        $outputPath = Resolve-ConfigPath -ConfigDirectory $configDirectory -Value ([string]$config.output.componentNpkPath)
        $summaryPath = Resolve-ConfigPath -ConfigDirectory $configDirectory -Value ([string]$config.output.buildSummaryPath)
        Assert-Condition -Condition ($outputPath -eq (Resolve-RepoPath -RepoRoot $repoRoot -Value ([string]$component.output.componentNpkPath))) `
            -Message "Component output path mismatch: $componentId"
        Assert-Condition -Condition ($summaryPath -eq (Resolve-RepoPath -RepoRoot $repoRoot -Value ([string]$component.output.buildSummaryPath))) `
            -Message "Build-summary path mismatch: $componentId"
        Assert-Condition -Condition ([IO.Path]::GetFileName($outputPath) -eq "weaponmaster-vergil-dark-blue-$componentId-v1.NPK") `
            -Message "Component filename is not stable: $componentId"

        Assert-Condition -Condition ($component.buildStatus -eq 'offline-validated-client-pending' -and
            $component.validatedArtifact.status -eq 'offline-validated-client-pending') `
            -Message "Component is not at the validated offline status: $componentId"
        $artifactComponentPath = Assert-FileSnapshot -RepoRoot $repoRoot `
            -Snapshot $component.validatedArtifact.componentNpk -Label "Validated component $componentId"
        $artifactSummaryPath = Assert-FileSnapshot -RepoRoot $repoRoot `
            -Snapshot $component.validatedArtifact.buildSummary -Label "Validated build summary $componentId"
        Assert-Condition -Condition ($artifactComponentPath -eq $outputPath -and $artifactSummaryPath -eq $summaryPath) `
            -Message "Validated artifact paths differ from the config: $componentId"
        $summary = Get-Content -LiteralPath $artifactSummaryPath -Raw -Encoding UTF8 | ConvertFrom-Json
        Assert-Condition -Condition ([int]$summary.schemaVersion -eq 1 -and $summary.status -eq 'passed' -and
            $summary.themeId -eq $plan.themeId -and $summary.deployment.performed -eq $false) `
            -Message "Build summary is not a non-deployed pass: $componentId"
        $summaryAllowed = Get-StringSet @($summary.selection.allowedImgPaths)
        $summaryExplicit = Get-StringSet @($summary.selection.explicitExcludedFrameKeys)
        Assert-SetEqual -Expected $actualAllowed -Actual $summaryAllowed -Label "$componentId config/summary IMG paths"
        Assert-SetEqual -Expected $actualExcluded -Actual $summaryExplicit -Label "$componentId config/summary explicit exclusions"
        Assert-Condition -Condition ([IO.Path]::GetFullPath([string]$summary.source.path) -eq $planSourcePath -and
            ([string]$summary.source.sha256).ToUpperInvariant() -eq ([string]$source.sourceNpk.sha256).ToUpperInvariant() -and
            [long]$summary.source.length -eq [long]$source.sourceNpk.length) `
            -Message "Build-summary source snapshot differs from the plan: $componentId"
        Assert-Condition -Condition ([IO.Path]::GetFullPath([string]$summary.output.componentNpkPath) -eq $outputPath -and
            [IO.Path]::GetFullPath([string]$summary.output.buildSummaryPath) -eq $summaryPath -and
            [long]$summary.output.length -eq [long]$component.validatedArtifact.componentNpk.length -and
            ([string]$summary.output.sha256).ToUpperInvariant() -eq
                ([string]$component.validatedArtifact.componentNpk.sha256).ToUpperInvariant()) `
            -Message "Build-summary output snapshot differs from the plan: $componentId"
        Assert-Condition -Condition ($summary.validation.reopenedFromDisk -eq 'passed' -and
            $summary.validation.structureAndSharing -eq 'passed' -and
            $summary.validation.ddsHeaders -eq 'byte-identical' -and
            $summary.validation.bc3AlphaBlocks -eq 'byte-identical where applicable' -and
            $summary.validation.bc1TransparentMode -eq 'preserved per block where applicable' -and
            $summary.validation.authorizedDecodedAlpha -eq 'byte-identical' -and
            $summary.validation.unauthorizedDecodedBgra -eq 'byte-identical' -and
            $summary.validation.texdiagPerTexture -eq 'passed') `
            -Message "Build-summary hard gates changed: $componentId"
        $partitions = Get-BuildSummaryFramePartitions -Summary $summary -ComponentId $componentId
        Assert-Condition -Condition ($partitions.Schema -eq 'textures') `
            -Message "Ver5 component did not use Texture accounting: $componentId"
        $expectedSelectedFrameKeys = New-Object 'System.Collections.Generic.HashSet[string]' ([StringComparer]::OrdinalIgnoreCase)
        foreach ($image in $images) {
            for ($frameIndex = 0; $frameIndex -lt [int]$image.frameCount; $frameIndex++) {
                Assert-Condition -Condition ($expectedSelectedFrameKeys.Add("$($image.path)#$frameIndex")) `
                    -Message "Duplicate expected selected frame key: $componentId/$($image.path)#$frameIndex"
            }
        }
        $actualSelectedFrameKeys = New-Object 'System.Collections.Generic.HashSet[string]' ([StringComparer]::OrdinalIgnoreCase)
        foreach ($frameKey in @($partitions.Changed) + @($partitions.Explicit) + @($partitions.Dynamic)) {
            Assert-Condition -Condition ($actualSelectedFrameKeys.Add([string]$frameKey)) `
                -Message "Duplicate actual selected frame key: $componentId/$frameKey"
        }
        Assert-SetEqual -Expected $expectedSelectedFrameKeys -Actual $actualSelectedFrameKeys `
            -Label "$componentId selected IMG frame universe"
        $summaryEvidenceByComponent[$componentId] = [pscustomobject]@{
            Summary = $summary
            Partitions = $partitions
            ComponentPath = $artifactComponentPath
            SummaryPath = $artifactSummaryPath
        }
        foreach ($frameKey in $partitions.Changed) {
            Assert-Condition -Condition (-not $globalExplicitFrames.Contains($frameKey) -and
                -not $globalDynamicFrames.Contains($frameKey) -and $globalChangedFrames.Add($frameKey)) `
                -Message "Duplicate or overlapping changed frame across components: $frameKey"
        }
        foreach ($frameKey in $partitions.Explicit) {
            Assert-Condition -Condition (-not $globalChangedFrames.Contains($frameKey) -and
                -not $globalDynamicFrames.Contains($frameKey) -and $globalExplicitFrames.Add($frameKey)) `
                -Message "Duplicate or overlapping explicit frame across components: $frameKey"
        }
        foreach ($frameKey in $partitions.Dynamic) {
            Assert-Condition -Condition (-not $globalChangedFrames.Contains($frameKey) -and
                -not $globalExplicitFrames.Contains($frameKey) -and $globalDynamicFrames.Add($frameKey)) `
                -Message "Duplicate or overlapping dynamic frame across components: $frameKey"
        }

        $postBuildExcludedFrameCount = $expectedExcluded.Count - $baselineExcluded.Count
        $preBuildAuthorizedFrames = (($images | Measure-Object genericAllowedFrameCount -Sum).Sum +
            ($images | Measure-Object specializedWeaponReviewFrameCount -Sum).Sum -
            $postBuildExcludedFrameCount)
        Assert-Condition -Condition ([int]$component.counts.allowedImgCount -eq $images.Count) -Message "Allowed IMG count mismatch: $componentId"
        Assert-Condition -Condition ([int]$component.counts.preBuildAuthorizedFrameCount -eq $preBuildAuthorizedFrames -and
            $preBuildAuthorizedFrames -eq $partitions.Changed.Count + $partitions.Dynamic.Count) `
            -Message "Pre-build authorized frame count mismatch: $componentId"
        Assert-Condition -Condition ([int]$component.counts.authorizedFrameCount -eq $partitions.Changed.Count) `
            -Message "Effective changed frame count mismatch: $componentId"
        Assert-Condition -Condition ([int]$component.counts.explicitExcludedFrameCount -eq $partitions.Explicit.Count -and
            $partitions.Explicit.Count -eq $expectedExcluded.Count) `
            -Message "Explicit excluded frame count mismatch: $componentId"
        Assert-Condition -Condition ([int]$component.counts.dynamicPreservedFrameCount -eq $partitions.Dynamic.Count) `
            -Message "Dynamic preserved frame count mismatch: $componentId"
        Assert-Condition -Condition ([int]$component.counts.excludedFrameCount -eq
            $partitions.Explicit.Count + $partitions.Dynamic.Count) `
            -Message "Total excluded frame count mismatch: $componentId"
        Assert-Condition -Condition ([int]$component.counts.selectedFrameCount -eq [int]$summary.counts.frames) `
            -Message "Selected frame count mismatch: $componentId"
        $totalAllowedImgs += $images.Count
        $totalPreBuildAuthorizedFrames += $preBuildAuthorizedFrames
        $totalEffectiveChangedFrames += $partitions.Changed.Count
        $totalExplicitExcludedFrames += $partitions.Explicit.Count
        $totalDynamicPreservedFrames += $partitions.Dynamic.Count
        $totalSelectedFrames += [int]$summary.counts.frames

        if ($componentId -in @('common', 'illusionslash_finish')) {
            Assert-Condition -Condition ($component.selectionRole -eq 'partial-primary-selected') `
                -Message "Partial component selection role changed: $componentId"
        }
    }

    $expectedRootPaths = Get-StringSet @($selectedVer5 | Where-Object root -eq $root | ForEach-Object path)
    Assert-SetEqual -Expected $expectedRootPaths -Actual $rootSeenPaths -Label "$root split-component union"
}
$expectedVer5Paths = Get-StringSet @($selectedVer5 | ForEach-Object path)
Assert-SetEqual -Expected $expectedVer5Paths -Actual $ver5SeenPaths -Label 'All Ver5 component IMG union'

$ver2Component = @($components | Where-Object id -eq 'flowmindadvanced-ver2')
Assert-Condition -Condition ($ver2Component.Count -eq 1) -Message 'Missing or duplicate flowmindadvanced-ver2 component.'
$ver2Component = $ver2Component[0]
Assert-Condition -Condition ($ver2Component.handler -eq 'ver2-argb-same-format-recolor') -Message 'Wrong Ver2 handler.'
$ver2ConfigPath = Resolve-RepoPath -RepoRoot $repoRoot -Value ([string]$ver2Component.configPath)
$null = $actualConfigPaths.Add($ver2ConfigPath)
$ver2ConfigDirectory = Split-Path -Parent $ver2ConfigPath
$ver2Config = Get-Content -LiteralPath $ver2ConfigPath -Raw -Encoding UTF8 | ConvertFrom-Json
Assert-Condition -Condition ($ver2Config.schemaVersion -eq 1 -and $ver2Config.themeId -eq $plan.themeId) `
    -Message 'Ver2 config identity mismatch.'
$expectedVer2Allowed = Get-StringSet @($selectedVer2 | ForEach-Object path)
$actualVer2Allowed = Get-StringSet @($ver2Config.allowedImgPaths)
Assert-SetEqual -Expected $expectedVer2Allowed -Actual $actualVer2Allowed -Label 'flowmindadvanced-ver2 allowedImgPaths'
$actualVer2ExcludedImgs = Get-StringSet @($ver2Config.excludedImgPaths)
$expectedVer2ExcludedImgs = Get-StringSet @($noChangeEntries | Where-Object version -eq 'Ver2' | ForEach-Object imgPath)
Assert-SetEqual -Expected $expectedVer2ExcludedImgs -Actual $actualVer2ExcludedImgs `
    -Label 'flowmindadvanced-ver2 excludedImgPaths'
Assert-Condition -Condition (@($ver2Config.excludedFrameKeys).Count -eq 0) -Message 'Ver2 config has unexpected frame exclusions.'
Assert-Condition -Condition ([int]$ver2Config.expectations.albumCount -eq 7 -and [int]$ver2Config.expectations.frameCount -eq 42) `
    -Message 'Ver2 config expectations changed.'
$ver2Source = @($plan.sources | Where-Object id -eq $ver2Component.sourceId)
Assert-Condition -Condition ($ver2Source.Count -eq 1) -Message 'Missing flowmindadvanced Ver2 source snapshot.'
$ver2Source = $ver2Source[0]
$ver2ConfigSourcePath = Resolve-ConfigPath -ConfigDirectory $ver2ConfigDirectory -Value ([string]$ver2Config.sourceNpk.path)
$ver2PlanSourcePath = Resolve-RepoPath -RepoRoot $repoRoot -Value ([string]$ver2Source.sourceNpk.path)
Assert-Condition -Condition ($ver2ConfigSourcePath -eq $ver2PlanSourcePath) -Message 'Ver2 source path mismatch.'
Assert-Condition -Condition (([string]$ver2Config.sourceNpk.sha256).ToUpperInvariant() -eq ([string]$ver2Source.sourceNpk.sha256).ToUpperInvariant()) `
    -Message 'Ver2 source SHA-256 mismatch.'
Assert-Condition -Condition ([long]$ver2Config.sourceNpk.length -eq [long]$ver2Source.sourceNpk.length) `
    -Message 'Ver2 source length mismatch.'
$ver2OutputPath = Resolve-ConfigPath -ConfigDirectory $ver2ConfigDirectory -Value ([string]$ver2Config.output.componentNpkPath)
$ver2SummaryPath = Resolve-ConfigPath -ConfigDirectory $ver2ConfigDirectory -Value ([string]$ver2Config.output.buildSummaryPath)
Assert-Condition -Condition ($ver2OutputPath -eq (Resolve-RepoPath -RepoRoot $repoRoot -Value ([string]$ver2Component.output.componentNpkPath))) `
    -Message 'Ver2 component output path mismatch.'
Assert-Condition -Condition ($ver2SummaryPath -eq (Resolve-RepoPath -RepoRoot $repoRoot -Value ([string]$ver2Component.output.buildSummaryPath))) `
    -Message 'Ver2 build-summary path mismatch.'
Assert-Condition -Condition ($ver2Component.buildStatus -eq 'offline-validated-client-pending' -and
    [int]$ver2Component.counts.allowedImgCount -eq 7 -and
    [int]$ver2Component.counts.preBuildAuthorizedFrameCount -eq 42 -and
    [int]$ver2Component.counts.authorizedFrameCount -eq 42 -and
    [int]$ver2Component.counts.explicitExcludedFrameCount -eq 0 -and
    [int]$ver2Component.counts.dynamicPreservedFrameCount -eq 0 -and
    [int]$ver2Component.counts.excludedFrameCount -eq 0 -and
    [int]$ver2Component.counts.selectedFrameCount -eq 42) `
    -Message 'Ver2 component plan counts changed.'
$ver2Artifact = $ver2Component.validatedArtifact
$ver2ArtifactPath = Assert-FileSnapshot -RepoRoot $repoRoot -Snapshot $ver2Artifact.componentNpk `
    -Label 'Validated Ver2 component'
$ver2BuildSummaryPath = Assert-FileSnapshot -RepoRoot $repoRoot -Snapshot $ver2Artifact.buildSummary `
    -Label 'Validated Ver2 build summary'
$ver2CrossValidationPath = Assert-FileSnapshot -RepoRoot $repoRoot -Snapshot $ver2Artifact.crossValidation `
    -Label 'Validated Ver2 cross-validation'
$ver2NegativeTestPath = Assert-FileSnapshot -RepoRoot $repoRoot -Snapshot $ver2Artifact.checkedZlibNegativeTest `
    -Label 'Validated Ver2 zlib negative test'
$ver2BuildSummary = Get-Content -LiteralPath $ver2BuildSummaryPath -Raw -Encoding UTF8 | ConvertFrom-Json
$ver2CrossValidation = Get-Content -LiteralPath $ver2CrossValidationPath -Raw -Encoding UTF8 | ConvertFrom-Json
$ver2NegativeTest = Get-Content -LiteralPath $ver2NegativeTestPath -Raw -Encoding UTF8 | ConvertFrom-Json
$ver2ArtifactHash = (Get-FileHash -LiteralPath $ver2ArtifactPath -Algorithm SHA256).Hash
Assert-Condition -Condition ($ver2ArtifactPath -eq $ver2OutputPath -and $ver2BuildSummaryPath -eq $ver2SummaryPath) `
    -Message 'Validated Ver2 artifact paths differ from the config.'
Assert-Condition -Condition ($ver2Artifact.status -eq 'offline-validated-client-pending' -and $ver2ArtifactHash -eq 'FEA3E88E41B4329ED81354D399E3365F9AA0A3229ED2E45024815801AD9B6F40') `
    -Message 'Validated Ver2 artifact identity changed.'
Assert-Condition -Condition ([int]$ver2BuildSummary.schemaVersion -eq 1 -and
    $ver2BuildSummary.status -eq 'passed' -and $ver2BuildSummary.themeId -eq $plan.themeId -and
    $ver2BuildSummary.deployment.performed -eq $false -and
    [int]$ver2BuildSummary.counts.albums -eq 7 -and [int]$ver2BuildSummary.counts.changedFrames -eq 42) `
    -Message 'Validated Ver2 build-summary counts changed.'
Assert-SetEqual -Expected $actualVer2Allowed -Actual (Get-StringSet @($ver2BuildSummary.selection.allowedImgPaths)) `
    -Label 'flowmindadvanced-ver2 config/summary IMG paths'
Assert-Condition -Condition (@($ver2BuildSummary.selection.explicitExcludedFrameKeys).Count -eq 0 -and
    [IO.Path]::GetFullPath([string]$ver2BuildSummary.source.path) -eq $ver2PlanSourcePath -and
    ([string]$ver2BuildSummary.source.sha256).ToUpperInvariant() -eq
        ([string]$ver2Source.sourceNpk.sha256).ToUpperInvariant() -and
    [long]$ver2BuildSummary.source.length -eq [long]$ver2Source.sourceNpk.length) `
    -Message 'Validated Ver2 summary selection/source snapshot changed.'
Assert-Condition -Condition ([IO.Path]::GetFullPath([string]$ver2BuildSummary.output.componentNpkPath) -eq $ver2OutputPath -and
    [IO.Path]::GetFullPath([string]$ver2BuildSummary.output.buildSummaryPath) -eq $ver2SummaryPath -and
    [long]$ver2BuildSummary.output.length -eq [long]$ver2Artifact.componentNpk.length -and
    ([string]$ver2BuildSummary.output.sha256).ToUpperInvariant() -eq
        ([string]$ver2Artifact.componentNpk.sha256).ToUpperInvariant()) `
    -Message 'Validated Ver2 summary output snapshot changed.'
Assert-Condition -Condition ($ver2BuildSummary.validation.authorizedDecodedAlpha -eq 'byte-identical' -and $ver2BuildSummary.validation.authorizedVisibleNearBlackRgb -eq 'byte-identical') `
    -Message 'Validated Ver2 alpha/near-black gates changed.'
Assert-Condition -Condition ($ver2CrossValidation.status -eq 'passed' -and $ver2CrossValidation.output.sha256 -eq $ver2ArtifactHash -and [int]$ver2CrossValidation.frames.metadataComparisons -eq 924 -and [int]$ver2CrossValidation.pixels.pixelFailureCount -eq 0) `
    -Message 'Validated Ver2 cross-validation changed.'
Assert-Condition -Condition ($ver2NegativeTest.status -eq 'passed' -and $ver2NegativeTest.test -eq 'corrupt-zlib-payload-must-fail') `
    -Message 'Validated Ver2 zlib negative test changed.'
$ver2Partitions = Get-BuildSummaryFramePartitions -Summary $ver2BuildSummary -ComponentId 'flowmindadvanced-ver2'
Assert-Condition -Condition ($ver2Partitions.Schema -eq 'frames' -and $ver2Partitions.Changed.Count -eq 42 -and
    $ver2Partitions.Explicit.Count -eq 0 -and $ver2Partitions.Dynamic.Count -eq 0) `
    -Message 'Validated Ver2 frame partition changed.'
$expectedVer2FrameKeys = New-Object 'System.Collections.Generic.HashSet[string]' ([StringComparer]::OrdinalIgnoreCase)
foreach ($image in $selectedVer2) {
    for ($frameIndex = 0; $frameIndex -lt [int]$image.frameCount; $frameIndex++) {
        Assert-Condition -Condition ($expectedVer2FrameKeys.Add("$($image.path)#$frameIndex")) `
            -Message "Duplicate expected Ver2 selected frame key: $($image.path)#$frameIndex"
    }
}
$actualVer2FrameKeys = New-Object 'System.Collections.Generic.HashSet[string]' ([StringComparer]::OrdinalIgnoreCase)
foreach ($frameKey in @($ver2Partitions.Changed) + @($ver2Partitions.Explicit) + @($ver2Partitions.Dynamic)) {
    Assert-Condition -Condition ($actualVer2FrameKeys.Add([string]$frameKey)) `
        -Message "Duplicate actual Ver2 selected frame key: $frameKey"
}
Assert-SetEqual -Expected $expectedVer2FrameKeys -Actual $actualVer2FrameKeys `
    -Label 'flowmindadvanced-ver2 selected IMG frame universe'
$summaryEvidenceByComponent['flowmindadvanced-ver2'] = [pscustomobject]@{
    Summary = $ver2BuildSummary
    Partitions = $ver2Partitions
    ComponentPath = $ver2ArtifactPath
    SummaryPath = $ver2BuildSummaryPath
}
foreach ($frameKey in $ver2Partitions.Changed) {
    Assert-Condition -Condition (-not $globalExplicitFrames.Contains($frameKey) -and
        -not $globalDynamicFrames.Contains($frameKey) -and $globalChangedFrames.Add($frameKey)) `
        -Message "Duplicate or overlapping changed frame across components: $frameKey"
}
foreach ($path in $actualVer2Allowed) {
    $normalized = Get-NormalizedInternalPath $path
    Assert-Condition -Condition ($seenInternalPaths.Add($normalized)) -Message "Duplicate internal IMG across configs: $path"
}
$totalAllowedImgs += $selectedVer2.Count
$totalPreBuildAuthorizedFrames += ($selectedVer2 | Measure-Object pendingSameFormatFrameCount -Sum).Sum
$totalEffectiveChangedFrames += $ver2Partitions.Changed.Count
$totalSelectedFrames += [int]$ver2BuildSummary.counts.frames

Assert-Condition -Condition ($summaryEvidenceByComponent.Count -eq 31) `
    -Message "Validated component summary coverage changed: $($summaryEvidenceByComponent.Count)/31"
$derivedDynamicComponentIds = Get-StringSet @(
    $summaryEvidenceByComponent.GetEnumerator() |
        Where-Object { $_.Value.Partitions.Dynamic.Count -gt 0 } |
        ForEach-Object Key
)
$accountingDynamicComponentIds = Get-StringSet @($accounting.components | ForEach-Object componentId)
Assert-Condition -Condition ($accountingDynamicComponentIds.Count -eq @($accounting.components).Count -and
    $accountingDynamicComponentIds.Count -eq 12 -and
    [int]$accounting.totals.dynamicComponentCount -eq $derivedDynamicComponentIds.Count) `
    -Message 'Post-build accounting contains duplicate dynamic component records.'
Assert-SetEqual -Expected $derivedDynamicComponentIds -Actual $accountingDynamicComponentIds `
    -Label 'Dynamic component evidence set'
foreach ($componentEvidence in @($accounting.components)) {
    $componentId = [string]$componentEvidence.componentId
    $component = @($components | Where-Object id -eq $componentId)
    Assert-Condition -Condition ($component.Count -eq 1) `
        -Message "Accounting references an unknown component: $componentId"
    $component = $component[0]
    $summaryEvidence = $summaryEvidenceByComponent[$componentId]
    $actualDynamicTextureGroupCount = if ($summaryEvidence.Summary.PSObject.Properties['textures']) {
        @($summaryEvidence.Summary.textures | Where-Object {
            $_.decision -eq 'skipped' -and $_.skipReason -ne 'explicit-excluded-reference'
        }).Count
    } else { 0 }
    Assert-Condition -Condition ($componentEvidence.imgVersion -eq $component.imgVersion -and
        [int]$componentEvidence.selectedImgCount -eq @($summaryEvidence.Summary.selection.allowedImgPaths).Count -and
        [int]$componentEvidence.frameCount -eq [int]$summaryEvidence.Summary.counts.frames -and
        [int]$componentEvidence.changedFrameReferenceCount -eq $summaryEvidence.Partitions.Changed.Count -and
        [int]$componentEvidence.explicitExcludedFrameReferenceCount -eq $summaryEvidence.Partitions.Explicit.Count -and
        [int]$componentEvidence.dynamicExcludedFrameReferenceCount -eq $summaryEvidence.Partitions.Dynamic.Count -and
        [int]$componentEvidence.dynamicSkippedTextureGroupCount -eq $actualDynamicTextureGroupCount) `
        -Message "Accounting component totals differ from its summary: $componentId"
    Assert-Condition -Condition ($componentEvidence.buildSummary.kind -eq 'passed-build-summary' -and
        $componentEvidence.buildSummary.path -eq $component.validatedArtifact.buildSummary.path -and
        [long]$componentEvidence.buildSummary.length -eq [long]$component.validatedArtifact.buildSummary.length -and
        $componentEvidence.buildSummary.sha256 -eq $component.validatedArtifact.buildSummary.sha256 -and
        $componentEvidence.componentNpk.kind -eq 'passed-component-npk' -and
        $componentEvidence.componentNpk.path -eq $component.validatedArtifact.componentNpk.path -and
        [long]$componentEvidence.componentNpk.length -eq [long]$component.validatedArtifact.componentNpk.length -and
        $componentEvidence.componentNpk.sha256 -eq $component.validatedArtifact.componentNpk.sha256) `
        -Message "Accounting component snapshots differ from the resource plan: $componentId"
    $null = Assert-FileSnapshot -RepoRoot $repoRoot -Snapshot $componentEvidence.buildSummary `
        -Label "Accounting build summary $componentId"
    $null = Assert-FileSnapshot -RepoRoot $repoRoot -Snapshot $componentEvidence.componentNpk `
        -Label "Accounting component NPK $componentId"
}

$derivedDynamicGroupKeys = New-Object 'System.Collections.Generic.HashSet[string]' ([StringComparer]::OrdinalIgnoreCase)
foreach ($entry in $summaryEvidenceByComponent.GetEnumerator()) {
    $componentId = [string]$entry.Key
    $summary = $entry.Value.Summary
    if (-not $summary.PSObject.Properties['textures']) { continue }
    foreach ($texture in @($summary.textures | Where-Object {
        $_.decision -eq 'skipped' -and $_.skipReason -ne 'explicit-excluded-reference'
    })) {
        $groupKey = "$componentId|$($texture.imgPath)|$($texture.textureGroupId)"
        Assert-Condition -Condition ($derivedDynamicGroupKeys.Add($groupKey)) `
            -Message "Duplicate dynamic Texture group in summaries: $groupKey"
    }
}
Assert-SetEqual -Expected $derivedDynamicGroupKeys -Actual $accountingGroupKeys `
    -Label 'Summary/accounting dynamic Texture groups'
foreach ($group in $accountingDynamicGroups) {
    $summary = $summaryEvidenceByComponent[[string]$group.componentId].Summary
    $record = @($summary.textures | Where-Object {
        $_.imgPath -eq $group.imgPath -and [int]$_.textureGroupId -eq [int]$group.textureGroupId
    })
    Assert-Condition -Condition ($record.Count -eq 1) `
        -Message "Accounting dynamic Texture group is absent from its summary: $($group.componentId)/$($group.imgPath)/$($group.textureGroupId)"
    $record = $record[0]
    Assert-Condition -Condition ($record.decision -eq 'skipped' -and $record.skipReason -eq $group.reason -and
        [int]$record.textureIndex -eq [int]$group.textureIndex -and $record.format -eq $group.format -and
        $record.sourceCompressedSha256 -eq $group.sourceCompressedSha256 -and
        $record.outputCompressedSha256 -eq $group.outputCompressedSha256 -and
        $record.sourceDdsSha256 -eq $group.sourceDdsSha256 -and
        $record.outputDdsSha256 -eq $group.outputDdsSha256 -and
        $record.sourceBgraSha256 -eq $group.sourceBgraSha256 -and
        $record.outputBgraSha256 -eq $group.outputBgraSha256) `
        -Message "Accounting dynamic Texture evidence differs from its summary: $($group.componentId)/$($group.imgPath)/$($group.textureGroupId)"
    Assert-SetEqual -Expected (Get-StringSet @($record.frameReferences)) `
        -Actual (Get-StringSet @($group.frameReferences)) `
        -Label "Accounting dynamic Texture frame references $($group.componentId)/$($group.textureGroupId)"
}

Assert-SetEqual -Expected $globalDynamicFrames -Actual $accountingDynamicFrames `
    -Label 'Summary/accounting dynamic frame partition'
Assert-Condition -Condition ($globalChangedFrames.Count -eq [int]$accounting.framePartitions.changedFrameKeyCount -and
    (Get-StringSetSha256 -Values $globalChangedFrames) -eq [string]$accounting.framePartitions.changedFrameKeySetSha256 -and
    $globalExplicitFrames.Count -eq [int]$accounting.framePartitions.explicitExcludedFrameKeyCount -and
    (Get-StringSetSha256 -Values $globalExplicitFrames) -eq [string]$accounting.framePartitions.explicitExcludedFrameKeySetSha256 -and
    (Get-StringSetSha256 -Values $globalDynamicFrames) -eq [string]$accounting.framePartitions.dynamicExcludedFrameKeySetSha256) `
    -Message 'Summary-derived frame partition hashes differ from post-build accounting.'

$configDirectory = Split-Path -Parent $planPath
$diskConfigPaths = @(
    Get-ChildItem -LiteralPath $configDirectory -Filter '*.json' -File |
        Where-Object Name -notlike 'resource-plan*.json' |
        ForEach-Object FullName
)
$diskConfigSet = Get-StringSet $diskConfigPaths
Assert-SetEqual -Expected $actualConfigPaths -Actual $diskConfigSet -Label 'Static config file set'

$reuseComponents = @($plan.reuseComponents)
Assert-Condition -Condition ($reuseComponents.Count -eq 1) -Message 'Exactly one validated reuse component is required.'
$cutin = $reuseComponents[0]
Assert-Condition -Condition ($cutin.id -eq 'cutin-weaponmaster-neo-v2') -Message 'Unexpected reuse component ID.'
Assert-Condition -Condition ($cutin.mode -eq 'validated-img-payload-reuse') -Message 'Cut-in must use validated IMG payload reuse mode.'
$cutinComponentPath = Assert-FileSnapshot -RepoRoot $repoRoot -Snapshot $cutin.sourceComponent -Label 'Cut-in v2 source component'
$cutinReleasePath = Assert-FileSnapshot -RepoRoot $repoRoot -Snapshot $cutin.releaseEvidence -Label 'Cut-in v2 release evidence'
$cutinSelected = Get-StringSet @($cutin.selectedImgPaths)
$expectedCutinSelected = Get-StringSet @('sprite/character/swordman/effect/cutin/cutin_weaponmaster_neo.img')
Assert-SetEqual -Expected $expectedCutinSelected -Actual $cutinSelected -Label 'Cut-in selected IMG payload'
foreach ($path in $cutinSelected) {
    $normalized = Get-NormalizedInternalPath $path
    Assert-Condition -Condition ($seenInternalPaths.Add($normalized)) -Message "Duplicate internal IMG across configs/reuse components: $path"
}
$cutinRelease = Get-Content -LiteralPath $cutinReleasePath -Raw -Encoding UTF8 | ConvertFrom-Json
$cutinHash = (Get-FileHash -LiteralPath $cutinComponentPath -Algorithm SHA256).Hash
Assert-Condition -Condition ($cutinHash -eq '3590860BB32C5C69B5E92E4D83B3C743AF952463C94D3C5EAAAFB01B47919D88') `
    -Message 'Cut-in v2 reusable component hash changed.'
Assert-Condition -Condition (([string]$cutinRelease.outputNpk.sha256).ToUpperInvariant() -eq $cutinHash) `
    -Message 'Cut-in release output hash does not match the reusable component.'
Assert-Condition -Condition ($cutinRelease.target.img -eq 'sprite/character/swordman/effect/cutin/cutin_weaponmaster_neo.img') `
    -Message 'Cut-in release target IMG changed.'
Assert-Condition -Condition (@($cutinRelease.target.changedFrames).Count -eq 24 -and @($cutinRelease.target.preservedTransparentFrames).Count -eq 3) `
    -Message 'Cut-in release frame evidence changed.'
Assert-Condition -Condition ($cutinRelease.validation.independentIndex -eq 'passed' -and [int]$cutinRelease.validation.metadataDiffCount -eq 0) `
    -Message 'Cut-in release evidence does not report required validation gates.'
Assert-Condition -Condition ($cutinRelease.deployment.authorized -eq $false -and $cutinRelease.deployment.performed -eq $false) `
    -Message 'Cut-in release unexpectedly records deployment authorization.'
Assert-Condition -Condition ($cutin.baselinePolicy.installedImagePacks2IsOfficialBaseline -eq $false -and $cutin.baselinePolicy.useInstalledPackageAsBuildSource -eq $false) `
    -Message 'Cut-in plan must not treat the installed customized package as an official baseline or build source.'

$sourceIds = Get-StringSet @($plan.sources | ForEach-Object id)
Assert-Condition -Condition ($sourceIds.Count -eq 28 -and $sourceIds.Count -eq @($plan.sources).Count) `
    -Message 'Resource plan must contain 28 unique live source snapshots.'
foreach ($source in @($plan.sources)) {
    $null = Assert-FileSnapshot -RepoRoot $repoRoot -Snapshot $source.sourceNpk -Label "Source NPK $($source.id)"
    $evidenceKinds = Get-StringSet @($source.inventoryEvidence.files | ForEach-Object kind)
    foreach ($requiredKind in @('album-inventory', 'frame-inventory', 'pixel-state')) {
        Assert-Condition -Condition ($evidenceKinds.Contains($requiredKind)) `
            -Message "Source $($source.id) lacks $requiredKind evidence."
    }
    foreach ($file in @($source.inventoryEvidence.files)) {
        $null = Assert-FileSnapshot -RepoRoot $repoRoot -Snapshot $file -Label "Inventory evidence $($source.id)/$($file.kind)"
    }
    foreach ($sheet in @($source.inventoryEvidence.contactSheets)) {
        $null = Assert-FileSnapshot -RepoRoot $repoRoot -Snapshot $sheet -Label "Contact sheet $($source.id)"
    }
    $contactSheetPaths = @($source.inventoryEvidence.contactSheetPaths)
    Assert-Condition -Condition ($contactSheetPaths.Count -gt 0) -Message "Source $($source.id) lacks contact-sheet evidence."
    foreach ($sheetPath in $contactSheetPaths) {
        $resolvedSheetPath = Resolve-RepoPath -RepoRoot $repoRoot -Value ([string]$sheetPath)
        Assert-Condition -Condition (Test-Path -LiteralPath $resolvedSheetPath -PathType Leaf) `
            -Message "Contact-sheet evidence was not found: $resolvedSheetPath"
    }
}

Assert-Condition -Condition ([int]$plan.totals.sourceCount -eq 28) -Message 'Plan sourceCount mismatch.'
Assert-Condition -Condition ([int]$plan.totals.configCount -eq 31) -Message 'Plan configCount mismatch.'
Assert-Condition -Condition ([int]$plan.totals.allowedImgCount -eq $totalAllowedImgs) -Message 'Plan allowedImgCount mismatch.'
Assert-Condition -Condition ([int]$plan.totals.ver5PreBuildAuthorizedFrameCount -eq 3625 -and
    [int]$plan.totals.ver2PreBuildAuthorizedFrameCount -eq 42 -and
    [int]$plan.totals.preBuildAuthorizedFrameCount -eq $totalPreBuildAuthorizedFrames -and
    $totalPreBuildAuthorizedFrames -eq 3667) `
    -Message 'Plan pre-build authorized frame totals changed.'
Assert-Condition -Condition ([int]$plan.totals.ver5AuthorizedFrameCount -eq 3551 -and
    [int]$plan.totals.ver2AuthorizedFrameCount -eq 42 -and
    [int]$plan.totals.authorizedFrameCount -eq $totalEffectiveChangedFrames -and
    $totalEffectiveChangedFrames -eq 3593) `
    -Message 'Plan effective changed frame totals changed.'
Assert-Condition -Condition ([int]$plan.totals.explicitExcludedFrameCount -eq $totalExplicitExcludedFrames -and
    $totalExplicitExcludedFrames -eq 128 -and
    [int]$plan.totals.dynamicPreservedFrameCount -eq $totalDynamicPreservedFrames -and
    $totalDynamicPreservedFrames -eq 74 -and
    [int]$plan.totals.excludedFrameCount -eq $totalExplicitExcludedFrames + $totalDynamicPreservedFrames -and
    [int]$plan.totals.excludedFrameCount -eq 202 -and
    [int]$plan.totals.selectedFrameCount -eq $totalSelectedFrames -and $totalSelectedFrames -eq 3795) `
    -Message 'Plan post-build frame partition totals changed.'
Assert-Condition -Condition ([int]$plan.totals.postBuildFrameExcludedCount -eq $postBuildFrameExclusions.Count) `
    -Message 'Plan post-build frame exclusion count mismatch.'
Assert-Condition -Condition ([int]$plan.totals.wholeImgGateExcludedImgCount -eq $wholeImgGateExcluded.Count) `
    -Message 'Plan whole-IMG gate exclusion count mismatch.'
Assert-Condition -Condition ([int]$plan.totals.wholeImgGateExcludedFrameCount -eq $wholeImgGateFrameCount) `
    -Message 'Plan whole-IMG excluded frame count mismatch.'
Assert-Condition -Condition ([int]$plan.totals.candidatePoolExcludedFrameCount -eq
    ($totalExplicitExcludedFrames + $totalDynamicPreservedFrames + $wholeImgGateFrameCount) -and
    [int]$plan.totals.candidatePoolExcludedFrameCount -eq 221) `
    -Message 'Plan candidate-pool excluded frame count mismatch.'
Assert-Condition -Condition ([int]$plan.totals.reuseComponentCount -eq 1 -and [int]$plan.totals.reuseSelectedImgCount -eq 1) `
    -Message 'Plan reuse-component totals mismatch.'
Assert-Condition -Condition ([int]$plan.totals.reuseChangedFrameCount -eq 24 -and
    [int]$plan.totals.reusePreservedFrameCount -eq 3) `
    -Message 'Plan reuse-component frame totals mismatch.'
Assert-Condition -Condition ([int]$plan.totals.finalAggregateSelectedImgCount -eq ($totalAllowedImgs + 1)) `
    -Message 'Plan final aggregate IMG count mismatch.'
Assert-Condition -Condition ([int]$plan.totals.finalPreBuildAuthorizedChangedFrameCount -eq 3691 -and
    [int]$plan.totals.finalAuthorizedChangedFrameCount -eq 3617 -and
    [int]$plan.totals.finalSelectedFrameCount -eq 3822 -and
    [int]$plan.totals.finalPreservedFrameCount -eq 205) `
    -Message 'Plan final aggregate frame totals changed.'

[pscustomobject]@{
    Status = 'passed'
    ResourcePlan = $planPath
    SourceCount = @($plan.sources).Count
    ConfigCount = $components.Count
    AllowedImgCount = $totalAllowedImgs
    PreBuildAuthorizedFrameCount = $totalPreBuildAuthorizedFrames
    EffectiveChangedFrameCount = $totalEffectiveChangedFrames
    ExplicitExcludedFrameKeyCount = $totalExplicitExcludedFrames
    DynamicPreservedFrameKeyCount = $totalDynamicPreservedFrames
    SelectedFrameCount = $totalSelectedFrames
    WholeImgGateExcludedImgCount = $wholeImgGateExcluded.Count
    WholeImgGateExcludedFrameCount = $wholeImgGateFrameCount
    CandidatePoolExcludedFrameCount = $totalExplicitExcludedFrames + $totalDynamicPreservedFrames + $wholeImgGateFrameCount
    StableOrderRecoveryCount = $stableRecoveries.Count
    ReuseComponentCount = 1
    ReuseSelectedImgCount = 1
    ReuseChangedFrameCount = 24
    FinalAggregateSelectedImgCount = $totalAllowedImgs + 1
    FinalEffectiveChangedFrameCount = 3617
    FinalSelectedFrameCount = 3822
    FinalPreservedFrameCount = 205
    DuplicateInternalImgCount = 0
    CharacterOrUiImgCount = 0
    Deployment = 'not-authorized-not-performed'
    FullSkillCoverageProven = $false
} | ConvertTo-Json -Depth 4

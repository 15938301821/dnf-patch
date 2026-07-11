[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)]
    [string]$ResourcePlanPath,

    [Parameter(Mandatory = $true)]
    [string]$AccountingPath
)

$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest

function Assert-Condition {
    param([bool]$Condition, [string]$Message)
    if (-not $Condition) { throw $Message }
}

function Resolve-RepoPath {
    param([string]$RepoRoot, [string]$Value)
    $native = $Value.Replace('/', [IO.Path]::DirectorySeparatorChar)
    if (-not [IO.Path]::IsPathRooted($native)) { $native = Join-Path $RepoRoot $native }
    return [IO.Path]::GetFullPath($native)
}

function Get-RepoRelativePath {
    param([string]$RepoRoot, [string]$Path)
    $root = [IO.Path]::GetFullPath($RepoRoot).TrimEnd(
        [IO.Path]::DirectorySeparatorChar,
        [IO.Path]::AltDirectorySeparatorChar) + [IO.Path]::DirectorySeparatorChar
    $rootUri = New-Object Uri $root
    $pathUri = New-Object Uri ([IO.Path]::GetFullPath($Path))
    return [Uri]::UnescapeDataString($rootUri.MakeRelativeUri($pathUri).ToString()).Replace('\', '/')
}

function Get-FileSnapshot {
    param([string]$RepoRoot, [string]$Path, [string]$Kind)
    $item = Get-Item -LiteralPath $Path
    return [pscustomobject][ordered]@{
        kind = $Kind
        path = Get-RepoRelativePath -RepoRoot $RepoRoot -Path $item.FullName
        length = $item.Length
        lastWriteTime = $item.LastWriteTime.ToString('o')
        sha256 = (Get-FileHash -LiteralPath $item.FullName -Algorithm SHA256).Hash
    }
}

function Set-Property {
    param([object]$Object, [string]$Name, [object]$Value)
    $property = $Object.PSObject.Properties[$Name]
    if ($null -eq $property) {
        $Object | Add-Member -NotePropertyName $Name -NotePropertyValue $Value
    }
    else {
        $property.Value = $Value
    }
}

function Get-UniqueFrameReferences {
    param([object[]]$Records, [string]$ComponentId, [string]$Label)
    $set = New-Object 'Collections.Generic.HashSet[string]' ([StringComparer]::OrdinalIgnoreCase)
    foreach ($record in @($Records)) {
        foreach ($frameKey in @($record.frameReferences)) {
            Assert-Condition -Condition (-not [string]::IsNullOrWhiteSpace([string]$frameKey) -and $set.Add([string]$frameKey)) `
                -Message "$ComponentId $Label contains an empty or duplicate frame reference: $frameKey"
        }
    }
    return ,$set
}

$repoRoot = (Resolve-Path -LiteralPath (Split-Path -Parent $PSScriptRoot)).Path
$planPath = Resolve-RepoPath -RepoRoot $repoRoot -Value $ResourcePlanPath
$accountingPath = Resolve-RepoPath -RepoRoot $repoRoot -Value $AccountingPath
$plan = Get-Content -LiteralPath $planPath -Raw -Encoding UTF8 | ConvertFrom-Json
$accounting = Get-Content -LiteralPath $accountingPath -Raw -Encoding UTF8 | ConvertFrom-Json

Assert-Condition -Condition ($plan.planId -eq 'weaponmaster-vergil-dark-blue-full-skill-v1') `
    -Message 'Unexpected resource plan.'
Assert-Condition -Condition ([int]$accounting.schemaVersion -eq 1 -and
    $accounting.status -eq 'passed-build-summary-dynamic-exclusion-expansion') `
    -Message 'Post-build frame accounting evidence is not a pass.'
Assert-Condition -Condition (@($plan.components).Count -eq 31 -and [int]$accounting.totals.componentCount -eq 31) `
    -Message 'Component count changed.'
Assert-Condition -Condition ($plan.coverage.fullSkillCoverageProven -eq $false -and
    $plan.deployment.authorized -eq $false -and $plan.deployment.performed -eq $false) `
    -Message 'This transition is only valid for the non-deployed pre-release plan.'

$dynamicByComponent = @{}
foreach ($componentEvidence in @($accounting.components)) {
    $dynamicByComponent[[string]$componentEvidence.componentId] = $componentEvidence
}

$globalPreBuildAuthorized = 0
$globalEffectiveChanged = 0
$globalExplicit = 0
$globalDynamic = 0
$globalSelectedFrames = 0
$ver5PreBuildAuthorized = 0
$ver5EffectiveChanged = 0
$ver2PreBuildAuthorized = 0
$ver2EffectiveChanged = 0

foreach ($component in @($plan.components)) {
    $componentId = [string]$component.id
    Assert-Condition -Condition ($component.selectedForAggregation -eq $true) `
        -Message "Component is not selected: $componentId"
    $summaryPath = Resolve-RepoPath -RepoRoot $repoRoot -Value ([string]$component.output.buildSummaryPath)
    $componentPath = Resolve-RepoPath -RepoRoot $repoRoot -Value ([string]$component.output.componentNpkPath)
    Assert-Condition -Condition (Test-Path -LiteralPath $summaryPath -PathType Leaf) `
        -Message "Build summary is missing: $componentId"
    Assert-Condition -Condition (Test-Path -LiteralPath $componentPath -PathType Leaf) `
        -Message "Component NPK is missing: $componentId"
    $summary = Get-Content -LiteralPath $summaryPath -Raw -Encoding UTF8 | ConvertFrom-Json
    Assert-Condition -Condition ($summary.status -eq 'passed' -and $summary.deployment.performed -eq $false) `
        -Message "Build summary is not a non-deployed pass: $componentId"
    Assert-Condition -Condition ((Get-FileHash -LiteralPath $componentPath -Algorithm SHA256).Hash -eq
        ([string]$summary.output.sha256).ToUpperInvariant()) `
        -Message "Component hash differs from its summary: $componentId"

    $changedCount = 0
    $explicitCount = 0
    $dynamicCount = 0
    if ($null -ne $summary.PSObject.Properties['textures']) {
        $changed = Get-UniqueFrameReferences -Records @($summary.textures | Where-Object decision -eq 'changed') `
            -ComponentId $componentId -Label 'changed textures'
        $explicit = Get-UniqueFrameReferences -Records @($summary.textures | Where-Object skipReason -eq 'explicit-excluded-reference') `
            -ComponentId $componentId -Label 'explicit textures'
        $dynamic = Get-UniqueFrameReferences -Records @($summary.textures | Where-Object {
            $_.decision -eq 'skipped' -and $_.skipReason -ne 'explicit-excluded-reference'
        }) -ComponentId $componentId -Label 'dynamic textures'
        $changedCount = $changed.Count
        $explicitCount = $explicit.Count
        $dynamicCount = $dynamic.Count
    }
    elseif ($null -ne $summary.PSObject.Properties['frames']) {
        $changedCount = @($summary.frames | Where-Object decision -eq 'changed').Count
        $explicitCount = @($summary.frames | Where-Object {
            $_.decision -eq 'skipped' -and $_.skipReason -eq 'explicit-excluded-reference'
        }).Count
        $dynamicCount = @($summary.frames).Count - $changedCount - $explicitCount
    }
    else {
        throw "Unsupported build-summary schema: $componentId"
    }

    $selectedFrames = [int]$summary.counts.frames
    Assert-Condition -Condition ($changedCount + $explicitCount + $dynamicCount -eq $selectedFrames) `
        -Message "Frame partition is incomplete: $componentId"
    $preBuildAuthorized = $changedCount + $dynamicCount
    $oldPreBuildAuthorized = if ($null -ne $component.counts.PSObject.Properties['preBuildAuthorizedFrameCount']) {
        [int]$component.counts.preBuildAuthorizedFrameCount
    } else {
        [int]$component.counts.authorizedFrameCount
    }
    Assert-Condition -Condition ($preBuildAuthorized -eq $oldPreBuildAuthorized) `
        -Message "Pre-build authorized count changed: $componentId $preBuildAuthorized/$oldPreBuildAuthorized"
    if ($dynamicCount -gt 0) {
        Assert-Condition -Condition ($dynamicByComponent.ContainsKey($componentId) -and
            [int]$dynamicByComponent[$componentId].changedFrameReferenceCount -eq $changedCount -and
            [int]$dynamicByComponent[$componentId].dynamicExcludedFrameReferenceCount -eq $dynamicCount) `
            -Message "Accounting evidence differs for $componentId"
    }

    Set-Property -Object $component.counts -Name 'preBuildAuthorizedFrameCount' -Value $preBuildAuthorized
    Set-Property -Object $component.counts -Name 'authorizedFrameCount' -Value $changedCount
    Set-Property -Object $component.counts -Name 'explicitExcludedFrameCount' -Value $explicitCount
    Set-Property -Object $component.counts -Name 'dynamicPreservedFrameCount' -Value $dynamicCount
    Set-Property -Object $component.counts -Name 'excludedFrameCount' -Value ($explicitCount + $dynamicCount)
    Set-Property -Object $component.counts -Name 'selectedFrameCount' -Value $selectedFrames
    Set-Property -Object $component -Name 'buildStatus' -Value 'offline-validated-client-pending'

    $artifact = if ($null -eq $component.PSObject.Properties['validatedArtifact']) {
        [pscustomobject]@{}
    } else {
        $component.validatedArtifact
    }
    Set-Property -Object $artifact -Name 'componentNpk' -Value (
        Get-FileSnapshot -RepoRoot $repoRoot -Path $componentPath -Kind 'offline-validated-component')
    Set-Property -Object $artifact -Name 'buildSummary' -Value (
        Get-FileSnapshot -RepoRoot $repoRoot -Path $summaryPath -Kind 'passed-build-summary')
    Set-Property -Object $artifact -Name 'status' -Value 'offline-validated-client-pending'
    Set-Property -Object $component -Name 'validatedArtifact' -Value $artifact

    $globalPreBuildAuthorized += $preBuildAuthorized
    $globalEffectiveChanged += $changedCount
    $globalExplicit += $explicitCount
    $globalDynamic += $dynamicCount
    $globalSelectedFrames += $selectedFrames
    if ($component.imgVersion -eq 'Ver5') {
        $ver5PreBuildAuthorized += $preBuildAuthorized
        $ver5EffectiveChanged += $changedCount
    }
    elseif ($component.imgVersion -eq 'Ver2') {
        $ver2PreBuildAuthorized += $preBuildAuthorized
        $ver2EffectiveChanged += $changedCount
    }
    else {
        throw "Unexpected component IMG version: $componentId/$($component.imgVersion)"
    }
}

Assert-Condition -Condition ($globalSelectedFrames -eq [int]$accounting.totals.selectedFrameReferenceCount -and
    $globalEffectiveChanged -eq [int]$accounting.totals.changedFrameReferenceCount -and
    $globalExplicit -eq [int]$accounting.totals.explicitExcludedFrameReferenceCount -and
    $globalDynamic -eq [int]$accounting.totals.dynamicExcludedFrameReferenceCount) `
    -Message 'Global accounting differs from the evidence.'
Assert-Condition -Condition ($ver5PreBuildAuthorized -eq 3625 -and $ver5EffectiveChanged -eq 3551 -and
    $ver2PreBuildAuthorized -eq 42 -and $ver2EffectiveChanged -eq 42 -and
    $globalPreBuildAuthorized -eq 3667 -and $globalEffectiveChanged -eq 3593 -and
    $globalExplicit -eq 128 -and $globalDynamic -eq 74) `
    -Message 'Expected post-build accounting totals changed.'

$accountingSnapshot = Get-FileSnapshot -RepoRoot $repoRoot -Path $accountingPath -Kind 'post-build-frame-accounting'
Set-Property -Object $plan.evidence -Name 'postBuildFrameAccounting' -Value $accountingSnapshot
Set-Property -Object $plan.scope -Name 'operation' -Value 'offline-components-validated-final-aggregation-pending'
Set-Property -Object $plan.scope -Name 'npkBuildPerformed' -Value $true
Set-Property -Object $plan.scope -Name 'componentBuildCount' -Value 31
Set-Property -Object $plan.scope -Name 'componentBuildPassedCount' -Value 31
Set-Property -Object $plan.scope -Name 'finalAggregationPerformed' -Value $false
$plan.authorization.ver2SelectionRule = 'flowmindadvanced seven Ver2 IMG and 42 frames use a separate same-format ARGB config'

Set-Property -Object $plan.totals -Name 'ver5PreBuildAuthorizedFrameCount' -Value $ver5PreBuildAuthorized
Set-Property -Object $plan.totals -Name 'ver2PreBuildAuthorizedFrameCount' -Value $ver2PreBuildAuthorized
Set-Property -Object $plan.totals -Name 'preBuildAuthorizedFrameCount' -Value $globalPreBuildAuthorized
$plan.totals.ver5AuthorizedFrameCount = $ver5EffectiveChanged
$plan.totals.ver2AuthorizedFrameCount = $ver2EffectiveChanged
$plan.totals.authorizedFrameCount = $globalEffectiveChanged
Set-Property -Object $plan.totals -Name 'explicitExcludedFrameCount' -Value $globalExplicit
Set-Property -Object $plan.totals -Name 'dynamicPreservedFrameCount' -Value $globalDynamic
$plan.totals.excludedFrameCount = $globalExplicit + $globalDynamic
Set-Property -Object $plan.totals -Name 'selectedFrameCount' -Value $globalSelectedFrames
Set-Property -Object $plan.totals -Name 'finalPreBuildAuthorizedChangedFrameCount' -Value (
    $globalPreBuildAuthorized + [int]$plan.totals.reuseChangedFrameCount)
$plan.totals.finalAuthorizedChangedFrameCount = $globalEffectiveChanged + [int]$plan.totals.reuseChangedFrameCount
Set-Property -Object $plan.totals -Name 'finalSelectedFrameCount' -Value (
    $globalSelectedFrames + [int]$plan.totals.reuseChangedFrameCount + [int]$plan.totals.reusePreservedFrameCount)
Set-Property -Object $plan.totals -Name 'finalPreservedFrameCount' -Value (
    $globalExplicit + $globalDynamic + [int]$plan.totals.reusePreservedFrameCount)
$plan.totals.candidatePoolExcludedFrameCount =
    $globalExplicit + $globalDynamic + [int]$plan.totals.wholeImgGateExcludedFrameCount

$plan.status = 'components-offline-validated-final-aggregation-pending'
$plan.generatedAt = (Get-Date).ToString('o')
$plan.coverage.reason = '31 selected components and the reusable Cut-in component are built and individually offline-validated; final aggregation, independent final-NPK validation, full-frame contact sheets, release metadata, and target-client A/B remain pending.'
$plan.coverage.remainingGates = @(
    'aggregate authorized changed IMG plus Cut-in target IMG',
    'independent structural and pixel validation',
    'full-frame contact sheets',
    'release.json',
    'target-client A/B; no deployment'
)

$temporaryPath = Join-Path (Split-Path -Parent $planPath) (
    '.' + [IO.Path]::GetFileName($planPath) + '.' + [Guid]::NewGuid().ToString('N') + '.tmp')
$backupPath = Join-Path (Split-Path -Parent $planPath) (
    '.' + [IO.Path]::GetFileName($planPath) + '.' + [Guid]::NewGuid().ToString('N') + '.bak')
$replacementVerified = $false
try {
    $plan | ConvertTo-Json -Depth 100 | Set-Content -LiteralPath $temporaryPath -Encoding UTF8
    $check = Get-Content -LiteralPath $temporaryPath -Raw -Encoding UTF8 | ConvertFrom-Json
    Assert-Condition -Condition ($check.status -eq 'components-offline-validated-final-aggregation-pending' -and
        [int]$check.totals.authorizedFrameCount -eq 3593 -and
        [int]$check.totals.dynamicPreservedFrameCount -eq 74 -and
        @($check.components | Where-Object buildStatus -ne 'offline-validated-client-pending').Count -eq 0) `
        -Message 'Temporary post-build plan verification failed.'
    [IO.File]::Replace($temporaryPath, $planPath, $backupPath)
    $committed = Get-Content -LiteralPath $planPath -Raw -Encoding UTF8 | ConvertFrom-Json
    Assert-Condition -Condition ($committed.status -eq 'components-offline-validated-final-aggregation-pending' -and
        [int]$committed.totals.authorizedFrameCount -eq 3593 -and
        [int]$committed.totals.dynamicPreservedFrameCount -eq 74 -and
        @($committed.components | Where-Object buildStatus -ne 'offline-validated-client-pending').Count -eq 0) `
        -Message 'Committed post-build plan verification failed; the backup was retained.'
    $replacementVerified = $true
}
finally {
    if (Test-Path -LiteralPath $temporaryPath) { Remove-Item -LiteralPath $temporaryPath -Force }
    if ($replacementVerified -and (Test-Path -LiteralPath $backupPath)) {
        Remove-Item -LiteralPath $backupPath -Force
    }
}

[pscustomobject]@{
    Status = 'passed'
    ResourcePlan = $planPath
    ResourcePlanSha256 = (Get-FileHash -LiteralPath $planPath -Algorithm SHA256).Hash
    ComponentCount = 31
    PreBuildAuthorizedFrameCount = $globalPreBuildAuthorized
    EffectiveChangedFrameCount = $globalEffectiveChanged
    ExplicitExcludedFrameCount = $globalExplicit
    DynamicPreservedFrameCount = $globalDynamic
    FinalEffectiveChangedFrameCount = [int]$plan.totals.finalAuthorizedChangedFrameCount
    Deployment = 'not-authorized-not-performed'
} | Format-List

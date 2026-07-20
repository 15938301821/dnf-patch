[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)]
    [string]$BaselinePlanPath,

    [Parameter(Mandatory = $true)]
    [string]$SourceMigrationPath,

    [Parameter(Mandatory = $true)]
    [string]$OutputPath,

    [ValidatePattern('^[A-Za-z0-9][A-Za-z0-9._-]*$')]
    [string]$RunId = 'cutin-weaponmaster-neo-aseprite-v1'
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

function Assert-Condition {
    param([bool]$Condition, [string]$Message)

    if (-not $Condition) {
        throw $Message
    }
}

function Get-RepoRelativePath {
    param([string]$RepositoryRoot, [string]$Path)

    $root = $RepositoryRoot.TrimEnd('\') + '\'
    $rootUri = New-Object Uri $root
    $pathUri = New-Object Uri ([IO.Path]::GetFullPath($Path))
    return [Uri]::UnescapeDataString($rootUri.MakeRelativeUri($pathUri).ToString()).Replace('\', '/')
}

function New-Snapshot {
    param([string]$RepositoryRoot, [string]$Path)

    $resolved = (Resolve-Path -LiteralPath $Path).Path
    $item = Get-Item -LiteralPath $resolved
    return [ordered]@{
        path = Get-RepoRelativePath -RepositoryRoot $RepositoryRoot -Path $resolved
        length = [long]$item.Length
        sha256 = (Get-FileHash -LiteralPath $resolved -Algorithm SHA256).Hash
    }
}

$repoRoot = (Resolve-Path -LiteralPath (Split-Path -Parent $PSScriptRoot)).Path
$baselinePath = (Resolve-Path -LiteralPath $BaselinePlanPath).Path
$migrationPath = (Resolve-Path -LiteralPath $SourceMigrationPath).Path
$outputFile = [IO.Path]::GetFullPath($OutputPath)
Assert-Condition (-not (Test-Path -LiteralPath $outputFile)) "Refusing to overwrite an existing migration plan: $outputFile"

$baseline = Get-Content -LiteralPath $baselinePath -Raw -Encoding UTF8 | ConvertFrom-Json
$migration = Get-Content -LiteralPath $migrationPath -Raw -Encoding UTF8 | ConvertFrom-Json
$selected = @($baseline.components | Where-Object { $_.selectedForAggregation -eq $true })
$reuse = @($baseline.reuseComponents)

Assert-Condition ([int]$baseline.schemaVersion -eq 1) 'Baseline schemaVersion must be 1.'
Assert-Condition ([string]$baseline.planId -eq 'weaponmaster-vergil-dark-blue-full-skill-v3') 'Unexpected baseline plan identity.'
Assert-Condition ($baseline.coverage.fullSkillCoverageProven -eq $false) 'Baseline coverage must remain false.'
Assert-Condition ($selected.Count -eq 31) "Expected 31 selected baseline components, found $($selected.Count)."
Assert-Condition ($reuse.Count -eq 1 -and [string]$reuse[0].id -eq 'cutin-weaponmaster-neo-v2') 'Unexpected baseline reuse component.'
Assert-Condition ([string]$migration.status -eq 'passed') 'Source migration report did not pass.'
Assert-Condition ([int]$migration.counts.uniqueExpectedSnapshots -eq 53) 'Source migration expected snapshot count changed.'
Assert-Condition ([int]$migration.counts.matched -eq 53) 'Source migration matched count changed.'
Assert-Condition ([int]$migration.counts.contentDrift -eq 0 -and [int]$migration.counts.missing -eq 0) 'Source migration contains drift or missing sources.'

$themeRoot = Split-Path -Parent (Split-Path -Parent (Split-Path -Parent $baselinePath))
$professionRoot = Split-Path -Parent $themeRoot
$professionName = Split-Path -Leaf $professionRoot
$legacyProfessionPrefix = $professionName + '/'
$currentProfessionPrefix = 'jobs/' + $professionName + '/'
$baselineSnapshot = New-Snapshot -RepositoryRoot $repoRoot -Path $baselinePath
$migrationSnapshot = New-Snapshot -RepositoryRoot $repoRoot -Path $migrationPath
$selectedIds = @($selected | ForEach-Object { [string]$_.id } | Sort-Object)
$selectedImgCount = [int](@($selected | ForEach-Object { @($_.selectedImgPaths).Count } | Measure-Object -Sum).Sum)

$plan = [ordered]@{
    schemaVersion = 1
    planId = 'weaponmaster-vergil-dark-blue-aseprite-migration-v5'
    themeId = 'weaponmaster-vergil-dark-blue'
    generatedAt = (Get-Date).ToString('o')
    status = 'migration-evidence-pending'
    mode = 'immutable migration overlay; no build, aggregation, deployment, or process operation'
    historicalPathRelocation = [ordered]@{
        mode = 'exact-repository-relative-prefix'
        sourcePrefix = $legacyProfessionPrefix
        targetPrefix = $currentProfessionPrefix
        absolutePaths = 'not-relocated'
        otherPrefixes = 'not-relocated'
        purpose = 'resolve immutable pre-jobs repository-relative evidence without rewriting historical files'
    }
    professionManifestPath = Get-RepoRelativePath -RepositoryRoot $repoRoot -Path (Join-Path $professionRoot 'manifest.json')
    baselinePlan = [ordered]@{
        path = $baselineSnapshot.path
        length = $baselineSnapshot.length
        sha256 = $baselineSnapshot.sha256
        planId = [string]$baseline.planId
        role = 'immutable historical component and source snapshot; not an active Cut-in authorization'
    }
    sourceMigration = [ordered]@{
        path = $migrationSnapshot.path
        length = $migrationSnapshot.length
        sha256 = $migrationSnapshot.sha256
        status = [string]$migration.status
        uniqueExpectedSnapshots = [int]$migration.counts.uniqueExpectedSnapshots
        matched = [int]$migration.counts.matched
        contentDrift = [int]$migration.counts.contentDrift
        missing = [int]$migration.counts.missing
        role = 'active read-only source identity evidence'
    }
    baselineComponents = [ordered]@{
        componentCount = $selected.Count
        selectedImgCount = $selectedImgCount
        historicalValidationStatus = 'offline-validated-under-baseline-plan'
        activeDisposition = 'live artifact, output-path binding, config selection, toolchain, builder snapshot, and independent-index revalidation required'
        selectedComponentIds = $selectedIds
    }
    supersededReuseComponents = @([ordered]@{
        id = 'cutin-weaponmaster-neo-v2'
        baselinePlanRequiredForFinalAggregation = $true
        activeAggregationAuthorized = $false
        status = 'superseded-historical-evidence-only'
        reason = 'The Photoshop-era Cut-in payload and release evidence cannot authorize the current Aseprite contract.'
    })
    activeCutin = [ordered]@{
        id = $RunId
        runId = $RunId
        targetImg = 'sprite/character/swordman/effect/cutin/cutin_weaponmaster_neo.img'
        imgVersion = 'Ver5'
        changedFrames = '3-26'
        preservedTransparentFrames = '0-2'
        requiredLayeredProjectCount = 24
        requiredRuntimePngCount = 24
        minimumAsepriteApiVersion = 30
        evidence = [ordered]@{
            renderSummaryPath = Get-RepoRelativePath -RepositoryRoot $repoRoot -Path (Join-Path $themeRoot (Join-Path 'validation' (Join-Path $RunId 'render-summary.json')))
            manualReviewPath = Get-RepoRelativePath -RepositoryRoot $repoRoot -Path (Join-Path $themeRoot (Join-Path 'validation' (Join-Path $RunId 'manual-review.json')))
            buildSummaryPath = Get-RepoRelativePath -RepositoryRoot $repoRoot -Path (Join-Path $themeRoot (Join-Path 'validation' (Join-Path ('build-' + $RunId) 'build-summary.json')))
        }
    }
    readinessPolicy = [ordered]@{
        componentSnapshotsAndIndependentIndexes = 'required'
        componentConfigPlanSummarySelections = 'required'
        componentPlanConfigSummaryOutputPaths = 'required'
        componentSummaryToolchainSnapshots = 'required'
        baselineBuilderSnapshots = 'required'
        asepriteImportedAndPinned = 'required'
        renderSummaryAndTwentyFourPairs = 'required'
        layeredProjectsReopenedAndPixelEqual = 'required'
        manualFullSequenceReview = 'required-separate-immutable-evidence'
        buildSummaryAndBuilderStats = 'required'
        cutinIndependentIndexAndFullFrameDecode = 'required'
        cutinMetadataAndPixelValidation = 'required'
        historicalCutinReuse = 'forbidden'
        readyForAggregation = $false
    }
    coverage = [ordered]@{
        fullSkillCoverageProven = $false
        reason = 'This is a pre-aggregation migration plan. Final aggregation, independent final-NPK validation, release metadata, release closure, and target-client A/B are not complete.'
    }
    initialBlockers = @(
        'aseprite-not-imported',
        'aseprite-api-capability-not-recorded',
        'component-live-revalidation-pending',
        'cutin-render-evidence-pending',
        'cutin-manual-full-sequence-review-pending',
        'cutin-build-evidence-pending',
        'cutin-independent-validation-pending',
        'final-aggregation-not-performed',
        'final-validation-not-performed',
        'release-closure-not-performed'
    )
    deployment = [ordered]@{
        authorized = $false
        performed = $false
        imagePacks2Write = $false
        processOperation = $false
        status = 'not-authorized-not-performed'
    }
}

$parent = Split-Path -Parent $outputFile
New-Item -ItemType Directory -Path $parent -Force | Out-Null
$temporary = Join-Path $parent ('.' + [IO.Path]::GetFileName($outputFile) + '.tmp-' + [Guid]::NewGuid().ToString('N'))
try {
    $plan | ConvertTo-Json -Depth 12 | Set-Content -LiteralPath $temporary -Encoding UTF8
    $check = Get-Content -LiteralPath $temporary -Raw -Encoding UTF8 | ConvertFrom-Json
    Assert-Condition ([string]$check.planId -eq 'weaponmaster-vergil-dark-blue-aseprite-migration-v5') 'Generated plan identity changed.'
    Assert-Condition ([string]$check.historicalPathRelocation.sourcePrefix -eq $legacyProfessionPrefix -and
        [string]$check.historicalPathRelocation.targetPrefix -eq $currentProfessionPrefix -and
        [string]$check.historicalPathRelocation.absolutePaths -eq 'not-relocated') `
        'Generated plan historical path relocation policy changed.'
    Assert-Condition ($check.coverage.fullSkillCoverageProven -eq $false) 'Generated plan coverage must remain false.'
    Assert-Condition ($check.deployment.performed -eq $false) 'Generated plan cannot record deployment.'
    [IO.File]::Move($temporary, $outputFile)
}
finally {
    if (Test-Path -LiteralPath $temporary) {
        Remove-Item -LiteralPath $temporary -Force
    }
}

$outputItem = Get-Item -LiteralPath $outputFile
[pscustomobject]@{
    status = 'passed'
    output = $outputFile
    length = [long]$outputItem.Length
    sha256 = (Get-FileHash -LiteralPath $outputFile -Algorithm SHA256).Hash
    fullSkillCoverageProven = $false
    readyForAggregation = $false
    deployment = 'not-authorized-not-performed'
}
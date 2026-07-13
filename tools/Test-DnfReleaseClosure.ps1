[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)]
    [string]$ProfessionManifestPath,

    [string]$ReleaseReportPath,

    [string]$RepoRoot,

    [switch]$AsJson
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
$OutputEncoding = [Console]::OutputEncoding = New-Object System.Text.UTF8Encoding($false)
$script:SnapshotCount = 0
$script:ProvenanceSnapshotCount = 0

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

function Test-ObjectProperty {
    param(
        [object]$Object,
        [string]$Name
    )

    return $null -ne $Object -and $null -ne $Object.PSObject.Properties[$Name]
}

function Get-RequiredProperty {
    param(
        [object]$Object,
        [string]$Name,
        [string]$Label
    )

    Assert-Condition -Condition (Test-ObjectProperty -Object $Object -Name $Name) `
        -Message "$Label is missing required property '$Name'."
    Write-Output -NoEnumerate $Object.PSObject.Properties[$Name].Value
}

function Get-NormalizedHash {
    param(
        [object]$Value,
        [string]$Label
    )

    $hash = ([string]$Value).Trim().ToUpperInvariant()
    Assert-Condition -Condition ($hash -match '^[0-9A-F]{64}$') -Message "$Label is not a SHA-256 value: '$Value'."
    return $hash
}

function Resolve-FullPath {
    param(
        [string]$Value,
        [string]$BaseDirectory,
        [string]$Label
    )

    Assert-Condition -Condition (-not [string]::IsNullOrWhiteSpace($Value)) -Message "$Label path is empty."
    $native = $Value.Replace('/', [IO.Path]::DirectorySeparatorChar)
    if ([IO.Path]::IsPathRooted($native)) {
        return [IO.Path]::GetFullPath($native)
    }
    return [IO.Path]::GetFullPath((Join-Path $BaseDirectory $native))
}

function Assert-PathInsideRepository {
    param(
        [string]$Path,
        [string]$RepositoryRoot,
        [string]$Label
    )

    $root = $RepositoryRoot.TrimEnd([IO.Path]::DirectorySeparatorChar, [IO.Path]::AltDirectorySeparatorChar)
    $prefix = $root + [IO.Path]::DirectorySeparatorChar
    Assert-Condition -Condition ($Path.StartsWith($prefix, [StringComparison]::OrdinalIgnoreCase)) `
        -Message "$Label must stay inside the repository: $Path"
}

function Resolve-ExistingFile {
    param(
        [string]$Value,
        [string]$BaseDirectory,
        [string]$Label,
        [bool]$RequireInsideRepository = $true
    )

    $path = Resolve-FullPath -Value $Value -BaseDirectory $BaseDirectory -Label $Label
    Assert-Condition -Condition (Test-Path -LiteralPath $path -PathType Leaf) -Message "$Label was not found: $path"
    $resolved = (Resolve-Path -LiteralPath $path).Path
    if ($RequireInsideRepository) {
        Assert-PathInsideRepository -Path $resolved -RepositoryRoot $script:RepositoryRoot -Label $Label
    }
    return $resolved
}

function Assert-FileSnapshot {
    param(
        [object]$Snapshot,
        [string]$BaseDirectory,
        [string]$Label,
        [bool]$RequireInsideRepository = $true,
        [bool]$Provenance = $false
    )

    Assert-Condition -Condition ($null -ne $Snapshot) -Message "$Label snapshot is missing."
    $pathValue = [string](Get-RequiredProperty -Object $Snapshot -Name 'path' -Label $Label)
    $path = Resolve-ExistingFile -Value $pathValue -BaseDirectory $BaseDirectory -Label $Label `
        -RequireInsideRepository $RequireInsideRepository
    $item = Get-Item -LiteralPath $path
    $expectedHash = Get-NormalizedHash -Value (Get-RequiredProperty -Object $Snapshot -Name 'sha256' -Label $Label) `
        -Label "$Label expected hash"
    $actualHash = (Get-FileHash -LiteralPath $path -Algorithm SHA256).Hash
    Assert-Condition -Condition ($actualHash -eq $expectedHash) `
        -Message "$Label SHA-256 changed: actual=$actualHash expected=$expectedHash path=$path"
    if (Test-ObjectProperty -Object $Snapshot -Name 'length') {
        $expectedLength = [long](Get-RequiredProperty -Object $Snapshot -Name 'length' -Label $Label)
        Assert-Condition -Condition ($item.Length -eq $expectedLength) `
            -Message "$Label length changed: actual=$($item.Length) expected=$expectedLength path=$path"
    }

    $script:SnapshotCount++
    if ($Provenance) {
        $script:ProvenanceSnapshotCount++
    }
    Write-Output -NoEnumerate ([pscustomobject]@{
        path = $path
        length = $item.Length
        sha256 = $actualHash
    })
}

function New-SnapshotObject {
    param(
        [object]$Path,
        [object]$Sha256,
        [object]$Length
    )

    $snapshot = [ordered]@{
        path = [string]$Path
        sha256 = [string]$Sha256
    }
    if ($null -ne $Length) {
        $snapshot.length = [long]$Length
    }
    return [pscustomobject]$snapshot
}

function Assert-SameFile {
    param(
        [object]$Left,
        [object]$Right,
        [string]$Label
    )

    Assert-Condition -Condition ($Left.path -ieq $Right.path) `
        -Message "$Label path mismatch: left=$($Left.path) right=$($Right.path)"
    Assert-Condition -Condition ([long]$Left.length -eq [long]$Right.length) `
        -Message "$Label length mismatch: left=$($Left.length) right=$($Right.length)"
    Assert-Condition -Condition ($Left.sha256 -eq $Right.sha256) `
        -Message "$Label SHA-256 mismatch: left=$($Left.sha256) right=$($Right.sha256)"
}

function Assert-TextEqual {
    param(
        [object]$Actual,
        [object]$Expected,
        [string]$Label
    )

    Assert-Condition -Condition (([string]$Actual).Equals([string]$Expected, [StringComparison]::OrdinalIgnoreCase)) `
        -Message "$Label mismatch: actual='$Actual' expected='$Expected'"
}

function Assert-LongEqual {
    param(
        [object]$Actual,
        [object]$Expected,
        [string]$Label
    )

    Assert-Condition -Condition ([long]$Actual -eq [long]$Expected) `
        -Message "$Label mismatch: actual=$Actual expected=$Expected"
}

function Assert-TrueValue {
    param(
        [object]$Actual,
        [string]$Label
    )

    Assert-Condition -Condition ($Actual -eq $true) -Message "$Label must be true, found '$Actual'."
}

function Assert-FalseValue {
    param(
        [object]$Actual,
        [string]$Label
    )

    Assert-Condition -Condition ($Actual -eq $false) -Message "$Label must be false, found '$Actual'."
}

function Assert-NoDeployment {
    param(
        [object]$Deployment,
        [string]$Label
    )

    Assert-Condition -Condition ($null -ne $Deployment) -Message "$Label deployment record is missing."
    foreach ($name in @('authorized', 'performed')) {
        Assert-FalseValue -Actual (Get-RequiredProperty -Object $Deployment -Name $name -Label "$Label deployment") `
            -Label "$Label deployment.$name"
    }
    foreach ($name in @('imagePacks2Write', 'processOperation')) {
        if (Test-ObjectProperty -Object $Deployment -Name $name) {
            Assert-FalseValue -Actual $Deployment.PSObject.Properties[$name].Value -Label "$Label deployment.$name"
        }
    }
}

$defaultRepoRoot = Split-Path -Parent $PSScriptRoot
$script:RepositoryRoot = if ([string]::IsNullOrWhiteSpace($RepoRoot)) {
    (Resolve-Path -LiteralPath $defaultRepoRoot).Path
}
else {
    $candidate = Resolve-FullPath -Value $RepoRoot -BaseDirectory $defaultRepoRoot -Label 'Repository root'
    Assert-Condition -Condition (Test-Path -LiteralPath $candidate -PathType Container) `
        -Message "Repository root was not found: $candidate"
    (Resolve-Path -LiteralPath $candidate).Path
}

$manifestPath = Resolve-ExistingFile -Value $ProfessionManifestPath -BaseDirectory $script:RepositoryRoot `
    -Label 'Profession manifest'
$manifestDirectory = Split-Path -Parent $manifestPath
$manifest = Get-Content -LiteralPath $manifestPath -Raw -Encoding UTF8 | ConvertFrom-Json
$manifestRelease = Get-RequiredProperty -Object $manifest -Name 'fullSkillRelease' -Label 'Profession manifest'

$releaseValue = if ([string]::IsNullOrWhiteSpace($ReleaseReportPath)) {
    [string](Get-RequiredProperty -Object $manifestRelease -Name 'releaseReport' -Label 'Manifest fullSkillRelease')
}
else {
    $ReleaseReportPath
}
$releasePath = Resolve-ExistingFile -Value $releaseValue -BaseDirectory $manifestDirectory -Label 'Release report'
$releaseDirectory = Split-Path -Parent $releasePath
$release = Get-Content -LiteralPath $releasePath -Raw -Encoding UTF8 | ConvertFrom-Json

$manifestArtifact = Assert-FileSnapshot -Snapshot (Get-RequiredProperty $manifestRelease 'artifact' 'Manifest fullSkillRelease') `
    -BaseDirectory $manifestDirectory -Label 'Manifest artifact'
$releaseArtifact = Assert-FileSnapshot -Snapshot (Get-RequiredProperty $release 'artifact' 'Release report') `
    -BaseDirectory $releaseDirectory -Label 'Release artifact'
$manifestPackage = Assert-FileSnapshot -Snapshot (Get-RequiredProperty $manifestRelease 'packageSummary' 'Manifest fullSkillRelease') `
    -BaseDirectory $manifestDirectory -Label 'Manifest package summary'
$releasePackage = Assert-FileSnapshot -Snapshot (Get-RequiredProperty $release 'packageSummary' 'Release report') `
    -BaseDirectory $releaseDirectory -Label 'Release package summary'

$manifestEvidence = Get-RequiredProperty $manifestRelease 'sourceEvidence' 'Manifest fullSkillRelease'
$releaseEvidence = Get-RequiredProperty $release 'sourceEvidence' 'Release report'
$manifestPlan = Assert-FileSnapshot -Snapshot (Get-RequiredProperty $manifestEvidence 'resourcePlan' 'Manifest sourceEvidence') `
    -BaseDirectory $manifestDirectory -Label 'Manifest resource plan'
$releasePlan = Assert-FileSnapshot -Snapshot (Get-RequiredProperty $releaseEvidence 'resourcePlan' 'Release sourceEvidence') `
    -BaseDirectory $releaseDirectory -Label 'Release resource plan'
$manifestAccounting = Assert-FileSnapshot -Snapshot (Get-RequiredProperty $manifestEvidence 'postBuildFrameAccounting' 'Manifest sourceEvidence') `
    -BaseDirectory $manifestDirectory -Label 'Manifest frame accounting'
$releaseAccounting = Assert-FileSnapshot -Snapshot (Get-RequiredProperty $releaseEvidence 'postBuildFrameAccounting' 'Release sourceEvidence') `
    -BaseDirectory $releaseDirectory -Label 'Release frame accounting'

$manifestValidation = Get-RequiredProperty $manifestRelease 'validation' 'Manifest fullSkillRelease'
$releaseValidation = Get-RequiredProperty $release 'validation' 'Release report'
$manifestSummary = Assert-FileSnapshot -Snapshot (Get-RequiredProperty $manifestValidation 'finalSummary' 'Manifest validation') `
    -BaseDirectory $manifestDirectory -Label 'Manifest final summary'
$releaseSummary = Assert-FileSnapshot -Snapshot (Get-RequiredProperty $releaseValidation 'finalSummary' 'Release validation') `
    -BaseDirectory $releaseDirectory -Label 'Release final summary'
$manifestIndex = Assert-FileSnapshot -Snapshot (Get-RequiredProperty $manifestValidation 'independentIndex' 'Manifest validation') `
    -BaseDirectory $manifestDirectory -Label 'Manifest independent index'
$releaseIndex = Assert-FileSnapshot -Snapshot (Get-RequiredProperty $releaseValidation 'independentIndex' 'Release validation') `
    -BaseDirectory $releaseDirectory -Label 'Release independent index'

$manifestFullFrame = Get-RequiredProperty $manifestValidation 'fullFrame' 'Manifest validation'
$releaseFullFrame = Get-RequiredProperty $releaseValidation 'fullFrame' 'Release validation'
$manifestAlbumSnapshot = New-SnapshotObject `
    -Path (Get-RequiredProperty $manifestFullFrame 'albumInventoryPath' 'Manifest fullFrame') `
    -Sha256 (Get-RequiredProperty $manifestFullFrame 'albumInventorySha256' 'Manifest fullFrame') `
    -Length $null
$manifestFrameSnapshot = New-SnapshotObject `
    -Path (Get-RequiredProperty $manifestFullFrame 'frameInventoryPath' 'Manifest fullFrame') `
    -Sha256 (Get-RequiredProperty $manifestFullFrame 'frameInventorySha256' 'Manifest fullFrame') `
    -Length $null
$manifestAlbum = Assert-FileSnapshot -Snapshot $manifestAlbumSnapshot -BaseDirectory $manifestDirectory `
    -Label 'Manifest album inventory'
$manifestFrames = Assert-FileSnapshot -Snapshot $manifestFrameSnapshot -BaseDirectory $manifestDirectory `
    -Label 'Manifest frame inventory'
$releaseAlbum = Assert-FileSnapshot -Snapshot (Get-RequiredProperty $releaseFullFrame 'albumInventory' 'Release fullFrame') `
    -BaseDirectory $releaseDirectory -Label 'Release album inventory'
$releaseFrames = Assert-FileSnapshot -Snapshot (Get-RequiredProperty $releaseFullFrame 'frameInventory' 'Release fullFrame') `
    -BaseDirectory $releaseDirectory -Label 'Release frame inventory'

Assert-SameFile $manifestArtifact $releaseArtifact 'Manifest/release artifact'
Assert-SameFile $manifestPackage $releasePackage 'Manifest/release package summary'
Assert-SameFile $manifestPlan $releasePlan 'Manifest/release resource plan'
Assert-SameFile $manifestAccounting $releaseAccounting 'Manifest/release frame accounting'
Assert-SameFile $manifestSummary $releaseSummary 'Manifest/release final summary'
Assert-SameFile $manifestIndex $releaseIndex 'Manifest/release independent index'
Assert-SameFile $manifestAlbum $releaseAlbum 'Manifest/release album inventory'
Assert-SameFile $manifestFrames $releaseFrames 'Manifest/release frame inventory'

$summaryDirectory = Split-Path -Parent $manifestSummary.path
$summary = Get-Content -LiteralPath $manifestSummary.path -Raw -Encoding UTF8 | ConvertFrom-Json
$summaryArtifact = Assert-FileSnapshot -Snapshot (Get-RequiredProperty $summary 'finalArtifact' 'Final summary') `
    -BaseDirectory $summaryDirectory -Label 'Summary artifact'
$summaryPackage = Assert-FileSnapshot -Snapshot (Get-RequiredProperty $summary 'packageSummary' 'Final summary') `
    -BaseDirectory $summaryDirectory -Label 'Summary package summary'
$summaryPlanRecord = Get-RequiredProperty $summary 'resourcePlan' 'Final summary'
$summaryPlanSnapshot = New-SnapshotObject `
    -Path (Get-RequiredProperty $summaryPlanRecord 'inputPath' 'Summary resource plan') `
    -Sha256 (Get-RequiredProperty $summaryPlanRecord 'sha256' 'Summary resource plan') `
    -Length (Get-RequiredProperty $summaryPlanRecord 'length' 'Summary resource plan')
$summaryValidatedPlanSnapshot = New-SnapshotObject `
    -Path (Get-RequiredProperty $summaryPlanRecord 'validatedSnapshotPath' 'Summary resource plan') `
    -Sha256 (Get-RequiredProperty $summaryPlanRecord 'sha256' 'Summary resource plan') `
    -Length (Get-RequiredProperty $summaryPlanRecord 'length' 'Summary resource plan')
$summaryPlan = Assert-FileSnapshot -Snapshot $summaryPlanSnapshot `
    -BaseDirectory $summaryDirectory -Label 'Summary resource plan input'
$summaryValidatedPlan = Assert-FileSnapshot -Snapshot $summaryValidatedPlanSnapshot `
    -BaseDirectory $summaryDirectory -Label 'Summary validated resource-plan snapshot'
$summaryValidation = Get-RequiredProperty $summary 'validation' 'Final summary'
$summaryIndexEvidence = Get-RequiredProperty $summaryValidation 'independentIndex' 'Final summary validation'
$summaryIndexSnapshot = New-SnapshotObject `
    -Path (Get-RequiredProperty $summaryIndexEvidence 'report' 'Summary independent index') `
    -Sha256 (Get-RequiredProperty $summaryIndexEvidence 'reportSha256' 'Summary independent index') `
    -Length $null
$summaryIndex = Assert-FileSnapshot -Snapshot $summaryIndexSnapshot -BaseDirectory $summaryDirectory `
    -Label 'Summary independent index'
$summaryFullFrame = Get-RequiredProperty $summaryValidation 'fullFrame' 'Final summary validation'
$summaryAlbum = Assert-FileSnapshot -Snapshot (Get-RequiredProperty $summaryFullFrame 'albumInventory' 'Summary fullFrame') `
    -BaseDirectory $summaryDirectory -Label 'Summary album inventory'
$summaryFrames = Assert-FileSnapshot -Snapshot (Get-RequiredProperty $summaryFullFrame 'frameInventory' 'Summary fullFrame') `
    -BaseDirectory $summaryDirectory -Label 'Summary frame inventory'
$summaryLog = Assert-FileSnapshot -Snapshot (Get-RequiredProperty $summaryFullFrame 'log' 'Summary fullFrame') `
    -BaseDirectory $summaryDirectory -Label 'Summary full-frame log'

$contactSheetCount = 0
foreach ($sheet in @((Get-RequiredProperty $summaryFullFrame 'contactSheets' 'Summary fullFrame'))) {
    $null = Assert-FileSnapshot -Snapshot $sheet -BaseDirectory $summaryDirectory `
        -Label "Summary contact sheet $contactSheetCount"
    $contactSheetCount++
}
Assert-Condition -Condition ($contactSheetCount -gt 0) -Message 'Final summary has no contact-sheet snapshots.'

Assert-SameFile $manifestArtifact $summaryArtifact 'Manifest/summary artifact'
Assert-SameFile $manifestPackage $summaryPackage 'Manifest/summary package summary'
Assert-SameFile $manifestPlan $summaryPlan 'Manifest/summary resource plan'
Assert-Condition -Condition ($summaryValidatedPlan.length -eq $manifestPlan.length) `
    -Message 'Validated resource-plan snapshot length differs from the input plan.'
Assert-Condition -Condition ($summaryValidatedPlan.sha256 -eq $manifestPlan.sha256) `
    -Message 'Validated resource-plan snapshot SHA-256 differs from the input plan.'
Assert-SameFile $manifestIndex $summaryIndex 'Manifest/summary independent index'
Assert-SameFile $manifestAlbum $summaryAlbum 'Manifest/summary album inventory'
Assert-SameFile $manifestFrames $summaryFrames 'Manifest/summary frame inventory'

$provenance = Get-RequiredProperty $summary 'provenance' 'Final summary'
foreach ($collectionName in @('officialSources', 'componentConfigs', 'componentToolchains', 'tools')) {
    foreach ($snapshot in @((Get-RequiredProperty $provenance $collectionName 'Final summary provenance'))) {
        $null = Assert-FileSnapshot -Snapshot $snapshot -BaseDirectory $summaryDirectory `
            -Label "Summary provenance $collectionName" -RequireInsideRepository $false -Provenance $true
    }
}

Assert-TextEqual (Get-RequiredProperty $manifestRelease 'status' 'Manifest fullSkillRelease') `
    'offline-validated-client-pending' 'Manifest release status'
Assert-TextEqual (Get-RequiredProperty $release 'status' 'Release report') `
    'offline-validated-client-pending' 'Release report status'
Assert-TextEqual (Get-RequiredProperty $summary 'status' 'Final summary') 'passed' 'Final summary status'
Assert-TextEqual (Get-RequiredProperty $releaseValidation 'status' 'Release validation') 'passed' 'Release validation status'

$manifestCoverage = Get-RequiredProperty $manifest 'coverage' 'Profession manifest'
$releaseCoverage = Get-RequiredProperty $release 'coverage' 'Release report'
Assert-TrueValue (Get-RequiredProperty $manifestCoverage 'fullSkillCoverageProven' 'Manifest coverage') `
    'Manifest coverage.fullSkillCoverageProven'
Assert-TrueValue (Get-RequiredProperty $manifestRelease 'fullSkillCoverageProven' 'Manifest fullSkillRelease') `
    'Manifest fullSkillRelease.fullSkillCoverageProven'
Assert-TrueValue (Get-RequiredProperty $releaseCoverage 'fullSkillCoverageProven' 'Release coverage') `
    'Release coverage.fullSkillCoverageProven'
Assert-FalseValue (Get-RequiredProperty $releaseCoverage 'clientCompatibilityProven' 'Release coverage') `
    'Release coverage.clientCompatibilityProven'

$offlineCoverage = Get-RequiredProperty $summaryValidation 'manifestScopeOfflineCoverage' 'Final summary validation'
Assert-TrueValue (Get-RequiredProperty $offlineCoverage 'eligibleForReleaseMetadataFullSkillCoverage' 'Offline coverage') `
    'Offline coverage eligibility'
Assert-FalseValue (Get-RequiredProperty $offlineCoverage 'fullSkillCoverageProvenAtValidationStart' 'Offline coverage') `
    'Offline coverage start state'
Assert-FalseValue (Get-RequiredProperty $offlineCoverage 'releaseMetadataGeneratedByThisValidator' 'Offline coverage') `
    'Offline coverage metadata mutation'
Assert-TrueValue (Get-RequiredProperty $offlineCoverage 'releaseMetadataRequiredBeforeCoverageTransition' 'Offline coverage') `
    'Offline coverage metadata requirement'
Assert-FalseValue (Get-RequiredProperty $offlineCoverage 'targetClientCompatibilityProven' 'Offline coverage') `
    'Offline coverage target-client compatibility'

Assert-FalseValue (Get-RequiredProperty (Get-RequiredProperty $manifestEvidence 'resourcePlan' 'Manifest sourceEvidence') `
    'fullSkillCoverageProvenAtValidationStart' 'Manifest resource-plan snapshot') 'Manifest plan start coverage'
Assert-FalseValue (Get-RequiredProperty (Get-RequiredProperty $releaseEvidence 'resourcePlan' 'Release sourceEvidence') `
    'fullSkillCoverageProvenAtValidationStart' 'Release resource-plan snapshot') 'Release plan start coverage'

$planJson = Get-Content -LiteralPath $manifestPlan.path -Raw -Encoding UTF8 | ConvertFrom-Json
$planCoverage = Get-RequiredProperty $planJson 'coverage' 'Resource plan'
Assert-FalseValue (Get-RequiredProperty $planCoverage 'fullSkillCoverageProven' 'Resource-plan coverage') `
    'Resource-plan pre-release coverage'

Assert-NoDeployment (Get-RequiredProperty $manifestRelease 'deployment' 'Manifest fullSkillRelease') 'Manifest'
Assert-NoDeployment (Get-RequiredProperty $release 'deployment' 'Release report') 'Release report'
Assert-NoDeployment (Get-RequiredProperty $summary 'deployment' 'Final summary') 'Final summary'

$manifestArtifactRecord = Get-RequiredProperty $manifestRelease 'artifact' 'Manifest fullSkillRelease'
$releaseArtifactRecord = Get-RequiredProperty $release 'artifact' 'Release report'
$summaryArtifactRecord = Get-RequiredProperty $summary 'finalArtifact' 'Final summary'
$expectedImgCount = Get-RequiredProperty $manifestArtifactRecord 'imgCount' 'Manifest artifact'
$expectedFrameCount = Get-RequiredProperty $manifestArtifactRecord 'frameCount' 'Manifest artifact'
Assert-LongEqual (Get-RequiredProperty $releaseArtifactRecord 'imgCount' 'Release artifact') $expectedImgCount `
    'Release artifact IMG count'
Assert-LongEqual (Get-RequiredProperty $releaseArtifactRecord 'frameCount' 'Release artifact') $expectedFrameCount `
    'Release artifact frame count'
Assert-LongEqual (Get-RequiredProperty $summaryArtifactRecord 'imgCount' 'Summary artifact') $expectedImgCount `
    'Summary artifact IMG count'
Assert-LongEqual (Get-RequiredProperty $summaryArtifactRecord 'frameCount' 'Summary artifact') $expectedFrameCount `
    'Summary artifact frame count'
$summaryCounts = Get-RequiredProperty $summary 'counts' 'Final summary'
Assert-LongEqual (Get-RequiredProperty $summaryCounts 'albums' 'Summary counts') $expectedImgCount `
    'Summary album count'
Assert-LongEqual (Get-RequiredProperty $summaryCounts 'frames' 'Summary counts') $expectedFrameCount `
    'Summary frame count'
$summarySelection = Get-RequiredProperty $summary 'selection' 'Final summary'
Assert-LongEqual (Get-RequiredProperty $summarySelection 'imgCount' 'Summary selection') $expectedImgCount `
    'Summary selected IMG count'

$indexReport = Get-Content -LiteralPath $manifestIndex.path -Raw -Encoding UTF8 | ConvertFrom-Json
Assert-TextEqual (Get-RequiredProperty $indexReport 'NpkMagic' 'Independent index') 'NeoplePack_Bill' `
    'Independent index NPK magic'
Assert-LongEqual (Get-RequiredProperty $indexReport 'EntryCount' 'Independent index') $expectedImgCount `
    'Independent index entry count'
Assert-LongEqual (Get-RequiredProperty $indexReport 'UniquePathCount' 'Independent index') $expectedImgCount `
    'Independent index unique path count'
Assert-TrueValue (Get-RequiredProperty $indexReport 'HeaderSha256Valid' 'Independent index') `
    'Independent index header SHA-256'
Assert-LongEqual (Get-RequiredProperty $indexReport 'ImgMagicValidCount' 'Independent index') $expectedImgCount `
    'Independent index IMG magic count'

$indexToolPath = Join-Path $script:RepositoryRoot 'tools\Test-DnfNpkIndex.ps1'
Assert-Condition -Condition (Test-Path -LiteralPath $indexToolPath -PathType Leaf) `
    -Message "Independent index validator was not found: $indexToolPath"
$liveIndexText = & $indexToolPath -Path $manifestArtifact.path -ExpectedEntryCount ([int]$expectedImgCount) `
    -ExpectedSha256 $manifestArtifact.sha256 -AsJson | Out-String
$liveIndex = $liveIndexText | ConvertFrom-Json
Assert-LongEqual (Get-RequiredProperty $liveIndex 'EntryCount' 'Live independent index') $expectedImgCount `
    'Live independent index entry count'
Assert-LongEqual (Get-RequiredProperty $liveIndex 'UniquePathCount' 'Live independent index') $expectedImgCount `
    'Live independent index unique path count'

Assert-TextEqual (Get-RequiredProperty (Get-RequiredProperty $release 'packageSummary' 'Release report') `
    'payloadEquivalence' 'Release package summary') 'passed' 'Release package payload equivalence'
Assert-TextEqual (Get-RequiredProperty (Get-RequiredProperty $summary 'packageSummary' 'Final summary') `
    'payloadEquivalence' 'Summary package summary') 'passed' 'Summary package payload equivalence'
Assert-TextEqual (Get-RequiredProperty (Get-RequiredProperty $summary 'packageSummary' 'Final summary') `
    'selectedSourceEquivalence' 'Summary package summary') 'passed' 'Summary selected-source equivalence'

$manifestToolchain = Get-RequiredProperty $manifestRelease 'toolchain' 'Manifest fullSkillRelease'
$releaseToolchain = Get-RequiredProperty $release 'toolchain' 'Release report'
$toolBindings = @(
    [pscustomobject]@{ field = 'packagerSha256'; label = 'custom-npk-packager' },
    [pscustomobject]@{ field = 'resourcePlanValidatorSha256'; label = 'resource-plan-validator' },
    [pscustomobject]@{ field = 'finalReleaseValidatorSha256'; label = 'final-release-validator' },
    [pscustomobject]@{ field = 'independentIndexValidatorSha256'; label = 'independent-index' },
    [pscustomobject]@{ field = 'fullFrameExportSha256'; label = 'full-frame-export' }
)
$summaryTools = @((Get-RequiredProperty $provenance 'tools' 'Final summary provenance'))
foreach ($binding in $toolBindings) {
    $manifestHash = Get-NormalizedHash `
        -Value (Get-RequiredProperty $manifestToolchain $binding.field 'Manifest toolchain') `
        -Label "Manifest toolchain $($binding.field)"
    $releaseHash = Get-NormalizedHash `
        -Value (Get-RequiredProperty $releaseToolchain $binding.field 'Release toolchain') `
        -Label "Release toolchain $($binding.field)"
    Assert-TextEqual $releaseHash $manifestHash "Manifest/release toolchain $($binding.field)"
    $matches = @($summaryTools | Where-Object { $_.label -eq $binding.label })
    Assert-Condition -Condition ($matches.Count -eq 1) `
        -Message "Final summary must contain exactly one '$($binding.label)' tool snapshot; found $($matches.Count)."
    $summaryHash = Get-NormalizedHash -Value $matches[0].sha256 -Label "Summary tool $($binding.label)"
    Assert-TextEqual $summaryHash $manifestHash "Manifest/summary toolchain $($binding.field)"
}

$resourcePlanValidators = @($summaryTools | Where-Object { $_.label -eq 'resource-plan-validator' })
Assert-Condition -Condition ($resourcePlanValidators.Count -eq 1) `
    -Message "Final summary must contain exactly one resource-plan-validator; found $($resourcePlanValidators.Count)."
$resourcePlanValidatorPath = Resolve-ExistingFile -Value ([string]$resourcePlanValidators[0].path) `
    -BaseDirectory $summaryDirectory -Label 'Resource-plan validator'
$resourcePlanValidatorCommand = Get-Command -LiteralPath $resourcePlanValidatorPath -ErrorAction Stop
$resourcePlanValidatorArguments = @{ ResourcePlanPath = $manifestPlan.path }
if ($resourcePlanValidatorCommand.Parameters.ContainsKey('RepoRoot')) {
    $resourcePlanValidatorArguments.RepoRoot = $script:RepositoryRoot
}
if ($resourcePlanValidatorCommand.Parameters.ContainsKey('AsJson')) {
    $resourcePlanValidatorArguments.AsJson = $true
}
$resourcePlanGateText = & $resourcePlanValidatorPath @resourcePlanValidatorArguments | Out-String
Assert-Condition -Condition (-not [string]::IsNullOrWhiteSpace($resourcePlanGateText)) `
    -Message 'Resource-plan validator returned no result.'
$resourcePlanGate = $resourcePlanGateText | ConvertFrom-Json
Assert-TextEqual (Get-RequiredProperty $resourcePlanGate 'Status' 'Resource-plan validator result') 'passed' `
    'Live resource-plan validation status'

$result = [pscustomobject]@{
    schemaVersion = 1
    status = 'passed'
    mode = 'read-only release metadata closure; no deployment or process operation'
    professionManifest = $manifestPath
    releaseReport = $releasePath
    finalSummary = $manifestSummary.path
    artifact = [pscustomobject]@{
        path = $manifestArtifact.path
        length = $manifestArtifact.length
        sha256 = $manifestArtifact.sha256
        imgCount = [int]$expectedImgCount
        frameCount = [int]$expectedFrameCount
    }
    snapshotCount = $script:SnapshotCount
    provenanceSnapshotCount = $script:ProvenanceSnapshotCount
    contactSheetCount = $contactSheetCount
    resourcePlanValidation = 'passed-live-and-snapshot'
    independentIndex = 'passed-live-and-snapshot'
    fullSkillCoverageProvenAtValidationStart = $false
    fullSkillCoverageProvenAfterMetadataClosure = $true
    targetClientCompatibilityProven = $false
    deployment = 'not-authorized-not-performed'
}

if ($AsJson) {
    $result | ConvertTo-Json -Depth 8
}
else {
    $result
}

[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)]
    [string]$ProfessionManifestPath,

    [string]$ReleaseId,

    [string]$RepoRoot,

    [switch]$AsJson
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
$script:SnapshotCount = 0

function Assert-Condition {
    param([bool]$Condition, [string]$Message)

    if (-not $Condition) {
        throw $Message
    }
}

function Resolve-PathValue {
    param([string]$Value, [string]$BaseDirectory, [string]$Label)

    Assert-Condition (-not [string]::IsNullOrWhiteSpace($Value)) "$Label path is empty."
    $native = $Value.Replace('/', [IO.Path]::DirectorySeparatorChar)
    if (-not [IO.Path]::IsPathRooted($native)) {
        $native = Join-Path $BaseDirectory $native
    }
    return [IO.Path]::GetFullPath($native)
}

function Assert-FileSnapshot {
    param(
        [object]$Snapshot,
        [string]$BaseDirectory,
        [string]$Label,
        [switch]$LengthOptional
    )

    Assert-Condition ($null -ne $Snapshot) "$Label snapshot is missing."
    Assert-Condition ($null -ne $Snapshot.PSObject.Properties['path']) "$Label path is missing."
    Assert-Condition ($null -ne $Snapshot.PSObject.Properties['sha256']) "$Label SHA-256 is missing."
    $path = Resolve-PathValue -Value ([string]$Snapshot.path) -BaseDirectory $BaseDirectory -Label $Label
    Assert-Condition (Test-Path -LiteralPath $path -PathType Leaf) "$Label was not found: $path"
    $item = Get-Item -LiteralPath $path
    if (-not $LengthOptional) {
        Assert-Condition ($null -ne $Snapshot.PSObject.Properties['length']) "$Label length is missing."
    }
    if ($null -ne $Snapshot.PSObject.Properties['length']) {
        Assert-Condition ($item.Length -eq [long]$Snapshot.length) `
            "$Label length changed: actual=$($item.Length) expected=$($Snapshot.length)"
    }
    $actualHash = (Get-FileHash -LiteralPath $path -Algorithm SHA256).Hash
    $expectedHash = ([string]$Snapshot.sha256).ToUpperInvariant()
    Assert-Condition ($expectedHash -match '^[0-9A-F]{64}$') "$Label expected SHA-256 is invalid: $expectedHash"
    Assert-Condition ($actualHash -eq $expectedHash) `
        "$Label SHA-256 changed: actual=$actualHash expected=$expectedHash"
    $script:SnapshotCount++
    return [pscustomobject]@{
        path = $path
        length = [long]$item.Length
        sha256 = $actualHash
    }
}

function New-Snapshot {
    param([string]$Path, [object]$Length, [string]$Sha256)

    $value = [ordered]@{ path = $Path; sha256 = $Sha256 }
    if ($null -ne $Length) {
        $value.length = [long]$Length
    }
    return [pscustomobject]$value
}

function Assert-SameFile {
    param([object]$Left, [object]$Right, [string]$Label)

    Assert-Condition ($Left.path -ieq $Right.path) "$Label path mismatch: left=$($Left.path) right=$($Right.path)"
    Assert-Condition ([long]$Left.length -eq [long]$Right.length) `
        "$Label length mismatch: left=$($Left.length) right=$($Right.length)"
    Assert-Condition ([string]$Left.sha256 -eq [string]$Right.sha256) `
        "$Label SHA-256 mismatch: left=$($Left.sha256) right=$($Right.sha256)"
}

function Assert-NoDeployment {
    param([object]$Deployment, [string]$Label)

    Assert-Condition ($null -ne $Deployment) "$Label deployment record is missing."
    Assert-Condition ($Deployment.authorized -eq $false) "$Label authorized deployment."
    Assert-Condition ($Deployment.performed -eq $false) "$Label records deployment."
    if ($null -ne $Deployment.PSObject.Properties['imagePacks2Write']) {
        Assert-Condition ($Deployment.imagePacks2Write -eq $false) "$Label records an ImagePacks2 write."
    }
    if ($null -ne $Deployment.PSObject.Properties['processOperation']) {
        Assert-Condition ($Deployment.processOperation -eq $false) "$Label records a process operation."
    }
}

$defaultRoot = Split-Path -Parent $PSScriptRoot
$repositoryRoot = if ([string]::IsNullOrWhiteSpace($RepoRoot)) {
    (Resolve-Path -LiteralPath $defaultRoot).Path
}
else {
    (Resolve-Path -LiteralPath $RepoRoot).Path
}
$manifestPath = Resolve-PathValue -Value $ProfessionManifestPath -BaseDirectory $repositoryRoot -Label 'Profession manifest'
Assert-Condition (Test-Path -LiteralPath $manifestPath -PathType Leaf) "Profession manifest was not found: $manifestPath"
$manifestDirectory = Split-Path -Parent $manifestPath
$manifest = Get-Content -LiteralPath $manifestPath -Raw -Encoding UTF8 | ConvertFrom-Json
Assert-Condition ([int]$manifest.schemaVersion -eq 1) 'Unsupported profession manifest schemaVersion.'
$hasCurrentFullSkillRelease = $null -ne $manifest.PSObject.Properties['fullSkillRelease']
if (-not $hasCurrentFullSkillRelease) {
    Assert-Condition ($manifest.coverage.fullSkillCoverageProven -eq $false) `
        'Manifest coverage cannot be true without a current fullSkillRelease.'
}

$historical = @($manifest.historicalFullSkillReleases)
Assert-Condition ($historical.Count -gt 0) 'Profession manifest has no historical full-skill releases.'
$selected = @(if ([string]::IsNullOrWhiteSpace($ReleaseId)) {
        $historical
    }
    else {
        $historical | Where-Object { [string]$_.releaseId -eq $ReleaseId }
    })
Assert-Condition ($selected.Count -gt 0) "Historical release was not found: $ReleaseId"
if (-not [string]::IsNullOrWhiteSpace($ReleaseId)) {
    Assert-Condition ($selected.Count -eq 1) "Historical release ID is not unique: $ReleaseId"
}

$indexValidator = Join-Path $repositoryRoot 'tools\Test-DnfNpkIndex.ps1'
Assert-Condition (Test-Path -LiteralPath $indexValidator -PathType Leaf) `
    "Independent index validator was not found: $indexValidator"
$releaseResults = New-Object 'System.Collections.Generic.List[object]'
foreach ($archive in $selected) {
    $archiveId = [string]$archive.releaseId
    Assert-Condition ([int]$archive.schemaVersion -eq 1) "Historical release schema changed: $archiveId"
    Assert-Condition ([string]$archive.status -eq 'offline-validated-client-pending') `
        "Historical release status changed: $archiveId/$($archive.status)"
    Assert-Condition ($archive.fullSkillCoverageProven -eq $true) `
        "Historical release no longer records its historical coverage conclusion: $archiveId"
    Assert-Condition ($archive.artifact.deployed -eq $false) "Historical artifact records deployment: $archiveId"
    Assert-NoDeployment -Deployment $archive.deployment -Label "Historical release $archiveId"

    $expectedImgCount = [int]$archive.artifact.imgCount
    $expectedFrameCount = [int]$archive.artifact.frameCount
    $expectedEntryCount = [int]$archive.packageSummary.entryCount
    $expectedSourceNpkCount = [int]$archive.packageSummary.sourceNpkCount
    $expectedContactSheetCount = [int]$archive.validation.fullFrame.contactSheetCount
    Assert-Condition ($expectedImgCount -gt 0 -and $expectedFrameCount -gt 0 -and
        $expectedEntryCount -eq $expectedImgCount -and $expectedSourceNpkCount -gt 0 -and
        $expectedContactSheetCount -gt 0) "Historical archive counts are invalid: $archiveId"

    $artifact = Assert-FileSnapshot -Snapshot $archive.artifact -BaseDirectory $manifestDirectory `
        -Label "Historical artifact $archiveId"
    $package = Assert-FileSnapshot -Snapshot $archive.packageSummary -BaseDirectory $manifestDirectory `
        -Label "Historical package summary $archiveId"
    $plan = Assert-FileSnapshot -Snapshot $archive.sourceEvidence.resourcePlan -BaseDirectory $manifestDirectory `
        -Label "Historical resource plan $archiveId"
    $accounting = Assert-FileSnapshot -Snapshot $archive.sourceEvidence.postBuildFrameAccounting `
        -BaseDirectory $manifestDirectory -Label "Historical frame accounting $archiveId"
    $summary = Assert-FileSnapshot -Snapshot $archive.validation.finalSummary -BaseDirectory $manifestDirectory `
        -Label "Historical final summary $archiveId"
    $index = Assert-FileSnapshot -Snapshot $archive.validation.independentIndex -BaseDirectory $manifestDirectory `
        -Label "Historical independent index $archiveId"
    $albumSnapshot = New-Snapshot -Path ([string]$archive.validation.fullFrame.albumInventoryPath) `
        -Length $null -Sha256 ([string]$archive.validation.fullFrame.albumInventorySha256)
    $frameSnapshot = New-Snapshot -Path ([string]$archive.validation.fullFrame.frameInventoryPath) `
        -Length $null -Sha256 ([string]$archive.validation.fullFrame.frameInventorySha256)
    $album = Assert-FileSnapshot -Snapshot $albumSnapshot -BaseDirectory $manifestDirectory `
        -Label "Historical album inventory $archiveId" -LengthOptional
    $frames = Assert-FileSnapshot -Snapshot $frameSnapshot -BaseDirectory $manifestDirectory `
        -Label "Historical frame inventory $archiveId" -LengthOptional

    $releaseReportPath = Resolve-PathValue -Value ([string]$archive.releaseReport) -BaseDirectory $manifestDirectory `
        -Label "Historical release report $archiveId"
    Assert-Condition (Test-Path -LiteralPath $releaseReportPath -PathType Leaf) `
        "Historical release report was not found: $releaseReportPath"
    $releaseDirectory = Split-Path -Parent $releaseReportPath
    $release = Get-Content -LiteralPath $releaseReportPath -Raw -Encoding UTF8 | ConvertFrom-Json
    Assert-Condition ([string]$release.releaseId -eq $archiveId) "Historical release report ID changed: $archiveId"
    Assert-Condition ([string]$release.status -eq 'offline-validated-client-pending') `
        "Historical release report status changed: $archiveId"
    Assert-Condition ($release.coverage.fullSkillCoverageProven -eq $true) `
        "Historical release report coverage changed: $archiveId"
    Assert-Condition ($release.coverage.clientCompatibilityProven -eq $false) `
        "Historical release report claims client compatibility: $archiveId"
    Assert-NoDeployment -Deployment $release.deployment -Label "Historical release report $archiveId"

    $releaseArtifact = Assert-FileSnapshot -Snapshot $release.artifact -BaseDirectory $releaseDirectory `
        -Label "Release-report artifact $archiveId"
    $releasePackage = Assert-FileSnapshot -Snapshot $release.packageSummary -BaseDirectory $releaseDirectory `
        -Label "Release-report package $archiveId"
    $releasePlan = Assert-FileSnapshot -Snapshot $release.sourceEvidence.resourcePlan -BaseDirectory $releaseDirectory `
        -Label "Release-report plan $archiveId"
    $releaseAccounting = Assert-FileSnapshot -Snapshot $release.sourceEvidence.postBuildFrameAccounting `
        -BaseDirectory $releaseDirectory -Label "Release-report accounting $archiveId"
    $releaseSummary = Assert-FileSnapshot -Snapshot $release.validation.finalSummary -BaseDirectory $releaseDirectory `
        -Label "Release-report final summary $archiveId"
    $releaseIndex = Assert-FileSnapshot -Snapshot $release.validation.independentIndex -BaseDirectory $releaseDirectory `
        -Label "Release-report independent index $archiveId"
    $releaseAlbum = Assert-FileSnapshot -Snapshot $release.validation.fullFrame.albumInventory `
        -BaseDirectory $releaseDirectory -Label "Release-report album inventory $archiveId"
    $releaseFrames = Assert-FileSnapshot -Snapshot $release.validation.fullFrame.frameInventory `
        -BaseDirectory $releaseDirectory -Label "Release-report frame inventory $archiveId"

    Assert-SameFile $artifact $releaseArtifact "Archive/release artifact $archiveId"
    Assert-SameFile $package $releasePackage "Archive/release package $archiveId"
    Assert-SameFile $plan $releasePlan "Archive/release plan $archiveId"
    Assert-SameFile $accounting $releaseAccounting "Archive/release accounting $archiveId"
    Assert-SameFile $summary $releaseSummary "Archive/release final summary $archiveId"
    Assert-SameFile $index $releaseIndex "Archive/release independent index $archiveId"
    Assert-SameFile $album $releaseAlbum "Archive/release album inventory $archiveId"
    Assert-SameFile $frames $releaseFrames "Archive/release frame inventory $archiveId"

    $finalDirectory = Split-Path -Parent $summary.path
    $final = Get-Content -LiteralPath $summary.path -Raw -Encoding UTF8 | ConvertFrom-Json
    Assert-Condition ([int]$final.schemaVersion -eq 1) "Historical final summary schema changed: $archiveId"
    Assert-Condition ([string]$final.status -eq 'passed') "Historical final summary did not pass: $archiveId"
    Assert-NoDeployment -Deployment $final.deployment -Label "Historical final summary $archiveId"
    Assert-Condition ($final.validation.manifestScopeOfflineCoverage.eligibleForReleaseMetadataFullSkillCoverage -eq $true) `
        "Historical final summary no longer records release eligibility: $archiveId"
    Assert-Condition ($final.validation.manifestScopeOfflineCoverage.fullSkillCoverageProvenAtValidationStart -eq $false) `
        "Historical final summary did not start from false coverage: $archiveId"
    Assert-Condition ($final.validation.manifestScopeOfflineCoverage.targetClientCompatibilityProven -eq $false) `
        "Historical final summary claims target-client compatibility: $archiveId"

    $finalArtifactSnapshot = New-Snapshot -Path $artifact.path `
        -Length ([long]$final.finalArtifact.length) -Sha256 ([string]$final.finalArtifact.sha256)
    $finalArtifact = Assert-FileSnapshot -Snapshot $finalArtifactSnapshot -BaseDirectory $finalDirectory `
        -Label "Final-summary artifact $archiveId"
    $finalPackageSnapshot = New-Snapshot -Path $package.path `
        -Length ([long]$final.packageSummary.length) -Sha256 ([string]$final.packageSummary.sha256)
    $finalPackage = Assert-FileSnapshot -Snapshot $finalPackageSnapshot -BaseDirectory $finalDirectory `
        -Label "Final-summary package $archiveId"
    Assert-Condition (-not [string]::IsNullOrWhiteSpace([string]$final.resourcePlan.inputPath)) `
        "Final-summary historical resource-plan input path is missing: $archiveId"
    Assert-Condition (-not [string]::IsNullOrWhiteSpace([string]$final.resourcePlan.validatedSnapshotPath)) `
        "Final-summary historical validated-plan path is missing: $archiveId"
    $finalPlanSnapshot = New-Snapshot -Path 'validated-resource-plan.json' `
        -Length ([long]$final.resourcePlan.length) -Sha256 ([string]$final.resourcePlan.sha256)
    $finalPlan = Assert-FileSnapshot -Snapshot $finalPlanSnapshot -BaseDirectory $finalDirectory `
        -Label "Final-summary local validated resource plan $archiveId"
    $finalIndexSnapshot = New-Snapshot -Path $index.path `
        -Length $null -Sha256 ([string]$final.validation.independentIndex.reportSha256)
    $finalIndex = Assert-FileSnapshot -Snapshot $finalIndexSnapshot -BaseDirectory $finalDirectory `
        -Label "Final-summary independent index $archiveId" -LengthOptional
    $finalAlbumSnapshot = New-Snapshot -Path $album.path `
        -Length ([long]$final.validation.fullFrame.albumInventory.length) `
        -Sha256 ([string]$final.validation.fullFrame.albumInventory.sha256)
    $finalAlbum = Assert-FileSnapshot -Snapshot $finalAlbumSnapshot `
        -BaseDirectory $finalDirectory -Label "Final-summary album inventory $archiveId"
    $finalFrameSnapshot = New-Snapshot -Path $frames.path `
        -Length ([long]$final.validation.fullFrame.frameInventory.length) `
        -Sha256 ([string]$final.validation.fullFrame.frameInventory.sha256)
    $finalFrames = Assert-FileSnapshot -Snapshot $finalFrameSnapshot `
        -BaseDirectory $finalDirectory -Label "Final-summary frame inventory $archiveId"
    $finalLogSnapshot = New-Snapshot -Path 'full-frame-validation.log' `
        -Length ([long]$final.validation.fullFrame.log.length) `
        -Sha256 ([string]$final.validation.fullFrame.log.sha256)
    $null = Assert-FileSnapshot -Snapshot $finalLogSnapshot -BaseDirectory $finalDirectory `
        -Label "Final-summary full-frame log $archiveId"

    Assert-SameFile $artifact $finalArtifact "Archive/final artifact $archiveId"
    Assert-SameFile $package $finalPackage "Archive/final package $archiveId"
    Assert-SameFile $plan $finalPlan "Archive/final plan $archiveId"
    Assert-SameFile $index $finalIndex "Archive/final independent index $archiveId"
    Assert-SameFile $album $finalAlbum "Archive/final album inventory $archiveId"
    Assert-SameFile $frames $finalFrames "Archive/final frame inventory $archiveId"

    $contactSheetCount = 0
    foreach ($sheet in @($final.validation.fullFrame.contactSheets)) {
        $sheetName = [IO.Path]::GetFileName([string]$sheet.path)
        Assert-Condition (-not [string]::IsNullOrWhiteSpace($sheetName)) `
            "Historical contact sheet has no filename: $archiveId/$contactSheetCount"
        $localSheetSnapshot = New-Snapshot `
            -Path (Join-Path 'full-frame-validation\sheets' $sheetName) `
            -Length ([long]$sheet.length) -Sha256 ([string]$sheet.sha256)
        $null = Assert-FileSnapshot -Snapshot $localSheetSnapshot -BaseDirectory $finalDirectory `
            -Label "Historical contact sheet $archiveId/$contactSheetCount"
        $contactSheetCount++
    }
    Assert-Condition ($contactSheetCount -eq [int]$archive.validation.fullFrame.contactSheetCount) `
        "Historical contact sheet count changed: actual=$contactSheetCount expected=$($archive.validation.fullFrame.contactSheetCount)"
    Assert-Condition ($contactSheetCount -eq $expectedContactSheetCount) `
        "Historical release contact sheet count changed: $archiveId"
    Assert-Condition ((@($archive.validation.fullFrame.backgrounds) -join ',') -eq 'black,white,checkerboard') `
        "Historical background set changed: $archiveId"
    Assert-Condition ([int]$archive.validation.fullFrame.decodedNonLinkFrames -eq $expectedFrameCount) `
        "Historical decoded frame count changed: $archiveId"
    Assert-Condition ([int]$archive.artifact.imgCount -eq $expectedImgCount -and
        [int]$archive.artifact.frameCount -eq $expectedFrameCount) `
        "Historical artifact count changed: $archiveId"
    Assert-Condition ([int]$archive.packageSummary.entryCount -eq $expectedEntryCount) `
        "Historical package entry count changed: $archiveId"
    Assert-Condition ([string]$archive.packageSummary.payloadEquivalence -eq 'passed') `
        "Historical package payload equivalence changed: $archiveId"

    $packageJson = Get-Content -LiteralPath $package.path -Raw -Encoding UTF8 | ConvertFrom-Json
    Assert-Condition ([int]$packageJson.schemaVersion -eq 1) "Historical package schema changed: $archiveId"
    Assert-Condition ([int]$packageJson.entryCount -eq $expectedEntryCount -and
        @($packageJson.entries).Count -eq $expectedEntryCount) `
        "Historical package entry records changed: $archiveId"
    Assert-Condition (@($packageJson.sources).Count -eq $expectedSourceNpkCount) `
        "Historical package source count changed: $archiveId"
    Assert-Condition ([string]$packageJson.deployment -eq 'not-performed-by-packager') `
        "Historical package records deployment: $archiveId"

    $recordedIndex = Get-Content -LiteralPath $index.path -Raw -Encoding UTF8 | ConvertFrom-Json
    Assert-Condition ([int]$recordedIndex.EntryCount -eq $expectedEntryCount) `
        "Historical recorded index entry count changed: $archiveId"
    Assert-Condition ([int]$recordedIndex.UniquePathCount -eq $expectedEntryCount) `
        "Historical recorded index unique path count changed: $archiveId"
    Assert-Condition ($recordedIndex.HeaderSha256Valid -eq $true) `
        "Historical recorded index header check changed: $archiveId"
    Assert-Condition ([int]$recordedIndex.ImgMagicValidCount -eq $expectedEntryCount) `
        "Historical recorded index IMG magic count changed: $archiveId"

    $liveIndexText = & $indexValidator -Path $artifact.path -ExpectedEntryCount $expectedEntryCount `
        -ExpectedSha256 $artifact.sha256 -AsJson | Out-String
    $liveIndex = $liveIndexText | ConvertFrom-Json
    Assert-Condition ([int]$liveIndex.EntryCount -eq $expectedEntryCount) `
        "Live historical index entry count changed: $archiveId"
    Assert-Condition ([int]$liveIndex.UniquePathCount -eq $expectedEntryCount) `
        "Live historical index path count changed: $archiveId"
    Assert-Condition ($liveIndex.HeaderSha256Valid -eq $true) "Live historical index header check failed: $archiveId"
    Assert-Condition ([int]$liveIndex.ImgMagicValidCount -eq $expectedEntryCount) `
        "Live historical index IMG magic count changed: $archiveId"

    $albumJson = Get-Content -LiteralPath $album.path -Raw -Encoding UTF8 | ConvertFrom-Json
    $frameRows = @(Import-Csv -LiteralPath $frames.path -Encoding UTF8)
    Assert-Condition ([int]$albumJson.AlbumCount -eq $expectedImgCount -and
        [int]$albumJson.FrameCount -eq $expectedFrameCount -and
        [int]$albumJson.DecodedNonLinkFrames -eq $expectedFrameCount -and
        [int]$albumJson.LinkFrames -eq 0 -and [int]$albumJson.HiddenFrames -eq 0 -and
        $frameRows.Count -eq $expectedFrameCount) `
        "Historical full-frame inventory contents changed: $archiveId"
    Assert-Condition ([int]$albumJson.SheetCount -eq $expectedContactSheetCount -and
        (@($albumJson.Backgrounds) -join ',') -eq 'black,white,checkerboard') `
        "Historical full-frame sheet/background contents changed: $archiveId"

    $releaseResults.Add([pscustomobject]@{
        releaseId = $archiveId
        status = 'passed-historical-integrity'
        artifact = [pscustomobject]@{
            path = $artifact.path
            length = $artifact.length
            sha256 = $artifact.sha256
            imgCount = $expectedImgCount
            frameCount = $expectedFrameCount
        }
        packageEntryCount = $expectedEntryCount
        sourceNpkCount = $expectedSourceNpkCount
        contactSheetCount = $contactSheetCount
        independentIndex = 'passed-live-and-snapshot'
        targetClientCompatibilityProven = $false
        deployment = 'not-authorized-not-performed'
    })
}

$releaseArray = $releaseResults.ToArray()
$result = [pscustomobject]@{
    schemaVersion = 1
    status = 'passed'
    mode = 'read-only historical release integrity; no live binding to changed rules or old official source paths'
    professionManifest = $manifestPath
    historicalReleaseCount = $releaseArray.Count
    releases = $releaseArray
    snapshotCount = $script:SnapshotCount
    currentFullSkillReleasePresent = $hasCurrentFullSkillRelease
    currentFullSkillCoverageProven = [bool]$manifest.coverage.fullSkillCoverageProven
    historicalCoverageConclusionsPreserved = $true
    targetClientCompatibilityProven = $false
    deployment = 'not-authorized-not-performed'
}

if ($AsJson) {
    $result | ConvertTo-Json -Depth 10
}
else {
    $result
}
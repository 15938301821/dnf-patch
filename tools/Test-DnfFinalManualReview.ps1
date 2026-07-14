[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)]
    [string]$FinalSummaryPath,

    [Parameter(Mandatory = $true)]
    [string]$ManualReviewPath,

    [int]$MaxAgeHours = 168,

    [string]$ReferenceTimeUtc,

    [string]$RepoRoot,

    [switch]$AsJson
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
$OutputEncoding = [Console]::OutputEncoding = New-Object System.Text.UTF8Encoding($false)

function Assert-Condition {
    param([bool]$Condition, [string]$Message)

    if (-not $Condition) {
        throw $Message
    }
}

function Test-Property {
    param([object]$Object, [string]$Name)

    return $null -ne $Object -and $null -ne $Object.PSObject.Properties[$Name]
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

function Assert-InsideRepository {
    param([string]$Path, [string]$RepositoryRoot, [string]$Label)

    $root = $RepositoryRoot.TrimEnd(
        [IO.Path]::DirectorySeparatorChar,
        [IO.Path]::AltDirectorySeparatorChar)
    $prefix = $root + [IO.Path]::DirectorySeparatorChar
    Assert-Condition ($Path.StartsWith($prefix, [StringComparison]::OrdinalIgnoreCase)) `
        "$Label must stay inside the repository: $Path"
}

function Assert-NoReparsePointPath {
    param([string]$Path, [string]$RepositoryRoot, [string]$Label)

    $candidate = [IO.Path]::GetFullPath($Path)
    $root = [IO.Path]::GetFullPath($RepositoryRoot).TrimEnd(
        [IO.Path]::DirectorySeparatorChar,
        [IO.Path]::AltDirectorySeparatorChar)
    Assert-InsideRepository -Path $candidate -RepositoryRoot $root -Label $Label
    while ($true) {
        if (Test-Path -LiteralPath $candidate) {
            $item = Get-Item -LiteralPath $candidate -Force
            Assert-Condition (
                ($item.Attributes -band [IO.FileAttributes]::ReparsePoint) -eq 0) `
                "$Label cannot traverse a reparse point: $($item.FullName)"
        }
        if ($candidate.Equals($root, [StringComparison]::OrdinalIgnoreCase)) {
            break
        }
        $parent = Split-Path -Parent $candidate
        Assert-Condition (-not [string]::IsNullOrWhiteSpace($parent) -and
            $parent -ne $candidate) "$Label path ancestry could not be resolved: $Path"
        $candidate = $parent
    }
}

function Resolve-ExistingFile {
    param([string]$Value, [string]$BaseDirectory, [string]$RepositoryRoot, [string]$Label)

    $path = Resolve-PathValue -Value $Value -BaseDirectory $BaseDirectory -Label $Label
    Assert-Condition (Test-Path -LiteralPath $path -PathType Leaf) "$Label was not found: $path"
    $path = (Resolve-Path -LiteralPath $path).Path
    Assert-InsideRepository -Path $path -RepositoryRoot $RepositoryRoot -Label $Label
    Assert-NoReparsePointPath -Path $path -RepositoryRoot $RepositoryRoot -Label $Label
    return $path
}

function Get-Snapshot {
    param([string]$Path)

    $item = Get-Item -LiteralPath $Path
    return [pscustomobject]@{
        path = $item.FullName
        length = [long]$item.Length
        sha256 = (Get-FileHash -LiteralPath $item.FullName -Algorithm SHA256).Hash
    }
}

function Assert-Snapshot {
    param(
        [object]$Snapshot,
        [string]$BaseDirectory,
        [string]$RepositoryRoot,
        [string]$Label
    )

    Assert-Condition ($null -ne $Snapshot) "$Label snapshot is missing."
    foreach ($name in @('path', 'length', 'sha256')) {
        Assert-Condition (Test-Property -Object $Snapshot -Name $name) `
            "$Label snapshot is missing '$name'."
    }
    $path = Resolve-ExistingFile -Value ([string]$Snapshot.path) -BaseDirectory $BaseDirectory `
        -RepositoryRoot $RepositoryRoot -Label $Label
    $current = Get-Snapshot -Path $path
    $expectedHash = ([string]$Snapshot.sha256).Trim().ToUpperInvariant()
    Assert-Condition ($expectedHash -match '^[0-9A-F]{64}$') "$Label SHA-256 is invalid."
    Assert-Condition ($current.length -eq [long]$Snapshot.length) `
        "$Label length changed: actual=$($current.length) expected=$($Snapshot.length)"
    Assert-Condition ($current.sha256 -eq $expectedHash) `
        "$Label SHA-256 changed: actual=$($current.sha256) expected=$expectedHash"
    return $current
}

function Assert-SameSnapshot {
    param([object]$Left, [object]$Right, [string]$Label)

    if ($Left.path -ine $Right.path) {
        throw "$Label path differs: left=$($Left.path) right=$($Right.path)"
    }
    if ($Left.length -ne $Right.length) {
        throw "$Label length differs: left=$($Left.length) right=$($Right.length)"
    }
    if ($Left.sha256 -ne $Right.sha256) {
        throw "$Label SHA-256 differs: left=$($Left.sha256) right=$($Right.sha256)"
    }
}

function Assert-NoDeployment {
    param([object]$Deployment, [string]$Label)

    Assert-Condition ($null -ne $Deployment) "$Label deployment record is missing."
    foreach ($name in @(
        'authorized',
        'performed',
        'imagePacks2Write',
        'processOperation')) {
        Assert-Condition (Test-Property -Object $Deployment -Name $name) `
            "$Label deployment.$name is missing."
        Assert-Condition ($Deployment.PSObject.Properties[$name].Value -eq $false) `
            "$Label deployment.$name must be false."
    }
}

Assert-Condition ($MaxAgeHours -ge 1 -and $MaxAgeHours -le 8760) `
    'MaxAgeHours must be between 1 and 8760.'
$defaultRoot = Split-Path -Parent $PSScriptRoot
$repositoryRoot = if ([string]::IsNullOrWhiteSpace($RepoRoot)) {
    (Resolve-Path -LiteralPath $defaultRoot).Path
}
else {
    (Resolve-Path -LiteralPath $RepoRoot).Path
}
$summaryPath = Resolve-ExistingFile -Value $FinalSummaryPath -BaseDirectory $repositoryRoot `
    -RepositoryRoot $repositoryRoot -Label 'Final summary'
$reviewPath = Resolve-ExistingFile -Value $ManualReviewPath -BaseDirectory $repositoryRoot `
    -RepositoryRoot $repositoryRoot -Label 'Manual review'
$summaryDirectory = Split-Path -Parent $summaryPath
$reviewDirectory = Split-Path -Parent $reviewPath
$summary = Get-Content -LiteralPath $summaryPath -Raw -Encoding UTF8 | ConvertFrom-Json
$review = Get-Content -LiteralPath $reviewPath -Raw -Encoding UTF8 | ConvertFrom-Json

Assert-Condition ([int]$review.schemaVersion -eq 1) 'Unsupported manual-review schemaVersion.'
Assert-Condition ([string]$review.status -eq 'passed') 'Manual review status is not passed.'
Assert-Condition ($review.approved -eq $true) 'Manual review is not approved.'
Assert-Condition (Test-Property -Object $review -Name 'reviewedBy') `
    'Manual review reviewedBy is missing.'
$reviewedBy = ([string]$review.reviewedBy).Trim()
Assert-Condition (-not [string]::IsNullOrWhiteSpace($reviewedBy)) `
    'Manual review reviewedBy must be non-empty.'
Assert-Condition ($review.reviewedAllContactSheets -eq $true) `
    'Manual review does not cover every contact sheet.'
Assert-Condition (Test-Property -Object $review -Name 'targetClientCompatibilityProven') `
    'Manual review targetClientCompatibilityProven is missing.'
Assert-Condition ($review.targetClientCompatibilityProven -eq $false) `
    'Manual review cannot claim target-client compatibility.'
Assert-NoDeployment -Deployment $review.deployment -Label 'Manual review'
Assert-Condition ([string]$summary.status -eq 'passed') 'Final summary status is not passed.'
Assert-Condition ($summary.fullSkillCoverageProven -eq $false) `
    'Final summary must remain pre-metadata.'
Assert-Condition ($summary.validation.manifestScopeOfflineCoverage.eligibleForReleaseMetadataFullSkillCoverage -eq $true) `
    'Final summary is not eligible for release metadata.'
Assert-NoDeployment -Deployment $summary.deployment -Label 'Final summary'

$approvedAt = [DateTimeOffset]::MinValue
Assert-Condition ([DateTimeOffset]::TryParse([string]$review.approvedAtUtc, [ref]$approvedAt)) `
    'Manual review approvedAtUtc is invalid.'
Assert-Condition ($approvedAt.Offset -eq [TimeSpan]::Zero) `
    'Manual review approvedAtUtc must use UTC offset zero.'
$now = if ([string]::IsNullOrWhiteSpace($ReferenceTimeUtc)) {
    [DateTimeOffset]::UtcNow
}
else {
    $referenceTime = [DateTimeOffset]::MinValue
    Assert-Condition ([DateTimeOffset]::TryParse($ReferenceTimeUtc, [ref]$referenceTime)) `
        'ReferenceTimeUtc is invalid.'
    Assert-Condition ($referenceTime.Offset -eq [TimeSpan]::Zero) `
        'ReferenceTimeUtc must use UTC offset zero.'
    $referenceTime.ToUniversalTime()
}
Assert-Condition ($approvedAt.ToUniversalTime() -le $now.AddMinutes(5)) `
    'Manual review approval timestamp is in the future.'
Assert-Condition ($approvedAt.ToUniversalTime() -ge $now.AddHours(-$MaxAgeHours)) `
    'Manual review approval is stale.'

$summarySnapshot = Get-Snapshot -Path $summaryPath
$reviewedSummary = Assert-Snapshot -Snapshot $review.finalSummary -BaseDirectory $reviewDirectory `
    -RepositoryRoot $repositoryRoot -Label 'Reviewed final summary'
Assert-SameSnapshot -Left $summarySnapshot -Right $reviewedSummary -Label 'Requested/reviewed final summary'

$expectedBackgrounds = @($summary.validation.fullFrame.backgrounds)
$reviewedBackgrounds = @($review.backgrounds)
Assert-Condition (($expectedBackgrounds -join ',') -eq 'black,white,checkerboard') `
    'Final summary background set changed.'
Assert-Condition (($reviewedBackgrounds -join ',') -eq ($expectedBackgrounds -join ',')) `
    'Manual review background set differs from the final summary.'

$expectedSheets = New-Object 'Collections.Generic.Dictionary[string,object]' (
    [StringComparer]::OrdinalIgnoreCase)
foreach ($sheet in @($summary.validation.fullFrame.contactSheets)) {
    $snapshot = Assert-Snapshot -Snapshot $sheet -BaseDirectory $summaryDirectory `
        -RepositoryRoot $repositoryRoot -Label 'Final-summary contact sheet'
    Assert-Condition (-not $expectedSheets.ContainsKey($snapshot.path)) `
        "Final summary contains a duplicate contact sheet: $($snapshot.path)"
    $expectedSheets.Add($snapshot.path, $snapshot)
}
Assert-Condition ($expectedSheets.Count -gt 0) 'Final summary contains no contact sheets.'
$reviewedSheets = New-Object 'Collections.Generic.Dictionary[string,object]' (
    [StringComparer]::OrdinalIgnoreCase)
foreach ($sheet in @($review.contactSheets)) {
    $snapshot = Assert-Snapshot -Snapshot $sheet -BaseDirectory $reviewDirectory `
        -RepositoryRoot $repositoryRoot -Label 'Reviewed contact sheet'
    Assert-Condition (-not $reviewedSheets.ContainsKey($snapshot.path)) `
        "Manual review contains a duplicate contact sheet: $($snapshot.path)"
    $reviewedSheets.Add($snapshot.path, $snapshot)
}
Assert-Condition ($reviewedSheets.Count -eq $expectedSheets.Count) `
    "Manual review contact-sheet count differs: reviewed=$($reviewedSheets.Count) expected=$($expectedSheets.Count)"
foreach ($path in $expectedSheets.Keys) {
    Assert-Condition $reviewedSheets.ContainsKey($path) "Manual review is missing contact sheet: $path"
    Assert-SameSnapshot -Left $expectedSheets[$path] -Right $reviewedSheets[$path] `
        -Label "Contact sheet $path"
}

foreach ($name in @(
    'blankPageCount',
    'unexpectedFullCanvasBlackFrameCount',
    'layoutAnomalyCount',
    'temporalAnomalyCount',
    'watermarkFindingCount')) {
    Assert-Condition (Test-Property -Object $review.findings -Name $name) `
        "Manual review findings.$name is missing."
    $findingValue = $review.findings.PSObject.Properties[$name].Value
    $findingIsInteger = $findingValue -is [int] -or $findingValue -is [long]
    Assert-Condition $findingIsInteger `
        "Manual review findings.$name must be an explicit integer."
    Assert-Condition ([long]$findingValue -eq 0) `
        "Manual review findings.$name must be zero."
}

$result = [pscustomobject]@{
    schemaVersion = 1
    status = 'passed'
    approved = $true
    approvedAtUtc = $approvedAt.ToUniversalTime().ToString('o')
    referenceTimeUtc = $now.ToUniversalTime().ToString('o')
    reviewedBy = $reviewedBy
    finalSummaryBound = $true
    reviewedAllContactSheets = $true
    contactSheetCount = $expectedSheets.Count
    backgroundCount = $expectedBackgrounds.Count
    findingCount = 0
    fullSkillCoverageProven = $false
    targetClientCompatibilityProven = $false
    deployment = [pscustomobject]@{
        authorized = $false
        performed = $false
        imagePacks2Write = $false
        processOperation = $false
    }
}
if ($AsJson) {
    $result | ConvertTo-Json -Depth 8
}
else {
    $result
}

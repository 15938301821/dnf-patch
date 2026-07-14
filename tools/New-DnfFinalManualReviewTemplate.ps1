[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)]
    [string]$FinalSummaryPath,

    [Parameter(Mandatory = $true)]
    [string]$OutputPath,

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

function Get-RelativePath {
    param([string]$Path, [string]$BaseDirectory)

    $basePath = [IO.Path]::GetFullPath($BaseDirectory).TrimEnd(
        [IO.Path]::DirectorySeparatorChar,
        [IO.Path]::AltDirectorySeparatorChar) + [IO.Path]::DirectorySeparatorChar
    $baseUri = New-Object Uri($basePath)
    $pathUri = New-Object Uri([IO.Path]::GetFullPath($Path))
    return [Uri]::UnescapeDataString($baseUri.MakeRelativeUri($pathUri).ToString())
}

function Get-Snapshot {
    param([string]$Path, [string]$BaseDirectory)

    $item = Get-Item -LiteralPath $Path
    return [ordered]@{
        path = Get-RelativePath -Path $item.FullName -BaseDirectory $BaseDirectory
        length = [long]$item.Length
        sha256 = (Get-FileHash -LiteralPath $item.FullName -Algorithm SHA256).Hash
    }
}

$defaultRoot = Split-Path -Parent $PSScriptRoot
$repositoryRoot = if ([string]::IsNullOrWhiteSpace($RepoRoot)) {
    (Resolve-Path -LiteralPath $defaultRoot).Path
}
else {
    (Resolve-Path -LiteralPath $RepoRoot).Path
}
$summaryPath = Resolve-ExistingFile -Value $FinalSummaryPath -BaseDirectory $repositoryRoot `
    -RepositoryRoot $repositoryRoot -Label 'Final summary'
$outputPath = Resolve-PathValue -Value $OutputPath -BaseDirectory $repositoryRoot `
    -Label 'Manual-review template'
Assert-InsideRepository -Path $outputPath -RepositoryRoot $repositoryRoot `
    -Label 'Manual-review template'
Assert-NoReparsePointPath -Path $outputPath -RepositoryRoot $repositoryRoot `
    -Label 'Manual-review template'
Assert-Condition ([IO.Path]::GetExtension($outputPath) -ieq '.json') `
    'Manual-review template must use the .json extension.'
Assert-Condition (-not (Test-Path -LiteralPath $outputPath)) `
    "Refusing to overwrite a manual-review template: $outputPath"
$summary = Get-Content -LiteralPath $summaryPath -Raw -Encoding UTF8 | ConvertFrom-Json
Assert-Condition ([string]$summary.status -eq 'passed') 'Final summary status is not passed.'
Assert-Condition ($summary.fullSkillCoverageProven -eq $false) `
    'Final summary must remain pre-metadata.'
Assert-Condition ($summary.validation.manifestScopeOfflineCoverage.eligibleForReleaseMetadataFullSkillCoverage -eq $true) `
    'Final summary is not eligible for release metadata.'
$summaryDirectory = Split-Path -Parent $summaryPath
$outputDirectory = Split-Path -Parent $outputPath
$contactSheets = New-Object 'Collections.Generic.List[object]'
foreach ($sheet in @($summary.validation.fullFrame.contactSheets)) {
    $sheetPath = Resolve-ExistingFile -Value ([string]$sheet.path) -BaseDirectory $summaryDirectory `
        -RepositoryRoot $repositoryRoot -Label 'Final contact sheet'
    $item = Get-Item -LiteralPath $sheetPath
    $hash = (Get-FileHash -LiteralPath $sheetPath -Algorithm SHA256).Hash
    Assert-Condition ($item.Length -eq [long]$sheet.length -and
        $hash -eq ([string]$sheet.sha256).ToUpperInvariant()) `
        "Final contact-sheet snapshot changed: $sheetPath"
    $contactSheets.Add((Get-Snapshot -Path $sheetPath -BaseDirectory $outputDirectory))
}
Assert-Condition ($contactSheets.Count -gt 0) 'Final summary contains no contact sheets.'
$template = [ordered]@{
    schemaVersion = 1
    status = 'pending-human-review'
    approved = $false
    approvedAtUtc = $null
    reviewedBy = $null
    reviewedAllContactSheets = $false
    finalSummary = Get-Snapshot -Path $summaryPath -BaseDirectory $outputDirectory
    backgrounds = @($summary.validation.fullFrame.backgrounds)
    contactSheets = $contactSheets.ToArray()
    findings = [ordered]@{
        blankPageCount = $null
        unexpectedFullCanvasBlackFrameCount = $null
        layoutAnomalyCount = $null
        temporalAnomalyCount = $null
        watermarkFindingCount = $null
    }
    notes = $null
    targetClientCompatibilityProven = $false
    deployment = [ordered]@{
        authorized = $false
        performed = $false
        imagePacks2Write = $false
        processOperation = $false
    }
}
if (-not (Test-Path -LiteralPath $outputDirectory -PathType Container)) {
    New-Item -ItemType Directory -Path $outputDirectory -Force | Out-Null
}
Assert-NoReparsePointPath -Path $outputPath -RepositoryRoot $repositoryRoot `
    -Label 'Manual-review template before write'
$temporary = Join-Path $outputDirectory (
    '.' + [IO.Path]::GetFileName($outputPath) + '.' + [Guid]::NewGuid().ToString('N') + '.tmp')
try {
    $template | ConvertTo-Json -Depth 12 | Set-Content -LiteralPath $temporary -Encoding UTF8
    $null = Get-Content -LiteralPath $temporary -Raw -Encoding UTF8 | ConvertFrom-Json
    [IO.File]::Move($temporary, $outputPath)
}
finally {
    if (Test-Path -LiteralPath $temporary) {
        Remove-Item -LiteralPath $temporary -Force
    }
}
$result = [pscustomobject]@{
    schemaVersion = 1
    status = 'passed'
    state = 'manual-review-template-created'
    template = Get-Snapshot -Path $outputPath -BaseDirectory $repositoryRoot
    approved = $false
    contactSheetCount = $contactSheets.Count
    fullSkillCoverageProven = $false
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

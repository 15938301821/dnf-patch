[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)]
    [string]$ResourcePlanPath,

    [Parameter(Mandatory = $true)]
    [string]$FinalNpk,

    [Parameter(Mandatory = $true)]
    [string]$PackageSummaryPath,

    [Parameter(Mandatory = $true)]
    [string]$OutputDirectory,

    [string]$RepoRoot,

    [string]$ExtractorDirectory,

    [switch]$AsJson
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
$OutputEncoding = [Console]::OutputEncoding = New-Object System.Text.UTF8Encoding($false)
$script:RepositoryRoot = $null
$script:LegacySourcePrefix = $null
$script:LegacyTargetPrefix = $null
$script:HistoricalPathRelocationCount = 0

function Assert-Condition {
    param([bool]$Condition, [string]$Message)

    if (-not $Condition) {
        throw $Message
    }
}

function Test-ObjectProperty {
    param([object]$Object, [string]$Name)

    return $null -ne $Object -and $null -ne $Object.PSObject.Properties[$Name]
}

function Get-ObjectProperty {
    param([object]$Object, [string]$Name, [object]$Default = $null)

    if (-not (Test-ObjectProperty -Object $Object -Name $Name)) {
        return $Default
    }
    return $Object.PSObject.Properties[$Name].Value
}

function Resolve-PathValue {
    param([string]$Value, [string]$BaseDirectory, [string]$Label)

    Assert-Condition (-not [string]::IsNullOrWhiteSpace($Value)) "$Label path is empty."
    $normalized = $Value.Replace('\', '/')
    $resolutionBase = $BaseDirectory
    if (-not [IO.Path]::IsPathRooted($Value) -and
        -not [string]::IsNullOrWhiteSpace($script:LegacySourcePrefix) -and
        $normalized.StartsWith($script:LegacySourcePrefix, [StringComparison]::Ordinal)) {
        $normalized = $script:LegacyTargetPrefix +
        $normalized.Substring($script:LegacySourcePrefix.Length)
        $resolutionBase = $script:RepositoryRoot
        $script:HistoricalPathRelocationCount++
    }
    $native = $normalized.Replace('/', [IO.Path]::DirectorySeparatorChar)
    if (-not [IO.Path]::IsPathRooted($native)) {
        $native = Join-Path $resolutionBase $native
    }
    return [IO.Path]::GetFullPath($native)
}

function Initialize-HistoricalPathRelocation {
    param([object]$Plan)

    Assert-Condition (Test-ObjectProperty -Object $Plan -Name 'historicalPathRelocation') `
        'Historical path relocation policy is missing.'
    $policy = $Plan.historicalPathRelocation
    $professionManifestRelative = ([string]$Plan.professionManifestPath).Replace('\', '/')
    Assert-Condition ($professionManifestRelative -match '^jobs/([^/]+)/manifest\.json$') `
        'Profession manifest must use the current jobs route.'
    $professionName = $Matches[1]
    $expectedSourcePrefix = $professionName + '/'
    $expectedTargetPrefix = 'jobs/' + $professionName + '/'
    Assert-Condition ([string]$policy.mode -eq 'exact-repository-relative-prefix' -and
        [string]$policy.sourcePrefix -eq $expectedSourcePrefix -and
        [string]$policy.targetPrefix -eq $expectedTargetPrefix -and
        [string]$policy.absolutePaths -eq 'not-relocated' -and
        [string]$policy.otherPrefixes -eq 'not-relocated') `
        'Historical path relocation policy changed.'
    $script:LegacySourcePrefix = $expectedSourcePrefix
    $script:LegacyTargetPrefix = $expectedTargetPrefix
}

function Assert-PathInsideRepository {
    param([string]$Path, [string]$RepositoryRoot, [string]$Label)

    $root = $RepositoryRoot.TrimEnd(
        [IO.Path]::DirectorySeparatorChar,
        [IO.Path]::AltDirectorySeparatorChar)
    $prefix = $root + [IO.Path]::DirectorySeparatorChar
    Assert-Condition ($Path.StartsWith($prefix, [StringComparison]::OrdinalIgnoreCase)) `
        "$Label must stay inside the repository: $Path"
}

function Resolve-ExistingFile {
    param([string]$Value, [string]$BaseDirectory, [string]$RepositoryRoot, [string]$Label)

    $path = Resolve-PathValue -Value $Value -BaseDirectory $BaseDirectory -Label $Label
    Assert-Condition (Test-Path -LiteralPath $path -PathType Leaf) "$Label was not found: $path"
    $resolved = (Resolve-Path -LiteralPath $path).Path
    Assert-PathInsideRepository -Path $resolved -RepositoryRoot $RepositoryRoot -Label $Label
    return $resolved
}

function Get-NormalizedHash {
    param([object]$Value, [string]$Label)

    $hash = ([string]$Value).Trim().ToUpperInvariant()
    Assert-Condition ($hash -match '^[0-9A-F]{64}$') "$Label is not a SHA-256 value: '$Value'"
    return $hash
}

function Get-InternalPath {
    param([object]$Value)

    $path = ([string]$Value).Trim().Replace('\', '/')
    Assert-Condition (-not [string]::IsNullOrWhiteSpace($path)) 'An IMG path is empty.'
    return $path
}

function New-StringSet {
    param([object[]]$Values, [string]$Label, [switch]$AllowEmpty)

    $set = New-Object 'Collections.Generic.HashSet[string]' ([StringComparer]::OrdinalIgnoreCase)
    foreach ($value in @($Values)) {
        $normalized = Get-InternalPath -Value $value
        Assert-Condition $set.Add($normalized) "$Label contains a duplicate value: $normalized"
    }
    if (-not $AllowEmpty) {
        Assert-Condition ($set.Count -gt 0) "$Label is empty."
    }
    return ,$set
}

function New-FilePathSet {
    param([object[]]$Values, [string]$Label)

    $set = New-Object 'Collections.Generic.HashSet[string]' ([StringComparer]::OrdinalIgnoreCase)
    foreach ($value in @($Values)) {
        Assert-Condition (-not [string]::IsNullOrWhiteSpace([string]$value)) `
            "$Label contains an empty path."
        $path = [IO.Path]::GetFullPath([string]$value)
        Assert-Condition $set.Add($path) "$Label contains a duplicate path: $path"
    }
    Assert-Condition ($set.Count -gt 0) "$Label is empty."
    return ,$set
}

function Assert-SetEqual {
    param(
        [Collections.Generic.HashSet[string]]$Expected,
        [Collections.Generic.HashSet[string]]$Actual,
        [string]$Label
    )

    $missing = @($Expected | Where-Object { -not $Actual.Contains($_) } | Sort-Object)
    $unexpected = @($Actual | Where-Object { -not $Expected.Contains($_) } | Sort-Object)
    Assert-Condition ($missing.Count -eq 0 -and $unexpected.Count -eq 0) `
        "$Label differs. Missing=[$($missing -join ',')]; Unexpected=[$($unexpected -join ',')]"
}

function Assert-FileSnapshot {
    param(
        [object]$Snapshot,
        [string]$BaseDirectory,
        [string]$RepositoryRoot,
        [string]$Label,
        [bool]$RequireInsideRepository = $true
    )

    Assert-Condition ($null -ne $Snapshot) "$Label snapshot is missing."
    foreach ($name in @('path', 'length', 'sha256')) {
        Assert-Condition (Test-ObjectProperty -Object $Snapshot -Name $name) `
            "$Label snapshot is missing '$name'."
    }
    $path = Resolve-PathValue -Value ([string]$Snapshot.path) -BaseDirectory $BaseDirectory -Label $Label
    Assert-Condition (Test-Path -LiteralPath $path -PathType Leaf) "$Label was not found: $path"
    $path = (Resolve-Path -LiteralPath $path).Path
    if ($RequireInsideRepository) {
        Assert-PathInsideRepository -Path $path -RepositoryRoot $RepositoryRoot -Label $Label
    }
    $item = Get-Item -LiteralPath $path
    $hash = (Get-FileHash -LiteralPath $path -Algorithm SHA256).Hash
    $expectedHash = Get-NormalizedHash -Value $Snapshot.sha256 -Label "$Label expected hash"
    Assert-Condition ($item.Length -eq [long]$Snapshot.length) `
        "$Label length changed: actual=$($item.Length) expected=$($Snapshot.length)"
    Assert-Condition ($hash -eq $expectedHash) `
        "$Label SHA-256 changed: actual=$hash expected=$expectedHash"
    return [pscustomobject]@{
        path = $path
        length = [long]$item.Length
        sha256 = $hash
    }
}

function New-FileSnapshot {
    param([string]$Path)

    $item = Get-Item -LiteralPath $Path
    return [pscustomobject]@{
        path = $item.FullName
        length = [long]$item.Length
        sha256 = (Get-FileHash -LiteralPath $item.FullName -Algorithm SHA256).Hash
    }
}

function Get-FutureSnapshot {
    param(
        [string]$StagedPath,
        [string]$StagingRoot,
        [string]$PublishedRoot
    )

    $stagingPrefix = $StagingRoot.TrimEnd([IO.Path]::DirectorySeparatorChar) +
        [IO.Path]::DirectorySeparatorChar
    Assert-Condition ($StagedPath.StartsWith($stagingPrefix, [StringComparison]::OrdinalIgnoreCase)) `
        "Staged evidence is outside the staging directory: $StagedPath"
    $relative = $StagedPath.Substring($stagingPrefix.Length)
    $publishedPath = Join-Path $PublishedRoot $relative
    $item = Get-Item -LiteralPath $StagedPath
    return [pscustomobject]@{
        path = $publishedPath
        length = [long]$item.Length
        sha256 = (Get-FileHash -LiteralPath $StagedPath -Algorithm SHA256).Hash
    }
}

function Assert-NoDeployment {
    param([object]$Deployment, [string]$Label)

    Assert-Condition ($null -ne $Deployment) "$Label deployment evidence is missing."
    if ($Deployment -is [string]) {
        $value = ([string]$Deployment).Trim()
        Assert-Condition ($value -match '(?i)not[- ](?:authorized|performed)') `
            "$Label records an unsafe deployment state: $value"
        return
    }
    if (Test-ObjectProperty -Object $Deployment -Name 'authorized') {
        Assert-Condition ($Deployment.authorized -eq $false) "$Label authorized deployment."
    }
    Assert-Condition (Test-ObjectProperty -Object $Deployment -Name 'performed') `
        "$Label deployment.performed is missing."
    Assert-Condition ($Deployment.performed -eq $false) "$Label records deployment."
    foreach ($name in @('imagePacks2Write', 'processOperation')) {
        if (Test-ObjectProperty -Object $Deployment -Name $name) {
            Assert-Condition ($Deployment.PSObject.Properties[$name].Value -eq $false) `
                "$Label records $name."
        }
    }
}

function Get-ByteHash {
    param([byte[]]$Bytes)

    $sha = [Security.Cryptography.SHA256]::Create()
    try {
        return [BitConverter]::ToString($sha.ComputeHash($Bytes)).Replace('-', '')
    }
    finally {
        $sha.Dispose()
    }
}

function Test-ByteArrayEqual {
    param([byte[]]$Left, [byte[]]$Right)

    if ($null -eq $Left -or $null -eq $Right -or $Left.Length -ne $Right.Length) {
        return $false
    }
    for ($index = 0; $index -lt $Left.Length; $index++) {
        if ($Left[$index] -ne $Right[$index]) {
            return $false
        }
    }
    return $true
}

function Read-NpkPayloadInventory {
    param([string]$Path, [string]$Label)

    $nameKey = [Text.Encoding]::ASCII.GetBytes(
        'puchikon@neople dungeon and fighter ' + ('DNF' * 73) + [char]0)
    Assert-Condition ($nameKey.Length -eq 256) 'Unexpected NPK filename key length.'

    $stream = [IO.File]::Open($Path, [IO.FileMode]::Open, [IO.FileAccess]::Read, [IO.FileShare]::Read)
    $reader = New-Object IO.BinaryReader($stream, [Text.Encoding]::ASCII, $true)
    $sha = [Security.Cryptography.SHA256]::Create()
    try {
        $magic = [Text.Encoding]::ASCII.GetString($reader.ReadBytes(16)).TrimEnd([char]0)
        Assert-Condition ($magic -eq 'NeoplePack_Bill') "$Label has invalid NPK magic '$magic'."
        $entryCount = $reader.ReadInt32()
        Assert-Condition ($entryCount -gt 0) "$Label has invalid entry count $entryCount."
        $headerLength = 20L + 264L * $entryCount
        $dataStart = $headerLength + 32L
        Assert-Condition ($dataStart -le $stream.Length) "$Label header exceeds the file length."

        $entries = New-Object 'Collections.Generic.List[object]'
        $pathSet = New-Object 'Collections.Generic.HashSet[string]' ([StringComparer]::OrdinalIgnoreCase)
        for ($entryIndex = 0; $entryIndex -lt $entryCount; $entryIndex++) {
            $offset = [long]$reader.ReadInt32()
            $size = [long]$reader.ReadInt32()
            $encryptedName = $reader.ReadBytes(256)
            Assert-Condition ($encryptedName.Length -eq 256) "$Label index entry $entryIndex is truncated."
            $plainName = New-Object byte[] 256
            for ($byteIndex = 0; $byteIndex -lt 256; $byteIndex++) {
                $plainName[$byteIndex] = $encryptedName[$byteIndex] -bxor $nameKey[$byteIndex]
            }
            $nullIndex = [Array]::IndexOf($plainName, [byte]0)
            Assert-Condition ($nullIndex -gt 0) "$Label index entry $entryIndex has an invalid path."
            $internalPath = Get-InternalPath -Value (
                [Text.Encoding]::ASCII.GetString($plainName, 0, $nullIndex))
            Assert-Condition $pathSet.Add($internalPath) "$Label has a duplicate IMG path: $internalPath"
            Assert-Condition ($offset -ge $dataStart -and $size -gt 0 -and
                $offset + $size -le $stream.Length -and $size -le [int]::MaxValue) `
                "$Label entry is outside the NPK: $internalPath"
            $entries.Add([pscustomobject]@{
                path = $internalPath
                offset = $offset
                length = $size
            })
        }

        $storedHeaderHash = $reader.ReadBytes(32)
        Assert-Condition ($storedHeaderHash.Length -eq 32) "$Label header SHA-256 is truncated."
        $hashInputLength = [int]($headerLength - ($headerLength % 17L))
        $stream.Position = 0
        $computedHeaderHash = $sha.ComputeHash($reader.ReadBytes($hashInputLength))
        Assert-Condition (Test-ByteArrayEqual -Left $storedHeaderHash -Right $computedHeaderHash) `
            "$Label header SHA-256 is invalid."

        $payloads = New-Object 'Collections.Generic.List[object]'
        foreach ($entry in $entries) {
            $stream.Position = $entry.offset
            $payload = $reader.ReadBytes([int]$entry.length)
            Assert-Condition ($payload.Length -eq $entry.length) `
                "$Label IMG payload is truncated: $($entry.path)"
            $magicLength = [Math]::Min(18, $payload.Length)
            $magicEnd = [Array]::IndexOf($payload, [byte]0, 0, $magicLength)
            Assert-Condition ($magicEnd -gt 0) "$Label IMG magic is invalid: $($entry.path)"
            $imgMagic = [Text.Encoding]::ASCII.GetString($payload, 0, $magicEnd)
            Assert-Condition ($imgMagic -in @('Neople Img File', 'Neople Image File')) `
                "$Label IMG magic is invalid for $($entry.path): $imgMagic"
            $payloads.Add([pscustomobject]@{
                path = $entry.path
                payloadLength = [long]$entry.length
                payloadSha256 = Get-ByteHash -Bytes $payload
            })
        }
        return [pscustomobject]@{
            path = $Path
            entryCount = $entryCount
            entries = $payloads.ToArray()
        }
    }
    finally {
        $sha.Dispose()
        $reader.Dispose()
        $stream.Dispose()
    }
}

function ConvertTo-EntryDictionary {
    param([object[]]$Entries, [string]$Label)

    $dictionary = New-Object 'Collections.Generic.Dictionary[string,object]' (
        [StringComparer]::OrdinalIgnoreCase)
    foreach ($entry in @($Entries)) {
        $path = Get-InternalPath -Value $entry.path
        Assert-Condition (-not $dictionary.ContainsKey($path)) "$Label contains a duplicate IMG path: $path"
        $dictionary.Add($path, $entry)
    }
    return ,$dictionary
}

function Get-PackageResult {
    param([object]$Summary)

    $candidates = @($Summary)
    foreach ($name in @('package', 'packagerResult', 'result', 'artifact')) {
        if (Test-ObjectProperty -Object $Summary -Name $name) {
            $candidates += $Summary.PSObject.Properties[$name].Value
        }
    }
    foreach ($candidate in $candidates) {
        if ($null -ne $candidate -and
            (Test-ObjectProperty -Object $candidate -Name 'entries')) {
            return $candidate
        }
    }
    throw 'Package summary does not contain a package result with entries.'
}

$defaultRoot = Split-Path -Parent $PSScriptRoot
$repositoryRoot = if ([string]::IsNullOrWhiteSpace($RepoRoot)) {
    (Resolve-Path -LiteralPath $defaultRoot).Path
}
else {
    (Resolve-Path -LiteralPath $RepoRoot).Path
}
$script:RepositoryRoot = $repositoryRoot
Import-Module (Join-Path $repositoryRoot 'tools\DnfPatch.Toolchain.psm1') -Force

$planPath = Resolve-ExistingFile -Value $ResourcePlanPath -BaseDirectory $repositoryRoot `
    -RepositoryRoot $repositoryRoot -Label 'Aseprite migration resource plan'
$migrationValidator = Resolve-ExistingFile -Value 'tools/Test-VergilAsepriteMigrationPlan.ps1' `
    -BaseDirectory $repositoryRoot -RepositoryRoot $repositoryRoot -Label 'Aseprite migration validator'
$migrationText = (& $migrationValidator -ResourcePlanPath $planPath -RepoRoot $repositoryRoot -AsJson | Out-String).Trim()
Assert-Condition (-not [string]::IsNullOrWhiteSpace($migrationText)) `
    'Aseprite migration validator returned no JSON.'
$migration = $migrationText | ConvertFrom-Json
Assert-Condition ([string]$migration.status -eq 'passed') 'Aseprite migration validation did not pass.'
if ($migration.readyForAggregation -ne $true) {
    $blockerText = @($migration.blockers) -join ','
    throw "Aseprite migration is not ready for final aggregation. Blockers=[$blockerText]"
}
Assert-Condition ([string]$migration.state -eq 'ready-for-aggregation') `
    'Aseprite migration state is not ready-for-aggregation.'
Assert-Condition ($migration.fullSkillCoverageProven -eq $false) `
    'Pre-aggregation migration evidence cannot prove full coverage.'
Assert-Condition ([int]$migration.components.count -eq 31 -and
    [int]$migration.components.selectedImgCount -eq 417) `
    'Aseprite migration component totals changed.'
Assert-Condition ([string]$migration.components.status -eq 'passed-live-revalidation' -and
    [string]$migration.components.artifactSnapshotsAndIndependentIndexes -eq 'passed' -and
    [int]$migration.components.configCount -eq 31 -and
    [string]$migration.components.outputPathBindings -eq 'passed' -and
    [int]$migration.components.outputPathBindingCount -eq 31 -and
    [int]$migration.components.outputPathBindingIssueCount -eq 0 -and
    [int]$migration.components.summaryToolchainSnapshotCount -eq 7 -and
    [int]$migration.components.baselineBuilderSnapshotCount -eq 7 -and
    [int]$migration.components.provenanceIssueCount -eq 0) `
    'Aseprite migration component config or toolchain provenance did not pass.'
Assert-Condition ($migration.cutin.renderValidated -eq $true -and
    $migration.cutin.manualReviewValidated -eq $true -and
    $migration.cutin.buildValidated -eq $true) `
    'Aseprite Cut-in render, manual review, and build must all be validated.'
$remainingBlockers = @($migration.blockers | Where-Object {
    $_ -notin @(
        'final-aggregation-not-performed',
        'final-validation-not-performed',
        'release-closure-not-performed')
})
Assert-Condition ($remainingBlockers.Count -eq 0) `
    "Aseprite migration still has pre-aggregation blockers: $($remainingBlockers -join ',')"

$plan = Get-Content -LiteralPath $planPath -Raw -Encoding UTF8 | ConvertFrom-Json
Assert-Condition ([int]$plan.schemaVersion -eq 1) 'Unsupported migration resource-plan schemaVersion.'
Assert-Condition ([string]$plan.planId -eq [string]$migration.planId) `
    'Migration plan identity differs from the readiness gate.'
Initialize-HistoricalPathRelocation -Plan $plan
Assert-Condition ($plan.coverage.fullSkillCoverageProven -eq $false) `
    'Migration resource plan must start with coverage=false.'
Assert-NoDeployment -Deployment $plan.deployment -Label 'Migration resource plan'
$baselineSnapshot = Assert-FileSnapshot -Snapshot $plan.baselinePlan -BaseDirectory $repositoryRoot `
    -RepositoryRoot $repositoryRoot -Label 'Baseline resource plan'
$sourceMigrationSnapshot = Assert-FileSnapshot -Snapshot $plan.sourceMigration -BaseDirectory $repositoryRoot `
    -RepositoryRoot $repositoryRoot -Label 'Source migration audit'
$baseline = Get-Content -LiteralPath $baselineSnapshot.path -Raw -Encoding UTF8 | ConvertFrom-Json
$sourceMigration = Get-Content -LiteralPath $sourceMigrationSnapshot.path -Raw -Encoding UTF8 | ConvertFrom-Json
Assert-Condition ([string]$baseline.planId -eq [string]$plan.baselinePlan.planId) `
    'Baseline resource-plan identity changed.'
Assert-Condition ($baseline.coverage.fullSkillCoverageProven -eq $false) `
    'Baseline resource plan must remain pre-release.'
Assert-Condition ([string]$sourceMigration.status -eq 'passed' -and
    [int]$sourceMigration.counts.matched -eq [int]$sourceMigration.counts.uniqueExpectedSnapshots -and
    [int]$sourceMigration.counts.contentDrift -eq 0 -and
    [int]$sourceMigration.counts.missing -eq 0) `
    'Source migration evidence is not a complete identity match.'
Assert-NoDeployment -Deployment $sourceMigration.deployment -Label 'Source migration audit'
$officialSourceReports = New-Object 'Collections.Generic.List[object]'
$baselineSourcesByName = New-Object 'Collections.Generic.Dictionary[string,object]' (
    [StringComparer]::OrdinalIgnoreCase)
foreach ($source in @($baseline.sources)) {
    $sourceName = [IO.Path]::GetFileName([string]$source.sourceNpk.path)
    Assert-Condition (-not $baselineSourcesByName.ContainsKey($sourceName)) `
        "Baseline source filename is duplicated: $sourceName"
    $baselineSourcesByName.Add($sourceName, $source)
}
Assert-Condition ($baselineSourcesByName.Count -eq 28) `
    "Expected 28 baseline official sources, found $($baselineSourcesByName.Count)."
$matchedSourceNames = New-Object 'Collections.Generic.HashSet[string]' ([StringComparer]::OrdinalIgnoreCase)
foreach ($record in @($sourceMigration.sources | Where-Object {
    $baselineSourcesByName.ContainsKey([string]$_.name)
})) {
    $sourceName = [string]$record.name
    Assert-Condition ([string]$record.status -eq 'matched' -and $matchedSourceNames.Add($sourceName)) `
        "Current source migration record is not uniquely matched: $sourceName"
    $baselineSource = $baselineSourcesByName[$sourceName]
    $baselineSourceSnapshot = $baselineSource.sourceNpk
    $baselineHash = Get-NormalizedHash -Value $baselineSourceSnapshot.sha256 `
        -Label "Baseline source hash $sourceName"
    Assert-Condition ([long]$record.expectedLength -eq [long]$baselineSourceSnapshot.length -and
        [long]$record.actualLength -eq [long]$baselineSourceSnapshot.length -and
        (Get-NormalizedHash -Value $record.expectedSha256 -Label "Migrated expected hash $sourceName") -eq $baselineHash -and
        (Get-NormalizedHash -Value $record.actualSha256 -Label "Migrated actual hash $sourceName") -eq $baselineHash) `
        "Current source migration identity differs from the v3 source snapshot: $sourceName"
    $snapshot = [pscustomobject]@{
        path = [string]$record.activePath
        length = [long]$record.actualLength
        sha256 = [string]$record.actualSha256
    }
    $verifiedSource = Assert-FileSnapshot -Snapshot $snapshot -BaseDirectory $repositoryRoot `
        -RepositoryRoot $repositoryRoot -Label "Current official source $sourceName" `
        -RequireInsideRepository $false
    $sourceItem = Get-Item -LiteralPath $verifiedSource.path
    $sourceLastWriteTime = $sourceItem.LastWriteTime.ToString('o')
    Assert-Condition (Test-ObjectProperty -Object $record -Name 'actualLastWriteTime') `
        "Current source migration lacks a last-write time: $sourceName"
    Assert-Condition ($sourceLastWriteTime -eq [string]$record.actualLastWriteTime) `
        "Current official source last-write time changed: actual=$sourceLastWriteTime expected=$($record.actualLastWriteTime) path=$($verifiedSource.path)"
    $officialSourceReports.Add([pscustomobject]@{
        sourceId = [string]$baselineSource.id
        path = $verifiedSource.path
        length = $verifiedSource.length
        lastWriteTime = $sourceLastWriteTime
        sha256 = $verifiedSource.sha256
    })
}
Assert-Condition ($matchedSourceNames.Count -eq $baselineSourcesByName.Count) `
    "Current source migration does not cover all 28 baseline source identities: $($matchedSourceNames.Count)/$($baselineSourcesByName.Count)"

$finalPath = Resolve-ExistingFile -Value $FinalNpk -BaseDirectory $repositoryRoot `
    -RepositoryRoot $repositoryRoot -Label 'Final Aseprite NPK'
$packagePath = Resolve-ExistingFile -Value $PackageSummaryPath -BaseDirectory $repositoryRoot `
    -RepositoryRoot $repositoryRoot -Label 'Aseprite package summary'
$outputPath = Resolve-PathValue -Value $OutputDirectory -BaseDirectory $repositoryRoot `
    -Label 'Final validation output'
Assert-PathInsideRepository -Path $outputPath -RepositoryRoot $repositoryRoot -Label 'Final validation output'
Assert-Condition ([IO.Path]::GetExtension($finalPath) -ieq '.NPK') `
    "Final artifact must use .NPK: $finalPath"
$finalName = [IO.Path]::GetFileName($finalPath)
$packageName = [IO.Path]::GetFileName($packagePath)
$outputName = [IO.Path]::GetFileName($outputPath.TrimEnd([IO.Path]::DirectorySeparatorChar))
foreach ($nameRecord in @(
    [pscustomobject]@{ value = $finalName; label = 'Final NPK' },
    [pscustomobject]@{ value = $packageName; label = 'Package summary' },
    [pscustomobject]@{ value = $outputName; label = 'Validation directory' })) {
    Assert-Condition ($nameRecord.value -match '(?i)aseprite') `
        "$($nameRecord.label) name must identify the Aseprite activity: $($nameRecord.value)"
    Assert-Condition ($nameRecord.value -match '(?i)(?:^|[-_])v[0-9]+(?:[-_.]|$)') `
        "$($nameRecord.label) name must contain a version token: $($nameRecord.value)"
}
Assert-Condition ($finalName -match '(?i)weaponmaster-vergil-dark-blue') `
    "Final NPK name does not identify the theme: $finalName"

if (Test-Path -LiteralPath $outputPath) {
    Assert-Condition (Test-Path -LiteralPath $outputPath -PathType Container) `
        "Validation output exists but is not a directory: $outputPath"
    $existingOutput = @(Get-ChildItem -LiteralPath $outputPath -Force)
    Assert-Condition ($existingOutput.Count -eq 0) `
        "Validation output must be new or empty: $outputPath"
}

$manifestPath = Resolve-ExistingFile -Value ([string]$plan.professionManifestPath) `
    -BaseDirectory $repositoryRoot -RepositoryRoot $repositoryRoot -Label 'Profession manifest'
$manifestDirectory = Split-Path -Parent $manifestPath
$manifest = Get-Content -LiteralPath $manifestPath -Raw -Encoding UTF8 | ConvertFrom-Json
Assert-Condition ($manifest.coverage.fullSkillCoverageProven -eq $false) `
    'Profession manifest coverage must remain false before final validation.'
Assert-Condition (-not (Test-ObjectProperty -Object $manifest -Name 'fullSkillRelease')) `
    'Profession manifest already contains a current fullSkillRelease.'

$finalItem = Get-Item -LiteralPath $finalPath
$finalHash = (Get-FileHash -LiteralPath $finalPath -Algorithm SHA256).Hash
$packageItem = Get-Item -LiteralPath $packagePath
$packageFileHash = (Get-FileHash -LiteralPath $packagePath -Algorithm SHA256).Hash
foreach ($archive in @($manifest.historicalFullSkillReleases)) {
    $historicalArtifactPath = Resolve-PathValue -Value ([string]$archive.artifact.path) `
        -BaseDirectory $manifestDirectory -Label 'Historical artifact'
    $historicalPackagePath = Resolve-PathValue -Value ([string]$archive.packageSummary.path) `
        -BaseDirectory $manifestDirectory -Label 'Historical package summary'
    Assert-Condition ($finalPath -ine $historicalArtifactPath -and
        $finalHash -ne (Get-NormalizedHash -Value $archive.artifact.sha256 -Label 'Historical artifact hash')) `
        'The activity final NPK must not reuse a historical artifact path or hash.'
    Assert-Condition ($packagePath -ine $historicalPackagePath -and
        $packageFileHash -ne (Get-NormalizedHash -Value $archive.packageSummary.sha256 `
            -Label 'Historical package hash')) `
        'The activity package summary must not reuse a historical path or hash.'
}

$selectedComponents = @($baseline.components | Where-Object { $_.selectedForAggregation -eq $true })
Assert-Condition ($selectedComponents.Count -eq 31) `
    "Expected 31 baseline components, found $($selectedComponents.Count)."
$expectedPaths = New-Object 'Collections.Generic.HashSet[string]' ([StringComparer]::OrdinalIgnoreCase)
$expectedPayloads = New-Object 'Collections.Generic.Dictionary[string,object]' (
    [StringComparer]::OrdinalIgnoreCase)
$expectedSources = New-Object 'Collections.Generic.Dictionary[string,object]' (
    [StringComparer]::OrdinalIgnoreCase)
$componentReports = New-Object 'Collections.Generic.List[object]'
$componentConfigReports = New-Object 'Collections.Generic.List[object]'
$componentToolReports = New-Object 'Collections.Generic.List[object]'
$expectedComponentFrames = 0

foreach ($component in $selectedComponents) {
    $componentId = [string]$component.id
    $componentSnapshot = Assert-FileSnapshot -Snapshot $component.validatedArtifact.componentNpk `
        -BaseDirectory $repositoryRoot -RepositoryRoot $repositoryRoot -Label "Component NPK $componentId"
    $summarySnapshot = Assert-FileSnapshot -Snapshot $component.validatedArtifact.buildSummary `
        -BaseDirectory $repositoryRoot -RepositoryRoot $repositoryRoot -Label "Component summary $componentId"
    $summary = Get-Content -LiteralPath $summarySnapshot.path -Raw -Encoding UTF8 | ConvertFrom-Json
    Assert-Condition ([int]$summary.schemaVersion -eq 1 -and
        [string]$summary.themeId -eq [string]$plan.themeId -and
        [string]$summary.status -eq 'passed') `
        "Component build summary identity or status changed: $componentId"
    Assert-Condition ([long]$summary.output.length -eq $componentSnapshot.length -and
        (Get-NormalizedHash -Value $summary.output.sha256 `
            -Label "Component summary output hash $componentId") -eq $componentSnapshot.sha256) `
        "Component build summary output snapshot changed: $componentId"
    Assert-NoDeployment -Deployment $summary.deployment -Label "Component $componentId"
    $planComponentPath = Resolve-PathValue -Value ([string]$component.output.componentNpkPath) `
        -BaseDirectory $repositoryRoot -Label "Component plan NPK path $componentId"
    $planSummaryPath = Resolve-PathValue -Value ([string]$component.output.buildSummaryPath) `
        -BaseDirectory $repositoryRoot -Label "Component plan summary path $componentId"
    $summaryComponentPath = Resolve-PathValue -Value ([string]$summary.output.componentNpkPath) `
        -BaseDirectory $repositoryRoot -Label "Component summary NPK path $componentId"
    $summarySelfPath = Resolve-PathValue -Value ([string]$summary.output.buildSummaryPath) `
        -BaseDirectory $repositoryRoot -Label "Component summary self path $componentId"
    Assert-Condition ($planComponentPath -ieq $componentSnapshot.path -and
        $summaryComponentPath -ieq $componentSnapshot.path -and
        $planSummaryPath -ieq $summarySnapshot.path -and
        $summarySelfPath -ieq $summarySnapshot.path) `
        "Component plan/summary output paths do not bind to the validated snapshots: $componentId"
    $configPath = Resolve-ExistingFile -Value ([string]$component.configPath) `
        -BaseDirectory $repositoryRoot -RepositoryRoot $repositoryRoot `
        -Label "Component config $componentId"
    $configSnapshot = New-FileSnapshot -Path $configPath
    $config = Get-Content -LiteralPath $configPath -Raw -Encoding UTF8 | ConvertFrom-Json
    Assert-Condition ([int]$config.schemaVersion -eq 1 -and
        [string]$config.themeId -eq [string]$plan.themeId) `
        "Component config identity changed: $componentId"
    $configDirectory = Split-Path -Parent $configPath
    $configComponentPath = Resolve-PathValue -Value ([string]$config.output.componentNpkPath) `
        -BaseDirectory $configDirectory -Label "Component config NPK path $componentId"
    $configSummaryPath = Resolve-PathValue -Value ([string]$config.output.buildSummaryPath) `
        -BaseDirectory $configDirectory -Label "Component config summary path $componentId"
    Assert-Condition ($configComponentPath -ieq $componentSnapshot.path -and
        $configSummaryPath -ieq $summarySnapshot.path) `
        "Component config output paths do not bind to the validated snapshots: $componentId"
    $componentConfigReports.Add([pscustomobject]@{
        componentId = $componentId
        path = $configSnapshot.path
        length = $configSnapshot.length
        sha256 = $configSnapshot.sha256
    })
    if (Test-ObjectProperty -Object $summary -Name 'toolchain') {
        foreach ($property in @($summary.toolchain.PSObject.Properties)) {
            $toolSnapshot = $property.Value
            if ($null -eq $toolSnapshot -or
                -not (Test-ObjectProperty -Object $toolSnapshot -Name 'path') -or
                -not (Test-ObjectProperty -Object $toolSnapshot -Name 'length') -or
                -not (Test-ObjectProperty -Object $toolSnapshot -Name 'sha256')) {
                continue
            }
            $verifiedTool = Assert-FileSnapshot -Snapshot $toolSnapshot `
                -BaseDirectory $repositoryRoot -RepositoryRoot $repositoryRoot `
                -Label "Component tool $componentId/$($property.Name)"
            $componentToolReports.Add([pscustomobject]@{
                componentId = $componentId
                label = [string]$property.Name
                path = $verifiedTool.path
                length = $verifiedTool.length
                sha256 = $verifiedTool.sha256
            })
        }
    }
    $selectedPaths = New-StringSet -Values @($component.selectedImgPaths) `
        -Label "Component selected IMG paths $componentId"
    $summaryPaths = New-StringSet -Values @($summary.selection.allowedImgPaths) `
        -Label "Component summary IMG paths $componentId"
    $configPaths = New-StringSet -Values @($config.allowedImgPaths) `
        -Label "Component config IMG paths $componentId"
    Assert-SetEqual -Expected $selectedPaths -Actual $summaryPaths `
        -Label "Component plan/summary IMG paths $componentId"
    Assert-SetEqual -Expected $selectedPaths -Actual $configPaths `
        -Label "Component plan/config IMG paths $componentId"
    $inventory = Read-NpkPayloadInventory -Path $componentSnapshot.path -Label "Component $componentId"
    $inventoryPaths = New-StringSet -Values @($inventory.entries | ForEach-Object { $_.path }) `
        -Label "Component payload paths $componentId"
    Assert-SetEqual -Expected $selectedPaths -Actual $inventoryPaths `
        -Label "Component selected/payload paths $componentId"
    Assert-Condition ([int]$summary.counts.albums -eq $selectedPaths.Count -and
        [int]$summary.counts.frames -gt 0) `
        "Component album/frame counts are invalid: $componentId"
    $expectedComponentFrames += [int]$summary.counts.frames
    $entryByPath = ConvertTo-EntryDictionary -Entries $inventory.entries -Label "Component $componentId"
    foreach ($path in $selectedPaths) {
        Assert-Condition $expectedPaths.Add($path) "More than one component owns IMG path: $path"
        $entry = $entryByPath[$path]
        $expectedPayloads.Add($path, [pscustomobject]@{
            ownerId = $componentId
            sourceNpk = $componentSnapshot.path
            sourceNpkSha256 = $componentSnapshot.sha256
            payloadLength = [long]$entry.payloadLength
            payloadSha256 = [string]$entry.payloadSha256
        })
    }
    Assert-Condition (-not $expectedSources.ContainsKey($componentSnapshot.path)) `
        "Component source NPK path is duplicated: $($componentSnapshot.path)"
    $expectedSources.Add($componentSnapshot.path, $componentSnapshot)
    $componentReports.Add([pscustomobject]@{
        id = $componentId
        imgVersion = [string]$component.imgVersion
        selectedImgCount = $selectedPaths.Count
        frameCount = [int]$summary.counts.frames
        componentNpk = $componentSnapshot
        buildSummary = $summarySnapshot
        config = $configSnapshot
        deploymentPerformed = $false
    })
}
Assert-Condition ($expectedPaths.Count -eq 417 -and $expectedComponentFrames -eq 3795) `
    "Baseline component totals changed: imgs=$($expectedPaths.Count) frames=$expectedComponentFrames"
Assert-Condition ($componentConfigReports.Count -eq 31 -and $componentToolReports.Count -eq 7) `
    "Component provenance totals changed: configs=$($componentConfigReports.Count) tools=$($componentToolReports.Count)"

$renderPath = Resolve-ExistingFile -Value ([string]$plan.activeCutin.evidence.renderSummaryPath) `
    -BaseDirectory $repositoryRoot -RepositoryRoot $repositoryRoot -Label 'Active Cut-in render summary'
$manualPath = Resolve-ExistingFile -Value ([string]$plan.activeCutin.evidence.manualReviewPath) `
    -BaseDirectory $repositoryRoot -RepositoryRoot $repositoryRoot -Label 'Active Cut-in manual review'
$buildPath = Resolve-ExistingFile -Value ([string]$plan.activeCutin.evidence.buildSummaryPath) `
    -BaseDirectory $repositoryRoot -RepositoryRoot $repositoryRoot -Label 'Active Cut-in build summary'
$renderSnapshot = New-FileSnapshot -Path $renderPath
$manualSnapshot = New-FileSnapshot -Path $manualPath
$buildSnapshot = New-FileSnapshot -Path $buildPath
$build = Get-Content -LiteralPath $buildPath -Raw -Encoding UTF8 | ConvertFrom-Json
Assert-Condition ([string]$build.runId -eq [string]$plan.activeCutin.runId -and
    [string]$build.status -eq 'passed' -and $build.fullSkillCoverageProven -eq $false) `
    'Active Cut-in build identity or status changed.'
Assert-NoDeployment -Deployment $build.deployment -Label 'Active Cut-in build'
$cutinOutput = Assert-FileSnapshot -Snapshot $build.outputNpk -BaseDirectory $repositoryRoot `
    -RepositoryRoot $repositoryRoot -Label 'Active Cut-in output NPK'
$targetImg = Get-InternalPath -Value $plan.activeCutin.targetImg
Assert-Condition ((Get-InternalPath -Value $build.targetImg) -ieq $targetImg) `
    'Active Cut-in target IMG changed.'
$cutinFrames = New-Object 'Collections.Generic.HashSet[int]'
foreach ($frameIndex in @(@($build.changedFrames) + @($build.preservedFrames))) {
    Assert-Condition $cutinFrames.Add([int]$frameIndex) `
        "Active Cut-in frame set contains a duplicate: $frameIndex"
}
Assert-Condition ($cutinFrames.Count -eq 27) 'Active Cut-in frame set must contain 27 frames.'
for ($frameIndex = 0; $frameIndex -lt 27; $frameIndex++) {
    Assert-Condition $cutinFrames.Contains($frameIndex) "Active Cut-in frame set is missing $frameIndex."
}
$cutinInventory = Read-NpkPayloadInventory -Path $cutinOutput.path -Label 'Active Cut-in component'
Assert-Condition ($cutinInventory.entryCount -eq 26) `
    "Active Cut-in component entry count changed: $($cutinInventory.entryCount)"
$cutinEntries = ConvertTo-EntryDictionary -Entries $cutinInventory.entries -Label 'Active Cut-in component'
Assert-Condition $cutinEntries.ContainsKey($targetImg) `
    "Active Cut-in component does not contain the target IMG: $targetImg"
Assert-Condition $expectedPaths.Add($targetImg) `
    "Active Cut-in target overlaps a baseline component: $targetImg"
$cutinEntry = $cutinEntries[$targetImg]
$expectedPayloads.Add($targetImg, [pscustomobject]@{
    ownerId = [string]$plan.activeCutin.id
    sourceNpk = $cutinOutput.path
    sourceNpkSha256 = $cutinOutput.sha256
    payloadLength = [long]$cutinEntry.payloadLength
    payloadSha256 = [string]$cutinEntry.payloadSha256
})
Assert-Condition (-not $expectedSources.ContainsKey($cutinOutput.path)) `
    'Active Cut-in source path overlaps a baseline component source.'
$expectedSources.Add($cutinOutput.path, $cutinOutput)

$supersededReuse = @($baseline.reuseComponents | Where-Object {
    [string]$_.id -eq 'cutin-weaponmaster-neo-v2'
})
Assert-Condition ($supersededReuse.Count -eq 1) 'Historical Cut-in baseline record is missing.'
$historicalCutinPath = Resolve-PathValue -Value ([string]$supersededReuse[0].sourceComponent.path) `
    -BaseDirectory $repositoryRoot -Label 'Historical Cut-in component'
$historicalCutinHash = Get-NormalizedHash -Value $supersededReuse[0].sourceComponent.sha256 `
    -Label 'Historical Cut-in hash'
Assert-Condition ($cutinOutput.path -ine $historicalCutinPath -and
    $cutinOutput.sha256 -ne $historicalCutinHash) `
    'Active aggregation must not reuse the historical Photoshop-era Cut-in component.'

$cutinToolReports = New-Object 'Collections.Generic.List[object]'
foreach ($property in @($build.toolchain.PSObject.Properties)) {
    $toolSnapshot = $property.Value
    if ($null -eq $toolSnapshot -or -not (Test-ObjectProperty -Object $toolSnapshot -Name 'path')) {
        continue
    }
    $verifiedTool = Assert-FileSnapshot -Snapshot $toolSnapshot -BaseDirectory $repositoryRoot `
        -RepositoryRoot $repositoryRoot -Label "Active Cut-in tool $($property.Name)"
    $cutinToolReports.Add([pscustomobject]@{
        label = [string]$property.Name
        path = $verifiedTool.path
        length = $verifiedTool.length
        sha256 = $verifiedTool.sha256
    })
}
$asepriteSnapshot = Assert-FileSnapshot -Snapshot $migration.aseprite -BaseDirectory $repositoryRoot `
    -RepositoryRoot $repositoryRoot -Label 'Pinned Aseprite executable'
Assert-Condition ($migration.aseprite.apiCapabilityRecorded -eq $true -and
    [int]$migration.aseprite.apiVersion -ge [int]$plan.activeCutin.minimumAsepriteApiVersion) `
    'Pinned Aseprite API capability is insufficient.'

$expectedFrameCount = $expectedComponentFrames + $cutinFrames.Count
Assert-Condition ($expectedPaths.Count -eq 418 -and $expectedFrameCount -eq 3822 -and
    $expectedSources.Count -eq 32) `
    "Final selection totals changed: imgs=$($expectedPaths.Count) frames=$expectedFrameCount sources=$($expectedSources.Count)"

$packageSummary = Get-Content -LiteralPath $packagePath -Raw -Encoding UTF8 | ConvertFrom-Json
$package = Get-PackageResult -Summary $packageSummary
Assert-Condition ([int]$package.schemaVersion -eq 1) 'Unsupported package-summary schemaVersion.'
Assert-NoDeployment -Deployment $package.deployment -Label 'Final package summary'
$packageEntries = @($package.entries)
Assert-Condition ([int]$package.entryCount -eq $expectedPaths.Count -and
    $packageEntries.Count -eq $expectedPaths.Count) `
    'Package summary does not contain exactly 418 entries.'
$packageEntryMap = ConvertTo-EntryDictionary -Entries $packageEntries -Label 'Package summary'
$packagePaths = New-StringSet -Values @($packageEntries | ForEach-Object { $_.path }) `
    -Label 'Package summary IMG paths'
Assert-SetEqual -Expected $expectedPaths -Actual $packagePaths -Label 'Selected/package IMG paths'
$packageOutput = if ($package.output -is [string]) {
    Resolve-ExistingFile -Value ([string]$package.output) -BaseDirectory $repositoryRoot `
        -RepositoryRoot $repositoryRoot -Label 'Packaged final NPK'
}
else {
    Resolve-ExistingFile -Value ([string]$package.output.path) -BaseDirectory $repositoryRoot `
        -RepositoryRoot $repositoryRoot -Label 'Packaged final NPK'
}
Assert-Condition ($packageOutput -ieq $finalPath) 'Package summary points to another final NPK.'
Assert-Condition ([long]$package.length -eq $finalItem.Length -and
    (Get-NormalizedHash -Value $package.sha256 -Label 'Package output hash') -eq $finalHash) `
    'Package output length or SHA-256 differs from the final NPK.'
$reportedPackagePath = Resolve-ExistingFile -Value ([string]$package.packageSummaryPath) `
    -BaseDirectory $repositoryRoot -RepositoryRoot $repositoryRoot -Label 'Reported package summary'
Assert-Condition ($reportedPackagePath -ieq $packagePath) `
    'Package summary does not identify its committed path.'
$packagerSnapshot = Assert-FileSnapshot -Snapshot $package.packager -BaseDirectory $repositoryRoot `
    -RepositoryRoot $repositoryRoot -Label 'NPK packager'
$currentPackager = Resolve-ExistingFile -Value 'tools/New-DnfCustomNpk.ps1' -BaseDirectory $repositoryRoot `
    -RepositoryRoot $repositoryRoot -Label 'Current NPK packager'
Assert-Condition ($packagerSnapshot.path -ieq $currentPackager) `
    'Package summary was generated by another packager entry point.'

foreach ($path in $expectedPaths) {
    $expected = $expectedPayloads[$path]
    $packaged = $packageEntryMap[$path]
    $packagedSource = Resolve-ExistingFile -Value ([string]$packaged.sourceNpk) `
        -BaseDirectory $repositoryRoot -RepositoryRoot $repositoryRoot -Label "Package source for $path"
    Assert-Condition ([long]$packaged.payloadLength -eq [long]$expected.payloadLength -and
        (Get-NormalizedHash -Value $packaged.payloadSha256 -Label "Package payload hash $path") -eq
            [string]$expected.payloadSha256 -and
        $packagedSource -ieq [string]$expected.sourceNpk) `
        "Package entry does not match its selected source payload: $path"
}

$packageSourcePaths = New-Object 'Collections.Generic.HashSet[string]' ([StringComparer]::OrdinalIgnoreCase)
foreach ($source in @($package.sources)) {
    $sourcePath = Resolve-ExistingFile -Value ([string]$source.path) -BaseDirectory $repositoryRoot `
        -RepositoryRoot $repositoryRoot -Label 'Package source NPK'
    Assert-Condition $packageSourcePaths.Add($sourcePath) `
        "Package summary contains a duplicate source: $sourcePath"
    Assert-Condition $expectedSources.ContainsKey($sourcePath) `
        "Package summary contains an unexpected source: $sourcePath"
    $expectedSource = $expectedSources[$sourcePath]
    Assert-Condition ((Get-NormalizedHash -Value $source.sha256 -Label "Package source hash $sourcePath") -eq
        [string]$expectedSource.sha256) "Package source hash changed: $sourcePath"
}
$expectedSourcePaths = New-FilePathSet -Values @($expectedSources.Keys) -Label 'Expected package sources'
Assert-SetEqual -Expected $expectedSourcePaths -Actual $packageSourcePaths `
    -Label 'Selected/package source NPK paths'

$finalInventory = Read-NpkPayloadInventory -Path $finalPath -Label 'Final Aseprite NPK'
Assert-Condition ($finalInventory.entryCount -eq $expectedPaths.Count) `
    'Final NPK entry count differs from the 418 selected IMG paths.'
$finalEntries = ConvertTo-EntryDictionary -Entries $finalInventory.entries -Label 'Final Aseprite NPK'
$finalPaths = New-StringSet -Values @($finalInventory.entries | ForEach-Object { $_.path }) `
    -Label 'Final NPK IMG paths'
Assert-SetEqual -Expected $expectedPaths -Actual $finalPaths -Label 'Selected/final IMG paths'
foreach ($path in $expectedPaths) {
    $expected = $expectedPayloads[$path]
    $finalEntry = $finalEntries[$path]
    Assert-Condition ([long]$finalEntry.payloadLength -eq [long]$expected.payloadLength -and
        [string]$finalEntry.payloadSha256 -eq [string]$expected.payloadSha256) `
        "Final NPK payload differs from the selected component payload: $path"
}

$extractorPath = Resolve-DnfExtractorDirectory -Path $ExtractorDirectory -RepositoryRoot $repositoryRoot
$outputParent = Split-Path -Parent $outputPath
New-Item -ItemType Directory -Path $outputParent -Force | Out-Null
$stagingPath = Join-Path $outputParent (
    '.' + [IO.Path]::GetFileName($outputPath) + '.staging-' + [Guid]::NewGuid().ToString('N'))
Assert-Condition (-not (Test-Path -LiteralPath $stagingPath)) `
    "Validation staging path already exists: $stagingPath"
New-Item -ItemType Directory -Path $stagingPath | Out-Null
$published = $false
try {
    $validatedPlanPath = Join-Path $stagingPath 'validated-resource-plan-v5.json'
    [IO.File]::Copy($planPath, $validatedPlanPath, $false)
    $migrationGatePath = Join-Path $stagingPath 'activity-migration-gate.json'
    $migrationText | Set-Content -LiteralPath $migrationGatePath -Encoding UTF8

    $indexTool = Resolve-ExistingFile -Value 'tools/Test-DnfNpkIndex.ps1' -BaseDirectory $repositoryRoot `
        -RepositoryRoot $repositoryRoot -Label 'Independent NPK index validator'
    $indexText = (& $indexTool -Path $finalPath -ExpectedEntryCount $expectedPaths.Count `
        -ExpectedSha256 $finalHash -AsJson | Out-String).Trim()
    Assert-Condition (-not [string]::IsNullOrWhiteSpace($indexText)) `
        'Independent NPK index validator returned no JSON.'
    $index = $indexText | ConvertFrom-Json
    Assert-Condition ([int]$index.EntryCount -eq $expectedPaths.Count -and
        [int]$index.UniquePathCount -eq $expectedPaths.Count -and
        $index.HeaderSha256Valid -eq $true -and
        [int]$index.ImgMagicValidCount -eq $expectedPaths.Count -and
        [string]$index.ParserDependency -eq 'PowerShell/.NET only; no ExtractorSharp') `
        'Independent final NPK index validation failed.'
    $indexPath = Join-Path $stagingPath 'independent-index.json'
    $indexText | Set-Content -LiteralPath $indexPath -Encoding UTF8

    $exportTool = Resolve-ExistingFile -Value 'tools/Export-DnfNpkValidation.ps1' `
        -BaseDirectory $repositoryRoot -RepositoryRoot $repositoryRoot `
        -Label 'Full-frame validation exporter'
    $powerShell32 = Join-Path $env:WINDIR 'SysWOW64\WindowsPowerShell\v1.0\powershell.exe'
    Assert-Condition (Test-Path -LiteralPath $powerShell32 -PathType Leaf) `
        "32-bit Windows PowerShell is required: $powerShell32"
    $fullFramePath = Join-Path $stagingPath 'full-frame-validation'
    $exportOutput = (& $powerShell32 -NoProfile -NonInteractive -ExecutionPolicy Bypass `
        -File $exportTool -InputFile $finalPath -OutputDirectory $fullFramePath `
        -ExtractorDirectory $extractorPath 2>&1 | Out-String)
    $exportExitCode = $LASTEXITCODE
    $exportLogPath = Join-Path $stagingPath 'full-frame-validation.log'
    $exportOutput | Set-Content -LiteralPath $exportLogPath -Encoding UTF8
    Assert-Condition ($exportExitCode -eq 0) `
        "32-bit full-frame validation failed with exit code $exportExitCode."

    $albumPath = Resolve-ExistingFile -Value 'album-inventory.json' -BaseDirectory $fullFramePath `
        -RepositoryRoot $repositoryRoot -Label 'Final album inventory'
    $framePath = Resolve-ExistingFile -Value 'frame-inventory.csv' -BaseDirectory $fullFramePath `
        -RepositoryRoot $repositoryRoot -Label 'Final frame inventory'
    $album = Get-Content -LiteralPath $albumPath -Raw -Encoding UTF8 | ConvertFrom-Json
    $frames = @(Import-Csv -LiteralPath $framePath -Encoding UTF8)
    Assert-Condition ([int]$album.AlbumCount -eq 418 -and
        [int]$album.FrameCount -eq 3822 -and
        [int]$album.DecodedNonLinkFrames -eq 3822 -and
        [int]$album.LinkFrames -eq 0 -and
        [int]$album.HiddenFrames -eq 0 -and
        $frames.Count -eq 3822) `
        'Final full-frame validation must contain 418 IMG and 3822 decoded visible frames.'
    $linkRows = @($frames | Where-Object { [string]$_.Type -eq 'LINK' })
    $hiddenRows = @($frames | Where-Object { [string]$_.Hidden -match '(?i)^true$' })
    Assert-Condition ($linkRows.Count -eq 0 -and $hiddenRows.Count -eq 0) `
        'Final frame inventory contains a LINK or Hidden frame.'
    Assert-Condition ((Get-NormalizedHash -Value $album.InputSha256 -Label 'Album input hash') -eq $finalHash) `
        'Final album inventory points to another NPK.'
    $albumPaths = New-StringSet -Values @($album.Albums | ForEach-Object { $_.Path }) `
        -Label 'Decoded album paths'
    Assert-SetEqual -Expected $expectedPaths -Actual $albumPaths -Label 'Selected/decoded IMG paths'
    $targetAlbums = @($album.Albums | Where-Object {
        (Get-InternalPath -Value $_.Path) -ieq $targetImg
    })
    Assert-Condition ($targetAlbums.Count -eq 1 -and [int]$targetAlbums[0].FrameCount -eq 27) `
        'Final active Cut-in album must contain exactly 27 frames.'
    Assert-Condition ((@($album.Backgrounds) -join ',') -eq 'black,white,checkerboard') `
        'Final contact-sheet background set changed.'
    $expectedSheetCount = [int][Math]::Ceiling($expectedFrameCount / 256.0)
    $sheetDirectory = Join-Path $fullFramePath 'sheets'
    $sheets = @(Get-ChildItem -LiteralPath $sheetDirectory -File -Filter 'frames-*.png' | Sort-Object Name)
    Assert-Condition ($sheets.Count -eq $expectedSheetCount -and
        $sheets.Count -eq [int]$album.SheetCount) `
        'Final black/white/checkerboard contact-sheet set is incomplete.'
    $sheetSnapshots = @($sheets | ForEach-Object {
        Get-FutureSnapshot -StagedPath $_.FullName -StagingRoot $stagingPath -PublishedRoot $outputPath
    })

    $formatCounts = [ordered]@{}
    foreach ($group in @($frames | Group-Object -Property Type | Sort-Object Name)) {
        $formatCounts[[string]$group.Name] = [int]$group.Count
    }
    $versionCounts = [ordered]@{}
    foreach ($property in @($index.ImgVersionCounts.PSObject.Properties | Sort-Object Name)) {
        $versionCounts[[string]$property.Name] = [int]$property.Value
    }

    $toolReports = New-Object 'Collections.Generic.List[object]'
    foreach ($tool in @(
        [pscustomobject]@{ label = 'resource-plan-validator'; path = $migrationValidator },
        [pscustomobject]@{ label = 'final-release-validator'; path = $PSCommandPath },
        [pscustomobject]@{ label = 'custom-npk-packager'; path = $currentPackager },
        [pscustomobject]@{ label = 'independent-index'; path = $indexTool },
        [pscustomobject]@{ label = 'full-frame-export'; path = $exportTool })) {
        $snapshot = New-FileSnapshot -Path $tool.path
        $toolReports.Add([pscustomobject]@{
            label = $tool.label
            path = $snapshot.path
            length = $snapshot.length
            sha256 = $snapshot.sha256
        })
    }
    foreach ($dependencyName in @('ExtractorSharp.Core.dll', 'ExtractorSharp.Json.dll', 'zlib1.dll')) {
        $dependencyPath = Resolve-ExistingFile -Value $dependencyName -BaseDirectory $extractorPath `
            -RepositoryRoot $repositoryRoot -Label $dependencyName
        $snapshot = New-FileSnapshot -Path $dependencyPath
        $toolReports.Add([pscustomobject]@{
            label = $dependencyName
            path = $snapshot.path
            length = $snapshot.length
            sha256 = $snapshot.sha256
        })
    }
    foreach ($builderSnapshot in @($baseline.evidence.builderSnapshots)) {
        $verifiedBuilder = Assert-FileSnapshot -Snapshot $builderSnapshot `
            -BaseDirectory $repositoryRoot -RepositoryRoot $repositoryRoot `
            -Label 'Baseline builder snapshot'
        $toolReports.Add([pscustomobject]@{
            label = [string](Get-ObjectProperty -Object $builderSnapshot -Name 'kind' `
                -Default 'builder-snapshot')
            path = $verifiedBuilder.path
            length = $verifiedBuilder.length
            sha256 = $verifiedBuilder.sha256
        })
    }
    Assert-Condition (@($baseline.evidence.builderSnapshots).Count -eq 7) `
        "Expected 7 baseline builder snapshots, found $(@($baseline.evidence.builderSnapshots).Count)."
    $validatedPlanSnapshot = Get-FutureSnapshot -StagedPath $validatedPlanPath `
        -StagingRoot $stagingPath -PublishedRoot $outputPath
    $migrationGateSnapshot = Get-FutureSnapshot -StagedPath $migrationGatePath `
        -StagingRoot $stagingPath -PublishedRoot $outputPath
    $indexSnapshot = Get-FutureSnapshot -StagedPath $indexPath `
        -StagingRoot $stagingPath -PublishedRoot $outputPath
    $albumSnapshot = Get-FutureSnapshot -StagedPath $albumPath `
        -StagingRoot $stagingPath -PublishedRoot $outputPath
    $frameSnapshot = Get-FutureSnapshot -StagedPath $framePath `
        -StagingRoot $stagingPath -PublishedRoot $outputPath
    $logSnapshot = Get-FutureSnapshot -StagedPath $exportLogPath `
        -StagingRoot $stagingPath -PublishedRoot $outputPath
    foreach ($evidence in @(
        [pscustomobject]@{ label = 'source-migration'; snapshot = $sourceMigrationSnapshot },
        [pscustomobject]@{ label = 'activity-migration-gate'; snapshot = $migrationGateSnapshot },
        [pscustomobject]@{ label = 'cutin-render-summary'; snapshot = $renderSnapshot },
        [pscustomobject]@{ label = 'cutin-manual-review'; snapshot = $manualSnapshot },
        [pscustomobject]@{ label = 'cutin-build-summary'; snapshot = $buildSnapshot },
        [pscustomobject]@{ label = 'aseprite'; snapshot = $asepriteSnapshot })) {
        $toolReports.Add([pscustomobject]@{
            label = $evidence.label
            path = $evidence.snapshot.path
            length = $evidence.snapshot.length
            sha256 = $evidence.snapshot.sha256
        })
    }
    $componentArray = $componentReports.ToArray()
    $componentConfigArray = $componentConfigReports.ToArray()
    $componentToolArray = $componentToolReports.ToArray()
    $officialSourceArray = $officialSourceReports.ToArray()
    $cutinToolArray = $cutinToolReports.ToArray()
    $toolArray = $toolReports.ToArray()

    $frameAccounting = Assert-FileSnapshot -Snapshot $baseline.evidence.postBuildFrameAccounting `
        -BaseDirectory $repositoryRoot -RepositoryRoot $repositoryRoot `
        -Label 'Post-build frame accounting'

    $summary = [ordered]@{
        schemaVersion = 1
        generatedAtUtc = [DateTime]::UtcNow.ToString('o')
        status = 'passed'
        mode = 'offline Aseprite activity release validation; no build, deployment, or process operation'
        fullSkillCoverageProven = $false
        resourcePlan = [ordered]@{
            inputPath = $planPath
            validatedSnapshotPath = $validatedPlanSnapshot.path
            length = $validatedPlanSnapshot.length
            sha256 = $validatedPlanSnapshot.sha256
            planId = [string]$plan.planId
            coverageAtValidationStart = [ordered]@{
                fullSkillCoverageProven = $false
                reason = [string]$plan.coverage.reason
            }
            baselinePlan = $baselineSnapshot
            sourceMigration = $sourceMigrationSnapshot
            postBuildFrameAccounting = $frameAccounting
            activityMigrationGate = $migrationGateSnapshot
            historicalPathRelocation = [ordered]@{
                mode = [string]$plan.historicalPathRelocation.mode
                sourcePrefix = $script:LegacySourcePrefix
                targetPrefix = $script:LegacyTargetPrefix
                resolutionCount = $script:HistoricalPathRelocationCount
            }
            selectedComponentIds = @($componentArray | ForEach-Object { $_.id })
            activeCutinId = [string]$plan.activeCutin.id
            totals = [ordered]@{
                componentCount = $componentArray.Count
                componentImgCount = 417
                componentFrameCount = $expectedComponentFrames
                activeCutinImgCount = 1
                activeCutinFrameCount = $cutinFrames.Count
                finalImgCount = $expectedPaths.Count
                finalFrameCount = $expectedFrameCount
                sourceNpkCount = $expectedSources.Count
            }
        }
        finalArtifact = [ordered]@{
            path = $finalPath
            length = [long]$finalItem.Length
            sha256 = $finalHash
            imgCount = $expectedPaths.Count
            frameCount = $expectedFrameCount
            deploymentPerformed = $false
        }
        packageSummary = [ordered]@{
            path = $packagePath
            length = [long]$packageItem.Length
            sha256 = $packageFileHash
            entryCount = [int]$package.entryCount
            sourceNpkCount = $expectedSources.Count
            packager = $packagerSnapshot
            payloadEquivalence = 'passed'
            selectedSourceEquivalence = 'passed'
            deploymentPerformed = $false
        }
        selection = [ordered]@{
            imgCount = $expectedPaths.Count
            imgPaths = @($expectedPaths | Sort-Object)
            duplicateCount = 0
            rawPayloadLengthAndSha256 = 'identical-to-package-and-selected-source-components'
        }
        counts = [ordered]@{
            albums = [int]$album.AlbumCount
            frames = [int]$album.FrameCount
            decodedNonLinkFrames = [int]$album.DecodedNonLinkFrames
            linkFrames = [int]$album.LinkFrames
            hiddenFrames = [int]$album.HiddenFrames
            imgVersionCounts = $versionCounts
            finalFrameFormatCounts = $formatCounts
        }
        components = $componentArray
        activeCutin = [ordered]@{
            id = [string]$plan.activeCutin.id
            runId = [string]$plan.activeCutin.runId
            targetImg = $targetImg
            selectedFrameCount = $cutinFrames.Count
            changedFrames = @($build.changedFrames)
            preservedTransparentFrames = @($build.preservedFrames)
            sourceComponent = $cutinOutput
            renderSummary = $renderSnapshot
            manualReview = $manualSnapshot
            buildSummary = $buildSnapshot
            aseprite = [ordered]@{
                path = $asepriteSnapshot.path
                length = $asepriteSnapshot.length
                sha256 = $asepriteSnapshot.sha256
                apiVersion = [int]$migration.aseprite.apiVersion
            }
            toolchain = $cutinToolArray
            historicalCutinReuse = 'forbidden-and-not-used'
            deploymentPerformed = $false
        }
        validation = [ordered]@{
            manifestScopeOfflineCoverage = [ordered]@{
                status = 'passed'
                eligibleForReleaseMetadataFullSkillCoverage = $true
                fullSkillCoverageProvenAtValidationStart = $false
                releaseMetadataGeneratedByThisValidator = $false
                releaseMetadataRequiredBeforeCoverageTransition = $true
                targetClientCompatibilityProven = $false
            }
            independentIndex = [ordered]@{
                status = 'passed'
                report = $indexSnapshot.path
                reportLength = $indexSnapshot.length
                reportSha256 = $indexSnapshot.sha256
                parserDependency = [string]$index.ParserDependency
            }
            componentAndActiveCutinPayloadEquivalence = 'passed'
            activeCutinAsepriteRenderManualBuildAndDeepValidation = 'passed'
            fullFrame = [ordered]@{
                status = 'passed'
                powershell = $powerShell32
                decodedNonLinkFrames = [int]$album.DecodedNonLinkFrames
                validatedLinkFrames = [int]$album.LinkFrames
                hiddenFrames = [int]$album.HiddenFrames
                backgrounds = @('black', 'white', 'checkerboard')
                albumInventory = $albumSnapshot
                frameInventory = $frameSnapshot
                contactSheets = $sheetSnapshots
                log = $logSnapshot
            }
        }
        provenance = [ordered]@{
            officialSources = $officialSourceArray
            componentConfigs = $componentConfigArray
            componentToolchains = $componentToolArray
            activeCutin = [ordered]@{
                renderSummary = $renderSnapshot
                manualReview = $manualSnapshot
                buildSummary = $buildSnapshot
                tools = $cutinToolArray
            }
            tools = $toolArray
        }
        deployment = [ordered]@{
            authorized = $false
            performed = $false
            imagePacks2Write = $false
            processOperation = $false
            status = 'not-authorized-not-performed'
        }
        pending = @(
            'Manifest and release metadata must be generated from this summary before coverage can transition to true.',
            'Release closure and the project gate remain required.',
            'Target-client A/B and client load priority remain unproven.'
        )
    }

    $stagedSummaryPath = Join-Path $stagingPath 'final-validation-summary.json'
    $summary | ConvertTo-Json -Depth 20 | Set-Content -LiteralPath $stagedSummaryPath -Encoding UTF8
    $summaryCheck = Get-Content -LiteralPath $stagedSummaryPath -Raw -Encoding UTF8 | ConvertFrom-Json
    Assert-Condition ([string]$summaryCheck.status -eq 'passed' -and
        $summaryCheck.fullSkillCoverageProven -eq $false -and
        $summaryCheck.validation.manifestScopeOfflineCoverage.eligibleForReleaseMetadataFullSkillCoverage -eq $true -and
        $summaryCheck.validation.manifestScopeOfflineCoverage.releaseMetadataGeneratedByThisValidator -eq $false -and
        $summaryCheck.deployment.performed -eq $false) `
        'Staged final validation summary failed its self-check.'

    if (Test-Path -LiteralPath $outputPath) {
        Remove-Item -LiteralPath $outputPath -Force
    }
    Move-Item -LiteralPath $stagingPath -Destination $outputPath
    $summaryPath = Join-Path $outputPath 'final-validation-summary.json'
    $publishedSummary = Get-Content -LiteralPath $summaryPath -Raw -Encoding UTF8 | ConvertFrom-Json
    Assert-Condition ([string]$publishedSummary.finalArtifact.sha256 -eq $finalHash -and
        [int]$publishedSummary.finalArtifact.imgCount -eq 418 -and
        [int]$publishedSummary.finalArtifact.frameCount -eq 3822 -and
        [int]$publishedSummary.resourcePlan.historicalPathRelocation.resolutionCount -gt 0) `
        'Published final validation summary changed after atomic publication.'
    foreach ($publishedSnapshot in @(
        $publishedSummary.resourcePlan.activityMigrationGate,
        $publishedSummary.validation.independentIndex,
        $publishedSummary.validation.fullFrame.albumInventory,
        $publishedSummary.validation.fullFrame.frameInventory,
        $publishedSummary.validation.fullFrame.log) +
        @($publishedSummary.validation.fullFrame.contactSheets)) {
        $snapshot = if (Test-ObjectProperty -Object $publishedSnapshot -Name 'report') {
            [pscustomobject]@{
                path = [string]$publishedSnapshot.report
                length = [long]$publishedSnapshot.reportLength
                sha256 = [string]$publishedSnapshot.reportSha256
            }
        }
        else {
            $publishedSnapshot
        }
        $null = Assert-FileSnapshot -Snapshot $snapshot -BaseDirectory $outputPath `
            -RepositoryRoot $repositoryRoot -Label 'Published final evidence'
    }
    $published = $true

    $result = [pscustomobject]@{
        schemaVersion = 1
        status = 'passed'
        finalNpk = $finalPath
        finalSha256 = $finalHash
        imgCount = $expectedPaths.Count
        frameCount = $expectedFrameCount
        sourceNpkCount = $expectedSources.Count
        summary = $summaryPath
        historicalPathRelocationCount = $script:HistoricalPathRelocationCount
        eligibleForReleaseMetadata = $true
        fullSkillCoverageProven = $false
        deployed = $false
    }
    if ($AsJson) {
        $result | ConvertTo-Json -Depth 6
    }
    else {
        $result
    }
}
finally {
    if (-not $published -and (Test-Path -LiteralPath $stagingPath)) {
        Remove-Item -LiteralPath $stagingPath -Recurse -Force
    }
    if (-not $published -and (Test-Path -LiteralPath $outputPath -PathType Container)) {
        Remove-Item -LiteralPath $outputPath -Recurse -Force
    }
}
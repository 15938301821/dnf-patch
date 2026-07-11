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

    [string]$ExtractorDirectory
)

$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest

function Assert-Condition {
    param(
        [bool]$Condition,
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

function Get-ObjectProperty {
    param(
        [object]$Object,
        [string]$Name,
        [object]$Default = $null
    )

    if (-not (Test-ObjectProperty -Object $Object -Name $Name)) {
        return $Default
    }
    return $Object.PSObject.Properties[$Name].Value
}

function Get-NormalizedHash {
    param(
        [object]$Value,
        [string]$Label
    )

    $text = ([string]$Value).Trim().ToUpperInvariant()
    Assert-Condition -Condition ($text -match '^[0-9A-F]{64}$') -Message "$Label is not a SHA-256 value: '$Value'"
    return $text
}

function Get-InternalPath {
    param([object]$Value)

    $path = ([string]$Value).Trim().Replace('\', '/')
    Assert-Condition -Condition (-not [string]::IsNullOrWhiteSpace($path)) -Message 'An IMG path is empty.'
    return $path
}

function New-InternalPathSet {
    param(
        [object[]]$Values,
        [string]$Label,
        [switch]$AllowEmpty
    )

    $set = New-Object 'Collections.Generic.HashSet[string]' ([StringComparer]::OrdinalIgnoreCase)
    foreach ($value in @($Values)) {
        $path = Get-InternalPath -Value $value
        Assert-Condition -Condition $set.Add($path) -Message "$Label contains a duplicate IMG path: $path"
    }
    if (-not $AllowEmpty) {
        Assert-Condition -Condition ($set.Count -gt 0) -Message "$Label is empty."
    }
    return ,$set
}

function Assert-SetEqual {
    param(
        [Collections.Generic.HashSet[string]]$Expected,
        [Collections.Generic.HashSet[string]]$Actual,
        [string]$Label
    )

    $missing = @()
    foreach ($value in $Expected) {
        if (-not $Actual.Contains($value)) {
            $missing += $value
        }
    }
    $unexpected = @()
    foreach ($value in $Actual) {
        if (-not $Expected.Contains($value)) {
            $unexpected += $value
        }
    }
    Assert-Condition -Condition ($missing.Count -eq 0 -and $unexpected.Count -eq 0) `
        -Message "$Label differs. Missing=[$($missing -join ', ')]; Unexpected=[$($unexpected -join ', ')]"
}

function Resolve-FilePath {
    param(
        [string]$Value,
        [string]$BaseDirectory,
        [string]$Label
    )

    Assert-Condition -Condition (-not [string]::IsNullOrWhiteSpace($Value)) -Message "$Label path is empty."
    $candidate = if ([IO.Path]::IsPathRooted($Value)) {
        [IO.Path]::GetFullPath($Value)
    }
    else {
        [IO.Path]::GetFullPath((Join-Path $BaseDirectory ($Value.Replace('/', '\'))))
    }
    Assert-Condition -Condition (Test-Path -LiteralPath $candidate -PathType Leaf) -Message "$Label was not found: $candidate"
    return (Resolve-Path -LiteralPath $candidate).Path
}

function Resolve-DirectoryPath {
    param(
        [string]$Value,
        [string]$BaseDirectory,
        [string]$Label
    )

    Assert-Condition -Condition (-not [string]::IsNullOrWhiteSpace($Value)) -Message "$Label path is empty."
    $candidate = if ([IO.Path]::IsPathRooted($Value)) {
        [IO.Path]::GetFullPath($Value)
    }
    else {
        [IO.Path]::GetFullPath((Join-Path $BaseDirectory ($Value.Replace('/', '\'))))
    }
    Assert-Condition -Condition (Test-Path -LiteralPath $candidate -PathType Container) -Message "$Label was not found: $candidate"
    return (Resolve-Path -LiteralPath $candidate).Path
}

function Assert-PathInsideRepository {
    param(
        [string]$Path,
        [string]$RepositoryRoot,
        [string]$Label
    )

    $prefix = $RepositoryRoot.TrimEnd([IO.Path]::DirectorySeparatorChar, [IO.Path]::AltDirectorySeparatorChar) + [IO.Path]::DirectorySeparatorChar
    Assert-Condition -Condition ($Path.StartsWith($prefix, [StringComparison]::OrdinalIgnoreCase)) `
        -Message "$Label must stay inside the repository: $Path"
}

function Assert-FileSnapshot {
    param(
        [object]$Snapshot,
        [string]$RepositoryRoot,
        [string]$Label
    )

    Assert-Condition -Condition ($null -ne $Snapshot) -Message "$Label snapshot is missing."
    $path = Resolve-FilePath -Value ([string](Get-ObjectProperty -Object $Snapshot -Name 'path')) -BaseDirectory $RepositoryRoot -Label $Label
    $item = Get-Item -LiteralPath $path
    $actualHash = (Get-FileHash -LiteralPath $path -Algorithm SHA256).Hash
    $expectedHash = Get-NormalizedHash -Value (Get-ObjectProperty -Object $Snapshot -Name 'sha256') -Label "$Label expected hash"
    Assert-Condition -Condition ($actualHash -eq $expectedHash) -Message "$Label SHA-256 changed: $actualHash/$expectedHash"
    if (Test-ObjectProperty -Object $Snapshot -Name 'length') {
        Assert-Condition -Condition ($item.Length -eq [long](Get-ObjectProperty -Object $Snapshot -Name 'length')) `
            -Message "$Label length changed: $($item.Length)/$(Get-ObjectProperty -Object $Snapshot -Name 'length')"
    }
    return [pscustomobject]@{
        path = $path
        length = $item.Length
        sha256 = $actualHash
    }
}

function Assert-TextValue {
    param(
        [object]$Actual,
        [string]$Expected,
        [string]$Label
    )

    Assert-Condition -Condition (([string]$Actual).Equals($Expected, [StringComparison]::OrdinalIgnoreCase)) `
        -Message "$Label must be '$Expected', found '$Actual'."
}

function Assert-DeploymentNotPerformed {
    param(
        [object]$Deployment,
        [string]$Label,
        [switch]$AllowString
    )

    Assert-Condition -Condition ($null -ne $Deployment) -Message "$Label deployment evidence is missing."
    if ($Deployment -is [string]) {
        Assert-Condition -Condition $AllowString -Message "$Label deployment evidence must be an object."
        $text = ([string]$Deployment).Trim()
        Assert-Condition -Condition ($text -match '(?i)not[- ]performed|not[- ]authorized') `
            -Message "$Label reports an unsafe deployment state: $text"
        return
    }

    Assert-Condition -Condition (Test-ObjectProperty -Object $Deployment -Name 'performed') `
        -Message "$Label deployment.performed is missing."
    Assert-Condition -Condition ((Get-ObjectProperty -Object $Deployment -Name 'performed') -eq $false) `
        -Message "$Label reports that deployment was performed."
    $status = [string](Get-ObjectProperty -Object $Deployment -Name 'status' -Default '')
    if (-not [string]::IsNullOrWhiteSpace($status)) {
        Assert-Condition -Condition ($status -notmatch '(?i)^(deployed|performed|complete-deploy)') `
            -Message "$Label has an unsafe deployment status: $status"
    }
}

function Test-PlanItemSelected {
    param([object]$Item)

    foreach ($propertyName in @('superseded', 'nonSelected', 'disabled')) {
        if (Test-ObjectProperty -Object $Item -Name $propertyName) {
            $marker = Get-ObjectProperty -Object $Item -Name $propertyName
            if ($marker -eq $true -or ($marker -is [string] -and -not [string]::IsNullOrWhiteSpace([string]$marker) -and [string]$marker -notmatch '(?i)^false$')) {
                return $false
            }
        }
    }
    if (Test-ObjectProperty -Object $Item -Name 'supersededBy') {
        if (-not [string]::IsNullOrWhiteSpace([string](Get-ObjectProperty -Object $Item -Name 'supersededBy'))) {
            return $false
        }
    }
    foreach ($propertyName in @(
        'selected',
        'finalSelected',
        'selectedForAggregation',
        'selectedForFinalAggregation',
        'enabled',
        'includeInFinal',
        'includeInFinalAggregation',
        'requiredForFinalAggregation')) {
        if (Test-ObjectProperty -Object $Item -Name $propertyName) {
            if ((Get-ObjectProperty -Object $Item -Name $propertyName) -eq $false) {
                return $false
            }
        }
    }
    foreach ($propertyName in @(
        'selectionStatus',
        'selectionRole',
        'aggregationStatus',
        'finalSelectionStatus',
        'disposition',
        'buildStatus',
        'status')) {
        $value = [string](Get-ObjectProperty -Object $Item -Name $propertyName -Default '')
        if ($value -match '(?i)^(superseded|non-selected|not-selected|excluded|disabled|omitted)(?:$|[- ])') {
            return $false
        }
    }
    foreach ($nestedName in @('selection', 'aggregation')) {
        $nested = Get-ObjectProperty -Object $Item -Name $nestedName
        if ($null -eq $nested -or $nested -is [string]) {
            continue
        }
        foreach ($propertyName in @('selected', 'enabled', 'include', 'includeInFinal', 'required')) {
            if (Test-ObjectProperty -Object $nested -Name $propertyName) {
                if ((Get-ObjectProperty -Object $nested -Name $propertyName) -eq $false) {
                    return $false
                }
            }
        }
        $status = [string](Get-ObjectProperty -Object $nested -Name 'status' -Default '')
        if ($status -match '(?i)^(superseded|non-selected|not-selected|excluded|disabled|omitted)(?:$|[- ])') {
            return $false
        }
    }
    return $true
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
    param(
        [byte[]]$Left,
        [byte[]]$Right
    )

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
    param(
        [string]$Path,
        [string]$Label
    )

    $nameKey = [Text.Encoding]::ASCII.GetBytes(
        'puchikon@neople dungeon and fighter ' + ('DNF' * 73) + [char]0)
    Assert-Condition -Condition ($nameKey.Length -eq 256) -Message 'Unexpected NPK filename key length.'

    $stream = [IO.File]::Open($Path, [IO.FileMode]::Open, [IO.FileAccess]::Read, [IO.FileShare]::Read)
    $reader = New-Object IO.BinaryReader($stream, [Text.Encoding]::ASCII, $true)
    $sha = [Security.Cryptography.SHA256]::Create()
    try {
        $magic = [Text.Encoding]::ASCII.GetString($reader.ReadBytes(16)).TrimEnd([char]0)
        Assert-Condition -Condition ($magic -eq 'NeoplePack_Bill') -Message "$Label has invalid NPK magic '$magic'."
        $entryCount = $reader.ReadInt32()
        Assert-Condition -Condition ($entryCount -gt 0) -Message "$Label has invalid entry count $entryCount."
        $headerLength = 20L + 264L * $entryCount
        $dataStart = $headerLength + 32L
        Assert-Condition -Condition ($dataStart -le $stream.Length) -Message "$Label header exceeds the file length."

        $entries = New-Object 'Collections.Generic.List[object]'
        $pathSet = New-Object 'Collections.Generic.HashSet[string]' ([StringComparer]::OrdinalIgnoreCase)
        for ($entryIndex = 0; $entryIndex -lt $entryCount; $entryIndex++) {
            $offset = [long]$reader.ReadInt32()
            $size = [long]$reader.ReadInt32()
            $encryptedName = $reader.ReadBytes(256)
            Assert-Condition -Condition ($encryptedName.Length -eq 256) -Message "$Label index entry $entryIndex is truncated."
            $plainName = New-Object byte[] 256
            for ($byteIndex = 0; $byteIndex -lt 256; $byteIndex++) {
                $plainName[$byteIndex] = $encryptedName[$byteIndex] -bxor $nameKey[$byteIndex]
            }
            $nullIndex = [Array]::IndexOf($plainName, [byte]0)
            Assert-Condition -Condition ($nullIndex -gt 0) -Message "$Label index entry $entryIndex has an invalid path."
            $internalPath = Get-InternalPath -Value ([Text.Encoding]::ASCII.GetString($plainName, 0, $nullIndex))
            Assert-Condition -Condition $pathSet.Add($internalPath) -Message "$Label has a duplicate IMG path: $internalPath"
            Assert-Condition -Condition ($offset -ge $dataStart -and $size -gt 0 -and $offset + $size -le $stream.Length) `
                -Message "$Label entry is outside the NPK: $internalPath"
            Assert-Condition -Condition ($size -le [int]::MaxValue) -Message "$Label IMG payload is too large to validate: $internalPath"
            $entries.Add([pscustomobject]@{
                path = $internalPath
                offset = $offset
                length = $size
            })
        }

        $storedHeaderHash = $reader.ReadBytes(32)
        Assert-Condition -Condition ($storedHeaderHash.Length -eq 32) -Message "$Label header SHA-256 is truncated."
        $hashInputLength = [int]($headerLength - ($headerLength % 17L))
        $stream.Position = 0
        $hashInput = $reader.ReadBytes($hashInputLength)
        $computedHeaderHash = $sha.ComputeHash($hashInput)
        Assert-Condition -Condition (Test-ByteArrayEqual -Left $storedHeaderHash -Right $computedHeaderHash) `
            -Message "$Label header SHA-256 is invalid."

        $payloadRecords = New-Object 'Collections.Generic.List[object]'
        foreach ($entry in $entries) {
            $stream.Position = $entry.offset
            $payload = $reader.ReadBytes([int]$entry.length)
            Assert-Condition -Condition ($payload.Length -eq $entry.length) -Message "$Label IMG payload is truncated: $($entry.path)"
            $magicEnd = [Array]::IndexOf($payload, [byte]0, 0, [Math]::Min(18, $payload.Length))
            Assert-Condition -Condition ($magicEnd -gt 0) -Message "$Label IMG magic is invalid: $($entry.path)"
            $imgMagic = [Text.Encoding]::ASCII.GetString($payload, 0, $magicEnd)
            Assert-Condition -Condition ($imgMagic -in @('Neople Img File', 'Neople Image File')) `
                -Message "$Label IMG magic is invalid for $($entry.path): $imgMagic"
            $payloadRecords.Add([pscustomobject]@{
                path = $entry.path
                payloadLength = $entry.length
                payloadSha256 = Get-ByteHash -Bytes $payload
            })
        }
        return [pscustomobject]@{
            path = $Path
            entryCount = $entryCount
            entries = $payloadRecords.ToArray()
        }
    }
    finally {
        $sha.Dispose()
        $reader.Dispose()
        $stream.Dispose()
    }
}

function ConvertTo-EntryDictionary {
    param(
        [object[]]$Entries,
        [string]$Label
    )

    $dictionary = New-Object 'Collections.Generic.Dictionary[string,object]' ([StringComparer]::OrdinalIgnoreCase)
    foreach ($entry in @($Entries)) {
        $path = Get-InternalPath -Value (Get-ObjectProperty -Object $entry -Name 'path')
        Assert-Condition -Condition (-not $dictionary.ContainsKey($path)) -Message "$Label contains a duplicate IMG path: $path"
        $dictionary.Add($path, $entry)
    }
    return ,$dictionary
}

function Get-EvidenceSnapshot {
    param(
        [object]$Component,
        [string]$PropertyName
    )

    $validatedArtifact = Get-ObjectProperty -Object $Component -Name 'validatedArtifact'
    if ($null -ne $validatedArtifact -and (Test-ObjectProperty -Object $validatedArtifact -Name $PropertyName)) {
        return Get-ObjectProperty -Object $validatedArtifact -Name $PropertyName
    }
    $validation = Get-ObjectProperty -Object $Component -Name 'validation'
    if ($null -ne $validation -and (Test-ObjectProperty -Object $validation -Name $PropertyName)) {
        return Get-ObjectProperty -Object $validation -Name $PropertyName
    }
    return $null
}

function Get-PackageResult {
    param([object]$Summary)

    $candidates = @($Summary)
    foreach ($propertyName in @('package', 'packagerResult', 'result', 'artifact')) {
        if (Test-ObjectProperty -Object $Summary -Name $propertyName) {
            $candidates += Get-ObjectProperty -Object $Summary -Name $propertyName
        }
    }
    foreach ($candidate in $candidates) {
        if ($null -ne $candidate -and (Test-ObjectProperty -Object $candidate -Name 'entries')) {
            return $candidate
        }
    }
    throw 'Package summary does not contain a packager result with entries.'
}

$repoRoot = (Resolve-Path -LiteralPath (Split-Path -Parent $PSScriptRoot)).Path
Import-Module (Join-Path $PSScriptRoot 'DnfPatch.Toolchain.psm1') -Force
$planPath = Resolve-FilePath -Value $ResourcePlanPath -BaseDirectory $repoRoot -Label 'Resource plan'
$finalPath = Resolve-FilePath -Value $FinalNpk -BaseDirectory $repoRoot -Label 'Final NPK'
$packagePath = Resolve-FilePath -Value $PackageSummaryPath -BaseDirectory $repoRoot -Label 'Package summary'
$extractorPath = Resolve-DnfExtractorDirectory -Path $ExtractorDirectory -RepositoryRoot $repoRoot
$resourcePlanValidatorPath = Resolve-FilePath -Value 'tools/Test-VergilResourcePlan.ps1' -BaseDirectory $repoRoot `
    -Label 'Resource-plan validator'
$outputPath = if ([IO.Path]::IsPathRooted($OutputDirectory)) {
    [IO.Path]::GetFullPath($OutputDirectory)
}
else {
    [IO.Path]::GetFullPath((Join-Path $repoRoot ($OutputDirectory.Replace('/', '\'))))
}

Assert-PathInsideRepository -Path $finalPath -RepositoryRoot $repoRoot -Label 'Final NPK'
Assert-PathInsideRepository -Path $outputPath -RepositoryRoot $repoRoot -Label 'Validation output'
Assert-Condition -Condition ([IO.Path]::GetExtension($finalPath) -ieq '.NPK') -Message "Final artifact must use .NPK: $finalPath"
$finalName = [IO.Path]::GetFileName($finalPath)
Assert-Condition -Condition ($finalName -match '(?i)weaponmaster-vergil-dark-blue') `
    -Message "Final artifact name must contain weaponmaster-vergil-dark-blue: $finalName"
Assert-Condition -Condition ($finalName -match '(?i)(?:^|[-_])v[0-9]+(?:[-_.]|$)') `
    -Message "Final artifact name must contain a version token such as v1: $finalName"

$resourcePlanGateText = (& $resourcePlanValidatorPath -ResourcePlanPath $planPath | Out-String).Trim()
Assert-Condition -Condition (-not [string]::IsNullOrWhiteSpace($resourcePlanGateText)) `
    -Message 'Resource-plan validator returned no JSON.'
$resourcePlanGate = $resourcePlanGateText | ConvertFrom-Json
Assert-Condition -Condition ($resourcePlanGate.Status -eq 'passed' -and
    [int]$resourcePlanGate.SourceCount -eq 28 -and [int]$resourcePlanGate.ConfigCount -eq 31 -and
    [int]$resourcePlanGate.AllowedImgCount -eq 417 -and
    [int]$resourcePlanGate.PreBuildAuthorizedFrameCount -eq 3667 -and
    [int]$resourcePlanGate.EffectiveChangedFrameCount -eq 3593 -and
    [int]$resourcePlanGate.ExplicitExcludedFrameKeyCount -eq 128 -and
    [int]$resourcePlanGate.DynamicPreservedFrameKeyCount -eq 74 -and
    [int]$resourcePlanGate.SelectedFrameCount -eq 3795 -and
    [int]$resourcePlanGate.CandidatePoolExcludedFrameCount -eq 221 -and
    [int]$resourcePlanGate.FinalAggregateSelectedImgCount -eq 418 -and
    [int]$resourcePlanGate.FinalEffectiveChangedFrameCount -eq 3617 -and
    [int]$resourcePlanGate.FinalSelectedFrameCount -eq 3822 -and
    [int]$resourcePlanGate.FinalPreservedFrameCount -eq 205 -and
    $resourcePlanGate.Deployment -eq 'not-authorized-not-performed' -and
    $resourcePlanGate.FullSkillCoverageProven -eq $false) `
    -Message 'Resource-plan validator did not return the reviewed post-build/pre-release totals.'

if (Test-Path -LiteralPath $outputPath) {
    Assert-Condition -Condition (Test-Path -LiteralPath $outputPath -PathType Container) `
        -Message "Validation output exists but is not a directory: $outputPath"
    $existingOutput = @(Get-ChildItem -LiteralPath $outputPath -Force)
    Assert-Condition -Condition ($existingOutput.Count -eq 0) `
        -Message "Validation output directory must be empty to prevent stale evidence: $outputPath"
}
else {
    New-Item -ItemType Directory -Path $outputPath | Out-Null
}

$planInputItem = Get-Item -LiteralPath $planPath
$planInputHash = (Get-FileHash -LiteralPath $planPath -Algorithm SHA256).Hash
$planSnapshotPath = Join-Path $outputPath 'validated-resource-plan.json'
[IO.File]::Copy($planPath, $planSnapshotPath, $false)
Assert-Condition -Condition ((Get-Item -LiteralPath $planSnapshotPath).Length -eq $planInputItem.Length -and
    (Get-FileHash -LiteralPath $planSnapshotPath -Algorithm SHA256).Hash -eq $planInputHash) `
    -Message 'Immutable resource-plan validation snapshot differs from the input plan.'
$plan = Get-Content -LiteralPath $planSnapshotPath -Raw -Encoding UTF8 | ConvertFrom-Json
$packageSummary = Get-Content -LiteralPath $packagePath -Raw -Encoding UTF8 | ConvertFrom-Json
$packageResult = Get-PackageResult -Summary $packageSummary
Assert-DeploymentNotPerformed -Deployment (Get-ObjectProperty -Object $plan -Name 'deployment') -Label 'Resource plan'
Assert-Condition -Condition ($plan.status -eq 'components-offline-validated-final-aggregation-pending' -and
    $plan.scope.npkBuildPerformed -eq $true -and [int]$plan.scope.componentBuildCount -eq 31 -and
    [int]$plan.scope.componentBuildPassedCount -eq 31 -and $plan.scope.finalAggregationPerformed -eq $false) `
    -Message 'Resource plan is not at the reviewed post-build/pre-aggregation gate.'
$planEvidence = Get-ObjectProperty -Object $plan -Name 'evidence'
$accountingSnapshot = Get-ObjectProperty -Object $planEvidence -Name 'postBuildFrameAccounting'
$accountingReport = Assert-FileSnapshot -Snapshot $accountingSnapshot -RepositoryRoot $repoRoot `
    -Label 'Post-build frame accounting'
$accounting = Get-Content -LiteralPath $accountingReport.path -Raw -Encoding UTF8 | ConvertFrom-Json
Assert-Condition -Condition ([int]$accounting.schemaVersion -eq 1 -and
    $accounting.status -eq 'passed-build-summary-dynamic-exclusion-expansion' -and
    [int]$accounting.totals.componentCount -eq 31 -and
    [int]$accounting.totals.dynamicComponentCount -eq 12 -and
    [int]$accounting.totals.selectedFrameReferenceCount -eq 3795 -and
    [int]$accounting.totals.changedFrameReferenceCount -eq 3593 -and
    [int]$accounting.totals.explicitExcludedFrameReferenceCount -eq 128 -and
    [int]$accounting.totals.dynamicExcludedFrameReferenceCount -eq 74 -and
    [int]$accounting.totals.dynamicSkippedTextureGroupCount -eq 70 -and
    [int]$accounting.totals.sourceOutputCompressedHashMismatchCount -eq 0 -and
    [int]$accounting.totals.sourceOutputDdsHashMismatchCount -eq 0 -and
    [int]$accounting.totals.sourceOutputBgraHashMismatchCount -eq 0 -and
    [int]$accounting.totals.partitionOverlapCount -eq 0) `
    -Message 'Post-build frame accounting totals changed.'
if (-not [object]::ReferenceEquals($packageSummary, $packageResult) -and
    (Test-ObjectProperty -Object $packageSummary -Name 'deployment')) {
    Assert-DeploymentNotPerformed -Deployment (Get-ObjectProperty -Object $packageSummary -Name 'deployment') `
        -Label 'Package-summary wrapper' -AllowString
}
$packageGeneratedAt = [string](Get-ObjectProperty -Object $packageResult -Name 'generatedAtUtc' -Default '')
$packageGeneratedAtValue = [DateTime]::MinValue
Assert-Condition -Condition (-not [string]::IsNullOrWhiteSpace($packageGeneratedAt) -and
    [DateTime]::TryParse($packageGeneratedAt, [ref]$packageGeneratedAtValue)) `
    -Message 'Package summary generatedAtUtc is missing or invalid.'
$packageSummaryValue = [string](Get-ObjectProperty -Object $packageResult -Name 'packageSummaryPath' -Default '')
Assert-Condition -Condition (-not [string]::IsNullOrWhiteSpace($packageSummaryValue)) `
    -Message 'Package summary does not identify its committed summary path.'
$packageSummaryReportedPath = Resolve-FilePath -Value $packageSummaryValue -BaseDirectory $repoRoot `
    -Label 'Packager-reported package summary'
Assert-Condition -Condition ($packageSummaryReportedPath -ieq $packagePath) `
    -Message 'Packager-reported package summary path differs from the validated summary.'
$packagerSnapshot = Get-ObjectProperty -Object $packageResult -Name 'packager'
$packagerReport = Assert-FileSnapshot -Snapshot $packagerSnapshot -RepositoryRoot $repoRoot -Label 'Package summary packager'
$currentPackagerPath = Resolve-FilePath -Value 'tools/New-DnfCustomNpk.ps1' -BaseDirectory $repoRoot -Label 'Current NPK packager'
Assert-Condition -Condition ($packagerReport.path -ieq $currentPackagerPath) `
    -Message 'Package summary was produced by another packager path.'

$selectedComponents = @()
$skippedComponents = @()
foreach ($component in @((Get-ObjectProperty -Object $plan -Name 'components' -Default @()))) {
    $componentId = [string](Get-ObjectProperty -Object $component -Name 'id')
    Assert-Condition -Condition (-not [string]::IsNullOrWhiteSpace($componentId)) -Message 'Resource plan contains a component without an id.'
    $explicitlySelected = (Test-ObjectProperty -Object $component -Name 'selectedForAggregation') -and
        (Get-ObjectProperty -Object $component -Name 'selectedForAggregation') -eq $true
    if ($explicitlySelected -and (Test-PlanItemSelected -Item $component)) {
        $selectedComponents += $component
    }
    else {
        $skippedComponents += $componentId
    }
}
$selectedReuseComponents = @()
$skippedReuseComponents = @()
foreach ($reuse in @((Get-ObjectProperty -Object $plan -Name 'reuseComponents' -Default @()))) {
    $reuseId = [string](Get-ObjectProperty -Object $reuse -Name 'id')
    Assert-Condition -Condition (-not [string]::IsNullOrWhiteSpace($reuseId)) -Message 'Resource plan contains a reuse component without an id.'
    $explicitlyRequired = (Test-ObjectProperty -Object $reuse -Name 'requiredForFinalAggregation') -and
        (Get-ObjectProperty -Object $reuse -Name 'requiredForFinalAggregation') -eq $true
    if ($explicitlyRequired -and (Test-PlanItemSelected -Item $reuse)) {
        $selectedReuseComponents += $reuse
    }
    else {
        $skippedReuseComponents += $reuseId
    }
}
Assert-Condition -Condition ($selectedComponents.Count + $selectedReuseComponents.Count -gt 0) `
    -Message 'Resource plan has no selected components for final aggregation.'
Assert-Condition -Condition ($selectedComponents.Count -eq 31 -and $skippedComponents.Count -eq 0 -and
    $selectedReuseComponents.Count -eq 1 -and $skippedReuseComponents.Count -eq 0) `
    -Message "Final aggregation requires exactly 31 explicit components and one explicit reuse component; selected/skipped=$($selectedComponents.Count)/$($skippedComponents.Count)/$($selectedReuseComponents.Count)/$($skippedReuseComponents.Count)."

$planSourceById = New-Object 'Collections.Generic.Dictionary[string,object]' ([StringComparer]::OrdinalIgnoreCase)
foreach ($source in @((Get-ObjectProperty -Object $plan -Name 'sources' -Default @()))) {
    $sourceId = [string](Get-ObjectProperty -Object $source -Name 'id')
    Assert-Condition -Condition (-not [string]::IsNullOrWhiteSpace($sourceId) -and
        -not $planSourceById.ContainsKey($sourceId)) `
        -Message "Resource plan contains an empty or duplicate source id: $sourceId"
    $planSourceById.Add($sourceId, $source)
}
Assert-Condition -Condition ($planSourceById.Count -eq 28) `
    -Message "Resource plan must contain 28 unique source records, found $($planSourceById.Count)."

$expectedPaths = New-Object 'Collections.Generic.HashSet[string]' ([StringComparer]::OrdinalIgnoreCase)
$expectedPayloadSources = New-Object 'Collections.Generic.Dictionary[string,object]' ([StringComparer]::OrdinalIgnoreCase)
$componentReports = @()
$sourceReports = @()
$configReports = @()
$componentToolReports = @()
$expectedAlbumCount = 0
$expectedFrameCount = 0
$ver5Totals = [ordered]@{
    componentCount = 0
    changedTextures = 0L
    skippedTextures = 0L
    changedBc1Textures = 0L
    changedBc3Textures = 0L
}
$ver2Totals = [ordered]@{
    componentCount = 0
    changedFrames = 0L
    skippedFrames = 0L
    changedArgb1555Frames = 0L
    changedArgb8888Frames = 0L
}

foreach ($component in $selectedComponents) {
    $componentId = [string](Get-ObjectProperty -Object $component -Name 'id')
    $handler = [string](Get-ObjectProperty -Object $component -Name 'handler')
    $imgVersion = [string](Get-ObjectProperty -Object $component -Name 'imgVersion')
    $output = Get-ObjectProperty -Object $component -Name 'output'
    Assert-Condition -Condition ($null -ne $output) -Message "Selected component $componentId has no output definition."
    $componentNpkPath = Resolve-FilePath -Value ([string](Get-ObjectProperty -Object $output -Name 'componentNpkPath')) `
        -BaseDirectory $repoRoot -Label "$componentId component NPK"
    $buildSummaryPath = Resolve-FilePath -Value ([string](Get-ObjectProperty -Object $output -Name 'buildSummaryPath')) `
        -BaseDirectory $repoRoot -Label "$componentId build summary"
    $configPath = Resolve-FilePath -Value ([string](Get-ObjectProperty -Object $component -Name 'configPath')) `
        -BaseDirectory $repoRoot -Label "$componentId config"

    $summary = Get-Content -LiteralPath $buildSummaryPath -Raw -Encoding UTF8 | ConvertFrom-Json
    $config = Get-Content -LiteralPath $configPath -Raw -Encoding UTF8 | ConvertFrom-Json
    Assert-TextValue -Actual (Get-ObjectProperty -Object $summary -Name 'status') -Expected 'passed' -Label "$componentId build summary status"
    Assert-DeploymentNotPerformed -Deployment (Get-ObjectProperty -Object $summary -Name 'deployment') -Label $componentId

    $summaryOutput = Get-ObjectProperty -Object $summary -Name 'output'
    Assert-Condition -Condition ($null -ne $summaryOutput) -Message "$componentId build summary has no output evidence."
    $summaryNpkPath = Resolve-FilePath -Value ([string](Get-ObjectProperty -Object $summaryOutput -Name 'componentNpkPath')) `
        -BaseDirectory $repoRoot -Label "$componentId summary component NPK"
    $summaryReportPath = Resolve-FilePath -Value ([string](Get-ObjectProperty -Object $summaryOutput -Name 'buildSummaryPath')) `
        -BaseDirectory $repoRoot -Label "$componentId summary report path"
    Assert-Condition -Condition ($summaryNpkPath -ieq $componentNpkPath) -Message "$componentId output path differs between plan and build summary."
    Assert-Condition -Condition ($summaryReportPath -ieq $buildSummaryPath) -Message "$componentId report path differs between plan and build summary."

    $componentItem = Get-Item -LiteralPath $componentNpkPath
    $componentHash = (Get-FileHash -LiteralPath $componentNpkPath -Algorithm SHA256).Hash
    Assert-Condition -Condition ($componentItem.Length -eq [long](Get-ObjectProperty -Object $summaryOutput -Name 'length')) `
        -Message "$componentId component length differs from its build summary."
    Assert-Condition -Condition ($componentHash -eq (Get-NormalizedHash -Value (Get-ObjectProperty -Object $summaryOutput -Name 'sha256') -Label "$componentId output hash")) `
        -Message "$componentId component SHA-256 differs from its build summary."

    $validatedArtifact = Get-ObjectProperty -Object $component -Name 'validatedArtifact'
    Assert-Condition -Condition ($null -ne $validatedArtifact -and
        (Get-ObjectProperty -Object $validatedArtifact -Name 'status') -eq 'offline-validated-client-pending' -and
        (Test-ObjectProperty -Object $validatedArtifact -Name 'componentNpk') -and
        (Test-ObjectProperty -Object $validatedArtifact -Name 'buildSummary')) `
        -Message "$componentId lacks mandatory validated-artifact snapshots."
    $validatedComponent = Assert-FileSnapshot -Snapshot (Get-ObjectProperty -Object $validatedArtifact -Name 'componentNpk') `
        -RepositoryRoot $repoRoot -Label "$componentId validated componentNpk"
    $validatedSummary = Assert-FileSnapshot -Snapshot (Get-ObjectProperty -Object $validatedArtifact -Name 'buildSummary') `
        -RepositoryRoot $repoRoot -Label "$componentId validated buildSummary"
    Assert-Condition -Condition ($validatedComponent.path -ieq $componentNpkPath -and
        $validatedSummary.path -ieq $buildSummaryPath -and
        $validatedComponent.sha256 -eq $componentHash) `
        -Message "$componentId validated-artifact snapshots differ from plan output/build-summary paths."
    $summaryToolchain = Get-ObjectProperty -Object $summary -Name 'toolchain'
    if ($null -ne $summaryToolchain) {
        foreach ($toolProperty in $summaryToolchain.PSObject.Properties) {
            $toolSnapshot = $toolProperty.Value
            if ($null -eq $toolSnapshot -or -not (Test-ObjectProperty -Object $toolSnapshot -Name 'path') -or
                -not (Test-ObjectProperty -Object $toolSnapshot -Name 'sha256')) {
                continue
            }
            $verifiedTool = Assert-FileSnapshot -Snapshot $toolSnapshot -RepositoryRoot $repoRoot `
                -Label "$componentId toolchain.$($toolProperty.Name)"
            $componentToolReports += [pscustomobject]@{
                componentId = $componentId
                label = [string]$toolProperty.Name
                path = $verifiedTool.path
                length = $verifiedTool.length
                sha256 = $verifiedTool.sha256
                version = [string](Get-ObjectProperty -Object $toolSnapshot -Name 'version' -Default '')
            }
        }
    }

    $summarySelection = Get-ObjectProperty -Object $summary -Name 'selection'
    $summaryAllowed = New-InternalPathSet -Values @((Get-ObjectProperty -Object $summarySelection -Name 'allowedImgPaths' -Default @())) `
        -Label "$componentId build-summary selection.allowedImgPaths"
    $configAllowed = New-InternalPathSet -Values @((Get-ObjectProperty -Object $config -Name 'allowedImgPaths' -Default @())) `
        -Label "$componentId config allowedImgPaths"
    $planAllowed = New-InternalPathSet -Values @((Get-ObjectProperty -Object $component -Name 'selectedImgPaths' -Default @())) `
        -Label "$componentId plan selectedImgPaths"
    Assert-SetEqual -Expected $summaryAllowed -Actual $configAllowed -Label "$componentId config/build-summary IMG selection"
    Assert-SetEqual -Expected $summaryAllowed -Actual $planAllowed -Label "$componentId plan/build-summary IMG selection"
    $planCounts = Get-ObjectProperty -Object $component -Name 'counts'
    if ($null -ne $planCounts -and (Test-ObjectProperty -Object $planCounts -Name 'allowedImgCount')) {
        Assert-Condition -Condition ($summaryAllowed.Count -eq [int](Get-ObjectProperty -Object $planCounts -Name 'allowedImgCount')) `
            -Message "$componentId selected IMG count differs from the resource plan."
    }

    $rawComponent = Read-NpkPayloadInventory -Path $componentNpkPath -Label "$componentId component"
    $rawComponentEntries = ConvertTo-EntryDictionary -Entries $rawComponent.entries -Label "$componentId component"
    $rawComponentPaths = New-InternalPathSet -Values @($rawComponent.entries | ForEach-Object { $_.path }) -Label "$componentId component paths"
    Assert-SetEqual -Expected $summaryAllowed -Actual $rawComponentPaths -Label "$componentId component/selection paths"

    foreach ($path in $summaryAllowed) {
        Assert-Condition -Condition $expectedPaths.Add($path) -Message "Selected IMG path is owned by more than one component: $path"
        $rawEntry = $rawComponentEntries[$path]
        $expectedPayloadSources.Add($path, [pscustomobject]@{
            ownerId = $componentId
            sourceNpk = $componentNpkPath
            sourceNpkSha256 = $componentHash
            payloadLength = [long]$rawEntry.payloadLength
            payloadSha256 = [string]$rawEntry.payloadSha256
        })
    }

    $counts = Get-ObjectProperty -Object $summary -Name 'counts'
    Assert-Condition -Condition ($null -ne $counts) -Message "$componentId build summary has no counts."
    $albums = [int](Get-ObjectProperty -Object $counts -Name 'albums')
    $frames = [int](Get-ObjectProperty -Object $counts -Name 'frames')
    Assert-Condition -Condition ($albums -eq $summaryAllowed.Count -and $frames -gt 0) `
        -Message "$componentId album/frame counts are invalid: $albums/$frames"
    $expectedAlbumCount += $albums
    $expectedFrameCount += $frames

    $validation = Get-ObjectProperty -Object $summary -Name 'validation'
    Assert-Condition -Condition ($null -ne $validation) -Message "$componentId build summary has no validation object."
    $formatReport = $null
    if ($handler -match '(?i)ver5' -or $imgVersion -eq 'Ver5') {
        foreach ($gate in @(
            @('reopenedFromDisk', 'passed'),
            @('structureAndSharing', 'passed'),
            @('ddsHeaders', 'byte-identical'),
            @('bc3AlphaBlocks', 'byte-identical where applicable'),
            @('bc1TransparentMode', 'preserved per block where applicable'),
            @('authorizedDecodedAlpha', 'byte-identical'),
            @('unauthorizedDecodedBgra', 'byte-identical'),
            @('texdiagPerTexture', 'passed'))) {
            Assert-TextValue -Actual (Get-ObjectProperty -Object $validation -Name $gate[0]) -Expected $gate[1] `
                -Label "$componentId validation.$($gate[0])"
        }
        $textures = [int](Get-ObjectProperty -Object $counts -Name 'textures')
        $changedTextures = [int](Get-ObjectProperty -Object $counts -Name 'changedTextures')
        $skippedTextures = [int](Get-ObjectProperty -Object $counts -Name 'skippedTextures')
        $bc1 = [int](Get-ObjectProperty -Object $counts -Name 'changedBc1Textures')
        $bc3 = [int](Get-ObjectProperty -Object $counts -Name 'changedBc3Textures')
        Assert-Condition -Condition ($textures -gt 0 -and $changedTextures -gt 0 -and $changedTextures + $skippedTextures -eq $textures) `
            -Message "$componentId changed/skipped Texture counts are inconsistent."
        Assert-Condition -Condition ($bc1 + $bc3 -eq $changedTextures) -Message "$componentId BC1/BC3 counts do not equal changedTextures."
        Assert-Condition -Condition ([int](Get-ObjectProperty -Object $validation -Name 'texdiagValidatedTextures') -eq $textures) `
            -Message "$componentId texdiag did not cover every Texture."
        Assert-Condition -Condition (
            [int](Get-ObjectProperty -Object $validation -Name 'authorizedAlphaVerifiedTextures') +
            [int](Get-ObjectProperty -Object $validation -Name 'unauthorizedBgraVerifiedTextures') -eq $textures) `
            -Message "$componentId alpha/unauthorized BGRA checks did not cover every Texture."
        $ver5Totals.componentCount++
        $ver5Totals.changedTextures += $changedTextures
        $ver5Totals.skippedTextures += $skippedTextures
        $ver5Totals.changedBc1Textures += $bc1
        $ver5Totals.changedBc3Textures += $bc3
        $formatReport = [ordered]@{
            imgVersion = 'Ver5'
            textures = $textures
            changedTextures = $changedTextures
            skippedTextures = $skippedTextures
            changedBc1Textures = $bc1
            changedBc3Textures = $bc3
        }
    }
    elseif ($handler -match '(?i)ver2' -or $imgVersion -eq 'Ver2') {
        foreach ($gate in @(
            @('sourceIdentityReverified', 'passed-before-load-after-load-and-before-summary'),
            @('reopenedFromDisk', 'passed'),
            @('structureAndFrameOrder', 'passed'),
            @('typeAndCompression', 'preserved'),
            @('geometryAndLinks', 'preserved'),
            @('nativeZlibStatusAndLength', 'passed'),
            @('authorizedDecodedAlpha', 'byte-identical'),
            @('authorizedVisibleNearBlackRgb', 'byte-identical'),
            @('unauthorizedRawData', 'byte-identical'),
            @('unauthorizedDecodedBgra', 'byte-identical'))) {
            Assert-TextValue -Actual (Get-ObjectProperty -Object $validation -Name $gate[0]) -Expected $gate[1] `
                -Label "$componentId validation.$($gate[0])"
        }
        $changedFrames = [int](Get-ObjectProperty -Object $counts -Name 'changedFrames')
        $skippedFrames = [int](Get-ObjectProperty -Object $counts -Name 'skippedFrames')
        $linkFrames = [int](Get-ObjectProperty -Object $counts -Name 'linkFrames' -Default 0)
        $argb1555 = [int](Get-ObjectProperty -Object $counts -Name 'changedArgb1555Frames')
        $argb8888 = [int](Get-ObjectProperty -Object $counts -Name 'changedArgb8888Frames')
        Assert-Condition -Condition ($changedFrames -gt 0 -and $changedFrames + $skippedFrames + $linkFrames -eq $frames) `
            -Message "$componentId changed/skipped/LINK frame counts are inconsistent."
        Assert-Condition -Condition ($argb1555 + $argb8888 -eq $changedFrames) `
            -Message "$componentId ARGB1555/ARGB8888 counts do not equal changedFrames."
        Assert-Condition -Condition ([int](Get-ObjectProperty -Object $validation -Name 'authorizedNearBlackVerifiedFrames') -eq $changedFrames) `
            -Message "$componentId near-black verification did not cover every changed frame."

        $crossSnapshot = Get-EvidenceSnapshot -Component $component -PropertyName 'crossValidation'
        $negativeSnapshot = Get-EvidenceSnapshot -Component $component -PropertyName 'checkedZlibNegativeTest'
        if ($null -ne $crossSnapshot) {
            $crossPath = (Assert-FileSnapshot -Snapshot $crossSnapshot -RepositoryRoot $repoRoot -Label "$componentId cross-validation").path
        }
        else {
            $crossPath = Resolve-FilePath -Value 'cross-validation.json' -BaseDirectory (Split-Path -Parent $buildSummaryPath) `
                -Label "$componentId cross-validation"
        }
        if ($null -ne $negativeSnapshot) {
            $negativePath = (Assert-FileSnapshot -Snapshot $negativeSnapshot -RepositoryRoot $repoRoot -Label "$componentId checked-zlib negative test").path
        }
        else {
            $negativePath = Resolve-FilePath -Value 'checked-zlib-negative-test.json' -BaseDirectory (Split-Path -Parent $buildSummaryPath) `
                -Label "$componentId checked-zlib negative test"
        }
        $cross = Get-Content -LiteralPath $crossPath -Raw -Encoding UTF8 | ConvertFrom-Json
        $negative = Get-Content -LiteralPath $negativePath -Raw -Encoding UTF8 | ConvertFrom-Json
        Assert-TextValue -Actual (Get-ObjectProperty -Object $cross -Name 'status') -Expected 'passed' -Label "$componentId cross-validation status"
        $crossOutput = Get-ObjectProperty -Object $cross -Name 'output'
        Assert-Condition -Condition ((Get-NormalizedHash -Value (Get-ObjectProperty -Object $crossOutput -Name 'sha256') `
            -Label "$componentId cross-validation output hash") -eq $componentHash) -Message "$componentId cross-validation targets another artifact."
        $crossFrames = Get-ObjectProperty -Object $cross -Name 'frames'
        $metadataFields = @((Get-ObjectProperty -Object $crossFrames -Name 'metadataFields' -Default @()))
        Assert-Condition -Condition ($metadataFields.Count -gt 0 -and
            [long](Get-ObjectProperty -Object $crossFrames -Name 'metadataComparisons') -eq [long]$frames * $metadataFields.Count) `
            -Message "$componentId metadata cross-validation count is incomplete."
        $crossPixels = Get-ObjectProperty -Object $cross -Name 'pixels'
        Assert-Condition -Condition ([int](Get-ObjectProperty -Object $crossPixels -Name 'pixelFailureCount') -eq 0) `
            -Message "$componentId cross-validation reports pixel failures."
        Assert-Condition -Condition ([int](Get-ObjectProperty -Object $crossPixels -Name 'authorizedNearBlackVerifiedFrames') -eq $changedFrames) `
            -Message "$componentId cross-validation near-black coverage is incomplete."
        $crossDecode = Get-ObjectProperty -Object $cross -Name 'fullFrameDecode'
        Assert-Condition -Condition (
            [int](Get-ObjectProperty -Object $crossDecode -Name 'decodedNonLinkFrames') +
            [int](Get-ObjectProperty -Object $crossDecode -Name 'linkFrames') -eq $frames) `
            -Message "$componentId cross-validation did not decode or validate every frame."
        Assert-DeploymentNotPerformed -Deployment (Get-ObjectProperty -Object $cross -Name 'deployment') -Label "$componentId cross-validation"
        Assert-TextValue -Actual (Get-ObjectProperty -Object $negative -Name 'status') -Expected 'passed' `
            -Label "$componentId checked-zlib negative-test status"
        Assert-TextValue -Actual (Get-ObjectProperty -Object $negative -Name 'test') -Expected 'corrupt-zlib-payload-must-fail' `
            -Label "$componentId checked-zlib negative-test kind"

        $ver2Totals.componentCount++
        $ver2Totals.changedFrames += $changedFrames
        $ver2Totals.skippedFrames += $skippedFrames
        $ver2Totals.changedArgb1555Frames += $argb1555
        $ver2Totals.changedArgb8888Frames += $argb8888
        $formatReport = [ordered]@{
            imgVersion = 'Ver2'
            changedFrames = $changedFrames
            skippedFrames = $skippedFrames
            changedArgb1555Frames = $argb1555
            changedArgb8888Frames = $argb8888
            metadataComparisons = [long](Get-ObjectProperty -Object $crossFrames -Name 'metadataComparisons')
            checkedZlibNegativeTest = 'passed'
        }
    }
    else {
        throw "Selected component $componentId uses an unsupported or undeclared handler/version: $handler/$imgVersion"
    }

    $source = Get-ObjectProperty -Object $summary -Name 'source'
    $sourcePath = Resolve-FilePath -Value ([string](Get-ObjectProperty -Object $source -Name 'path')) -BaseDirectory $repoRoot `
        -Label "$componentId official source NPK"
    $sourceId = [string](Get-ObjectProperty -Object $component -Name 'sourceId')
    Assert-Condition -Condition (-not [string]::IsNullOrWhiteSpace($sourceId) -and $planSourceById.ContainsKey($sourceId)) `
        -Message "$componentId references an unknown resource-plan source id: $sourceId"
    $planSourceRecord = $planSourceById[$sourceId]
    Assert-Condition -Condition (@((Get-ObjectProperty -Object $planSourceRecord -Name 'componentIds' -Default @())) -contains $componentId) `
        -Message "$componentId is not listed by its resource-plan source record: $sourceId"
    $verifiedPlanSource = Assert-FileSnapshot -Snapshot (Get-ObjectProperty -Object $planSourceRecord -Name 'sourceNpk') `
        -RepositoryRoot $repoRoot -Label "$componentId resource-plan source NPK"
    $sourceItem = Get-Item -LiteralPath $sourcePath
    $sourceHash = (Get-FileHash -LiteralPath $sourcePath -Algorithm SHA256).Hash
    Assert-Condition -Condition ($sourcePath -ieq $verifiedPlanSource.path -and
        $sourceItem.Length -eq [long](Get-ObjectProperty -Object $source -Name 'length') -and
        $sourceItem.Length -eq [long]$verifiedPlanSource.length) `
        -Message "$componentId source NPK length changed."
    Assert-Condition -Condition ($sourceHash -eq (Get-NormalizedHash -Value (Get-ObjectProperty -Object $source -Name 'sha256') `
        -Label "$componentId source hash") -and $sourceHash -eq $verifiedPlanSource.sha256) `
        -Message "$componentId source NPK SHA-256 changed or differs from the resource plan."

    $sourceReports += [pscustomobject]@{
        componentId = $componentId
        path = $sourcePath
        length = $sourceItem.Length
        sha256 = $sourceHash
    }
    $configReports += [pscustomobject]@{
        componentId = $componentId
        path = $configPath
        length = (Get-Item -LiteralPath $configPath).Length
        sha256 = (Get-FileHash -LiteralPath $configPath -Algorithm SHA256).Hash
    }
    $componentReports += [pscustomobject]@{
        id = $componentId
        handler = $handler
        imgVersion = $imgVersion
        selectedImgCount = $summaryAllowed.Count
        frameCount = $frames
        output = [ordered]@{
            path = $componentNpkPath
            length = $componentItem.Length
            sha256 = $componentHash
        }
        buildSummary = [ordered]@{
            path = $buildSummaryPath
            length = (Get-Item -LiteralPath $buildSummaryPath).Length
            sha256 = (Get-FileHash -LiteralPath $buildSummaryPath -Algorithm SHA256).Hash
            status = 'passed'
        }
        gates = $formatReport
        deploymentPerformed = $false
    }
}

$reuseReports = @()
$reuseChangedFrames = 0L
$reusePreservedFrames = 0L
$reuseExpectedFrameCounts = New-Object 'Collections.Generic.Dictionary[string,int]' ([StringComparer]::OrdinalIgnoreCase)
foreach ($reuse in $selectedReuseComponents) {
    $reuseId = [string](Get-ObjectProperty -Object $reuse -Name 'id')
    Assert-Condition -Condition ($reuseId -eq 'cutin-weaponmaster-neo-v2' -and
        (Get-ObjectProperty -Object $reuse -Name 'mode') -eq 'validated-img-payload-reuse' -and
        (Get-ObjectProperty -Object $reuse -Name 'requiredForFinalAggregation') -eq $true -and
        (Get-ObjectProperty -Object $reuse -Name 'noRecolorConfig') -eq $true -and
        (Get-ObjectProperty -Object $reuse -Name 'componentContainsNonTargetImgs') -eq $true -and
        (Get-ObjectProperty -Object $reuse -Name 'aggregationRule') -eq
            'reuse only the selected target IMG payload, never the other 25 IMG entries') `
        -Message 'Cut-in reuse selection/mode/aggregation rule changed.'
    $baselinePolicy = Get-ObjectProperty -Object $reuse -Name 'baselinePolicy'
    Assert-Condition -Condition ((Get-ObjectProperty -Object $baselinePolicy -Name 'installedImagePacks2IsOfficialBaseline') -eq $false -and
        (Get-ObjectProperty -Object $baselinePolicy -Name 'useInstalledPackageAsBuildSource') -eq $false) `
        -Message 'Cut-in reuse must not treat the installed customized package as an official build source.'
    $sourceSnapshot = Get-ObjectProperty -Object $reuse -Name 'sourceComponent'
    $sourceFile = Assert-FileSnapshot -Snapshot $sourceSnapshot -RepositoryRoot $repoRoot -Label "$reuseId source component"
    $releaseSnapshot = Get-ObjectProperty -Object $reuse -Name 'releaseEvidence'
    $releaseFile = Assert-FileSnapshot -Snapshot $releaseSnapshot -RepositoryRoot $repoRoot -Label "$reuseId release evidence"
    $release = Get-Content -LiteralPath $releaseFile.path -Raw -Encoding UTF8 | ConvertFrom-Json
    Assert-DeploymentNotPerformed -Deployment (Get-ObjectProperty -Object $release -Name 'deployment') -Label "$reuseId release evidence"

    $releaseOutput = Get-ObjectProperty -Object $release -Name 'outputNpk'
    Assert-Condition -Condition ((Resolve-FilePath -Value ([string](Get-ObjectProperty -Object $releaseOutput -Name 'path')) `
        -BaseDirectory $repoRoot -Label "$reuseId release output") -ieq $sourceFile.path) `
        -Message "$reuseId release evidence points to another component."
    Assert-Condition -Condition ((Get-NormalizedHash -Value (Get-ObjectProperty -Object $releaseOutput -Name 'sha256') `
        -Label "$reuseId release output hash") -eq $sourceFile.sha256) -Message "$reuseId release output hash differs from the reusable component."

    $releaseValidation = Get-ObjectProperty -Object $release -Name 'validation'
    Assert-TextValue -Actual (Get-ObjectProperty -Object $releaseValidation -Name 'independentIndex') -Expected 'passed' `
        -Label "$reuseId independent index"
    Assert-Condition -Condition ([int](Get-ObjectProperty -Object $releaseValidation -Name 'metadataDiffCount') -eq 0) `
        -Message "$reuseId release evidence reports metadata differences."
    Assert-Condition -Condition ([int](Get-ObjectProperty -Object $releaseValidation -Name 'targetPixelFailureCount') -eq 0) `
        -Message "$reuseId release evidence reports target pixel failures."
    Assert-Condition -Condition (
        [int](Get-ObjectProperty -Object $releaseValidation -Name 'outputDecodedNonLinkFrames') +
        [int](Get-ObjectProperty -Object $releaseValidation -Name 'outputLinkFrames') -eq
        [int](Get-ObjectProperty -Object $releaseValidation -Name 'outputFrameCount')) `
        -Message "$reuseId release evidence did not decode or validate every frame."

    $selectedReusePaths = New-InternalPathSet -Values @((Get-ObjectProperty -Object $reuse -Name 'selectedImgPaths' -Default @())) `
        -Label "$reuseId selectedImgPaths"
    $releaseTarget = Get-ObjectProperty -Object $release -Name 'target'
    $targetImg = Get-InternalPath -Value (Get-ObjectProperty -Object $releaseTarget -Name 'img')
    Assert-Condition -Condition ($selectedReusePaths.Count -eq 1 -and $selectedReusePaths.Contains($targetImg)) `
        -Message "$reuseId release target does not exactly match selectedImgPaths."

    $changedFrameIndexes = @((Get-ObjectProperty -Object $releaseTarget -Name 'changedFrames' -Default @()))
    $preservedFrameIndexes = @((Get-ObjectProperty -Object $releaseTarget -Name 'preservedTransparentFrames' -Default @()))
    Assert-Condition -Condition ($changedFrameIndexes.Count -eq 24 -and $preservedFrameIndexes.Count -eq 3) `
        -Message "$reuseId changed/preserved frame counts changed."
    $frameSet = New-Object 'Collections.Generic.HashSet[int]'
    foreach ($frameIndex in @($changedFrameIndexes + $preservedFrameIndexes)) {
        Assert-Condition -Condition $frameSet.Add([int]$frameIndex) -Message "$reuseId release target has a duplicate frame index: $frameIndex"
    }
    Assert-Condition -Condition ($frameSet.Count -eq 27) -Message "$reuseId selected Cut-in target must contain exactly 27 frames, found $($frameSet.Count)."
    for ($frameIndex = 0; $frameIndex -lt 27; $frameIndex++) {
        Assert-Condition -Condition $frameSet.Contains($frameIndex) -Message "$reuseId selected Cut-in target is missing frame $frameIndex."
    }
    $reuseChangedFrames += $changedFrameIndexes.Count
    $reusePreservedFrames += $preservedFrameIndexes.Count
    $expectedAlbumCount += $selectedReusePaths.Count
    $expectedFrameCount += $frameSet.Count
    $reuseExpectedFrameCounts.Add($targetImg, $frameSet.Count)

    $rawReuse = Read-NpkPayloadInventory -Path $sourceFile.path -Label "$reuseId reusable component"
    $rawReuseEntries = ConvertTo-EntryDictionary -Entries $rawReuse.entries -Label "$reuseId reusable component"
    foreach ($path in $selectedReusePaths) {
        Assert-Condition -Condition $rawReuseEntries.ContainsKey($path) -Message "$reuseId reusable component is missing selected IMG: $path"
        Assert-Condition -Condition $expectedPaths.Add($path) -Message "Selected IMG path is owned by more than one component: $path"
        $rawEntry = $rawReuseEntries[$path]
        $expectedPayloadSources.Add($path, [pscustomobject]@{
            ownerId = $reuseId
            sourceNpk = $sourceFile.path
            sourceNpkSha256 = $sourceFile.sha256
            payloadLength = [long]$rawEntry.payloadLength
            payloadSha256 = [string]$rawEntry.payloadSha256
        })
    }

    $reuseReports += [pscustomobject]@{
        id = $reuseId
        mode = [string](Get-ObjectProperty -Object $reuse -Name 'mode')
        selectedImgCount = $selectedReusePaths.Count
        selectedFrameCount = $frameSet.Count
        changedFrames = $changedFrameIndexes.Count
        preservedTransparentFrames = $preservedFrameIndexes.Count
        sourceComponent = $sourceFile
        releaseEvidence = $releaseFile
        componentEntryCount = $rawReuse.entryCount
        deploymentPerformed = $false
    }
}

Assert-Condition -Condition ($expectedAlbumCount -eq $expectedPaths.Count) `
    -Message "Expected album count does not equal the unique selected IMG count: $expectedAlbumCount/$($expectedPaths.Count)"

$planTotals = Get-ObjectProperty -Object $plan -Name 'totals'
Assert-Condition -Condition ($null -ne $planTotals) -Message 'Resource plan totals are missing.'
Assert-Condition -Condition ([int](Get-ObjectProperty -Object $planTotals -Name 'configCount') -eq $selectedComponents.Count) `
    -Message 'Resource plan configCount differs from the selected component count.'
Assert-Condition -Condition ([int](Get-ObjectProperty -Object $planTotals -Name 'reuseComponentCount') -eq $selectedReuseComponents.Count) `
    -Message 'Resource plan reuseComponentCount differs from the selected reuse count.'
Assert-Condition -Condition ([int](Get-ObjectProperty -Object $planTotals -Name 'finalAggregateSelectedImgCount') -eq $expectedPaths.Count) `
    -Message 'Resource plan finalAggregateSelectedImgCount differs from the selected IMG set.'
Assert-Condition -Condition ([int](Get-ObjectProperty -Object $planTotals -Name 'allowedImgCount') +
    [int](Get-ObjectProperty -Object $planTotals -Name 'reuseSelectedImgCount') -eq $expectedPaths.Count) `
    -Message 'Resource plan allowed/reuse IMG totals do not cover the final selected IMG set.'
Assert-Condition -Condition ([int](Get-ObjectProperty -Object $planTotals -Name 'finalAuthorizedChangedFrameCount') -eq
    [int](Get-ObjectProperty -Object $planTotals -Name 'authorizedFrameCount') +
    [int](Get-ObjectProperty -Object $planTotals -Name 'reuseChangedFrameCount')) `
    -Message 'Resource plan final authorized-change frame total is inconsistent.'
Assert-Condition -Condition (
    [int](Get-ObjectProperty -Object $planTotals -Name 'sourceCount') -eq 28 -and
    [int](Get-ObjectProperty -Object $planTotals -Name 'configCount') -eq 31 -and
    [int](Get-ObjectProperty -Object $planTotals -Name 'allowedImgCount') -eq 417 -and
    [int](Get-ObjectProperty -Object $planTotals -Name 'preBuildAuthorizedFrameCount') -eq 3667 -and
    [int](Get-ObjectProperty -Object $planTotals -Name 'authorizedFrameCount') -eq 3593 -and
    [int](Get-ObjectProperty -Object $planTotals -Name 'explicitExcludedFrameCount') -eq 128 -and
    [int](Get-ObjectProperty -Object $planTotals -Name 'dynamicPreservedFrameCount') -eq 74 -and
    [int](Get-ObjectProperty -Object $planTotals -Name 'excludedFrameCount') -eq 202 -and
    [int](Get-ObjectProperty -Object $planTotals -Name 'selectedFrameCount') -eq 3795 -and
    [int](Get-ObjectProperty -Object $planTotals -Name 'wholeImgGateExcludedFrameCount') -eq 19 -and
    [int](Get-ObjectProperty -Object $planTotals -Name 'candidatePoolExcludedFrameCount') -eq 221 -and
    [int](Get-ObjectProperty -Object $planTotals -Name 'reuseChangedFrameCount') -eq $reuseChangedFrames -and
    [int](Get-ObjectProperty -Object $planTotals -Name 'reusePreservedFrameCount') -eq $reusePreservedFrames -and
    $reuseChangedFrames -eq 24 -and $reusePreservedFrames -eq 3 -and
    [int](Get-ObjectProperty -Object $planTotals -Name 'finalAggregateSelectedImgCount') -eq 418 -and
    [int](Get-ObjectProperty -Object $planTotals -Name 'finalAuthorizedChangedFrameCount') -eq 3617 -and
    [int](Get-ObjectProperty -Object $planTotals -Name 'finalSelectedFrameCount') -eq 3822 -and
    [int](Get-ObjectProperty -Object $planTotals -Name 'finalPreservedFrameCount') -eq 205 -and
    $expectedAlbumCount -eq 418 -and $expectedFrameCount -eq 3822) `
    -Message 'Resource plan/final aggregation exact IMG and frame totals changed.'

$planCoverage = Get-ObjectProperty -Object $plan -Name 'coverage'
Assert-Condition -Condition ($null -ne $planCoverage) -Message 'Resource plan coverage object is missing.'
Assert-Condition -Condition ((Get-ObjectProperty -Object $planCoverage -Name 'fullSkillCoverageProven') -eq $false) `
    -Message 'Resource plan claimed fullSkillCoverageProven before final aggregation and validation completed.'
Assert-Condition -Condition (-not [string]::IsNullOrWhiteSpace(
    [string](Get-ObjectProperty -Object $planCoverage -Name 'reason' -Default ''))) `
    -Message 'Resource plan coverage reason is missing.'

$selectedComponentIdSet = New-Object 'Collections.Generic.HashSet[string]' ([StringComparer]::OrdinalIgnoreCase)
foreach ($component in $selectedComponents) {
    [void]$selectedComponentIdSet.Add([string](Get-ObjectProperty -Object $component -Name 'id'))
}
$technicalRoots = @((Get-ObjectProperty -Object $planCoverage -Name 'technicalRoots' -Default @()))
Assert-Condition -Condition ($technicalRoots.Count -gt 0) -Message 'Resource plan has no technical-root coverage records.'
$technicalRootSet = New-Object 'Collections.Generic.HashSet[string]' ([StringComparer]::OrdinalIgnoreCase)
foreach ($root in $technicalRoots) {
    $rootId = [string](Get-ObjectProperty -Object $root -Name 'technicalRoot')
    Assert-Condition -Condition (-not [string]::IsNullOrWhiteSpace($rootId) -and $technicalRootSet.Add($rootId)) `
        -Message "Resource plan has an empty or duplicate technical root: $rootId"
    Assert-Condition -Condition ((Get-ObjectProperty -Object $root -Name 'resourceIdentityProven') -eq $true) `
        -Message "Technical root is not identity-proven: $rootId"
    $rootComponentIds = @((Get-ObjectProperty -Object $root -Name 'componentIds' -Default @()))
    Assert-Condition -Condition ($rootComponentIds.Count -gt 0) -Message "Technical root has no component mapping: $rootId"
    foreach ($componentId in $rootComponentIds) {
        Assert-Condition -Condition $selectedComponentIdSet.Contains([string]$componentId) `
            -Message "Technical root maps to a non-selected component: $rootId/$componentId"
    }
}

$unresolvedNoDedicatedRoots = @((Get-ObjectProperty -Object $planCoverage -Name 'unresolvedNoDedicatedVisualRoots' -Default @()))
foreach ($entry in $unresolvedNoDedicatedRoots) {
    Assert-Condition -Condition ([int](Get-ObjectProperty -Object $entry -Name 'matchingInternalPathCount') -eq 0 -and
        [string](Get-ObjectProperty -Object $entry -Name 'status') -match 'no-target-male-swordman-visual-root-found') `
        -Message "Unresolved Replay skill is not backed by a zero-match visual-root audit: $(Get-ObjectProperty -Object $entry -Name 'replaySkill')"
}
$excludedTechnicalRoots = @((Get-ObjectProperty -Object $planCoverage -Name 'excludedTechnicalRoots' -Default @()))
$excludedTechnicalRootSet = New-Object 'Collections.Generic.HashSet[string]' ([StringComparer]::OrdinalIgnoreCase)
foreach ($entry in $excludedTechnicalRoots) {
    $rootId = [string](Get-ObjectProperty -Object $entry -Name 'technicalRoot')
    Assert-Condition -Condition (-not [string]::IsNullOrWhiteSpace($rootId) -and $excludedTechnicalRootSet.Add($rootId) -and
        -not [string]::IsNullOrWhiteSpace([string](Get-ObjectProperty -Object $entry -Name 'reason'))) `
        -Message "Excluded technical root is incomplete or duplicated: $rootId"
}
$remainingGates = @((Get-ObjectProperty -Object $planCoverage -Name 'remainingGates' -Default @()))
$remainingGateSet = New-Object 'Collections.Generic.HashSet[string]' ([StringComparer]::OrdinalIgnoreCase)
foreach ($gate in $remainingGates) {
    Assert-Condition -Condition (-not [string]::IsNullOrWhiteSpace([string]$gate) -and $remainingGateSet.Add([string]$gate)) `
        -Message "Resource plan has an empty or duplicate remaining gate: $gate"
}
$expectedRemainingGateSet = New-Object 'Collections.Generic.HashSet[string]' ([StringComparer]::OrdinalIgnoreCase)
foreach ($gate in @(
    'aggregate authorized changed IMG plus Cut-in target IMG',
    'independent structural and pixel validation',
    'full-frame contact sheets',
    'release.json',
    'target-client A/B; no deployment')) {
    [void]$expectedRemainingGateSet.Add($gate)
}
Assert-SetEqual -Expected $expectedRemainingGateSet -Actual $remainingGateSet `
    -Label 'Post-build/pre-release remaining gates'

$finalItem = Get-Item -LiteralPath $finalPath
$finalHash = (Get-FileHash -LiteralPath $finalPath -Algorithm SHA256).Hash
$packageEntries = @((Get-ObjectProperty -Object $packageResult -Name 'entries' -Default @()))
$packageEntryDictionary = ConvertTo-EntryDictionary -Entries $packageEntries -Label 'Package summary entries'
$packagePaths = New-InternalPathSet -Values @($packageEntries | ForEach-Object { Get-ObjectProperty -Object $_ -Name 'path' }) `
    -Label 'Package summary entries'
Assert-SetEqual -Expected $expectedPaths -Actual $packagePaths -Label 'Resource-plan/package-summary IMG paths'
Assert-Condition -Condition ([int](Get-ObjectProperty -Object $packageResult -Name 'entryCount') -eq $expectedPaths.Count) `
    -Message 'Package summary entryCount differs from its entries and the resource plan.'

$packageOutputValue = Get-ObjectProperty -Object $packageResult -Name 'output'
if ($packageOutputValue -is [string]) {
    $packageOutputPath = Resolve-FilePath -Value ([string]$packageOutputValue) -BaseDirectory $repoRoot -Label 'Package summary output'
}
else {
    $packageOutputPath = Resolve-FilePath -Value ([string](Get-ObjectProperty -Object $packageOutputValue -Name 'path')) `
        -BaseDirectory $repoRoot -Label 'Package summary output'
}
Assert-Condition -Condition ($packageOutputPath -ieq $finalPath) -Message 'Package summary points to another final NPK.'
$packageLength = if (Test-ObjectProperty -Object $packageResult -Name 'length') {
    [long](Get-ObjectProperty -Object $packageResult -Name 'length')
}
else {
    [long](Get-ObjectProperty -Object $packageOutputValue -Name 'length')
}
$packageHash = if (Test-ObjectProperty -Object $packageResult -Name 'sha256') {
    Get-NormalizedHash -Value (Get-ObjectProperty -Object $packageResult -Name 'sha256') -Label 'Package final hash'
}
else {
    Get-NormalizedHash -Value (Get-ObjectProperty -Object $packageOutputValue -Name 'sha256') -Label 'Package final hash'
}
Assert-Condition -Condition ($packageLength -eq $finalItem.Length -and $packageHash -eq $finalHash) `
    -Message 'Package summary final length/SHA-256 differs from FinalNpk.'
Assert-DeploymentNotPerformed -Deployment (Get-ObjectProperty -Object $packageResult -Name 'deployment') -Label 'Packager' -AllowString

$finalRaw = Read-NpkPayloadInventory -Path $finalPath -Label 'Final NPK'
$finalRawEntries = ConvertTo-EntryDictionary -Entries $finalRaw.entries -Label 'Final NPK'
$finalRawPaths = New-InternalPathSet -Values @($finalRaw.entries | ForEach-Object { $_.path }) -Label 'Final NPK paths'
Assert-SetEqual -Expected $expectedPaths -Actual $finalRawPaths -Label 'Resource-plan/final NPK IMG paths'

foreach ($path in $expectedPaths) {
    $expected = $expectedPayloadSources[$path]
    $packaged = $packageEntryDictionary[$path]
    $finalEntry = $finalRawEntries[$path]
    $packagedHash = Get-NormalizedHash -Value (Get-ObjectProperty -Object $packaged -Name 'payloadSha256') `
        -Label "Package payload hash for $path"
    $packagedLength = [long](Get-ObjectProperty -Object $packaged -Name 'payloadLength')
    Assert-Condition -Condition ($packagedLength -eq $expected.payloadLength -and $packagedHash -eq $expected.payloadSha256) `
        -Message "Package entry does not match the selected component payload: $path"
    Assert-Condition -Condition ([long]$finalEntry.payloadLength -eq $expected.payloadLength -and
        [string]$finalEntry.payloadSha256 -eq $expected.payloadSha256) `
        -Message "Final raw IMG payload does not match the selected component payload: $path"
    $packagedSourcePath = Resolve-FilePath -Value ([string](Get-ObjectProperty -Object $packaged -Name 'sourceNpk')) `
        -BaseDirectory $repoRoot -Label "Package source for $path"
    Assert-Condition -Condition ($packagedSourcePath -ieq $expected.sourceNpk) `
        -Message "Package entry was sourced from an undeclared component: $path"
}

$expectedSourcePaths = New-Object 'Collections.Generic.HashSet[string]' ([StringComparer]::OrdinalIgnoreCase)
foreach ($expected in $expectedPayloadSources.Values) {
    [void]$expectedSourcePaths.Add([IO.Path]::GetFullPath([string]$expected.sourceNpk))
}
$packageSourcePaths = New-Object 'Collections.Generic.HashSet[string]' ([StringComparer]::OrdinalIgnoreCase)
foreach ($source in @((Get-ObjectProperty -Object $packageResult -Name 'sources' -Default @()))) {
    $sourcePath = Resolve-FilePath -Value ([string](Get-ObjectProperty -Object $source -Name 'path')) -BaseDirectory $repoRoot `
        -Label 'Package source NPK'
    Assert-Condition -Condition $packageSourcePaths.Add($sourcePath) -Message "Package summary has a duplicate source NPK: $sourcePath"
    $currentHash = (Get-FileHash -LiteralPath $sourcePath -Algorithm SHA256).Hash
    Assert-Condition -Condition ($currentHash -eq (Get-NormalizedHash -Value (Get-ObjectProperty -Object $source -Name 'sha256') `
        -Label "Package source hash for $sourcePath")) -Message "Package source NPK changed after packaging: $sourcePath"
}
Assert-SetEqual -Expected $expectedSourcePaths -Actual $packageSourcePaths -Label 'Selected/package source NPK paths'

$indexTool = Resolve-FilePath -Value 'tools/Test-DnfNpkIndex.ps1' -BaseDirectory $repoRoot -Label 'Independent NPK index tool'
$exportTool = Resolve-FilePath -Value 'tools/Export-DnfNpkValidation.ps1' -BaseDirectory $repoRoot -Label 'Full-frame validation tool'
$indexReportPath = Join-Path $outputPath 'independent-index.json'
$indexJsonText = (& $indexTool -Path $finalPath -ExpectedEntryCount $expectedPaths.Count -ExpectedSha256 $finalHash -AsJson | Out-String).Trim()
Assert-Condition -Condition (-not [string]::IsNullOrWhiteSpace($indexJsonText)) -Message 'Independent NPK index tool returned no JSON.'
$indexResult = $indexJsonText | ConvertFrom-Json
Assert-Condition -Condition ([int](Get-ObjectProperty -Object $indexResult -Name 'EntryCount') -eq $expectedPaths.Count -and
    [int](Get-ObjectProperty -Object $indexResult -Name 'UniquePathCount') -eq $expectedPaths.Count -and
    (Get-ObjectProperty -Object $indexResult -Name 'HeaderSha256Valid') -eq $true -and
    [int](Get-ObjectProperty -Object $indexResult -Name 'ImgMagicValidCount') -eq $expectedPaths.Count) `
    -Message 'Independent NPK index result is incomplete or failed.'
$indexJsonText | Set-Content -LiteralPath $indexReportPath -Encoding UTF8

$powerShell32 = Join-Path $env:WINDIR 'SysWOW64\WindowsPowerShell\v1.0\powershell.exe'
Assert-Condition -Condition (Test-Path -LiteralPath $powerShell32 -PathType Leaf) `
    -Message "32-bit Windows PowerShell is required for ExtractorSharp x86 zlib validation: $powerShell32"
$fullFramePath = Join-Path $outputPath 'full-frame-validation'
Assert-Condition -Condition (-not (Test-Path -LiteralPath $fullFramePath)) -Message "Full-frame validation output already exists: $fullFramePath"
$exportOutput = (& $powerShell32 -NoProfile -NonInteractive -ExecutionPolicy Bypass -File $exportTool `
    -InputFile $finalPath -OutputDirectory $fullFramePath -ExtractorDirectory $extractorPath 2>&1 | Out-String)
$exportExitCode = $LASTEXITCODE
$exportLogPath = Join-Path $outputPath 'full-frame-validation.log'
$exportOutput | Set-Content -LiteralPath $exportLogPath -Encoding UTF8
Assert-Condition -Condition ($exportExitCode -eq 0) -Message "32-bit full-frame validation failed with exit code $exportExitCode. See $exportLogPath"

$albumInventoryPath = Resolve-FilePath -Value 'album-inventory.json' -BaseDirectory $fullFramePath -Label 'Final album inventory'
$frameInventoryPath = Resolve-FilePath -Value 'frame-inventory.csv' -BaseDirectory $fullFramePath -Label 'Final frame inventory'
$albumInventory = Get-Content -LiteralPath $albumInventoryPath -Raw -Encoding UTF8 | ConvertFrom-Json
$frameInventory = @(Import-Csv -LiteralPath $frameInventoryPath -Encoding UTF8)
Assert-Condition -Condition ([int](Get-ObjectProperty -Object $albumInventory -Name 'AlbumCount') -eq $expectedAlbumCount) `
    -Message "Final album count differs from selected components plus Cut-in: $(Get-ObjectProperty -Object $albumInventory -Name 'AlbumCount')/$expectedAlbumCount"
Assert-Condition -Condition ([int](Get-ObjectProperty -Object $albumInventory -Name 'FrameCount') -eq $expectedFrameCount) `
    -Message "Final frame count differs from selected component summaries plus the 27-frame Cut-in: $(Get-ObjectProperty -Object $albumInventory -Name 'FrameCount')/$expectedFrameCount"
Assert-Condition -Condition ($frameInventory.Count -eq $expectedFrameCount) -Message 'Final frame inventory row count is incomplete.'
Assert-Condition -Condition (
    [int](Get-ObjectProperty -Object $albumInventory -Name 'DecodedNonLinkFrames') +
    [int](Get-ObjectProperty -Object $albumInventory -Name 'LinkFrames') -eq $expectedFrameCount) `
    -Message 'Not every final frame was decoded or LINK-validated.'

$albumPaths = New-InternalPathSet -Values @((Get-ObjectProperty -Object $albumInventory -Name 'Albums') | ForEach-Object {
    Get-ObjectProperty -Object $_ -Name 'Path'
}) -Label 'Final ExtractorSharp album paths'
Assert-SetEqual -Expected $expectedPaths -Actual $albumPaths -Label 'Selected/final decoded IMG paths'
foreach ($reusePath in $reuseExpectedFrameCounts.Keys) {
    $matchingAlbums = @((Get-ObjectProperty -Object $albumInventory -Name 'Albums') | Where-Object {
        (Get-InternalPath -Value (Get-ObjectProperty -Object $_ -Name 'Path')) -ieq $reusePath
    })
    Assert-Condition -Condition ($matchingAlbums.Count -eq 1 -and
        [int](Get-ObjectProperty -Object $matchingAlbums[0] -Name 'FrameCount') -eq $reuseExpectedFrameCounts[$reusePath]) `
        -Message "Final reused Cut-in album does not contain the declared 27 frames: $reusePath"
}
$backgroundSet = New-InternalPathSet -Values @((Get-ObjectProperty -Object $albumInventory -Name 'Backgrounds')) `
    -Label 'Contact-sheet backgrounds'
$expectedBackgroundSet = New-InternalPathSet -Values @('black', 'white', 'checkerboard') -Label 'Expected contact-sheet backgrounds'
Assert-SetEqual -Expected $expectedBackgroundSet -Actual $backgroundSet -Label 'Contact-sheet backgrounds'

$sheetDirectory = Join-Path $fullFramePath 'sheets'
$sheets = @(Get-ChildItem -LiteralPath $sheetDirectory -Filter 'frames-*.png' -File | Sort-Object Name)
Assert-Condition -Condition ($sheets.Count -eq [int](Get-ObjectProperty -Object $albumInventory -Name 'SheetCount') -and $sheets.Count -gt 0) `
    -Message 'Final black/white/checkerboard contact-sheet count is incomplete.'
$sheetReports = @($sheets | ForEach-Object {
    [pscustomobject]@{
        path = $_.FullName
        length = $_.Length
        sha256 = (Get-FileHash -LiteralPath $_.FullName -Algorithm SHA256).Hash
    }
})

$frameFormatCounts = [ordered]@{}
foreach ($group in @($frameInventory | Group-Object -Property Type | Sort-Object Name)) {
    $frameFormatCounts[[string]$group.Name] = [int]$group.Count
}
$versionCounts = [ordered]@{}
$indexVersions = Get-ObjectProperty -Object $indexResult -Name 'ImgVersionCounts'
foreach ($property in @($indexVersions.PSObject.Properties | Sort-Object Name)) {
    $versionCounts[[string]$property.Name] = [int]$property.Value
}

$toolReports = @()
foreach ($tool in @(
    [pscustomobject]@{ label = 'resource-plan'; path = $planPath },
    [pscustomobject]@{ label = 'resource-plan-validator'; path = $resourcePlanValidatorPath },
    [pscustomobject]@{ label = 'post-build-frame-accounting'; path = $accountingReport.path },
    [pscustomobject]@{ label = 'package-summary'; path = $packagePath },
    [pscustomobject]@{ label = 'custom-npk-packager'; path = (Resolve-FilePath -Value 'tools/New-DnfCustomNpk.ps1' -BaseDirectory $repoRoot -Label 'Custom NPK packager') },
    [pscustomobject]@{ label = 'independent-index'; path = $indexTool },
    [pscustomobject]@{ label = 'full-frame-export'; path = $exportTool },
    [pscustomobject]@{ label = 'texdiag'; path = (Resolve-FilePath -Value 'tools/bin/directxtex/may2026/texdiag.exe' -BaseDirectory $repoRoot -Label 'texdiag') },
    [pscustomobject]@{ label = 'final-release-validator'; path = $PSCommandPath })) {
    $item = Get-Item -LiteralPath $tool.path
    $toolReports += [pscustomobject]@{
        label = $tool.label
        path = $item.FullName
        length = $item.Length
        sha256 = (Get-FileHash -LiteralPath $item.FullName -Algorithm SHA256).Hash
    }
}
foreach ($dependencyName in @('ExtractorSharp.Core.dll', 'ExtractorSharp.Json.dll', 'zlib1.dll')) {
    $dependencyPath = Resolve-FilePath -Value $dependencyName -BaseDirectory $extractorPath -Label $dependencyName
    $dependencyItem = Get-Item -LiteralPath $dependencyPath
    $toolReports += [pscustomobject]@{
        label = $dependencyName
        path = $dependencyPath
        length = $dependencyItem.Length
        sha256 = (Get-FileHash -LiteralPath $dependencyPath -Algorithm SHA256).Hash
    }
}
foreach ($snapshot in @((Get-ObjectProperty -Object $planEvidence -Name 'builderSnapshots' -Default @()))) {
    $verified = Assert-FileSnapshot -Snapshot $snapshot -RepositoryRoot $repoRoot -Label 'Resource-plan builder snapshot'
    $toolReports += [pscustomobject]@{
        label = [string](Get-ObjectProperty -Object $snapshot -Name 'kind' -Default 'builder-snapshot')
        path = $verified.path
        length = $verified.length
        sha256 = $verified.sha256
    }
}
foreach ($snapshotCollectionName in @('toolSnapshots', 'validatorSnapshots')) {
    foreach ($snapshot in @((Get-ObjectProperty -Object $planEvidence -Name $snapshotCollectionName -Default @()))) {
        $verified = Assert-FileSnapshot -Snapshot $snapshot -RepositoryRoot $repoRoot `
            -Label "Resource-plan $snapshotCollectionName snapshot"
        $toolReports += [pscustomobject]@{
            label = [string](Get-ObjectProperty -Object $snapshot -Name 'kind' -Default $snapshotCollectionName)
            path = $verified.path
            length = $verified.length
            sha256 = $verified.sha256
        }
    }
}

$summaryPath = Join-Path $outputPath 'final-validation-summary.json'
$temporarySummaryPath = Join-Path $outputPath ('.final-validation-summary.' + [Guid]::NewGuid().ToString('N') + '.tmp')
$finalSummary = [ordered]@{
    schemaVersion = 1
    generatedAtUtc = [DateTime]::UtcNow.ToString('o')
    status = 'passed'
    mode = 'offline read-only release validation; no deployment or process operation'
    resourcePlan = [ordered]@{
        inputPath = $planPath
        validatedSnapshotPath = $planSnapshotPath
        length = (Get-Item -LiteralPath $planSnapshotPath).Length
        sha256 = (Get-FileHash -LiteralPath $planSnapshotPath -Algorithm SHA256).Hash
        planId = [string](Get-ObjectProperty -Object $plan -Name 'planId')
        selectedComponentIds = @($componentReports | ForEach-Object { $_.id })
        explicitlyNonSelectedComponentIds = @($skippedComponents)
        selectedReuseComponentIds = @($reuseReports | ForEach-Object { $_.id })
        explicitlyNonSelectedReuseComponentIds = @($skippedReuseComponents)
        totals = $planTotals
        preAggregationGate = [ordered]@{
            status = [string]$resourcePlanGate.Status
            validator = [ordered]@{
                path = $resourcePlanValidatorPath
                length = (Get-Item -LiteralPath $resourcePlanValidatorPath).Length
                sha256 = (Get-FileHash -LiteralPath $resourcePlanValidatorPath -Algorithm SHA256).Hash
            }
            effectiveChangedFrames = [int]$resourcePlanGate.EffectiveChangedFrameCount
            explicitPreservedFrames = [int]$resourcePlanGate.ExplicitExcludedFrameKeyCount
            dynamicPreservedFrames = [int]$resourcePlanGate.DynamicPreservedFrameKeyCount
            selectedFrames = [int]$resourcePlanGate.SelectedFrameCount
        }
        postBuildFrameAccounting = [ordered]@{
            path = $accountingReport.path
            length = $accountingReport.length
            sha256 = $accountingReport.sha256
            dynamicTextureGroups = [int]$accounting.totals.dynamicSkippedTextureGroupCount
            dynamicFrameReferences = [int]$accounting.totals.dynamicExcludedFrameReferenceCount
            payloadHashMismatchCount = 0
            partitionOverlapCount = [int]$accounting.totals.partitionOverlapCount
        }
        coverageAtValidationStart = [ordered]@{
            fullSkillCoverageProven = $false
            reason = [string](Get-ObjectProperty -Object $planCoverage -Name 'reason')
            technicalRoots = $technicalRoots
            unresolvedNoDedicatedVisualRoots = $unresolvedNoDedicatedRoots
            excludedTechnicalRoots = $excludedTechnicalRoots
            remainingGates = $remainingGates
        }
    }
    finalArtifact = [ordered]@{
        path = $finalPath
        length = $finalItem.Length
        sha256 = $finalHash
        imgCount = $expectedPaths.Count
        frameCount = $expectedFrameCount
        deploymentPerformed = $false
    }
    packageSummary = [ordered]@{
        path = $packagePath
        length = (Get-Item -LiteralPath $packagePath).Length
        sha256 = (Get-FileHash -LiteralPath $packagePath -Algorithm SHA256).Hash
        generatedAtUtc = $packageGeneratedAtValue.ToUniversalTime().ToString('o')
        packager = $packagerReport
        payloadEquivalence = 'passed'
        selectedSourceEquivalence = 'passed'
        deploymentPerformed = $false
    }
    selection = [ordered]@{
        imgCount = $expectedPaths.Count
        imgPaths = @($expectedPaths | Sort-Object)
        duplicateCount = 0
        rawPayloadLengthAndSha256 = 'identical-to-packager-and-selected-source-components'
    }
    counts = [ordered]@{
        albums = $expectedAlbumCount
        frames = $expectedFrameCount
        decodedNonLinkFrames = [int](Get-ObjectProperty -Object $albumInventory -Name 'DecodedNonLinkFrames')
        linkFrames = [int](Get-ObjectProperty -Object $albumInventory -Name 'LinkFrames')
        hiddenFrames = [int](Get-ObjectProperty -Object $albumInventory -Name 'HiddenFrames')
        imgVersionCounts = $versionCounts
        finalFrameFormatCounts = $frameFormatCounts
        ver5 = $ver5Totals
        ver2 = $ver2Totals
        reusedCutin = [ordered]@{
            changedFrames = $reuseChangedFrames
            preservedTransparentFrames = $reusePreservedFrames
            totalFrames = $reuseChangedFrames + $reusePreservedFrames
        }
    }
    components = @($componentReports)
    reuseComponents = @($reuseReports)
    validation = [ordered]@{
        manifestScopeOfflineCoverage = [ordered]@{
            status = 'passed'
            meaning = 'All selected visual roots, shared resources, authorized changes, safety exclusions, and the selected Cut-in payload in the current resource plan passed offline gates.'
            eligibleForReleaseMetadataFullSkillCoverage = $true
            fullSkillCoverageProvenAtValidationStart = $false
            releaseMetadataGeneratedByThisValidator = $false
            releaseMetadataRequiredBeforeCoverageTransition = $true
            targetClientCompatibilityProven = $false
        }
        independentIndex = [ordered]@{
            status = 'passed'
            report = $indexReportPath
            reportSha256 = (Get-FileHash -LiteralPath $indexReportPath -Algorithm SHA256).Hash
            parserDependency = [string](Get-ObjectProperty -Object $indexResult -Name 'ParserDependency')
        }
        componentStructureFormatAlphaUnauthorizedAndTexdiag = 'passed'
        ver2CheckedZlibNearBlackAndMetadata = if ($ver2Totals.componentCount -gt 0) { 'passed' } else { 'not-applicable' }
        fullFrame = [ordered]@{
            status = 'passed'
            powershell = $powerShell32
            decodedNonLinkFrames = [int](Get-ObjectProperty -Object $albumInventory -Name 'DecodedNonLinkFrames')
            validatedLinkFrames = [int](Get-ObjectProperty -Object $albumInventory -Name 'LinkFrames')
            backgrounds = @('black', 'white', 'checkerboard')
            albumInventory = [ordered]@{
                path = $albumInventoryPath
                length = (Get-Item -LiteralPath $albumInventoryPath).Length
                sha256 = (Get-FileHash -LiteralPath $albumInventoryPath -Algorithm SHA256).Hash
            }
            frameInventory = [ordered]@{
                path = $frameInventoryPath
                length = (Get-Item -LiteralPath $frameInventoryPath).Length
                sha256 = (Get-FileHash -LiteralPath $frameInventoryPath -Algorithm SHA256).Hash
            }
            contactSheets = $sheetReports
            log = [ordered]@{
                path = $exportLogPath
                length = (Get-Item -LiteralPath $exportLogPath).Length
                sha256 = (Get-FileHash -LiteralPath $exportLogPath -Algorithm SHA256).Hash
            }
        }
    }
    provenance = [ordered]@{
        officialSources = @($sourceReports)
        componentConfigs = @($configReports)
        componentToolchains = @($componentToolReports)
        tools = @($toolReports)
    }
    deployment = [ordered]@{
        authorized = $false
        performed = $false
        imagePacks2Write = $false
        processOperation = $false
        status = 'not-authorized-not-performed'
    }
    pending = @(
        'release.json and manifest coverage metadata must be generated from this passed summary before fullSkillCoverageProven can transition to true.',
        'Target-client A/B verification remains user-owned and pending.',
        'Filename ordering does not prove client override priority.'
    )
}

try {
    $finalSummary | ConvertTo-Json -Depth 20 | Set-Content -LiteralPath $temporarySummaryPath -Encoding UTF8
    Assert-Condition -Condition (-not (Test-Path -LiteralPath $summaryPath)) -Message "Refusing to overwrite an existing final validation summary: $summaryPath"
    [IO.File]::Move($temporarySummaryPath, $summaryPath)
}
finally {
    if (Test-Path -LiteralPath $temporarySummaryPath) {
        Remove-Item -LiteralPath $temporarySummaryPath -Force
    }
}

[pscustomobject]@{
    Status = 'passed'
    FinalNpk = $finalPath
    FinalSha256 = $finalHash
    ImgCount = $expectedPaths.Count
    FrameCount = $expectedFrameCount
    Summary = $summaryPath
    Deployed = $false
} | Format-List

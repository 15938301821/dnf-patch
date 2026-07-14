[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)]
    [string]$FinalSummaryPath,

    [Parameter(Mandatory = $true)]
    [string]$ManualReviewPath,

    [Parameter(Mandatory = $true)]
    [string]$ProfessionManifestPath,

    [Parameter(Mandatory = $true)]
    [string]$ReleaseReportPath,

    [Parameter(Mandatory = $true)]
    [string]$TransactionReceiptPath,

    [Parameter(Mandatory = $true)]
    [string]$ReleaseId,

    [int]$ManualReviewMaxAgeHours = 168,

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
        [string]$Label,
        [switch]$LengthOptional
    )

    Assert-Condition ($null -ne $Snapshot) "$Label snapshot is missing."
    foreach ($name in @('path', 'sha256')) {
        Assert-Condition (Test-Property -Object $Snapshot -Name $name) `
            "$Label snapshot is missing '$name'."
    }
    $path = Resolve-ExistingFile -Value ([string]$Snapshot.path) -BaseDirectory $BaseDirectory `
        -RepositoryRoot $RepositoryRoot -Label $Label
    $current = Get-Snapshot -Path $path
    $expectedHash = ([string]$Snapshot.sha256).Trim().ToUpperInvariant()
    Assert-Condition ($expectedHash -match '^[0-9A-F]{64}$') "$Label SHA-256 is invalid."
    Assert-Condition ($current.sha256 -eq $expectedHash) `
        "$Label SHA-256 changed: actual=$($current.sha256) expected=$expectedHash"
    if (-not $LengthOptional) {
        Assert-Condition (Test-Property -Object $Snapshot -Name 'length') `
            "$Label snapshot is missing 'length'."
        Assert-Condition ($current.length -eq [long]$Snapshot.length) `
            "$Label length changed: actual=$($current.length) expected=$($Snapshot.length)"
    }
    return $current
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

function Get-RelativePath {
    param([string]$Path, [string]$BaseDirectory)

    $basePath = [IO.Path]::GetFullPath($BaseDirectory).TrimEnd(
        [IO.Path]::DirectorySeparatorChar,
        [IO.Path]::AltDirectorySeparatorChar) + [IO.Path]::DirectorySeparatorChar
    $baseUri = New-Object Uri($basePath)
    $pathUri = New-Object Uri([IO.Path]::GetFullPath($Path))
    return [Uri]::UnescapeDataString($baseUri.MakeRelativeUri($pathUri).ToString())
}

function New-RelativeSnapshot {
    param([object]$Snapshot, [string]$BaseDirectory)

    return [ordered]@{
        path = Get-RelativePath -Path $Snapshot.path -BaseDirectory $BaseDirectory
        length = [long]$Snapshot.length
        sha256 = [string]$Snapshot.sha256
    }
}

function Get-ToolSnapshot {
    param([object[]]$Tools, [string]$Label, [string]$SummaryDirectory, [string]$RepositoryRoot)

    $matches = @($Tools | Where-Object { [string]$_.label -eq $Label })
    Assert-Condition ($matches.Count -eq 1) `
        "Final summary must contain exactly one tool '$Label'; found $($matches.Count)."
    return Assert-Snapshot -Snapshot $matches[0] -BaseDirectory $SummaryDirectory `
        -RepositoryRoot $RepositoryRoot -Label "Final-summary tool $Label"
}

function Write-JsonTemporary {
    param([object]$Value, [string]$Path)

    $Value | ConvertTo-Json -Depth 50 | Set-Content -LiteralPath $Path -Encoding UTF8
    $null = Get-Content -LiteralPath $Path -Raw -Encoding UTF8 | ConvertFrom-Json
}

function Write-JsonAtomic {
    param([object]$Value, [string]$Path)

    $directory = Split-Path -Parent $Path
    if (-not (Test-Path -LiteralPath $directory -PathType Container)) {
        New-Item -ItemType Directory -Path $directory -Force | Out-Null
    }
    $temporary = Join-Path $directory (
        '.' + [IO.Path]::GetFileName($Path) + '.' +
        [Guid]::NewGuid().ToString('N') + '.tmp')
    $backup = Join-Path $directory (
        '.' + [IO.Path]::GetFileName($Path) + '.' +
        [Guid]::NewGuid().ToString('N') + '.bak')
    try {
        Write-JsonTemporary -Value $Value -Path $temporary
        if (Test-Path -LiteralPath $Path -PathType Leaf) {
            [IO.File]::Replace($temporary, $Path, $backup)
        }
        else {
            [IO.File]::Move($temporary, $Path)
        }
    }
    finally {
        foreach ($cleanupPath in @($temporary, $backup)) {
            if (Test-Path -LiteralPath $cleanupPath) {
                Remove-Item -LiteralPath $cleanupPath -Force
            }
        }
    }
}

function Get-TextSha256 {
    param([string]$Text)

    $sha = [Security.Cryptography.SHA256]::Create()
    try {
        $bytes = [Text.Encoding]::UTF8.GetBytes($Text)
        return [BitConverter]::ToString($sha.ComputeHash($bytes)).Replace('-', '')
    }
    finally {
        $sha.Dispose()
    }
}

function Get-TransactionPaths {
    param([string]$ReceiptPath, [string]$ManifestPath)

    $receiptDirectory = Split-Path -Parent $ReceiptPath
    $manifestDirectory = Split-Path -Parent $ManifestPath
    $token = (Get-TextSha256 -Text $ReceiptPath.ToUpperInvariant()).Substring(0, 24)
    return [pscustomobject]@{
        releaseStage = Join-Path $receiptDirectory ".release-$token.stage.json"
        manifestStage = Join-Path $manifestDirectory ".manifest-$token.stage.json"
        manifestBackup = Join-Path $manifestDirectory ".manifest-$token.backup.json"
        rollbackDiscard = Join-Path $manifestDirectory ".manifest-$token.rollback.json"
    }
}

function Enter-ReleaseMutex {
    param([string]$ManifestPath)

    $nameHash = Get-TextSha256 -Text $ManifestPath.ToUpperInvariant()
    $mutex = New-Object Threading.Mutex($false, "Local\DnfPatchRelease-$nameHash")
    $acquired = $false
    try {
        $acquired = $mutex.WaitOne(0)
    }
    catch [Threading.AbandonedMutexException] {
        $acquired = $true
    }
    if (-not $acquired) {
        $mutex.Dispose()
        throw "Another release transaction is active for manifest: $ManifestPath"
    }
    return $mutex
}

function Exit-ReleaseMutex {
    param([Threading.Mutex]$Mutex)

    if ($null -ne $Mutex) {
        $Mutex.ReleaseMutex()
        $Mutex.Dispose()
    }
}

function Assert-SameFileSnapshot {
    param([object]$Left, [object]$Right, [string]$Label)

    Assert-Condition ($Left.path -ieq $Right.path) `
        "$Label path differs: left=$($Left.path) right=$($Right.path)"
    Assert-Condition ([long]$Left.length -eq [long]$Right.length) `
        "$Label length differs: left=$($Left.length) right=$($Right.length)"
    Assert-Condition ([string]$Left.sha256 -eq [string]$Right.sha256) `
        "$Label SHA-256 differs: left=$($Left.sha256) right=$($Right.sha256)"
}

function Assert-CurrentFileSnapshot {
    param([object]$Snapshot, [string]$RepositoryRoot, [string]$Label)

    $current = Assert-Snapshot -Snapshot $Snapshot -BaseDirectory $RepositoryRoot `
        -RepositoryRoot $RepositoryRoot -Label $Label
    return $current
}

function Assert-TransactionDeployment {
    param([object]$Deployment, [string]$Label)

    Assert-NoDeployment -Deployment $Deployment -Label $Label
}

function Assert-ReceiptSnapshotPath {
    param(
        [object]$Snapshot,
        [string]$ExpectedPath,
        [string]$RepositoryRoot,
        [string]$Label
    )

    Assert-Condition ($null -ne $Snapshot -and
        (Test-Property -Object $Snapshot -Name 'path')) `
        "$Label snapshot is missing its path."
    $resolvedPath = Resolve-PathValue -Value ([string]$Snapshot.path) `
        -BaseDirectory $RepositoryRoot -Label $Label
    Assert-Condition ($resolvedPath -ieq $ExpectedPath) `
        "$Label path differs: actual=$resolvedPath expected=$ExpectedPath"
}

function Test-FileMatchesSnapshot {
    param([string]$Path, [object]$Snapshot)

    if (-not (Test-Path -LiteralPath $Path -PathType Leaf) -or
        $null -eq $Snapshot -or
        -not (Test-Property -Object $Snapshot -Name 'length') -or
        -not (Test-Property -Object $Snapshot -Name 'sha256')) {
        return $false
    }
    $item = Get-Item -LiteralPath $Path
    if ([long]$item.Length -ne [long]$Snapshot.length) {
        return $false
    }
    return (Get-FileHash -LiteralPath $Path -Algorithm SHA256).Hash -eq
        ([string]$Snapshot.sha256).ToUpperInvariant()
}

function Remove-TransactionArtifacts {
    param([object]$TransactionPaths, [switch]$KeepManifestBackup)

    foreach ($path in @(
        $TransactionPaths.releaseStage,
        $TransactionPaths.manifestStage,
        $TransactionPaths.rollbackDiscard)) {
        if (Test-Path -LiteralPath $path) {
            Remove-Item -LiteralPath $path -Force
        }
    }
    if (-not $KeepManifestBackup -and
        (Test-Path -LiteralPath $TransactionPaths.manifestBackup)) {
        Remove-Item -LiteralPath $TransactionPaths.manifestBackup -Force
    }
}

function Complete-ReleaseTransaction {
    param(
        [object]$Receipt,
        [object]$ReceiptSnapshot,
        [string]$ReceiptPath,
        [object]$TransactionPaths,
        [string]$ManifestPath,
        [string]$ReleasePath,
        [string]$RepositoryRoot
    )

    $manifestBefore = $Receipt.inputs.manifestBefore
    $manifestAfter = $Receipt.outputs.professionManifest
    $releaseAfter = $Receipt.outputs.releaseReport
    Assert-ReceiptSnapshotPath -Snapshot $manifestBefore -ExpectedPath $ManifestPath `
        -RepositoryRoot $RepositoryRoot -Label 'Transaction manifest-before'
    Assert-ReceiptSnapshotPath -Snapshot $manifestAfter -ExpectedPath $ManifestPath `
        -RepositoryRoot $RepositoryRoot -Label 'Transaction manifest-after'
    Assert-ReceiptSnapshotPath -Snapshot $releaseAfter -ExpectedPath $ReleasePath `
        -RepositoryRoot $RepositoryRoot -Label 'Transaction release report'

    $mutex = Enter-ReleaseMutex -ManifestPath $ManifestPath
    $rollbackEligible = $false
    $manifestCommitted = $false
    $releaseCommitted = $false
    $preserveManifestBackup = $false
    try {
        Assert-NoReparsePointPath -Path $ReceiptPath `
            -RepositoryRoot $RepositoryRoot -Label 'Transaction receipt'
        Assert-NoReparsePointPath -Path $ManifestPath `
            -RepositoryRoot $RepositoryRoot -Label 'Transaction manifest'
        Assert-NoReparsePointPath -Path $ReleasePath `
            -RepositoryRoot $RepositoryRoot -Label 'Transaction release report'
        $currentReceiptSnapshot = Get-Snapshot -Path $ReceiptPath
        Assert-SameFileSnapshot -Left $ReceiptSnapshot `
            -Right $currentReceiptSnapshot -Label 'Transaction receipt before commit'
        $null = Assert-CurrentFileSnapshot -Snapshot $Receipt.inputs.finalSummary `
            -RepositoryRoot $RepositoryRoot `
            -Label 'Transaction final summary before commit'
        $null = Assert-CurrentFileSnapshot -Snapshot $Receipt.inputs.manualReview `
            -RepositoryRoot $RepositoryRoot `
            -Label 'Transaction manual review before commit'

        $releaseMatches = Test-FileMatchesSnapshot -Path $ReleasePath `
            -Snapshot $releaseAfter
        $releaseCanCommit = -not (Test-Path -LiteralPath $ReleasePath) -and
            (Test-FileMatchesSnapshot -Path $TransactionPaths.releaseStage `
                -Snapshot $releaseAfter)
        Assert-Condition ($releaseMatches -or $releaseCanCommit) `
            'Release transaction cannot reconcile the release target or stage.'

        $manifestMatchesAfter = Test-FileMatchesSnapshot -Path $ManifestPath `
            -Snapshot $manifestAfter
        $manifestMatchesBefore = Test-FileMatchesSnapshot -Path $ManifestPath `
            -Snapshot $manifestBefore
        $manifestStageMatches = Test-FileMatchesSnapshot `
            -Path $TransactionPaths.manifestStage -Snapshot $manifestAfter
        if ($manifestMatchesAfter) {
            Assert-Condition (Test-Path -LiteralPath `
                $TransactionPaths.manifestBackup -PathType Leaf) `
                'Committed manifest has no transaction backup for rollback.'
        }
        else {
            Assert-Condition ($manifestMatchesBefore -and $manifestStageMatches) `
                'Release transaction manifest changed or its stage is unavailable.'
        }
        $rollbackEligible = $true

        if (-not $releaseMatches) {
            [IO.File]::Move($TransactionPaths.releaseStage, $ReleasePath)
        }
        $releaseCommitted = $true
        if (-not $manifestMatchesAfter) {
            [IO.File]::Replace($TransactionPaths.manifestStage, $ManifestPath,
                $TransactionPaths.manifestBackup)
        }
        $manifestCommitted = $true

        $closure = Invoke-ReleaseClosureGate -ManifestPath $ManifestPath `
            -ReleasePath $ReleasePath -RepositoryRoot $RepositoryRoot
        $Receipt.status = 'committed'
        $Receipt.committedAtUtc = [DateTime]::UtcNow.ToString('o')
        $Receipt.closure = [pscustomobject]@{
            status = [string]$closure.status
            manualReviewValidation = [string]$closure.manualReviewValidation
            resourcePlanValidation = [string]$closure.resourcePlanValidation
            independentIndex = [string]$closure.independentIndex
        }
        Write-JsonAtomic -Value $Receipt -Path $ReceiptPath
        Remove-TransactionArtifacts -TransactionPaths $TransactionPaths
        return $closure
    }
    catch {
        $failure = $_
        if (-not $rollbackEligible) {
            throw $failure
        }
        $rollbackErrors = New-Object 'Collections.Generic.List[string]'
        if ($manifestCommitted -or
            (Test-FileMatchesSnapshot -Path $ManifestPath -Snapshot $manifestAfter)) {
            if (Test-Path -LiteralPath $TransactionPaths.manifestBackup -PathType Leaf) {
                try {
                    [IO.File]::Replace($TransactionPaths.manifestBackup, $ManifestPath,
                        $TransactionPaths.rollbackDiscard)
                    $manifestCommitted = $false
                }
                catch {
                    $preserveManifestBackup = Test-Path -LiteralPath `
                        $TransactionPaths.manifestBackup -PathType Leaf
                    $rollbackErrors.Add("Manifest rollback failed: $($_.Exception.Message)")
                }
            }
            else {
                $rollbackErrors.Add('Manifest rollback backup is missing.')
            }
        }
        if ($releaseCommitted -or
            (Test-FileMatchesSnapshot -Path $ReleasePath -Snapshot $releaseAfter)) {
            try {
                if (Test-Path -LiteralPath $ReleasePath -PathType Leaf) {
                    Remove-Item -LiteralPath $ReleasePath -Force
                }
                $releaseCommitted = $false
            }
            catch {
                $rollbackErrors.Add("Release cleanup failed: $($_.Exception.Message)")
            }
        }
        Remove-TransactionArtifacts -TransactionPaths $TransactionPaths `
            -KeepManifestBackup:$preserveManifestBackup
        if ($rollbackErrors.Count -eq 0) {
            if (Test-Path -LiteralPath $ReceiptPath -PathType Leaf) {
                Remove-Item -LiteralPath $ReceiptPath -Force
            }
            throw $failure
        }
        $backupMessage = if ($preserveManifestBackup) {
            " Manifest backup preserved at: $($TransactionPaths.manifestBackup)"
        }
        else {
            ''
        }
        throw "Release metadata closure failed: $($failure.Exception.Message) " +
            "Rollback incomplete: $($rollbackErrors.ToArray() -join '; ').$backupMessage"
    }
    finally {
        Exit-ReleaseMutex -Mutex $mutex
    }
}

function Assert-ReleaseTransactionReceipt {
    param(
        [object]$Receipt,
        [string]$ReleaseId,
        [int]$ManualReviewMaxAgeHours,
        [string]$SummaryPath,
        [string]$ReviewPath,
        [string]$ManifestPath,
        [string]$ReleasePath,
        [string]$ReceiptPath,
        [string]$RepositoryRoot
    )

    $receiptSchemaVersion = 0
    if (Test-Property -Object $Receipt -Name 'schemaVersion') {
        $receiptSchemaVersion = [int]$Receipt.schemaVersion
    }
    Assert-Condition ($receiptSchemaVersion -eq 1) `
        'Transaction receipt schemaVersion is invalid.'
    Assert-Condition ([string]$Receipt.status -in @('pending', 'committed')) `
        "Transaction receipt status is invalid: $($Receipt.status)"
    Assert-Condition ([string]$Receipt.releaseId -ceq $ReleaseId) `
        'Transaction receipt releaseId differs.'
    Assert-Condition ([int]$Receipt.manualReviewMaxAgeHours -eq
        $ManualReviewMaxAgeHours) `
        'Transaction receipt manual-review age differs.'
    Assert-TransactionDeployment -Deployment $Receipt.deployment `
        -Label 'Transaction receipt'
    foreach ($record in @(
        [pscustomobject]@{
            value = [string]$Receipt.paths.professionManifest
            expected = $ManifestPath
            label = 'Transaction profession manifest'
        },
        [pscustomobject]@{
            value = [string]$Receipt.paths.releaseReport
            expected = $ReleasePath
            label = 'Transaction release report'
        },
        [pscustomobject]@{
            value = [string]$Receipt.paths.receipt
            expected = $ReceiptPath
            label = 'Transaction receipt'
        })) {
        $resolved = Resolve-PathValue -Value $record.value `
            -BaseDirectory $RepositoryRoot -Label $record.label
        Assert-Condition ($resolved -ieq $record.expected) `
            "$($record.label) path differs: actual=$resolved expected=$($record.expected)"
    }
    $currentSummary = Assert-CurrentFileSnapshot `
        -Snapshot $Receipt.inputs.finalSummary -RepositoryRoot $RepositoryRoot `
        -Label 'Transaction final summary'
    $currentReview = Assert-CurrentFileSnapshot `
        -Snapshot $Receipt.inputs.manualReview -RepositoryRoot $RepositoryRoot `
        -Label 'Transaction manual review'
    Assert-Condition ($currentSummary.path -ieq $SummaryPath) `
        'Transaction final-summary path differs.'
    Assert-Condition ($currentReview.path -ieq $ReviewPath) `
        'Transaction manual-review path differs.'
    Assert-ReceiptSnapshotPath -Snapshot $Receipt.inputs.manifestBefore `
        -ExpectedPath $ManifestPath -RepositoryRoot $RepositoryRoot `
        -Label 'Transaction manifest-before'
    Assert-ReceiptSnapshotPath -Snapshot $Receipt.outputs.professionManifest `
        -ExpectedPath $ManifestPath -RepositoryRoot $RepositoryRoot `
        -Label 'Transaction manifest-after'
    Assert-ReceiptSnapshotPath -Snapshot $Receipt.outputs.releaseReport `
        -ExpectedPath $ReleasePath -RepositoryRoot $RepositoryRoot `
        -Label 'Transaction release report'
}

function Write-ReleaseMetadataResult {
    param([object]$Result, [switch]$AsJson)

    if ($AsJson) {
        $Result | ConvertTo-Json -Depth 10
    }
    else {
        $Result
    }
}

function Invoke-ReleaseClosureGate {
    param(
        [string]$ManifestPath,
        [string]$ReleasePath,
        [string]$RepositoryRoot
    )

    $closureValidator = Join-Path $RepositoryRoot 'tools\Test-DnfReleaseClosure.ps1'
    $closureText = (& $closureValidator -ProfessionManifestPath $ManifestPath `
        -ReleaseReportPath $ReleasePath -RepoRoot $RepositoryRoot -AsJson |
        Out-String).Trim()
    Assert-Condition (-not [string]::IsNullOrWhiteSpace($closureText)) `
        'Release-closure validator returned no JSON.'
    $closure = $closureText | ConvertFrom-Json
    Assert-Condition ([string]$closure.status -eq 'passed' -and
        $closure.fullSkillCoverageProvenAtValidationStart -eq $false -and
        $closure.fullSkillCoverageProvenAfterMetadataClosure -eq $true -and
        $closure.targetClientCompatibilityProven -eq $false) `
        'Release metadata did not pass closure.'
    return $closure
}

function New-ReleaseMetadataResult {
    param(
        [string]$ReleaseId,
        [string]$ManifestPath,
        [string]$ReleasePath,
        [string]$SummaryPath,
        [string]$ReviewPath,
        [string]$ReceiptPath
    )

    return [pscustomobject]@{
        schemaVersion = 1
        status = 'passed'
        state = 'offline-release-closed-client-pending'
        releaseId = $ReleaseId
        professionManifest = Get-Snapshot -Path $ManifestPath
        releaseReport = Get-Snapshot -Path $ReleasePath
        finalSummary = Get-Snapshot -Path $SummaryPath
        manualReview = Get-Snapshot -Path $ReviewPath
        transaction = [pscustomobject]@{
            status = 'committed'
            receipt = Get-Snapshot -Path $ReceiptPath
        }
        releaseClosure = 'passed'
        fullSkillCoverageProvenAtValidationStart = $false
        fullSkillCoverageProvenAfterMetadataClosure = $true
        targetClientCompatibilityProven = $false
        deployment = [pscustomobject]@{
            authorized = $false
            performed = $false
            imagePacks2Write = $false
            processOperation = $false
        }
    }
}

Assert-Condition ($ReleaseId -match '^[a-z0-9]+(?:[.-][a-z0-9]+)*$') `
    'ReleaseId must use lowercase letters, digits, dots, and hyphens.'
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
$manifestPath = Resolve-ExistingFile -Value $ProfessionManifestPath -BaseDirectory $repositoryRoot `
    -RepositoryRoot $repositoryRoot -Label 'Profession manifest'
$releasePath = Resolve-PathValue -Value $ReleaseReportPath -BaseDirectory $repositoryRoot `
    -Label 'Release report'
$receiptPath = Resolve-PathValue -Value $TransactionReceiptPath `
    -BaseDirectory $repositoryRoot -Label 'Transaction receipt'
Assert-InsideRepository -Path $releasePath -RepositoryRoot $repositoryRoot -Label 'Release report'
Assert-NoReparsePointPath -Path $releasePath -RepositoryRoot $repositoryRoot `
    -Label 'Release report'
Assert-InsideRepository -Path $receiptPath -RepositoryRoot $repositoryRoot `
    -Label 'Transaction receipt'
Assert-NoReparsePointPath -Path $receiptPath -RepositoryRoot $repositoryRoot `
    -Label 'Transaction receipt'
Assert-Condition ([IO.Path]::GetExtension($releasePath) -ieq '.json') `
    'Release report must use the .json extension.'
Assert-Condition ([IO.Path]::GetExtension($receiptPath) -ieq '.json') `
    'Transaction receipt must use the .json extension.'

$summaryDirectory = Split-Path -Parent $summaryPath
$manifestDirectory = Split-Path -Parent $manifestPath
$releaseDirectory = Split-Path -Parent $releasePath
$receiptDirectory = Split-Path -Parent $receiptPath
$transactionPaths = Get-TransactionPaths -ReceiptPath $receiptPath `
    -ManifestPath $manifestPath
$summarySnapshotAtStart = Get-Snapshot -Path $summaryPath
$reviewSnapshotAtStart = Get-Snapshot -Path $reviewPath

if (Test-Path -LiteralPath $receiptPath -PathType Leaf) {
    $receipt = Get-Content -LiteralPath $receiptPath -Raw -Encoding UTF8 |
        ConvertFrom-Json
    Assert-ReleaseTransactionReceipt -Receipt $receipt -ReleaseId $ReleaseId `
        -ManualReviewMaxAgeHours $ManualReviewMaxAgeHours `
        -SummaryPath $summaryPath -ReviewPath $reviewPath `
        -ManifestPath $manifestPath -ReleasePath $releasePath `
        -ReceiptPath $receiptPath -RepositoryRoot $repositoryRoot
    if ([string]$receipt.status -eq 'committed') {
        $null = Assert-CurrentFileSnapshot `
            -Snapshot $receipt.outputs.professionManifest `
            -RepositoryRoot $repositoryRoot -Label 'Committed transaction manifest'
        $null = Assert-CurrentFileSnapshot -Snapshot $receipt.outputs.releaseReport `
            -RepositoryRoot $repositoryRoot -Label 'Committed transaction release'
        $null = Invoke-ReleaseClosureGate -ManifestPath $manifestPath `
            -ReleasePath $releasePath -RepositoryRoot $repositoryRoot
        Remove-TransactionArtifacts -TransactionPaths $transactionPaths
        $existingResult = New-ReleaseMetadataResult -ReleaseId $ReleaseId `
            -ManifestPath $manifestPath -ReleasePath $releasePath `
            -SummaryPath $summaryPath -ReviewPath $reviewPath `
            -ReceiptPath $receiptPath
        Write-ReleaseMetadataResult -Result $existingResult -AsJson:$AsJson
        return
    }

    $manualValidator = Join-Path $repositoryRoot `
        'tools\Test-DnfFinalManualReview.ps1'
    $manualText = (& $manualValidator -FinalSummaryPath $summaryPath `
        -ManualReviewPath $reviewPath -MaxAgeHours $ManualReviewMaxAgeHours `
        -RepoRoot $repositoryRoot -AsJson | Out-String).Trim()
    Assert-Condition (-not [string]::IsNullOrWhiteSpace($manualText)) `
        'Manual-review validator returned no JSON during transaction recovery.'
    $manualResult = $manualText | ConvertFrom-Json
    Assert-Condition ([string]$manualResult.status -eq 'passed' -and
        $manualResult.approved -eq $true -and
        $manualResult.reviewedAllContactSheets -eq $true -and
        [int]$manualResult.findingCount -eq 0) `
        'Manual-review validation did not pass during transaction recovery.'
    Assert-NoDeployment -Deployment $manualResult.deployment `
        -Label 'Recovered manual-review validation'
    $reviewSnapshotAfterRecoveryValidation = Get-Snapshot -Path $reviewPath
    Assert-SameFileSnapshot -Left $reviewSnapshotAtStart `
        -Right $reviewSnapshotAfterRecoveryValidation `
        -Label 'Manual review during transaction recovery'
    $receiptSnapshot = Get-Snapshot -Path $receiptPath
    $null = Complete-ReleaseTransaction -Receipt $receipt `
        -ReceiptSnapshot $receiptSnapshot `
        -ReceiptPath $receiptPath -TransactionPaths $transactionPaths `
        -ManifestPath $manifestPath -ReleasePath $releasePath `
        -RepositoryRoot $repositoryRoot
    $recoveredResult = New-ReleaseMetadataResult -ReleaseId $ReleaseId `
        -ManifestPath $manifestPath -ReleasePath $releasePath `
        -SummaryPath $summaryPath -ReviewPath $reviewPath `
        -ReceiptPath $receiptPath
    Write-ReleaseMetadataResult -Result $recoveredResult -AsJson:$AsJson
    return
}

Assert-Condition (-not (Test-Path -LiteralPath $releasePath)) `
    "Refusing to overwrite a release report without a transaction receipt: $releasePath"
foreach ($transactionArtifact in @(
    $transactionPaths.releaseStage,
    $transactionPaths.manifestStage,
    $transactionPaths.manifestBackup,
    $transactionPaths.rollbackDiscard)) {
    Assert-Condition (-not (Test-Path -LiteralPath $transactionArtifact)) `
        "Orphaned release transaction artifact requires investigation: $transactionArtifact"
}
$summary = Get-Content -LiteralPath $summaryPath -Raw -Encoding UTF8 | ConvertFrom-Json
$manifestBeforeSnapshot = Get-Snapshot -Path $manifestPath
$manifest = Get-Content -LiteralPath $manifestPath -Raw -Encoding UTF8 | ConvertFrom-Json
Assert-Condition ([string]$summary.status -eq 'passed') 'Final summary status is not passed.'
Assert-Condition ($summary.fullSkillCoverageProven -eq $false) `
    'Final summary must remain pre-metadata.'
Assert-Condition ($summary.validation.manifestScopeOfflineCoverage.eligibleForReleaseMetadataFullSkillCoverage -eq $true) `
    'Final summary is not eligible for release metadata.'
Assert-Condition ($summary.validation.manifestScopeOfflineCoverage.fullSkillCoverageProvenAtValidationStart -eq $false) `
    'Final summary did not start from coverage=false.'
Assert-Condition ($summary.validation.manifestScopeOfflineCoverage.releaseMetadataGeneratedByThisValidator -eq $false) `
    'Final validator unexpectedly generated release metadata.'
Assert-Condition ($summary.validation.manifestScopeOfflineCoverage.targetClientCompatibilityProven -eq $false) `
    'Final summary claims target-client compatibility.'
Assert-NoDeployment -Deployment $summary.deployment -Label 'Final summary'
Assert-Condition ($manifest.coverage.fullSkillCoverageProven -eq $false) `
    'Profession manifest must remain coverage=false before metadata generation.'
Assert-Condition (-not (Test-Property -Object $manifest -Name 'fullSkillRelease')) `
    'Profession manifest already contains fullSkillRelease.'

$manualValidator = Join-Path $repositoryRoot 'tools\Test-DnfFinalManualReview.ps1'
$manualText = (& $manualValidator -FinalSummaryPath $summaryPath -ManualReviewPath $reviewPath `
    -MaxAgeHours $ManualReviewMaxAgeHours -RepoRoot $repositoryRoot -AsJson | Out-String).Trim()
Assert-Condition (-not [string]::IsNullOrWhiteSpace($manualText)) `
    'Manual-review validator returned no JSON.'
$manualResult = $manualText | ConvertFrom-Json
Assert-Condition ([string]$manualResult.status -eq 'passed' -and
    $manualResult.approved -eq $true -and
    $manualResult.reviewedAllContactSheets -eq $true -and
    [int]$manualResult.findingCount -eq 0) `
    'Manual-review validation did not pass.'
Assert-NoDeployment -Deployment $manualResult.deployment -Label 'Manual-review validation'

$artifact = Assert-Snapshot -Snapshot $summary.finalArtifact -BaseDirectory $summaryDirectory `
    -RepositoryRoot $repositoryRoot -Label 'Final artifact'
$package = Assert-Snapshot -Snapshot $summary.packageSummary -BaseDirectory $summaryDirectory `
    -RepositoryRoot $repositoryRoot -Label 'Package summary'
$summarySnapshot = Get-Snapshot -Path $summaryPath
$reviewSnapshot = Get-Snapshot -Path $reviewPath
$planRecord = $summary.resourcePlan
$planSnapshotRecord = [pscustomobject]@{
    path = [string]$planRecord.inputPath
    length = [long]$planRecord.length
    sha256 = [string]$planRecord.sha256
}
$planSnapshot = Assert-Snapshot -Snapshot $planSnapshotRecord -BaseDirectory $summaryDirectory `
    -RepositoryRoot $repositoryRoot -Label 'Resource plan input'
$plan = Get-Content -LiteralPath $planSnapshot.path -Raw -Encoding UTF8 | ConvertFrom-Json
Assert-Condition ($plan.coverage.fullSkillCoverageProven -eq $false) `
    'Resource plan must remain coverage=false.'
$technicalRoots = @()
if (Test-Property -Object $plan.coverage -Name 'technicalRoots') {
    $technicalRoots = @($plan.coverage.technicalRoots)
}
else {
    Assert-Condition (Test-Property -Object $summary.resourcePlan -Name 'baselinePlan') `
        'Resource plan has no technical roots and final summary has no baseline-plan snapshot.'
    $baselinePlanSnapshot = Assert-Snapshot -Snapshot $summary.resourcePlan.baselinePlan `
        -BaseDirectory $summaryDirectory -RepositoryRoot $repositoryRoot `
        -Label 'Baseline resource plan'
    $baselinePlan = Get-Content -LiteralPath $baselinePlanSnapshot.path -Raw -Encoding UTF8 |
        ConvertFrom-Json
    $hasBaselineCoverage = Test-Property -Object $baselinePlan -Name 'coverage'
    $hasBaselineTechnicalRoots = $hasBaselineCoverage -and
        (Test-Property -Object $baselinePlan.coverage -Name 'technicalRoots')
    Assert-Condition $hasBaselineTechnicalRoots `
        'Baseline resource plan has no technical-root coverage records.'
    $technicalRoots = @($baselinePlan.coverage.technicalRoots)
}
Assert-Condition ($technicalRoots.Count -gt 0) `
    'Release metadata requires at least one verified technical-root record.'
$planManifestPath = Resolve-PathValue -Value ([string]$plan.professionManifestPath) `
    -BaseDirectory $repositoryRoot -Label 'Resource-plan profession manifest'
Assert-Condition ($planManifestPath -ieq $manifestPath) `
    'Resource plan points to another profession manifest.'
$accounting = Assert-Snapshot -Snapshot $planRecord.postBuildFrameAccounting `
    -BaseDirectory $summaryDirectory -RepositoryRoot $repositoryRoot `
    -Label 'Post-build frame accounting'
$indexRecord = $summary.validation.independentIndex
$indexSnapshotRecord = [pscustomobject]@{
    path = [string]$indexRecord.report
    length = [long]$indexRecord.reportLength
    sha256 = [string]$indexRecord.reportSha256
}
$indexSnapshot = Assert-Snapshot -Snapshot $indexSnapshotRecord -BaseDirectory $summaryDirectory `
    -RepositoryRoot $repositoryRoot -Label 'Independent index'
$albumSnapshot = Assert-Snapshot -Snapshot $summary.validation.fullFrame.albumInventory `
    -BaseDirectory $summaryDirectory -RepositoryRoot $repositoryRoot -Label 'Album inventory'
$frameSnapshot = Assert-Snapshot -Snapshot $summary.validation.fullFrame.frameInventory `
    -BaseDirectory $summaryDirectory -RepositoryRoot $repositoryRoot -Label 'Frame inventory'

$tools = @($summary.provenance.tools)
$packagerTool = Get-ToolSnapshot -Tools $tools -Label 'custom-npk-packager' `
    -SummaryDirectory $summaryDirectory -RepositoryRoot $repositoryRoot
$planValidatorTool = Get-ToolSnapshot -Tools $tools -Label 'resource-plan-validator' `
    -SummaryDirectory $summaryDirectory -RepositoryRoot $repositoryRoot
$finalValidatorTool = Get-ToolSnapshot -Tools $tools -Label 'final-release-validator' `
    -SummaryDirectory $summaryDirectory -RepositoryRoot $repositoryRoot
$indexTool = Get-ToolSnapshot -Tools $tools -Label 'independent-index' `
    -SummaryDirectory $summaryDirectory -RepositoryRoot $repositoryRoot
$fullFrameTool = Get-ToolSnapshot -Tools $tools -Label 'full-frame-export' `
    -SummaryDirectory $summaryDirectory -RepositoryRoot $repositoryRoot
$toolchain = [ordered]@{
    packagerSha256 = $packagerTool.sha256
    resourcePlanValidatorSha256 = $planValidatorTool.sha256
    finalReleaseValidatorSha256 = $finalValidatorTool.sha256
    independentIndexValidatorSha256 = $indexTool.sha256
    fullFrameExportSha256 = $fullFrameTool.sha256
}

$generatedAt = [DateTime]::UtcNow.ToString('o')
$deployment = [ordered]@{
    authorized = $false
    performed = $false
    target = $null
    backup = $null
    imagePacks2Write = $false
    processOperation = $false
    status = 'not-authorized-not-performed'
}
$artifactForRelease = New-RelativeSnapshot -Snapshot $artifact -BaseDirectory $releaseDirectory
$artifactForRelease['imgCount'] = [int]$summary.finalArtifact.imgCount
$artifactForRelease['frameCount'] = [int]$summary.finalArtifact.frameCount
$artifactForManifest = New-RelativeSnapshot -Snapshot $artifact -BaseDirectory $manifestDirectory
$artifactForManifest['imgCount'] = [int]$summary.finalArtifact.imgCount
$artifactForManifest['frameCount'] = [int]$summary.finalArtifact.frameCount
$artifactForManifest['deployed'] = $false
$packageForRelease = New-RelativeSnapshot -Snapshot $package -BaseDirectory $releaseDirectory
$packageForRelease['entryCount'] = [int]$summary.packageSummary.entryCount
$packageForRelease['sourceNpkCount'] = [int]$summary.packageSummary.sourceNpkCount
$packageForRelease['payloadEquivalence'] = [string]$summary.packageSummary.payloadEquivalence
$packageForManifest = New-RelativeSnapshot -Snapshot $package -BaseDirectory $manifestDirectory
$packageForManifest['entryCount'] = [int]$summary.packageSummary.entryCount
$packageForManifest['sourceNpkCount'] = [int]$summary.packageSummary.sourceNpkCount
$packageForManifest['payloadEquivalence'] = [string]$summary.packageSummary.payloadEquivalence
$planForRelease = New-RelativeSnapshot -Snapshot $planSnapshot -BaseDirectory $releaseDirectory
$planForRelease['fullSkillCoverageProvenAtValidationStart'] = $false
$planForManifest = New-RelativeSnapshot -Snapshot $planSnapshot -BaseDirectory $manifestDirectory
$planForManifest['fullSkillCoverageProvenAtValidationStart'] = $false
$accountingForRelease = New-RelativeSnapshot -Snapshot $accounting -BaseDirectory $releaseDirectory
$accountingForManifest = New-RelativeSnapshot -Snapshot $accounting -BaseDirectory $manifestDirectory
$summaryForRelease = New-RelativeSnapshot -Snapshot $summarySnapshot -BaseDirectory $releaseDirectory
$summaryForManifest = New-RelativeSnapshot -Snapshot $summarySnapshot -BaseDirectory $manifestDirectory
$indexForRelease = New-RelativeSnapshot -Snapshot $indexSnapshot -BaseDirectory $releaseDirectory
$indexForManifest = New-RelativeSnapshot -Snapshot $indexSnapshot -BaseDirectory $manifestDirectory
$albumForRelease = New-RelativeSnapshot -Snapshot $albumSnapshot -BaseDirectory $releaseDirectory
$framesForRelease = New-RelativeSnapshot -Snapshot $frameSnapshot -BaseDirectory $releaseDirectory
$manualForRelease = New-RelativeSnapshot -Snapshot $reviewSnapshot -BaseDirectory $releaseDirectory
$manualForManifest = New-RelativeSnapshot -Snapshot $reviewSnapshot -BaseDirectory $manifestDirectory

$release = [ordered]@{
    schemaVersion = 1
    releaseId = $ReleaseId
    generatedAtUtc = $generatedAt
    status = 'offline-validated-client-pending'
    mode = 'workspace-only release metadata; no ImagePacks2 write or process operation'
    coverage = [ordered]@{
        fullSkillCoverageProven = $true
        scope = [string]$manifest.coverage.scope
        meaning = 'Current verified manifest scope passed final validation, manual full-contact-sheet review, and metadata closure.'
        technicalRootCount = $technicalRoots.Count
        selectedComponentCount = [int]$summary.resourcePlan.totals.componentCount
        selectedReuseComponentCount = [int]$summary.resourcePlan.totals.activeCutinImgCount
        clientCompatibilityProven = $false
    }
    artifact = $artifactForRelease
    packageSummary = $packageForRelease
    sourceEvidence = [ordered]@{
        officialSourceCount = @($summary.provenance.officialSources).Count
        resourcePlan = $planForRelease
        postBuildFrameAccounting = $accountingForRelease
    }
    validation = [ordered]@{
        status = 'passed'
        finalSummary = $summaryForRelease
        manualReview = $manualForRelease
        manualReviewApproval = [ordered]@{
            reviewedBy = [string]$manualResult.reviewedBy
            approvedAtUtc = [string]$manualResult.approvedAtUtc
            maxAgeHours = $ManualReviewMaxAgeHours
        }
        independentIndex = $indexForRelease
        fullFrame = [ordered]@{
            albumInventory = $albumForRelease
            frameInventory = $framesForRelease
            decodedNonLinkFrames = [int]$summary.validation.fullFrame.decodedNonLinkFrames
            linkFrames = [int]$summary.validation.fullFrame.validatedLinkFrames
            hiddenFrames = [int]$summary.validation.fullFrame.hiddenFrames
            backgrounds = @($summary.validation.fullFrame.backgrounds)
            contactSheetCount = @($summary.validation.fullFrame.contactSheets).Count
            manualReviewStatus = 'passed-all-contact-sheets'
        }
    }
    toolchain = $toolchain
    deployment = $deployment
    rollback = [ordered]@{
        status = 'not-applicable-no-deployment'
        instruction = 'No game directory was changed; keep the official ImagePacks2 files unchanged.'
    }
    pending = @(
        'Target-client A/B verification is pending.',
        'Filename ordering does not prove client override priority.',
        'Offline validation does not prove client compatibility or account safety.'
    )
}

$manifestFullSkillRelease = [ordered]@{
    schemaVersion = 1
    releaseId = $ReleaseId
    generatedAtUtc = $generatedAt
    status = 'offline-validated-client-pending'
    fullSkillCoverageProven = $true
    coverageMeaning = 'Current verified manifest scope passed final validation and release metadata closure; target-client compatibility remains pending.'
    artifact = $artifactForManifest
    packageSummary = $packageForManifest
    sourceEvidence = [ordered]@{
        officialSourceCount = @($summary.provenance.officialSources).Count
        selectedComponentCount = [int]$summary.resourcePlan.totals.componentCount
        selectedReuseComponentCount = [int]$summary.resourcePlan.totals.activeCutinImgCount
        resourcePlan = $planForManifest
        postBuildFrameAccounting = $accountingForManifest
    }
    validation = [ordered]@{
        finalSummary = $summaryForManifest
        manualReview = $manualForManifest
        manualReviewApproval = [ordered]@{
            reviewedBy = [string]$manualResult.reviewedBy
            approvedAtUtc = [string]$manualResult.approvedAtUtc
            maxAgeHours = $ManualReviewMaxAgeHours
        }
        independentIndex = $indexForManifest
        fullFrame = [ordered]@{
            decodedNonLinkFrames = [int]$summary.validation.fullFrame.decodedNonLinkFrames
            linkFrames = [int]$summary.validation.fullFrame.validatedLinkFrames
            hiddenFrames = [int]$summary.validation.fullFrame.hiddenFrames
            albumInventoryPath = Get-RelativePath -Path $albumSnapshot.path -BaseDirectory $manifestDirectory
            albumInventorySha256 = $albumSnapshot.sha256
            frameInventoryPath = Get-RelativePath -Path $frameSnapshot.path -BaseDirectory $manifestDirectory
            frameInventorySha256 = $frameSnapshot.sha256
            backgrounds = @($summary.validation.fullFrame.backgrounds)
            contactSheetCount = @($summary.validation.fullFrame.contactSheets).Count
            manualReviewStatus = 'passed-all-contact-sheets'
        }
    }
    toolchain = $toolchain
    releaseReport = Get-RelativePath -Path $releasePath -BaseDirectory $manifestDirectory
    deployment = $deployment
    pending = @(
        'Target-client A/B verification.',
        'Client load priority verification.',
        'Client compatibility verification.'
    )
}

$manifest.coverage.fullSkillCoverageProven = $true
$manifest.coverage.reason = 'Current manifest scope passed final validation, manual review, metadata generation, and release closure.'
$manifest.coverage.meaning = 'Offline manifest-scope coverage only; target-client compatibility and load priority remain unproven.'
$manifest.coverage.clientCompatibilityProven = $false
$manifest | Add-Member -NotePropertyName fullSkillRelease -NotePropertyValue ([pscustomobject]$manifestFullSkillRelease)
if (Test-Property -Object $manifest -Name 'activityMigration') {
    $manifest.activityMigration.status = 'offline-release-closed-client-pending'
    $manifest.activityMigration.readyForAggregation = $true
    $manifest.activityMigration.fullSkillCoverageProven = $true
    $manifest.activityMigration.blockers = @(
        'target-client-ab-pending',
        'client-load-priority-pending',
        'client-compatibility-pending'
    )
    $manifest.activityMigration | Add-Member -NotePropertyName finalSummary `
        -NotePropertyValue ([pscustomobject]$summaryForManifest) -Force
    $manifest.activityMigration | Add-Member -NotePropertyName manualReview `
        -NotePropertyValue ([pscustomobject]$manualForManifest) -Force
    $manifest.activityMigration | Add-Member -NotePropertyName releaseReport `
        -NotePropertyValue (Get-RelativePath -Path $releasePath -BaseDirectory $manifestDirectory) -Force
}

if (-not (Test-Path -LiteralPath $releaseDirectory -PathType Container)) {
    New-Item -ItemType Directory -Path $releaseDirectory -Force | Out-Null
}
if (-not (Test-Path -LiteralPath $receiptDirectory -PathType Container)) {
    New-Item -ItemType Directory -Path $receiptDirectory -Force | Out-Null
}
Assert-NoReparsePointPath -Path $releasePath -RepositoryRoot $repositoryRoot `
    -Label 'Release report before commit'
Assert-NoReparsePointPath -Path $manifestPath -RepositoryRoot $repositoryRoot `
    -Label 'Profession manifest before commit'
$summaryBeforeCommit = Get-Snapshot -Path $summaryPath
$reviewBeforeCommit = Get-Snapshot -Path $reviewPath
$manifestBeforeCommit = Get-Snapshot -Path $manifestPath
Assert-SameFileSnapshot -Left $summarySnapshotAtStart -Right $summaryBeforeCommit `
    -Label 'Final summary before transaction commit'
Assert-SameFileSnapshot -Left $reviewSnapshot -Right $reviewBeforeCommit `
    -Label 'Manual review before transaction commit'
Assert-SameFileSnapshot -Left $manifestBeforeSnapshot -Right $manifestBeforeCommit `
    -Label 'Profession manifest before transaction commit'
$receiptWritten = $false
try {
    Write-JsonTemporary -Value $release -Path $transactionPaths.releaseStage
    Write-JsonTemporary -Value $manifest -Path $transactionPaths.manifestStage
    $releaseStageSnapshot = Get-Snapshot -Path $transactionPaths.releaseStage
    $manifestStageSnapshot = Get-Snapshot -Path $transactionPaths.manifestStage
    $releaseOutputSnapshot = [pscustomobject]@{
        path = Get-RelativePath -Path $releasePath -BaseDirectory $repositoryRoot
        length = [long]$releaseStageSnapshot.length
        sha256 = [string]$releaseStageSnapshot.sha256
    }
    $manifestOutputSnapshot = [pscustomobject]@{
        path = Get-RelativePath -Path $manifestPath -BaseDirectory $repositoryRoot
        length = [long]$manifestStageSnapshot.length
        sha256 = [string]$manifestStageSnapshot.sha256
    }
    $receipt = [pscustomobject]@{
        schemaVersion = 1
        status = 'pending'
        releaseId = $ReleaseId
        createdAtUtc = $generatedAt
        committedAtUtc = $null
        manualReviewMaxAgeHours = $ManualReviewMaxAgeHours
        paths = [pscustomobject]@{
            professionManifest = Get-RelativePath -Path $manifestPath `
                -BaseDirectory $repositoryRoot
            releaseReport = Get-RelativePath -Path $releasePath `
                -BaseDirectory $repositoryRoot
            receipt = Get-RelativePath -Path $receiptPath `
                -BaseDirectory $repositoryRoot
        }
        inputs = [pscustomobject]@{
            finalSummary = [pscustomobject](New-RelativeSnapshot `
                -Snapshot $summarySnapshotAtStart -BaseDirectory $repositoryRoot)
            manualReview = [pscustomobject](New-RelativeSnapshot `
                -Snapshot $reviewSnapshot -BaseDirectory $repositoryRoot)
            manifestBefore = [pscustomobject](New-RelativeSnapshot `
                -Snapshot $manifestBeforeSnapshot -BaseDirectory $repositoryRoot)
        }
        outputs = [pscustomobject]@{
            professionManifest = $manifestOutputSnapshot
            releaseReport = $releaseOutputSnapshot
        }
        closure = $null
        deployment = [pscustomobject]@{
            authorized = $false
            performed = $false
            imagePacks2Write = $false
            processOperation = $false
        }
    }
    Write-JsonAtomic -Value $receipt -Path $receiptPath
    $receiptWritten = $true
    $receiptSnapshot = Get-Snapshot -Path $receiptPath
    $null = Complete-ReleaseTransaction -Receipt $receipt `
        -ReceiptSnapshot $receiptSnapshot `
        -ReceiptPath $receiptPath -TransactionPaths $transactionPaths `
        -ManifestPath $manifestPath -ReleasePath $releasePath `
        -RepositoryRoot $repositoryRoot
}
catch {
    if (-not $receiptWritten) {
        Remove-TransactionArtifacts -TransactionPaths $transactionPaths
    }
    throw
}

$result = New-ReleaseMetadataResult -ReleaseId $ReleaseId `
    -ManifestPath $manifestPath -ReleasePath $releasePath `
    -SummaryPath $summaryPath -ReviewPath $reviewPath -ReceiptPath $receiptPath
Write-ReleaseMetadataResult -Result $result -AsJson:$AsJson

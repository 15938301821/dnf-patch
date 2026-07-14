[CmdletBinding()]
param(
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

function Write-Text {
    param([string]$Path, [string]$Text)

    $directory = Split-Path -Parent $Path
    if (-not (Test-Path -LiteralPath $directory -PathType Container)) {
        New-Item -ItemType Directory -Path $directory -Force | Out-Null
    }
    [IO.File]::WriteAllText($Path, $Text, (New-Object Text.UTF8Encoding($false)))
}

function Write-Json {
    param([string]$Path, [object]$Value)

    $text = $Value | ConvertTo-Json -Depth 30
    Write-Text -Path $Path -Text $text
}

function New-Snapshot {
    param([string]$Path, [string]$BaseDirectory)

    $item = Get-Item -LiteralPath $Path
    $base = [IO.Path]::GetFullPath($BaseDirectory).TrimEnd(
        [IO.Path]::DirectorySeparatorChar,
        [IO.Path]::AltDirectorySeparatorChar) + [IO.Path]::DirectorySeparatorChar
    $baseUri = New-Object Uri($base)
    $pathUri = New-Object Uri([IO.Path]::GetFullPath($Path))
    return [pscustomobject]@{
        path = [Uri]::UnescapeDataString($baseUri.MakeRelativeUri($pathUri).ToString())
        length = [long]$item.Length
        sha256 = (Get-FileHash -LiteralPath $Path -Algorithm SHA256).Hash
    }
}

$defaultRoot = Split-Path -Parent $PSScriptRoot
$repositoryRoot = if ([string]::IsNullOrWhiteSpace($RepoRoot)) {
    (Resolve-Path -LiteralPath $defaultRoot).Path
}
else {
    (Resolve-Path -LiteralPath $RepoRoot).Path
}
$fixtureRoot = Join-Path ([IO.Path]::GetTempPath()) (
    'dnf-patch-release-fixture-' + [Guid]::NewGuid().ToString('N'))
$toolsDirectory = Join-Path $fixtureRoot 'tools'
$professionDirectory = Join-Path $fixtureRoot 'profession'
$runDirectory = Join-Path $fixtureRoot 'run'
New-Item -ItemType Directory -Path $toolsDirectory, $professionDirectory, $runDirectory `
    -Force | Out-Null

try {
    $manualValidatorPath = Join-Path $toolsDirectory 'Test-DnfFinalManualReview.ps1'
    $closureValidatorPath = Join-Path $toolsDirectory 'Test-DnfReleaseClosure.ps1'
    Write-Text -Path $manualValidatorPath -Text @'
[CmdletBinding()]
param(
    [string]$FinalSummaryPath,
    [string]$ManualReviewPath,
    [int]$MaxAgeHours,
    [string]$RepoRoot,
    [switch]$AsJson
)
$result = [pscustomobject]@{
    status = 'passed'
    approved = $true
    approvedAtUtc = [DateTime]::UtcNow.ToString('o')
    reviewedBy = 'fixture-reviewer'
    reviewedAllContactSheets = $true
    findingCount = 0
    deployment = [pscustomobject]@{
        authorized = $false
        performed = $false
        imagePacks2Write = $false
        processOperation = $false
    }
}
$result | ConvertTo-Json -Depth 5
'@
    Write-Text -Path $closureValidatorPath -Text @'
[CmdletBinding()]
param(
    [string]$ProfessionManifestPath,
    [string]$ReleaseReportPath,
    [string]$RepoRoot,
    [switch]$AsJson
)
if (-not (Test-Path -LiteralPath $ProfessionManifestPath -PathType Leaf) -or
    -not (Test-Path -LiteralPath $ReleaseReportPath -PathType Leaf)) {
    throw 'Fixture did not observe committed metadata.'
}
throw 'fixture-closure-failure'
'@

    $artifactPath = Join-Path $runDirectory 'artifact.NPK'
    $packagePath = Join-Path $runDirectory 'package.json'
    $planPath = Join-Path $runDirectory 'plan.json'
    $accountingPath = Join-Path $runDirectory 'accounting.json'
    $indexPath = Join-Path $runDirectory 'index.json'
    $albumPath = Join-Path $runDirectory 'album.json'
    $framesPath = Join-Path $runDirectory 'frames.csv'
    $sheetPath = Join-Path $runDirectory 'sheet.png'
    $toolPath = Join-Path $runDirectory 'tool.ps1'
    $reviewPath = Join-Path $runDirectory 'manual-review.json'
    foreach ($record in @(
        [pscustomobject]@{ path = $artifactPath; text = 'artifact' },
        [pscustomobject]@{ path = $packagePath; text = '{"status":"passed"}' },
        [pscustomobject]@{ path = $accountingPath; text = '{"status":"passed"}' },
        [pscustomobject]@{ path = $indexPath; text = '{"status":"passed"}' },
        [pscustomobject]@{ path = $albumPath; text = '{"status":"passed"}' },
        [pscustomobject]@{ path = $framesPath; text = 'frame' },
        [pscustomobject]@{ path = $sheetPath; text = 'sheet' },
        [pscustomobject]@{ path = $toolPath; text = 'param()' },
        [pscustomobject]@{ path = $reviewPath; text = '{"approved":true}' })) {
        Write-Text -Path $record.path -Text $record.text
    }

    $manifestPath = Join-Path $professionDirectory 'manifest.json'
    $manifest = [pscustomobject]@{
        schemaVersion = 1
        coverage = [pscustomobject]@{
            scope = 'fixture scope'
            fullSkillCoverageProven = $false
            reason = 'fixture pre-release'
            meaning = 'fixture pre-release'
            clientCompatibilityProven = $false
        }
    }
    Write-Json -Path $manifestPath -Value $manifest
    $manifestBefore = Get-FileHash -LiteralPath $manifestPath -Algorithm SHA256
    $manifestBeforeBytes = [IO.File]::ReadAllBytes($manifestPath)

    $plan = [pscustomobject]@{
        schemaVersion = 1
        professionManifestPath = 'profession/manifest.json'
        coverage = [pscustomobject]@{
            fullSkillCoverageProven = $false
            technicalRoots = @([pscustomobject]@{ id = 'fixture-root' })
        }
    }
    Write-Json -Path $planPath -Value $plan

    $tools = New-Object 'Collections.Generic.List[object]'
    foreach ($label in @(
        'custom-npk-packager',
        'resource-plan-validator',
        'final-release-validator',
        'independent-index',
        'full-frame-export')) {
        $snapshot = New-Snapshot -Path $toolPath -BaseDirectory $runDirectory
        $tools.Add([pscustomobject]@{
            label = $label
            path = $snapshot.path
            length = $snapshot.length
            sha256 = $snapshot.sha256
        })
    }
    $summary = [pscustomobject]@{
        schemaVersion = 1
        status = 'passed'
        fullSkillCoverageProven = $false
        finalArtifact = New-Snapshot -Path $artifactPath -BaseDirectory $runDirectory
        packageSummary = [pscustomobject]@{
            path = (New-Snapshot -Path $packagePath -BaseDirectory $runDirectory).path
            length = (Get-Item -LiteralPath $packagePath).Length
            sha256 = (Get-FileHash -LiteralPath $packagePath -Algorithm SHA256).Hash
            entryCount = 1
            sourceNpkCount = 1
            payloadEquivalence = 'passed'
        }
        resourcePlan = [pscustomobject]@{
            inputPath = (New-Snapshot -Path $planPath -BaseDirectory $runDirectory).path
            length = (Get-Item -LiteralPath $planPath).Length
            sha256 = (Get-FileHash -LiteralPath $planPath -Algorithm SHA256).Hash
            postBuildFrameAccounting = New-Snapshot -Path $accountingPath `
                -BaseDirectory $runDirectory
            totals = [pscustomobject]@{
                componentCount = 1
                activeCutinImgCount = 0
            }
        }
        validation = [pscustomobject]@{
            manifestScopeOfflineCoverage = [pscustomobject]@{
                eligibleForReleaseMetadataFullSkillCoverage = $true
                fullSkillCoverageProvenAtValidationStart = $false
                releaseMetadataGeneratedByThisValidator = $false
                targetClientCompatibilityProven = $false
            }
            independentIndex = [pscustomobject]@{
                report = (New-Snapshot -Path $indexPath -BaseDirectory $runDirectory).path
                reportLength = (Get-Item -LiteralPath $indexPath).Length
                reportSha256 = (Get-FileHash -LiteralPath $indexPath -Algorithm SHA256).Hash
            }
            fullFrame = [pscustomobject]@{
                albumInventory = New-Snapshot -Path $albumPath -BaseDirectory $runDirectory
                frameInventory = New-Snapshot -Path $framesPath -BaseDirectory $runDirectory
                decodedNonLinkFrames = 1
                validatedLinkFrames = 0
                hiddenFrames = 0
                backgrounds = @('black', 'white', 'checkerboard')
                contactSheets = @((New-Snapshot -Path $sheetPath -BaseDirectory $runDirectory))
            }
        }
        provenance = [pscustomobject]@{
            officialSources = @([pscustomobject]@{ label = 'fixture-source' })
            tools = $tools.ToArray()
        }
        deployment = [pscustomobject]@{
            authorized = $false
            performed = $false
            imagePacks2Write = $false
            processOperation = $false
        }
    }
    $summary.finalArtifact | Add-Member -NotePropertyName imgCount -NotePropertyValue 1
    $summary.finalArtifact | Add-Member -NotePropertyName frameCount -NotePropertyValue 1
    $summaryPath = Join-Path $runDirectory 'final-summary.json'
    Write-Json -Path $summaryPath -Value $summary
    $releasePath = Join-Path $runDirectory 'release.json'
    $receiptPath = Join-Path $runDirectory 'release-transaction.json'

    $failureObserved = $false
    $failureMessage = $null
    try {
        & (Join-Path $repositoryRoot 'tools\New-DnfReleaseMetadata.ps1') `
            -FinalSummaryPath $summaryPath -ManualReviewPath $reviewPath `
            -ProfessionManifestPath $manifestPath -ReleaseReportPath $releasePath `
            -TransactionReceiptPath $receiptPath `
            -ReleaseId 'fixture.rollback-v1' -RepoRoot $fixtureRoot -AsJson | Out-Null
    }
    catch {
        $failureMessage = $_.Exception.Message
        $failureObserved = $_.Exception.Message -match 'fixture-closure-failure'
    }
    Assert-Condition $failureObserved `
        "Fixture closure failure was not observed. Actual failure: $failureMessage"
    $manifestAfter = Get-FileHash -LiteralPath $manifestPath -Algorithm SHA256
    Assert-Condition ($manifestAfter.Hash -eq $manifestBefore.Hash) `
        'Manifest bytes were not restored after closure failure.'
    Assert-Condition (-not (Test-Path -LiteralPath $releasePath)) `
        'Release report remained after closure failure.'
    Assert-Condition (-not (Test-Path -LiteralPath $receiptPath)) `
        'Release transaction receipt remained after closure failure.'
    $temporaryFiles = @(Get-ChildItem -LiteralPath $fixtureRoot -Recurse -File -Force |
        Where-Object {
            $_.Name -match '^\..+\.(tmp|bak)$' -or
            $_.Name -match '^\.(release|manifest)-.+\.(stage|backup|rollback)\.json$'
        })
    Assert-Condition ($temporaryFiles.Count -eq 0) `
        'Metadata rollback left temporary or backup files.'

    Write-Text -Path $closureValidatorPath -Text @'
[CmdletBinding()]
param(
    [string]$ProfessionManifestPath,
    [string]$ReleaseReportPath,
    [string]$RepoRoot,
    [switch]$AsJson
)
if (-not (Test-Path -LiteralPath $ProfessionManifestPath -PathType Leaf) -or
    -not (Test-Path -LiteralPath $ReleaseReportPath -PathType Leaf)) {
    throw 'Fixture did not observe committed metadata.'
}
[pscustomobject]@{
    status = 'passed'
    fullSkillCoverageProvenAtValidationStart = $false
    fullSkillCoverageProvenAfterMetadataClosure = $true
    targetClientCompatibilityProven = $false
    manualReviewValidation = 'passed-live-and-snapshot-at-release-time'
    resourcePlanValidation = 'passed-live-and-snapshot'
    independentIndex = 'passed-live-and-snapshot'
} | ConvertTo-Json -Depth 5
'@

    $successText = (& (Join-Path $repositoryRoot 'tools\New-DnfReleaseMetadata.ps1') `
        -FinalSummaryPath $summaryPath -ManualReviewPath $reviewPath `
        -ProfessionManifestPath $manifestPath -ReleaseReportPath $releasePath `
        -TransactionReceiptPath $receiptPath `
        -ReleaseId 'fixture.rollback-v1' -RepoRoot $fixtureRoot -AsJson |
        Out-String).Trim()
    $successResult = $successText | ConvertFrom-Json
    $committedReceipt = Get-Content -LiteralPath $receiptPath -Raw -Encoding UTF8 |
        ConvertFrom-Json
    Assert-Condition ([string]$successResult.status -eq 'passed' -and
        [string]$successResult.transaction.status -eq 'committed' -and
        [string]$committedReceipt.status -eq 'committed') `
        'Successful transaction did not create a committed receipt.'

    $sha = [Security.Cryptography.SHA256]::Create()
    try {
        $receiptTokenBytes = [Text.Encoding]::UTF8.GetBytes(
            $receiptPath.ToUpperInvariant())
        $receiptToken = [BitConverter]::ToString(
            $sha.ComputeHash($receiptTokenBytes)).Replace('-', '').Substring(0, 24)
    }
    finally {
        $sha.Dispose()
    }
    $manifestBackupPath = Join-Path $professionDirectory `
        ".manifest-$receiptToken.backup.json"
    [IO.File]::WriteAllBytes($manifestBackupPath, $manifestBeforeBytes)
    $committedReceipt.status = 'pending'
    $committedReceipt.committedAtUtc = $null
    $committedReceipt.closure = $null
    Write-Json -Path $receiptPath -Value $committedReceipt

    $recoveryText = (& (Join-Path $repositoryRoot 'tools\New-DnfReleaseMetadata.ps1') `
        -FinalSummaryPath $summaryPath -ManualReviewPath $reviewPath `
        -ProfessionManifestPath $manifestPath -ReleaseReportPath $releasePath `
        -TransactionReceiptPath $receiptPath `
        -ReleaseId 'fixture.rollback-v1' -RepoRoot $fixtureRoot -AsJson |
        Out-String).Trim()
    $recoveryResult = $recoveryText | ConvertFrom-Json
    $recoveredReceipt = Get-Content -LiteralPath $receiptPath -Raw -Encoding UTF8 |
        ConvertFrom-Json
    Assert-Condition ([string]$recoveryResult.status -eq 'passed' -and
        [string]$recoveredReceipt.status -eq 'committed' -and
        -not (Test-Path -LiteralPath $manifestBackupPath)) `
        'Pending transaction did not reconcile committed targets.'

    $idempotentText = (& (Join-Path $repositoryRoot 'tools\New-DnfReleaseMetadata.ps1') `
        -FinalSummaryPath $summaryPath -ManualReviewPath $reviewPath `
        -ProfessionManifestPath $manifestPath -ReleaseReportPath $releasePath `
        -TransactionReceiptPath $receiptPath `
        -ReleaseId 'fixture.rollback-v1' -RepoRoot $fixtureRoot -AsJson |
        Out-String).Trim()
    $idempotentResult = $idempotentText | ConvertFrom-Json
    Assert-Condition ([string]$idempotentResult.status -eq 'passed' -and
        [string]$idempotentResult.transaction.status -eq 'committed') `
        'Committed transaction was not idempotent.'

    $result = [pscustomobject]@{
        schemaVersion = 1
        status = 'passed'
        failureObserved = $true
        manifestByteIdentityRestored = $true
        releaseRemoved = $true
        temporaryFileCount = 0
        transactionRecoveryPassed = $true
        committedTransactionIdempotent = $true
        deployment = [pscustomobject]@{
            authorized = $false
            performed = $false
            imagePacks2Write = $false
            processOperation = $false
        }
    }
}
finally {
    if (Test-Path -LiteralPath $fixtureRoot) {
        Remove-Item -LiteralPath $fixtureRoot -Recurse -Force
    }
}

if ($AsJson) {
    $result | ConvertTo-Json -Depth 6
}
else {
    $result
}

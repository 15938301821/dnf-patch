[CmdletBinding()]
param(
    [ValidatePattern('^[A-Za-z0-9][A-Za-z0-9._-]*$')]
    [string]$RunId = 'cutin-weaponmaster-neo-aseprite-v1',

    [string]$ImagePacks2,

    [string]$OutputFile,

    [string]$ExtractorDirectory,

    [string]$EditedPngDirectory,

    [string]$RenderSummaryPath,

    [string]$ValidationDirectory,

    [string]$TexconvPath,

    [string]$TexdiagPath
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
$OutputEncoding = [Console]::OutputEncoding = New-Object System.Text.UTF8Encoding($false)

function Get-BomAwareText {
    param([Parameter(Mandatory = $true)][string]$Path)

    $stream = [IO.File]::Open($Path, [IO.FileMode]::Open, [IO.FileAccess]::Read, [IO.FileShare]::Read)
    $reader = New-Object IO.StreamReader($stream, [Text.Encoding]::UTF8, $true)
    try {
        return $reader.ReadToEnd()
    }
    finally {
        $reader.Dispose()
        $stream.Dispose()
    }
}

function ConvertFrom-KeyValueOutput {
    param([Parameter(Mandatory = $true)][string]$Text)

    $values = @{}
    foreach ($line in [regex]::Split($Text, "\r\n|\n|\r")) {
        if ($line -notmatch '^(?<key>[A-Za-z][A-Za-z0-9]*)=(?<value>.*)$') {
            continue
        }
        $key = [string]$Matches['key']
        if ($values.ContainsKey($key)) {
            throw "Builder output contains a duplicate key: $key"
        }
        $values[$key] = [string]$Matches['value']
    }
    return $values
}

function Assert-BuilderValue {
    param(
        [hashtable]$Values,
        [string]$Name,
        [string]$Expected
    )

    if (-not $Values.ContainsKey($Name) -or [string]$Values[$Name] -ne $Expected) {
        $actual = if ($Values.ContainsKey($Name)) { [string]$Values[$Name] } else { '<missing>' }
        throw "Builder output $Name changed: actual=$actual expected=$Expected"
    }
}

function Get-FutureSnapshot {
    param(
        [Parameter(Mandatory = $true)][string]$StagedPath,
        [Parameter(Mandatory = $true)][string]$PublishedPath
    )

    $item = Get-Item -LiteralPath $StagedPath
    return [pscustomobject]@{
        path = [IO.Path]::GetFullPath($PublishedPath)
        length = [long]$item.Length
        sha256 = (Get-FileHash -LiteralPath $StagedPath -Algorithm SHA256).Hash
    }
}

$themeRoot = Split-Path -Parent $PSScriptRoot
$professionRoot = Split-Path -Parent $themeRoot
$jobsRoot = Split-Path -Parent $professionRoot
$repoRoot = Split-Path -Parent $jobsRoot
Import-Module (Join-Path $repoRoot 'tools\DnfPatch.Toolchain.psm1') -Force
$imagePacksPath = Resolve-DnfImagePacks2 -Path $ImagePacks2 -RepositoryRoot $repoRoot
$ExtractorDirectory = Resolve-DnfExtractorDirectory -Path $ExtractorDirectory -RepositoryRoot $repoRoot
$TexconvPath = Resolve-DnfDirectXTexTool -Name 'texconv.exe' -Path $TexconvPath -RepositoryRoot $repoRoot
$TexdiagPath = Resolve-DnfDirectXTexTool -Name 'texdiag.exe' -Path $TexdiagPath -RepositoryRoot $repoRoot
$sourceCode = Join-Path $PSScriptRoot 'Build-VergilCutinWeaponmasterNeo.cs'
$targetValidator = Join-Path $PSScriptRoot 'Test-VergilCutinWeaponmasterNeo.ps1'
$indexValidator = Join-Path $repoRoot 'tools\Test-DnfNpkIndex.ps1'
$fullFrameValidator = Join-Path $repoRoot 'tools\Export-DnfNpkValidation.ps1'
$buildRoot = Join-Path $repoRoot ('tools\bin\vergil-cutin-weaponmaster-neo-build-' + $RunId)
$builder = Join-Path $buildRoot 'Build-VergilCutinWeaponmasterNeo.exe'
$compiler = 'C:\Windows\Microsoft.NET\Framework\v4.0.30319\csc.exe'
$powerShell32 = Join-Path $env:WINDIR 'SysWOW64\WindowsPowerShell\v1.0\powershell.exe'
if ([string]::IsNullOrWhiteSpace($OutputFile)) {
    $OutputFile = Join-Path $themeRoot (Join-Path 'npk' (Join-Path $RunId 'sprite_character_swordman_effect_cutin.NPK'))
}
if ([string]::IsNullOrWhiteSpace($EditedPngDirectory)) {
    $EditedPngDirectory = Join-Path $themeRoot (Join-Path 'frames\runtime' (Join-Path $RunId 'png'))
}
if ([string]::IsNullOrWhiteSpace($RenderSummaryPath)) {
    $RenderSummaryPath = Join-Path $themeRoot (Join-Path 'validation' (Join-Path $RunId 'render-summary.json'))
}
if ([string]::IsNullOrWhiteSpace($ValidationDirectory)) {
    $ValidationDirectory = Join-Path $themeRoot (Join-Path 'validation' ('build-' + $RunId))
}

$sourceNpk = Join-Path $imagePacksPath 'sprite_character_swordman_effect_cutin.NPK'
$outputPath = [IO.Path]::GetFullPath($OutputFile)
$editedPath = (Resolve-Path -LiteralPath $EditedPngDirectory).Path
$renderSummaryFile = (Resolve-Path -LiteralPath $RenderSummaryPath).Path
$validationRoot = [IO.Path]::GetFullPath($ValidationDirectory)
$themePath = (Resolve-Path -LiteralPath $themeRoot).Path

foreach ($workspacePath in @($outputPath, $editedPath, $renderSummaryFile, $validationRoot)) {
    if (-not $workspacePath.StartsWith($themePath + [IO.Path]::DirectorySeparatorChar, [StringComparison]::OrdinalIgnoreCase)) {
        throw "Cut-in build input and output paths must remain inside the theme workspace: $workspacePath"
    }
}
foreach ($newPath in @($outputPath, $validationRoot)) {
    if (Test-Path -LiteralPath $newPath) {
        throw "Refusing to overwrite an existing versioned build path: $newPath"
    }
}

foreach ($requiredFile in @(
    $sourceCode,
    $targetValidator,
    $indexValidator,
    $fullFrameValidator,
    $compiler,
    $powerShell32,
    $sourceNpk,
    (Join-Path $ExtractorDirectory 'ExtractorSharp.Core.dll'),
    (Join-Path $ExtractorDirectory 'ExtractorSharp.Json.dll'),
    (Join-Path $ExtractorDirectory 'zlib1.dll'),
    $TexconvPath,
    $TexdiagPath,
    $renderSummaryFile
)) {
    if (-not (Test-Path -LiteralPath $requiredFile -PathType Leaf)) {
        throw "Required file was not found: $requiredFile"
    }
}

$renderSummary = Get-Content -LiteralPath $renderSummaryFile -Raw -Encoding UTF8 | ConvertFrom-Json
if ($renderSummary.schemaVersion -ne 1 -or
    $renderSummary.status -ne 'passed' -or
    $renderSummary.runId -ne $RunId -or
    $renderSummary.fullSkillCoverageProven -ne $false -or
    $renderSummary.editor.apiCapability.status -ne 'passed' -or
    [int]$renderSummary.editor.apiCapability.apiVersion -lt 30 -or
    [int]$renderSummary.accounting.expectedFrames -ne 24 -or
    [int]$renderSummary.accounting.layeredProjects -ne 24 -or
    [int]$renderSummary.accounting.runtimePngs -ne 24 -or
    [int]$renderSummary.accounting.missingFrames -ne 0 -or
    [int]$renderSummary.accounting.duplicateFrames -ne 0 -or
    [int]$renderSummary.accounting.geometryDrift -ne 0 -or
    $renderSummary.validation.sourceInputsUnchanged -ne 'passed' -or
    $renderSummary.validation.runtimeGeometry -ne 'passed-1068x600' -or
    $renderSummary.validation.layeredProjectsReopened -ne 'passed' -or
    $renderSummary.validation.layeredProjectRuntimePixelEquality -ne 'passed') {
    throw 'Aseprite render summary does not satisfy the verified Cut-in build contract.'
}

$editedPngs = @(Get-ChildItem -LiteralPath $editedPath -File -Filter 'frame-*.png' | Sort-Object Name)
if ($editedPngs.Count -ne 24) {
    throw "Expected 24 edited PNG files, found $($editedPngs.Count): $editedPath"
}
$renderFrames = @($renderSummary.frames)
if ($renderFrames.Count -ne 24) {
    throw "Expected 24 frame records in the Aseprite render summary, found $($renderFrames.Count)."
}
foreach ($frameIndex in 3..26) {
    $matches = @($renderFrames | Where-Object { [int]$_.frameIndex -eq $frameIndex })
    if ($matches.Count -ne 1) {
        throw "Expected one Aseprite render record for frame $frameIndex, found $($matches.Count)."
    }
    $pngPath = Join-Path $editedPath ('frame-{0:D3}.png' -f $frameIndex)
    $pngSnapshot = Get-DnfFileSnapshot -Path $pngPath
    $recordedPath = [IO.Path]::GetFullPath([string]$matches[0].runtime.path)
    if (-not $recordedPath.Equals($pngPath, [StringComparison]::OrdinalIgnoreCase) -or
        [long]$matches[0].runtime.length -ne $pngSnapshot.length -or
        ([string]$matches[0].runtime.sha256).ToUpperInvariant() -ne $pngSnapshot.sha256 -or
        [int]$matches[0].runtime.width -ne 1068 -or
        [int]$matches[0].runtime.height -ne 600) {
        throw "Runtime PNG differs from the Aseprite render evidence at frame $frameIndex."
    }
}

foreach ($directXTool in @($TexconvPath, $TexdiagPath)) {
    $signature = Get-AuthenticodeSignature -LiteralPath $directXTool
    if ($signature.Status -ne [System.Management.Automation.SignatureStatus]::Valid) {
        throw "DirectXTex signature is not valid: $directXTool ($($signature.Status))"
    }
}

New-Item -ItemType Directory -Path $buildRoot -Force | Out-Null
New-Item -ItemType Directory -Path (Split-Path -Parent $outputPath) -Force | Out-Null
$validationParent = Split-Path -Parent $validationRoot
New-Item -ItemType Directory -Path $validationParent -Force | Out-Null
$stagingValidation = Join-Path $validationParent ('.' + [IO.Path]::GetFileName($validationRoot) + '.staging-' + [Guid]::NewGuid().ToString('N'))
New-Item -ItemType Directory -Path $stagingValidation | Out-Null

foreach ($dependency in @('ExtractorSharp.Core.dll', 'ExtractorSharp.Json.dll', 'zlib1.dll')) {
    Copy-Item -LiteralPath (Join-Path $ExtractorDirectory $dependency) -Destination (Join-Path $buildRoot $dependency) -Force
}

$coreReference = '/reference:' + (Join-Path $buildRoot 'ExtractorSharp.Core.dll')
$jsonReference = '/reference:' + (Join-Path $buildRoot 'ExtractorSharp.Json.dll')
$compilerArguments = @(
    '/nologo',
    '/optimize+',
    '/platform:x86',
    '/target:exe',
    ('/out:' + $builder),
    '/reference:System.Drawing.dll',
    '/reference:System.Security.dll',
    $coreReference,
    $jsonReference,
    $sourceCode
)
& $compiler $compilerArguments
if ($LASTEXITCODE -ne 0) {
    throw "Compilation failed with exit code $LASTEXITCODE."
}

$buildToken = [Guid]::NewGuid().ToString('N')
$temporaryOutput = Join-Path $buildRoot ("candidate-$buildToken.NPK")
$workDirectory = Join-Path $buildRoot ("work-$buildToken")
$buildLog = Join-Path $stagingValidation 'builder-output.txt'
$publishedOutput = $false
$publishedValidation = $false
try {
    & $builder $sourceNpk $temporaryOutput $editedPath $TexconvPath $TexdiagPath $workDirectory |
        Tee-Object -LiteralPath $buildLog
    if ($LASTEXITCODE -ne 0) {
        throw "Patch generation failed with exit code $LASTEXITCODE."
    }
    if (-not (Test-Path -LiteralPath $temporaryOutput -PathType Leaf)) {
        throw 'Builder did not create the temporary NPK.'
    }

    $builderText = Get-BomAwareText -Path $buildLog
    $builderValues = ConvertFrom-KeyValueOutput -Text $builderText
    Assert-BuilderValue -Values $builderValues -Name 'SourceLength' -Expected '137275223'
    Assert-BuilderValue -Values $builderValues -Name 'SourceSha256' `
        -Expected '51C7FF71615DB6982D55BFBFEEA1741F37778CD4B89BE2C8B5833DD329E61224'
    Assert-BuilderValue -Values $builderValues -Name 'TargetImg' `
        -Expected 'sprite/character/swordman/effect/cutin/cutin_weaponmaster_neo.img'
    Assert-BuilderValue -Values $builderValues -Name 'NpkEntries' -Expected '26'
    Assert-BuilderValue -Values $builderValues -Name 'ChangedVisibleTextures' -Expected '24'
    Assert-BuilderValue -Values $builderValues -Name 'PreservedPlaceholderFrames' -Expected '3'
    Assert-BuilderValue -Values $builderValues -Name 'PreservedBc3AlphaBlocks' -Expected '961200'
    Assert-BuilderValue -Values $builderValues -Name 'NonTargetPayloadsByteIdentical' -Expected '25'
    Assert-BuilderValue -Values $builderValues -Name 'SharedPayloadEntriesReused' -Expected '6'
    Assert-BuilderValue -Values $builderValues -Name 'StructureValidation' -Expected 'passed'
    Assert-BuilderValue -Values $builderValues -Name 'TexdiagValidation' -Expected 'passed'
    Assert-BuilderValue -Values $builderValues -Name 'Deployment' -Expected 'not-performed'
    $modifiedImgBytes = 0L
    $changedBc3ColorBlocks = 0L
    if (-not [long]::TryParse([string]$builderValues['ModifiedImgBytes'], [ref]$modifiedImgBytes) -or
        $modifiedImgBytes -le 0) {
        throw "Builder output ModifiedImgBytes is invalid: $($builderValues['ModifiedImgBytes'])"
    }
    if (-not [long]::TryParse([string]$builderValues['ChangedBc3ColorBlocks'], [ref]$changedBc3ColorBlocks) -or
        $changedBc3ColorBlocks -le 0) {
        throw "Builder output ChangedBc3ColorBlocks is invalid: $($builderValues['ChangedBc3ColorBlocks'])"
    }

    $sourceItem = Get-Item -LiteralPath $sourceNpk
    $outputItem = Get-Item -LiteralPath $temporaryOutput
    $sourceHash = (Get-FileHash -LiteralPath $sourceNpk -Algorithm SHA256).Hash
    $outputHash = (Get-FileHash -LiteralPath $temporaryOutput -Algorithm SHA256).Hash
    Assert-BuilderValue -Values $builderValues -Name 'OutputLength' -Expected ([string]$outputItem.Length)
    Assert-BuilderValue -Values $builderValues -Name 'OutputSha256' -Expected $outputHash
    $editedHashes = $editedPngs |
        Select-Object Name,Length,@{n='Sha256';e={(Get-FileHash -LiteralPath $_.FullName -Algorithm SHA256).Hash}}

    $indexPath = Join-Path $stagingValidation 'independent-index.json'
    $indexText = (& $indexValidator -Path $temporaryOutput -ExpectedEntryCount 26 `
        -ExpectedSha256 $outputHash -AsJson | Out-String).Trim()
    if ([string]::IsNullOrWhiteSpace($indexText)) {
        throw 'Independent NPK index validator returned no JSON.'
    }
    $indexResult = $indexText | ConvertFrom-Json
    if ([int]$indexResult.EntryCount -ne 26 -or
        [int]$indexResult.UniquePathCount -ne 26 -or
        $indexResult.HeaderSha256Valid -ne $true -or
        [int]$indexResult.ImgMagicValidCount -ne 26) {
        throw 'Independent NPK index validation did not cover all 26 unique IMG entries.'
    }
    $indexText | Set-Content -LiteralPath $indexPath -Encoding UTF8

    $fullFramePath = Join-Path $stagingValidation 'full-frame-validation'
    $fullFrameOutput = (& $powerShell32 -NoProfile -NonInteractive -ExecutionPolicy Bypass `
        -File $fullFrameValidator -InputFile $temporaryOutput -OutputDirectory $fullFramePath `
        -ExtractorDirectory $ExtractorDirectory -FramesPerPage 256 2>&1 | Out-String)
    $fullFrameExitCode = $LASTEXITCODE
    $fullFrameLog = Join-Path $stagingValidation 'full-frame-validation.log'
    $fullFrameOutput | Set-Content -LiteralPath $fullFrameLog -Encoding UTF8
    if ($fullFrameExitCode -ne 0) {
        throw "32-bit full-frame validation failed with exit code $fullFrameExitCode."
    }
    $albumInventoryPath = Join-Path $fullFramePath 'album-inventory.json'
    $frameInventoryPath = Join-Path $fullFramePath 'frame-inventory.csv'
    $albumInventory = Get-Content -LiteralPath $albumInventoryPath -Raw -Encoding UTF8 | ConvertFrom-Json
    $frameInventory = @(Import-Csv -LiteralPath $frameInventoryPath -Encoding UTF8)
    if ([int]$albumInventory.AlbumCount -ne 26 -or
        [int]$albumInventory.FrameCount -ne 834 -or
        [int]$albumInventory.DecodedNonLinkFrames -ne 834 -or
        [int]$albumInventory.LinkFrames -ne 0 -or
        [int]$albumInventory.HiddenFrames -ne 0 -or
        $frameInventory.Count -ne 834 -or
        (@($albumInventory.Backgrounds) -join ',') -ne 'black,white,checkerboard') {
        throw 'Full-frame validation did not decode the verified 26 IMG / 834 frame Cut-in package.'
    }
    $contactSheets = @(Get-ChildItem -LiteralPath (Join-Path $fullFramePath 'sheets') `
        -File -Filter 'frames-*.png' | Sort-Object Name)
    if ($contactSheets.Count -ne [int]$albumInventory.SheetCount -or $contactSheets.Count -lt 1) {
        throw 'Full-frame contact-sheet evidence is incomplete.'
    }

    $targetDiffPath = Join-Path $stagingValidation 'target-diff.json'
    $targetDiffLog = Join-Path $stagingValidation 'target-diff-validation.log'
    $targetDiffOutput = (& $powerShell32 -NoProfile -NonInteractive -ExecutionPolicy Bypass `
        -File $targetValidator -SourceNpk $sourceNpk -OutputNpk $temporaryOutput `
        -OutputFile $targetDiffPath -ExtractorDirectory $ExtractorDirectory 2>&1 | Out-String)
    $targetDiffExitCode = $LASTEXITCODE
    $targetDiffOutput | Set-Content -LiteralPath $targetDiffLog -Encoding UTF8
    if ($targetDiffExitCode -ne 0) {
        throw "32-bit target-diff validation failed with exit code $targetDiffExitCode."
    }
    $targetDiff = Get-Content -LiteralPath $targetDiffPath -Raw -Encoding UTF8 | ConvertFrom-Json
    if ($targetDiff.status -ne 'passed' -or
        [int]$targetDiff.npk.entryCount -ne 26 -or
        [int]$targetDiff.npk.nonTargetPayloadsByteIdentical -ne 25 -or
        [int]$targetDiff.albums.outputFrameCount -ne 834 -or
        [int]$targetDiff.validation.changedFrameCount -ne 24 -or
        [int]$targetDiff.validation.preservedPlaceholderCount -ne 3 -or
        [int]$targetDiff.validation.metadataDiffCount -ne 0 -or
        [long]$targetDiff.validation.alphaMismatchPixelCount -ne 0 -or
        [int]$targetDiff.validation.bc3AlphaBlockMismatchCount -ne 0 -or
        [int]$targetDiff.validation.targetPixelFailureCount -ne 0) {
        throw 'Target-diff validation did not satisfy the Cut-in source/output contract.'
    }

    $sourceItemAfter = Get-Item -LiteralPath $sourceNpk
    $sourceHashAfter = (Get-FileHash -LiteralPath $sourceNpk -Algorithm SHA256).Hash
    if ($sourceItemAfter.Length -ne $sourceItem.Length -or
        $sourceItemAfter.LastWriteTime.ToString('o') -ne $sourceItem.LastWriteTime.ToString('o') -or
        $sourceHashAfter -ne $sourceHash) {
        throw 'Read-only source NPK changed during the Cut-in build or validation.'
    }

    $publishedFullFramePath = Join-Path $validationRoot 'full-frame-validation'
    $publishedContactSheets = @($contactSheets | ForEach-Object {
        Get-FutureSnapshot -StagedPath $_.FullName `
            -PublishedPath (Join-Path (Join-Path $publishedFullFramePath 'sheets') $_.Name)
    })
    $builderStats = [ordered]@{
        npkEntries = 26
        modifiedImgBytes = $modifiedImgBytes
        changedVisibleTextures = 24
        preservedPlaceholderFrames = 3
        changedBc3ColorBlocks = $changedBc3ColorBlocks
        preservedBc3AlphaBlocks = 961200
        nonTargetPayloadsByteIdentical = 25
        sharedPayloadEntriesReused = 6
        structureValidation = 'passed'
        texdiagValidation = 'passed'
    }
    $builderOutputSnapshot = Get-FutureSnapshot -StagedPath $buildLog `
        -PublishedPath (Join-Path $validationRoot 'builder-output.txt')
    $indexSnapshot = Get-FutureSnapshot -StagedPath $indexPath `
        -PublishedPath (Join-Path $validationRoot 'independent-index.json')
    $albumInventorySnapshot = Get-FutureSnapshot -StagedPath $albumInventoryPath `
        -PublishedPath (Join-Path $publishedFullFramePath 'album-inventory.json')
    $frameInventorySnapshot = Get-FutureSnapshot -StagedPath $frameInventoryPath `
        -PublishedPath (Join-Path $publishedFullFramePath 'frame-inventory.csv')
    $fullFrameLogSnapshot = Get-FutureSnapshot -StagedPath $fullFrameLog `
        -PublishedPath (Join-Path $validationRoot 'full-frame-validation.log')
    $targetDiffSnapshot = Get-FutureSnapshot -StagedPath $targetDiffPath `
        -PublishedPath (Join-Path $validationRoot 'target-diff.json')
    $targetDiffLogSnapshot = Get-FutureSnapshot -StagedPath $targetDiffLog `
        -PublishedPath (Join-Path $validationRoot 'target-diff-validation.log')

    $summary = [ordered]@{
        schemaVersion = 1
        generatedAt = (Get-Date).ToString('o')
        runId = $RunId
        status = 'passed'
        fullSkillCoverageProven = $false
        mode = 'offline build, deployment not authorized'
        renderSummary = Get-DnfFileSnapshot -Path $renderSummaryFile
        sourceNpk = [ordered]@{
            path = $sourceNpk
            length = [long]$sourceItem.Length
            lastWriteTime = $sourceItem.LastWriteTime.ToString('o')
            sha256 = $sourceHash
        }
        editedPngDirectory = $editedPath
        editedPngCount = [int]$editedPngs.Count
        editedPngs = $editedHashes
        outputNpk = [ordered]@{
            path = $outputPath
            length = [long]$outputItem.Length
            sha256 = $outputHash
        }
        targetImg = 'sprite/character/swordman/effect/cutin/cutin_weaponmaster_neo.img'
        changedFrames = @(3..26)
        preservedFrames = @(0..2)
        preservedNonTargetImgPayloads = 25
        builderStats = $builderStats
        builderOutput = $builderOutputSnapshot
        validation = [ordered]@{
            independentIndex = [ordered]@{
                status = 'passed'
                entryCount = 26
                uniquePathCount = 26
                snapshot = $indexSnapshot
                parserDependency = [string]$indexResult.ParserDependency
            }
            fullFrame = [ordered]@{
                status = 'passed'
                albumCount = 26
                frameCount = 834
                decodedNonLinkFrames = 834
                linkFrames = 0
                hiddenFrames = 0
                backgrounds = @('black', 'white', 'checkerboard')
                albumInventory = $albumInventorySnapshot
                frameInventory = $frameInventorySnapshot
                contactSheets = $publishedContactSheets
                log = $fullFrameLogSnapshot
            }
            targetDiff = [ordered]@{
                status = 'passed'
                snapshot = $targetDiffSnapshot
                log = $targetDiffLogSnapshot
                changedFrameCount = 24
                preservedPlaceholderCount = 3
                metadataDiffCount = 0
                nonTargetPayloadHashMismatchCount = 0
                alphaMismatchPixelCount = 0
                bc3AlphaBlockMismatchCount = 0
                targetPixelFailureCount = 0
            }
        }
        toolchain = [ordered]@{
            wrapper = Get-DnfFileSnapshot -Path $PSCommandPath
            builderSource = Get-DnfFileSnapshot -Path $sourceCode
            targetDiffValidator = Get-DnfFileSnapshot -Path $targetValidator
            independentIndexValidator = Get-DnfFileSnapshot -Path $indexValidator
            fullFrameValidator = Get-DnfFileSnapshot -Path $fullFrameValidator
            extractorCore = Get-DnfFileSnapshot -Path (Join-Path $ExtractorDirectory 'ExtractorSharp.Core.dll')
            extractorJson = Get-DnfFileSnapshot -Path (Join-Path $ExtractorDirectory 'ExtractorSharp.Json.dll')
            extractorZlib = Get-DnfFileSnapshot -Path (Join-Path $ExtractorDirectory 'zlib1.dll')
            texconv = Get-DnfFileSnapshot -Path $TexconvPath
            texdiag = Get-DnfFileSnapshot -Path $TexdiagPath
        }
        fullSequenceVisualReview = [string]$renderSummary.validation.fullSequenceVisualReview
        deployment = 'not-authorized-not-performed'
    }
    $stagingSummaryPath = Join-Path $stagingValidation 'build-summary.json'
    $summary | ConvertTo-Json -Depth 15 | Set-Content -LiteralPath $stagingSummaryPath -Encoding UTF8
    $null = Get-Content -LiteralPath $stagingSummaryPath -Raw -Encoding UTF8 | ConvertFrom-Json

    [IO.File]::Move($temporaryOutput, $outputPath)
    $publishedOutput = $true
    $publishedOutputItem = Get-Item -LiteralPath $outputPath
    $publishedOutputHash = (Get-FileHash -LiteralPath $outputPath -Algorithm SHA256).Hash
    if ($publishedOutputItem.Length -ne $outputItem.Length -or $publishedOutputHash -ne $outputHash) {
        throw 'Published Cut-in NPK differs from the fully validated temporary candidate.'
    }

    Move-Item -LiteralPath $stagingValidation -Destination $validationRoot
    $publishedValidation = $true
    $summaryPath = Join-Path $validationRoot 'build-summary.json'

    Write-Output "SourceFile=$sourceNpk"
    Write-Output "SourceLength=$($sourceItem.Length)"
    Write-Output "SourceLastWriteTime=$($sourceItem.LastWriteTime.ToString('o'))"
    Write-Output "SourceSha256=$sourceHash"
    Write-Output "EditedPngDirectory=$editedPath"
    Write-Output "EditedPngCount=$($editedPngs.Count)"
    Write-Output "FinalOutput=$outputPath"
    Write-Output "OutputLength=$($outputItem.Length)"
    Write-Output "OutputSha256=$outputHash"
    Write-Output "BuildSummary=$summaryPath"
    Write-Output 'Deployment=not-authorized-not-performed'
}
catch {
    if ($publishedValidation -and (Test-Path -LiteralPath $validationRoot)) {
        Remove-Item -LiteralPath $validationRoot -Recurse -Force
    }
    if ($publishedOutput -and (Test-Path -LiteralPath $outputPath -PathType Leaf)) {
        Remove-Item -LiteralPath $outputPath -Force
    }
    throw
}
finally {
    foreach ($temporaryPath in @($temporaryOutput, $workDirectory, $stagingValidation)) {
        if (Test-Path -LiteralPath $temporaryPath) {
            Remove-Item -LiteralPath $temporaryPath -Recurse -Force
        }
    }
}

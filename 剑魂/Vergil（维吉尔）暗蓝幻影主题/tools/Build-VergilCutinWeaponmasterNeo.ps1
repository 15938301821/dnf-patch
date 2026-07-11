[CmdletBinding()]
param(
    [string]$ImagePacks2,

    [string]$OutputFile,

    [string]$ExtractorDirectory,

    [string]$EditedPngDirectory,

    [string]$TexconvPath,

    [string]$TexdiagPath
)

$ErrorActionPreference = 'Stop'

$themeRoot = Split-Path -Parent $PSScriptRoot
$professionRoot = Split-Path -Parent $themeRoot
$repoRoot = Split-Path -Parent $professionRoot
Import-Module (Join-Path $repoRoot 'tools\DnfPatch.Toolchain.psm1') -Force
$imagePacksPath = Resolve-DnfImagePacks2 -Path $ImagePacks2 -RepositoryRoot $repoRoot
$ExtractorDirectory = Resolve-DnfExtractorDirectory -Path $ExtractorDirectory -RepositoryRoot $repoRoot
$TexconvPath = Resolve-DnfDirectXTexTool -Name 'texconv.exe' -Path $TexconvPath -RepositoryRoot $repoRoot
$TexdiagPath = Resolve-DnfDirectXTexTool -Name 'texdiag.exe' -Path $TexdiagPath -RepositoryRoot $repoRoot
$sourceCode = Join-Path $PSScriptRoot 'Build-VergilCutinWeaponmasterNeo.cs'
$buildRoot = Join-Path $repoRoot 'tools\bin\vergil-cutin-weaponmaster-neo-v3-aseprite'
$builder = Join-Path $buildRoot 'Build-VergilCutinWeaponmasterNeo.exe'
$compiler = 'C:\Windows\Microsoft.NET\Framework\v4.0.30319\csc.exe'
$validationRoot = Join-Path $themeRoot 'validation\build-cutin-neo-v3-aseprite'
if ([string]::IsNullOrWhiteSpace($OutputFile)) {
    $OutputFile = Join-Path $themeRoot 'npk\cutin-weaponmaster-neo-v3-aseprite\sprite_character_swordman_effect_cutin.NPK'
}
if ([string]::IsNullOrWhiteSpace($EditedPngDirectory)) {
    $EditedPngDirectory = Join-Path $themeRoot 'frames\runtime\cutin_weaponmaster_neo_aseprite_v1\png'
}

$sourceNpk = Join-Path $imagePacksPath 'sprite_character_swordman_effect_cutin.NPK'
$outputPath = [IO.Path]::GetFullPath($OutputFile)
$editedPath = (Resolve-Path -LiteralPath $EditedPngDirectory).Path

foreach ($requiredFile in @(
    $sourceCode,
    $compiler,
    $sourceNpk,
    (Join-Path $ExtractorDirectory 'ExtractorSharp.Core.dll'),
    (Join-Path $ExtractorDirectory 'ExtractorSharp.Json.dll'),
    (Join-Path $ExtractorDirectory 'zlib1.dll'),
    $TexconvPath,
    $TexdiagPath
)) {
    if (-not (Test-Path -LiteralPath $requiredFile -PathType Leaf)) {
        throw "Required file was not found: $requiredFile"
    }
}

$editedPngs = @(Get-ChildItem -LiteralPath $editedPath -File -Filter 'frame-*.png')
if ($editedPngs.Count -ne 24) {
    throw "Expected 24 edited PNG files, found $($editedPngs.Count): $editedPath"
}

if (Test-Path -LiteralPath $outputPath) {
    throw "Refusing to overwrite an existing versioned artifact: $outputPath"
}

foreach ($directXTool in @($TexconvPath, $TexdiagPath)) {
    $signature = Get-AuthenticodeSignature -LiteralPath $directXTool
    if ($signature.Status -ne [System.Management.Automation.SignatureStatus]::Valid) {
        throw "DirectXTex signature is not valid: $directXTool ($($signature.Status))"
    }
}

New-Item -ItemType Directory -Path $buildRoot -Force | Out-Null
New-Item -ItemType Directory -Path $validationRoot -Force | Out-Null
New-Item -ItemType Directory -Path (Split-Path -Parent $outputPath) -Force | Out-Null

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

$runId = [Guid]::NewGuid().ToString('N')
$temporaryOutput = Join-Path $buildRoot ("candidate-$runId.NPK")
$workDirectory = Join-Path $buildRoot ("work-$runId")
$buildLog = Join-Path $validationRoot 'builder-output.txt'

& $builder $sourceNpk $temporaryOutput $editedPath $TexconvPath $TexdiagPath $workDirectory |
    Tee-Object -LiteralPath $buildLog
if ($LASTEXITCODE -ne 0) {
    throw "Patch generation failed with exit code $LASTEXITCODE."
}
if (-not (Test-Path -LiteralPath $temporaryOutput -PathType Leaf)) {
    throw 'Builder did not create the temporary NPK.'
}

[IO.File]::Move($temporaryOutput, $outputPath)

$sourceItem = Get-Item -LiteralPath $sourceNpk
$outputItem = Get-Item -LiteralPath $outputPath
$sourceHash = (Get-FileHash -LiteralPath $sourceNpk -Algorithm SHA256).Hash
$outputHash = (Get-FileHash -LiteralPath $outputPath -Algorithm SHA256).Hash
$editedHashes = $editedPngs |
    Sort-Object Name |
    Select-Object Name,Length,@{n='Sha256';e={(Get-FileHash -LiteralPath $_.FullName -Algorithm SHA256).Hash}}

$summary = [ordered]@{
    generatedAt = (Get-Date).ToString('o')
    mode = 'offline build, deployment not authorized'
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
    changedFrames = 3..26
    preservedFrames = 0..2
    preservedNonTargetImgPayloads = 25
    deployment = 'not-authorized-not-performed'
}
$summaryPath = Join-Path $validationRoot 'build-summary.json'
$summary | ConvertTo-Json -Depth 8 | Set-Content -LiteralPath $summaryPath -Encoding UTF8

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

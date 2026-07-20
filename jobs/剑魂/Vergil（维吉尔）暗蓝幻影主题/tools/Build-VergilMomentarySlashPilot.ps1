[CmdletBinding()]
param(
    [string]$ImagePacks2,

    [string]$OutputFile,

    [string]$ExtractorDirectory,

    [string]$TexconvPath,

    [string]$TexdiagPath
)

$ErrorActionPreference = 'Stop'

$themeRoot = Split-Path -Parent $PSScriptRoot
$professionRoot = Split-Path -Parent $themeRoot
$jobsRoot = Split-Path -Parent $professionRoot
$repoRoot = Split-Path -Parent $jobsRoot
Import-Module (Join-Path $repoRoot 'tools\DnfPatch.Toolchain.psm1') -Force
$imagePacksPath = Resolve-DnfImagePacks2 -Path $ImagePacks2 -RepositoryRoot $repoRoot
$ExtractorDirectory = Resolve-DnfExtractorDirectory -Path $ExtractorDirectory -RepositoryRoot $repoRoot
$TexconvPath = Resolve-DnfDirectXTexTool -Name 'texconv.exe' -Path $TexconvPath -RepositoryRoot $repoRoot
$TexdiagPath = Resolve-DnfDirectXTexTool -Name 'texdiag.exe' -Path $TexdiagPath -RepositoryRoot $repoRoot
$sourceCode = Join-Path $PSScriptRoot 'Build-VergilMomentarySlashPilot.cs'
$manifestFile = Join-Path $professionRoot 'manifest.json'
$buildRoot = Join-Path $repoRoot 'tools\bin\vergil-momentaryslash-pilot-v2-local-source'
$builder = Join-Path $buildRoot 'Build-VergilMomentarySlashPilot.exe'
$compiler = 'C:\Windows\Microsoft.NET\Framework\v4.0.30319\csc.exe'
$validationRoot = Join-Path $themeRoot 'validation\build-pilot-v2-local-source'

if ([string]::IsNullOrWhiteSpace($OutputFile)) {
    $OutputFile = Join-Path $themeRoot 'npk\vergil-momentaryslash-pilot-v2-local-source.NPK'
}

$sourceNpk = Join-Path $imagePacksPath 'sprite_character_swordman_effect_momentaryslash.NPK'
$outputPath = [IO.Path]::GetFullPath($OutputFile)

foreach ($requiredFile in @(
    $sourceCode,
    $manifestFile,
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

& $builder $sourceNpk $temporaryOutput $TexconvPath $TexdiagPath $workDirectory |
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
$manifestHash = (Get-FileHash -LiteralPath $manifestFile -Algorithm SHA256).Hash

Write-Output "SourceFile=$sourceNpk"
Write-Output "SourceLength=$($sourceItem.Length)"
Write-Output "SourceLastWriteTime=$($sourceItem.LastWriteTime.ToString('o'))"
Write-Output "SourceSha256=$sourceHash"
Write-Output "ManifestSha256=$manifestHash"
Write-Output "FinalOutput=$outputPath"
Write-Output "OutputLength=$($outputItem.Length)"
Write-Output "OutputSha256=$outputHash"
Write-Output 'Deployment=not-authorized-not-performed'

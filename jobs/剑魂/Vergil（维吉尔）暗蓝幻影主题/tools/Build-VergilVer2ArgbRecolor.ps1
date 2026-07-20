[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)]
    [string]$ConfigFile,

    [string]$ImagePacks2,

    [string]$ExtractorDirectory,

    [switch]$AllowLegacyEndpointRecolor
)

$ErrorActionPreference = 'Stop'
if (-not $AllowLegacyEndpointRecolor) {
    throw 'This script is legacy ARGB recolor diagnostic only. Default patch generation must run the registered official-source model prompt package Aseprite workflow and produce layered/runtime evidence. Re-run with -AllowLegacyEndpointRecolor only when intentionally reproducing legacy evidence.'
}

function Resolve-ConfiguredPath {
    param(
        [Parameter(Mandatory = $true)]
        [string]$BaseDirectory,

        [Parameter(Mandatory = $true)]
        [string]$Value
    )

    $nativeValue = $Value.Replace('/', [IO.Path]::DirectorySeparatorChar)
    if (-not [IO.Path]::IsPathRooted($nativeValue)) {
        $nativeValue = Join-Path $BaseDirectory $nativeValue
    }
    return [IO.Path]::GetFullPath($nativeValue)
}

function Assert-PathInsideRoot {
    param(
        [Parameter(Mandatory = $true)]
        [string]$Path,

        [Parameter(Mandatory = $true)]
        [string]$Root,

        [Parameter(Mandatory = $true)]
        [string]$Label
    )

    $fullPath = [IO.Path]::GetFullPath($Path)
    $fullRoot = [IO.Path]::GetFullPath($Root).TrimEnd(
        [IO.Path]::DirectorySeparatorChar,
        [IO.Path]::AltDirectorySeparatorChar)
    $rootPrefix = $fullRoot + [IO.Path]::DirectorySeparatorChar
    if (-not $fullPath.StartsWith($rootPrefix, [StringComparison]::OrdinalIgnoreCase)) {
        throw "$Label must stay inside the current Vergil theme workspace: $fullPath"
    }
}

function Assert-SummaryArtifact {
    param(
        [Parameter(Mandatory = $true)]
        $Artifact,

        [Parameter(Mandatory = $true)]
        [string]$ExpectedPath,

        [Parameter(Mandatory = $true)]
        [string]$Label
    )

    if ($null -eq $Artifact -or
        [string]::IsNullOrWhiteSpace([string]$Artifact.path) -or
        [string]::IsNullOrWhiteSpace([string]$Artifact.sha256)) {
        throw "$Label is missing from the builder toolchain summary."
    }
    $expectedFullPath = [IO.Path]::GetFullPath($ExpectedPath)
    $reportedFullPath = [IO.Path]::GetFullPath([string]$Artifact.path)
    if (-not [string]::Equals($reportedFullPath, $expectedFullPath, [StringComparison]::OrdinalIgnoreCase)) {
        throw "$Label path differs from the executed artifact: $reportedFullPath/$expectedFullPath"
    }
    $item = Get-Item -LiteralPath $expectedFullPath
    if ([long]$Artifact.length -ne $item.Length) {
        throw "$Label length differs from the executed artifact: $($Artifact.length)/$($item.Length)"
    }
    $actualHash = (Get-FileHash -LiteralPath $expectedFullPath -Algorithm SHA256).Hash
    if (-not [string]::Equals([string]$Artifact.sha256, $actualHash, [StringComparison]::OrdinalIgnoreCase)) {
        throw "$Label SHA-256 differs from the executed artifact: $($Artifact.sha256)/$actualHash"
    }
}

$themeRoot = Split-Path -Parent $PSScriptRoot
$professionRoot = Split-Path -Parent $themeRoot
$jobsRoot = Split-Path -Parent $professionRoot
$repoRoot = Split-Path -Parent $jobsRoot
Import-Module (Join-Path $repoRoot 'tools\DnfPatch.Toolchain.psm1') -Force
$ExtractorDirectory = Resolve-DnfExtractorDirectory -Path $ExtractorDirectory -RepositoryRoot $repoRoot
$sourceCode = Join-Path $PSScriptRoot 'Build-VergilVer2ArgbRecolor.cs'
$configSchema = Join-Path $PSScriptRoot 'vergil-ver2-argb-recolor.config.schema.json'
$compiler = 'C:\Windows\Microsoft.NET\Framework\v4.0.30319\csc.exe'
$buildRoot = Join-Path $repoRoot 'tools\bin\vergil-ver2-argb-recolor-v2-local-source'
$builder = Join-Path $buildRoot 'Build-VergilVer2ArgbRecolor.exe'

$configPath = (Resolve-Path -LiteralPath $ConfigFile).Path
$configDirectory = Split-Path -Parent $configPath
$config = Get-Content -LiteralPath $configPath -Raw -Encoding UTF8 | ConvertFrom-Json
if ($config.schemaVersion -ne 1) {
    throw "Unsupported config schemaVersion: $($config.schemaVersion)"
}
if ($config.themeId -ne 'weaponmaster-vergil-dark-blue') {
    throw 'Config themeId must be weaponmaster-vergil-dark-blue.'
}
if ($null -eq $config.sourceNpk -or
    [string]::IsNullOrWhiteSpace([string]$config.sourceNpk.path) -or
    [string]::IsNullOrWhiteSpace([string]$config.sourceNpk.sha256) -or
    [long]$config.sourceNpk.length -lt 1) {
    throw 'Config sourceNpk.path, sourceNpk.sha256, and a positive sourceNpk.length are required.'
}
if ($null -eq $config.output -or
    [string]::IsNullOrWhiteSpace([string]$config.output.componentNpkPath) -or
    [string]::IsNullOrWhiteSpace([string]$config.output.buildSummaryPath)) {
    throw 'Config output.componentNpkPath and output.buildSummaryPath are required.'
}
if ($null -eq $config.expectations -or
    [int]$config.expectations.albumCount -lt 1 -or
    [int]$config.expectations.frameCount -lt 1) {
    throw 'Config expectations.albumCount and expectations.frameCount must be positive.'
}
if (@($config.allowedImgPaths).Count -eq 0) {
    throw 'Config allowedImgPaths must not be empty.'
}
if ($null -eq $config.PSObject.Properties['excludedImgPaths']) {
    throw 'Config excludedImgPaths must be present; use an empty array when none are excluded.'
}
if ($null -eq $config.PSObject.Properties['excludedFrameKeys']) {
    throw 'Config excludedFrameKeys must be present; use an empty array when none are excluded.'
}

$sourceNpk = Resolve-DnfSourceNpk -ConfiguredPath ([string]$config.sourceNpk.path) `
    -ImagePacks2 $ImagePacks2 -RepositoryRoot $repoRoot
$outputPath = Resolve-ConfiguredPath -BaseDirectory $configDirectory -Value ([string]$config.output.componentNpkPath)
$summaryPath = Resolve-ConfiguredPath -BaseDirectory $configDirectory -Value ([string]$config.output.buildSummaryPath)
Assert-PathInsideRoot -Path $outputPath -Root $themeRoot -Label 'Component NPK output'
Assert-PathInsideRoot -Path $summaryPath -Root $themeRoot -Label 'Build summary output'

foreach ($requiredFile in @(
    $sourceCode,
    $configSchema,
    $compiler,
    $sourceNpk,
    (Join-Path $ExtractorDirectory 'ExtractorSharp.Core.dll'),
    (Join-Path $ExtractorDirectory 'ExtractorSharp.Json.dll'),
    (Join-Path $ExtractorDirectory 'zlib1.dll')
)) {
    if (-not (Test-Path -LiteralPath $requiredFile -PathType Leaf)) {
        throw "Required file was not found: $requiredFile"
    }
}

$configHashBefore = (Get-FileHash -LiteralPath $configPath -Algorithm SHA256).Hash
$sourceCodeHashBefore = (Get-FileHash -LiteralPath $sourceCode -Algorithm SHA256).Hash
$configSchemaHashBefore = (Get-FileHash -LiteralPath $configSchema -Algorithm SHA256).Hash

if (Test-Path -LiteralPath $outputPath) {
    throw "Refusing to overwrite an existing component NPK: $outputPath"
}
if (Test-Path -LiteralPath $summaryPath) {
    throw "Refusing to overwrite an existing build summary: $summaryPath"
}
if ([IO.Path]::GetFileName($sourceNpk) -eq [IO.Path]::GetFileName($outputPath)) {
    throw 'Component NPK filename must not impersonate the official source filename.'
}

$expectedHash = ([string]$config.sourceNpk.sha256).ToUpperInvariant()
$actualHash = (Get-FileHash -LiteralPath $sourceNpk -Algorithm SHA256).Hash
if ($actualHash -ne $expectedHash) {
    throw "Source SHA-256 changed: $actualHash/$expectedHash"
}
$actualLength = (Get-Item -LiteralPath $sourceNpk).Length
if ($actualLength -ne [long]$config.sourceNpk.length) {
    throw "Source length changed: $actualLength/$($config.sourceNpk.length)"
}

New-Item -ItemType Directory -Path $buildRoot -Force | Out-Null
foreach ($dependency in @('ExtractorSharp.Core.dll', 'ExtractorSharp.Json.dll', 'zlib1.dll')) {
    Copy-Item -LiteralPath (Join-Path $ExtractorDirectory $dependency) `
        -Destination (Join-Path $buildRoot $dependency) `
        -Force
}

$compilerArguments = @(
    '/nologo',
    '/warn:4',
    '/warnaserror+',
    '/optimize+',
    '/platform:x86',
    '/target:exe',
    ('/out:' + $builder),
    '/reference:System.Drawing.dll',
    '/reference:System.Security.dll',
    '/reference:System.Web.Extensions.dll',
    ('/reference:' + (Join-Path $buildRoot 'ExtractorSharp.Core.dll')),
    ('/reference:' + (Join-Path $buildRoot 'ExtractorSharp.Json.dll')),
    $sourceCode
)
& $compiler $compilerArguments
if ($LASTEXITCODE -ne 0) {
    throw "Compilation failed with exit code $LASTEXITCODE."
}
$sourceCodeHashAfterCompile = (Get-FileHash -LiteralPath $sourceCode -Algorithm SHA256).Hash
if ($sourceCodeHashAfterCompile -ne $sourceCodeHashBefore) {
    throw 'Builder source changed while it was being compiled.'
}

$previousErrorActionPreference = $ErrorActionPreference
try {
    $ErrorActionPreference = 'Continue'
    $builderOutput = & $builder $configPath $sourceNpk $sourceCode 2>&1
    $builderExitCode = $LASTEXITCODE
}
finally {
    $ErrorActionPreference = $previousErrorActionPreference
}
$builderOutput | Write-Output
if ($builderExitCode -ne 0) {
    throw "Patch generation failed with exit code $builderExitCode."
}
if (-not (Test-Path -LiteralPath $outputPath -PathType Leaf)) {
    throw 'Builder did not create the configured component NPK.'
}
if (-not (Test-Path -LiteralPath $summaryPath -PathType Leaf)) {
    throw 'Builder did not create build-summary.json.'
}

$summary = Get-Content -LiteralPath $summaryPath -Raw -Encoding UTF8 | ConvertFrom-Json
$requiredValidation = @{
    sourceIdentityReverified = 'passed-before-load-after-load-and-before-summary'
    reopenedFromDisk = 'passed'
    structureAndFrameOrder = 'passed'
    typeAndCompression = 'preserved'
    geometryAndLinks = 'preserved'
    nativeZlibStatusAndLength = 'passed'
    authorizedDecodedAlpha = 'byte-identical'
    authorizedVisibleNearBlackRgb = 'byte-identical'
    unauthorizedRawData = 'byte-identical'
    unauthorizedDecodedBgra = 'byte-identical'
}
if ($summary.status -ne 'passed') {
    throw 'Builder summary status is not passed.'
}
foreach ($gate in $requiredValidation.GetEnumerator()) {
    if ([string]$summary.validation.($gate.Key) -ne $gate.Value) {
        throw "Builder summary gate $($gate.Key) is not $($gate.Value)."
    }
}
if ($summary.validation.independentNpkIndex -ne 'pending-external' -or
    $summary.validation.independentFullFrameDecode -ne 'pending-external') {
    throw 'Builder summary must leave independent validation to the external release gates.'
}
if ([int]$summary.counts.changedFrames -lt 1 -or
    [int]$summary.counts.eligibleFrames -ne [int]$summary.counts.changedFrames -or
    ([int]$summary.counts.changedFrames + [int]$summary.counts.skippedFrames) -ne [int]$summary.counts.frames) {
    throw 'Builder summary frame decisions are inconsistent.'
}
if ([int]$summary.validation.authorizedAlphaVerifiedFrames -ne [int]$summary.counts.changedFrames -or
    [int]$summary.validation.authorizedNearBlackVerifiedFrames -ne [int]$summary.counts.changedFrames) {
    throw 'Builder summary authorized alpha/near-black verification counts are inconsistent.'
}
if (@($summary.albums).Count -ne [int]$config.expectations.albumCount -or
    @($summary.frames).Count -ne [int]$config.expectations.frameCount) {
    throw 'Builder summary album/frame evidence count differs from the config expectations.'
}
$reportedExcludedImgs = @($summary.selection.explicitExcludedImgPaths | Sort-Object)
$configuredExcludedImgs = @($config.excludedImgPaths | Sort-Object)
if ($reportedExcludedImgs.Count -ne $configuredExcludedImgs.Count -or
    ($reportedExcludedImgs -join "`n") -ne ($configuredExcludedImgs -join "`n")) {
    throw 'Builder summary excluded IMG paths differ from the config.'
}
if ($summary.deployment.performed -ne $false -or
    $summary.deployment.status -ne 'not-authorized-not-performed') {
    throw 'Builder summary unexpectedly reports deployment.'
}

$extractorCore = Join-Path $buildRoot 'ExtractorSharp.Core.dll'
$extractorJson = Join-Path $buildRoot 'ExtractorSharp.Json.dll'
$zlib = Join-Path $buildRoot 'zlib1.dll'
Assert-SummaryArtifact -Artifact $summary.toolchain.config -ExpectedPath $configPath -Label 'Build config'
Assert-SummaryArtifact -Artifact $summary.toolchain.configSchema -ExpectedPath $configSchema -Label 'Config schema'
Assert-SummaryArtifact -Artifact $summary.toolchain.builderSource -ExpectedPath $sourceCode -Label 'Builder source'
Assert-SummaryArtifact -Artifact $summary.toolchain.builderExecutable -ExpectedPath $builder -Label 'Builder executable'
Assert-SummaryArtifact -Artifact $summary.toolchain.extractorSharpCore -ExpectedPath $extractorCore -Label 'ExtractorSharp.Core'
Assert-SummaryArtifact -Artifact $summary.toolchain.extractorSharpJson -ExpectedPath $extractorJson -Label 'ExtractorSharp.Json'
Assert-SummaryArtifact -Artifact $summary.toolchain.zlib -ExpectedPath $zlib -Label 'zlib'

if ((Get-FileHash -LiteralPath $configPath -Algorithm SHA256).Hash -ne $configHashBefore -or
    (Get-FileHash -LiteralPath $sourceCode -Algorithm SHA256).Hash -ne $sourceCodeHashBefore -or
    (Get-FileHash -LiteralPath $configSchema -Algorithm SHA256).Hash -ne $configSchemaHashBefore) {
    throw 'Config, builder source, or schema changed during generation.'
}

$outputItem = Get-Item -LiteralPath $outputPath
$outputHash = (Get-FileHash -LiteralPath $outputPath -Algorithm SHA256).Hash
if (-not [string]::Equals([string]$summary.output.componentNpkPath, $outputPath, [StringComparison]::OrdinalIgnoreCase) -or
    [long]$summary.output.length -ne $outputItem.Length -or
    -not [string]::Equals([string]$summary.output.sha256, $outputHash, [StringComparison]::OrdinalIgnoreCase)) {
    throw 'Builder summary output identity differs from the created component NPK.'
}
Write-Output "FinalOutput=$outputPath"
Write-Output "OutputLength=$($outputItem.Length)"
Write-Output "OutputSha256=$outputHash"
Write-Output "BuildSummary=$summaryPath"
Write-Output 'Deployment=not-authorized-not-performed'

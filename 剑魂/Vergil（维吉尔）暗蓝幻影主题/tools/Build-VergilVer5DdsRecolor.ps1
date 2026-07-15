[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)]
    [string]$ConfigFile,

    [string]$ImagePacks2,

    [string]$ExtractorDirectory,

    [string]$TexdiagPath
)

$ErrorActionPreference = 'Stop'

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

$themeRoot = Split-Path -Parent $PSScriptRoot
$professionRoot = Split-Path -Parent $themeRoot
$repoRoot = Split-Path -Parent $professionRoot
Import-Module (Join-Path $repoRoot 'tools\DnfPatch.Toolchain.psm1') -Force
$ExtractorDirectory = Resolve-DnfExtractorDirectory -Path $ExtractorDirectory -RepositoryRoot $repoRoot
$TexdiagPath = Resolve-DnfDirectXTexTool -Name 'texdiag.exe' -Path $TexdiagPath -RepositoryRoot $repoRoot
$sourceCode = Join-Path $PSScriptRoot 'Build-VergilVer5DdsRecolor.cs'
$compiler = 'C:\Windows\Microsoft.NET\Framework\v4.0.30319\csc.exe'
$buildRoot = Join-Path $repoRoot 'tools\bin\vergil-ver5-dds-recolor-v3-endpoint-recolor'
$builder = Join-Path $buildRoot 'Build-VergilVer5DdsRecolor.exe'

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
    [string]::IsNullOrWhiteSpace([string]$config.sourceNpk.sha256)) {
    throw 'Config sourceNpk.path and sourceNpk.sha256 are required.'
}
if ($null -eq $config.output -or
    [string]::IsNullOrWhiteSpace([string]$config.output.componentNpkPath) -or
    [string]::IsNullOrWhiteSpace([string]$config.output.buildSummaryPath)) {
    throw 'Config output.componentNpkPath and output.buildSummaryPath are required.'
}
if (@($config.allowedImgPaths).Count -eq 0) {
    throw 'Config allowedImgPaths must not be empty.'
}
if ($null -eq $config.PSObject.Properties['excludedFrameKeys']) {
    throw 'Config excludedFrameKeys must be present; use an empty array when none are excluded.'
}
$usesIllusionSlashScope = $false
foreach ($imgPath in @($config.allowedImgPaths)) {
    $normalizedImgPath = ([string]$imgPath).Trim().Replace('\', '/')
    if ($normalizedImgPath.StartsWith('sprite/character/swordman/effect/illusionslash/', [StringComparison]::OrdinalIgnoreCase)) {
        $usesIllusionSlashScope = $true
    }
}
$illusionSlashPromptFileName = [string]::Concat([char]0x5E7B, [char]0x5F71, [char]0x5251, [char]0x821E, '.md')
$expectedThemeAgentPath = [IO.Path]::GetFullPath((Join-Path $themeRoot 'AGENTS.md'))
$expectedThemePromptPath = [IO.Path]::GetFullPath((Join-Path (Join-Path $themeRoot 'prompts') $illusionSlashPromptFileName))
$expectedProfessionPromptPath = [IO.Path]::GetFullPath((Join-Path (Join-Path $professionRoot 'prompts') $illusionSlashPromptFileName))
if ($usesIllusionSlashScope -or $null -ne $config.PSObject.Properties['promptBinding']) {
    if ($null -eq $config.promptBinding) {
        throw 'Illusionslash configs must include promptBinding.'
    }
    if ([string]$config.promptBinding.role -ne 'primary-skill-prompt' -or [int]$config.promptBinding.priority -ne 1) {
        throw 'Illusionslash promptBinding must be the primary skill prompt with priority 1.'
    }
    if ([string]$config.promptBinding.uiFrameGeometryPolicy -ne 'strict-preserve-source-frame-position-size' -or
        [string]$config.promptBinding.scope -ne 'illusionslash-only') {
        throw 'Illusionslash promptBinding must require strict source frame position/size preservation and illusionslash-only scope.'
    }
    if ([string]::IsNullOrWhiteSpace([string]$config.promptBinding.themeAgentPath) -or
        [string]::IsNullOrWhiteSpace([string]$config.promptBinding.themePromptPath) -or
        [string]::IsNullOrWhiteSpace([string]$config.promptBinding.professionPromptPath)) {
        throw 'Illusionslash promptBinding must include themeAgentPath, themePromptPath, and professionPromptPath.'
    }
}

$sourceNpk = Resolve-DnfSourceNpk -ConfiguredPath ([string]$config.sourceNpk.path) `
    -ImagePacks2 $ImagePacks2 -RepositoryRoot $repoRoot
$outputPath = Resolve-ConfiguredPath -BaseDirectory $configDirectory -Value ([string]$config.output.componentNpkPath)
$summaryPath = Resolve-ConfiguredPath -BaseDirectory $configDirectory -Value ([string]$config.output.buildSummaryPath)
$promptFiles = @()
if ($null -ne $config.promptBinding) {
    $themeAgentPath = Resolve-ConfiguredPath -BaseDirectory $configDirectory -Value ([string]$config.promptBinding.themeAgentPath)
    $themePromptPath = Resolve-ConfiguredPath -BaseDirectory $configDirectory -Value ([string]$config.promptBinding.themePromptPath)
    $professionPromptPath = Resolve-ConfiguredPath -BaseDirectory $configDirectory -Value ([string]$config.promptBinding.professionPromptPath)
    if (-not [IO.Path]::GetFullPath($themeAgentPath).Equals($expectedThemeAgentPath, [StringComparison]::OrdinalIgnoreCase) -or
        -not [IO.Path]::GetFullPath($themePromptPath).Equals($expectedThemePromptPath, [StringComparison]::OrdinalIgnoreCase) -or
        -not [IO.Path]::GetFullPath($professionPromptPath).Equals($expectedProfessionPromptPath, [StringComparison]::OrdinalIgnoreCase)) {
        throw 'Illusionslash promptBinding must target the theme AGENTS, theme prompt, and profession prompt files.'
    }
    $promptFiles += $themeAgentPath
    $promptFiles += $themePromptPath
    $promptFiles += $professionPromptPath
}
Assert-PathInsideRoot -Path $outputPath -Root $themeRoot -Label 'Component NPK output'
Assert-PathInsideRoot -Path $summaryPath -Root $themeRoot -Label 'Build summary output'
$repoRootForPrefix = [IO.Path]::GetFullPath($repoRoot).TrimEnd([IO.Path]::DirectorySeparatorChar, [IO.Path]::AltDirectorySeparatorChar)
foreach ($promptFile in $promptFiles) {
    if (-not [IO.Path]::GetFullPath($promptFile).StartsWith(($repoRootForPrefix + [IO.Path]::DirectorySeparatorChar), [StringComparison]::OrdinalIgnoreCase)) {
        throw "Prompt binding file must stay inside the repository: $promptFile"
    }
}

foreach ($requiredFile in @(
        $sourceCode,
        $compiler,
        $sourceNpk,
        (Join-Path $ExtractorDirectory 'ExtractorSharp.Core.dll'),
        (Join-Path $ExtractorDirectory 'ExtractorSharp.Json.dll'),
        (Join-Path $ExtractorDirectory 'zlib1.dll'),
        $TexdiagPath
    )) {
    if (-not (Test-Path -LiteralPath $requiredFile -PathType Leaf)) {
        throw "Required file was not found: $requiredFile"
    }
}

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
if ([long]$config.sourceNpk.length -gt 0) {
    $actualLength = (Get-Item -LiteralPath $sourceNpk).Length
    if ($actualLength -ne [long]$config.sourceNpk.length) {
        throw "Source length changed: $actualLength/$($config.sourceNpk.length)"
    }
}

$signature = Get-AuthenticodeSignature -LiteralPath $TexdiagPath
if ($signature.Status -ne [System.Management.Automation.SignatureStatus]::Valid) {
    throw "DirectXTex signature is not valid: $TexdiagPath ($($signature.Status))"
}

New-Item -ItemType Directory -Path $buildRoot -Force | Out-Null
foreach ($dependency in @('ExtractorSharp.Core.dll', 'ExtractorSharp.Json.dll', 'zlib1.dll')) {
    Copy-Item -LiteralPath (Join-Path $ExtractorDirectory $dependency) `
        -Destination (Join-Path $buildRoot $dependency) `
        -Force
}

$compilerArguments = @(
    '/nologo',
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

$runId = [Guid]::NewGuid().ToString('N')
$workDirectory = Join-Path $buildRoot ("work-$runId")
New-Item -ItemType Directory -Path $workDirectory -Force | Out-Null

$builderOutput = & $builder $configPath $sourceNpk $TexdiagPath $workDirectory 2>&1
$builderExitCode = $LASTEXITCODE
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
if ($summary.status -ne 'passed' -or
    $summary.validation.reopenedFromDisk -ne 'passed' -or
    $summary.validation.texdiagPerTexture -ne 'passed') {
    throw 'Builder summary does not report all required gates as passed.'
}

$outputItem = Get-Item -LiteralPath $outputPath
Write-Output "FinalOutput=$outputPath"
Write-Output "OutputLength=$($outputItem.Length)"
Write-Output "OutputSha256=$((Get-FileHash -LiteralPath $outputPath -Algorithm SHA256).Hash)"
Write-Output "BuildSummary=$summaryPath"
Write-Output 'Deployment=not-authorized-not-performed'

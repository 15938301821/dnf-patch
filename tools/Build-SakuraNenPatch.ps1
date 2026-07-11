param(
    [string]$ImagePacks2,

    [string]$OutputFile,

    [string]$ExtractorDirectory,

    [switch]$ExactSecondFix
)

$projectRoot = Split-Path -Parent $PSScriptRoot
Import-Module (Join-Path $PSScriptRoot 'DnfPatch.Toolchain.psm1') -Force
$imagePacksPath = Resolve-DnfImagePacks2 -Path $ImagePacks2 -RepositoryRoot $projectRoot
$extractorDir = Resolve-DnfExtractorDirectory -Path $ExtractorDirectory -RepositoryRoot $projectRoot
$themeRoot = Join-Path $projectRoot '气功师（女）\樱花主题'
$binDir = Join-Path $PSScriptRoot 'bin'
$sourceFile = Join-Path $PSScriptRoot 'Build-SakuraNenPatch.cs'
$builder = Join-Path $binDir 'Build-SakuraNenPatch.exe'
$compiler = 'C:\Windows\Microsoft.NET\Framework\v4.0.30319\csc.exe'
$sourceLink = Join-Path $binDir 'ImagePacks2'
$temporaryOutput = Join-Path $binDir 'sakura-nen-patch.npk'
$previousExactSecondFix = $env:SAKURA_EXACT_SECOND_FIX

if ([string]::IsNullOrWhiteSpace($OutputFile)) {
    $outputName = if ($ExactSecondFix) {
        '!!!女气功全技能-樱花粉-第二次修复原版.NPK'
    }
    else {
        '!!!女气功全技能-樱花粉.NPK'
    }
    $OutputFile = Join-Path (Join-Path $themeRoot 'npk') $outputName
}

New-Item -ItemType Directory -Path $binDir -Force | Out-Null

$dependencies = @(
    'ExtractorSharp.Core.dll',
    'ExtractorSharp.Json.dll',
    'zlib1.dll'
)
foreach ($dependency in $dependencies) {
    Copy-Item -LiteralPath (Join-Path $extractorDir $dependency) -Destination (Join-Path $binDir $dependency) -Force
}

$coreReference = '/reference:' + (Join-Path $binDir 'ExtractorSharp.Core.dll')
$jsonReference = '/reference:' + (Join-Path $binDir 'ExtractorSharp.Json.dll')
& $compiler /nologo /optimize+ /platform:x86 /target:exe `
    /out:$builder `
    /reference:System.Drawing.dll `
    $coreReference `
    $jsonReference `
    $sourceFile
if ($LASTEXITCODE -ne 0) {
    throw "Compilation failed with exit code $LASTEXITCODE."
}

if (Test-Path -LiteralPath $sourceLink) {
    [IO.Directory]::Delete($sourceLink, $false)
}
New-Item -ItemType Junction -Path $sourceLink -Target $imagePacksPath | Out-Null

try {
    $env:SAKURA_IMAGEPACKS2 = $sourceLink
    $env:SAKURA_OUTPUT = $temporaryOutput
    if ($ExactSecondFix) {
        $env:SAKURA_EXACT_SECOND_FIX = '1'
    }
    else {
        Remove-Item Env:SAKURA_EXACT_SECOND_FIX -ErrorAction SilentlyContinue
    }
    & $builder
    if ($LASTEXITCODE -ne 0) {
        throw "Patch generation failed with exit code $LASTEXITCODE."
    }

    $outputDirectory = Split-Path -Parent $OutputFile
    New-Item -ItemType Directory -Path $outputDirectory -Force | Out-Null
    Move-Item -LiteralPath $temporaryOutput -Destination $OutputFile -Force
    Write-Output "FinalOutput=$OutputFile"
}
finally {
    if ($null -eq $previousExactSecondFix) {
        Remove-Item Env:SAKURA_EXACT_SECOND_FIX -ErrorAction SilentlyContinue
    }
    else {
        $env:SAKURA_EXACT_SECOND_FIX = $previousExactSecondFix
    }
    if (Test-Path -LiteralPath $sourceLink) {
        [IO.Directory]::Delete($sourceLink, $false)
    }
}

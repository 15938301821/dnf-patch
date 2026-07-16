[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)]
    [string]$ConfigFile,

    [Parameter(Mandatory = $true)]
    [ValidatePattern('^[A-Za-z0-9][A-Za-z0-9._-]*$')]
    [string]$RunId,

    [string]$ImagePacks2,

    [string]$ExtractorDirectory,

    [string]$RuntimeDirectory,

    [string]$RenderSummaryPath,

    [string]$TexconvPath,

    [string]$TexdiagPath,

    [string]$ValidationDirectory
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
$OutputEncoding = [Console]::OutputEncoding = New-Object System.Text.UTF8Encoding($false)

function Resolve-ConfiguredPath {
    param(
        [Parameter(Mandatory = $true)][string]$BaseDirectory,
        [Parameter(Mandatory = $true)][string]$Value
    )

    $native = $Value.Replace('/', [IO.Path]::DirectorySeparatorChar)
    if (-not [IO.Path]::IsPathRooted($native)) {
        $native = Join-Path $BaseDirectory $native
    }
    return [IO.Path]::GetFullPath($native)
}

function Assert-InsideRoot {
    param(
        [Parameter(Mandatory = $true)][string]$Path,
        [Parameter(Mandatory = $true)][string]$Root,
        [Parameter(Mandatory = $true)][string]$Label
    )

    $fullPath = [IO.Path]::GetFullPath($Path)
    $fullRoot = [IO.Path]::GetFullPath($Root).TrimEnd([IO.Path]::DirectorySeparatorChar, [IO.Path]::AltDirectorySeparatorChar)
    $prefix = $fullRoot + [IO.Path]::DirectorySeparatorChar
    if (-not ($fullPath.Equals($fullRoot, [StringComparison]::OrdinalIgnoreCase) -or
            $fullPath.StartsWith($prefix, [StringComparison]::OrdinalIgnoreCase))) {
        throw "$Label must stay inside '$fullRoot': $fullPath"
    }
}

function Get-BomAwareText {
    param([Parameter(Mandatory = $true)][string]$Path)

    $stream = [IO.File]::Open($Path, [IO.FileMode]::Open, [IO.FileAccess]::Read, [IO.FileShare]::Read)
    $reader = New-Object IO.StreamReader($stream, [Text.Encoding]::UTF8, $true)
    try { return $reader.ReadToEnd() }
    finally {
        $reader.Dispose()
        $stream.Dispose()
    }
}

function ConvertFrom-KeyValueOutput {
    param([Parameter(Mandatory = $true)][string]$Text)

    $values = @{}
    foreach ($line in [regex]::Split($Text, "\r\n|\n|\r")) {
        if ($line -notmatch '^(?<key>[A-Za-z][A-Za-z0-9]*)=(?<value>.*)$') { continue }
        $key = [string]$Matches['key']
        if ($values.ContainsKey($key)) { throw "Builder output contains a duplicate key: $key" }
        $values[$key] = [string]$Matches['value']
    }
    return $values
}

function Get-PublishedFileSnapshot {
    param(
        [Parameter(Mandatory = $true)][string]$CurrentPath,
        [Parameter(Mandatory = $true)][string]$PublishedPath
    )

    $snapshot = Get-DnfFileSnapshot -Path $CurrentPath
    return [pscustomobject]@{
        path = [IO.Path]::GetFullPath($PublishedPath)
        length = [long]$snapshot.length
        lastWriteTime = [string]$snapshot.lastWriteTime
        sha256 = [string]$snapshot.sha256
    }
}

function Get-DnfFrameKey {
    param(
        [Parameter(Mandatory = $true)][string]$ImgPath,
        [Parameter(Mandatory = $true)][int]$FrameIndex
    )

    return ($ImgPath.Replace('\\', '/') + '#' + $FrameIndex)
}

$themeRoot = Split-Path -Parent $PSScriptRoot
$professionRoot = Split-Path -Parent $themeRoot
$repoRoot = Split-Path -Parent $professionRoot
Import-Module (Join-Path $repoRoot 'tools\DnfPatch.Toolchain.psm1') -Force

$configPath = (Resolve-Path -LiteralPath $ConfigFile).Path
$configDirectory = Split-Path -Parent $configPath
$config = Get-Content -LiteralPath $configPath -Raw -Encoding UTF8 | ConvertFrom-Json
if ($config.schemaVersion -ne 1) { throw "Unsupported config schemaVersion: $($config.schemaVersion)" }
if ($config.themeId -ne 'weaponmaster-vergil-dark-blue') { throw 'Config themeId must be weaponmaster-vergil-dark-blue.' }
if ($null -eq $config.output -or [string]::IsNullOrWhiteSpace([string]$config.output.componentNpkPath) -or
    [string]::IsNullOrWhiteSpace([string]$config.output.buildSummaryPath)) {
    throw 'Config output paths are required.'
}

$ExtractorDirectory = Resolve-DnfExtractorDirectory -Path $ExtractorDirectory -RepositoryRoot $repoRoot
$TexconvPath = Resolve-DnfDirectXTexTool -Name 'texconv.exe' -Path $TexconvPath -RepositoryRoot $repoRoot
$TexdiagPath = Resolve-DnfDirectXTexTool -Name 'texdiag.exe' -Path $TexdiagPath -RepositoryRoot $repoRoot
$sourceNpk = Resolve-DnfSourceNpk -ConfiguredPath ([string]$config.sourceNpk.path) -ImagePacks2 $ImagePacks2 -RepositoryRoot $repoRoot
if ([string]::IsNullOrWhiteSpace($RuntimeDirectory)) {
    $RuntimeDirectory = Join-Path $themeRoot (Join-Path 'frames\runtime' (Join-Path $RunId 'illusionslash'))
}
if ([string]::IsNullOrWhiteSpace($RenderSummaryPath)) {
    $RenderSummaryPath = Join-Path $themeRoot (Join-Path 'validation' (Join-Path $RunId (Join-Path 'redraw' 'render-summary.json')))
}
if ([string]::IsNullOrWhiteSpace($ValidationDirectory)) {
    $ValidationDirectory = Join-Path $themeRoot (Join-Path 'validation' (Join-Path $RunId 'build-illusionslash'))
}

$runtimePath = (Resolve-Path -LiteralPath $RuntimeDirectory).Path
$renderSummaryFile = (Resolve-Path -LiteralPath $RenderSummaryPath).Path
$validationRoot = [IO.Path]::GetFullPath($ValidationDirectory)
$outputPath = Resolve-ConfiguredPath -BaseDirectory $configDirectory -Value ([string]$config.output.componentNpkPath)
$summaryPath = Resolve-ConfiguredPath -BaseDirectory $configDirectory -Value ([string]$config.output.buildSummaryPath)
$themePath = (Resolve-Path -LiteralPath $themeRoot).Path
foreach ($path in @($runtimePath, $renderSummaryFile, $validationRoot, $outputPath, $summaryPath)) {
    Assert-InsideRoot -Path $path -Root $themePath -Label 'Illusionslash build path'
}
foreach ($newPath in @($validationRoot, $outputPath, $summaryPath)) {
    if (Test-Path -LiteralPath $newPath) { throw "Refusing to overwrite existing build path: $newPath" }
}
foreach ($requiredFile in @(
    (Join-Path $ExtractorDirectory 'ExtractorSharp.Core.dll'),
    (Join-Path $ExtractorDirectory 'ExtractorSharp.Json.dll'),
    (Join-Path $ExtractorDirectory 'zlib1.dll'),
    $sourceNpk,
    $TexconvPath,
    $TexdiagPath,
    $renderSummaryFile,
    (Join-Path $repoRoot 'tools\Test-DnfNpkIndex.ps1'),
    (Join-Path $repoRoot 'tools\Export-DnfNpkValidation.ps1'),
    (Join-Path $repoRoot 'tools\Test-DnfNpkPixels.ps1')
)) {
    if (-not (Test-Path -LiteralPath $requiredFile -PathType Leaf)) {
        throw "Required file was not found: $requiredFile"
    }
}

$renderSummary = Get-Content -LiteralPath $renderSummaryFile -Raw -Encoding UTF8 | ConvertFrom-Json
if ($renderSummary.schemaVersion -ne 1 -or $renderSummary.status -ne 'passed' -or $renderSummary.runId -ne $RunId -or
    $renderSummary.fullSkillCoverageProven -ne $false -or $renderSummary.validation.promptStylePlanBound -ne 'passed') {
    throw 'Render summary does not satisfy the illusionslash build contract.'
}
if ($renderSummary.deployment.authorized -ne $false -or $renderSummary.deployment.performed -ne $false -or
    $renderSummary.deployment.imagePacks2Write -ne $false -or $renderSummary.deployment.processOperation -ne $false) {
    throw 'Render summary must not include deployment.'
}

foreach ($directXTool in @($TexconvPath, $TexdiagPath)) {
    $signature = Get-AuthenticodeSignature -LiteralPath $directXTool
    if ($signature.Status -ne [System.Management.Automation.SignatureStatus]::Valid) {
        throw "DirectXTex signature is not valid: $directXTool ($($signature.Status))"
    }
}

$sourceCode = Join-Path $PSScriptRoot 'Build-VergilIllusionSlashAseprite.cs'
$compiler = 'C:\Windows\Microsoft.NET\Framework\v4.0.30319\csc.exe'
$powerShell32 = Join-Path $env:WINDIR 'SysWOW64\WindowsPowerShell\v1.0\powershell.exe'
foreach ($requiredFile in @($sourceCode, $compiler, $powerShell32)) {
    if (-not (Test-Path -LiteralPath $requiredFile -PathType Leaf)) {
        throw "Required file was not found: $requiredFile"
    }
}

$buildRoot = Join-Path $repoRoot ('tools\bin\vergil-illusionslash-aseprite-build-' + $RunId)
$builder = Join-Path $buildRoot 'Build-VergilIllusionSlashAseprite.exe'
New-Item -ItemType Directory -Path $buildRoot -Force | Out-Null
foreach ($dependency in @('ExtractorSharp.Core.dll', 'ExtractorSharp.Json.dll', 'zlib1.dll')) {
    Copy-Item -LiteralPath (Join-Path $ExtractorDirectory $dependency) -Destination (Join-Path $buildRoot $dependency) -Force
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
if ($LASTEXITCODE -ne 0) { throw "Compilation failed with exit code $LASTEXITCODE." }

New-Item -ItemType Directory -Path (Split-Path -Parent $outputPath) -Force | Out-Null
New-Item -ItemType Directory -Path (Split-Path -Parent $summaryPath) -Force | Out-Null
$validationParent = Split-Path -Parent $validationRoot
New-Item -ItemType Directory -Path $validationParent -Force | Out-Null
$stagingValidation = Join-Path $validationParent ('.' + [IO.Path]::GetFileName($validationRoot) + '.staging-' + [Guid]::NewGuid().ToString('N'))
New-Item -ItemType Directory -Path $stagingValidation | Out-Null
$buildLog = Join-Path $stagingValidation 'builder-output.txt'
$workDirectory = Join-Path $buildRoot ('work-' + [Guid]::NewGuid().ToString('N'))

$publishedValidation = $false
try {
    & $builder $configPath $sourceNpk $renderSummaryFile $runtimePath $TexconvPath $TexdiagPath $workDirectory |
        Tee-Object -LiteralPath $buildLog
    if ($LASTEXITCODE -ne 0) { throw "Patch generation failed with exit code $LASTEXITCODE." }
    if (-not (Test-Path -LiteralPath $outputPath -PathType Leaf)) { throw 'Builder did not create the component NPK.' }
    if (-not (Test-Path -LiteralPath $summaryPath -PathType Leaf)) { throw 'Builder did not create build-summary.json.' }

    $builderText = Get-BomAwareText -Path $buildLog
    $builderValues = ConvertFrom-KeyValueOutput -Text $builderText
    if (-not $builderValues.ContainsKey('StructureValidation') -or $builderValues['StructureValidation'] -ne 'passed' -or
        -not $builderValues.ContainsKey('TexdiagValidation') -or $builderValues['TexdiagValidation'] -ne 'passed') {
        throw 'Builder output did not report required validation markers.'
    }

    $summary = Get-Content -LiteralPath $summaryPath -Raw -Encoding UTF8 | ConvertFrom-Json
    if ($summary.status -ne 'passed' -or $summary.validation.reopenedFromDisk -ne 'passed' -or
        $summary.validation.texdiagPerTexture -ne 'passed' -or $summary.deployment.performed -ne $false) {
        throw 'Build summary does not report all required gates as passed.'
    }
    if ([int]$summary.counts.changedTextures -le 0 -or [int]$summary.counts.changedBc1Textures -le 0) {
        throw 'Build summary did not record changed BC1 textures.'
    }

    $indexJson = & (Join-Path $repoRoot 'tools\Test-DnfNpkIndex.ps1') -Path $outputPath -ExpectedEntryCount (@($config.allowedImgPaths).Count) -AsJson
    if ($LASTEXITCODE -ne 0) { throw 'Independent NPK index validation failed.' }
    $indexJson | Set-Content -LiteralPath (Join-Path $stagingValidation 'npk-index.json') -Encoding UTF8

    $fullFrameOutput = Join-Path $stagingValidation 'full-frame-export'
    & $powerShell32 -NoProfile -ExecutionPolicy Bypass -File (Join-Path $repoRoot 'tools\Export-DnfNpkValidation.ps1') `
        -InputFile $outputPath -OutputDirectory $fullFrameOutput -FramesPerPage 256 | Tee-Object -LiteralPath (Join-Path $stagingValidation 'full-frame-export-output.txt')
    if ($LASTEXITCODE -ne 0) { throw 'Full-frame export validation failed.' }

    $pixelJsonPath = Join-Path $stagingValidation 'pixel-state.json'
    & $powerShell32 -NoProfile -ExecutionPolicy Bypass -File (Join-Path $repoRoot 'tools\Test-DnfNpkPixels.ps1') `
        -InputFile $outputPath -PathPattern 'sprite/character/swordman/effect/illusionslash' -OutputFile $pixelJsonPath | Out-Null
    $pixelExitCode = $LASTEXITCODE
    if (-not (Test-Path -LiteralPath $pixelJsonPath -PathType Leaf)) {
        throw 'Pixel-state validator did not write its JSON report.'
    }
    $pixelState = Get-Content -LiteralPath $pixelJsonPath -Raw -Encoding UTF8 | ConvertFrom-Json
    $excludedFrameKeys = @{}
    foreach ($frameKey in @($config.excludedFrameKeys)) {
        $excludedFrameKeys[[string]$frameKey] = $true
    }
    $pixelFailures = @($pixelState.Records | Where-Object { $_.FullyTransparent -or $_.AllVisiblePixelsBlack -or $_.FullCanvasOpaqueBlack })
    $unexpectedPixelFailures = @($pixelFailures | Where-Object {
        $key = Get-DnfFrameKey -ImgPath ([string]$_.ImgPath) -FrameIndex ([int]$_.FrameIndex)
        -not $excludedFrameKeys.ContainsKey($key)
    })
    if ($unexpectedPixelFailures.Count -ne 0) {
        throw "Pixel-state validation failed outside configured excluded frames: $($unexpectedPixelFailures.Count)"
    }
    if ($pixelExitCode -ne 0 -and $pixelFailures.Count -ne $excludedFrameKeys.Count) {
        throw "Pixel-state validator reported unexpected failure count: $($pixelFailures.Count)"
    }
    $allowedPixelFailures = @($pixelFailures | ForEach-Object {
        [ordered]@{
            frameKey = Get-DnfFrameKey -ImgPath ([string]$_.ImgPath) -FrameIndex ([int]$_.FrameIndex)
            reason = if ($_.FullyTransparent) { 'configured-excluded-fully-transparent' } elseif ($_.AllVisiblePixelsBlack) { 'configured-excluded-all-visible-black' } else { 'configured-excluded-full-canvas-opaque-black' }
        }
    })

    $validationSummaryPath = Join-Path $stagingValidation 'build-validation-summary.json'
    $validationSummary = [ordered]@{
        schemaVersion = 1
        status = 'passed'
        runId = $RunId
        componentNpk = Get-DnfFileSnapshot -Path $outputPath
        buildSummary = Get-DnfFileSnapshot -Path $summaryPath
        renderSummary = Get-DnfFileSnapshot -Path $renderSummaryFile
        index = Get-PublishedFileSnapshot -CurrentPath (Join-Path $stagingValidation 'npk-index.json') -PublishedPath (Join-Path $validationRoot 'npk-index.json')
        fullFrameExport = [ordered]@{
            directory = Join-Path $validationRoot 'full-frame-export'
            albumInventory = Get-PublishedFileSnapshot -CurrentPath (Join-Path $fullFrameOutput 'album-inventory.json') -PublishedPath (Join-Path (Join-Path $validationRoot 'full-frame-export') 'album-inventory.json')
            frameInventory = Get-PublishedFileSnapshot -CurrentPath (Join-Path $fullFrameOutput 'frame-inventory.csv') -PublishedPath (Join-Path (Join-Path $validationRoot 'full-frame-export') 'frame-inventory.csv')
        }
        pixelState = Get-PublishedFileSnapshot -CurrentPath $pixelJsonPath -PublishedPath (Join-Path $validationRoot 'pixel-state.json')
        pixelStatePolicy = [ordered]@{
            status = 'passed'
            checkedFrameCount = [int]$pixelState.CheckedFrameCount
            failureCount = [int]$pixelState.FailureCount
            allowedConfiguredExcludedFailures = $allowedPixelFailures
            unexpectedFailureCount = $unexpectedPixelFailures.Count
        }
        deployment = [ordered]@{
            authorized = $false
            performed = $false
            imagePacks2Write = $false
            processOperation = $false
        }
    }
    $validationSummary | ConvertTo-Json -Depth 12 | Set-Content -LiteralPath $validationSummaryPath -Encoding UTF8

    Move-Item -LiteralPath $stagingValidation -Destination $validationRoot
    $publishedValidation = $true

    Write-Output "FinalOutput=$outputPath"
    Write-Output "OutputLength=$((Get-Item -LiteralPath $outputPath).Length)"
    Write-Output "OutputSha256=$((Get-FileHash -LiteralPath $outputPath -Algorithm SHA256).Hash)"
    Write-Output "BuildSummary=$summaryPath"
    Write-Output "ValidationDirectory=$validationRoot"
    Write-Output 'Deployment=not-authorized-not-performed'
}
finally {
    if (-not $publishedValidation -and (Test-Path -LiteralPath $stagingValidation)) {
        Remove-Item -LiteralPath $stagingValidation -Recurse -Force
    }
}

[CmdletBinding()]
param()

$ErrorActionPreference = 'Stop'

$themeRoot = Split-Path -Parent $PSScriptRoot
$professionRoot = Split-Path -Parent $themeRoot
$repoRoot = Split-Path -Parent $professionRoot
$illusionSlashPromptFileName = [string]::Concat([char]0x5E7B, [char]0x5F71, [char]0x5251, [char]0x821E, '.md')

function Resolve-ThemePath {
    param([Parameter(Mandatory = $true)][string]$RelativePath)

    return [IO.Path]::GetFullPath((Join-Path $themeRoot $RelativePath))
}

function Resolve-RepoPath {
    param([Parameter(Mandatory = $true)][string]$RelativePath)

    return [IO.Path]::GetFullPath((Join-Path $repoRoot $RelativePath))
}

function Get-ThemeRelativePath {
    param([Parameter(Mandatory = $true)][string]$Path)

    $fullPath = [IO.Path]::GetFullPath($Path)
    $fullRoot = [IO.Path]::GetFullPath($themeRoot).TrimEnd(
        [IO.Path]::DirectorySeparatorChar,
        [IO.Path]::AltDirectorySeparatorChar)
    $prefix = $fullRoot + [IO.Path]::DirectorySeparatorChar
    if ($fullPath.StartsWith($prefix, [StringComparison]::OrdinalIgnoreCase)) {
        return $fullPath.Substring($prefix.Length).Replace([IO.Path]::DirectorySeparatorChar, '/')
    }
    return $fullPath
}

function Read-JsonFile {
    param([Parameter(Mandatory = $true)][string]$Path)

    return Get-Content -LiteralPath $Path -Raw -Encoding UTF8 | ConvertFrom-Json
}

function Write-JsonNew {
    param(
        [Parameter(Mandatory = $true)][string]$Path,
        [Parameter(Mandatory = $true)]$Value,
        [int]$Depth = 12
    )

    if (Test-Path -LiteralPath $Path) {
        throw "Refusing to overwrite existing JSON: $Path"
    }
    $directory = Split-Path -Parent $Path
    if (-not [string]::IsNullOrWhiteSpace($directory)) {
        New-Item -ItemType Directory -Path $directory -Force | Out-Null
    }
    $json = $Value | ConvertTo-Json -Depth $Depth
    $json | Set-Content -LiteralPath $Path -Encoding UTF8
    [void](Read-JsonFile -Path $Path)
}

function Get-FileSnapshot {
    param([Parameter(Mandatory = $true)][string]$Path)

    $item = Get-Item -LiteralPath $Path
    return [ordered]@{
        path   = Get-ThemeRelativePath -Path $item.FullName
        length = $item.Length
        sha256 = (Get-FileHash -LiteralPath $item.FullName -Algorithm SHA256).Hash
    }
}

function Assert-ExistingFile {
    param([Parameter(Mandatory = $true)][string]$Path)

    if (-not (Test-Path -LiteralPath $Path -PathType Leaf)) {
        throw "Required file was not found: $Path"
    }
}

function Assert-NewFile {
    param([Parameter(Mandatory = $true)][string]$Path)

    if (Test-Path -LiteralPath $Path) {
        throw "Refusing to overwrite existing file: $Path"
    }
}

function Assert-EqualText {
    param(
        [Parameter(Mandatory = $true)][string]$Actual,
        [Parameter(Mandatory = $true)][string]$Expected,
        [Parameter(Mandatory = $true)][string]$Label
    )

    if ($Actual -cne $Expected) {
        throw "$Label mismatch. Actual='$Actual' Expected='$Expected'"
    }
}

function Assert-PassedText {
    param(
        [Parameter(Mandatory = $true)][string]$Actual,
        [Parameter(Mandatory = $true)][string]$Expected,
        [Parameter(Mandatory = $true)][string]$Label
    )

    if ($Actual -ne $Expected) {
        throw "$Label did not pass. Actual='$Actual' Expected='$Expected'"
    }
}

function Add-IntValue {
    param(
        [Parameter(Mandatory = $true)][hashtable]$Table,
        [Parameter(Mandatory = $true)][string]$Name,
        [Parameter(Mandatory = $true)]$Value
    )

    $Table[$Name] = [int]$Table[$Name] + [int]$Value
}

function Test-SetEquals {
    param(
        [Parameter(Mandatory = $true)][string[]]$Actual,
        [Parameter(Mandatory = $true)][string[]]$Expected,
        [Parameter(Mandatory = $true)][string]$Label
    )

    $actualSet = New-Object 'Collections.Generic.HashSet[string]' ([StringComparer]::OrdinalIgnoreCase)
    foreach ($value in $Actual) {
        if (-not $actualSet.Add($value)) {
            throw "$Label contains a duplicate value: $value"
        }
    }
    $expectedSet = New-Object 'Collections.Generic.HashSet[string]' ([StringComparer]::OrdinalIgnoreCase)
    foreach ($value in $Expected) {
        if (-not $expectedSet.Add($value)) {
            throw "$Label expected set contains a duplicate value: $value"
        }
    }
    if ($actualSet.Count -ne $expectedSet.Count) {
        throw "$Label count mismatch. Actual=$($actualSet.Count) Expected=$($expectedSet.Count)"
    }
    foreach ($value in $expectedSet) {
        if (-not $actualSet.Contains($value)) {
            throw "$Label missing value: $value"
        }
    }
}

function Get-ExpectedPromptBindingFiles {
    return [pscustomobject]@{
        ThemeAgent       = [IO.Path]::GetFullPath((Join-Path $themeRoot 'AGENTS.md'))
        ThemePrompt      = [IO.Path]::GetFullPath((Join-Path (Join-Path $themeRoot 'prompts') $illusionSlashPromptFileName))
        ProfessionPrompt = [IO.Path]::GetFullPath((Join-Path (Join-Path $professionRoot 'prompts') $illusionSlashPromptFileName))
    }
}

function Assert-PromptFileSnapshot {
    param(
        [Parameter(Mandatory = $true)]$Snapshot,
        [Parameter(Mandatory = $true)][string]$ExpectedPath,
        [Parameter(Mandatory = $true)][string]$Label
    )

    if ($null -eq $Snapshot) {
        throw "$Label prompt binding snapshot is missing."
    }
    $expectedItem = Get-Item -LiteralPath $ExpectedPath
    $actualPath = [IO.Path]::GetFullPath([string]$Snapshot.path)
    if (-not $actualPath.Equals($expectedItem.FullName, [StringComparison]::OrdinalIgnoreCase)) {
        throw "$Label prompt binding path mismatch. Actual='$actualPath' Expected='$($expectedItem.FullName)'"
    }
    if ([long]$Snapshot.length -ne $expectedItem.Length) {
        throw "$Label prompt binding length mismatch."
    }
    if ([string]$Snapshot.sha256 -ne (Get-FileHash -LiteralPath $expectedItem.FullName -Algorithm SHA256).Hash) {
        throw "$Label prompt binding SHA-256 mismatch."
    }
}

function Assert-PromptBindingSummary {
    param(
        [Parameter(Mandatory = $true)]$Summary,
        [Parameter(Mandatory = $true)][string]$ComponentId
    )

    $binding = $Summary.selection.promptBinding
    if ($null -eq $binding) {
        throw "$ComponentId promptBinding summary is missing."
    }
    if ([string]$binding.role -ne 'primary-skill-prompt' -or [int]$binding.priority -ne 1) {
        throw "$ComponentId promptBinding role or priority is invalid."
    }
    if ([string]$binding.uiFrameGeometryPolicy -ne 'strict-preserve-source-frame-position-size' -or
        [string]$binding.scope -ne 'illusionslash-only') {
        throw "$ComponentId promptBinding scope or geometry policy is invalid."
    }

    $expected = Get-ExpectedPromptBindingFiles
    Assert-PromptFileSnapshot -Snapshot $binding.themeAgent -ExpectedPath $expected.ThemeAgent -Label "$ComponentId theme AGENTS"
    Assert-PromptFileSnapshot -Snapshot $binding.themePrompt -ExpectedPath $expected.ThemePrompt -Label "$ComponentId theme prompt"
    Assert-PromptFileSnapshot -Snapshot $binding.professionPrompt -ExpectedPath $expected.ProfessionPrompt -Label "$ComponentId profession prompt"
}

function Invoke-CheckedPowerShell32 {
    param(
        [Parameter(Mandatory = $true)][string]$ScriptPath,
        [Parameter(Mandatory = $true)][string[]]$Arguments,
        [int[]]$AllowedExitCodes = @(0)
    )

    $powerShell32 = Join-Path $env:WINDIR 'SysWOW64\WindowsPowerShell\v1.0\powershell.exe'
    Assert-ExistingFile -Path $powerShell32
    $output = & $powerShell32 -NoProfile -ExecutionPolicy Bypass -File $ScriptPath @Arguments 2>&1
    $exitCode = $LASTEXITCODE
    $output | Write-Output
    if ($exitCode -notin $AllowedExitCodes) {
        throw "32-bit PowerShell script failed with exit code ${exitCode}: $ScriptPath"
    }
    return [pscustomobject]@{
        ExitCode = $exitCode
        Output   = $output
    }
}

$components = @(
    [pscustomobject]@{
        id        = 'illusionslash'
        config    = 'configs/custom-skill-v3-fix2/illusionslash.json'
        component = 'npk/custom-skill-v3-fix2/components/a_weaponmaster-vergil-dark-blue-illusionslash-v3-fix2.NPK'
        summary   = 'validation/custom-skill-v3-fix2/components/illusionslash/build-summary.json'
        include   = @(
            'sprite/character/swordman/effect/illusionslash/damage.img',
            'sprite/character/swordman/effect/illusionslash/illusionslashvp2beamswd.img',
            'sprite/character/swordman/effect/illusionslash/illusionslashvp2body.img',
            'sprite/character/swordman/effect/illusionslash/illusionslashvp2club.img',
            'sprite/character/swordman/effect/illusionslash/illusionslashvp2katana.img',
            'sprite/character/swordman/effect/illusionslash/illusionslashvp2lswd.img',
            'sprite/character/swordman/effect/illusionslash/illusionslashvp2sswd.img',
            'sprite/character/swordman/effect/illusionslash/particle.img',
            'sprite/character/swordman/effect/illusionslash/shot-front_shadow.img'
        )
    },
    [pscustomobject]@{
        id        = 'illusionslash_finish'
        config    = 'configs/custom-skill-v3-fix2/illusionslash_finish.json'
        component = 'npk/custom-skill-v3-fix2/components/a_weaponmaster-vergil-dark-blue-illusionslash_finish-v3-fix2.NPK'
        summary   = 'validation/custom-skill-v3-fix2/components/illusionslash_finish/build-summary.json'
        include   = @(
            'sprite/character/swordman/effect/illusionslash/finish/1_shockwave_dodge.img',
            'sprite/character/swordman/effect/illusionslash/finish/2_ground_dodge.img',
            'sprite/character/swordman/effect/illusionslash/finish/3_sword_dodge.img',
            'sprite/character/swordman/effect/illusionslash/finish/4_attackt_dodge.img',
            'sprite/character/swordman/effect/illusionslash/finish/5_light_dodge.img',
            'sprite/character/swordman/effect/illusionslash/finish/illusionslashspark03.img',
            'sprite/character/swordman/effect/illusionslash/finish/stone.img'
        )
    },
    [pscustomobject]@{
        id        = 'illusionslash_finish_sparkhead04_stable'
        config    = 'configs/custom-skill-v3-fix2/illusionslash_finish-sparkhead04-stable.json'
        component = 'npk/custom-skill-v3-fix2/components/a_weaponmaster-vergil-dark-blue-illusionslash_finish-sparkhead04-stable-v3-fix2.NPK'
        summary   = 'validation/custom-skill-v3-fix2/components/illusionslash_finish-sparkhead04-stable/build-summary.json'
        include   = @(
            'sprite/character/swordman/effect/illusionslash/finish/illusionslashsparkhead04.img'
        )
    }
)

$finalOutput = Resolve-ThemePath -RelativePath 'npk/custom-skill-v3-fix2/a_weaponmaster-vergil-dark-blue-custom-skill-v3-fix2.NPK'
$packageSummaryPath = Resolve-ThemePath -RelativePath 'validation/custom-skill-v3-fix2/package-summary.json'
$indexPath = Resolve-ThemePath -RelativePath 'validation/custom-skill-v3-fix2/independent-index.json'
$fullFrameDirectory = Resolve-ThemePath -RelativePath 'validation/custom-skill-v3-fix2/full-frame-validation'
$pixelRawPath = Resolve-ThemePath -RelativePath 'validation/custom-skill-v3-fix2/pixel-state-raw.json'
$pixelValidationPath = Resolve-ThemePath -RelativePath 'validation/custom-skill-v3-fix2/pixel-state-validation.json'
$validationSummaryPath = Resolve-ThemePath -RelativePath 'validation/custom-skill-v3-fix2/validation-summary.json'

Assert-NewFile -Path $finalOutput
Assert-NewFile -Path $packageSummaryPath
Assert-NewFile -Path $indexPath
Assert-NewFile -Path $pixelRawPath
Assert-NewFile -Path $pixelValidationPath
Assert-NewFile -Path $validationSummaryPath
if ((Test-Path -LiteralPath $fullFrameDirectory) -and @(Get-ChildItem -LiteralPath $fullFrameDirectory -Force).Count -ne 0) {
    throw "Full-frame validation directory must be empty: $fullFrameDirectory"
}

$allIncludePaths = New-Object 'Collections.Generic.List[string]'
$includeSet = New-Object 'Collections.Generic.HashSet[string]' ([StringComparer]::OrdinalIgnoreCase)
$componentNpks = New-Object 'Collections.Generic.List[string]'
$componentReports = New-Object 'Collections.Generic.List[object]'
$skippedFrameKeys = New-Object 'Collections.Generic.HashSet[string]' ([StringComparer]::OrdinalIgnoreCase)
$aggregateCounts = @{
    albums                   = 0
    frames                   = 0
    textures                 = 0
    eligibleTextures         = 0
    changedTextures          = 0
    skippedTextures          = 0
    changedBc1Textures       = 0
    changedBc3Textures       = 0
    changedColorBlocks       = 0
    explicitExcludedTextures = 0
    hiddenTextures           = 0
    linkedTextures           = 0
    transparentTextures      = 0
    nearBlackTextures        = 0
    noColorChangeTextures    = 0
    warmPreservedTextures    = 0
    visibleRgbChanges        = 0
    texdiagValidatedTextures = 0
}

foreach ($component in $components) {
    $componentPath = Resolve-ThemePath -RelativePath $component.component
    $summaryPath = Resolve-ThemePath -RelativePath $component.summary
    $configPath = Resolve-ThemePath -RelativePath $component.config
    Assert-ExistingFile -Path $componentPath
    Assert-ExistingFile -Path $summaryPath
    Assert-ExistingFile -Path $configPath

    foreach ($includePath in $component.include) {
        if ($includePath -notlike 'sprite/character/swordman/effect/illusionslash/*') {
            throw "Custom-skill-v3-fix2 may only include illusionslash IMG paths: $includePath"
        }
        if ($includePath -like '*cutin*' -or $includePath -like '*momentaryslash*') {
            throw "Custom-skill-v3-fix2 must not include Cut-in or momentaryslash paths: $includePath"
        }
        if (-not $includeSet.Add($includePath)) {
            throw "Duplicate custom-skill-v3-fix2 include path: $includePath"
        }
        $allIncludePaths.Add($includePath)
    }

    $summary = Read-JsonFile -Path $summaryPath
    Assert-PassedText -Actual ([string]$summary.status) -Expected 'passed' -Label "$($component.id) build status"
    Assert-PassedText -Actual ([string]$summary.validation.reopenedFromDisk) -Expected 'passed' -Label "$($component.id) reopenedFromDisk"
    Assert-PassedText -Actual ([string]$summary.validation.structureAndSharing) -Expected 'passed' -Label "$($component.id) structureAndSharing"
    Assert-PassedText -Actual ([string]$summary.validation.ddsHeaders) -Expected 'byte-identical' -Label "$($component.id) ddsHeaders"
    Assert-PassedText -Actual ([string]$summary.validation.bc3AlphaBlocks) -Expected 'byte-identical where applicable' -Label "$($component.id) bc3AlphaBlocks"
    Assert-PassedText -Actual ([string]$summary.validation.bc1TransparentMode) -Expected 'preserved per block where applicable' -Label "$($component.id) bc1TransparentMode"
    Assert-PassedText -Actual ([string]$summary.validation.authorizedDecodedAlpha) -Expected 'byte-identical' -Label "$($component.id) authorizedDecodedAlpha"
    Assert-PassedText -Actual ([string]$summary.validation.unauthorizedDecodedBgra) -Expected 'byte-identical' -Label "$($component.id) unauthorizedDecodedBgra"
    Assert-PassedText -Actual ([string]$summary.validation.texdiagPerTexture) -Expected 'passed' -Label "$($component.id) texdiagPerTexture"

    $actualComponentPath = [IO.Path]::GetFullPath([string]$summary.output.componentNpkPath)
    if (-not $actualComponentPath.Equals($componentPath, [StringComparison]::OrdinalIgnoreCase)) {
        throw "$($component.id) component path mismatch: $actualComponentPath / $componentPath"
    }
    $componentItem = Get-Item -LiteralPath $componentPath
    if ([long]$summary.output.length -ne $componentItem.Length) {
        throw "$($component.id) component length mismatch."
    }
    if ([string]$summary.output.sha256 -ne (Get-FileHash -LiteralPath $componentPath -Algorithm SHA256).Hash) {
        throw "$($component.id) component SHA-256 mismatch."
    }

    Test-SetEquals -Actual ([string[]]@($summary.selection.allowedImgPaths)) -Expected ([string[]]$component.include) -Label "$($component.id) allowedImgPaths"
    Assert-PromptBindingSummary -Summary $summary -ComponentId $component.id
    Assert-EqualText -Actual ([string]$summary.validation.framePositionAndSize) -Expected 'byte-identical Width/Height/X/Y' -Label "$($component.id) framePositionAndSize"
    Assert-EqualText -Actual ([string]$summary.validation.frameCanvasAndOffsets) -Expected 'byte-identical CanvasWidth/CanvasHeight/X/Y' -Label "$($component.id) frameCanvasAndOffsets"
    Assert-EqualText -Actual ([string]$summary.validation.atlasRectanglesAndRotation) -Expected 'byte-identical LeftUp/RightDown/Rotation/Unknown' -Label "$($component.id) atlasRectanglesAndRotation"
    Assert-EqualText -Actual ([string]$summary.validation.textureVersionAndIndexing) -Expected 'byte-identical TextureVersion/TextureIndex/Texture size' -Label "$($component.id) textureVersionAndIndexing"
    if ([int]$summary.counts.changedTextures -le 0) {
        throw "$($component.id) did not change any textures."
    }
    if ([int]$summary.counts.changedColorBlocks -le 0) {
        throw "$($component.id) did not change any BC color blocks."
    }

    $visibleChanges = 0
    foreach ($texture in @($summary.textures)) {
        if ([string]$texture.imgPath -notlike 'sprite/character/swordman/effect/illusionslash/*') {
            throw "$($component.id) texture is outside illusionslash scope: $($texture.imgPath)"
        }
        if ([string]$texture.decision -eq 'changed') {
            if ([int]$texture.changedColorBlocks -le 0) {
                throw "$($component.id) changed texture has no changed color blocks: $($texture.imgPath)#$($texture.textureIndex)"
            }
            if ([int]$texture.visibleRgbChanges -le 0) {
                throw "$($component.id) changed texture has no visible RGB changes: $($texture.imgPath)#$($texture.textureIndex)"
            }
            if ([string]$texture.sourceDdsSha256 -eq [string]$texture.outputDdsSha256) {
                throw "$($component.id) changed texture DDS hash did not change: $($texture.imgPath)#$($texture.textureIndex)"
            }
            Assert-EqualText -Actual ([string]$texture.outputAlphaSha256) -Expected ([string]$texture.sourceAlphaSha256) -Label "$($component.id) changed texture alpha hash"
            $visibleChanges += [int]$texture.visibleRgbChanges
        }
        elseif ([string]$texture.decision -eq 'skipped') {
            Assert-EqualText -Actual ([string]$texture.outputDdsSha256) -Expected ([string]$texture.sourceDdsSha256) -Label "$($component.id) skipped texture DDS hash"
            Assert-EqualText -Actual ([string]$texture.outputBgraSha256) -Expected ([string]$texture.sourceBgraSha256) -Label "$($component.id) skipped texture BGRA hash"
            Assert-EqualText -Actual ([string]$texture.outputAlphaSha256) -Expected ([string]$texture.sourceAlphaSha256) -Label "$($component.id) skipped texture alpha hash"
            foreach ($frameReference in @($texture.frameReferences)) {
                [void]$skippedFrameKeys.Add([string]$frameReference)
            }
        }
        else {
            throw "$($component.id) has an unknown texture decision: $($texture.decision)"
        }
    }
    if ($visibleChanges -le 0) {
        throw "$($component.id) visible RGB change total is zero."
    }

    foreach ($name in @(
            'albums', 'frames', 'textures', 'eligibleTextures', 'changedTextures', 'skippedTextures',
            'changedBc1Textures', 'changedBc3Textures', 'changedColorBlocks', 'explicitExcludedTextures',
            'hiddenTextures', 'linkedTextures', 'transparentTextures', 'nearBlackTextures',
            'noColorChangeTextures', 'warmPreservedTextures')) {
        Add-IntValue -Table $aggregateCounts -Name $name -Value $summary.counts.$name
    }
    Add-IntValue -Table $aggregateCounts -Name 'visibleRgbChanges' -Value $visibleChanges
    Add-IntValue -Table $aggregateCounts -Name 'texdiagValidatedTextures' -Value $summary.validation.texdiagValidatedTextures

    $componentReports.Add([ordered]@{
            id                      = $component.id
            config                  = $component.config
            path                    = $component.component
            buildSummary            = $component.summary
            selectedImgCount        = @($component.include).Count
            frameCount              = [int]$summary.counts.frames
            textureCount            = [int]$summary.counts.textures
            changedTextureCount     = [int]$summary.counts.changedTextures
            skippedTextureCount     = [int]$summary.counts.skippedTextures
            changedBc1TextureCount  = [int]$summary.counts.changedBc1Textures
            changedBc3TextureCount  = [int]$summary.counts.changedBc3Textures
            changedColorBlockCount  = [int]$summary.counts.changedColorBlocks
            visibleRgbChangeCount   = $visibleChanges
            promptBinding           = $summary.selection.promptBinding
            framePositionAndSize    = [string]$summary.validation.framePositionAndSize
            frameCanvasAndOffsets   = [string]$summary.validation.frameCanvasAndOffsets
            atlasRectanglesAndRotation = [string]$summary.validation.atlasRectanglesAndRotation
            textureVersionAndIndexing  = [string]$summary.validation.textureVersionAndIndexing
            ddsHeaders              = [string]$summary.validation.ddsHeaders
            bc3AlphaBlocks          = [string]$summary.validation.bc3AlphaBlocks
            bc1TransparentMode      = [string]$summary.validation.bc1TransparentMode
            authorizedDecodedAlpha  = [string]$summary.validation.authorizedDecodedAlpha
            unauthorizedDecodedBgra = [string]$summary.validation.unauthorizedDecodedBgra
            texdiag                 = [string]$summary.validation.texdiagPerTexture
        })
    $componentNpks.Add($componentPath)
}

$packager = Resolve-RepoPath -RelativePath 'tools/New-DnfCustomNpk.ps1'
$indexTool = Resolve-RepoPath -RelativePath 'tools/Test-DnfNpkIndex.ps1'
$exportTool = Resolve-RepoPath -RelativePath 'tools/Export-DnfNpkValidation.ps1'
$pixelTool = Resolve-RepoPath -RelativePath 'tools/Test-DnfNpkPixels.ps1'
foreach ($tool in @($packager, $indexTool, $exportTool, $pixelTool)) {
    Assert-ExistingFile -Path $tool
}

$packagerOutput = & $packager `
    -SourceNpk ([string[]]$componentNpks.ToArray()) `
    -IncludeImgPath ([string[]]$allIncludePaths.ToArray()) `
    -OutputPath $finalOutput `
    -SummaryPath $packageSummaryPath
$packagerOutput | Write-Output
Assert-ExistingFile -Path $finalOutput
Assert-ExistingFile -Path $packageSummaryPath
$packageSummary = Read-JsonFile -Path $packageSummaryPath
if ([int]$packageSummary.entryCount -ne $allIncludePaths.Count) {
    throw 'Package summary entry count mismatch.'
}
if ([string]$packageSummary.sha256 -ne (Get-FileHash -LiteralPath $finalOutput -Algorithm SHA256).Hash) {
    throw 'Package summary SHA-256 mismatch.'
}

$indexJsonLines = & $indexTool -Path $finalOutput -ExpectedEntryCount $allIncludePaths.Count -AsJson
$indexExitCode = $LASTEXITCODE
$indexText = ($indexJsonLines | Out-String).Trim()
if ($indexExitCode -ne 0) {
    throw "Independent NPK index failed with exit code $indexExitCode."
}
$indexText | Set-Content -LiteralPath $indexPath -Encoding UTF8
$index = $indexText | ConvertFrom-Json
if ([int]$index.EntryCount -ne $allIncludePaths.Count -or
    [int]$index.UniquePathCount -ne $allIncludePaths.Count -or
    $index.HeaderSha256Valid -ne $true -or
    [int]$index.ImgMagicValidCount -ne $allIncludePaths.Count) {
    throw 'Independent NPK index summary is not valid.'
}

[void](Invoke-CheckedPowerShell32 -ScriptPath $exportTool -Arguments @(
        '-InputFile', $finalOutput,
        '-OutputDirectory', $fullFrameDirectory,
        '-FramesPerPage', '64'
    ))
$albumInventoryPath = Join-Path $fullFrameDirectory 'album-inventory.json'
$frameInventoryPath = Join-Path $fullFrameDirectory 'frame-inventory.csv'
Assert-ExistingFile -Path $albumInventoryPath
Assert-ExistingFile -Path $frameInventoryPath
$albumInventory = Read-JsonFile -Path $albumInventoryPath
if ([int]$albumInventory.AlbumCount -ne $allIncludePaths.Count) {
    throw 'Full-frame album count mismatch.'
}
if ([int]$albumInventory.DecodedNonLinkFrames -le 0) {
    throw 'Full-frame validation decoded no frames.'
}

$pixelRun = Invoke-CheckedPowerShell32 -ScriptPath $pixelTool -AllowedExitCodes @(0, 2) -Arguments @(
    '-InputFile', $finalOutput,
    '-PathPattern', '^sprite/character/swordman/effect/illusionslash/',
    '-OutputFile', $pixelRawPath
)
Assert-ExistingFile -Path $pixelRawPath
$pixelRaw = Read-JsonFile -Path $pixelRawPath
$unexpectedTransparent = New-Object 'Collections.Generic.List[string]'
$unexpectedBlack = New-Object 'Collections.Generic.List[string]'
$expectedTransparent = New-Object 'Collections.Generic.List[string]'
$expectedBlack = New-Object 'Collections.Generic.List[string]'
foreach ($record in @($pixelRaw.Records)) {
    $frameKey = ([string]$record.ImgPath) + '#' + ([string]$record.FrameIndex)
    if ($record.FullyTransparent -eq $true) {
        if ($skippedFrameKeys.Contains($frameKey)) {
            $expectedTransparent.Add($frameKey)
        }
        else {
            $unexpectedTransparent.Add($frameKey)
        }
    }
    if ($record.AllVisiblePixelsBlack -eq $true -or $record.FullCanvasOpaqueBlack -eq $true) {
        if ($skippedFrameKeys.Contains($frameKey)) {
            $expectedBlack.Add($frameKey)
        }
        else {
            $unexpectedBlack.Add($frameKey)
        }
    }
}
if ($unexpectedTransparent.Count -ne 0 -or $unexpectedBlack.Count -ne 0) {
    throw "Unexpected pixel-state failures. Transparent=$($unexpectedTransparent.Count) Black=$($unexpectedBlack.Count)"
}

$pixelValidation = [ordered]@{
    schemaVersion                   = 1
    validatedAtUtc                  = [DateTime]::UtcNow.ToString('o')
    status                          = 'passed'
    input                           = Get-FileSnapshot -Path $finalOutput
    checkedFrameCount               = [int]$pixelRaw.CheckedFrameCount
    rawCheckerExitCode              = [int]$pixelRun.ExitCode
    expectedTransparentFrameCount   = $expectedTransparent.Count
    unexpectedTransparentFrameCount = $unexpectedTransparent.Count
    expectedBlackFrameCount         = $expectedBlack.Count
    unexpectedBlackFrameCount       = $unexpectedBlack.Count
    expectedTransparentFrameKeys    = [string[]]$expectedTransparent.ToArray()
    expectedBlackFrameKeys          = [string[]]$expectedBlack.ToArray()
    rawReportPath                   = Get-ThemeRelativePath -Path $pixelRawPath
    note                            = 'Raw checker exit 2 is accepted only when every transparent or black-frame finding belongs to a byte-identical skipped source-semantic texture.'
}
Write-JsonNew -Path $pixelValidationPath -Value $pixelValidation -Depth 8

$finalSnapshot = Get-FileSnapshot -Path $finalOutput
$summary = [ordered]@{
    schemaVersion  = 1
    generatedAtUtc = [DateTime]::UtcNow.ToString('o')
    status         = 'passed-offline-custom-skill-v3-fix2-client-pending'
    scope          = [ordered]@{
        profession                     = 'swordman-weaponmaster'
        themeId                        = 'weaponmaster-vergil-dark-blue'
        label                          = 'custom-skill-v3-fix2'
        pilotResource                  = 'illusionslash'
        fullSkillCoverageProven        = $false
        releaseMetadataAuthorized      = $false
        activeAsepriteFullSkillRelease = $false
        displayNameMappingStatus       = 'unverified-by-current-manifest'
        note                           = 'Partial skill candidate: v3 plus the missed body technical layer. The a_ filename is only a client loading order test candidate; offline validation does not prove client priority.'
    }
    artifact       = [ordered]@{
        path             = $finalSnapshot.path
        length           = $finalSnapshot.length
        sha256           = $finalSnapshot.sha256
        imgCount         = $allIncludePaths.Count
        frameCount       = [int]$albumInventory.FrameCount
        imgVersionCounts = $index.ImgVersionCounts
        deployed         = $false
    }
    components     = [object[]]$componentReports.ToArray()
    changes        = [ordered]@{
        endpointRecolorMode      = 'endpoint-level-no-png-texconv-reencode'
        targetTechnicalResource  = 'sprite/character/swordman/effect/illusionslash/*'
        promptDrivenAsepriteStatus = 'not-executed-endpoint-recolor-only'
        promptAsepriteMainPipelineComplete = $false
        includedImgCount         = $allIncludePaths.Count
        changedTextureCount      = [int]$aggregateCounts.changedTextures
        skippedTextureCount      = [int]$aggregateCounts.skippedTextures
        changedBc1TextureCount   = [int]$aggregateCounts.changedBc1Textures
        changedBc3TextureCount   = [int]$aggregateCounts.changedBc3Textures
        changedColorBlockCount   = [int]$aggregateCounts.changedColorBlocks
        visibleRgbChangeCount    = [int]$aggregateCounts.visibleRgbChanges
        addedAfterV3             = 'one verified body technical layer from the fix2 component config'
        excludedCutin            = $true
        excludedMomentaryslash   = $true
        clientLoadingOrderProven = $false
    }
    preservation   = [ordered]@{
        endpointStructureAndSharing     = 'passed'
        endpointDdsHeaders              = 'byte-identical'
        endpointColorSelectorBits       = 'byte-identical per changed BC block'
        endpointBc3AlphaBlocks          = 'byte-identical where applicable'
        endpointBc1TransparentMode      = 'preserved per block where applicable'
        endpointAuthorizedDecodedAlpha  = 'byte-identical'
        endpointUnauthorizedDecodedBgra = 'byte-identical'
        endpointTexdiag                 = 'passed'
        texdiagValidatedTextures        = [int]$aggregateCounts.texdiagValidatedTextures
        finalPayloadEquivalence         = 'passed'
        sourceFrameGeometryPreserved    = 'passed-by-builder-structure-gate-and-full-frame-inventory'
    }
    validation     = [ordered]@{
        independentFinalIndex     = [ordered]@{
            status             = 'passed'
            entryCount         = [int]$index.EntryCount
            uniquePathCount    = [int]$index.UniquePathCount
            headerSha256Valid  = $index.HeaderSha256Valid
            imgMagicValidCount = [int]$index.ImgMagicValidCount
            evidence           = Get-ThemeRelativePath -Path $indexPath
        }
        packagePayloadEquivalence = [ordered]@{
            status             = 'passed'
            comparedEntryCount = [int]$packageSummary.entryCount
            evidence           = Get-ThemeRelativePath -Path $packageSummaryPath
        }
        fullFrame                 = [ordered]@{
            status               = 'passed'
            albumCount           = [int]$albumInventory.AlbumCount
            frameCount           = [int]$albumInventory.FrameCount
            decodedNonLinkFrames = [int]$albumInventory.DecodedNonLinkFrames
            linkFrames           = [int]$albumInventory.LinkFrames
            hiddenFrames         = [int]$albumInventory.HiddenFrames
            backgrounds          = @('black', 'white', 'checkerboard')
            contactSheetCount    = [int]$albumInventory.SheetCount
            albumInventory       = Get-ThemeRelativePath -Path $albumInventoryPath
            frameInventory       = Get-ThemeRelativePath -Path $frameInventoryPath
        }
        pixelState                = [ordered]@{
            status                          = 'passed'
            checkedFrameCount               = [int]$pixelRaw.CheckedFrameCount
            expectedTransparentFrameCount   = $expectedTransparent.Count
            unexpectedTransparentFrameCount = $unexpectedTransparent.Count
            expectedBlackFrameCount         = $expectedBlack.Count
            unexpectedBlackFrameCount       = $unexpectedBlack.Count
            evidence                        = Get-ThemeRelativePath -Path $pixelValidationPath
        }
        qualitySpecific           = [ordered]@{
            status                            = 'passed'
            noPngOrTexconvReencode            = $true
            changedColorBlocksGreaterThanZero = ([int]$aggregateCounts.changedColorBlocks -gt 0)
            visibleRgbChangesGreaterThanZero  = ([int]$aggregateCounts.visibleRgbChanges -gt 0)
            selectorPreservation              = 'passed-by-builder-hard-gate'
            alphaPreservation                 = 'passed-by-alpha-hash-and-BC3-block-gates'
            sourceFrameGeometryPreserved      = 'passed'
        }
        contactSheetReview        = [ordered]@{
            automatedOrAssistantScreening = 'not-human-review'
            humanManualReview             = 'pending'
            note                          = 'Contact sheets are generated for review; this partial package does not create formal DAG manual-review approval.'
        }
    }
    evidence       = @(
        Get-FileSnapshot -Path $packageSummaryPath
        Get-FileSnapshot -Path $indexPath
        Get-FileSnapshot -Path $pixelRawPath
        Get-FileSnapshot -Path $pixelValidationPath
        Get-FileSnapshot -Path $albumInventoryPath
        Get-FileSnapshot -Path $frameInventoryPath
        Get-FileSnapshot -Path (Resolve-RepoPath -RelativePath 'tools/New-DnfCustomNpk.ps1')
        Get-FileSnapshot -Path (Resolve-RepoPath -RelativePath 'tools/Test-DnfNpkIndex.ps1')
        Get-FileSnapshot -Path (Resolve-RepoPath -RelativePath 'tools/Export-DnfNpkValidation.ps1')
        Get-FileSnapshot -Path (Resolve-RepoPath -RelativePath 'tools/Test-DnfNpkPixels.ps1')
        Get-FileSnapshot -Path (Resolve-ThemePath -RelativePath 'tools/Build-VergilVer5DdsRecolor.ps1')
        Get-FileSnapshot -Path (Resolve-ThemePath -RelativePath 'tools/Build-VergilVer5DdsRecolor.cs')
        Get-FileSnapshot -Path (Resolve-ThemePath -RelativePath 'tools/New-VergilCustomSkillV3Fix2.ps1')
    )
    deployment     = [ordered]@{
        performed = $false
        status    = 'not-authorized-not-performed'
    }
    pending        = @(
        'Target client A/B loading and visual review remain user-side pending.',
        'The endpoint recolor candidate only proves low-level DDS endpoint changes plus prompt/reference binding; it has not executed the large-model plus Aseprite redraw pipeline.',
        'This package is not a full-skill release and does not authorize manifest or release metadata promotion.',
        'Display-name mapping remains unverified by the active manifest; the technical resource scope is illusionslash IMG paths only.',
        'The a_ filename is a loading order test candidate only; client priority is not proven by offline validation.'
    )
}

Write-JsonNew -Path $validationSummaryPath -Value $summary -Depth 12
Write-Output "FinalOutput=$finalOutput"
Write-Output "OutputLength=$($finalSnapshot.length)"
Write-Output "OutputSha256=$($finalSnapshot.sha256)"
Write-Output "ValidationSummary=$validationSummaryPath"
Write-Output 'Deployment=not-authorized-not-performed'

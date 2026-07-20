[CmdletBinding()]
param(
    [string]$OutputFile
)

$ErrorActionPreference = 'Stop'

$themeRoot = Split-Path -Parent $PSScriptRoot
$professionRoot = Split-Path -Parent $themeRoot
$jobsRoot = Split-Path -Parent $professionRoot
$repoRoot = Split-Path -Parent $jobsRoot
$packager = Join-Path $repoRoot 'tools\New-DnfCustomNpk.ps1'
$cutinComponent = Join-Path $themeRoot 'npk\cutin-weaponmaster-neo-v2\sprite_character_swordman_effect_cutin.NPK'
$momentarySlashComponent = Join-Path $themeRoot 'npk\vergil-momentaryslash-pilot-v1.NPK'
$validationRoot = Join-Path $themeRoot 'validation\progress-v1'

if ([string]::IsNullOrWhiteSpace($OutputFile)) {
    $OutputFile = Join-Path $themeRoot 'npk\progress-v1\!weaponmaster_vergil_darkblue_progress_v1.NPK'
}
$outputPath = [IO.Path]::GetFullPath($OutputFile)

foreach ($requiredFile in @($packager, $cutinComponent, $momentarySlashComponent)) {
    if (-not (Test-Path -LiteralPath $requiredFile -PathType Leaf)) {
        throw "Required file was not found: $requiredFile"
    }
}

$include = @(
    'sprite/character/swordman/effect/cutin/cutin_weaponmaster_neo.img',
    'sprite/character/swordman/effect/momentaryslash/drawingsword_blue_ldodge_under.img',
    'sprite/character/swordman/effect/momentaryslash/drawingsword_blue_ldodge_upper.img',
    'sprite/character/swordman/effect/momentaryslash/drawingsword_none_under.img',
    'sprite/character/swordman/effect/momentaryslash/drawingsword_none_upper.img',
    'sprite/character/swordman/effect/momentaryslash/drawingsword_red_ldodge_under.img',
    'sprite/character/swordman/effect/momentaryslash/drawingsword_red_ldodge_upper.img',
    'sprite/character/swordman/effect/momentaryslash/drawingsword_white_ldodge_under.img',
    'sprite/character/swordman/effect/momentaryslash/drawingsword_white_ldodge_upper.img'
)

New-Item -ItemType Directory -Path $validationRoot -Force | Out-Null
$packageJson = & $packager `
    -SourceNpk @($cutinComponent, $momentarySlashComponent) `
    -IncludeImgPath $include `
    -OutputPath $outputPath
if ($null -ne $LASTEXITCODE -and $LASTEXITCODE -ne 0) {
    throw "Custom NPK packaging failed with exit code $LASTEXITCODE."
}
$package = $packageJson | ConvertFrom-Json

$summary = [ordered]@{
    generatedAt = (Get-Date).ToString('o')
    status = 'offline-package-created-validation-pending'
    scope = [ordered]@{
        label = 'progress-v1'
        completedComponents = @('third-awakening cut-in', 'momentaryslash technical-resource pilot')
        completedPromptCount = 1
        technicalPilotCount = 1
        fullSkillCoverage = $false
        note = 'This is a progress preview, not the requested final 16-item package.'
    }
    package = $package
    deployment = [ordered]@{
        authorizedByCurrentUser = $true
        performed = $false
    }
}
$summaryPath = Join-Path $validationRoot 'package-summary.json'
$summary | ConvertTo-Json -Depth 10 | Set-Content -LiteralPath $summaryPath -Encoding UTF8

Write-Output "Output=$($package.output)"
Write-Output "Length=$($package.length)"
Write-Output "Sha256=$($package.sha256)"
Write-Output "EntryCount=$($package.entryCount)"
Write-Output "Summary=$summaryPath"
Write-Output 'FullSkillCoverage=false'

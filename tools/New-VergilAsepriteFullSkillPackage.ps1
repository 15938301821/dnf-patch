[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)]
    [string]$ResourcePlanPath,

    [Parameter(Mandatory = $true)]
    [string]$OutputNpk,

    [Parameter(Mandatory = $true)]
    [string]$PackageSummaryPath,

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

function Test-Property {
    param([object]$Object, [string]$Name)

    return $null -ne $Object -and $null -ne $Object.PSObject.Properties[$Name]
}

function Resolve-PathValue {
    param([string]$Value, [string]$BaseDirectory, [string]$Label)

    Assert-Condition (-not [string]::IsNullOrWhiteSpace($Value)) "$Label path is empty."
    $native = $Value.Replace('/', [IO.Path]::DirectorySeparatorChar)
    if (-not [IO.Path]::IsPathRooted($native)) {
        $native = Join-Path $BaseDirectory $native
    }
    return [IO.Path]::GetFullPath($native)
}

function Assert-PathInside {
    param([string]$Path, [string]$Root, [string]$Label)

    $normalizedRoot = [IO.Path]::GetFullPath($Root).TrimEnd(
        [IO.Path]::DirectorySeparatorChar,
        [IO.Path]::AltDirectorySeparatorChar)
    $prefix = $normalizedRoot + [IO.Path]::DirectorySeparatorChar
    Assert-Condition ($Path.StartsWith($prefix, [StringComparison]::OrdinalIgnoreCase)) `
        "$Label must stay inside '$normalizedRoot': $Path"
}

function Resolve-ExistingFile {
    param([string]$Value, [string]$BaseDirectory, [string]$Label)

    $path = Resolve-PathValue -Value $Value -BaseDirectory $BaseDirectory -Label $Label
    Assert-Condition (Test-Path -LiteralPath $path -PathType Leaf) "$Label was not found: $path"
    $path = (Resolve-Path -LiteralPath $path).Path
    Assert-PathInside -Path $path -Root $script:RepositoryRoot -Label $Label
    return $path
}

function Assert-Snapshot {
    param([object]$Snapshot, [string]$BaseDirectory, [string]$Label)

    Assert-Condition ($null -ne $Snapshot) "$Label snapshot is missing."
    foreach ($name in @('path', 'length', 'sha256')) {
        Assert-Condition (Test-Property -Object $Snapshot -Name $name) `
            "$Label snapshot is missing '$name'."
    }
    $path = Resolve-ExistingFile -Value ([string]$Snapshot.path) `
        -BaseDirectory $BaseDirectory -Label $Label
    $item = Get-Item -LiteralPath $path
    $hash = (Get-FileHash -LiteralPath $path -Algorithm SHA256).Hash
    $expectedHash = ([string]$Snapshot.sha256).Trim().ToUpperInvariant()
    Assert-Condition ($expectedHash -match '^[0-9A-F]{64}$') `
        "$Label expected SHA-256 is invalid."
    Assert-Condition ($item.Length -eq [long]$Snapshot.length) `
        "$Label length changed: actual=$($item.Length) expected=$($Snapshot.length)"
    Assert-Condition ($hash -eq $expectedHash) `
        "$Label SHA-256 changed: actual=$hash expected=$expectedHash"
    return [pscustomobject]@{
        path = $path
        length = [long]$item.Length
        sha256 = $hash
    }
}

function New-StringSet {
    param([object[]]$Values, [string]$Label)

    $set = New-Object 'Collections.Generic.HashSet[string]' ([StringComparer]::OrdinalIgnoreCase)
    foreach ($value in @($Values)) {
        $text = ([string]$value).Trim().Replace('\', '/')
        Assert-Condition (-not [string]::IsNullOrWhiteSpace($text)) "$Label contains an empty value."
        Assert-Condition $set.Add($text) "$Label contains a duplicate value: $text"
    }
    return ,$set
}

function Assert-NoDeployment {
    param([object]$Deployment, [string]$Label)

    Assert-Condition ($null -ne $Deployment) "$Label deployment record is missing."
    if ($Deployment -is [string]) {
        Assert-Condition (([string]$Deployment) -match '(?i)not[- ](?:authorized|performed)') `
            "$Label records an unsafe deployment state: $Deployment"
        return
    }
    foreach ($name in @('authorized', 'performed')) {
        Assert-Condition (Test-Property -Object $Deployment -Name $name) `
            "$Label deployment.$name is missing."
        Assert-Condition ($Deployment.PSObject.Properties[$name].Value -eq $false) `
            "$Label deployment.$name must be false."
    }
    foreach ($name in @('imagePacks2Write', 'processOperation')) {
        if (Test-Property -Object $Deployment -Name $name) {
            Assert-Condition ($Deployment.PSObject.Properties[$name].Value -eq $false) `
                "$Label deployment.$name must be false."
        }
    }
}

$defaultRoot = Split-Path -Parent $PSScriptRoot
$script:RepositoryRoot = if ([string]::IsNullOrWhiteSpace($RepoRoot)) {
    (Resolve-Path -LiteralPath $defaultRoot).Path
}
else {
    (Resolve-Path -LiteralPath $RepoRoot).Path
}
$planPath = Resolve-ExistingFile -Value $ResourcePlanPath -BaseDirectory $script:RepositoryRoot `
    -Label 'Aseprite migration resource plan'
$plan = Get-Content -LiteralPath $planPath -Raw -Encoding UTF8 | ConvertFrom-Json
Assert-Condition ([int]$plan.schemaVersion -eq 1) 'Unsupported resource-plan schemaVersion.'
Assert-Condition ([string]$plan.themeId -eq 'weaponmaster-vergil-dark-blue') `
    'Unexpected resource-plan theme identity.'
Assert-Condition ($plan.coverage.fullSkillCoverageProven -eq $false) `
    'Resource plan must remain pre-release.'
Assert-NoDeployment -Deployment $plan.deployment -Label 'Resource plan'

$migrationValidator = Join-Path $script:RepositoryRoot 'tools\Test-VergilAsepriteMigrationPlan.ps1'
$migrationText = (& $migrationValidator -ResourcePlanPath $planPath `
    -RepoRoot $script:RepositoryRoot -AsJson | Out-String).Trim()
Assert-Condition (-not [string]::IsNullOrWhiteSpace($migrationText)) `
    'Migration readiness gate returned no JSON.'
$migration = $migrationText | ConvertFrom-Json
Assert-Condition ([string]$migration.status -eq 'passed') 'Migration readiness gate did not pass.'
Assert-Condition ([string]$migration.state -eq 'ready-for-aggregation') `
    'Migration readiness state is not ready-for-aggregation.'
Assert-Condition ($migration.readyForAggregation -eq $true) `
    'Migration readiness gate did not authorize aggregation.'
Assert-Condition ($migration.fullSkillCoverageProven -eq $false) `
    'Migration readiness gate cannot prove full coverage.'
Assert-Condition ([int]$migration.components.count -eq 31 -and
    [int]$migration.components.selectedImgCount -eq 417 -and
    [int]$migration.components.provenanceIssueCount -eq 0) `
    'Migration component readiness totals changed.'
Assert-Condition ($migration.cutin.renderValidated -eq $true -and
    $migration.cutin.manualReviewValidated -eq $true -and
    $migration.cutin.buildValidated -eq $true) `
    'Active Cut-in evidence is incomplete.'
Assert-NoDeployment -Deployment $migration.deployment -Label 'Migration readiness gate'

$baselineSnapshot = Assert-Snapshot -Snapshot $plan.baselinePlan `
    -BaseDirectory $script:RepositoryRoot -Label 'Baseline resource plan'
$baseline = Get-Content -LiteralPath $baselineSnapshot.path -Raw -Encoding UTF8 | ConvertFrom-Json
Assert-Condition ([string]$baseline.planId -eq [string]$plan.baselinePlan.planId) `
    'Baseline resource-plan identity changed.'
Assert-Condition ($baseline.coverage.fullSkillCoverageProven -eq $false) `
    'Baseline resource plan must remain pre-release.'
Assert-NoDeployment -Deployment $baseline.deployment -Label 'Baseline resource plan'

$selectedComponents = @($baseline.components | Where-Object { $_.selectedForAggregation -eq $true })
Assert-Condition ($selectedComponents.Count -eq 31) `
    "Expected 31 selected components, found $($selectedComponents.Count)."
$expectedComponentIds = New-StringSet -Values @($plan.baselineComponents.selectedComponentIds) `
    -Label 'Migration component ids'
$actualComponentIds = New-StringSet -Values @($selectedComponents | ForEach-Object { $_.id }) `
    -Label 'Baseline component ids'
Assert-Condition ($expectedComponentIds.SetEquals($actualComponentIds)) `
    'Migration and baseline selected component ids differ.'

$componentSources = New-Object 'Collections.Generic.List[string]'
$componentReports = New-Object 'Collections.Generic.List[object]'
$selectedImgPaths = New-Object 'Collections.Generic.HashSet[string]' ([StringComparer]::OrdinalIgnoreCase)
foreach ($component in $selectedComponents) {
    $componentId = [string]$component.id
    $componentSnapshot = Assert-Snapshot -Snapshot $component.validatedArtifact.componentNpk `
        -BaseDirectory $script:RepositoryRoot -Label "Component NPK $componentId"
    Assert-Condition (-not $componentSources.Contains($componentSnapshot.path)) `
        "Component NPK path is duplicated: $($componentSnapshot.path)"
    $componentSources.Add($componentSnapshot.path)
    $componentPaths = New-StringSet -Values @($component.selectedImgPaths) `
        -Label "Component IMG paths $componentId"
    foreach ($imgPath in $componentPaths) {
        Assert-Condition $selectedImgPaths.Add($imgPath) `
            "More than one component owns IMG path: $imgPath"
    }
    $componentReports.Add([pscustomobject]@{
        id = $componentId
        selectedImgCount = $componentPaths.Count
        sourceNpk = $componentSnapshot
    })
}
Assert-Condition ($componentSources.Count -eq 31 -and $selectedImgPaths.Count -eq 417) `
    "Component aggregation totals changed: sources=$($componentSources.Count) imgs=$($selectedImgPaths.Count)"

$buildPath = Resolve-ExistingFile -Value ([string]$plan.activeCutin.evidence.buildSummaryPath) `
    -BaseDirectory $script:RepositoryRoot -Label 'Active Cut-in build summary'
$build = Get-Content -LiteralPath $buildPath -Raw -Encoding UTF8 | ConvertFrom-Json
Assert-Condition ([string]$build.runId -eq [string]$plan.activeCutin.runId -and
    [string]$build.status -eq 'passed' -and $build.fullSkillCoverageProven -eq $false) `
    'Active Cut-in build identity or status changed.'
Assert-NoDeployment -Deployment $build.deployment -Label 'Active Cut-in build'
$cutinSnapshot = Assert-Snapshot -Snapshot $build.outputNpk `
    -BaseDirectory $script:RepositoryRoot -Label 'Active Cut-in component'
$targetImg = ([string]$plan.activeCutin.targetImg).Trim().Replace('\', '/')
Assert-Condition (([string]$build.targetImg).Trim().Replace('\', '/') -ieq $targetImg) `
    'Active Cut-in target IMG changed.'
Assert-Condition $selectedImgPaths.Add($targetImg) `
    'Active Cut-in target overlaps a selected component IMG.'
Assert-Condition (-not $componentSources.Contains($cutinSnapshot.path)) `
    'Active Cut-in source overlaps a selected component source.'

$outputPath = Resolve-PathValue -Value $OutputNpk -BaseDirectory $script:RepositoryRoot `
    -Label 'Final Aseprite NPK'
$summaryPath = Resolve-PathValue -Value $PackageSummaryPath -BaseDirectory $script:RepositoryRoot `
    -Label 'Aseprite package summary'
Assert-PathInside -Path $outputPath -Root $script:RepositoryRoot -Label 'Final Aseprite NPK'
Assert-PathInside -Path $summaryPath -Root $script:RepositoryRoot -Label 'Aseprite package summary'
$themeRoot = Split-Path -Parent (Split-Path -Parent (Split-Path -Parent $planPath))
Assert-PathInside -Path $outputPath -Root $themeRoot -Label 'Final Aseprite NPK'
Assert-PathInside -Path $summaryPath -Root $themeRoot -Label 'Aseprite package summary'
Assert-Condition ([IO.Path]::GetExtension($outputPath) -ieq '.NPK') `
    'Final Aseprite artifact must use the .NPK extension.'
Assert-Condition ([IO.Path]::GetExtension($summaryPath) -ieq '.json') `
    'Aseprite package summary must use the .json extension.'
foreach ($record in @(
    [pscustomobject]@{ name = [IO.Path]::GetFileName($outputPath); label = 'Final NPK' },
    [pscustomobject]@{ name = [IO.Path]::GetFileName($summaryPath); label = 'Package summary' })) {
    Assert-Condition ($record.name -match '(?i)aseprite') `
        "$($record.label) name must identify the Aseprite activity: $($record.name)"
    Assert-Condition ($record.name -match '(?i)(?:^|[-_])v[0-9]+(?:[-_.]|$)') `
        "$($record.label) name must contain a version token: $($record.name)"
}
Assert-Condition (-not (Test-Path -LiteralPath $outputPath)) `
    "Refusing to overwrite the final NPK: $outputPath"
Assert-Condition (-not (Test-Path -LiteralPath $summaryPath)) `
    "Refusing to overwrite the package summary: $summaryPath"

$sourcePaths = @($componentSources.ToArray()) + @($cutinSnapshot.path)
$includePaths = @($selectedImgPaths | Sort-Object)
$packagerPath = Join-Path $script:RepositoryRoot 'tools\New-DnfCustomNpk.ps1'
$packageText = (& $packagerPath -SourceNpk $sourcePaths -IncludeImgPath $includePaths `
    -OutputPath $outputPath -SummaryPath $summaryPath | Out-String).Trim()
Assert-Condition (-not [string]::IsNullOrWhiteSpace($packageText)) 'Packager returned no JSON.'
$package = $packageText | ConvertFrom-Json
Assert-Condition ([int]$package.schemaVersion -eq 1 -and [int]$package.entryCount -eq 418) `
    'Packager result entry count changed.'
Assert-Condition (@($package.sources).Count -eq 32 -and @($package.entries).Count -eq 418) `
    'Packager source or entry totals changed.'
Assert-Condition ([string]$package.output -ieq $outputPath -and
    [string]$package.packageSummaryPath -ieq $summaryPath) `
    'Packager output paths differ from the requested paths.'
Assert-Condition ([string]$package.deployment -eq 'not-performed-by-packager') `
    'Packager deployment state changed.'
$outputItem = Get-Item -LiteralPath $outputPath
$summaryItem = Get-Item -LiteralPath $summaryPath
$outputHash = (Get-FileHash -LiteralPath $outputPath -Algorithm SHA256).Hash
$summaryHash = (Get-FileHash -LiteralPath $summaryPath -Algorithm SHA256).Hash
Assert-Condition ($outputItem.Length -eq [long]$package.length -and
    $outputHash -eq ([string]$package.sha256).ToUpperInvariant()) `
    'Published NPK differs from the packager result.'

$result = [pscustomobject]@{
    schemaVersion = 1
    status = 'passed'
    state = 'aggregated-awaiting-final-validation'
    resourcePlan = $planPath
    planId = [string]$plan.planId
    readiness = [pscustomobject]@{
        status = 'passed'
        readyForAggregation = $true
        fullSkillCoverageProven = $false
    }
    artifact = [pscustomobject]@{
        path = $outputPath
        length = [long]$outputItem.Length
        sha256 = $outputHash
        imgCount = 418
    }
    packageSummary = [pscustomobject]@{
        path = $summaryPath
        length = [long]$summaryItem.Length
        sha256 = $summaryHash
        entryCount = 418
        sourceNpkCount = 32
    }
    counts = [pscustomobject]@{
        componentCount = 31
        componentImgCount = 417
        activeCutinImgCount = 1
        finalImgCount = 418
        sourceNpkCount = 32
    }
    components = $componentReports.ToArray()
    deployment = [pscustomobject]@{
        authorized = $false
        performed = $false
        imagePacks2Write = $false
        processOperation = $false
    }
}
if ($AsJson) {
    $result | ConvertTo-Json -Depth 10
}
else {
    $result
}

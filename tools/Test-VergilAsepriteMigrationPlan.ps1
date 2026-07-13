[CmdletBinding()]
param(
    [string]$ResourcePlanPath,

    [string]$RepoRoot,

    [switch]$AsJson
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

function Assert-Condition {
    param([bool]$Condition, [string]$Message)

    if (-not $Condition) {
        throw $Message
    }
}

function Resolve-RepoPath {
    param([string]$RepositoryRoot, [string]$Value)

    $native = $Value.Replace('/', [IO.Path]::DirectorySeparatorChar)
    if (-not [IO.Path]::IsPathRooted($native)) {
        $native = Join-Path $RepositoryRoot $native
    }
    return [IO.Path]::GetFullPath($native)
}

function Test-ObjectProperty {
    param([object]$Object, [string]$Name)

    return $null -ne $Object -and $null -ne $Object.PSObject.Properties[$Name]
}

function Test-PathInsideRepository {
    param([string]$RepositoryRoot, [string]$Path)

    $root = [IO.Path]::GetFullPath($RepositoryRoot).TrimEnd(
        [IO.Path]::DirectorySeparatorChar,
        [IO.Path]::AltDirectorySeparatorChar)
    $prefix = $root + [IO.Path]::DirectorySeparatorChar
    return $Path.StartsWith($prefix, [StringComparison]::OrdinalIgnoreCase)
}

function Get-SnapshotValidation {
    param(
        [string]$RepositoryRoot,
        [object]$Snapshot,
        [string]$Label
    )

    $result = [ordered]@{
        label = $Label
        passed = $false
        status = 'invalid-snapshot'
        path = $null
        expectedLength = $null
        actualLength = $null
        expectedSha256 = $null
        actualSha256 = $null
    }
    foreach ($name in @('path', 'length', 'sha256')) {
        if (-not (Test-ObjectProperty -Object $Snapshot -Name $name)) {
            $result.status = "missing-$name"
            return [pscustomobject]$result
        }
    }

    try {
        $path = Resolve-RepoPath -RepositoryRoot $RepositoryRoot -Value ([string]$Snapshot.path)
    }
    catch {
        $result.status = 'invalid-path'
        return [pscustomobject]$result
    }
    $result.path = $path
    $result.expectedLength = [long]$Snapshot.length
    $result.expectedSha256 = ([string]$Snapshot.sha256).ToUpperInvariant()
    if (-not (Test-PathInsideRepository -RepositoryRoot $RepositoryRoot -Path $path)) {
        $result.status = 'outside-repository'
        return [pscustomobject]$result
    }
    if (-not (Test-Path -LiteralPath $path -PathType Leaf)) {
        $result.status = 'missing-file'
        return [pscustomobject]$result
    }
    if ($result.expectedSha256 -notmatch '^[0-9A-F]{64}$') {
        $result.status = 'invalid-expected-sha256'
        return [pscustomobject]$result
    }

    $item = Get-Item -LiteralPath $path
    $actualHash = (Get-FileHash -LiteralPath $path -Algorithm SHA256).Hash
    $result.actualLength = [long]$item.Length
    $result.actualSha256 = $actualHash
    $lengthMatches = $item.Length -eq [long]$Snapshot.length
    $hashMatches = $actualHash -eq $result.expectedSha256
    if ($lengthMatches -and $hashMatches) {
        $result.passed = $true
        $result.status = 'passed'
    }
    elseif (-not $lengthMatches -and -not $hashMatches) {
        $result.status = 'length-and-sha256-drift'
    }
    elseif (-not $lengthMatches) {
        $result.status = 'length-drift'
    }
    else {
        $result.status = 'sha256-drift'
    }
    return [pscustomobject]$result
}

function Assert-FileSnapshot {
    param(
        [string]$RepositoryRoot,
        [object]$Snapshot,
        [string]$Label
    )

    $path = Resolve-RepoPath -RepositoryRoot $RepositoryRoot -Value ([string]$Snapshot.path)
    Assert-Condition (Test-Path -LiteralPath $path -PathType Leaf) "$Label was not found: $path"
    $item = Get-Item -LiteralPath $path
    Assert-Condition ($item.Length -eq [long]$Snapshot.length) `
        "$Label length changed: actual=$($item.Length) expected=$($Snapshot.length)"
    $actualHash = (Get-FileHash -LiteralPath $path -Algorithm SHA256).Hash
    $expectedHash = ([string]$Snapshot.sha256).ToUpperInvariant()
    Assert-Condition ($actualHash -eq $expectedHash) `
        "$Label SHA-256 changed: actual=$actualHash expected=$expectedHash"
    return $path
}

function Get-StringSet {
    param([object[]]$Values)

    $set = New-Object 'System.Collections.Generic.HashSet[string]' ([StringComparer]::Ordinal)
    foreach ($value in @($Values)) {
        Assert-Condition (-not [string]::IsNullOrWhiteSpace([string]$value)) 'A required string set contains an empty value.'
        Assert-Condition ($set.Add([string]$value)) "A required string set contains a duplicate: $value"
    }
    return ,$set
}

function Assert-SetEqual {
    param(
        [System.Collections.Generic.HashSet[string]]$Expected,
        [System.Collections.Generic.HashSet[string]]$Actual,
        [string]$Label
    )

    $missing = @($Expected | Where-Object { -not $Actual.Contains($_) } | Sort-Object)
    $unexpected = @($Actual | Where-Object { -not $Expected.Contains($_) } | Sort-Object)
    Assert-Condition ($missing.Count -eq 0 -and $unexpected.Count -eq 0) `
        "$Label mismatch. Missing=[$($missing -join ',')] Unexpected=[$($unexpected -join ',')]"
}

function Compare-StringSet {
    param(
        [System.Collections.Generic.HashSet[string]]$Expected,
        [System.Collections.Generic.HashSet[string]]$Actual
    )

    $missing = @($Expected | Where-Object { -not $Actual.Contains($_) } | Sort-Object)
    $unexpected = @($Actual | Where-Object { -not $Expected.Contains($_) } | Sort-Object)
    return [pscustomobject]@{
        passed = $missing.Count -eq 0 -and $unexpected.Count -eq 0
        missing = $missing
        unexpected = $unexpected
    }
}

function Get-PathBindingValidation {
    param(
        [string]$RepositoryRoot,
        [string]$BaseDirectory,
        [object]$Value,
        [string]$ExpectedPath
    )

    $result = [ordered]@{
        passed = $false
        status = 'missing-path'
        expectedPath = [IO.Path]::GetFullPath($ExpectedPath)
        actualPath = $null
    }
    if ([string]::IsNullOrWhiteSpace([string]$Value)) {
        return [pscustomobject]$result
    }
    try {
        $actualPath = Resolve-RepoPath -RepositoryRoot $BaseDirectory -Value ([string]$Value)
    }
    catch {
        $result.status = 'invalid-path'
        return [pscustomobject]$result
    }
    $result.actualPath = $actualPath
    if (-not (Test-PathInsideRepository -RepositoryRoot $RepositoryRoot -Path $actualPath)) {
        $result.status = 'outside-repository'
        return [pscustomobject]$result
    }
    if ($actualPath.Equals($result.expectedPath, [StringComparison]::OrdinalIgnoreCase)) {
        $result.passed = $true
        $result.status = 'passed'
    }
    else {
        $result.status = 'path-mismatch'
    }
    return [pscustomobject]$result
}

function Add-RevalidationIssue {
    param(
        [System.Collections.Generic.List[object]]$List,
        [string]$Scope,
        [string]$ComponentId,
        [string]$Label,
        [string]$Status,
        [object]$Details
    )

    $null = $List.Add([pscustomobject]@{
        scope = $Scope
        componentId = $ComponentId
        label = $Label
        status = $Status
        details = $Details
    })
}

function Add-Blocker {
    param(
        [System.Collections.Generic.List[string]]$List,
        [string]$Value
    )

    if (-not $List.Contains($Value)) {
        $List.Add($Value)
    }
}

function Test-RecordedSnapshot {
    param([object]$Snapshot)

    if ($null -eq $Snapshot -or
        $null -eq $Snapshot.PSObject.Properties['path'] -or
        $null -eq $Snapshot.PSObject.Properties['length'] -or
        $null -eq $Snapshot.PSObject.Properties['sha256']) {
        return $false
    }
    $path = [IO.Path]::GetFullPath([string]$Snapshot.path)
    if (-not (Test-Path -LiteralPath $path -PathType Leaf)) {
        return $false
    }
    $item = Get-Item -LiteralPath $path
    if ($item.Length -ne [long]$Snapshot.length) {
        return $false
    }
    return (Get-FileHash -LiteralPath $path -Algorithm SHA256).Hash -eq
        ([string]$Snapshot.sha256).ToUpperInvariant()
}

$defaultRoot = Split-Path -Parent $PSScriptRoot
$repositoryRoot = if ([string]::IsNullOrWhiteSpace($RepoRoot)) {
    (Resolve-Path -LiteralPath $defaultRoot).Path
}
else {
    (Resolve-Path -LiteralPath $RepoRoot).Path
}
if ([string]::IsNullOrWhiteSpace($ResourcePlanPath)) {
    $matches = @(Get-ChildItem -LiteralPath $repositoryRoot -Recurse -File -Filter 'resource-plan-v4.json')
    Assert-Condition ($matches.Count -eq 1) "Expected one resource-plan-v4.json, found $($matches.Count)."
    $ResourcePlanPath = $matches[0].FullName
}

$planPath = (Resolve-Path -LiteralPath $ResourcePlanPath).Path
$plan = Get-Content -LiteralPath $planPath -Raw -Encoding UTF8 | ConvertFrom-Json
Assert-Condition ([int]$plan.schemaVersion -eq 1) 'Unsupported migration plan schemaVersion.'
Assert-Condition ([string]$plan.planId -eq 'weaponmaster-vergil-dark-blue-aseprite-migration-v4') `
    "Unexpected migration plan identity: $($plan.planId)"
Assert-Condition ([string]$plan.themeId -eq 'weaponmaster-vergil-dark-blue') 'Unexpected migration plan themeId.'
Assert-Condition ([string]$plan.status -eq 'migration-evidence-pending') 'Unexpected migration plan status.'
Assert-Condition ($plan.coverage.fullSkillCoverageProven -eq $false) 'Migration plan coverage must remain false.'
Assert-Condition ($plan.deployment.authorized -eq $false) 'Migration plan cannot authorize deployment.'
Assert-Condition ($plan.deployment.performed -eq $false) 'Migration plan cannot record deployment.'
Assert-Condition ($plan.deployment.imagePacks2Write -eq $false) 'Migration plan cannot record an ImagePacks2 write.'
Assert-Condition ($plan.deployment.processOperation -eq $false) 'Migration plan cannot record a process operation.'
Assert-Condition ([string]$plan.readinessPolicy.historicalCutinReuse -eq 'forbidden') `
    'Historical Cut-in reuse must remain forbidden.'
Assert-Condition ([string]$plan.readinessPolicy.componentSnapshotsAndIndependentIndexes -eq 'required') `
    'Component artifact and independent-index readiness policy changed.'
Assert-Condition ([string]$plan.readinessPolicy.componentConfigPlanSummarySelections -eq 'required') `
    'Component config/plan/summary readiness policy changed.'
Assert-Condition ([string]$plan.readinessPolicy.componentPlanConfigSummaryOutputPaths -eq 'required') `
    'Component output-path binding readiness policy changed.'
Assert-Condition ([string]$plan.readinessPolicy.componentSummaryToolchainSnapshots -eq 'required') `
    'Component toolchain readiness policy changed.'
Assert-Condition ([string]$plan.readinessPolicy.baselineBuilderSnapshots -eq 'required') `
    'Baseline builder-snapshot readiness policy changed.'

$baselinePath = Assert-FileSnapshot -RepositoryRoot $repositoryRoot -Snapshot $plan.baselinePlan -Label 'Baseline resource plan'
$sourceMigrationPath = Assert-FileSnapshot -RepositoryRoot $repositoryRoot -Snapshot $plan.sourceMigration -Label 'Source migration audit'
$baseline = Get-Content -LiteralPath $baselinePath -Raw -Encoding UTF8 | ConvertFrom-Json
$sourceMigration = Get-Content -LiteralPath $sourceMigrationPath -Raw -Encoding UTF8 | ConvertFrom-Json

Assert-Condition ([string]$baseline.planId -eq [string]$plan.baselinePlan.planId) 'Baseline planId binding changed.'
Assert-Condition ([string]$baseline.planId -eq 'weaponmaster-vergil-dark-blue-full-skill-v3') 'Unexpected baseline plan.'
Assert-Condition ($baseline.coverage.fullSkillCoverageProven -eq $false) 'Baseline plan must remain pre-release.'
Assert-Condition ([string]$sourceMigration.status -eq 'passed') 'Source migration audit did not pass.'
Assert-Condition ([int]$sourceMigration.counts.uniqueExpectedSnapshots -eq 53) 'Source migration unique snapshot count changed.'
Assert-Condition ([int]$sourceMigration.counts.matched -eq 53) 'Source migration matched count changed.'
Assert-Condition ([int]$sourceMigration.counts.contentDrift -eq 0) 'Source migration contains content drift.'
Assert-Condition ([int]$sourceMigration.counts.missing -eq 0) 'Source migration contains missing inputs.'
Assert-Condition ($sourceMigration.deployment.authorized -eq $false) 'Source migration cannot authorize deployment.'
Assert-Condition ($sourceMigration.deployment.performed -eq $false) 'Source migration cannot record deployment.'

$selectedComponents = @($baseline.components | Where-Object { $_.selectedForAggregation -eq $true })
Assert-Condition ($selectedComponents.Count -eq 31) "Expected 31 selected baseline components, found $($selectedComponents.Count)."
$planComponentIds = Get-StringSet @($plan.baselineComponents.selectedComponentIds)
$baselineComponentIds = Get-StringSet @($selectedComponents | ForEach-Object { [string]$_.id })
Assert-SetEqual -Expected $baselineComponentIds -Actual $planComponentIds -Label 'Migration/baseline component IDs'
$selectedImgCount = [int](@($selectedComponents | ForEach-Object { @($_.selectedImgPaths).Count } | Measure-Object -Sum).Sum)
Assert-Condition ([int]$plan.baselineComponents.componentCount -eq 31) 'Migration component count changed.'
Assert-Condition ([int]$plan.baselineComponents.selectedImgCount -eq 417) 'Migration selected IMG count changed.'
Assert-Condition ($selectedImgCount -eq 417) "Baseline selected IMG count changed: $selectedImgCount"

$superseded = @($plan.supersededReuseComponents)
Assert-Condition ($superseded.Count -eq 1) 'Expected one superseded reuse component.'
Assert-Condition ([string]$superseded[0].id -eq 'cutin-weaponmaster-neo-v2') 'Unexpected superseded reuse component.'
Assert-Condition ($superseded[0].activeAggregationAuthorized -eq $false) 'Historical Cut-in cannot be authorized for active aggregation.'
Assert-Condition ([string]$superseded[0].status -eq 'superseded-historical-evidence-only') `
    'Historical Cut-in disposition changed.'

$indexValidator = Join-Path $repositoryRoot 'tools\Test-DnfNpkIndex.ps1'
Assert-Condition (Test-Path -LiteralPath $indexValidator -PathType Leaf) "Independent index validator was not found: $indexValidator"
$blockers = New-Object 'System.Collections.Generic.List[string]'
$componentResults = New-Object 'System.Collections.Generic.List[object]'
$componentConfigResults = New-Object 'System.Collections.Generic.List[object]'
$componentToolResults = New-Object 'System.Collections.Generic.List[object]'
$baselineBuilderResults = New-Object 'System.Collections.Generic.List[object]'
$componentIssues = New-Object 'System.Collections.Generic.List[object]'
$outputPathBindingCount = 0
foreach ($component in $selectedComponents) {
    $componentId = [string]$component.id
    $componentIssueStart = $componentIssues.Count
    $componentToolStart = $componentToolResults.Count
    Assert-Condition ($component.validatedArtifact.status -eq 'offline-validated-client-pending') `
        "Component status changed: $componentId/$($component.validatedArtifact.status)"
    $componentPath = Assert-FileSnapshot -RepositoryRoot $repositoryRoot `
        -Snapshot $component.validatedArtifact.componentNpk -Label "Component NPK $componentId"
    $summaryPath = Assert-FileSnapshot -RepositoryRoot $repositoryRoot `
        -Snapshot $component.validatedArtifact.buildSummary -Label "Component build summary $componentId"
    $summary = Get-Content -LiteralPath $summaryPath -Raw -Encoding UTF8 | ConvertFrom-Json
    Assert-Condition ([string]$summary.status -eq 'passed') "Component build summary did not pass: $componentId"
    Assert-Condition ([long]$summary.output.length -eq [long]$component.validatedArtifact.componentNpk.length) `
        "Component summary length binding changed: $componentId"
    Assert-Condition (([string]$summary.output.sha256).ToUpperInvariant() -eq
        ([string]$component.validatedArtifact.componentNpk.sha256).ToUpperInvariant()) `
        "Component summary SHA-256 binding changed: $componentId"
    Assert-Condition ($summary.deployment.performed -eq $false) "Component summary records deployment: $componentId"
    Assert-Condition ([string]$summary.deployment.status -eq 'not-authorized-not-performed') `
        "Component deployment status changed: $componentId/$($summary.deployment.status)"

    $planComponentBinding = Get-PathBindingValidation -RepositoryRoot $repositoryRoot `
        -BaseDirectory $repositoryRoot -Value $component.output.componentNpkPath `
        -ExpectedPath $componentPath
    $planSummaryBinding = Get-PathBindingValidation -RepositoryRoot $repositoryRoot `
        -BaseDirectory $repositoryRoot -Value $component.output.buildSummaryPath `
        -ExpectedPath $summaryPath
    $summaryComponentBinding = Get-PathBindingValidation -RepositoryRoot $repositoryRoot `
        -BaseDirectory $repositoryRoot -Value $summary.output.componentNpkPath `
        -ExpectedPath $componentPath
    $summarySelfBinding = Get-PathBindingValidation -RepositoryRoot $repositoryRoot `
        -BaseDirectory $repositoryRoot -Value $summary.output.buildSummaryPath `
        -ExpectedPath $summaryPath
    foreach ($binding in @(
        [pscustomobject]@{ label = 'plan-component-npk-path'; value = $planComponentBinding },
        [pscustomobject]@{ label = 'plan-build-summary-path'; value = $planSummaryBinding },
        [pscustomobject]@{ label = 'summary-component-npk-path'; value = $summaryComponentBinding },
        [pscustomobject]@{ label = 'summary-build-summary-path'; value = $summarySelfBinding }
    )) {
        if (-not $binding.value.passed) {
            Add-RevalidationIssue -List $componentIssues -Scope 'component-output' `
                -ComponentId $componentId -Label $binding.label -Status $binding.value.status `
                -Details $binding.value
        }
    }

    $selectedPaths = Get-StringSet @($component.selectedImgPaths)
    $summaryPaths = Get-StringSet @($summary.selection.allowedImgPaths)
    $summarySelection = Compare-StringSet -Expected $selectedPaths -Actual $summaryPaths
    if (-not $summarySelection.passed) {
        Add-RevalidationIssue -List $componentIssues -Scope 'component-selection' `
            -ComponentId $componentId -Label 'plan-summary-allowed-img-paths' `
            -Status 'selection-drift' -Details $summarySelection
    }

    $configPath = Resolve-RepoPath -RepositoryRoot $repositoryRoot -Value ([string]$component.configPath)
    $configRecord = [ordered]@{
        componentId = $componentId
        status = 'missing-file'
        path = $configPath
        length = $null
        sha256 = $null
        planSelectionMatches = $false
        outputBindingsPassed = $false
        outputBindings = $null
    }
    $configSelection = [pscustomobject]@{ passed = $false; missing = @(); unexpected = @() }
    if (-not (Test-PathInsideRepository -RepositoryRoot $repositoryRoot -Path $configPath)) {
        $configRecord.status = 'outside-repository'
        Add-RevalidationIssue -List $componentIssues -Scope 'component-config' `
            -ComponentId $componentId -Label 'config-path' -Status 'outside-repository' `
            -Details ([pscustomobject]@{ path = $configPath })
    }
    elseif (-not (Test-Path -LiteralPath $configPath -PathType Leaf)) {
        Add-RevalidationIssue -List $componentIssues -Scope 'component-config' `
            -ComponentId $componentId -Label 'config-file' -Status 'missing-file' `
            -Details ([pscustomobject]@{ path = $configPath })
    }
    else {
        $configItem = Get-Item -LiteralPath $configPath
        $configRecord.length = [long]$configItem.Length
        $configRecord.sha256 = (Get-FileHash -LiteralPath $configPath -Algorithm SHA256).Hash
        try {
            $config = Get-Content -LiteralPath $configPath -Raw -Encoding UTF8 | ConvertFrom-Json
            $configDirectory = Split-Path -Parent $configPath
            $configComponentBinding = Get-PathBindingValidation -RepositoryRoot $repositoryRoot `
                -BaseDirectory $configDirectory -Value $config.output.componentNpkPath `
                -ExpectedPath $componentPath
            $configSummaryBinding = Get-PathBindingValidation -RepositoryRoot $repositoryRoot `
                -BaseDirectory $configDirectory -Value $config.output.buildSummaryPath `
                -ExpectedPath $summaryPath
            $configRecord.outputBindings = [pscustomobject]@{
                componentNpk = $configComponentBinding
                buildSummary = $configSummaryBinding
            }
            $configRecord.outputBindingsPassed = $configComponentBinding.passed -and
                $configSummaryBinding.passed
            foreach ($binding in @(
                [pscustomobject]@{ label = 'config-component-npk-path'; value = $configComponentBinding },
                [pscustomobject]@{ label = 'config-build-summary-path'; value = $configSummaryBinding }
            )) {
                if (-not $binding.value.passed) {
                    Add-RevalidationIssue -List $componentIssues -Scope 'component-output' `
                        -ComponentId $componentId -Label $binding.label -Status $binding.value.status `
                        -Details $binding.value
                }
            }
            if ([int]$config.schemaVersion -ne 1 -or
                [string]$config.themeId -ne [string]$plan.themeId) {
                $configRecord.status = 'identity-drift'
                Add-RevalidationIssue -List $componentIssues -Scope 'component-config' `
                    -ComponentId $componentId -Label 'config-identity' -Status 'identity-drift' `
                    -Details ([pscustomobject]@{
                        schemaVersion = $config.schemaVersion
                        themeId = $config.themeId
                    })
            }
            else {
                $configPaths = Get-StringSet @($config.allowedImgPaths)
                $configSelection = Compare-StringSet -Expected $selectedPaths -Actual $configPaths
                $configRecord.planSelectionMatches = $configSelection.passed
                if ($configSelection.passed -and $configRecord.outputBindingsPassed) {
                    $configRecord.status = 'passed'
                }
                elseif (-not $configSelection.passed) {
                    $configRecord.status = 'selection-drift'
                    Add-RevalidationIssue -List $componentIssues -Scope 'component-selection' `
                        -ComponentId $componentId -Label 'plan-config-allowed-img-paths' `
                        -Status 'selection-drift' -Details $configSelection
                }
                else {
                    $configRecord.status = 'output-path-drift'
                }
            }
        }
        catch {
            $configRecord.status = 'invalid-json-or-contract'
            Add-RevalidationIssue -List $componentIssues -Scope 'component-config' `
                -ComponentId $componentId -Label 'config-parse' `
                -Status 'invalid-json-or-contract' `
                -Details ([pscustomobject]@{ message = $_.Exception.Message })
        }
    }
    $componentConfigResults.Add([pscustomobject]$configRecord)
    $allOutputBindingsPassed = $planComponentBinding.passed -and
        $planSummaryBinding.passed -and
        $summaryComponentBinding.passed -and
        $summarySelfBinding.passed -and
        $configRecord.outputBindingsPassed
    if ($allOutputBindingsPassed) {
        $outputPathBindingCount++
    }

    if (Test-ObjectProperty -Object $summary -Name 'toolchain') {
        foreach ($property in @($summary.toolchain.PSObject.Properties)) {
            $toolResult = Get-SnapshotValidation -RepositoryRoot $repositoryRoot `
                -Snapshot $property.Value -Label "$componentId/$($property.Name)"
            $componentToolResults.Add([pscustomobject]@{
                componentId = $componentId
                label = [string]$property.Name
                passed = $toolResult.passed
                status = $toolResult.status
                path = $toolResult.path
                expectedLength = $toolResult.expectedLength
                actualLength = $toolResult.actualLength
                expectedSha256 = $toolResult.expectedSha256
                actualSha256 = $toolResult.actualSha256
            })
            if (-not $toolResult.passed) {
                Add-RevalidationIssue -List $componentIssues -Scope 'component-toolchain' `
                    -ComponentId $componentId -Label ([string]$property.Name) `
                    -Status $toolResult.status -Details $toolResult
            }
        }
    }

    $indexText = & $indexValidator -Path $componentPath `
        -ExpectedEntryCount @($component.selectedImgPaths).Count `
        -ExpectedSha256 ([string]$component.validatedArtifact.componentNpk.sha256) -AsJson | Out-String
    $index = $indexText | ConvertFrom-Json
    Assert-Condition ($index.HeaderSha256Valid -eq $true) "Component independent index failed: $componentId"
    Assert-Condition ([int]$index.EntryCount -eq @($component.selectedImgPaths).Count) `
        "Component independent entry count changed: $componentId"
    Assert-Condition ([int]$index.UniquePathCount -eq [int]$index.EntryCount) `
        "Component independent index contains duplicate paths: $componentId"
    Assert-Condition ([int]$index.ImgMagicValidCount -eq [int]$index.EntryCount) `
        "Component independent IMG magic count changed: $componentId"
    $componentResults.Add([pscustomobject]@{
        id = $componentId
        entryCount = [int]$index.EntryCount
        sha256 = [string]$index.Sha256
        config = [pscustomobject]$configRecord
        selection = [pscustomobject]@{
            planSummary = $summarySelection
            planConfig = $configSelection
        }
        outputBindings = [pscustomobject]@{
            planComponentNpk = $planComponentBinding
            planBuildSummary = $planSummaryBinding
            summaryComponentNpk = $summaryComponentBinding
            summaryBuildSummary = $summarySelfBinding
            config = $configRecord.outputBindings
            allPassed = $allOutputBindingsPassed
        }
        toolchainSnapshotCount = $componentToolResults.Count - $componentToolStart
        status = if ($componentIssues.Count -eq $componentIssueStart) {
            'passed-live-revalidation'
        }
        else {
            'blocked-live-revalidation'
        }
    })
}

foreach ($builderSnapshot in @($baseline.evidence.builderSnapshots)) {
    $kind = if (Test-ObjectProperty -Object $builderSnapshot -Name 'kind') {
        [string]$builderSnapshot.kind
    }
    else {
        'builder-snapshot'
    }
    $builderResult = Get-SnapshotValidation -RepositoryRoot $repositoryRoot `
        -Snapshot $builderSnapshot -Label $kind
    $baselineBuilderResults.Add($builderResult)
    if (-not $builderResult.passed) {
        Add-RevalidationIssue -List $componentIssues -Scope 'baseline-builder-snapshot' `
            -ComponentId $null -Label $kind -Status $builderResult.status -Details $builderResult
    }
}
if ($componentConfigResults.Count -ne 31) {
    Add-RevalidationIssue -List $componentIssues -Scope 'component-config' `
        -ComponentId $null -Label 'config-count' -Status 'count-mismatch' `
        -Details ([pscustomobject]@{ expected = 31; actual = $componentConfigResults.Count })
}
if ($componentToolResults.Count -ne 7) {
    Add-RevalidationIssue -List $componentIssues -Scope 'component-toolchain' `
        -ComponentId $null -Label 'summary-toolchain-snapshot-count' -Status 'count-mismatch' `
        -Details ([pscustomobject]@{ expected = 7; actual = $componentToolResults.Count })
}
if ($baselineBuilderResults.Count -ne 7) {
    Add-RevalidationIssue -List $componentIssues -Scope 'baseline-builder-snapshot' `
        -ComponentId $null -Label 'builder-snapshot-count' -Status 'count-mismatch' `
        -Details ([pscustomobject]@{ expected = 7; actual = $baselineBuilderResults.Count })
}
$componentLiveRevalidationPassed = $componentIssues.Count -eq 0
if (-not $componentLiveRevalidationPassed) {
    Add-Blocker -List $blockers -Value 'component-live-revalidation-pending'
}

$asepriteRecord = [ordered]@{ available = $false; apiCapabilityRecorded = $false }
$asepriteManifestPath = Join-Path $repositoryRoot 'tools\bin\aseprite\current.json'
if (-not (Test-Path -LiteralPath $asepriteManifestPath -PathType Leaf)) {
    Add-Blocker -List $blockers -Value 'aseprite-not-imported'
    Add-Blocker -List $blockers -Value 'aseprite-api-capability-not-recorded'
}
else {
    $asepriteManifest = Get-Content -LiteralPath $asepriteManifestPath -Raw -Encoding UTF8 | ConvertFrom-Json
    Assert-Condition ([int]$asepriteManifest.schemaVersion -eq 1) 'Aseprite current manifest schema changed.'
    $asepriteExecutable = Resolve-RepoPath -RepositoryRoot (Split-Path -Parent $asepriteManifestPath) `
        -Value ([string]$asepriteManifest.relativeExecutable)
    Assert-Condition (Test-Path -LiteralPath $asepriteExecutable -PathType Leaf) `
        "Aseprite executable was not found: $asepriteExecutable"
    $asepriteItem = Get-Item -LiteralPath $asepriteExecutable
    $asepriteHash = (Get-FileHash -LiteralPath $asepriteExecutable -Algorithm SHA256).Hash
    Assert-Condition ($asepriteItem.Length -eq [long]$asepriteManifest.length) 'Aseprite executable length changed.'
    Assert-Condition ($asepriteHash -eq ([string]$asepriteManifest.sha256).ToUpperInvariant()) 'Aseprite executable SHA-256 changed.'
    $apiRecorded = $null -ne $asepriteManifest.PSObject.Properties['apiVersion'] -and
        [int]$asepriteManifest.apiVersion -ge [int]$plan.activeCutin.minimumAsepriteApiVersion -and
        [int]$asepriteManifest.minimumApiVersion -eq 30
    if (-not $apiRecorded) {
        Add-Blocker -List $blockers -Value 'aseprite-api-capability-not-recorded'
    }
    $asepriteRecord = [ordered]@{
        available = $true
        apiCapabilityRecorded = $apiRecorded
        path = $asepriteExecutable
        length = [long]$asepriteItem.Length
        sha256 = $asepriteHash
        apiVersion = if ($apiRecorded) { [int]$asepriteManifest.apiVersion } else { $null }
    }
}

$renderPath = Resolve-RepoPath -RepositoryRoot $repositoryRoot -Value ([string]$plan.activeCutin.evidence.renderSummaryPath)
$manualPath = Resolve-RepoPath -RepositoryRoot $repositoryRoot -Value ([string]$plan.activeCutin.evidence.manualReviewPath)
$buildPath = Resolve-RepoPath -RepositoryRoot $repositoryRoot -Value ([string]$plan.activeCutin.evidence.buildSummaryPath)
$renderValidated = $false
$manualValidated = $false
$buildValidated = $false

if (-not (Test-Path -LiteralPath $renderPath -PathType Leaf)) {
    Add-Blocker -List $blockers -Value 'cutin-render-evidence-pending'
}
else {
    $render = Get-Content -LiteralPath $renderPath -Raw -Encoding UTF8 | ConvertFrom-Json
    Assert-Condition ([int]$render.schemaVersion -eq 1) 'Cut-in render summary schema changed.'
    Assert-Condition ([string]$render.runId -eq [string]$plan.activeCutin.runId) 'Cut-in render runId changed.'
    Assert-Condition ([string]$render.status -eq 'passed') 'Cut-in render summary did not pass.'
    Assert-Condition ($render.fullSkillCoverageProven -eq $false) 'Cut-in render summary cannot prove full coverage.'
    Assert-Condition ([string]$render.editor.application -eq 'Aseprite') 'Cut-in render editor changed.'
    Assert-Condition ([string]$render.editor.apiCapability.status -eq 'passed') 'Cut-in render lacks passed Aseprite API evidence.'
    Assert-Condition ([int]$render.editor.apiCapability.apiVersion -ge 30) 'Cut-in render Aseprite API is too old.'
    Assert-Condition ([int]$render.accounting.layeredProjects -eq 24) 'Cut-in layered project count changed.'
    Assert-Condition ([int]$render.accounting.runtimePngs -eq 24) 'Cut-in runtime PNG count changed.'
    Assert-Condition ([int]$render.accounting.missingFrames -eq 0) 'Cut-in render has missing frames.'
    Assert-Condition ([int]$render.accounting.duplicateFrames -eq 0) 'Cut-in render has duplicate frames.'
    Assert-Condition ([int]$render.accounting.geometryDrift -eq 0) 'Cut-in render has geometry drift.'
    Assert-Condition ([int]$render.accounting.configurationDrift -eq 0) 'Cut-in render has configuration drift.'
    Assert-Condition ([int]$render.accounting.reopenedProjectsValidated -eq 24) 'Cut-in projects were not all reopened.'
    Assert-Condition ([int]$render.accounting.runtimeMatchesLayeredRender -eq 24) 'Cut-in runtime/project pixel equality is incomplete.'
    Assert-Condition ([string]$render.validation.layeredProjectsReopened -eq 'passed') 'Cut-in project reopen validation failed.'
    Assert-Condition ([string]$render.validation.layeredProjectRuntimePixelEquality -eq 'passed') 'Cut-in project/runtime equality failed.'
    Assert-Condition ([string]$render.deployment -eq 'not-authorized-not-performed') 'Cut-in render records deployment.'

    $frameIndexes = New-Object 'System.Collections.Generic.HashSet[int]'
    foreach ($frame in @($render.frames)) {
        $frameIndex = [int]$frame.frameIndex
        Assert-Condition ($frameIndex -ge 3 -and $frameIndex -le 26 -and $frameIndexes.Add($frameIndex)) `
            "Invalid or duplicate Cut-in render frame: $frameIndex"
        Assert-Condition (Test-RecordedSnapshot -Snapshot $frame.source) "Cut-in source frame snapshot changed: $frameIndex"
        Assert-Condition (Test-RecordedSnapshot -Snapshot $frame.edited) "Cut-in layered project snapshot changed: $frameIndex"
        Assert-Condition (Test-RecordedSnapshot -Snapshot $frame.runtime) "Cut-in runtime PNG snapshot changed: $frameIndex"
        Assert-Condition ([int]$frame.runtime.width -eq 1068 -and [int]$frame.runtime.height -eq 600) `
            "Cut-in runtime geometry changed: $frameIndex"
    }
    Assert-Condition ($frameIndexes.Count -eq 24) 'Cut-in render frame set is incomplete.'
    $renderValidated = $true
}

if (-not (Test-Path -LiteralPath $manualPath -PathType Leaf)) {
    Add-Blocker -List $blockers -Value 'cutin-manual-full-sequence-review-pending'
}
else {
    $manual = Get-Content -LiteralPath $manualPath -Raw -Encoding UTF8 | ConvertFrom-Json
    Assert-Condition ([int]$manual.schemaVersion -eq 1) 'Cut-in manual review schema changed.'
    Assert-Condition ([string]$manual.runId -eq [string]$plan.activeCutin.runId) 'Cut-in manual review runId changed.'
    Assert-Condition ([string]$manual.status -eq 'passed') 'Cut-in manual full-sequence review did not pass.'
    Assert-Condition ([string]$manual.scope.frameIndexes -eq '3-26') 'Cut-in manual review frame scope changed.'
    foreach ($field in @(
        'fullSequenceContinuity',
        'sourceTimingAndStageContinuity',
        'characterAndWeaponFocus',
        'watermarkAndTextAbsent',
        'noUnexpectedBlankOrFullCanvasBlackFrame',
        'themeAcceptance'
    )) {
        Assert-Condition ([string]$manual.checks.$field -eq 'passed') "Cut-in manual review check did not pass: $field"
    }
    Assert-Condition (Test-RecordedSnapshot -Snapshot $manual.renderSummary) 'Cut-in manual review render-summary binding changed.'
    Assert-Condition ([string]$manual.deployment -eq 'not-authorized-not-performed') 'Cut-in manual review records deployment.'
    $manualValidated = $true
}

if (-not (Test-Path -LiteralPath $buildPath -PathType Leaf)) {
    Add-Blocker -List $blockers -Value 'cutin-build-evidence-pending'
    Add-Blocker -List $blockers -Value 'cutin-independent-validation-pending'
}
else {
    $build = Get-Content -LiteralPath $buildPath -Raw -Encoding UTF8 | ConvertFrom-Json
    Assert-Condition ([int]$build.schemaVersion -eq 1) 'Cut-in build summary schema changed.'
    Assert-Condition ([string]$build.runId -eq [string]$plan.activeCutin.runId) 'Cut-in build runId changed.'
    Assert-Condition ([string]$build.status -eq 'passed') 'Cut-in build summary did not pass.'
    Assert-Condition ($build.fullSkillCoverageProven -eq $false) 'Cut-in component cannot prove full coverage.'
    Assert-Condition ([string]$build.targetImg -eq [string]$plan.activeCutin.targetImg) 'Cut-in build target IMG changed.'
    Assert-Condition ((@($build.changedFrames) -join ',') -eq ((3..26) -join ',')) 'Cut-in changed frame set changed.'
    Assert-Condition ((@($build.preservedFrames) -join ',') -eq '0,1,2') 'Cut-in preserved frame set changed.'
    Assert-Condition ([int]$build.preservedNonTargetImgPayloads -eq 25) 'Cut-in non-target preservation count changed.'
    Assert-Condition (Test-RecordedSnapshot -Snapshot $build.renderSummary) 'Cut-in build render-summary binding changed.'
    Assert-Condition (Test-RecordedSnapshot -Snapshot $build.outputNpk) 'Cut-in build output NPK snapshot changed.'
    Assert-Condition ([int]$build.editedPngCount -eq 24 -and @($build.editedPngs).Count -eq 24) `
        'Cut-in build runtime PNG accounting changed.'
    Assert-Condition ([int]$build.builderStats.npkEntries -eq 26) 'Cut-in builder NPK entry count changed.'
    Assert-Condition ([long]$build.builderStats.modifiedImgBytes -gt 0) 'Cut-in builder modified IMG size is invalid.'
    Assert-Condition ([int]$build.builderStats.changedVisibleTextures -eq 24) `
        'Cut-in builder changed texture count changed.'
    Assert-Condition ([int]$build.builderStats.preservedPlaceholderFrames -eq 3) `
        'Cut-in builder placeholder count changed.'
    Assert-Condition ([long]$build.builderStats.changedBc3ColorBlocks -gt 0) `
        'Cut-in builder did not record BC3 color changes.'
    Assert-Condition ([long]$build.builderStats.preservedBc3AlphaBlocks -eq 961200) `
        'Cut-in builder BC3 alpha block count changed.'
    Assert-Condition ([int]$build.builderStats.nonTargetPayloadsByteIdentical -eq 25) `
        'Cut-in builder non-target payload count changed.'
    Assert-Condition ([int]$build.builderStats.sharedPayloadEntriesReused -eq 6) `
        'Cut-in builder shared payload reuse count changed.'
    Assert-Condition ([string]$build.builderStats.structureValidation -eq 'passed' -and
        [string]$build.builderStats.texdiagValidation -eq 'passed') `
        'Cut-in builder structure or texdiag validation did not pass.'
    Assert-Condition (Test-RecordedSnapshot -Snapshot $build.builderOutput) `
        'Cut-in builder-output snapshot changed.'
    Assert-Condition ([string]$build.deployment -eq 'not-authorized-not-performed') 'Cut-in build records deployment.'
    $buildValidated = $true

    $hasIndependentEvidence = $null -ne $build.PSObject.Properties['validation'] -and
        $null -ne $build.validation.PSObject.Properties['independentIndex'] -and
        $null -ne $build.validation.PSObject.Properties['fullFrame'] -and
        $null -ne $build.validation.PSObject.Properties['targetDiff']
    if (-not $hasIndependentEvidence) {
        Add-Blocker -List $blockers -Value 'cutin-independent-validation-pending'
    }
    else {
        Assert-Condition (Test-RecordedSnapshot -Snapshot $build.validation.independentIndex.snapshot) `
            'Cut-in independent-index snapshot changed.'
        Assert-Condition ([string]$build.validation.independentIndex.status -eq 'passed') `
            'Cut-in independent index did not pass.'
        Assert-Condition ([int]$build.validation.independentIndex.entryCount -eq 26) `
            'Cut-in component independent entry count changed.'
        Assert-Condition ([int]$build.validation.independentIndex.uniquePathCount -eq 26) `
            'Cut-in component independent unique path count changed.'
        Assert-Condition ([string]$build.validation.independentIndex.parserDependency -eq
            'PowerShell/.NET only; no ExtractorSharp') `
            'Cut-in independent index is not independent from ExtractorSharp.'
        $indexPath = [IO.Path]::GetFullPath([string]$build.validation.independentIndex.snapshot.path)
        $index = Get-Content -LiteralPath $indexPath -Raw -Encoding UTF8 | ConvertFrom-Json
        Assert-Condition ([int]$index.EntryCount -eq 26 -and [int]$index.UniquePathCount -eq 26 -and
            $index.HeaderSha256Valid -eq $true -and [int]$index.ImgMagicValidCount -eq 26) `
            'Cut-in recorded independent index contents changed.'
        Assert-Condition (([string]$index.Sha256).ToUpperInvariant() -eq
            ([string]$build.outputNpk.sha256).ToUpperInvariant()) `
            'Cut-in independent index/output NPK hash binding changed.'
        Assert-Condition ([string]$build.validation.fullFrame.status -eq 'passed') `
            'Cut-in full-frame validation did not pass.'
        Assert-Condition ([int]$build.validation.fullFrame.albumCount -eq 26 -and
            [int]$build.validation.fullFrame.frameCount -eq 834 -and
            [int]$build.validation.fullFrame.decodedNonLinkFrames -eq 834 -and
            [int]$build.validation.fullFrame.linkFrames -eq 0 -and
            [int]$build.validation.fullFrame.hiddenFrames -eq 0) `
            'Cut-in package decoded frame count changed.'
        Assert-Condition ((@($build.validation.fullFrame.backgrounds) -join ',') -eq
            'black,white,checkerboard') 'Cut-in full-frame background set changed.'
        Assert-Condition (Test-RecordedSnapshot -Snapshot $build.validation.fullFrame.albumInventory) `
            'Cut-in album-inventory snapshot changed.'
        Assert-Condition (Test-RecordedSnapshot -Snapshot $build.validation.fullFrame.frameInventory) `
            'Cut-in frame-inventory snapshot changed.'
        Assert-Condition (Test-RecordedSnapshot -Snapshot $build.validation.fullFrame.log) `
            'Cut-in full-frame log snapshot changed.'
        $albumPath = [IO.Path]::GetFullPath([string]$build.validation.fullFrame.albumInventory.path)
        $framePath = [IO.Path]::GetFullPath([string]$build.validation.fullFrame.frameInventory.path)
        $album = Get-Content -LiteralPath $albumPath -Raw -Encoding UTF8 | ConvertFrom-Json
        $frames = @(Import-Csv -LiteralPath $framePath -Encoding UTF8)
        Assert-Condition ([int]$album.AlbumCount -eq 26 -and [int]$album.FrameCount -eq 834 -and
            [int]$album.DecodedNonLinkFrames -eq 834 -and [int]$album.LinkFrames -eq 0 -and
            [int]$album.HiddenFrames -eq 0 -and $frames.Count -eq 834) `
            'Cut-in full-frame inventory contents changed.'
        Assert-Condition ((@($album.Backgrounds) -join ',') -eq 'black,white,checkerboard') `
            'Cut-in recorded full-frame backgrounds changed.'
        Assert-Condition (([string]$album.InputSha256).ToUpperInvariant() -eq
            ([string]$build.outputNpk.sha256).ToUpperInvariant()) `
            'Cut-in full-frame inventory/output NPK hash binding changed.'
        $contactSheets = @($build.validation.fullFrame.contactSheets)
        Assert-Condition ($contactSheets.Count -eq [int]$album.SheetCount -and $contactSheets.Count -eq 4) `
            'Cut-in full-frame contact-sheet count changed.'
        foreach ($sheet in $contactSheets) {
            Assert-Condition (Test-RecordedSnapshot -Snapshot $sheet) 'Cut-in contact-sheet snapshot changed.'
        }
        Assert-Condition ([string]$build.validation.targetDiff.status -eq 'passed') `
            'Cut-in target diff did not pass.'
        Assert-Condition (Test-RecordedSnapshot -Snapshot $build.validation.targetDiff.snapshot) `
            'Cut-in target-diff snapshot changed.'
        Assert-Condition (Test-RecordedSnapshot -Snapshot $build.validation.targetDiff.log) `
            'Cut-in target-diff log snapshot changed.'
        Assert-Condition ([int]$build.validation.targetDiff.changedFrameCount -eq 24) `
            'Cut-in target changed frame count changed.'
        Assert-Condition ([int]$build.validation.targetDiff.preservedPlaceholderCount -eq 3) `
            'Cut-in target placeholder count changed.'
        Assert-Condition ([int]$build.validation.targetDiff.metadataDiffCount -eq 0) `
            'Cut-in target metadata changed.'
        Assert-Condition ([int]$build.validation.targetDiff.nonTargetPayloadHashMismatchCount -eq 0 -and
            [long]$build.validation.targetDiff.alphaMismatchPixelCount -eq 0 -and
            [int]$build.validation.targetDiff.bc3AlphaBlockMismatchCount -eq 0 -and
            [int]$build.validation.targetDiff.targetPixelFailureCount -eq 0) `
            'Cut-in target pixel or payload preservation changed.'
        $targetDiffPath = [IO.Path]::GetFullPath([string]$build.validation.targetDiff.snapshot.path)
        $targetDiff = Get-Content -LiteralPath $targetDiffPath -Raw -Encoding UTF8 | ConvertFrom-Json
        Assert-Condition ([string]$targetDiff.status -eq 'passed' -and
            [int]$targetDiff.npk.entryCount -eq 26 -and
            [int]$targetDiff.npk.nonTargetPayloadsByteIdentical -eq 25 -and
            [int]$targetDiff.albums.outputFrameCount -eq 834 -and
            [int]$targetDiff.validation.changedFrameCount -eq 24 -and
            [int]$targetDiff.validation.preservedPlaceholderCount -eq 3 -and
            [int]$targetDiff.validation.metadataDiffCount -eq 0 -and
            [long]$targetDiff.validation.alphaMismatchPixelCount -eq 0 -and
            [int]$targetDiff.validation.bc3AlphaBlockMismatchCount -eq 0 -and
            [int]$targetDiff.validation.targetPixelFailureCount -eq 0) `
            'Cut-in target-diff report contents changed.'
        Assert-Condition (([string]$targetDiff.sourceNpk.sha256).ToUpperInvariant() -eq
            ([string]$build.sourceNpk.sha256).ToUpperInvariant() -and
            ([string]$targetDiff.outputNpk.sha256).ToUpperInvariant() -eq
            ([string]$build.outputNpk.sha256).ToUpperInvariant()) `
            'Cut-in target-diff source/output hash binding changed.'
    }
}

Add-Blocker -List $blockers -Value 'final-aggregation-not-performed'
Add-Blocker -List $blockers -Value 'final-validation-not-performed'
Add-Blocker -List $blockers -Value 'release-closure-not-performed'

$componentArray = $componentResults.ToArray()
$componentConfigArray = $componentConfigResults.ToArray()
$componentToolArray = $componentToolResults.ToArray()
$baselineBuilderArray = $baselineBuilderResults.ToArray()
$componentIssueArray = $componentIssues.ToArray()
$componentOutputIssueArray = @($componentIssueArray | Where-Object { $_.scope -eq 'component-output' })
$allOutputPathBindingsPassed = $outputPathBindingCount -eq 31 -and
    $componentOutputIssueArray.Count -eq 0
$blockerArray = $blockers.ToArray()
$preAggregationBlockers = @($blockerArray | Where-Object {
    $_ -notin @('final-aggregation-not-performed', 'final-validation-not-performed', 'release-closure-not-performed')
})
$readyForAggregation = $preAggregationBlockers.Count -eq 0
$result = [pscustomobject]@{
    schemaVersion = 1
    status = 'passed'
    state = if ($readyForAggregation) { 'ready-for-aggregation' } else { 'blocked-pre-aggregation' }
    mode = 'validation only; no build, aggregation, deployment, or process operation'
    planId = [string]$plan.planId
    resourcePlanPath = $planPath
    sourceMigration = [pscustomobject]@{
        status = 'passed'
        matched = 53
        contentDrift = 0
        missing = 0
    }
    components = [pscustomobject]@{
        status = if ($componentLiveRevalidationPassed) {
            'passed-live-revalidation'
        }
        else {
            'blocked-live-revalidation'
        }
        artifactSnapshotsAndIndependentIndexes = 'passed'
        count = $componentArray.Count
        selectedImgCount = $selectedImgCount
        configCount = $componentConfigArray.Count
        outputPathBindings = if ($allOutputPathBindingsPassed) { 'passed' } else { 'blocked' }
        outputPathBindingCount = $outputPathBindingCount
        outputPathBindingIssueCount = $componentOutputIssueArray.Count
        summaryToolchainSnapshotCount = $componentToolArray.Count
        baselineBuilderSnapshotCount = $baselineBuilderArray.Count
        provenanceIssueCount = $componentIssueArray.Count
        provenanceIssues = $componentIssueArray
        configs = $componentConfigArray
        summaryToolchainSnapshots = $componentToolArray
        baselineBuilderSnapshots = $baselineBuilderArray
        records = $componentArray
    }
    aseprite = [pscustomobject]$asepriteRecord
    cutin = [pscustomobject]@{
        runId = [string]$plan.activeCutin.runId
        renderValidated = $renderValidated
        manualReviewValidated = $manualValidated
        buildValidated = $buildValidated
    }
    readyForAggregation = $readyForAggregation
    fullSkillCoverageProven = $false
    blockers = $blockerArray
    deployment = 'not-authorized-not-performed'
}

if ($AsJson) {
    $result | ConvertTo-Json -Depth 12
}
else {
    $result
}
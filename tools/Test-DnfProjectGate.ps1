[CmdletBinding()]
param(
    [string]$RepoRoot,

    [switch]$AsJson
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
$OutputEncoding = [Console]::OutputEncoding = New-Object System.Text.UTF8Encoding($false)

function Assert-Condition {
    param(
        [Parameter(Mandatory = $true)]
        [bool]$Condition,

        [Parameter(Mandatory = $true)]
        [string]$Message
    )

    if (-not $Condition) {
        throw $Message
    }
}

function Resolve-Directory {
    param(
        [string]$Value,
        [string]$BaseDirectory
    )

    $candidate = if ([IO.Path]::IsPathRooted($Value)) {
        [IO.Path]::GetFullPath($Value)
    }
    else {
        [IO.Path]::GetFullPath((Join-Path $BaseDirectory $Value))
    }
    Assert-Condition -Condition (Test-Path -LiteralPath $candidate -PathType Container) `
        -Message "Directory was not found: $candidate"
    return (Resolve-Path -LiteralPath $candidate).Path
}

function Test-ObjectProperty {
    param([object]$Object, [string]$Name)

    return $null -ne $Object -and $null -ne $Object.PSObject.Properties[$Name]
}

function Assert-NoReparsePointPath {
    param(
        [string]$Path,
        [string]$RepositoryRoot,
        [string]$Label
    )

    $candidate = [IO.Path]::GetFullPath($Path)
    $root = [IO.Path]::GetFullPath($RepositoryRoot).TrimEnd(
        [IO.Path]::DirectorySeparatorChar,
        [IO.Path]::AltDirectorySeparatorChar)
    while ($true) {
        if (Test-Path -LiteralPath $candidate) {
            $item = Get-Item -LiteralPath $candidate -Force
            Assert-Condition -Condition (
                ($item.Attributes -band [IO.FileAttributes]::ReparsePoint) -eq 0) `
                -Message "$Label cannot traverse a reparse point: $($item.FullName)"
        }
        if ($candidate.Equals($root, [StringComparison]::OrdinalIgnoreCase)) {
            break
        }
        $parent = Split-Path -Parent $candidate
        Assert-Condition -Condition (-not [string]::IsNullOrWhiteSpace($parent) -and
            $parent -ne $candidate) `
            -Message "$Label path ancestry could not be resolved: $Path"
        $candidate = $parent
    }
}

function Resolve-RepositoryPath {
    param(
        [string]$Value,
        [string]$BaseDirectory,
        [string]$RepositoryRoot,
        [string]$Label
    )

    Assert-Condition -Condition (-not [string]::IsNullOrWhiteSpace($Value)) `
        -Message "$Label path is empty."
    $native = $Value.Replace('/', [IO.Path]::DirectorySeparatorChar)
    $candidate = if ([IO.Path]::IsPathRooted($native)) {
        [IO.Path]::GetFullPath($native)
    }
    else {
        [IO.Path]::GetFullPath((Join-Path $BaseDirectory $native))
    }
    $root = $RepositoryRoot.TrimEnd(
        [IO.Path]::DirectorySeparatorChar,
        [IO.Path]::AltDirectorySeparatorChar)
    $prefix = $root + [IO.Path]::DirectorySeparatorChar
    Assert-Condition -Condition ($candidate.StartsWith($prefix, [StringComparison]::OrdinalIgnoreCase)) `
        -Message "$Label must stay inside the repository: $candidate"
    Assert-NoReparsePointPath -Path $candidate -RepositoryRoot $RepositoryRoot `
        -Label $Label
    return $candidate
}

function Invoke-JsonValidator {
    param(
        [string]$ScriptPath,
        [hashtable]$Arguments,
        [string]$Label
    )

    Assert-Condition -Condition (Test-Path -LiteralPath $ScriptPath -PathType Leaf) `
        -Message "$Label script was not found: $ScriptPath"
    $text = & $ScriptPath @Arguments | Out-String
    Assert-Condition -Condition (-not [string]::IsNullOrWhiteSpace($text)) `
        -Message "$Label returned no result."
    $result = $text | ConvertFrom-Json
    Assert-Condition -Condition ($result.status -eq 'passed') `
        -Message "$Label did not pass: $text"
    Write-Output -NoEnumerate $result
}

$defaultRoot = Split-Path -Parent $PSScriptRoot
$repositoryRoot = if ([string]::IsNullOrWhiteSpace($RepoRoot)) {
    (Resolve-Path -LiteralPath $defaultRoot).Path
}
else {
    Resolve-Directory -Value $RepoRoot -BaseDirectory $defaultRoot
}

$rootAgents = Join-Path $repositoryRoot 'AGENTS.md'
$skillPath = Join-Path $repositoryRoot '.codex\skills\dnf-patch-maker\SKILL.md'
$fixedWorkflowValidator = Join-Path $repositoryRoot 'tools\Test-DnfWorkflow.ps1'
$fixedWorkflowRunner = Join-Path $repositoryRoot 'tools\Invoke-DnfWorkflow.ps1'
$adapterRegistryPath = Join-Path $repositoryRoot `
    'tools\workflow\adapter-registry.json'
Assert-Condition -Condition (Test-Path -LiteralPath $rootAgents -PathType Leaf) `
    -Message "Root AGENTS.md was not found: $rootAgents"
Assert-Condition -Condition (Test-Path -LiteralPath $skillPath -PathType Leaf) `
    -Message "Project dnf-patch-maker skill was not found: $skillPath"
foreach ($fixedControlPath in @(
        $fixedWorkflowValidator,
        $fixedWorkflowRunner,
        $adapterRegistryPath)) {
    Assert-Condition -Condition (Test-Path -LiteralPath $fixedControlPath -PathType Leaf) `
        -Message "Fixed workflow control file was not found: $fixedControlPath"
    Assert-NoReparsePointPath -Path $fixedControlPath -RepositoryRoot $repositoryRoot `
        -Label 'Fixed workflow control file'
}
$adapterRegistry = Get-Content -LiteralPath $adapterRegistryPath -Raw -Encoding UTF8 |
ConvertFrom-Json

$skillResults = New-Object System.Collections.Generic.List[object]
$skillsRoot = Join-Path $repositoryRoot '.codex\skills'
$skillDirectories = @(Get-ChildItem -LiteralPath $skillsRoot -Directory | Sort-Object FullName)
foreach ($skillDirectory in $skillDirectories) {
    $skillFile = Join-Path $skillDirectory.FullName 'SKILL.md'
    Assert-Condition -Condition (Test-Path -LiteralPath $skillFile -PathType Leaf) `
        -Message "Skill entrypoint was not found: $skillFile"
    $skillText = (Get-Content -LiteralPath $skillFile -Raw -Encoding UTF8).Replace("`r`n", "`n")
    $skillLines = @($skillText -split "`n")
    Assert-Condition -Condition ($skillLines.Count -le 500) `
        -Message "Skill entrypoint exceeds 500 lines: $skillFile/$($skillLines.Count)"
    Assert-Condition -Condition ($skillLines.Count -ge 5 -and $skillLines[0] -eq '---') `
        -Message "Skill frontmatter start is invalid: $skillFile"
    $frontmatterEnd = -1
    for ($lineIndex = 1; $lineIndex -lt $skillLines.Count; $lineIndex++) {
        if ($skillLines[$lineIndex] -eq '---') {
            $frontmatterEnd = $lineIndex
            break
        }
    }
    Assert-Condition -Condition ($frontmatterEnd -gt 1) -Message "Skill frontmatter end is missing: $skillFile"
    $frontmatter = @{}
    for ($lineIndex = 1; $lineIndex -lt $frontmatterEnd; $lineIndex++) {
        $line = $skillLines[$lineIndex]
        Assert-Condition -Condition ($line -match '^([a-z_]+):\s*(.+)$') `
            -Message "Invalid skill frontmatter line: $skillFile/$line"
        $frontmatter[$Matches[1]] = $Matches[2].Trim()
    }
    Assert-Condition -Condition ($frontmatter.Count -eq 2) `
        -Message "Skill frontmatter must contain only name and description: $skillFile"
    Assert-Condition -Condition ($frontmatter.ContainsKey('name') -and $frontmatter.ContainsKey('description')) `
        -Message "Skill frontmatter lacks name or description: $skillFile"
    $skillName = [string]$frontmatter['name']
    Assert-Condition -Condition ($skillName -match '^[a-z0-9-]{1,64}$') `
        -Message "Invalid skill name: $skillFile/$skillName"
    Assert-Condition -Condition ($skillDirectory.Name -ceq $skillName) `
        -Message "Skill folder/name mismatch: $($skillDirectory.Name)/$skillName"
    Assert-Condition -Condition (-not [string]::IsNullOrWhiteSpace([string]$frontmatter['description'])) `
        -Message "Skill description is empty: $skillFile"

    foreach ($match in [regex]::Matches($skillText, '\]\(([^)]+)\)')) {
        $reference = $match.Groups[1].Value
        if ($reference -match '^(https?://|#)') {
            continue
        }
        $referencePath = [IO.Path]::GetFullPath((Join-Path $skillDirectory.FullName $reference.Replace('/', '\')))
        Assert-Condition -Condition (Test-Path -LiteralPath $referencePath) `
            -Message "Skill reference was not found: $skillFile/$reference"
    }

    $agentFile = Join-Path $skillDirectory.FullName 'agents\openai.yaml'
    Assert-Condition -Condition (Test-Path -LiteralPath $agentFile -PathType Leaf) `
        -Message "Skill UI metadata was not found: $agentFile"
    $agentText = (Get-Content -LiteralPath $agentFile -Raw -Encoding UTF8).Replace("`r`n", "`n")
    Assert-Condition -Condition ($agentText -match '(?m)^interface:\s*$') `
        -Message "Skill UI metadata lacks interface: $agentFile"
    foreach ($field in @('display_name', 'short_description', 'default_prompt')) {
        Assert-Condition -Condition ($agentText -match "(?m)^  $field`: `"([^`"]+)`"`$") `
            -Message "Skill UI metadata field must be a quoted string: $agentFile/$field"
    }
    $shortDescription = [regex]::Match($agentText, '(?m)^  short_description: "([^"]+)"$').Groups[1].Value
    $defaultPrompt = [regex]::Match($agentText, '(?m)^  default_prompt: "([^"]+)"$').Groups[1].Value
    Assert-Condition -Condition ($shortDescription.Length -ge 25 -and $shortDescription.Length -le 64) `
        -Message "Skill short_description must contain 25-64 characters: $agentFile/$($shortDescription.Length)"
    Assert-Condition -Condition ($defaultPrompt.Contains("`$$skillName")) `
        -Message ('Skill default_prompt must mention ${0}: {1}' -f $skillName, $agentFile)

    $unexpectedFiles = @(Get-ChildItem -LiteralPath $skillDirectory.FullName -Recurse -File | Where-Object {
            $_.Name -in @('README.md', 'CHANGELOG.md', 'INSTALLATION_GUIDE.md', 'QUICK_REFERENCE.md')
        })
    $unexpectedFileNames = @($unexpectedFiles | ForEach-Object { $_.FullName }) -join ', '
    Assert-Condition -Condition ($unexpectedFiles.Count -eq 0) `
        -Message "Skill contains unexpected auxiliary documentation: $unexpectedFileNames"
    $skillResults.Add([pscustomobject]@{
            name                   = $skillName
            lineCount              = $skillLines.Count
            referenceCount         = [regex]::Matches($skillText, '\]\(([^)]+)\)').Count
            shortDescriptionLength = $shortDescription.Length
        })
}

$copilotSkillMirrorResults = New-Object System.Collections.Generic.List[object]
$githubRoot = Join-Path $repositoryRoot '.github'
$copilotSkillsRoot = Join-Path $githubRoot 'skills'
if (Test-Path -LiteralPath $githubRoot) {
    Assert-Condition -Condition (Test-Path -LiteralPath $githubRoot -PathType Container) `
        -Message ".github must be a directory: $githubRoot"
    Assert-NoReparsePointPath -Path $githubRoot -RepositoryRoot $repositoryRoot `
        -Label '.github directory'
    $unexpectedGithubChildren = @(Get-ChildItem -LiteralPath $githubRoot -Force | Where-Object {
            $_.Name -ne 'skills'
        })
    $unexpectedGithubChildNames = @($unexpectedGithubChildren | ForEach-Object { $_.FullName }) -join ', '
    Assert-Condition -Condition ($unexpectedGithubChildren.Count -eq 0) `
        -Message "Unexpected .github content: $unexpectedGithubChildNames"
    Assert-Condition -Condition (Test-Path -LiteralPath $copilotSkillsRoot -PathType Container) `
        -Message "Copilot skill mirror was not found: $copilotSkillsRoot"
    Assert-NoReparsePointPath -Path $copilotSkillsRoot -RepositoryRoot $repositoryRoot `
        -Label 'Copilot skill mirror'

    $codexSkillsRootPrefix = $skillsRoot.TrimEnd(
        [IO.Path]::DirectorySeparatorChar,
        [IO.Path]::AltDirectorySeparatorChar) + [IO.Path]::DirectorySeparatorChar
    $copilotSkillsRootPrefix = $copilotSkillsRoot.TrimEnd(
        [IO.Path]::DirectorySeparatorChar,
        [IO.Path]::AltDirectorySeparatorChar) + [IO.Path]::DirectorySeparatorChar
    $codexSkillFiles = @(Get-ChildItem -LiteralPath $skillsRoot -Recurse -File | Sort-Object FullName)
    $copilotSkillFiles = @(Get-ChildItem -LiteralPath $copilotSkillsRoot -Recurse -File | Sort-Object FullName)
    $codexSkillRelativePaths = New-Object 'Collections.Generic.HashSet[string]' `
    ([StringComparer]::OrdinalIgnoreCase)

    foreach ($codexSkillFile in $codexSkillFiles) {
        $relativePath = $codexSkillFile.FullName.Substring($codexSkillsRootPrefix.Length)
        $null = $codexSkillRelativePaths.Add($relativePath)
        $copilotSkillFilePath = Join-Path $copilotSkillsRoot $relativePath
        Assert-Condition -Condition (Test-Path -LiteralPath $copilotSkillFilePath -PathType Leaf) `
            -Message "Copilot skill mirror file was not found: $copilotSkillFilePath"
        $codexHash = (Get-FileHash -LiteralPath $codexSkillFile.FullName -Algorithm SHA256).Hash
        $copilotHash = (Get-FileHash -LiteralPath $copilotSkillFilePath -Algorithm SHA256).Hash
        Assert-Condition -Condition ($codexHash -eq $copilotHash) `
            -Message "Copilot skill mirror differs from .codex: $relativePath"
        $copilotSkillMirrorResults.Add([pscustomobject]@{
                relativePath = $relativePath.Replace('\', '/')
                sha256       = $codexHash
            })
    }

    foreach ($copilotSkillFile in $copilotSkillFiles) {
        $relativePath = $copilotSkillFile.FullName.Substring($copilotSkillsRootPrefix.Length)
        Assert-Condition -Condition ($codexSkillRelativePaths.Contains($relativePath)) `
            -Message "Copilot skill mirror has no .codex counterpart: $relativePath"
    }
}

$powerShellGate = Invoke-JsonValidator `
    -ScriptPath (Join-Path $repositoryRoot 'tools\Test-DnfPowerShellSource.ps1') `
    -Arguments @{ Path = $repositoryRoot; AsJson = $true } `
    -Label 'PowerShell source gate'
$workflowFixtureGate = Invoke-JsonValidator `
    -ScriptPath (Join-Path $repositoryRoot 'tools\Test-DnfWorkflowFixtures.ps1') `
    -Arguments @{ RepoRoot = $repositoryRoot; AsJson = $true } `
    -Label 'Workflow control-plane fixtures'
Assert-Condition -Condition ([int]$workflowFixtureGate.fixtureCount -ge 22) `
    -Message 'Workflow control-plane fixture coverage is incomplete.'
$releaseRollbackFixtureGate = Invoke-JsonValidator `
    -ScriptPath (Join-Path $repositoryRoot 'tools\Test-DnfReleaseMetadataRollbackFixture.ps1') `
    -Arguments @{ RepoRoot = $repositoryRoot; AsJson = $true } `
    -Label 'Release metadata rollback fixture'
Assert-Condition -Condition ($releaseRollbackFixtureGate.failureObserved -eq $true -and
    $releaseRollbackFixtureGate.manifestByteIdentityRestored -eq $true -and
    $releaseRollbackFixtureGate.releaseRemoved -eq $true -and
    [int]$releaseRollbackFixtureGate.temporaryFileCount -eq 0 -and
    $releaseRollbackFixtureGate.transactionRecoveryPassed -eq $true -and
    $releaseRollbackFixtureGate.committedTransactionIdempotent -eq $true -and
    $releaseRollbackFixtureGate.concurrentManifestCasPassed -eq $true) `
    -Message 'Release metadata fixture did not prove rollback, recovery, idempotency, and manifest CAS.'

$jsonFiles = @(Get-ChildItem -LiteralPath $repositoryRoot -Recurse -File -Filter '*.json' | Sort-Object FullName)
foreach ($jsonFile in $jsonFiles) {
    try {
        $null = Get-Content -LiteralPath $jsonFile.FullName -Raw -Encoding UTF8 | ConvertFrom-Json
    }
    catch {
        throw "Invalid JSON: $($jsonFile.FullName): $($_.Exception.Message)"
    }
}

$promptValidator = Join-Path $repositoryRoot 'tools\Test-DnfPromptTree.ps1'
$generationPolicyValidator = Join-Path $repositoryRoot 'tools\Test-DnfGenerationWorkflowPolicy.ps1'
$promptResults = New-Object System.Collections.Generic.List[object]
$releaseResults = New-Object System.Collections.Generic.List[object]
$historicalReleaseResults = New-Object System.Collections.Generic.List[object]
$activityMigrationResults = New-Object System.Collections.Generic.List[object]
$generationWorkflowPolicyResults = New-Object System.Collections.Generic.List[object]
$workflowResults = New-Object System.Collections.Generic.List[object]
$professionDirectories = @(Get-ChildItem -LiteralPath $repositoryRoot -Directory | Where-Object {
        (Test-Path -LiteralPath (Join-Path $_.FullName 'AGENTS.md') -PathType Leaf) -and
        (Test-Path -LiteralPath (Join-Path $_.FullName 'prompts\README.md') -PathType Leaf)
    } | Sort-Object FullName)

foreach ($profession in $professionDirectories) {
    $professionResult = Invoke-JsonValidator -ScriptPath $promptValidator -Arguments @{
        ProfessionPath = $profession.FullName
        RepoRoot       = $repositoryRoot
    } -Label "Profession Prompt tree $($profession.Name)"
    $promptResults.Add([pscustomobject]@{
            profession   = $profession.FullName
            theme        = $null
            checkedFiles = [int]$professionResult.counts.checkedFiles
        })

    $themeDirectories = @(Get-ChildItem -LiteralPath $profession.FullName -Directory | Where-Object {
            (Test-Path -LiteralPath (Join-Path $_.FullName 'AGENTS.md') -PathType Leaf) -and
            (Test-Path -LiteralPath (Join-Path $_.FullName 'prompts\README.md') -PathType Leaf)
        } | Sort-Object FullName)
    foreach ($theme in $themeDirectories) {
        $themeResult = Invoke-JsonValidator -ScriptPath $promptValidator -Arguments @{
            ProfessionPath = $profession.FullName
            ThemePath      = $theme.FullName
            RepoRoot       = $repositoryRoot
        } -Label "Theme Prompt tree $($profession.Name)/$($theme.Name)"
        $promptResults.Add([pscustomobject]@{
                profession   = $profession.FullName
                theme        = $theme.FullName
                checkedFiles = [int]$themeResult.counts.checkedFiles
            })
    }

    $manifestPath = Join-Path $profession.FullName 'manifest.json'
    if (Test-Path -LiteralPath $manifestPath -PathType Leaf) {
        $manifest = Get-Content -LiteralPath $manifestPath -Raw -Encoding UTF8 | ConvertFrom-Json
        if ($null -ne $manifest.PSObject.Properties['fullSkillRelease']) {
            $releaseResult = Invoke-JsonValidator `
                -ScriptPath (Join-Path $repositoryRoot 'tools\Test-DnfReleaseClosure.ps1') `
                -Arguments @{ ProfessionManifestPath = $manifestPath; RepoRoot = $repositoryRoot; AsJson = $true } `
                -Label "Release closure $($profession.Name)"
            $releaseResults.Add($releaseResult)
        }
        if ($null -ne $manifest.PSObject.Properties['historicalFullSkillReleases'] -and
            @($manifest.historicalFullSkillReleases).Count -gt 0) {
            $historicalResult = Invoke-JsonValidator `
                -ScriptPath (Join-Path $repositoryRoot 'tools\Test-DnfHistoricalReleaseIntegrity.ps1') `
                -Arguments @{ ProfessionManifestPath = $manifestPath; RepoRoot = $repositoryRoot; AsJson = $true } `
                -Label "Historical release integrity $($profession.Name)"
            $historicalReleaseResults.Add($historicalResult)
        }
        if ($null -ne $manifest.PSObject.Properties['activityMigration']) {
            $migration = $manifest.activityMigration
            $manifestDirectory = Split-Path -Parent $manifestPath
            Assert-Condition -Condition (Test-ObjectProperty -Object $migration -Name 'workflow') `
                -Message "Activity migration has no registered workflow: $manifestPath"
            $workflow = $migration.workflow
            foreach ($name in @(
                    'path',
                    'workflowId',
                    'validator',
                    'runner',
                    'executeRequiresExplicitSwitch',
                    'resumeRequiresExecuteSwitch',
                    'network',
                    'deployment')) {
                Assert-Condition -Condition (Test-ObjectProperty -Object $workflow -Name $name) `
                    -Message "Activity workflow is missing '$name': $manifestPath"
            }
            Assert-Condition -Condition ($workflow.executeRequiresExplicitSwitch -eq $true -and
                $workflow.resumeRequiresExecuteSwitch -eq $true) `
                -Message "Activity workflow execution is not explicitly gated: $manifestPath"
            Assert-Condition -Condition ([string]$workflow.network -eq 'forbidden' -and
                [string]$workflow.deployment -eq 'forbidden') `
                -Message "Activity workflow network or deployment policy changed: $manifestPath"
            $workflowPath = Resolve-RepositoryPath -Value ([string]$workflow.path) `
                -BaseDirectory $manifestDirectory -RepositoryRoot $repositoryRoot `
                -Label 'Activity workflow'
            $workflowValidator = Resolve-RepositoryPath -Value ([string]$workflow.validator) `
                -BaseDirectory $manifestDirectory -RepositoryRoot $repositoryRoot `
                -Label 'Activity workflow validator'
            $workflowRunner = Resolve-RepositoryPath -Value ([string]$workflow.runner) `
                -BaseDirectory $manifestDirectory -RepositoryRoot $repositoryRoot `
                -Label 'Activity workflow runner'
            Assert-Condition -Condition (Test-Path -LiteralPath $workflowRunner -PathType Leaf) `
                -Message "Activity workflow runner was not found: $workflowRunner"
            Assert-Condition -Condition ($workflowValidator -ieq $fixedWorkflowValidator) `
                -Message "Activity workflow validator is not the fixed project entrypoint: $workflowValidator"
            Assert-Condition -Condition ($workflowRunner -ieq $fixedWorkflowRunner) `
                -Message "Activity workflow runner is not the fixed project entrypoint: $workflowRunner"
            $workflowGate = Invoke-JsonValidator -ScriptPath $fixedWorkflowValidator -Arguments @{
                WorkflowPath = $workflowPath
                RepoRoot     = $repositoryRoot
                AsJson       = $true
            } -Label "Activity workflow $($profession.Name)"
            $workflowDefinitions = @($workflowGate.workflows)
            Assert-Condition -Condition ($workflowDefinitions.Count -eq 1 -and
                [string]$workflowDefinitions[0].workflowId -eq [string]$workflow.workflowId -and
                [int]$workflowDefinitions[0].stepCount -gt 0) `
                -Message "Activity workflow identity differs from the manifest: $manifestPath"
            Assert-Condition -Condition ($workflowGate.deployment.authorized -eq $false -and
                $workflowGate.deployment.performed -eq $false -and
                $workflowGate.deployment.imagePacks2Write -eq $false -and
                $workflowGate.deployment.processOperation -eq $false) `
                -Message "Activity workflow static gate unexpectedly records deployment: $manifestPath"
            $workflowResults.Add([pscustomobject]@{
                    profession   = $profession.FullName
                    workflowPath = $workflowPath
                    workflowId   = [string]$workflow.workflowId
                    stepCount    = [int]$workflowDefinitions[0].stepCount
                    status       = 'passed'
                })

            $workflowDefinition = Get-Content -LiteralPath $workflowPath -Raw -Encoding UTF8 |
            ConvertFrom-Json
            $generationPolicyResult = Invoke-JsonValidator -ScriptPath $generationPolicyValidator -Arguments @{
                ThemePath      = [string]$workflowDefinition.themeRoot
                ProfessionPath = $profession.FullName
                WorkflowPath   = $workflowPath
                RepoRoot       = $repositoryRoot
                AsJson         = $true
            } -Label "Generation workflow policy $($profession.Name)"
            $generationWorkflowPolicyResults.Add($generationPolicyResult)

            $migrationValidator = Resolve-RepositoryPath `
                -Value ([string]$migration.validator) -BaseDirectory $manifestDirectory `
                -RepositoryRoot $repositoryRoot -Label 'Activity migration validator'
            $migrationPlan = Resolve-RepositoryPath `
                -Value ([string]$migration.resourcePlan.path) `
                -BaseDirectory $manifestDirectory -RepositoryRoot $repositoryRoot `
                -Label 'Activity migration resource plan'
            $matchingAdapters = New-Object 'Collections.Generic.List[object]'
            foreach ($registeredAdapter in @($adapterRegistry.adapters)) {
                if ([string]$registeredAdapter.mode -ne 'read-only' -or
                    [string]$registeredAdapter.network -ne 'forbidden') {
                    continue
                }
                $registeredScript = Resolve-RepositoryPath `
                    -Value ([string]$registeredAdapter.script) `
                    -BaseDirectory $repositoryRoot -RepositoryRoot $repositoryRoot `
                    -Label "Registered adapter $($registeredAdapter.id)"
                if ($registeredScript -ieq $migrationValidator) {
                    $matchingAdapters.Add($registeredAdapter)
                }
            }
            Assert-Condition -Condition ($matchingAdapters.Count -eq 1) `
                -Message "Activity migration validator must match exactly one read-only, forbidden-network adapter: $migrationValidator"
            $migrationAdapter = $matchingAdapters[0]
            $matchingWorkflowSteps = @($workflowDefinition.steps | Where-Object {
                    [string]$_.adapter -ceq [string]$migrationAdapter.id -and
                    [string]$_.mode -eq 'read-only'
                })
            Assert-Condition -Condition ($matchingWorkflowSteps.Count -eq 1) `
                -Message "Activity migration adapter must be used by exactly one read-only workflow step: $($migrationAdapter.id)"
            $migrationResult = Invoke-JsonValidator `
                -ScriptPath $migrationValidator `
                -Arguments @{ ResourcePlanPath = $migrationPlan; RepoRoot = $repositoryRoot; AsJson = $true } `
                -Label "Activity migration $($profession.Name)"
            Assert-Condition -Condition ([string]$migrationResult.planId -eq [string]$migration.resourcePlan.planId) `
                -Message "Activity migration planId mismatch: $($migrationResult.planId)/$($migration.resourcePlan.planId)"
            Assert-Condition -Condition ($migrationResult.readyForAggregation -eq $migration.readyForAggregation) `
                -Message "Activity migration readiness differs from the manifest: $($migrationResult.readyForAggregation)/$($migration.readyForAggregation)"
            Assert-Condition -Condition ($migrationResult.fullSkillCoverageProven -eq $false) `
                -Message 'The immutable activity resource plan must remain coverage=false.'
            Assert-Condition -Condition ($migrationResult.deployment -eq 'not-authorized-not-performed' -and
                $migration.deployment.authorized -eq $false -and $migration.deployment.performed -eq $false) `
                -Message 'Activity migration unexpectedly records deployment.'

            $activityStatus = [string]$migration.status
            if ($activityStatus -eq 'blocked-pre-aggregation') {
                Assert-Condition -Condition ($manifest.coverage.fullSkillCoverageProven -eq $false -and
                    $migration.fullSkillCoverageProven -eq $false -and
                    $migration.readyForAggregation -eq $false -and
                    -not (Test-ObjectProperty -Object $manifest -Name 'fullSkillRelease')) `
                    -Message 'Blocked activity state must remain coverage=false without fullSkillRelease.'
            }
            elseif ($activityStatus -eq 'offline-release-closed-client-pending') {
                Assert-Condition -Condition ($manifest.coverage.fullSkillCoverageProven -eq $true -and
                    $migration.fullSkillCoverageProven -eq $true -and
                    $migration.readyForAggregation -eq $true -and
                    (Test-ObjectProperty -Object $manifest -Name 'fullSkillRelease')) `
                    -Message 'Closed activity state must bind coverage=true to fullSkillRelease.'
                foreach ($name in @('finalSummary', 'manualReview', 'releaseReport')) {
                    Assert-Condition -Condition (Test-ObjectProperty -Object $migration -Name $name) `
                        -Message "Closed activity state is missing '$name'."
                }
            }
            else {
                throw "Unsupported activity migration status: $activityStatus"
            }
            $activityMigrationResults.Add($migrationResult)
        }
    }
}

$quarantinePath = Join-Path $repositoryRoot 'docs\legacy-quarantine.json'
Assert-Condition -Condition (Test-Path -LiteralPath $quarantinePath -PathType Leaf) `
    -Message "Legacy quarantine registry was not found: $quarantinePath"
$quarantine = Get-Content -LiteralPath $quarantinePath -Raw -Encoding UTF8 | ConvertFrom-Json
Assert-Condition -Condition ([string]$quarantine.status -eq 'legacy-unverified-quarantined') `
    -Message 'Legacy quarantine status changed.'
foreach ($name in @('buildEligible', 'releaseEligible', 'deploymentAuthorized', 'resourceMappingAuthority')) {
    Assert-Condition -Condition ($quarantine.policy.PSObject.Properties[$name].Value -eq $false) `
        -Message "Legacy quarantine policy.$name must be false."
}
Assert-Condition -Condition ($quarantine.deployment.authorized -eq $false -and
    $quarantine.deployment.performed -eq $false -and
    $quarantine.deployment.imagePacks2Write -eq $false -and
    $quarantine.deployment.processOperation -eq $false) `
    -Message 'Legacy quarantine unexpectedly records deployment.'

$quarantineDirectorySet = New-Object 'Collections.Generic.HashSet[string]' `
([StringComparer]::OrdinalIgnoreCase)
$quarantineAssets = New-Object System.Collections.Generic.List[object]
foreach ($directoryRecord in @($quarantine.directories)) {
    Assert-Condition -Condition ([string]$directoryRecord.status -eq 'quarantined-unverified' -and
        $directoryRecord.promotable -eq $false) `
        -Message "Legacy quarantine directory is promotable: $($directoryRecord.path)"
    $directoryPath = Resolve-RepositoryPath -Value ([string]$directoryRecord.path) `
        -BaseDirectory $repositoryRoot -RepositoryRoot $repositoryRoot `
        -Label 'Legacy quarantine directory'
    Assert-Condition -Condition (Test-Path -LiteralPath $directoryPath -PathType Container) `
        -Message "Legacy quarantine directory was not found: $directoryPath"
    Assert-Condition -Condition ((Split-Path -Parent $directoryPath) -ieq $repositoryRoot) `
        -Message "Legacy quarantine directory must be top-level: $directoryPath"
    Assert-Condition -Condition ($quarantineDirectorySet.Add($directoryPath)) `
        -Message "Duplicate legacy quarantine directory: $directoryPath"
    $expectedFiles = New-Object 'Collections.Generic.HashSet[string]' `
    ([StringComparer]::OrdinalIgnoreCase)
    foreach ($fileRecord in @($directoryRecord.files)) {
        Assert-Condition -Condition ([string]$fileRecord.classification -eq 'legacy-unverified-npk') `
            -Message "Legacy quarantine classification changed: $($fileRecord.path)"
        $filePath = Resolve-RepositoryPath -Value ([string]$fileRecord.path) `
            -BaseDirectory $repositoryRoot -RepositoryRoot $repositoryRoot `
            -Label 'Legacy quarantine file'
        Assert-Condition -Condition ((Split-Path -Parent $filePath) -ieq $directoryPath) `
            -Message "Legacy quarantine file is outside its directory: $filePath"
        Assert-Condition -Condition (Test-Path -LiteralPath $filePath -PathType Leaf) `
            -Message "Legacy quarantine file was not found: $filePath"
        Assert-Condition -Condition ($expectedFiles.Add($filePath)) `
            -Message "Duplicate legacy quarantine file: $filePath"
        $item = Get-Item -LiteralPath $filePath
        $actualHash = (Get-FileHash -LiteralPath $filePath -Algorithm SHA256).Hash
        $expectedTime = [DateTimeOffset]::Parse([string]$fileRecord.lastWriteTimeUtc).UtcDateTime
        Assert-Condition -Condition ($item.Length -eq [long]$fileRecord.length -and
            $actualHash -eq ([string]$fileRecord.sha256).ToUpperInvariant() -and
            $item.LastWriteTimeUtc -eq $expectedTime) `
            -Message "Legacy quarantine snapshot changed: $filePath"
        $quarantineAssets.Add([pscustomobject]@{
                path   = $filePath
                length = [long]$item.Length
                sha256 = $actualHash
                status = 'quarantined-unverified'
            })
    }
    $actualFiles = @(Get-ChildItem -LiteralPath $directoryPath -Recurse -File -Force)
    Assert-Condition -Condition ($actualFiles.Count -eq $expectedFiles.Count) `
        -Message "Legacy quarantine file set changed: $directoryPath"
    foreach ($actualFile in $actualFiles) {
        Assert-Condition -Condition ($expectedFiles.Contains($actualFile.FullName)) `
            -Message "Unregistered file exists in legacy quarantine: $($actualFile.FullName)"
    }
}

$infrastructureDirectories = @('.agents', '.codex', '.git', '.github', 'docs', 'tools', 'validation')
$professionDirectorySet = New-Object 'Collections.Generic.HashSet[string]' `
([StringComparer]::OrdinalIgnoreCase)
foreach ($profession in $professionDirectories) {
    $null = $professionDirectorySet.Add($profession.FullName)
}
$unmanagedTopLevelDirectories = @(
    Get-ChildItem -LiteralPath $repositoryRoot -Directory -Force | Where-Object {
        $_.Name -notin $infrastructureDirectories -and
        -not $professionDirectorySet.Contains($_.FullName) -and
        -not $quarantineDirectorySet.Contains($_.FullName)
    })
$unmanagedTopLevelDirectoryNames = @($unmanagedTopLevelDirectories | ForEach-Object {
        $_.FullName
    })
Assert-Condition -Condition ($unmanagedTopLevelDirectories.Count -eq 0) `
    -Message "Unmanaged top-level directories: $($unmanagedTopLevelDirectoryNames -join ', ')"
$unmanagedTopLevelFiles = @(Get-ChildItem -LiteralPath $repositoryRoot -File -Force | Where-Object {
        $_.Extension -ieq '.npk' -or $_.Name -ieq 'manifest.json'
    })
$unmanagedTopLevelFileNames = @($unmanagedTopLevelFiles | ForEach-Object {
        $_.FullName
    })
Assert-Condition -Condition ($unmanagedTopLevelFiles.Count -eq 0) `
    -Message "Unmanaged top-level NPK or manifest files: $($unmanagedTopLevelFileNames -join ', ')"

$gitDirectory = Join-Path $repositoryRoot '.git'
$gitDiffCheck = 'not-a-git-worktree'
if (Test-Path -LiteralPath $gitDirectory) {
    $previousErrorActionPreference = $ErrorActionPreference
    try {
        $ErrorActionPreference = 'Continue'
        $gitOutput = & git -C $repositoryRoot diff --check 2>&1 | Out-String
        $gitExitCode = $LASTEXITCODE
    }
    finally {
        $ErrorActionPreference = $previousErrorActionPreference
    }
    Assert-Condition -Condition ($gitExitCode -eq 0) -Message "git diff --check failed: $gitOutput"
    $gitDiffCheck = 'passed'
}

$promptArray = $promptResults.ToArray()
$releaseArray = $releaseResults.ToArray()
$historicalReleaseArray = $historicalReleaseResults.ToArray()
$activityMigrationArray = $activityMigrationResults.ToArray()
$generationWorkflowPolicyArray = $generationWorkflowPolicyResults.ToArray()
$workflowArray = $workflowResults.ToArray()
$quarantineAssetArray = $quarantineAssets.ToArray()
$skillArray = $skillResults.ToArray()
$copilotSkillMirrorArray = $copilotSkillMirrorResults.ToArray()
$result = [pscustomobject]@{
    schemaVersion                      = 1
    status                             = 'passed'
    mode                               = 'read-only project gate; no build, deployment, or process operation'
    repositoryRoot                     = $repositoryRoot
    jsonFileCount                      = $jsonFiles.Count
    skillCount                         = $skillArray.Count
    skills                             = $skillArray
    copilotSkillMirrorFileCount        = $copilotSkillMirrorArray.Count
    copilotSkillMirror                 = $copilotSkillMirrorArray
    powershell                         = $powerShellGate
    workflowFixtureGate                = $workflowFixtureGate
    releaseMetadataRollbackFixtureGate = $releaseRollbackFixtureGate
    professionCount                    = $professionDirectories.Count
    promptTreeGateCount                = $promptArray.Count
    promptTrees                        = $promptArray
    releaseClosureCount                = $releaseArray.Count
    releases                           = $releaseArray
    historicalReleaseGateCount         = $historicalReleaseArray.Count
    historicalReleases                 = $historicalReleaseArray
    activityMigrationGateCount         = $activityMigrationArray.Count
    activityMigrations                 = $activityMigrationArray
    generationWorkflowPolicyGateCount  = $generationWorkflowPolicyArray.Count
    generationWorkflowPolicies         = $generationWorkflowPolicyArray
    workflowGateCount                  = $workflowArray.Count
    workflows                          = $workflowArray
    legacyQuarantineDirectoryCount     = $quarantineDirectorySet.Count
    legacyQuarantineAssetCount         = $quarantineAssetArray.Count
    legacyQuarantineAssets             = $quarantineAssetArray
    unmanagedTopLevelDirectoryCount    = $unmanagedTopLevelDirectories.Count
    unmanagedTopLevelFileCount         = $unmanagedTopLevelFiles.Count
    gitDiffCheck                       = $gitDiffCheck
}

if ($AsJson) {
    $result | ConvertTo-Json -Depth 12
}
else {
    $result
}

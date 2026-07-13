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
Assert-Condition -Condition (Test-Path -LiteralPath $rootAgents -PathType Leaf) `
    -Message "Root AGENTS.md was not found: $rootAgents"
Assert-Condition -Condition (Test-Path -LiteralPath $skillPath -PathType Leaf) `
    -Message "Project dnf-patch-maker skill was not found: $skillPath"

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
        name = $skillName
        lineCount = $skillLines.Count
        referenceCount = [regex]::Matches($skillText, '\]\(([^)]+)\)').Count
        shortDescriptionLength = $shortDescription.Length
    })
}

$powerShellGate = Invoke-JsonValidator `
    -ScriptPath (Join-Path $repositoryRoot 'tools\Test-DnfPowerShellSource.ps1') `
    -Arguments @{ Path = $repositoryRoot; AsJson = $true } `
    -Label 'PowerShell source gate'

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
$promptResults = New-Object System.Collections.Generic.List[object]
$releaseResults = New-Object System.Collections.Generic.List[object]
$historicalReleaseResults = New-Object System.Collections.Generic.List[object]
$activityMigrationResults = New-Object System.Collections.Generic.List[object]
$professionDirectories = @(Get-ChildItem -LiteralPath $repositoryRoot -Directory | Where-Object {
    (Test-Path -LiteralPath (Join-Path $_.FullName 'AGENTS.md') -PathType Leaf) -and
    (Test-Path -LiteralPath (Join-Path $_.FullName 'prompts\README.md') -PathType Leaf)
} | Sort-Object FullName)

foreach ($profession in $professionDirectories) {
    $professionResult = Invoke-JsonValidator -ScriptPath $promptValidator -Arguments @{
        ProfessionPath = $profession.FullName
        RepoRoot = $repositoryRoot
    } -Label "Profession Prompt tree $($profession.Name)"
    $promptResults.Add([pscustomobject]@{
        profession = $profession.FullName
        theme = $null
        checkedFiles = [int]$professionResult.counts.checkedFiles
    })

    $themeDirectories = @(Get-ChildItem -LiteralPath $profession.FullName -Directory | Where-Object {
        (Test-Path -LiteralPath (Join-Path $_.FullName 'AGENTS.md') -PathType Leaf) -and
        (Test-Path -LiteralPath (Join-Path $_.FullName 'prompts\README.md') -PathType Leaf)
    } | Sort-Object FullName)
    foreach ($theme in $themeDirectories) {
        $themeResult = Invoke-JsonValidator -ScriptPath $promptValidator -Arguments @{
            ProfessionPath = $profession.FullName
            ThemePath = $theme.FullName
            RepoRoot = $repositoryRoot
        } -Label "Theme Prompt tree $($profession.Name)/$($theme.Name)"
        $promptResults.Add([pscustomobject]@{
            profession = $profession.FullName
            theme = $theme.FullName
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
            $migrationValidator = [IO.Path]::GetFullPath((Join-Path $manifestDirectory `
                ([string]$migration.validator).Replace('/', [IO.Path]::DirectorySeparatorChar)))
            $migrationPlan = [IO.Path]::GetFullPath((Join-Path $manifestDirectory `
                ([string]$migration.resourcePlan.path).Replace('/', [IO.Path]::DirectorySeparatorChar)))
            $migrationResult = Invoke-JsonValidator `
                -ScriptPath $migrationValidator `
                -Arguments @{ ResourcePlanPath = $migrationPlan; RepoRoot = $repositoryRoot; AsJson = $true } `
                -Label "Activity migration $($profession.Name)"
            Assert-Condition -Condition ([string]$migrationResult.planId -eq [string]$migration.resourcePlan.planId) `
                -Message "Activity migration planId mismatch: $($migrationResult.planId)/$($migration.resourcePlan.planId)"
            Assert-Condition -Condition ($migrationResult.readyForAggregation -eq $migration.readyForAggregation) `
                -Message "Activity migration readiness differs from the manifest: $($migrationResult.readyForAggregation)/$($migration.readyForAggregation)"
            Assert-Condition -Condition ($migrationResult.fullSkillCoverageProven -eq $false -and
                $migration.fullSkillCoverageProven -eq $false) `
                -Message 'Activity migration must remain coverage=false before final release closure.'
            Assert-Condition -Condition ($migrationResult.deployment -eq 'not-authorized-not-performed' -and
                $migration.deployment.authorized -eq $false -and $migration.deployment.performed -eq $false) `
                -Message 'Activity migration unexpectedly records deployment.'
            $activityMigrationResults.Add($migrationResult)
        }
    }
}

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
$skillArray = $skillResults.ToArray()
$result = [pscustomobject]@{
    schemaVersion = 1
    status = 'passed'
    mode = 'read-only project gate; no build, deployment, or process operation'
    repositoryRoot = $repositoryRoot
    jsonFileCount = $jsonFiles.Count
    skillCount = $skillArray.Count
    skills = $skillArray
    powershell = $powerShellGate
    professionCount = $professionDirectories.Count
    promptTreeGateCount = $promptArray.Count
    promptTrees = $promptArray
    releaseClosureCount = $releaseArray.Count
    releases = $releaseArray
    historicalReleaseGateCount = $historicalReleaseArray.Count
    historicalReleases = $historicalReleaseArray
    activityMigrationGateCount = $activityMigrationArray.Count
    activityMigrations = $activityMigrationArray
    gitDiffCheck = $gitDiffCheck
}

if ($AsJson) {
    $result | ConvertTo-Json -Depth 12
}
else {
    $result
}

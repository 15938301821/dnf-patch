[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)]
    [string]$ThemePath,

    [string]$ProfessionPath,

    [string]$WorkflowPath,

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

function Resolve-FullPath {
    param(
        [Parameter(Mandatory = $true)][string]$Value,
        [Parameter(Mandatory = $true)][string]$BaseDirectory,
        [Parameter(Mandatory = $true)][string]$Label
    )

    Assert-Condition -Condition (-not [string]::IsNullOrWhiteSpace($Value)) `
        -Message "$Label path is empty."
    $native = $Value.Replace('/', [IO.Path]::DirectorySeparatorChar)
    if ([IO.Path]::IsPathRooted($native)) {
        return [IO.Path]::GetFullPath($native)
    }
    return [IO.Path]::GetFullPath((Join-Path $BaseDirectory $native))
}

function Test-ObjectProperty {
    param([object]$Object, [string]$Name)

    return $null -ne $Object -and $null -ne $Object.PSObject.Properties[$Name]
}

function Add-Issue {
    param(
        [System.Collections.Generic.List[object]]$Issues,
        [string]$Code,
        [string]$Message,
        [object]$Details = $null
    )

    $Issues.Add([pscustomobject]@{
            code    = $Code
            message = $Message
            details = $Details
        })
}

function Get-RegisteredWorkflowFromManifest {
    param(
        [Parameter(Mandatory = $true)][string]$ManifestPath,
        [Parameter(Mandatory = $true)][string]$RepositoryRoot
    )

    $manifest = Get-Content -LiteralPath $ManifestPath -Raw -Encoding UTF8 | ConvertFrom-Json
    if (-not (Test-ObjectProperty -Object $manifest -Name 'activityMigration') -or
        -not (Test-ObjectProperty -Object $manifest.activityMigration -Name 'workflow')) {
        return $null
    }
    $manifestDirectory = Split-Path -Parent $ManifestPath
    $workflow = $manifest.activityMigration.workflow
    return [pscustomobject]@{
        workflowId                  = [string]$workflow.workflowId
        path                        = Resolve-FullPath -Value ([string]$workflow.path) `
            -BaseDirectory $manifestDirectory -Label 'manifest workflow'
        executeRequiresExplicitSwitch = $workflow.executeRequiresExplicitSwitch
        resumeRequiresExecuteSwitch = $workflow.resumeRequiresExecuteSwitch
        network                     = [string]$workflow.network
        deployment                  = [string]$workflow.deployment
    }
}

$defaultRoot = Split-Path -Parent $PSScriptRoot
$repositoryRoot = if ([string]::IsNullOrWhiteSpace($RepoRoot)) {
    (Resolve-Path -LiteralPath $defaultRoot).Path
}
else {
    (Resolve-Path -LiteralPath (Resolve-FullPath -Value $RepoRoot -BaseDirectory $defaultRoot -Label 'repository root')).Path
}
$themeRoot = (Resolve-Path -LiteralPath (Resolve-FullPath -Value $ThemePath -BaseDirectory $repositoryRoot -Label 'theme')).Path
$professionRoot = if ([string]::IsNullOrWhiteSpace($ProfessionPath)) {
    Split-Path -Parent $themeRoot
}
else {
    (Resolve-Path -LiteralPath (Resolve-FullPath -Value $ProfessionPath -BaseDirectory $repositoryRoot -Label 'profession')).Path
}
$manifestPath = Join-Path $professionRoot 'manifest.json'
$themeAgentsPath = Join-Path $themeRoot 'AGENTS.md'
$professionAgentsPath = Join-Path $professionRoot 'AGENTS.md'
foreach ($required in @($manifestPath, $themeAgentsPath, $professionAgentsPath)) {
    Assert-Condition -Condition (Test-Path -LiteralPath $required -PathType Leaf) `
        -Message "Required workflow policy input was not found: $required"
}

$registeredWorkflow = Get-RegisteredWorkflowFromManifest -ManifestPath $manifestPath `
    -RepositoryRoot $repositoryRoot
$workflowFile = if ([string]::IsNullOrWhiteSpace($WorkflowPath)) {
    if ($null -ne $registeredWorkflow) { $registeredWorkflow.path } else { $null }
}
else {
    Resolve-FullPath -Value $WorkflowPath -BaseDirectory $repositoryRoot -Label 'workflow'
}

$issues = New-Object System.Collections.Generic.List[object]
if ($null -eq $registeredWorkflow) {
    Add-Issue -Issues $issues -Code 'missing-registered-workflow' `
        -Message 'Profession manifest must register the default model and Aseprite workflow.'
}
elseif ($registeredWorkflow.executeRequiresExplicitSwitch -ne $true -or
    $registeredWorkflow.resumeRequiresExecuteSwitch -ne $true) {
    Add-Issue -Issues $issues -Code 'workflow-execution-not-explicitly-gated' `
        -Message 'Registered workflow must require explicit Execute and Resume gating.' `
        -Details $registeredWorkflow
}
elseif ($registeredWorkflow.network -ne 'forbidden' -or
    $registeredWorkflow.deployment -ne 'forbidden') {
    Add-Issue -Issues $issues -Code 'workflow-policy-relaxed' `
        -Message 'Registered workflow must forbid network and deployment by default.' `
        -Details $registeredWorkflow
}

if ([string]::IsNullOrWhiteSpace($workflowFile) -or
    -not (Test-Path -LiteralPath $workflowFile -PathType Leaf)) {
    Add-Issue -Issues $issues -Code 'workflow-file-missing' `
        -Message 'Default generation workflow file is missing.' `
        -Details ([pscustomobject]@{ path = $workflowFile })
}
else {
    $workflow = Get-Content -LiteralPath $workflowFile -Raw -Encoding UTF8 | ConvertFrom-Json
    $requiredSteps = @(
        'powershell-source-gate',
        'local-toolchain-gate',
        'migration-readiness-gate',
        'aggregate-package',
        'final-validation'
    )
    $stepIds = @($workflow.steps | ForEach-Object { [string]$_.id })
    foreach ($stepId in $requiredSteps) {
        if ($stepId -notin $stepIds) {
            Add-Issue -Issues $issues -Code 'workflow-required-step-missing' `
                -Message "Default generation workflow is missing step '$stepId'." `
                -Details ([pscustomobject]@{ workflow = $workflowFile; step = $stepId })
        }
    }
    $policy = $workflow.policy
    if ($policy.executeRequiresExplicitSwitch -ne $true -or
        [string]$policy.network -ne 'forbidden' -or
        [string]$policy.deployment -ne 'forbidden' -or
        [string]$policy.imagePacks2Write -ne 'forbidden') {
        Add-Issue -Issues $issues -Code 'workflow-policy-invalid' `
            -Message 'Default generation workflow must require explicit execution and forbid network, deployment, and ImagePacks2 writes.' `
            -Details $policy
    }
}

$themeText = Get-Content -LiteralPath $themeAgentsPath -Raw -Encoding UTF8
foreach ($requiredText in @(
        'default-generation-requires-official-source-model-prompt-package-aseprite-runtime-evidence',
        'legacy-diagnostic-endpoint-recolor-only',
        'missing-model-or-aseprite-evidence-must-block'
    )) {
    if (-not $themeText.Contains($requiredText)) {
        Add-Issue -Issues $issues -Code 'theme-policy-text-missing' `
            -Message "Theme policy is missing required marker: $requiredText"
    }
}

$result = [pscustomobject]@{
    schemaVersion = 1
    status        = if ($issues.Count -eq 0) { 'passed' } else { 'failed' }
    policy        = 'default-generation-requires-official-source-model-prompt-package-aseprite-runtime-evidence'
    repositoryRoot = $repositoryRoot
    professionPath = $professionRoot
    themePath     = $themeRoot
    workflowPath  = $workflowFile
    issueCount    = $issues.Count
    issues        = $issues.ToArray()
    deployment    = [pscustomobject]@{
        authorized      = $false
        performed       = $false
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

if ($issues.Count -gt 0) {
    exit 1
}

[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)]
    [string]$SourceWorkflowPath,

    [Parameter(Mandatory = $true)]
    [string]$OutputWorkflowPath,

    [Parameter(Mandatory = $true)]
    [ValidateRange(2, 2147483647)]
    [int]$Revision
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

function Assert-Condition {
    param([bool]$Condition, [string]$Message)

    if (-not $Condition) {
        throw $Message
    }
}

function Resolve-RepositoryPath {
    param([string]$RepositoryRoot, [string]$Value)

    $native = $Value.Replace('/', [IO.Path]::DirectorySeparatorChar)
    if (-not [IO.Path]::IsPathRooted($native)) {
        $native = Join-Path $RepositoryRoot $native
    }
    return [IO.Path]::GetFullPath($native)
}

function Convert-WorkflowNode {
    param(
        [object]$Value,
        [System.Collections.Specialized.OrderedDictionary]$Replacements
    )

    if ($null -eq $Value) {
        return $null
    }
    if ($Value -is [string]) {
        $text = [string]$Value
        foreach ($entry in $Replacements.GetEnumerator()) {
            $text = $text.Replace([string]$entry.Key, [string]$entry.Value)
        }
        return $text
    }
    if ($Value -is [System.Array]) {
        $items = New-Object System.Collections.Generic.List[object]
        foreach ($item in $Value) {
            $items.Add((Convert-WorkflowNode -Value $item -Replacements $Replacements))
        }
        return , $items.ToArray()
    }
    if ($Value -is [pscustomobject]) {
        $record = [ordered]@{}
        foreach ($property in $Value.PSObject.Properties) {
            $record[$property.Name] = Convert-WorkflowNode -Value $property.Value `
                -Replacements $Replacements
        }
        return [pscustomobject]$record
    }
    return $Value
}

$repositoryRoot = (Resolve-Path -LiteralPath (Split-Path -Parent $PSScriptRoot)).Path
$sourcePath = Resolve-RepositoryPath -RepositoryRoot $repositoryRoot -Value $SourceWorkflowPath
$outputPath = Resolve-RepositoryPath -RepositoryRoot $repositoryRoot -Value $OutputWorkflowPath
Assert-Condition (Test-Path -LiteralPath $sourcePath -PathType Leaf) `
    "Source workflow was not found: $sourcePath"
Assert-Condition (-not (Test-Path -LiteralPath $outputPath)) `
    "Refusing to overwrite an existing workflow: $outputPath"
Assert-Condition ([IO.Path]::GetDirectoryName($sourcePath) -eq [IO.Path]::GetDirectoryName($outputPath)) `
    'The revised workflow must remain beside its source workflow.'

$source = Get-Content -LiteralPath $sourcePath -Raw -Encoding UTF8 | ConvertFrom-Json
$sourceRevision = $Revision - 1
$expectedSourceId = "weaponmaster.vergil.aseprite-full-skill-v$sourceRevision"
$expectedOutputId = "weaponmaster.vergil.aseprite-full-skill-v$Revision"
Assert-Condition ([string]$source.workflowId -eq $expectedSourceId) `
    "Unexpected source workflow identity: $($source.workflowId)/$expectedSourceId"
Assert-Condition ([int]$source.schemaVersion -eq 1 -and @($source.steps).Count -gt 0) `
    'Source workflow structure is invalid.'
Assert-Condition ($source.policy.executeRequiresExplicitSwitch -eq $true -and
    [string]$source.policy.network -eq 'forbidden' -and
    [string]$source.policy.deployment -eq 'forbidden' -and
    [string]$source.policy.imagePacks2Write -eq 'forbidden') `
    'Source workflow execution or deployment policy changed.'

$sourceThemeRoot = [string]$source.themeRoot
$sourceProfessionRoot = @($sourceThemeRoot.Split('/'))[0]
Assert-Condition (-not [string]::IsNullOrWhiteSpace($sourceProfessionRoot) -and
    -not $sourceThemeRoot.StartsWith('jobs/', [StringComparison]::Ordinal)) `
    'Source workflow is not a pre-jobs workflow.'
$sourceWorkflowName = [IO.Path]::GetFileName($sourcePath)
$outputWorkflowName = [IO.Path]::GetFileName($outputPath)
$replacements = [ordered]@{
    $expectedSourceId = $expectedOutputId
    $sourceWorkflowName = $outputWorkflowName
    'resource-plan-v4.json' = 'resource-plan-v5.json'
    ($sourceProfessionRoot + '/') = ('jobs/' + $sourceProfessionRoot + '/')
    ('-{{runId}}-v' + $sourceRevision) = ('-{{runId}}-v' + $Revision)
}
$revised = Convert-WorkflowNode -Value $source -Replacements $replacements

Assert-Condition ([string]$revised.workflowId -eq $expectedOutputId) `
    'Revised workflow identity is invalid.'
Assert-Condition ([string]$revised.themeRoot -eq ('jobs/' + $sourceThemeRoot)) `
    'Revised workflow theme root is invalid.'
Assert-Condition ([string]$revised.runRoot -eq ('jobs/' + [string]$source.runRoot)) `
    'Revised workflow run root is invalid.'
Assert-Condition (@($revised.steps).Count -eq @($source.steps).Count) `
    'Revised workflow step count changed.'
Assert-Condition ($revised.policy.executeRequiresExplicitSwitch -eq $true -and
    [string]$revised.policy.network -eq 'forbidden' -and
    [string]$revised.policy.deployment -eq 'forbidden' -and
    [string]$revised.policy.imagePacks2Write -eq 'forbidden') `
    'Revised workflow execution or deployment policy changed.'

$parent = Split-Path -Parent $outputPath
$temporaryPath = Join-Path $parent ('.' + [IO.Path]::GetFileName($outputPath) +
    '.' + [Guid]::NewGuid().ToString('N') + '.tmp')
try {
    $revised | ConvertTo-Json -Depth 100 | Set-Content -LiteralPath $temporaryPath -Encoding UTF8
    $check = Get-Content -LiteralPath $temporaryPath -Raw -Encoding UTF8 | ConvertFrom-Json
    Assert-Condition ([string]$check.workflowId -eq $expectedOutputId -and
        [string]$check.themeRoot -eq ('jobs/' + $sourceThemeRoot) -and
        @($check.steps).Count -eq @($source.steps).Count) `
        'Temporary revised workflow verification failed.'
    [IO.File]::Move($temporaryPath, $outputPath)
}
finally {
    if (Test-Path -LiteralPath $temporaryPath) {
        Remove-Item -LiteralPath $temporaryPath -Force
    }
}

$outputItem = Get-Item -LiteralPath $outputPath
[pscustomobject]@{
    Status = 'passed'
    SourceWorkflow = $sourcePath
    OutputWorkflow = $outputPath
    WorkflowId = $expectedOutputId
    StepCount = @($revised.steps).Count
    Length = [long]$outputItem.Length
    Sha256 = (Get-FileHash -LiteralPath $outputPath -Algorithm SHA256).Hash
    Deployment = 'not-authorized-not-performed'
} | Format-List
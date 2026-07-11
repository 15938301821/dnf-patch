[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)]
    [string]$SourceResourcePlanPath,

    [Parameter(Mandatory = $true)]
    [string]$OutputResourcePlanPath,

    [Parameter(Mandatory = $true)]
    [ValidateRange(1, 2147483647)]
    [int]$Revision
)

$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest

function Assert-Condition {
    param([bool]$Condition, [string]$Message)

    if (-not $Condition) {
        throw $Message
    }
}

function Resolve-RepoPath {
    param([string]$RepoRoot, [string]$Value)

    $native = $Value.Replace('/', [IO.Path]::DirectorySeparatorChar)
    if (-not [IO.Path]::IsPathRooted($native)) {
        $native = Join-Path $RepoRoot $native
    }
    return [IO.Path]::GetFullPath($native)
}

function Get-RepoRelativePath {
    param([string]$RepoRoot, [string]$Path)

    $root = [IO.Path]::GetFullPath($RepoRoot).TrimEnd(
        [IO.Path]::DirectorySeparatorChar,
        [IO.Path]::AltDirectorySeparatorChar) + [IO.Path]::DirectorySeparatorChar
    $rootUri = New-Object Uri $root
    $pathUri = New-Object Uri ([IO.Path]::GetFullPath($Path))
    return [Uri]::UnescapeDataString($rootUri.MakeRelativeUri($pathUri).ToString()).Replace('\', '/')
}

function Get-FileSnapshot {
    param([string]$RepoRoot, [string]$Path, [string]$Kind)

    $item = Get-Item -LiteralPath $Path
    return [pscustomobject][ordered]@{
        kind = $Kind
        path = Get-RepoRelativePath -RepoRoot $RepoRoot -Path $item.FullName
        length = $item.Length
        lastWriteTime = $item.LastWriteTime.ToString('o')
        sha256 = (Get-FileHash -LiteralPath $item.FullName -Algorithm SHA256).Hash
    }
}

$repoRoot = (Resolve-Path -LiteralPath (Split-Path -Parent $PSScriptRoot)).Path
$sourcePath = Resolve-RepoPath -RepoRoot $repoRoot -Value $SourceResourcePlanPath
$outputPath = Resolve-RepoPath -RepoRoot $repoRoot -Value $OutputResourcePlanPath

Assert-Condition -Condition (Test-Path -LiteralPath $sourcePath -PathType Leaf) `
    -Message "Source resource plan was not found: $sourcePath"
Assert-Condition -Condition (-not (Test-Path -LiteralPath $outputPath)) `
    -Message "Refusing to overwrite an existing resource plan: $outputPath"
Assert-Condition -Condition ([IO.Path]::GetDirectoryName($sourcePath) -eq [IO.Path]::GetDirectoryName($outputPath)) `
    -Message 'The revised resource plan must remain beside its source plan.'

$plan = Get-Content -LiteralPath $sourcePath -Raw -Encoding UTF8 | ConvertFrom-Json
$sourceRevision = $Revision - 1
$expectedSourcePlanId = "weaponmaster-vergil-dark-blue-full-skill-v$sourceRevision"
$expectedOutputPlanId = "weaponmaster-vergil-dark-blue-full-skill-v$Revision"

Assert-Condition -Condition ($Revision -gt 1 -and [string]$plan.planId -eq $expectedSourcePlanId) `
    -Message "Unexpected source plan identity: $($plan.planId)/$expectedSourcePlanId"
Assert-Condition -Condition ([int]$plan.schemaVersion -eq 1 -and
    $plan.themeId -eq 'weaponmaster-vergil-dark-blue' -and
    $plan.status -eq 'components-offline-validated-final-aggregation-pending') `
    -Message 'Source resource plan is not at the reviewed post-build gate.'
Assert-Condition -Condition ($plan.coverage.fullSkillCoverageProven -eq $false -and
    $plan.deployment.authorized -eq $false -and $plan.deployment.performed -eq $false) `
    -Message 'Source resource plan must remain pre-release and non-deploying.'
Assert-Condition -Condition (@($plan.components).Count -eq 31 -and @($plan.reuseComponents).Count -eq 1) `
    -Message 'Source resource plan component scope changed.'

$contractSnapshots = @($plan.evidence.contractSnapshots)
$rootRuleEntries = @($contractSnapshots | Where-Object { [string]$_.path -eq 'AGENTS.md' })
$manifestEntries = @($contractSnapshots | Where-Object { [IO.Path]::GetFileName([string]$_.path) -ieq 'manifest.json' })

Assert-Condition -Condition ($rootRuleEntries.Count -eq 1 -and $manifestEntries.Count -eq 1) `
    -Message 'Source resource plan must contain one root-rules snapshot and one profession-manifest snapshot.'

$rootRulesPath = Join-Path $repoRoot 'AGENTS.md'
$manifestPath = Resolve-RepoPath -RepoRoot $repoRoot -Value ([string]$manifestEntries[0].path)
$rootRulesSnapshot = Get-FileSnapshot -RepoRoot $repoRoot -Path $rootRulesPath -Kind 'contract'
$manifestSnapshot = Get-FileSnapshot -RepoRoot $repoRoot -Path $manifestPath -Kind 'contract'
$rootRuleIndex = [Array]::IndexOf($contractSnapshots, $rootRuleEntries[0])
$manifestIndex = [Array]::IndexOf($contractSnapshots, $manifestEntries[0])
$contractSnapshots[$rootRuleIndex] = $rootRulesSnapshot
$contractSnapshots[$manifestIndex] = $manifestSnapshot
$plan.evidence.contractSnapshots = $contractSnapshots
$plan.planId = $expectedOutputPlanId
$plan.generatedAt = (Get-Date).ToString('o')

$outputDirectory = Split-Path -Parent $outputPath
$temporaryPath = Join-Path $outputDirectory ('.' + [IO.Path]::GetFileName($outputPath) + '.' + [Guid]::NewGuid().ToString('N') + '.tmp')
try {
    $plan | ConvertTo-Json -Depth 100 | Set-Content -LiteralPath $temporaryPath -Encoding UTF8
    $check = Get-Content -LiteralPath $temporaryPath -Raw -Encoding UTF8 | ConvertFrom-Json
    Assert-Condition -Condition ([string]$check.planId -eq $expectedOutputPlanId -and
        $check.coverage.fullSkillCoverageProven -eq $false -and
        $check.deployment.authorized -eq $false -and $check.deployment.performed -eq $false -and
        @($check.components).Count -eq 31 -and @($check.reuseComponents).Count -eq 1) `
        -Message 'Temporary revised resource plan verification failed.'
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
    SourceResourcePlan = $sourcePath
    OutputResourcePlan = $outputPath
    PlanId = $expectedOutputPlanId
    Length = $outputItem.Length
    Sha256 = (Get-FileHash -LiteralPath $outputPath -Algorithm SHA256).Hash
    FullSkillCoverageProven = $false
    Deployment = 'not-authorized-not-performed'
} | Format-List

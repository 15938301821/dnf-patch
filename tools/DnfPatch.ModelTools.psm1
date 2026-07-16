Set-StrictMode -Version Latest

Import-Module (Join-Path $PSScriptRoot 'DnfPatch.Toolchain.psm1') -Force

$script:AllowedToolIds = @(
    'resource.resolve-profession-theme',
    'resource.snapshot-file',
    'prompt.compose-style-brief',
    'style.normalize-operations',
    'image.ver5-dds-endpoint-recolor',
    'image.ver2-argb-recolor',
    'package.custom-npk',
    'validate.npk-index',
    'validate.npk-pixels',
    'validate.full-frame-export',
    'workflow.invoke-registered-dag',
    'workflow.policy.default-generation'
)

function Test-DnfModelProperty {
    param([object]$Object, [string]$Name)

    return $null -ne $Object -and $null -ne $Object.PSObject.Properties[$Name]
}

function Assert-DnfModelCondition {
    param(
        [Parameter(Mandatory = $true)][bool]$Condition,
        [Parameter(Mandatory = $true)][string]$Message
    )

    if (-not $Condition) {
        throw $Message
    }
}

function Test-DnfModelRelativePath {
    param([string]$Value)

    if ([string]::IsNullOrWhiteSpace($Value)) {
        return $false
    }
    $native = $Value.Replace('/', [IO.Path]::DirectorySeparatorChar)
    if ([IO.Path]::IsPathRooted($native)) {
        return $false
    }
    if ($Value -match '(^|[\\/])\.\.([\\/]|$)') {
        return $false
    }
    return $Value -notmatch ':'
}

function Assert-DnfModelPathInside {
    param(
        [Parameter(Mandatory = $true)][string]$Path,
        [Parameter(Mandatory = $true)][string]$Root,
        [Parameter(Mandatory = $true)][string]$Label
    )

    $fullPath = [IO.Path]::GetFullPath($Path)
    $fullRoot = [IO.Path]::GetFullPath($Root).TrimEnd(
        [IO.Path]::DirectorySeparatorChar,
        [IO.Path]::AltDirectorySeparatorChar)
    $prefix = $fullRoot + [IO.Path]::DirectorySeparatorChar
    if (-not ($fullPath.Equals($fullRoot, [StringComparison]::OrdinalIgnoreCase) -or
            $fullPath.StartsWith($prefix, [StringComparison]::OrdinalIgnoreCase))) {
        throw "$Label must stay inside '$fullRoot': $fullPath"
    }
}

function Resolve-DnfModelRepositoryPath {
    param(
        [Parameter(Mandatory = $true)][string]$Value,
        [Parameter(Mandatory = $true)][string]$RepositoryRoot,
        [string]$BaseDirectory = $RepositoryRoot,
        [string]$Label = 'Model path'
    )

    $native = $Value.Replace('/', [IO.Path]::DirectorySeparatorChar)
    $resolved = if ([IO.Path]::IsPathRooted($native)) {
        [IO.Path]::GetFullPath($native)
    }
    else {
        [IO.Path]::GetFullPath((Join-Path $BaseDirectory $native))
    }
    Assert-DnfModelPathInside -Path $resolved -Root $RepositoryRoot -Label $Label
    return $resolved
}

function Get-DnfModelRelativePath {
    param(
        [Parameter(Mandatory = $true)][string]$Path,
        [Parameter(Mandatory = $true)][string]$RepositoryRoot
    )

    $fullPath = [IO.Path]::GetFullPath($Path)
    $root = [IO.Path]::GetFullPath($RepositoryRoot).TrimEnd(
        [IO.Path]::DirectorySeparatorChar,
        [IO.Path]::AltDirectorySeparatorChar)
    Assert-DnfModelPathInside -Path $fullPath -Root $root -Label 'Relative path source'
    if ($fullPath.Equals($root, [StringComparison]::OrdinalIgnoreCase)) {
        return '.'
    }
    return $fullPath.Substring($root.Length + 1).Replace('\', '/')
}

function Get-DnfModelToolCatalog {
    [CmdletBinding()]
    param()

    $tools = @(
        [ordered]@{
            id          = 'resource.resolve-profession-theme'
            category    = 'resource'
            mode        = 'read-only'
            description = 'Resolve repository, profession, theme, manifest, AGENTS, prompt indexes, and local source roots.'
            parameters  = @('professionPath', 'themePath', 'manifestPath')
            writes      = @()
        },
        [ordered]@{
            id          = 'resource.snapshot-file'
            category    = 'resource'
            mode        = 'read-only'
            description = 'Create length and SHA-256 snapshots for repository files used as evidence.'
            parameters  = @('path')
            writes      = @()
        },
        [ordered]@{
            id          = 'prompt.compose-style-brief'
            category    = 'style'
            mode        = 'read-only'
            description = 'Compose source geometry policy, profession prompt, theme AGENTS, theme prompt, and model style intent into a deterministic style brief.'
            parameters  = @('professionPromptPath', 'themeAgentPath', 'themePromptPath', 'styleIntent')
            writes      = @()
        },
        [ordered]@{
            id          = 'style.normalize-operations'
            category    = 'style'
            mode        = 'read-only'
            description = 'Normalize model generated style operations into a safe DSL; arbitrary code is rejected.'
            parameters  = @('operations', 'palette', 'geometryPolicy')
            writes      = @()
            defaultGenerationEligible = $true
        },
        [ordered]@{
            id          = 'workflow.policy.default-generation'
            category    = 'workflow-policy'
            mode        = 'read-only'
            description = 'Default patch generation must start from official source frames, bind profession prompt plus theme AGENTS plus theme prompt, require model style evidence, require Aseprite layered project and runtime PNG evidence, then package and validate through the registered workflow.'
            parameters  = @('themePath', 'professionPath', 'workflowPath')
            writes      = @()
            defaultGenerationEligible = $true
        },
        [ordered]@{
            id          = 'image.ver5-dds-endpoint-recolor'
            category    = 'legacy-diagnostic'
            mode        = 'workspace-write-explicit-opt-in-only'
            description = 'Legacy diagnostic only. Applies Ver5 DDS BC1/BC3 endpoint recolor; forbidden for normal patch generation because it does not create model output, Aseprite layered projects, or runtime PNG evidence.'
            parameters  = @('configPath', 'imagePacks2', 'texdiagPath', 'allowLegacyEndpointRecolor')
            writes      = @('componentNpkPath', 'buildSummaryPath')
            defaultGenerationEligible = $false
            requiresExplicitLegacyOptIn = $true
        },
        [ordered]@{
            id          = 'image.ver2-argb-recolor'
            category    = 'legacy-diagnostic'
            mode        = 'workspace-write-explicit-opt-in-only'
            description = 'Legacy diagnostic only. Applies Ver2 ARGB same-format recolor; forbidden for normal patch generation because it does not create model output, Aseprite layered projects, or runtime PNG evidence.'
            parameters  = @('configPath', 'imagePacks2', 'allowLegacyEndpointRecolor')
            writes      = @('componentNpkPath', 'buildSummaryPath')
            defaultGenerationEligible = $false
            requiresExplicitLegacyOptIn = $true
        },
        [ordered]@{
            id          = 'package.custom-npk'
            category    = 'packaging'
            mode        = 'workspace-write'
            description = 'Package authorized IMG payloads from current workflow outputs into a custom NPK with payload equivalence summary.'
            parameters  = @('sourceNpk', 'includeImgPath', 'outputPath', 'summaryPath')
            writes      = @('outputPath', 'summaryPath')
            defaultGenerationEligible = $true
        },
        [ordered]@{
            id          = 'validate.npk-index'
            category    = 'validation'
            mode        = 'read-only'
            description = 'Independently validate NPK header hash, entry count, unique paths, and IMG magic.'
            parameters  = @('path', 'expectedEntryCount', 'expectedSha256')
            writes      = @()
        },
        [ordered]@{
            id          = 'validate.npk-pixels'
            category    = 'validation'
            mode        = 'read-only-or-report-write'
            description = 'Decode frames and report transparent, black, and pixel-state anomalies for a path pattern.'
            parameters  = @('inputFile', 'pathPattern', 'outputFile')
            writes      = @('outputFile')
        },
        [ordered]@{
            id          = 'validate.full-frame-export'
            category    = 'validation'
            mode        = 'workspace-write'
            description = 'Export full-frame black, white, and checkerboard contact sheets and frame inventory for review.'
            parameters  = @('inputFile', 'outputDirectory', 'framesPerPage')
            writes      = @('outputDirectory')
        },
        [ordered]@{
            id          = 'workflow.invoke-registered-dag'
            category    = 'workflow'
            mode        = 'read-only-or-workspace-write'
            description = 'Invoke a registered workflow through the fixed adapter registry, explicit Execute switch, RunId, snapshots, and recovery checks.'
            parameters  = @('workflowPath', 'runId', 'execute', 'resume')
            writes      = @('workflow declared outputs only')
        }
    )

    return [pscustomobject]@{
        schemaVersion = 1
        status        = 'passed'
        policy        = [pscustomobject]@{
            arbitraryModelCodeExecution               = 'forbidden'
            resourceFactsFromModel                    = 'forbidden'
            network                                   = 'forbidden-by-default'
            deployment                                = 'forbidden-without-current-user-authorization'
            imagePacks2Write                          = 'forbidden'
            sourceNpkAccess                           = 'read-only'
            defaultGenerationWorkflow                 = 'official-source-frames-plus-model-prompt-package-plus-aseprite-layered-projects-plus-runtime-png-plus-registered-workflow-validation'
            endpointRecolorDefault                    = 'forbidden-legacy-diagnostic-explicit-opt-in-only'
            existingArtifactReuseForNewGeneration     = 'forbidden-except-baseline-or-evidence'
            executionRequiresSchemaAndManifestBinding = $true
        }
        tools         = @($tools | ForEach-Object { [pscustomobject]$_ })
    }
}

function Get-DnfModelPromptSnapshot {
    param(
        [Parameter(Mandatory = $true)][string]$Path,
        [Parameter(Mandatory = $true)][string]$RepositoryRoot,
        [Parameter(Mandatory = $true)][string]$Label
    )

    $resolved = Resolve-DnfModelRepositoryPath -Value $Path -RepositoryRoot $RepositoryRoot -Label $Label
    if (-not (Test-Path -LiteralPath $resolved -PathType Leaf)) {
        throw "$Label was not found: $resolved"
    }
    $snapshot = Get-DnfFileSnapshot -Path $resolved
    return [pscustomobject]@{
        label  = $Label
        path   = Get-DnfModelRelativePath -Path $resolved -RepositoryRoot $RepositoryRoot
        length = [long]$snapshot.length
        sha256 = [string]$snapshot.sha256
    }
}

function ConvertTo-DnfModelStyleOperation {
    param([object]$Operation)

    Assert-DnfModelCondition -Condition (Test-DnfModelProperty -Object $Operation -Name 'type') `
        -Message 'Every style operation must include type.'
    $type = [string]$Operation.type
    if ($type -notin @('palette-map', 'rim-light', 'particle-trail', 'spatial-crack', 'blade-core', 'alpha-preserve')) {
        throw "Unsupported style operation type: $type"
    }

    $record = [ordered]@{
        type = $type
    }
    foreach ($property in @($Operation.PSObject.Properties | Sort-Object Name)) {
        if ($property.Name -eq 'type') {
            continue
        }
        if ($property.Name -notin @('target', 'color', 'colorStops', 'intensity', 'density', 'direction', 'blend', 'notes')) {
            throw "Unsupported style operation property '$($property.Name)' on $type."
        }
        if ($property.Name -eq 'blend' -and [string]$property.Value -notin @('source-preserving', 'additive-reference-only', 'normal-reference-only')) {
            throw "Unsupported style operation blend: $($property.Value)"
        }
        $record[$property.Name] = $property.Value
    }
    return [pscustomobject]$record
}

function New-DnfModelStylePlan {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)][string]$RequestPath,
        [string]$OutputPath,
        [string]$RepositoryRoot = (Get-DnfPatchRepositoryRoot)
    )

    $repo = (Resolve-Path -LiteralPath $RepositoryRoot).Path
    $requestFile = Resolve-DnfModelRepositoryPath -Value $RequestPath -RepositoryRoot $repo -Label 'Model request'
    if (-not (Test-Path -LiteralPath $requestFile -PathType Leaf)) {
        throw "Model request was not found: $requestFile"
    }
    $request = Get-Content -LiteralPath $requestFile -Raw -Encoding UTF8 | ConvertFrom-Json
    Assert-DnfModelCondition -Condition ([int]$request.schemaVersion -eq 1) `
        -Message "Unsupported model request schemaVersion: $($request.schemaVersion)"
    Assert-DnfModelCondition -Condition (Test-DnfModelProperty -Object $request -Name 'professionPath') `
        -Message 'Model request must include professionPath.'
    Assert-DnfModelCondition -Condition (Test-DnfModelProperty -Object $request -Name 'themePath') `
        -Message 'Model request must include themePath.'
    Assert-DnfModelCondition -Condition (Test-DnfModelProperty -Object $request -Name 'promptBinding') `
        -Message 'Model request must include promptBinding.'
    Assert-DnfModelCondition -Condition (Test-DnfModelProperty -Object $request -Name 'styleIntent') `
        -Message 'Model request must include styleIntent.'

    $professionPath = Resolve-DnfModelRepositoryPath -Value ([string]$request.professionPath) -RepositoryRoot $repo -Label 'Profession path'
    $themePath = Resolve-DnfModelRepositoryPath -Value ([string]$request.themePath) -RepositoryRoot $repo -Label 'Theme path'
    Assert-DnfModelCondition -Condition (Test-Path -LiteralPath $professionPath -PathType Container) `
        -Message "Profession path was not found: $professionPath"
    Assert-DnfModelCondition -Condition (Test-Path -LiteralPath $themePath -PathType Container) `
        -Message "Theme path was not found: $themePath"
    Assert-DnfModelPathInside -Path $themePath -Root $professionPath -Label 'Theme path'

    $manifestPath = Join-Path $professionPath 'manifest.json'
    Assert-DnfModelCondition -Condition (Test-Path -LiteralPath $manifestPath -PathType Leaf) `
        -Message "Profession manifest was not found: $manifestPath"
    $themeAgentPath = Join-Path $themePath 'AGENTS.md'
    Assert-DnfModelCondition -Condition (Test-Path -LiteralPath $themeAgentPath -PathType Leaf) `
        -Message "Theme AGENTS.md was not found: $themeAgentPath"

    $binding = $request.promptBinding
    foreach ($required in @('themeAgentPath', 'professionPromptPath', 'themePromptPath', 'uiFrameGeometryPolicy')) {
        Assert-DnfModelCondition -Condition (Test-DnfModelProperty -Object $binding -Name $required) `
            -Message "promptBinding.$required is required."
    }
    Assert-DnfModelCondition -Condition ([string]$binding.uiFrameGeometryPolicy -eq 'strict-preserve-source-frame-position-size') `
        -Message 'Only strict-preserve-source-frame-position-size is allowed for model generated style plans.'

    $themeAgentSnapshot = Get-DnfModelPromptSnapshot -Path ([string]$binding.themeAgentPath) -RepositoryRoot $repo -Label 'Theme AGENTS'
    $professionPromptSnapshot = Get-DnfModelPromptSnapshot -Path ([string]$binding.professionPromptPath) -RepositoryRoot $repo -Label 'Profession prompt'
    $themePromptSnapshot = Get-DnfModelPromptSnapshot -Path ([string]$binding.themePromptPath) -RepositoryRoot $repo -Label 'Theme prompt'
    Assert-DnfModelCondition -Condition ((Resolve-DnfModelRepositoryPath -Value ([string]$binding.themeAgentPath) -RepositoryRoot $repo -Label 'Theme AGENTS binding').Equals($themeAgentPath, [StringComparison]::OrdinalIgnoreCase)) `
        -Message 'promptBinding.themeAgentPath must target the selected theme AGENTS.md.'
    Assert-DnfModelPathInside -Path (Resolve-DnfModelRepositoryPath -Value ([string]$binding.professionPromptPath) -RepositoryRoot $repo -Label 'Profession prompt binding') `
        -Root (Join-Path $professionPath 'prompts') -Label 'Profession prompt binding'
    Assert-DnfModelPathInside -Path (Resolve-DnfModelRepositoryPath -Value ([string]$binding.themePromptPath) -RepositoryRoot $repo -Label 'Theme prompt binding') `
        -Root (Join-Path $themePath 'prompts') -Label 'Theme prompt binding'

    $operationResults = New-Object System.Collections.Generic.List[object]
    foreach ($operation in @($request.styleIntent.operations)) {
        $operationResults.Add((ConvertTo-DnfModelStyleOperation -Operation $operation))
    }
    Assert-DnfModelCondition -Condition ($operationResults.Count -gt 0) `
        -Message 'styleIntent.operations must contain at least one safe operation.'

    $palette = @($request.styleIntent.palette | ForEach-Object { [string]$_ })
    foreach ($color in $palette) {
        Assert-DnfModelCondition -Condition ($color -match '^#[0-9A-Fa-f]{6}$') `
            -Message "Palette color must be #RRGGBB: $color"
    }

    $catalog = Get-DnfModelToolCatalog
    $plan = [ordered]@{
        schemaVersion  = 1
        status         = 'passed'
        mode           = 'model-output-normalized-to-safe-style-plan; no build or deployment performed'
        repositoryRoot = $repo
        request        = [ordered]@{
            path   = Get-DnfModelRelativePath -Path $requestFile -RepositoryRoot $repo
            sha256 = (Get-FileHash -LiteralPath $requestFile -Algorithm SHA256).Hash
        }
        scope          = [ordered]@{
            professionPath = Get-DnfModelRelativePath -Path $professionPath -RepositoryRoot $repo
            themePath      = Get-DnfModelRelativePath -Path $themePath -RepositoryRoot $repo
            manifest       = Get-DnfModelPromptSnapshot -Path $manifestPath -RepositoryRoot $repo -Label 'Profession manifest'
        }
        promptBinding  = [ordered]@{
            priority              = if (Test-DnfModelProperty -Object $binding -Name 'priority') { [int]$binding.priority } else { 1 }
            uiFrameGeometryPolicy = [string]$binding.uiFrameGeometryPolicy
            themeAgent            = $themeAgentSnapshot
            professionPrompt      = $professionPromptSnapshot
            themePrompt           = $themePromptSnapshot
        }
        style          = [ordered]@{
            palette               = $palette
            operations            = $operationResults.ToArray()
            arbitraryCodeAccepted = $false
        }
        availableTools = $catalog.tools
        nextStep       = 'Bind this style plan to manifest-authorized source frames, then run the registered model and Aseprite workflow; endpoint recolor tools are legacy diagnostics and are not valid default generation outputs.'
        deployment     = 'not-authorized-not-performed'
    }

    $result = [pscustomobject]$plan
    if (-not [string]::IsNullOrWhiteSpace($OutputPath)) {
        $outputFile = Resolve-DnfModelRepositoryPath -Value $OutputPath -RepositoryRoot $repo -Label 'Style plan output'
        if (Test-Path -LiteralPath $outputFile) {
            throw "Refusing to overwrite existing style plan: $outputFile"
        }
        $directory = Split-Path -Parent $outputFile
        if (-not [string]::IsNullOrWhiteSpace($directory)) {
            New-Item -ItemType Directory -Path $directory -Force | Out-Null
        }
        $result | ConvertTo-Json -Depth 20 | Set-Content -LiteralPath $outputFile -Encoding UTF8
    }
    return $result
}

Export-ModuleMember -Function @(
    'Get-DnfModelToolCatalog',
    'New-DnfModelStylePlan'
)

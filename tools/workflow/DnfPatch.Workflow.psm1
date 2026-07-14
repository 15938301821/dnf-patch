Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
$script:ModulePath = $PSCommandPath
$script:Sha256Pattern = '^[0-9A-F]{64}$'
$script:IdentifierPattern = '^[a-z0-9]+(?:[.-][a-z0-9]+)*$'

function Test-DnfProperty {
    param([object]$Object, [string]$Name)

    return $null -ne $Object -and $null -ne $Object.PSObject.Properties[$Name]
}

function Get-DnfPropertyValue {
    param([object]$Object, [string]$Name, [object]$Default = $null)

    if (-not (Test-DnfProperty -Object $Object -Name $Name)) {
        return $Default
    }
    return $Object.PSObject.Properties[$Name].Value
}

function Get-DnfRepositoryRoot {
    param([string]$RepositoryRoot)

    $defaultRoot = Split-Path -Parent (Split-Path -Parent $PSScriptRoot)
    $candidate = if ([string]::IsNullOrWhiteSpace($RepositoryRoot)) {
        $defaultRoot
    }
    else {
        $RepositoryRoot
    }
    if (-not (Test-Path -LiteralPath $candidate -PathType Container)) {
        throw "Repository root was not found: $candidate"
    }
    return (Resolve-Path -LiteralPath $candidate).Path
}

function Test-DnfPathInside {
    param([string]$Path, [string]$Root)

    $fullPath = [IO.Path]::GetFullPath($Path)
    $fullRoot = [IO.Path]::GetFullPath($Root).TrimEnd(
        [IO.Path]::DirectorySeparatorChar,
        [IO.Path]::AltDirectorySeparatorChar)
    if ($fullPath.Equals($fullRoot, [StringComparison]::OrdinalIgnoreCase)) {
        return $true
    }
    $prefix = $fullRoot + [IO.Path]::DirectorySeparatorChar
    return $fullPath.StartsWith($prefix, [StringComparison]::OrdinalIgnoreCase)
}

function Assert-DnfPathInside {
    param([string]$Path, [string]$Root, [string]$Label)

    if (-not (Test-DnfPathInside -Path $Path -Root $Root)) {
        throw "$Label must stay inside '$Root': $Path"
    }
}

function Assert-DnfNoReparsePointPath {
    param([string]$Path, [string]$RepositoryRoot, [string]$Label)

    $candidate = [IO.Path]::GetFullPath($Path)
    $root = [IO.Path]::GetFullPath($RepositoryRoot).TrimEnd(
        [IO.Path]::DirectorySeparatorChar,
        [IO.Path]::AltDirectorySeparatorChar)
    Assert-DnfPathInside -Path $candidate -Root $root -Label $Label
    while ($true) {
        if (Test-Path -LiteralPath $candidate) {
            $item = Get-Item -LiteralPath $candidate -Force
            if (($item.Attributes -band [IO.FileAttributes]::ReparsePoint) -ne 0) {
                throw "$Label cannot traverse a reparse point: $($item.FullName)"
            }
        }
        if ($candidate.Equals($root, [StringComparison]::OrdinalIgnoreCase)) {
            break
        }
        $parent = Split-Path -Parent $candidate
        if ([string]::IsNullOrWhiteSpace($parent) -or $parent -eq $candidate) {
            throw "$Label path ancestry could not be resolved: $Path"
        }
        $candidate = $parent
    }
}

function ConvertTo-DnfNativePath {
    param([string]$Value)

    return $Value.Replace('/', [IO.Path]::DirectorySeparatorChar).Replace(
        '\', [IO.Path]::DirectorySeparatorChar)
}

function Expand-DnfWorkflowText {
    param(
        [string]$Value,
        [string]$RepositoryRoot,
        [object]$Workflow,
        [string]$RunId
    )

    $themeRoot = [IO.Path]::GetFullPath((Join-Path $RepositoryRoot (
                ConvertTo-DnfNativePath -Value ([string]$Workflow.themeRoot))))
    $runRoot = [IO.Path]::GetFullPath((Join-Path $RepositoryRoot (
                ConvertTo-DnfNativePath -Value ([string]$Workflow.runRoot))))
    $runDirectory = Join-Path $runRoot $RunId
    $expanded = $Value
    $tokens = [ordered]@{
        '{{repositoryRoot}}' = $RepositoryRoot
        '{{themeRoot}}'      = $themeRoot
        '{{runRoot}}'        = $runRoot
        '{{runDirectory}}'   = $runDirectory
        '{{runId}}'          = $RunId
    }
    foreach ($token in $tokens.Keys) {
        $expanded = $expanded.Replace($token, [string]$tokens[$token])
    }
    if ($expanded -match '\{\{[^{}]+\}\}') {
        throw "Unknown workflow token in value: $Value"
    }
    return $expanded
}

function Resolve-DnfWorkflowPath {
    param(
        [string]$Value,
        [string]$RepositoryRoot,
        [object]$Workflow,
        [string]$RunId,
        [string]$Label
    )

    if ([string]::IsNullOrWhiteSpace($Value)) {
        throw "$Label path is empty."
    }
    $expanded = Expand-DnfWorkflowText -Value $Value -RepositoryRoot $RepositoryRoot `
        -Workflow $Workflow -RunId $RunId
    $native = ConvertTo-DnfNativePath -Value $expanded
    $path = if ([IO.Path]::IsPathRooted($native)) {
        [IO.Path]::GetFullPath($native)
    }
    else {
        [IO.Path]::GetFullPath((Join-Path $RepositoryRoot $native))
    }
    Assert-DnfPathInside -Path $path -Root $RepositoryRoot -Label $Label
    Assert-DnfNoReparsePointPath -Path $path -RepositoryRoot $RepositoryRoot `
        -Label $Label
    return $path
}

function Get-DnfRelativePath {
    param([string]$Path, [string]$RepositoryRoot)

    Assert-DnfPathInside -Path $Path -Root $RepositoryRoot -Label 'Snapshot path'
    $root = $RepositoryRoot.TrimEnd(
        [IO.Path]::DirectorySeparatorChar,
        [IO.Path]::AltDirectorySeparatorChar)
    if ($Path.Equals($root, [StringComparison]::OrdinalIgnoreCase)) {
        return '.'
    }
    return $Path.Substring($root.Length + 1).Replace('\', '/')
}

function ConvertTo-DnfPlainObject {
    param([object]$Value)

    if ($null -eq $Value -or $Value -is [string] -or $Value -is [ValueType]) {
        return $Value
    }
    if ($Value -is [Collections.IDictionary]) {
        $result = [ordered]@{}
        foreach ($key in @($Value.Keys | Sort-Object { [string]$_ })) {
            $result[[string]$key] = ConvertTo-DnfPlainObject -Value $Value[$key]
        }
        return $result
    }
    if ($Value -is [Collections.IEnumerable]) {
        return @($Value | ForEach-Object { ConvertTo-DnfPlainObject -Value $_ })
    }
    $properties = @($Value.PSObject.Properties | Where-Object {
            $_.MemberType -in @('NoteProperty', 'Property')
        } | Sort-Object Name)
    $objectResult = [ordered]@{}
    foreach ($property in $properties) {
        $objectResult[$property.Name] = ConvertTo-DnfPlainObject -Value $property.Value
    }
    return $objectResult
}

function ConvertTo-DnfCanonicalJson {
    param([object]$Value)

    return (ConvertTo-DnfPlainObject -Value $Value) | ConvertTo-Json -Depth 50 -Compress
}

function Get-DnfTextSha256 {
    param([string]$Text)

    $sha = [Security.Cryptography.SHA256]::Create()
    try {
        $bytes = [Text.Encoding]::UTF8.GetBytes($Text)
        return [BitConverter]::ToString($sha.ComputeHash($bytes)).Replace('-', '')
    }
    finally {
        $sha.Dispose()
    }
}

function Get-DnfFileSha256 {
    param([string]$Path)

    return (Get-FileHash -LiteralPath $Path -Algorithm SHA256).Hash
}

function New-DnfPathSnapshot {
    param(
        [string]$Id,
        [string]$Path,
        [string]$Kind,
        [string]$RepositoryRoot
    )

    Assert-DnfNoReparsePointPath -Path $Path -RepositoryRoot $RepositoryRoot `
        -Label "Snapshot path $Id"
    if ($Kind -eq 'file') {
        if (-not (Test-Path -LiteralPath $Path -PathType Leaf)) {
            throw "Snapshot file was not found: $Path"
        }
        $item = Get-Item -LiteralPath $Path
        return [pscustomobject]@{
            id     = $Id
            path   = Get-DnfRelativePath -Path $item.FullName -RepositoryRoot $RepositoryRoot
            kind   = 'file'
            length = [long]$item.Length
            sha256 = Get-DnfFileSha256 -Path $item.FullName
        }
    }
    if ($Kind -ne 'directory') {
        throw "Unsupported snapshot kind '$Kind' for $Id."
    }
    if (-not (Test-Path -LiteralPath $Path -PathType Container)) {
        throw "Snapshot directory was not found: $Path"
    }
    $directory = (Resolve-Path -LiteralPath $Path).Path
    Assert-DnfPathInside -Path $directory -Root $RepositoryRoot -Label "Snapshot directory $Id"
    $reparseEntries = @(Get-ChildItem -LiteralPath $directory -Force -Recurse |
        Where-Object {
            ($_.Attributes -band [IO.FileAttributes]::ReparsePoint) -ne 0
        })
    if ($reparseEntries.Count -gt 0) {
        throw "Snapshot directory $Id contains a reparse point: $($reparseEntries[0].FullName)"
    }
    $lines = New-Object 'Collections.Generic.List[string]'
    $length = 0L
    foreach ($file in @(Get-ChildItem -LiteralPath $directory -File -Recurse | Sort-Object FullName)) {
        Assert-DnfPathInside -Path $file.FullName -Root $directory -Label "Snapshot file $Id"
        $relative = $file.FullName.Substring($directory.Length + 1).Replace('\', '/')
        $hash = Get-DnfFileSha256 -Path $file.FullName
        $length += [long]$file.Length
        $lines.Add("$relative|$($file.Length)|$hash")
    }
    return [pscustomobject]@{
        id     = $Id
        path   = Get-DnfRelativePath -Path $directory -RepositoryRoot $RepositoryRoot
        kind   = 'directory'
        length = $length
        sha256 = Get-DnfTextSha256 -Text ($lines.ToArray() -join "`n")
    }
}

function Test-DnfSnapshotCurrent {
    param([object]$Snapshot, [string]$RepositoryRoot)

    try {
        $path = if ([string]$Snapshot.path -eq '.') {
            $RepositoryRoot
        }
        else {
            [IO.Path]::GetFullPath((Join-Path $RepositoryRoot (
                        ConvertTo-DnfNativePath -Value ([string]$Snapshot.path))))
        }
        $current = New-DnfPathSnapshot -Id ([string]$Snapshot.id) -Path $path `
            -Kind ([string]$Snapshot.kind) -RepositoryRoot $RepositoryRoot
        return [long]$current.length -eq [long]$Snapshot.length -and
        [string]$current.sha256 -eq ([string]$Snapshot.sha256).ToUpperInvariant()
    }
    catch {
        return $false
    }
}

function Get-DnfObjectPathValue {
    param([object]$Object, [string]$Path)

    $current = $Object
    foreach ($segment in $Path.Split('.')) {
        if ($null -eq $current) {
            return [pscustomobject]@{ found = $false; value = $null }
        }
        if ($current -is [Collections.IDictionary]) {
            if (-not $current.Contains($segment)) {
                return [pscustomobject]@{ found = $false; value = $null }
            }
            $current = $current[$segment]
            continue
        }
        $property = $current.PSObject.Properties[$segment]
        if ($null -eq $property) {
            return [pscustomobject]@{ found = $false; value = $null }
        }
        $current = $property.Value
    }
    return [pscustomobject]@{ found = $true; value = $current }
}

function Test-DnfValueEqual {
    param([object]$Left, [object]$Right)

    return (ConvertTo-DnfCanonicalJson -Value $Left) -ceq (
        ConvertTo-DnfCanonicalJson -Value $Right)
}

function Test-DnfSuccessPredicates {
    param([object]$Result, [object]$Success, [object]$Parameters)

    $reports = New-Object 'Collections.Generic.List[object]'
    foreach ($predicate in @($Success.all)) {
        $resolved = Get-DnfObjectPathValue -Object $Result -Path ([string]$predicate.path)
        $passed = $false
        $expected = $null
        if ($resolved.found) {
            switch ([string]$predicate.operator) {
                'equals' {
                    $expected = Get-DnfPropertyValue -Object $predicate -Name 'value'
                    $passed = Test-DnfValueEqual -Left $resolved.value -Right $expected
                }
                'notEquals' {
                    $expected = Get-DnfPropertyValue -Object $predicate -Name 'value'
                    $passed = -not (Test-DnfValueEqual -Left $resolved.value -Right $expected)
                }
                'isTrue' {
                    $expected = $true
                    $passed = $resolved.value -eq $true
                }
                'isFalse' {
                    $expected = $false
                    $passed = $resolved.value -eq $false
                }
                'greaterThan' {
                    $expected = Get-DnfPropertyValue -Object $predicate -Name 'value'
                    try {
                        $passed = [decimal]$resolved.value -gt [decimal]$expected
                    }
                    catch {
                        $passed = $false
                    }
                }
                'equalsParameter' {
                    $parameterName = [string](Get-DnfPropertyValue -Object $predicate -Name 'parameter')
                    $parameterValue = Get-DnfObjectPathValue -Object $Parameters -Path $parameterName
                    if ($parameterValue.found) {
                        $expected = $parameterValue.value
                        $passed = Test-DnfValueEqual -Left $resolved.value -Right $expected
                    }
                }
            }
        }
        $reports.Add([pscustomobject]@{
                path     = [string]$predicate.path
                operator = [string]$predicate.operator
                actual   = $resolved.value
                expected = $expected
                passed   = [bool]$passed
            })
    }
    return $reports.ToArray()
}

function Expand-DnfParameterValue {
    param(
        [object]$Value,
        [string]$RepositoryRoot,
        [object]$Workflow,
        [string]$RunId
    )

    if ($null -eq $Value) {
        return $null
    }
    if ($Value -is [string]) {
        return Expand-DnfWorkflowText -Value $Value -RepositoryRoot $RepositoryRoot `
            -Workflow $Workflow -RunId $RunId
    }
    if ($Value -is [ValueType]) {
        return $Value
    }
    if ($Value -is [Collections.IEnumerable] -and -not ($Value -is [Collections.IDictionary])) {
        return @($Value | ForEach-Object {
                Expand-DnfParameterValue -Value $_ -RepositoryRoot $RepositoryRoot `
                    -Workflow $Workflow -RunId $RunId
            })
    }
    $result = [ordered]@{}
    foreach ($property in @($Value.PSObject.Properties)) {
        $result[$property.Name] = Expand-DnfParameterValue -Value $property.Value `
            -RepositoryRoot $RepositoryRoot -Workflow $Workflow -RunId $RunId
    }
    return [pscustomobject]$result
}

function ConvertTo-DnfParameterHashtable {
    param([object]$Parameters)

    $result = @{}
    foreach ($property in @($Parameters.PSObject.Properties)) {
        $result[$property.Name] = $property.Value
    }
    return $result
}

function Get-DnfAdapterMap {
    param([object]$Registry)

    $map = @{}
    foreach ($adapter in @($Registry.adapters)) {
        $id = [string]$adapter.id
        if ($map.ContainsKey($id)) {
            throw "Adapter registry contains duplicate id '$id'."
        }
        $map[$id] = $adapter
    }
    return $map
}

function Get-DnfTopologicalOrder {
    param([object[]]$Steps)

    $byId = @{}
    $indegree = @{}
    foreach ($step in $Steps) {
        $id = [string]$step.id
        $byId[$id] = $step
        $indegree[$id] = @($step.dependsOn).Count
    }
    $ready = New-Object 'Collections.Generic.List[string]'
    foreach ($id in @($indegree.Keys | Sort-Object)) {
        if ([int]$indegree[$id] -eq 0) {
            $ready.Add($id)
        }
    }
    $ordered = New-Object 'Collections.Generic.List[string]'
    while ($ready.Count -gt 0) {
        $id = $ready[0]
        $ready.RemoveAt(0)
        $ordered.Add($id)
        foreach ($candidate in @($Steps | Sort-Object id)) {
            if (@($candidate.dependsOn) -contains $id) {
                $candidateId = [string]$candidate.id
                $indegree[$candidateId] = [int]$indegree[$candidateId] - 1
                if ([int]$indegree[$candidateId] -eq 0) {
                    $ready.Add($candidateId)
                    $sorted = @($ready | Sort-Object)
                    $ready.Clear()
                    foreach ($value in $sorted) {
                        $ready.Add($value)
                    }
                }
            }
        }
    }
    if ($ordered.Count -ne $Steps.Count) {
        throw 'Workflow dependency graph contains a cycle.'
    }
    return $ordered.ToArray()
}

function Test-DnfWorkflowDefinition {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [string]$WorkflowPath,
        [string]$RegistryPath,
        [string]$RepositoryRoot,
        [switch]$ThrowOnError
    )

    $errors = New-Object 'Collections.Generic.List[string]'
    $repo = $null
    $workflowFile = $null
    $registryFile = $null
    $workflow = $null
    $registry = $null
    $topologicalOrder = @()
    try {
        $repo = Get-DnfRepositoryRoot -RepositoryRoot $RepositoryRoot
        $workflowFile = [IO.Path]::GetFullPath($WorkflowPath)
        if (-not [IO.Path]::IsPathRooted($WorkflowPath)) {
            $workflowFile = [IO.Path]::GetFullPath((Join-Path $repo $WorkflowPath))
        }
        Assert-DnfPathInside -Path $workflowFile -Root $repo -Label 'Workflow'
        Assert-DnfNoReparsePointPath -Path $workflowFile -RepositoryRoot $repo `
            -Label 'Workflow'
        if (-not (Test-Path -LiteralPath $workflowFile -PathType Leaf)) {
            throw "Workflow was not found: $workflowFile"
        }
        $registryFile = if ([string]::IsNullOrWhiteSpace($RegistryPath)) {
            Join-Path $PSScriptRoot 'adapter-registry.json'
        }
        elseif ([IO.Path]::IsPathRooted($RegistryPath)) {
            [IO.Path]::GetFullPath($RegistryPath)
        }
        else {
            [IO.Path]::GetFullPath((Join-Path $repo $RegistryPath))
        }
        Assert-DnfPathInside -Path $registryFile -Root $repo -Label 'Adapter registry'
        Assert-DnfNoReparsePointPath -Path $registryFile -RepositoryRoot $repo `
            -Label 'Adapter registry'
        if (-not (Test-Path -LiteralPath $registryFile -PathType Leaf)) {
            throw "Adapter registry was not found: $registryFile"
        }
        $workflow = Get-Content -LiteralPath $workflowFile -Raw -Encoding UTF8 | ConvertFrom-Json
        $registry = Get-Content -LiteralPath $registryFile -Raw -Encoding UTF8 | ConvertFrom-Json
    }
    catch {
        $errors.Add($_.Exception.Message)
    }

    if ($null -ne $workflow -and $null -ne $registry) {
        if ([int](Get-DnfPropertyValue $workflow 'schemaVersion' 0) -ne 1) {
            $errors.Add('Workflow schemaVersion must be 1.')
        }
        if ([int](Get-DnfPropertyValue $registry 'schemaVersion' 0) -ne 1) {
            $errors.Add('Adapter registry schemaVersion must be 1.')
        }
        foreach ($required in @('workflowId', 'themeRoot', 'runRoot', 'policy', 'steps')) {
            if (-not (Test-DnfProperty -Object $workflow -Name $required)) {
                $errors.Add("Workflow is missing '$required'.")
            }
        }
        $workflowId = [string](Get-DnfPropertyValue $workflow 'workflowId')
        if ($workflowId -notmatch $script:IdentifierPattern) {
            $errors.Add("Workflow id has an invalid format: '$workflowId'.")
        }
        $sampleRunId = 'static-validation-run'
        if ($null -ne $workflow.policy) {
            $policyChecks = [ordered]@{
                executeRequiresExplicitSwitch = $true
                deployment                    = 'forbidden'
                processOperations             = 'forbidden'
                imagePacks2Write              = 'forbidden'
                requireFreshRunDirectory      = $true
            }
            foreach ($name in $policyChecks.Keys) {
                $actual = Get-DnfPropertyValue -Object $workflow.policy -Name $name
                if (-not (Test-DnfValueEqual -Left $actual -Right $policyChecks[$name])) {
                    $errors.Add("Workflow policy '$name' must equal '$($policyChecks[$name])'.")
                }
            }
            $networkPolicy = [string](Get-DnfPropertyValue $workflow.policy 'network')
            if ($networkPolicy -notin @('forbidden', 'explicit-authorization-required')) {
                $errors.Add("Unsupported workflow network policy '$networkPolicy'.")
            }
            $recovery = Get-DnfPropertyValue $workflow.policy 'recovery'
            foreach ($name in @(
                    'requireWorkflowHash',
                    'requireRegistryHash',
                    'requireRunnerHash',
                    'requireAdapterScriptHash',
                    'requireParameterHash',
                    'requireInputSnapshots',
                    'requireOutputSnapshots')) {
                if ($null -eq $recovery -or (Get-DnfPropertyValue $recovery $name) -ne $true) {
                    $errors.Add("Workflow recovery policy '$name' must be true.")
                }
            }
        }

        $adapterMap = $null
        try {
            $adapterMap = Get-DnfAdapterMap -Registry $registry
        }
        catch {
            $errors.Add($_.Exception.Message)
        }
        if ($null -ne $adapterMap) {
            foreach ($adapter in @($registry.adapters)) {
                $adapterId = [string]$adapter.id
                if ($adapterId -notmatch $script:IdentifierPattern) {
                    $errors.Add("Adapter id has an invalid format: '$adapterId'.")
                }
                if ([string]$adapter.host -notin @(
                        'windows-powershell-x64', 'windows-powershell-x86')) {
                    $errors.Add("Adapter '$adapterId' has unsupported host '$($adapter.host)'.")
                }
                if ([string]$adapter.mode -notin @('read-only', 'workspace-write')) {
                    $errors.Add("Adapter '$adapterId' has unsupported mode '$($adapter.mode)'.")
                }
                if ([string]$adapter.network -notin @(
                        'forbidden', 'explicit-authorization-required')) {
                    $errors.Add("Adapter '$adapterId' has unsupported network policy '$($adapter.network)'.")
                }
                try {
                    $adapterScript = Resolve-DnfWorkflowPath -Value ([string]$adapter.script) `
                        -RepositoryRoot $repo -Workflow $workflow -RunId $sampleRunId `
                        -Label "Adapter script $adapterId"
                    if (-not (Test-Path -LiteralPath $adapterScript -PathType Leaf)) {
                        $errors.Add("Adapter script was not found for '$adapterId': $adapterScript")
                    }
                }
                catch {
                    $errors.Add($_.Exception.Message)
                }
                $allowed = @($adapter.allowedParameters)
                if (@($allowed | Select-Object -Unique).Count -ne $allowed.Count) {
                    $errors.Add("Adapter '$adapterId' has duplicate allowed parameters.")
                }
                $pathParameters = @((Get-DnfPropertyValue $adapter 'pathParameters' @()))
                $writePathParameters = @((Get-DnfPropertyValue `
                            $adapter 'writePathParameters' @()))
                foreach ($parameterName in @($pathParameters + $writePathParameters)) {
                    if ($allowed -notcontains [string]$parameterName) {
                        $errors.Add("Adapter '$adapterId' declares unlisted path parameter '$parameterName'.")
                    }
                }
                foreach ($parameterName in $writePathParameters) {
                    if ($pathParameters -notcontains [string]$parameterName) {
                        $errors.Add("Adapter '$adapterId' write path '$parameterName' is not a path parameter.")
                    }
                }
                if ([string]$adapter.mode -eq 'read-only' -and $writePathParameters.Count -gt 0) {
                    $errors.Add("Read-only adapter '$adapterId' declares write path parameters.")
                }
                if (Test-DnfProperty -Object $adapter -Name 'forcedParameters') {
                    foreach ($property in @($adapter.forcedParameters.PSObject.Properties)) {
                        if ($allowed -notcontains $property.Name) {
                            $errors.Add("Adapter '$adapterId' forces unlisted parameter '$($property.Name)'.")
                        }
                    }
                }
            }

            $stepIds = @{}
            foreach ($step in @($workflow.steps)) {
                $stepId = [string](Get-DnfPropertyValue $step 'id')
                if ([string]::IsNullOrWhiteSpace($stepId)) {
                    $errors.Add('Workflow contains a step with an empty id.')
                    continue
                }
                if ($stepId -notmatch $script:IdentifierPattern) {
                    $errors.Add("Workflow step id has an invalid format: '$stepId'.")
                    continue
                }
                if ($stepIds.ContainsKey($stepId)) {
                    $errors.Add("Workflow contains duplicate step id '$stepId'.")
                }
                else {
                    $stepIds[$stepId] = $step
                }
            }
            foreach ($step in @($workflow.steps)) {
                $stepId = [string]$step.id
                $adapterId = [string](Get-DnfPropertyValue $step 'adapter')
                if (-not $adapterMap.ContainsKey($adapterId)) {
                    $errors.Add("Step '$stepId' references unknown adapter '$adapterId'.")
                    continue
                }
                $adapter = $adapterMap[$adapterId]
                if ([string]$step.mode -ne [string]$adapter.mode) {
                    $errors.Add("Step '$stepId' mode differs from adapter '$adapterId'.")
                }
                if ([string]$adapter.network -eq 'explicit-authorization-required' -and
                    [string]$workflow.policy.network -ne 'explicit-authorization-required') {
                    $errors.Add("Step '$stepId' requires a workflow network authorization policy.")
                }
                foreach ($dependency in @($step.dependsOn)) {
                    if (-not $stepIds.ContainsKey([string]$dependency)) {
                        $errors.Add("Step '$stepId' has missing dependency '$dependency'.")
                    }
                    if ([string]$dependency -eq $stepId) {
                        $errors.Add("Step '$stepId' depends on itself.")
                    }
                }
                $allowedParameters = @($adapter.allowedParameters)
                $pathParameterNames = @((Get-DnfPropertyValue $adapter 'pathParameters' @()))
                $writePathParameterNames = @((Get-DnfPropertyValue `
                            $adapter 'writePathParameters' @()))
                $expandedPathParameters = @{}
                foreach ($property in @($step.parameters.PSObject.Properties)) {
                    if ($allowedParameters -notcontains $property.Name) {
                        $errors.Add("Step '$stepId' uses disallowed parameter '$($property.Name)'.")
                    }
                    try {
                        $expandedParameter = Expand-DnfParameterValue -Value $property.Value `
                            -RepositoryRoot $repo -Workflow $workflow -RunId $sampleRunId
                        if ($pathParameterNames -contains $property.Name) {
                            if (-not ($expandedParameter -is [string]) -or
                                [string]::IsNullOrWhiteSpace([string]$expandedParameter)) {
                                throw "Path parameter '$($property.Name)' must be a non-empty string."
                            }
                            $expandedPathParameters[$property.Name] = Resolve-DnfWorkflowPath `
                                -Value ([string]$property.Value) -RepositoryRoot $repo `
                                -Workflow $workflow -RunId $sampleRunId `
                                -Label "Step path parameter $stepId/$($property.Name)"
                        }
                    }
                    catch {
                        $errors.Add("Step '$stepId' parameter '$($property.Name)': $($_.Exception.Message)")
                    }
                }
                $predicates = @($step.success.all)
                if ($predicates.Count -lt 2) {
                    $errors.Add("Step '$stepId' must declare at least two success predicates.")
                }
                if (@($predicates | Where-Object {
                            [string]$_.path -notmatch '(?i)(^|\.)status$'
                        }).Count -eq 0) {
                    $errors.Add("Step '$stepId' cannot rely only on a status field.")
                }
                foreach ($predicate in $predicates) {
                    $operator = [string]$predicate.operator
                    if ($operator -notin @(
                            'equals', 'notEquals', 'isTrue', 'isFalse', 'greaterThan',
                            'equalsParameter')) {
                        $errors.Add("Step '$stepId' has unsupported predicate '$operator'.")
                    }
                    if ($operator -in @('equals', 'notEquals', 'greaterThan') -and
                        -not (Test-DnfProperty -Object $predicate -Name 'value')) {
                        $errors.Add("Step '$stepId' predicate '$operator' lacks value.")
                    }
                    if ($operator -eq 'equalsParameter' -and
                        -not (Test-DnfProperty -Object $predicate -Name 'parameter')) {
                        $errors.Add("Step '$stepId' equalsParameter predicate lacks parameter.")
                    }
                }
                foreach ($inputRecord in @((Get-DnfPropertyValue $step 'inputs' @()))) {
                    $inputId = [string](Get-DnfPropertyValue $inputRecord 'id')
                    if ($inputId -notmatch $script:IdentifierPattern) {
                        $errors.Add("Step '$stepId' input id has an invalid format: '$inputId'.")
                    }
                    try {
                        $null = Resolve-DnfWorkflowPath -Value ([string]$inputRecord.path) `
                            -RepositoryRoot $repo -Workflow $workflow -RunId $sampleRunId `
                            -Label "Step input $stepId/$($inputRecord.id)"
                    }
                    catch {
                        $errors.Add($_.Exception.Message)
                    }
                }
                $outputs = @((Get-DnfPropertyValue $step 'outputs' @()))
                $inputIds = @(@((Get-DnfPropertyValue $step 'inputs' @())) |
                    ForEach-Object { [string]$_.id })
                if (@($inputIds | Select-Object -Unique).Count -ne $inputIds.Count) {
                    $errors.Add("Step '$stepId' has duplicate input ids.")
                }
                $hasApproval = Test-DnfProperty -Object $step -Name 'approval'
                if ($hasApproval -and $inputIds -contains 'approval-evidence') {
                    $errors.Add("Step '$stepId' reserves input id 'approval-evidence' for approval evidence.")
                }
                $outputIds = @($outputs | ForEach-Object { [string]$_.id })
                if (@($outputIds | Select-Object -Unique).Count -ne $outputIds.Count) {
                    $errors.Add("Step '$stepId' has duplicate output ids.")
                }
                if ([string]$step.mode -eq 'workspace-write' -and $outputs.Count -eq 0) {
                    $errors.Add("Workspace-write step '$stepId' must declare outputs.")
                }
                $resolvedOutputPaths = New-Object 'Collections.Generic.HashSet[string]' `
                ([StringComparer]::OrdinalIgnoreCase)
                foreach ($outputRecord in $outputs) {
                    $outputId = [string](Get-DnfPropertyValue $outputRecord 'id')
                    if ($outputId -notmatch $script:IdentifierPattern) {
                        $errors.Add("Step '$stepId' output id has an invalid format: '$outputId'.")
                    }
                    try {
                        $outputPath = Resolve-DnfWorkflowPath -Value ([string]$outputRecord.path) `
                            -RepositoryRoot $repo -Workflow $workflow -RunId $sampleRunId `
                            -Label "Step output $stepId/$($outputRecord.id)"
                        if (-not $resolvedOutputPaths.Add($outputPath)) {
                            $errors.Add("Step '$stepId' declares duplicate output path '$outputPath'.")
                        }
                        $disposition = [string](Get-DnfPropertyValue $outputRecord 'disposition' 'create-new')
                        if ($disposition -notin @(
                                'create-new', 'resume-reconcile', 'atomic-replace')) {
                            $errors.Add("Step output '$stepId/$($outputRecord.id)' has unsupported disposition '$disposition'.")
                            continue
                        }
                        if ($disposition -eq 'resume-reconcile' -and
                            [string]$outputRecord.kind -ne 'file') {
                            $errors.Add("Resume-reconcile output '$stepId/$($outputRecord.id)' must be a file.")
                            continue
                        }
                        if ($disposition -eq 'atomic-replace' -and [string]$outputRecord.kind -ne 'file') {
                            $errors.Add("Atomic-replace output '$stepId/$($outputRecord.id)' must be a file.")
                            continue
                        }
                        $allowedRoots = @((Get-DnfPropertyValue `
                                    $workflow.policy 'allowedWriteRoots' @()))
                        if ($allowedRoots.Count -eq 0) {
                            $allowedRoots = @('{{runDirectory}}')
                        }
                        $insideAllowedRoot = $false
                        foreach ($allowedRootValue in $allowedRoots) {
                            $allowedRoot = Resolve-DnfWorkflowPath -Value ([string]$allowedRootValue) `
                                -RepositoryRoot $repo -Workflow $workflow -RunId $sampleRunId `
                                -Label 'Allowed write root'
                            if (Test-DnfPathInside -Path $outputPath -Root $allowedRoot) {
                                $insideAllowedRoot = $true
                                break
                            }
                        }
                        $atomicPathAllowed = $false
                        if ($disposition -eq 'atomic-replace') {
                            foreach ($atomicValue in @((Get-DnfPropertyValue `
                                            $workflow.policy 'allowedAtomicReplacePaths' @()))) {
                                $atomicPath = Resolve-DnfWorkflowPath -Value ([string]$atomicValue) `
                                    -RepositoryRoot $repo -Workflow $workflow -RunId $sampleRunId `
                                    -Label 'Allowed atomic replace path'
                                if ($outputPath -ieq $atomicPath) {
                                    $atomicPathAllowed = $true
                                    break
                                }
                            }
                            if (-not $atomicPathAllowed) {
                                $errors.Add("Atomic-replace output '$stepId/$($outputRecord.id)' is not explicitly allowed.")
                            }
                        }
                        elseif (-not $insideAllowedRoot) {
                            $errors.Add("Step output '$stepId/$($outputRecord.id)' is outside allowed write roots.")
                        }
                    }
                    catch {
                        $errors.Add($_.Exception.Message)
                    }
                }
                foreach ($parameterName in $writePathParameterNames) {
                    if (-not $expandedPathParameters.ContainsKey([string]$parameterName)) {
                        $errors.Add("Step '$stepId' lacks required write path parameter '$parameterName'.")
                        continue
                    }
                    if (-not $resolvedOutputPaths.Contains(
                            [string]$expandedPathParameters[[string]$parameterName])) {
                        $errors.Add("Step '$stepId' write path parameter '$parameterName' is not a declared output.")
                    }
                }
            }
            if ($errors.Count -eq 0) {
                try {
                    $topologicalOrder = Get-DnfTopologicalOrder -Steps @($workflow.steps)
                }
                catch {
                    $errors.Add($_.Exception.Message)
                }
            }
        }
        try {
            $themeRoot = Resolve-DnfWorkflowPath -Value ([string]$workflow.themeRoot) `
                -RepositoryRoot $repo -Workflow $workflow -RunId $sampleRunId -Label 'Theme root'
            $runRoot = Resolve-DnfWorkflowPath -Value ([string]$workflow.runRoot) `
                -RepositoryRoot $repo -Workflow $workflow -RunId $sampleRunId -Label 'Run root'
            if (-not (Test-DnfPathInside -Path $runRoot -Root $themeRoot)) {
                $errors.Add('Workflow runRoot must stay inside themeRoot.')
            }
        }
        catch {
            $errors.Add($_.Exception.Message)
        }
    }

    $result = [pscustomobject]@{
        schemaVersion    = 1
        status           = if ($errors.Count -eq 0) { 'passed' } else { 'failed' }
        workflowPath     = $workflowFile
        registryPath     = $registryFile
        workflowId       = if ($null -eq $workflow) { $null } else { [string]$workflow.workflowId }
        stepCount        = if ($null -eq $workflow) { 0 } else { @($workflow.steps).Count }
        topologicalOrder = @($topologicalOrder)
        errors           = $errors.ToArray()
        deployment       = [pscustomobject]@{
            authorized       = $false
            performed        = $false
            imagePacks2Write = $false
            processOperation = $false
        }
    }
    if ($ThrowOnError -and $errors.Count -gt 0) {
        throw ($errors.ToArray() -join [Environment]::NewLine)
    }
    return $result
}

function Get-DnfPowerShellHostPath {
    param([string]$HostId)

    $systemRoot = [Environment]::GetFolderPath('Windows')
    if ($HostId -eq 'windows-powershell-x86') {
        $path = Join-Path $systemRoot 'SysWOW64\WindowsPowerShell\v1.0\powershell.exe'
    }
    elseif ($HostId -eq 'windows-powershell-x64') {
        $folder = if ([Environment]::Is64BitProcess) { 'System32' } else { 'Sysnative' }
        $path = Join-Path $systemRoot "$folder\WindowsPowerShell\v1.0\powershell.exe"
    }
    else {
        throw "Unsupported PowerShell host '$HostId'."
    }
    if (-not (Test-Path -LiteralPath $path -PathType Leaf)) {
        throw "PowerShell host was not found: $path"
    }
    return $path
}

function Get-DnfRunnerSha256 {
    param([string]$RepositoryRoot)

    $shimPath = Join-Path $PSScriptRoot 'Invoke-DnfWorkflowAdapter.ps1'
    $entrypointPath = Join-Path (Split-Path -Parent $PSScriptRoot) 'Invoke-DnfWorkflow.ps1'
    if (-not (Test-Path -LiteralPath $entrypointPath -PathType Leaf)) {
        throw "Workflow entrypoint was not found: $entrypointPath"
    }
    $lines = @(
        "entrypoint|$(Get-DnfFileSha256 -Path $entrypointPath)",
        "module|$(Get-DnfFileSha256 -Path $script:ModulePath)",
        "shim|$(Get-DnfFileSha256 -Path $shimPath)"
    )
    return Get-DnfTextSha256 -Text ($lines -join "`n")
}

function Write-DnfJsonAtomic {
    param([object]$Value, [string]$Path, [int]$Depth = 50)

    $directory = Split-Path -Parent $Path
    if (-not (Test-Path -LiteralPath $directory -PathType Container)) {
        New-Item -ItemType Directory -Path $directory -Force | Out-Null
    }
    $temporary = Join-Path $directory (
        '.json-' + [Guid]::NewGuid().ToString('N') + '.tmp')
    try {
        $Value | ConvertTo-Json -Depth $Depth | Set-Content -LiteralPath $temporary -Encoding UTF8
        $null = Get-Content -LiteralPath $temporary -Raw -Encoding UTF8 | ConvertFrom-Json
        [IO.File]::Move($temporary, $Path)
    }
    finally {
        if (Test-Path -LiteralPath $temporary) {
            Remove-Item -LiteralPath $temporary -Force
        }
    }
}

function Invoke-DnfRegisteredAdapter {
    param(
        [object]$Adapter,
        [object]$Parameters,
        [string]$RepositoryRoot,
        [string]$ControlDirectory,
        [string]$StepId
    )

    $scriptPath = [IO.Path]::GetFullPath((Join-Path $RepositoryRoot (
                ConvertTo-DnfNativePath -Value ([string]$Adapter.script))))
    Assert-DnfPathInside -Path $scriptPath -Root $RepositoryRoot -Label "Adapter $($Adapter.id)"
    Assert-DnfNoReparsePointPath -Path $scriptPath -RepositoryRoot $RepositoryRoot `
        -Label "Adapter $($Adapter.id)"
    Assert-DnfNoReparsePointPath -Path $ControlDirectory -RepositoryRoot $RepositoryRoot `
        -Label 'Workflow control directory'
    $hostPath = Get-DnfPowerShellHostPath -HostId ([string]$Adapter.host)
    $shimPath = Join-Path $PSScriptRoot 'Invoke-DnfWorkflowAdapter.ps1'
    $parameterPath = Join-Path $ControlDirectory "$StepId.parameters.json"
    $parameterJson = ConvertTo-DnfPlainObject -Value $Parameters
    if (Test-Path -LiteralPath $parameterPath -PathType Leaf) {
        $existingParameters = Get-Content -LiteralPath $parameterPath -Raw -Encoding UTF8 |
        ConvertFrom-Json
        if ((ConvertTo-DnfCanonicalJson -Value $existingParameters) -cne
            (ConvertTo-DnfCanonicalJson -Value $parameterJson)) {
            throw "Adapter parameter evidence changed for step '$StepId'."
        }
    }
    else {
        Write-DnfJsonAtomic -Value $parameterJson -Path $parameterPath
    }
    $lines = & $hostPath -NoLogo -NoProfile -NonInteractive -ExecutionPolicy Bypass `
        -File $shimPath -ScriptPath $scriptPath -ParameterJsonPath $parameterPath 2>&1
    $exitCode = $LASTEXITCODE
    $text = (@($lines | ForEach-Object { [string]$_ }) -join [Environment]::NewLine).Trim()
    if ($exitCode -ne 0) {
        throw "Adapter '$($Adapter.id)' failed with exit code $exitCode. Output: $text"
    }
    if ([string]::IsNullOrWhiteSpace($text)) {
        throw "Adapter '$($Adapter.id)' returned no JSON."
    }
    try {
        return $text | ConvertFrom-Json
    }
    catch {
        throw "Adapter '$($Adapter.id)' returned invalid JSON: $text"
    }
}

function Test-DnfApproval {
    param(
        [object]$Approval,
        [string]$RepositoryRoot,
        [object]$Workflow,
        [string]$RunId
    )

    $path = Resolve-DnfWorkflowPath -Value ([string]$Approval.evidencePath) `
        -RepositoryRoot $RepositoryRoot -Workflow $Workflow -RunId $RunId `
        -Label 'Approval evidence'
    if (-not (Test-Path -LiteralPath $path -PathType Leaf)) {
        throw "Approval evidence was not found: $path"
    }
    $evidence = Get-Content -LiteralPath $path -Raw -Encoding UTF8 | ConvertFrom-Json
    $status = Get-DnfObjectPathValue -Object $evidence -Path ([string]$Approval.statusPath)
    if (-not $status.found -or -not (Test-DnfValueEqual -Left $status.value `
                -Right $Approval.approvedValue)) {
        throw "Approval evidence does not contain the required approved value: $path"
    }
    $approvedAt = Get-DnfObjectPathValue -Object $evidence -Path ([string]$Approval.approvedAtPath)
    if (-not $approvedAt.found) {
        throw "Approval evidence has no approval timestamp: $path"
    }
    $timestamp = [DateTimeOffset]::MinValue
    if (-not [DateTimeOffset]::TryParse([string]$approvedAt.value, [ref]$timestamp)) {
        throw "Approval timestamp is invalid: $($approvedAt.value)"
    }
    $now = [DateTimeOffset]::UtcNow
    if ($timestamp.ToUniversalTime() -gt $now.AddMinutes(5)) {
        throw "Approval timestamp is in the future: $timestamp"
    }
    if ($timestamp.ToUniversalTime() -lt $now.AddHours( - [int]$Approval.maxAgeHours)) {
        throw "Approval evidence is stale: $timestamp"
    }
    return [pscustomobject]@{ path = $path; evidence = $evidence }
}

function Test-DnfStepResultReusable {
    param(
        [object]$StepResult,
        [object]$Bindings,
        [string]$RepositoryRoot,
        [object]$Step,
        [object]$Parameters,
        [object]$Workflow,
        [string]$RunId,
        [string]$StepId,
        [string]$AdapterId
    )

    if ($null -eq $StepResult -or [string]$StepResult.state -ne 'passed' -or
        -not (Test-DnfProperty -Object $StepResult -Name 'bindings')) {
        return $false
    }
    if ($null -ne $Workflow) {
        if ([int](Get-DnfPropertyValue $StepResult 'schemaVersion' 0) -ne 1 -or
            [string](Get-DnfPropertyValue $StepResult 'workflowId') -cne
            [string]$Workflow.workflowId -or
            [string](Get-DnfPropertyValue $StepResult 'runId') -cne $RunId -or
            [string](Get-DnfPropertyValue $StepResult 'stepId') -cne $StepId -or
            [string](Get-DnfPropertyValue $StepResult 'adapter') -cne $AdapterId) {
            return $false
        }
        $deployment = Get-DnfPropertyValue $StepResult 'deployment'
        foreach ($name in @(
                'authorized', 'performed', 'imagePacks2Write', 'processOperation')) {
            if ($null -eq $deployment -or
                -not (Test-DnfProperty -Object $deployment -Name $name) -or
                $deployment.PSObject.Properties[$name].Value -ne $false) {
                return $false
            }
        }
    }
    foreach ($name in @(
            'workflowSha256', 'registrySha256', 'runnerSha256',
            'adapterScriptSha256', 'parameterSha256')) {
        if (-not (Test-DnfProperty -Object $StepResult.bindings -Name $name) -or
            -not (Test-DnfProperty -Object $Bindings -Name $name) -or
            [string]$StepResult.bindings.PSObject.Properties[$name].Value -ne
            [string]$Bindings.PSObject.Properties[$name].Value) {
            return $false
        }
    }
    $expectedInputs = New-Object 'Collections.Generic.List[object]'
    $expectedOutputs = New-Object 'Collections.Generic.List[object]'
    if ($null -ne $Workflow -and $null -ne $Step) {
        foreach ($inputRecord in @((Get-DnfPropertyValue $Step 'inputs' @()))) {
            try {
                $inputPath = Resolve-DnfWorkflowPath -Value ([string]$inputRecord.path) `
                    -RepositoryRoot $RepositoryRoot -Workflow $Workflow -RunId $RunId `
                    -Label "Resume input $StepId/$($inputRecord.id)"
                $kind = [string](Get-DnfPropertyValue $inputRecord 'kind' 'file')
                $exists = if ($kind -eq 'directory') {
                    Test-Path -LiteralPath $inputPath -PathType Container
                }
                else {
                    Test-Path -LiteralPath $inputPath -PathType Leaf
                }
                if (-not $exists) {
                    if ($inputRecord.required -eq $true) {
                        return $false
                    }
                    continue
                }
                $expectedInputs.Add([pscustomobject]@{
                        id   = [string]$inputRecord.id
                        path = Get-DnfRelativePath -Path $inputPath `
                            -RepositoryRoot $RepositoryRoot
                        kind = $kind
                    })
            }
            catch {
                return $false
            }
        }
        if (Test-DnfProperty -Object $Step -Name 'approval') {
            try {
                $approvalPath = Resolve-DnfWorkflowPath `
                    -Value ([string]$Step.approval.evidencePath) `
                    -RepositoryRoot $RepositoryRoot -Workflow $Workflow -RunId $RunId `
                    -Label "Resume approval $StepId"
                if (-not (Test-Path -LiteralPath $approvalPath -PathType Leaf)) {
                    return $false
                }
                $expectedInputs.Add([pscustomobject]@{
                        id   = 'approval-evidence'
                        path = Get-DnfRelativePath -Path $approvalPath `
                            -RepositoryRoot $RepositoryRoot
                        kind = 'file'
                    })
            }
            catch {
                return $false
            }
        }
        foreach ($outputRecord in @((Get-DnfPropertyValue $Step 'outputs' @()))) {
            try {
                $outputPath = Resolve-DnfWorkflowPath -Value ([string]$outputRecord.path) `
                    -RepositoryRoot $RepositoryRoot -Workflow $Workflow -RunId $RunId `
                    -Label "Resume output $StepId/$($outputRecord.id)"
                $expectedOutputs.Add([pscustomobject]@{
                        id   = [string]$outputRecord.id
                        path = Get-DnfRelativePath -Path $outputPath `
                            -RepositoryRoot $RepositoryRoot
                        kind = [string]$outputRecord.kind
                    })
            }
            catch {
                return $false
            }
        }
        foreach ($collection in @(
                [pscustomobject]@{
                    expected = $expectedInputs.ToArray()
                    actual   = @((Get-DnfPropertyValue $StepResult 'inputs' @()))
                },
                [pscustomobject]@{
                    expected = $expectedOutputs.ToArray()
                    actual   = @((Get-DnfPropertyValue $StepResult 'outputs' @()))
                })) {
            if ($collection.actual.Count -ne $collection.expected.Count) {
                return $false
            }
            foreach ($expected in @($collection.expected)) {
                $matches = @($collection.actual | Where-Object {
                        [string]$_.id -ceq [string]$expected.id
                    })
                if ($matches.Count -ne 1 -or
                    [string]$matches[0].path -ine [string]$expected.path -or
                    [string]$matches[0].kind -cne [string]$expected.kind) {
                    return $false
                }
            }
        }
    }
    $atomicOutputPaths = New-Object 'Collections.Generic.HashSet[string]' `
    ([StringComparer]::OrdinalIgnoreCase)
    if ($null -ne $Step) {
        foreach ($outputRecord in @((Get-DnfPropertyValue $Step 'outputs' @()))) {
            if ([string](Get-DnfPropertyValue $outputRecord 'disposition' 'create-new') -ne
                'atomic-replace') {
                continue
            }
            $outputId = [string]$outputRecord.id
            foreach ($snapshot in @($StepResult.outputs | Where-Object {
                        [string]$_.id -eq $outputId
                    })) {
                $null = $atomicOutputPaths.Add([string]$snapshot.path)
            }
        }
    }
    foreach ($snapshot in @($StepResult.inputs)) {
        if ($atomicOutputPaths.Contains([string]$snapshot.path)) {
            continue
        }
        if (-not (Test-DnfSnapshotCurrent -Snapshot $snapshot -RepositoryRoot $RepositoryRoot)) {
            return $false
        }
    }
    foreach ($snapshot in @($StepResult.outputs)) {
        if (-not (Test-DnfSnapshotCurrent -Snapshot $snapshot -RepositoryRoot $RepositoryRoot)) {
            return $false
        }
    }
    if (@($StepResult.successPredicates | Where-Object { $_.passed -ne $true }).Count -gt 0) {
        return $false
    }
    if ($null -ne $Step -and (Test-DnfProperty -Object $Step -Name 'success')) {
        if (-not (Test-DnfProperty -Object $StepResult -Name 'adapterResult')) {
            return $false
        }
        $currentPredicates = @(Test-DnfSuccessPredicates `
                -Result $StepResult.adapterResult -Success $Step.success `
                -Parameters $Parameters)
        if ($currentPredicates.Count -ne @($Step.success.all).Count -or
            @($currentPredicates | Where-Object { $_.passed -ne $true }).Count -gt 0) {
            return $false
        }
    }
    return $true
}

function Invoke-DnfWorkflow {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [string]$WorkflowPath,
        [string]$RegistryPath,
        [string]$RepositoryRoot,
        [string]$RunId,
        [switch]$Execute,
        [switch]$Resume,
        [switch]$AllowNetwork
    )

    $validation = Test-DnfWorkflowDefinition -WorkflowPath $WorkflowPath `
        -RegistryPath $RegistryPath -RepositoryRoot $RepositoryRoot
    if ([string]$validation.status -ne 'passed') {
        throw ($validation.errors -join [Environment]::NewLine)
    }
    if ($Resume -and -not $Execute) {
        throw 'Resume requires Execute.'
    }
    if (-not $Execute) {
        return [pscustomobject]@{
            schemaVersion      = 1
            status             = 'validated'
            mode               = 'static-only'
            workflowId         = $validation.workflowId
            stepCount          = $validation.stepCount
            topologicalOrder   = $validation.topologicalOrder
            executionPerformed = $false
            deployment         = [pscustomobject]@{
                authorized       = $false
                performed        = $false
                imagePacks2Write = $false
                processOperation = $false
            }
        }
    }
    if ([string]::IsNullOrWhiteSpace($RunId) -or
        $RunId.Length -lt 3 -or $RunId.Length -gt 64 -or
        $RunId -notmatch '^[a-z0-9]+(?:[.-][a-z0-9]+)*$') {
        throw 'Execute mode requires a 3-64 character lowercase dotted or hyphenated RunId.'
    }
    $repo = Get-DnfRepositoryRoot -RepositoryRoot $RepositoryRoot
    $workflowFile = $validation.workflowPath
    $registryFile = $validation.registryPath
    $workflow = Get-Content -LiteralPath $workflowFile -Raw -Encoding UTF8 | ConvertFrom-Json
    $registry = Get-Content -LiteralPath $registryFile -Raw -Encoding UTF8 | ConvertFrom-Json
    $adapterMap = Get-DnfAdapterMap -Registry $registry
    $runRoot = Resolve-DnfWorkflowPath -Value ([string]$workflow.runRoot) `
        -RepositoryRoot $repo -Workflow $workflow -RunId $RunId -Label 'Run root'
    $runDirectory = Join-Path $runRoot $RunId
    $controlDirectory = Join-Path $runDirectory '.workflow'
    if ($Resume) {
        if (-not (Test-Path -LiteralPath $controlDirectory -PathType Container)) {
            throw "Resume state was not found: $controlDirectory"
        }
    }
    else {
        if (Test-Path -LiteralPath $runDirectory) {
            throw "Fresh run directory already exists: $runDirectory"
        }
        New-Item -ItemType Directory -Path $controlDirectory -Force | Out-Null
    }
    Assert-DnfPathInside -Path $controlDirectory -Root $runDirectory `
        -Label 'Workflow control directory'
    Assert-DnfNoReparsePointPath -Path $controlDirectory -RepositoryRoot $repo `
        -Label 'Workflow control directory'

    $workflowHash = Get-DnfFileSha256 -Path $workflowFile
    $registryHash = Get-DnfFileSha256 -Path $registryFile
    $runnerHash = Get-DnfRunnerSha256 -RepositoryRoot $repo
    $runManifestPath = Join-Path $controlDirectory 'run-manifest.json'
    $runBindings = [pscustomobject]@{
        workflowSha256 = $workflowHash
        registrySha256 = $registryHash
        runnerSha256   = $runnerHash
    }
    if ($Resume) {
        $runManifest = Get-Content -LiteralPath $runManifestPath -Raw -Encoding UTF8 | ConvertFrom-Json
        if ([string]$runManifest.workflowId -ne [string]$workflow.workflowId -or
            [string]$runManifest.runId -ne $RunId -or
            [string]$runManifest.bindings.workflowSha256 -ne $workflowHash -or
            [string]$runManifest.bindings.registrySha256 -ne $registryHash -or
            [string]$runManifest.bindings.runnerSha256 -ne $runnerHash) {
            throw 'Resume governance bindings changed; start a fresh run.'
        }
    }
    else {
        $runManifest = [ordered]@{
            schemaVersion = 1
            createdAtUtc  = [DateTime]::UtcNow.ToString('o')
            workflowId    = [string]$workflow.workflowId
            runId         = $RunId
            workflowPath  = Get-DnfRelativePath -Path $workflowFile -RepositoryRoot $repo
            registryPath  = Get-DnfRelativePath -Path $registryFile -RepositoryRoot $repo
            bindings      = $runBindings
            deployment    = [ordered]@{
                authorized       = $false
                performed        = $false
                imagePacks2Write = $false
                processOperation = $false
            }
        }
        Write-DnfJsonAtomic -Value $runManifest -Path $runManifestPath
    }

    $stepById = @{}
    foreach ($step in @($workflow.steps)) {
        $stepById[[string]$step.id] = $step
    }
    $states = @{}
    $reports = New-Object 'Collections.Generic.List[object]'
    foreach ($stepId in @($validation.topologicalOrder)) {
        $step = $stepById[$stepId]
        foreach ($dependency in @($step.dependsOn)) {
            if ([string]$states[[string]$dependency] -notin @('passed', 'reused')) {
                throw "Step '$stepId' dependency '$dependency' did not pass."
            }
        }
        $adapter = $adapterMap[[string]$step.adapter]
        if ([string]$adapter.network -eq 'explicit-authorization-required' -and
            -not $AllowNetwork) {
            throw "Step '$stepId' requires explicit AllowNetwork authorization."
        }
        $parameters = Expand-DnfParameterValue -Value $step.parameters -RepositoryRoot $repo `
            -Workflow $workflow -RunId $RunId
        $parameterTable = ConvertTo-DnfParameterHashtable -Parameters $parameters
        if (Test-DnfProperty -Object $adapter -Name 'forcedParameters') {
            foreach ($property in @($adapter.forcedParameters.PSObject.Properties)) {
                if ($parameterTable.ContainsKey($property.Name) -and
                    -not (Test-DnfValueEqual -Left $parameterTable[$property.Name] `
                            -Right $property.Value)) {
                    throw "Step '$stepId' overrides forced parameter '$($property.Name)'."
                }
                $parameterTable[$property.Name] = $property.Value
            }
        }
        foreach ($parameterName in @((Get-DnfPropertyValue `
                        $adapter 'pathParameters' @()))) {
            if (-not $parameterTable.ContainsKey([string]$parameterName)) {
                continue
            }
            $parameterValue = $parameterTable[[string]$parameterName]
            if (-not ($parameterValue -is [string]) -or
                [string]::IsNullOrWhiteSpace([string]$parameterValue)) {
                throw "Step '$stepId' path parameter '$parameterName' must be a non-empty string."
            }
            $parameterTable[[string]$parameterName] = Resolve-DnfWorkflowPath `
                -Value ([string]$parameterValue) -RepositoryRoot $repo `
                -Workflow $workflow -RunId $RunId `
                -Label "Step path parameter $stepId/$parameterName"
        }
        $preparedParameters = [pscustomobject](ConvertTo-DnfPlainObject -Value $parameterTable)
        $adapterScriptPath = [IO.Path]::GetFullPath((Join-Path $repo (
                    ConvertTo-DnfNativePath -Value ([string]$adapter.script))))
        $bindings = [pscustomobject]@{
            workflowSha256      = $workflowHash
            registrySha256      = $registryHash
            runnerSha256        = $runnerHash
            adapterScriptSha256 = Get-DnfFileSha256 -Path $adapterScriptPath
            parameterSha256     = Get-DnfTextSha256 -Text (
                ConvertTo-DnfCanonicalJson -Value $preparedParameters)
        }
        $resultPath = Join-Path $controlDirectory "$stepId.result.json"
        if ($Resume -and (Test-Path -LiteralPath $resultPath -PathType Leaf)) {
            $previous = Get-Content -LiteralPath $resultPath -Raw -Encoding UTF8 | ConvertFrom-Json
            if (-not (Test-DnfStepResultReusable -StepResult $previous -Bindings $bindings `
                        -RepositoryRoot $repo -Step $step -Parameters $preparedParameters `
                        -Workflow $workflow -RunId $RunId -StepId $stepId `
                        -AdapterId ([string]$adapter.id))) {
                throw "Step '$stepId' cannot be resumed because governance, inputs, or outputs drifted."
            }
            if (Test-DnfProperty -Object $step -Name 'approval') {
                try {
                    $null = Test-DnfApproval -Approval $step.approval -RepositoryRoot $repo `
                        -Workflow $workflow -RunId $RunId
                }
                catch {
                    throw "Step '$stepId' approval cannot be resumed: $($_.Exception.Message)"
                }
            }
            $states[$stepId] = 'reused'
            $reports.Add([pscustomobject]@{ id = $stepId; state = 'reused'; result = $resultPath })
            continue
        }

        $startedAt = [DateTime]::UtcNow
        $inputSnapshots = New-Object 'Collections.Generic.List[object]'
        $outputSnapshots = New-Object 'Collections.Generic.List[object]'
        $predicateReports = @()
        $adapterResult = $null
        $errorText = $null
        try {
            foreach ($inputRecord in @((Get-DnfPropertyValue $step 'inputs' @()))) {
                $inputPath = Resolve-DnfWorkflowPath -Value ([string]$inputRecord.path) `
                    -RepositoryRoot $repo -Workflow $workflow -RunId $RunId `
                    -Label "Step input $stepId/$($inputRecord.id)"
                $kind = [string](Get-DnfPropertyValue $inputRecord 'kind' 'file')
                $exists = if ($kind -eq 'directory') {
                    Test-Path -LiteralPath $inputPath -PathType Container
                }
                else {
                    Test-Path -LiteralPath $inputPath -PathType Leaf
                }
                if (-not $exists) {
                    if ($inputRecord.required -eq $true) {
                        throw "Required step input was not found: $inputPath"
                    }
                    continue
                }
                $inputSnapshots.Add((New-DnfPathSnapshot -Id ([string]$inputRecord.id) `
                            -Path $inputPath -Kind $kind -RepositoryRoot $repo))
            }
            if (Test-DnfProperty -Object $step -Name 'approval') {
                $approval = Test-DnfApproval -Approval $step.approval -RepositoryRoot $repo `
                    -Workflow $workflow -RunId $RunId
                $inputSnapshots.Add((New-DnfPathSnapshot -Id 'approval-evidence' `
                            -Path $approval.path -Kind 'file' -RepositoryRoot $repo))
            }
            foreach ($outputRecord in @((Get-DnfPropertyValue $step 'outputs' @()))) {
                $outputPath = Resolve-DnfWorkflowPath -Value ([string]$outputRecord.path) `
                    -RepositoryRoot $repo -Workflow $workflow -RunId $RunId `
                    -Label "Step output $stepId/$($outputRecord.id)"
                $disposition = [string](Get-DnfPropertyValue $outputRecord `
                        'disposition' 'create-new')
                $outputExists = Test-Path -LiteralPath $outputPath
                if ($disposition -eq 'create-new' -and $outputExists) {
                    throw "Step '$stepId' refuses to overwrite output: $outputPath"
                }
                if ($disposition -eq 'resume-reconcile' -and $outputExists -and
                    -not $Resume) {
                    throw "Step '$stepId' only reconciles an existing output during Resume: $outputPath"
                }
                if ($disposition -eq 'atomic-replace' -and
                    -not (Test-Path -LiteralPath $outputPath -PathType Leaf)) {
                    throw "Step '$stepId' atomic-replace output was not found: $outputPath"
                }
            }
            $adapterResult = Invoke-DnfRegisteredAdapter -Adapter $adapter `
                -Parameters $preparedParameters -RepositoryRoot $repo `
                -ControlDirectory $controlDirectory -StepId $stepId
            $predicateReports = Test-DnfSuccessPredicates -Result $adapterResult `
                -Success $step.success -Parameters $preparedParameters
            $failedPredicates = @($predicateReports | Where-Object { $_.passed -ne $true })
            if ($failedPredicates.Count -gt 0) {
                $details = @($failedPredicates | ForEach-Object {
                        "$($_.path)/$($_.operator)"
                    }) -join ', '
                throw "Step '$stepId' success predicates failed: $details"
            }
            foreach ($outputRecord in @((Get-DnfPropertyValue $step 'outputs' @()))) {
                $outputPath = Resolve-DnfWorkflowPath -Value ([string]$outputRecord.path) `
                    -RepositoryRoot $repo -Workflow $workflow -RunId $RunId `
                    -Label "Step output $stepId/$($outputRecord.id)"
                $kind = [string]$outputRecord.kind
                $outputSnapshots.Add((New-DnfPathSnapshot -Id ([string]$outputRecord.id) `
                            -Path $outputPath -Kind $kind -RepositoryRoot $repo))
            }
        }
        catch {
            $errorText = $_.Exception.Message
        }
        $state = if ($null -eq $errorText) { 'passed' } else { 'failed' }
        $stepResult = [ordered]@{
            schemaVersion     = 1
            workflowId        = [string]$workflow.workflowId
            runId             = $RunId
            stepId            = $stepId
            adapter           = [string]$adapter.id
            state             = $state
            startedAtUtc      = $startedAt.ToString('o')
            finishedAtUtc     = [DateTime]::UtcNow.ToString('o')
            bindings          = $bindings
            inputs            = $inputSnapshots.ToArray()
            outputs           = $outputSnapshots.ToArray()
            successPredicates = @($predicateReports)
            adapterResult     = $adapterResult
            error             = $errorText
            deployment        = [ordered]@{
                authorized       = $false
                performed        = $false
                imagePacks2Write = $false
                processOperation = $false
            }
        }
        $states[$stepId] = $state
        if ($state -ne 'passed') {
            $attemptName = '{0}.attempt-{1}.failed.json' -f $stepId, `
                [DateTime]::UtcNow.ToString('yyyyMMddTHHmmssfffffffZ')
            $attemptPath = Join-Path $controlDirectory $attemptName
            Write-DnfJsonAtomic -Value $stepResult -Path $attemptPath
            $reports.Add([pscustomobject]@{ id = $stepId; state = $state; result = $attemptPath })
            throw "Workflow step '$stepId' failed: $errorText"
        }
        Write-DnfJsonAtomic -Value $stepResult -Path $resultPath
        $reports.Add([pscustomobject]@{ id = $stepId; state = $state; result = $resultPath })
    }

    $summary = [ordered]@{
        schemaVersion      = 1
        generatedAtUtc     = [DateTime]::UtcNow.ToString('o')
        status             = 'passed'
        workflowId         = [string]$workflow.workflowId
        runId              = $RunId
        runDirectory       = $runDirectory
        steps              = $reports.ToArray()
        executionPerformed = $true
        resumed            = [bool]$Resume
        deployment         = [ordered]@{
            authorized       = $false
            performed        = $false
            imagePacks2Write = $false
            processOperation = $false
        }
    }
    $summaryPath = Join-Path $controlDirectory 'run-summary.json'
    if (Test-Path -LiteralPath $summaryPath) {
        if (-not $Resume) {
            throw "Run summary already exists: $summaryPath"
        }
        $existingSummary = Get-Content -LiteralPath $summaryPath -Raw -Encoding UTF8 |
        ConvertFrom-Json
        if ([string]$existingSummary.status -ne 'passed' -or
            [string]$existingSummary.workflowId -ne [string]$workflow.workflowId -or
            [string]$existingSummary.runId -ne $RunId -or
            $existingSummary.deployment.authorized -ne $false -or
            $existingSummary.deployment.performed -ne $false -or
            $existingSummary.deployment.imagePacks2Write -ne $false -or
            $existingSummary.deployment.processOperation -ne $false) {
            throw "Existing run summary is not reusable: $summaryPath"
        }
        return $existingSummary
    }
    Write-DnfJsonAtomic -Value $summary -Path $summaryPath
    return [pscustomobject]$summary
}

Export-ModuleMember -Function @(
    'Test-DnfWorkflowDefinition',
    'Invoke-DnfWorkflow',
    'Test-DnfSuccessPredicates',
    'Test-DnfApproval',
    'Test-DnfStepResultReusable'
)

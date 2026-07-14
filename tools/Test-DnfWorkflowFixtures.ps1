[CmdletBinding()]
param(
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

function Write-JsonFile {
    param([object]$Value, [string]$Path)

    $Value | ConvertTo-Json -Depth 30 | Set-Content -LiteralPath $Path -Encoding UTF8
}

function New-Policy {
    return [pscustomobject]@{
        executeRequiresExplicitSwitch = $true
        network                       = 'forbidden'
        deployment                    = 'forbidden'
        processOperations             = 'forbidden'
        imagePacks2Write              = 'forbidden'
        requireFreshRunDirectory      = $true
        allowedWriteRoots             = @('{{runDirectory}}')
        allowedAtomicReplacePaths     = @()
        recovery                      = [pscustomobject]@{
            requireWorkflowHash      = $true
            requireRegistryHash      = $true
            requireRunnerHash        = $true
            requireAdapterScriptHash = $true
            requireParameterHash     = $true
            requireInputSnapshots    = $true
            requireOutputSnapshots   = $true
        }
    }
}

function New-Step {
    param(
        [string]$Id,
        [string[]]$DependsOn = @(),
        [string]$Mode = 'read-only',
        [object]$Parameters = $null,
        [object[]]$Outputs = @()
    )

    if ($null -eq $Parameters) {
        $Parameters = [pscustomobject]@{}
    }
    $step = [ordered]@{
        id         = $Id
        adapter    = if ($Mode -eq 'workspace-write') { 'fixture-write' } else { 'fixture-read' }
        mode       = $Mode
        dependsOn  = @($DependsOn)
        parameters = $Parameters
        success    = [ordered]@{
            all = @(
                [pscustomobject]@{ path = 'status'; operator = 'equals'; value = 'passed' },
                [pscustomobject]@{ path = 'ready'; operator = 'isTrue' }
            )
        }
    }
    if ($Outputs.Count -gt 0) {
        $step.outputs = @($Outputs)
    }
    return [pscustomobject]$step
}

function New-Workflow {
    param([object[]]$Steps, [object]$Policy = $null)

    if ($null -eq $Policy) {
        $Policy = New-Policy
    }
    return [pscustomobject]@{
        schemaVersion = 1
        workflowId    = 'fixture.workflow-v1'
        themeRoot     = 'tools/workflow/fixtures'
        runRoot       = 'tools/workflow/fixtures/.runs'
        policy        = $Policy
        steps         = @($Steps)
    }
}

function Invoke-StaticCase {
    param(
        [string]$Id,
        [object]$Workflow,
        [string]$ExpectedStatus,
        [string]$ExpectedErrorPattern,
        [string]$TemporaryRoot,
        [string]$RegistryPath,
        [string]$RepositoryRoot
    )

    $path = Join-Path $TemporaryRoot "$Id.workflow.json"
    Write-JsonFile -Value $Workflow -Path $path
    $result = Test-DnfWorkflowDefinition -WorkflowPath $path -RegistryPath $RegistryPath `
        -RepositoryRoot $RepositoryRoot
    Assert-Condition ([string]$result.status -eq $ExpectedStatus) `
        "Fixture '$Id' status differed: actual=$($result.status) expected=$ExpectedStatus"
    if (-not [string]::IsNullOrWhiteSpace($ExpectedErrorPattern)) {
        Assert-Condition ((@($result.errors) -join "`n") -match $ExpectedErrorPattern) `
            "Fixture '$Id' did not report expected error '$ExpectedErrorPattern'. Errors=$($result.errors -join '; ')"
    }
    return [pscustomobject]@{
        id             = $Id
        status         = 'passed'
        observedStatus = [string]$result.status
        expectedStatus = $ExpectedStatus
    }
}

$defaultRoot = Split-Path -Parent $PSScriptRoot
$sourceRepositoryRoot = if ([string]::IsNullOrWhiteSpace($RepoRoot)) {
    (Resolve-Path -LiteralPath $defaultRoot).Path
}
else {
    (Resolve-Path -LiteralPath $RepoRoot).Path
}
$repositoryRoot = Join-Path ([IO.Path]::GetTempPath()) (
    'dnf-patch-workflow-fixture-' + [Guid]::NewGuid().ToString('N'))
$copyPaths = @(
    'tools\workflow\DnfPatch.Workflow.psm1',
    'tools\workflow\Invoke-DnfWorkflowAdapter.ps1',
    'tools\workflow\fixtures\Test-DnfWorkflowFixtureAdapter.ps1',
    'tools\Invoke-DnfWorkflow.ps1',
    'tools\New-DnfFinalManualReviewTemplate.ps1',
    'tools\Test-DnfFinalManualReview.ps1'
)
foreach ($relativePath in $copyPaths) {
    $sourcePath = Join-Path $sourceRepositoryRoot $relativePath
    Assert-Condition (Test-Path -LiteralPath $sourcePath -PathType Leaf) `
        "Fixture source file was not found: $sourcePath"
    $destinationPath = Join-Path $repositoryRoot $relativePath
    $destinationDirectory = Split-Path -Parent $destinationPath
    if (-not (Test-Path -LiteralPath $destinationDirectory -PathType Container)) {
        New-Item -ItemType Directory -Path $destinationDirectory -Force | Out-Null
    }
    Copy-Item -LiteralPath $sourcePath -Destination $destinationPath
}
$modulePath = Join-Path $repositoryRoot 'tools\workflow\DnfPatch.Workflow.psm1'
Import-Module $modulePath -Force
$fixtureScript = Join-Path $repositoryRoot `
    'tools\workflow\fixtures\Test-DnfWorkflowFixtureAdapter.ps1'
$registry = [pscustomobject]@{
    schemaVersion = 1
    adapters      = @(
        [pscustomobject]@{
            id                = 'fixture-read'
            script            = 'tools/workflow/fixtures/Test-DnfWorkflowFixtureAdapter.ps1'
            host              = 'windows-powershell-x64'
            mode              = 'read-only'
            network           = 'forbidden'
            allowedParameters = @('InputPath', 'Status', 'Ready', 'AsJson')
            forcedParameters  = [pscustomobject]@{ AsJson = $true }
        },
        [pscustomobject]@{
            id                  = 'fixture-write'
            script              = 'tools/workflow/fixtures/Test-DnfWorkflowFixtureAdapter.ps1'
            host                = 'windows-powershell-x64'
            mode                = 'workspace-write'
            network             = 'forbidden'
            allowedParameters   = @(
                'InputPath',
                'OutputPath',
                'Status',
                'Ready',
                'AllowExistingOutput',
                'ReadyAfterExistingOutput',
                'AsJson')
            pathParameters      = @('OutputPath')
            writePathParameters = @('OutputPath')
            forcedParameters    = [pscustomobject]@{ AsJson = $true }
        }
    )
}
$invalidHostRegistry = $registry | ConvertTo-Json -Depth 10 | ConvertFrom-Json
$invalidHostRegistry.adapters[0].host = 'pwsh-any'
$temporaryRoot = Join-Path $repositoryRoot (
    'tools\workflow\fixtures\.test-' + [Guid]::NewGuid().ToString('N'))
New-Item -ItemType Directory -Path $temporaryRoot -Force | Out-Null
$registryPath = Join-Path $temporaryRoot 'registry.json'
$invalidHostRegistryPath = Join-Path $temporaryRoot 'registry-invalid-host.json'
Write-JsonFile -Value $registry -Path $registryPath
Write-JsonFile -Value $invalidHostRegistry -Path $invalidHostRegistryPath
$cases = New-Object 'Collections.Generic.List[object]'
try {
    $validWorkflow = New-Workflow -Steps @((New-Step -Id 'one'))
    $cases.Add((Invoke-StaticCase -Id 'valid' -Workflow $validWorkflow `
                -ExpectedStatus 'passed' -TemporaryRoot $temporaryRoot `
                -RegistryPath $registryPath -RepositoryRoot $repositoryRoot))

    $duplicateWorkflow = New-Workflow -Steps @(
        (New-Step -Id 'duplicate'),
        (New-Step -Id 'duplicate'))
    $cases.Add((Invoke-StaticCase -Id 'duplicate-step' -Workflow $duplicateWorkflow `
                -ExpectedStatus 'failed' -ExpectedErrorPattern 'duplicate step id' `
                -TemporaryRoot $temporaryRoot -RegistryPath $registryPath `
                -RepositoryRoot $repositoryRoot))

    $invalidStepIdWorkflow = New-Workflow -Steps @((New-Step -Id '../escaped-step'))
    $cases.Add((Invoke-StaticCase -Id 'invalid-step-id' `
                -Workflow $invalidStepIdWorkflow -ExpectedStatus 'failed' `
                -ExpectedErrorPattern 'step id has an invalid format' `
                -TemporaryRoot $temporaryRoot -RegistryPath $registryPath `
                -RepositoryRoot $repositoryRoot))

    $cycleWorkflow = New-Workflow -Steps @(
        (New-Step -Id 'a' -DependsOn @('b')),
        (New-Step -Id 'b' -DependsOn @('a')))
    $cases.Add((Invoke-StaticCase -Id 'dependency-cycle' -Workflow $cycleWorkflow `
                -ExpectedStatus 'failed' -ExpectedErrorPattern 'contains a cycle' `
                -TemporaryRoot $temporaryRoot -RegistryPath $registryPath `
                -RepositoryRoot $repositoryRoot))

    $escapeOutput = [pscustomobject]@{
        id          = 'escaped-output'
        path        = '../outside.bin'
        required    = $true
        snapshot    = 'sha256'
        kind        = 'file'
        disposition = 'create-new'
    }
    $escapeWorkflow = New-Workflow -Steps @((New-Step -Id 'escape' -Mode 'workspace-write' `
                -Parameters ([pscustomobject]@{ OutputPath = '../outside.bin' }) `
                -Outputs @($escapeOutput)))
    $cases.Add((Invoke-StaticCase -Id 'path-escape' -Workflow $escapeWorkflow `
                -ExpectedStatus 'failed' -ExpectedErrorPattern 'must stay inside' `
                -TemporaryRoot $temporaryRoot -RegistryPath $registryPath `
                -RepositoryRoot $repositoryRoot))

    $absoluteWorkflow = New-Workflow -Steps @((New-Step -Id 'absolute' -Mode 'workspace-write' `
                -Parameters ([pscustomobject]@{ OutputPath = 'C:\outside\file.bin' }) `
                -Outputs @([pscustomobject]@{
                    id = 'absolute-output'; path = 'C:\outside\file.bin'; required = $true
                    snapshot = 'sha256'; kind = 'file'; disposition = 'create-new'
                })))
    $cases.Add((Invoke-StaticCase -Id 'absolute-path' -Workflow $absoluteWorkflow `
                -ExpectedStatus 'failed' -ExpectedErrorPattern 'must stay inside' `
                -TemporaryRoot $temporaryRoot -RegistryPath $registryPath `
                -RepositoryRoot $repositoryRoot))

    $writePathMismatchWorkflow = New-Workflow -Steps @((New-Step `
                -Id 'write-path-mismatch' -Mode 'workspace-write' `
                -Parameters ([pscustomobject]@{
                    OutputPath = '{{runDirectory}}/actual-output.bin'
                }) `
                -Outputs @([pscustomobject]@{
                    id          = 'declared-output'
                    path        = '{{runDirectory}}/declared-output.bin'
                    required    = $true
                    snapshot    = 'sha256'
                    kind        = 'file'
                    disposition = 'create-new'
                })))
    $cases.Add((Invoke-StaticCase -Id 'write-path-output-mismatch' `
                -Workflow $writePathMismatchWorkflow -ExpectedStatus 'failed' `
                -ExpectedErrorPattern 'write path parameter.*is not a declared output' `
                -TemporaryRoot $temporaryRoot -RegistryPath $registryPath `
                -RepositoryRoot $repositoryRoot))

    $duplicateOutputPathWorkflow = New-Workflow -Steps @((New-Step `
                -Id 'duplicate-output-path' -Mode 'workspace-write' `
                -Parameters ([pscustomobject]@{
                    OutputPath = '{{runDirectory}}/same-output.bin'
                }) `
                -Outputs @(
                [pscustomobject]@{
                    id          = 'same-output-one'
                    path        = '{{runDirectory}}/same-output.bin'
                    required    = $true
                    snapshot    = 'sha256'
                    kind        = 'file'
                    disposition = 'create-new'
                },
                [pscustomobject]@{
                    id          = 'same-output-two'
                    path        = '{{runDirectory}}/same-output.bin'
                    required    = $true
                    snapshot    = 'sha256'
                    kind        = 'file'
                    disposition = 'create-new'
                })))
    $cases.Add((Invoke-StaticCase -Id 'duplicate-output-path' `
                -Workflow $duplicateOutputPathWorkflow -ExpectedStatus 'failed' `
                -ExpectedErrorPattern 'declares duplicate output path' `
                -TemporaryRoot $temporaryRoot -RegistryPath $registryPath `
                -RepositoryRoot $repositoryRoot))

    $cases.Add((Invoke-StaticCase -Id 'invalid-host' -Workflow $validWorkflow `
                -ExpectedStatus 'failed' -ExpectedErrorPattern 'unsupported host' `
                -TemporaryRoot $temporaryRoot -RegistryPath $invalidHostRegistryPath `
                -RepositoryRoot $repositoryRoot))

    $predicateResult = [pscustomobject]@{ status = 'passed'; ready = $false }
    $predicateDefinition = [pscustomobject]@{
        all = @(
            [pscustomobject]@{ path = 'status'; operator = 'equals'; value = 'passed' },
            [pscustomobject]@{ path = 'ready'; operator = 'isTrue' }
        )
    }
    $predicateReports = @(Test-DnfSuccessPredicates -Result $predicateResult `
            -Success $predicateDefinition -Parameters ([pscustomobject]@{}))
    Assert-Condition (@($predicateReports | Where-Object { $_.passed -ne $true }).Count -eq 1) `
        'Fake status=passed fixture bypassed the readiness predicate.'
    $predicateResumeResult = [pscustomobject]@{
        state             = 'passed'
        bindings          = [pscustomobject]@{
            workflowSha256      = ('A' * 64)
            registrySha256      = ('B' * 64)
            runnerSha256        = ('C' * 64)
            adapterScriptSha256 = ('D' * 64)
            parameterSha256     = ('E' * 64)
        }
        inputs            = @()
        outputs           = @()
        successPredicates = @(
            [pscustomobject]@{ passed = $true },
            [pscustomobject]@{ passed = $true })
        adapterResult     = $predicateResult
    }
    $predicateResumeStep = [pscustomobject]@{
        success = $predicateDefinition
    }
    Assert-Condition (-not (Test-DnfStepResultReusable `
                -StepResult $predicateResumeResult -Bindings $predicateResumeResult.bindings `
                -RepositoryRoot $repositoryRoot -Step $predicateResumeStep `
                -Parameters ([pscustomobject]@{}))) `
        'Resume fixture trusted stored predicate booleans without recomputing readiness.'
    $cases.Add([pscustomobject]@{
            id             = 'fake-status-passed'
            status         = 'passed'
            observedStatus = 'predicate-failed'
            expectedStatus = 'predicate-failed'
        })

    $approvalPath = Join-Path $temporaryRoot 'stale-approval.json'
    Write-JsonFile -Value ([pscustomobject]@{
            approved      = $true
            approvedAtUtc = [DateTime]::UtcNow.AddHours(-3).ToString('o')
        }) -Path $approvalPath
    $approvalWorkflow = New-Workflow -Steps @((New-Step -Id 'approval'))
    $approval = [pscustomobject]@{
        evidencePath   = $approvalPath
        statusPath     = 'approved'
        approvedValue  = $true
        approvedAtPath = 'approvedAtUtc'
        maxAgeHours    = 1
    }
    $approvalFailed = $false
    try {
        $null = Test-DnfApproval -Approval $approval -RepositoryRoot $repositoryRoot `
            -Workflow $approvalWorkflow -RunId 'fixture-run'
    }
    catch {
        $approvalFailed = $_.Exception.Message -match 'stale'
    }
    Assert-Condition $approvalFailed 'Stale manual approval fixture was accepted.'
    $cases.Add([pscustomobject]@{
            id             = 'stale-approval'
            status         = 'passed'
            observedStatus = 'rejected'
            expectedStatus = 'rejected'
        })

    $snapshotPath = Join-Path $temporaryRoot 'snapshot.txt'
    [IO.File]::WriteAllText($snapshotPath, 'one', (New-Object Text.UTF8Encoding($false)))
    $snapshotItem = Get-Item -LiteralPath $snapshotPath
    $snapshotHash = (Get-FileHash -LiteralPath $snapshotPath -Algorithm SHA256).Hash
    $relativeSnapshotPath = $snapshotPath.Substring($repositoryRoot.Length + 1).Replace('\', '/')
    $bindings = [pscustomobject]@{
        workflowSha256      = ('A' * 64)
        registrySha256      = ('B' * 64)
        runnerSha256        = ('C' * 64)
        adapterScriptSha256 = ('D' * 64)
        parameterSha256     = ('E' * 64)
    }
    $stepResult = [pscustomobject]@{
        state             = 'passed'
        bindings          = $bindings
        inputs            = @([pscustomobject]@{
                id = 'input'; path = $relativeSnapshotPath; kind = 'file'
                length = [long]$snapshotItem.Length; sha256 = $snapshotHash
            })
        outputs           = @()
        successPredicates = @(
            [pscustomobject]@{ passed = $true },
            [pscustomobject]@{ passed = $true })
    }
    Assert-Condition (Test-DnfStepResultReusable -StepResult $stepResult `
            -Bindings $bindings -RepositoryRoot $repositoryRoot) `
        'Unchanged resume fixture was not reusable.'
    $changedBindings = $bindings | ConvertTo-Json -Depth 5 | ConvertFrom-Json
    $changedBindings.runnerSha256 = ('F' * 64)
    Assert-Condition (-not (Test-DnfStepResultReusable -StepResult $stepResult `
                -Bindings $changedBindings -RepositoryRoot $repositoryRoot)) `
        'Resume fixture accepted changed governance hash.'
    [IO.File]::WriteAllText($snapshotPath, 'two', (New-Object Text.UTF8Encoding($false)))
    Assert-Condition (-not (Test-DnfStepResultReusable -StepResult $stepResult `
                -Bindings $bindings -RepositoryRoot $repositoryRoot)) `
        'Resume fixture accepted changed input snapshot.'
    $cases.Add([pscustomobject]@{
            id             = 'resume-governance-and-input-drift'
            status         = 'passed'
            observedStatus = 'rejected'
            expectedStatus = 'rejected'
        })

    $atomicPath = Join-Path $temporaryRoot 'atomic.json'
    [IO.File]::WriteAllText($atomicPath, 'before', (New-Object Text.UTF8Encoding($false)))
    $atomicBeforeItem = Get-Item -LiteralPath $atomicPath
    $atomicBeforeSnapshot = [pscustomobject]@{
        id     = 'atomic-before'
        path   = $atomicPath.Substring($repositoryRoot.Length + 1).Replace('\', '/')
        kind   = 'file'
        length = [long]$atomicBeforeItem.Length
        sha256 = (Get-FileHash -LiteralPath $atomicPath -Algorithm SHA256).Hash
    }
    [IO.File]::WriteAllText($atomicPath, 'after', (New-Object Text.UTF8Encoding($false)))
    $atomicAfterItem = Get-Item -LiteralPath $atomicPath
    $atomicAfterSnapshot = [pscustomobject]@{
        id     = 'atomic-after'
        path   = $atomicBeforeSnapshot.path
        kind   = 'file'
        length = [long]$atomicAfterItem.Length
        sha256 = (Get-FileHash -LiteralPath $atomicPath -Algorithm SHA256).Hash
    }
    $atomicStep = [pscustomobject]@{
        outputs = @([pscustomobject]@{
                id          = 'atomic-after'
                path        = $atomicBeforeSnapshot.path
                kind        = 'file'
                disposition = 'atomic-replace'
            })
    }
    $atomicStepResult = [pscustomobject]@{
        state             = 'passed'
        bindings          = $bindings
        inputs            = @($atomicBeforeSnapshot)
        outputs           = @($atomicAfterSnapshot)
        successPredicates = @(
            [pscustomobject]@{ passed = $true },
            [pscustomobject]@{ passed = $true })
    }
    Assert-Condition (Test-DnfStepResultReusable -StepResult $atomicStepResult `
            -Bindings $bindings -RepositoryRoot $repositoryRoot -Step $atomicStep) `
        'Atomic-replace fixture rejected the current committed output.'
    [IO.File]::WriteAllText($atomicPath, 'drifted', (New-Object Text.UTF8Encoding($false)))
    Assert-Condition (-not (Test-DnfStepResultReusable -StepResult $atomicStepResult `
                -Bindings $bindings -RepositoryRoot $repositoryRoot -Step $atomicStep)) `
        'Atomic-replace fixture accepted output drift.'
    $cases.Add([pscustomobject]@{
            id             = 'resume-atomic-replace'
            status         = 'passed'
            observedStatus = 'reused-then-drift-rejected'
            expectedStatus = 'reused-then-drift-rejected'
        })

    $resumeSwitchRejected = $false
    try {
        $null = Invoke-DnfWorkflow -WorkflowPath (Join-Path $temporaryRoot 'valid.workflow.json') `
            -RegistryPath $registryPath -RepositoryRoot $repositoryRoot `
            -RunId 'fixture-resume-switch' -Resume
    }
    catch {
        $resumeSwitchRejected = $_.Exception.Message -eq 'Resume requires Execute.'
    }
    Assert-Condition $resumeSwitchRejected 'Resume without Execute was not rejected.'
    $cases.Add([pscustomobject]@{
            id             = 'resume-requires-execute'
            status         = 'passed'
            observedStatus = 'rejected'
            expectedStatus = 'rejected'
        })

    $completedRunId = 'fixture-completed-resume'
    $completedRunWorkflow = New-Workflow -Steps @((New-Step -Id 'completed-read'))
    $completedRunWorkflowPath = Join-Path $temporaryRoot 'completed-resume.workflow.json'
    Write-JsonFile -Value $completedRunWorkflow -Path $completedRunWorkflowPath
    $firstRun = Invoke-DnfWorkflow -WorkflowPath $completedRunWorkflowPath `
        -RegistryPath $registryPath -RepositoryRoot $repositoryRoot `
        -RunId $completedRunId -Execute
    Assert-Condition ([string]$firstRun.status -eq 'passed' -and
        $firstRun.executionPerformed -eq $true) `
        'Completed-run fixture did not pass its initial execution.'
    $resumedRun = Invoke-DnfWorkflow -WorkflowPath $completedRunWorkflowPath `
        -RegistryPath $registryPath -RepositoryRoot $repositoryRoot `
        -RunId $completedRunId -Execute -Resume
    Assert-Condition ([string]$resumedRun.status -eq 'passed' -and
        [string]$resumedRun.runId -eq $completedRunId -and
        $resumedRun.deployment.performed -eq $false) `
        'Completed-run fixture was not resumed idempotently.'
    $completedRunDirectory = Join-Path $repositoryRoot `
        "tools\workflow\fixtures\.runs\$completedRunId"
    if (Test-Path -LiteralPath $completedRunDirectory) {
        Remove-Item -LiteralPath $completedRunDirectory -Recurse -Force
    }
    $cases.Add([pscustomobject]@{
            id             = 'resume-completed-run'
            status         = 'passed'
            observedStatus = 'idempotent'
            expectedStatus = 'idempotent'
        })

    $tamperInputPath = Join-Path $temporaryRoot 'resume-tamper-input.txt'
    $tamperAlternatePath = Join-Path $temporaryRoot 'resume-tamper-alternate.txt'
    [IO.File]::WriteAllText($tamperInputPath, 'expected', `
        (New-Object Text.UTF8Encoding($false)))
    [IO.File]::WriteAllText($tamperAlternatePath, 'alternate', `
        (New-Object Text.UTF8Encoding($false)))
    $tamperInputRelativePath = $tamperInputPath.Substring(
        $repositoryRoot.Length + 1).Replace('\', '/')
    $tamperAlternateRelativePath = $tamperAlternatePath.Substring(
        $repositoryRoot.Length + 1).Replace('\', '/')
    $tamperStep = New-Step -Id 'tamper-read'
    $tamperStep | Add-Member -NotePropertyName inputs -NotePropertyValue @(
        [pscustomobject]@{
            id       = 'expected-input'
            path     = $tamperInputRelativePath
            required = $true
            snapshot = 'sha256'
            kind     = 'file'
        })
    $tamperWorkflow = New-Workflow -Steps @($tamperStep)
    $tamperWorkflowPath = Join-Path $temporaryRoot 'resume-tamper.workflow.json'
    Write-JsonFile -Value $tamperWorkflow -Path $tamperWorkflowPath
    $tamperRunId = 'fixture-resume-result-tamper'
    $tamperRunDirectory = Join-Path $repositoryRoot `
        "tools\workflow\fixtures\.runs\$tamperRunId"
    try {
        $tamperInitial = Invoke-DnfWorkflow -WorkflowPath $tamperWorkflowPath `
            -RegistryPath $registryPath -RepositoryRoot $repositoryRoot `
            -RunId $tamperRunId -Execute
        Assert-Condition ([string]$tamperInitial.status -eq 'passed') `
            'Resume result-tamper fixture did not pass its initial execution.'
        $tamperResultPath = Join-Path $tamperRunDirectory `
            '.workflow\tamper-read.result.json'
        $tamperOriginalText = Get-Content -LiteralPath $tamperResultPath `
            -Raw -Encoding UTF8
        $tamperOriginal = $tamperOriginalText | ConvertFrom-Json

        $tamperVariants = New-Object 'Collections.Generic.List[object]'
        $missingSnapshot = $tamperOriginalText | ConvertFrom-Json
        $missingSnapshot.inputs = @()
        $tamperVariants.Add([pscustomobject]@{
                id     = 'missing-snapshot'
                result = $missingSnapshot
            })
        $duplicateSnapshot = $tamperOriginalText | ConvertFrom-Json
        $duplicateSnapshot.inputs = @(
            $duplicateSnapshot.inputs[0],
            $duplicateSnapshot.inputs[0])
        $tamperVariants.Add([pscustomobject]@{
                id     = 'duplicate-snapshot'
                result = $duplicateSnapshot
            })
        $reboundSnapshot = $tamperOriginalText | ConvertFrom-Json
        $alternateItem = Get-Item -LiteralPath $tamperAlternatePath
        $reboundSnapshot.inputs[0].path = $tamperAlternateRelativePath
        $reboundSnapshot.inputs[0].length = [long]$alternateItem.Length
        $reboundSnapshot.inputs[0].sha256 = (Get-FileHash `
                -LiteralPath $tamperAlternatePath -Algorithm SHA256).Hash
        $tamperVariants.Add([pscustomobject]@{
                id     = 'rebound-snapshot'
                result = $reboundSnapshot
            })
        $wrongIdentity = $tamperOriginalText | ConvertFrom-Json
        $wrongIdentity.stepId = 'other-step'
        $tamperVariants.Add([pscustomobject]@{
                id     = 'wrong-step-identity'
                result = $wrongIdentity
            })

        foreach ($variant in $tamperVariants.ToArray()) {
            Write-JsonFile -Value $variant.result -Path $tamperResultPath
            $tamperRejected = $false
            try {
                $null = Invoke-DnfWorkflow -WorkflowPath $tamperWorkflowPath `
                    -RegistryPath $registryPath -RepositoryRoot $repositoryRoot `
                    -RunId $tamperRunId -Execute -Resume
            }
            catch {
                $tamperRejected = $_.Exception.Message -match 'cannot be resumed'
            }
            Assert-Condition $tamperRejected `
                "Resume accepted tampered step result variant '$($variant.id)'."
        }
    }
    finally {
        if (Test-Path -LiteralPath $tamperRunDirectory) {
            Remove-Item -LiteralPath $tamperRunDirectory -Recurse -Force
        }
    }
    $cases.Add([pscustomobject]@{
            id             = 'resume-rejects-result-tampering'
            status         = 'passed'
            observedStatus = 'missing-duplicate-rebound-and-identity-rejected'
            expectedStatus = 'missing-duplicate-rebound-and-identity-rejected'
        })

    $reconcileRunId = 'fixture-resume-reconcile-output'
    $reconcileOutputValue = '{{runDirectory}}/reconciled-output.bin'
    $reconcileStep = New-Step -Id 'reconcile-write' -Mode 'workspace-write' `
        -Parameters ([pscustomobject]@{
            OutputPath               = $reconcileOutputValue
            AllowExistingOutput      = $true
            ReadyAfterExistingOutput = $true
        }) `
        -Outputs @([pscustomobject]@{
            id          = 'reconciled-output'
            path        = $reconcileOutputValue
            required    = $true
            snapshot    = 'sha256'
            kind        = 'file'
            disposition = 'resume-reconcile'
        })
    $reconcileWorkflow = New-Workflow -Steps @($reconcileStep)
    $reconcileWorkflowPath = Join-Path $temporaryRoot `
        'resume-reconcile-output.workflow.json'
    Write-JsonFile -Value $reconcileWorkflow -Path $reconcileWorkflowPath
    $reconcileRunDirectory = Join-Path $repositoryRoot `
        "tools\workflow\fixtures\.runs\$reconcileRunId"
    try {
        $initialFailureObserved = $false
        $initialFailureMessage = ''
        try {
            $null = Invoke-DnfWorkflow -WorkflowPath $reconcileWorkflowPath `
                -RegistryPath $registryPath -RepositoryRoot $repositoryRoot `
                -RunId $reconcileRunId -Execute
        }
        catch {
            $initialFailureMessage = $_.Exception.Message
            $initialFailureObserved = $_.Exception.Message -match `
                'success predicates failed'
        }
        Assert-Condition $initialFailureObserved `
            "Resume-reconcile fixture did not create its interrupted initial state. Error=$initialFailureMessage"
        $reconcileOutputPath = Join-Path $reconcileRunDirectory `
            'reconciled-output.bin'
        Assert-Condition (Test-Path -LiteralPath $reconcileOutputPath -PathType Leaf) `
            'Resume-reconcile fixture did not leave its committed output.'
        $beforeReconcileHash = (Get-FileHash -LiteralPath $reconcileOutputPath `
                -Algorithm SHA256).Hash
        $reconciledRun = Invoke-DnfWorkflow `
            -WorkflowPath $reconcileWorkflowPath -RegistryPath $registryPath `
            -RepositoryRoot $repositoryRoot -RunId $reconcileRunId `
            -Execute -Resume
        $afterReconcileHash = (Get-FileHash -LiteralPath $reconcileOutputPath `
                -Algorithm SHA256).Hash
        Assert-Condition ([string]$reconciledRun.status -eq 'passed' -and
            $beforeReconcileHash -eq $afterReconcileHash -and
            (Test-Path -LiteralPath (Join-Path $reconcileRunDirectory `
                    '.workflow\reconcile-write.result.json') -PathType Leaf)) `
            'Resume-reconcile fixture did not recover the existing output.'
    }
    finally {
        if (Test-Path -LiteralPath $reconcileRunDirectory) {
            Remove-Item -LiteralPath $reconcileRunDirectory -Recurse -Force
        }
    }
    $cases.Add([pscustomobject]@{
            id             = 'resume-reconciles-existing-output'
            status         = 'passed'
            observedStatus = 'interrupted-then-resumed-without-overwrite'
            expectedStatus = 'interrupted-then-resumed-without-overwrite'
        })

    $resumeApprovalRunId = 'fixture-resume-stale-approval'
    $resumeApprovalPath = Join-Path $temporaryRoot 'resume-approval.json'
    Write-JsonFile -Value ([pscustomobject]@{
            approved      = $true
            approvedAtUtc = [DateTime]::UtcNow.ToString('o')
        }) -Path $resumeApprovalPath
    $resumeApprovalRelativePath = $resumeApprovalPath.Substring(
        $repositoryRoot.Length + 1).Replace('\', '/')
    $resumeApprovalStep = New-Step -Id 'approval-read'
    $resumeApprovalStep | Add-Member -NotePropertyName approval -NotePropertyValue `
    ([pscustomobject]@{
            evidencePath   = $resumeApprovalRelativePath
            statusPath     = 'approved'
            approvedValue  = $true
            approvedAtPath = 'approvedAtUtc'
            maxAgeHours    = 1
        })
    $resumeApprovalWorkflow = New-Workflow -Steps @($resumeApprovalStep)
    $resumeApprovalWorkflowPath = Join-Path $temporaryRoot `
        'resume-stale-approval.workflow.json'
    Write-JsonFile -Value $resumeApprovalWorkflow -Path $resumeApprovalWorkflowPath
    $resumeApprovalRunDirectory = Join-Path $repositoryRoot `
        "tools\workflow\fixtures\.runs\$resumeApprovalRunId"
    try {
        $resumeApprovalInitial = Invoke-DnfWorkflow `
            -WorkflowPath $resumeApprovalWorkflowPath -RegistryPath $registryPath `
            -RepositoryRoot $repositoryRoot -RunId $resumeApprovalRunId -Execute
        Assert-Condition ([string]$resumeApprovalInitial.status -eq 'passed') `
            'Resume approval fixture did not pass its initial execution.'

        Write-JsonFile -Value ([pscustomobject]@{
                approved      = $true
                approvedAtUtc = [DateTime]::UtcNow.AddHours(-2).ToString('o')
            }) -Path $resumeApprovalPath
        $resumeApprovalResultPath = Join-Path $resumeApprovalRunDirectory `
            '.workflow\approval-read.result.json'
        $resumeApprovalResult = Get-Content -LiteralPath $resumeApprovalResultPath `
            -Raw -Encoding UTF8 | ConvertFrom-Json
        $approvalEvidenceSnapshots = @($resumeApprovalResult.inputs | Where-Object {
                [string]$_.id -eq 'approval-evidence'
            })
        Assert-Condition ($approvalEvidenceSnapshots.Count -eq 1) `
            'Resume approval fixture has no unique approval-evidence snapshot.'
        $resumeApprovalItem = Get-Item -LiteralPath $resumeApprovalPath
        $approvalEvidenceSnapshots[0].length = [long]$resumeApprovalItem.Length
        $approvalEvidenceSnapshots[0].sha256 = (Get-FileHash `
                -LiteralPath $resumeApprovalPath -Algorithm SHA256).Hash
        Write-JsonFile -Value $resumeApprovalResult -Path $resumeApprovalResultPath

        $resumeApprovalRejected = $false
        try {
            $null = Invoke-DnfWorkflow -WorkflowPath $resumeApprovalWorkflowPath `
                -RegistryPath $registryPath -RepositoryRoot $repositoryRoot `
                -RunId $resumeApprovalRunId -Execute -Resume
        }
        catch {
            $resumeApprovalRejected = $_.Exception.Message -match `
                'approval cannot be resumed.*stale'
        }
        Assert-Condition $resumeApprovalRejected `
            'Resume fixture reused an expired manual approval.'
    }
    finally {
        if (Test-Path -LiteralPath $resumeApprovalRunDirectory) {
            Remove-Item -LiteralPath $resumeApprovalRunDirectory -Recurse -Force
        }
    }
    $cases.Add([pscustomobject]@{
            id             = 'resume-revalidates-approval-age'
            status         = 'passed'
            observedStatus = 'stale-rejected'
            expectedStatus = 'stale-rejected'
        })

    $templateSheetPath = Join-Path $temporaryRoot 'template-sheet.png'
    [IO.File]::WriteAllText($templateSheetPath, 'sheet', `
        (New-Object Text.UTF8Encoding($false)))
    $templateSheetItem = Get-Item -LiteralPath $templateSheetPath
    $templateSummaryPath = Join-Path $temporaryRoot 'template-summary.json'
    Write-JsonFile -Value ([pscustomobject]@{
            schemaVersion           = 1
            status                  = 'passed'
            fullSkillCoverageProven = $false
            validation              = [pscustomobject]@{
                manifestScopeOfflineCoverage = [pscustomobject]@{
                    eligibleForReleaseMetadataFullSkillCoverage = $true
                }
                fullFrame                    = [pscustomobject]@{
                    backgrounds   = @('black', 'white', 'checkerboard')
                    contactSheets = @([pscustomobject]@{
                            path   = 'template-sheet.png'
                            length = [long]$templateSheetItem.Length
                            sha256 = (Get-FileHash -LiteralPath $templateSheetPath `
                                    -Algorithm SHA256).Hash
                        })
                }
            }
            deployment              = [pscustomobject]@{
                authorized       = $false
                performed        = $false
                imagePacks2Write = $false
                processOperation = $false
            }
        }) -Path $templateSummaryPath
    $templateOutputPath = Join-Path $temporaryRoot 'manual-review-template.json'
    $templateText = (& (Join-Path $repositoryRoot `
                'tools\New-DnfFinalManualReviewTemplate.ps1') `
            -FinalSummaryPath $templateSummaryPath -OutputPath $templateOutputPath `
            -RepoRoot $repositoryRoot -AsJson | Out-String).Trim()
    $templateResult = $templateText | ConvertFrom-Json
    $template = Get-Content -LiteralPath $templateOutputPath -Raw -Encoding UTF8 |
    ConvertFrom-Json
    Assert-Condition ([string]$templateResult.status -eq 'passed' -and
        [string]$template.status -eq 'pending-human-review' -and
        $template.approved -eq $false -and
        @($template.contactSheets).Count -eq 1 -and
        $template.deployment.performed -eq $false) `
        'Manual-review template fixture did not preserve its pending state.'
    $templateOverwriteRejected = $false
    try {
        & (Join-Path $repositoryRoot 'tools\New-DnfFinalManualReviewTemplate.ps1') `
            -FinalSummaryPath $templateSummaryPath -OutputPath $templateOutputPath `
            -RepoRoot $repositoryRoot -AsJson | Out-Null
    }
    catch {
        $templateOverwriteRejected = $_.Exception.Message -match 'Refusing to overwrite'
    }
    Assert-Condition $templateOverwriteRejected `
        'Manual-review template fixture allowed an overwrite.'
    $cases.Add([pscustomobject]@{
            id             = 'manual-review-template'
            status         = 'passed'
            observedStatus = 'created-and-overwrite-rejected'
            expectedStatus = 'created-and-overwrite-rejected'
        })

    $validReview = $template | ConvertTo-Json -Depth 20 | ConvertFrom-Json
    $validReview.status = 'passed'
    $validReview.approved = $true
    $validReview.approvedAtUtc = [DateTime]::UtcNow.ToString('o')
    $validReview.reviewedBy = 'fixture-reviewer'
    $validReview.reviewedAllContactSheets = $true
    foreach ($name in @(
            'blankPageCount',
            'unexpectedFullCanvasBlackFrameCount',
            'layoutAnomalyCount',
            'temporalAnomalyCount',
            'watermarkFindingCount')) {
        $validReview.findings.PSObject.Properties[$name].Value = 0
    }
    $validReviewPath = Join-Path $temporaryRoot 'manual-review-valid.json'
    Write-JsonFile -Value $validReview -Path $validReviewPath
    $validReviewText = (& (Join-Path $repositoryRoot `
                'tools\Test-DnfFinalManualReview.ps1') `
            -FinalSummaryPath $templateSummaryPath -ManualReviewPath $validReviewPath `
            -RepoRoot $repositoryRoot -AsJson | Out-String).Trim()
    $validReviewResult = $validReviewText | ConvertFrom-Json
    Assert-Condition ([string]$validReviewResult.status -eq 'passed' -and
        [string]$validReviewResult.reviewedBy -eq 'fixture-reviewer') `
        'Valid manual-review identity fixture did not pass.'

    $blankReviewer = $validReview | ConvertTo-Json -Depth 20 | ConvertFrom-Json
    $blankReviewer.reviewedBy = '   '
    $blankReviewerPath = Join-Path $temporaryRoot 'manual-review-blank-reviewer.json'
    Write-JsonFile -Value $blankReviewer -Path $blankReviewerPath
    $blankReviewerRejected = $false
    try {
        & (Join-Path $repositoryRoot 'tools\Test-DnfFinalManualReview.ps1') `
            -FinalSummaryPath $templateSummaryPath -ManualReviewPath $blankReviewerPath `
            -RepoRoot $repositoryRoot -AsJson | Out-Null
    }
    catch {
        $blankReviewerRejected = $_.Exception.Message -match 'reviewedBy must be non-empty'
    }
    Assert-Condition $blankReviewerRejected `
        'Manual-review fixture accepted an empty reviewer identity.'

    $compatibilityClaim = $validReview | ConvertTo-Json -Depth 20 | ConvertFrom-Json
    $compatibilityClaim.targetClientCompatibilityProven = $true
    $compatibilityClaimPath = Join-Path $temporaryRoot `
        'manual-review-client-compatibility-claim.json'
    Write-JsonFile -Value $compatibilityClaim -Path $compatibilityClaimPath
    $compatibilityClaimRejected = $false
    try {
        & (Join-Path $repositoryRoot 'tools\Test-DnfFinalManualReview.ps1') `
            -FinalSummaryPath $templateSummaryPath `
            -ManualReviewPath $compatibilityClaimPath -RepoRoot $repositoryRoot `
            -AsJson | Out-Null
    }
    catch {
        $compatibilityClaimRejected = $_.Exception.Message -match `
            'cannot claim target-client compatibility'
    }
    Assert-Condition $compatibilityClaimRejected `
        'Manual-review fixture accepted a target-client compatibility claim.'
    $cases.Add([pscustomobject]@{
            id             = 'manual-review-identity-and-client-claim'
            status         = 'passed'
            observedStatus = 'valid-passed-invalid-rejected'
            expectedStatus = 'valid-passed-invalid-rejected'
        })

    $nullFindingReview = $validReview | ConvertTo-Json -Depth 20 | ConvertFrom-Json
    $nullFindingReview.findings.blankPageCount = $null
    $nullFindingPath = Join-Path $temporaryRoot 'manual-review-null-finding.json'
    Write-JsonFile -Value $nullFindingReview -Path $nullFindingPath
    $nullFindingRejected = $false
    try {
        & (Join-Path $repositoryRoot 'tools\Test-DnfFinalManualReview.ps1') `
            -FinalSummaryPath $templateSummaryPath -ManualReviewPath $nullFindingPath `
            -RepoRoot $repositoryRoot -AsJson | Out-Null
    }
    catch {
        $nullFindingRejected = $_.Exception.Message -match 'must be an explicit integer'
    }
    Assert-Condition $nullFindingRejected `
        'Manual-review fixture accepted a null finding as zero.'

    $missingDeploymentReview = $validReview | ConvertTo-Json -Depth 20 | ConvertFrom-Json
    $missingDeploymentReview.deployment.PSObject.Properties.Remove('processOperation')
    $missingDeploymentPath = Join-Path $temporaryRoot `
        'manual-review-missing-deployment-field.json'
    Write-JsonFile -Value $missingDeploymentReview -Path $missingDeploymentPath
    $missingDeploymentRejected = $false
    try {
        & (Join-Path $repositoryRoot 'tools\Test-DnfFinalManualReview.ps1') `
            -FinalSummaryPath $templateSummaryPath `
            -ManualReviewPath $missingDeploymentPath -RepoRoot $repositoryRoot `
            -AsJson | Out-Null
    }
    catch {
        $missingDeploymentRejected = $_.Exception.Message -match `
            'deployment.processOperation is missing'
    }
    Assert-Condition $missingDeploymentRejected `
        'Manual-review fixture accepted an incomplete deployment record.'

    $nonUtcReview = $validReview | ConvertTo-Json -Depth 20 | ConvertFrom-Json
    $nonUtcReview.approvedAtUtc = [DateTimeOffset]::Now.ToString('o')
    if ([DateTimeOffset]::Now.Offset -eq [TimeSpan]::Zero) {
        $nonUtcReview.approvedAtUtc = [DateTimeOffset]::UtcNow.ToOffset(
            [TimeSpan]::FromHours(8)).ToString('o')
    }
    $nonUtcReviewPath = Join-Path $temporaryRoot 'manual-review-non-utc.json'
    Write-JsonFile -Value $nonUtcReview -Path $nonUtcReviewPath
    $nonUtcReviewRejected = $false
    try {
        & (Join-Path $repositoryRoot 'tools\Test-DnfFinalManualReview.ps1') `
            -FinalSummaryPath $templateSummaryPath -ManualReviewPath $nonUtcReviewPath `
            -RepoRoot $repositoryRoot -AsJson | Out-Null
    }
    catch {
        $nonUtcReviewRejected = $_.Exception.Message -match 'must use UTC offset zero'
    }
    Assert-Condition $nonUtcReviewRejected `
        'Manual-review fixture accepted a non-UTC approval timestamp.'
    $cases.Add([pscustomobject]@{
            id             = 'manual-review-explicit-findings-and-deployment'
            status         = 'passed'
            observedStatus = 'null-missing-and-non-utc-rejected'
            expectedStatus = 'null-missing-and-non-utc-rejected'
        })

    $coveragePath = Join-Path $temporaryRoot 'coverage-summary.json'
    Write-JsonFile -Value ([pscustomobject]@{
            status                  = 'passed'
            fullSkillCoverageProven = $true
            validation              = [pscustomobject]@{
                manifestScopeOfflineCoverage = [pscustomobject]@{
                    eligibleForReleaseMetadataFullSkillCoverage = $true
                }
            }
        }) -Path $coveragePath
    $coverageRejected = $false
    try {
        & (Join-Path $repositoryRoot 'tools\New-DnfFinalManualReviewTemplate.ps1') `
            -FinalSummaryPath $coveragePath -OutputPath (Join-Path $temporaryRoot 'review.json') `
            -RepoRoot $repositoryRoot -AsJson | Out-Null
    }
    catch {
        $coverageRejected = $_.Exception.Message -match 'pre-metadata'
    }
    Assert-Condition $coverageRejected 'Final-summary coverage=true fixture was accepted.'
    $cases.Add([pscustomobject]@{
            id             = 'coverage-true-before-metadata'
            status         = 'passed'
            observedStatus = 'rejected'
            expectedStatus = 'rejected'
        })

    Assert-Condition (Test-Path -LiteralPath $fixtureScript -PathType Leaf) `
        'Fixture adapter disappeared during the test.'
}
finally {
    if (Test-Path -LiteralPath $repositoryRoot) {
        Remove-Item -LiteralPath $repositoryRoot -Recurse -Force
    }
}

$caseArray = $cases.ToArray()
$result = [pscustomobject]@{
    schemaVersion = 1
    status        = 'passed'
    fixtureCount  = $caseArray.Count
    fixtures      = $caseArray
    deployment    = [pscustomobject]@{
        authorized       = $false
        performed        = $false
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

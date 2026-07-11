[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)]
    [string[]]$SnapshotJsonPath,

    [string]$ImagePacks2,
    [string]$OutputFile,
    [switch]$FailOnMismatch,
    [switch]$AsJson
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

Import-Module (Join-Path $PSScriptRoot 'DnfPatch.Toolchain.psm1') -Force
$repoRoot = Get-DnfPatchRepositoryRoot
$imagePacksPath = Resolve-DnfImagePacks2 -Path $ImagePacks2 -RepositoryRoot $repoRoot

function New-ExpectedSourceRecord {
    param(
        [object]$Snapshot,
        [string]$Owner,
        [string]$Label
    )

    if ($null -eq $Snapshot -or [string]::IsNullOrWhiteSpace([string]$Snapshot.sha256)) {
        throw "$Label lacks sha256: $Owner"
    }
    $pathValue = if ($null -ne $Snapshot.PSObject.Properties['path']) {
        [string]$Snapshot.path
    }
    elseif ($null -ne $Snapshot.PSObject.Properties['name']) {
        [string]$Snapshot.name
    }
    else {
        $null
    }
    $name = [IO.Path]::GetFileName($pathValue.Replace('/', [IO.Path]::DirectorySeparatorChar))
    if ([string]::IsNullOrWhiteSpace($name) -or
        -not $name.EndsWith('.NPK', [StringComparison]::OrdinalIgnoreCase)) {
        throw "$Label does not identify an NPK filename: $Owner/$pathValue"
    }
    if ($null -eq $Snapshot.PSObject.Properties['length'] -or [long]$Snapshot.length -lt 1) {
        throw "$Label lacks a positive length: $Owner/$name"
    }
    return [pscustomobject]@{
        owner = $Owner
        label = $Label
        name = $name
        capturedPath = $pathValue
        expectedLength = [long]$Snapshot.length
        expectedSha256 = ([string]$Snapshot.sha256).ToUpperInvariant()
    }
}

$inputRecords = New-Object System.Collections.Generic.List[object]
$inputSnapshots = New-Object System.Collections.Generic.List[object]
foreach ($value in $SnapshotJsonPath) {
    $path = (Resolve-Path -LiteralPath $value).Path
    $json = Get-Content -LiteralPath $path -Raw -Encoding UTF8 | ConvertFrom-Json
    $inputSnapshots.Add((Get-DnfFileSnapshot -Path $path))
    if ($null -ne $json.PSObject.Properties['sourcePacks']) {
        $index = 0
        foreach ($sourcePack in @($json.sourcePacks)) {
            $inputRecords.Add((New-ExpectedSourceRecord -Snapshot $sourcePack -Owner $path `
                -Label "sourcePacks[$index]"))
            $index++
        }
    }
    if ($null -ne $json.PSObject.Properties['sources']) {
        $index = 0
        foreach ($source in @($json.sources)) {
            if ($null -eq $source.PSObject.Properties['sourceNpk']) {
                throw "sources[$index] lacks sourceNpk: $path"
            }
            $inputRecords.Add((New-ExpectedSourceRecord -Snapshot $source.sourceNpk -Owner $path `
                -Label "sources[$index].sourceNpk"))
            $index++
        }
    }
}
if ($inputRecords.Count -eq 0) {
    throw 'No sourcePacks or sources[].sourceNpk snapshots were found.'
}

$uniqueByIdentity = @{}
foreach ($record in $inputRecords) {
    $key = $record.name.ToUpperInvariant() + '|' + $record.expectedLength + '|' + $record.expectedSha256
    if (-not $uniqueByIdentity.ContainsKey($key)) {
        $uniqueByIdentity[$key] = $record
    }
}

$hashCache = @{}
$results = New-Object System.Collections.Generic.List[object]
foreach ($record in @($uniqueByIdentity.Values | Sort-Object name, expectedSha256)) {
    $sourcePath = Join-Path $imagePacksPath $record.name
    $exists = Test-Path -LiteralPath $sourcePath -PathType Leaf
    $actualLength = $null
    $actualHash = $null
    $lastWriteTime = $null
    if ($exists) {
        $item = Get-Item -LiteralPath $sourcePath
        $actualLength = [long]$item.Length
        $lastWriteTime = $item.LastWriteTime.ToString('o')
        if (-not $hashCache.ContainsKey($sourcePath)) {
            $hashCache[$sourcePath] = (Get-FileHash -LiteralPath $sourcePath -Algorithm SHA256).Hash
        }
        $actualHash = [string]$hashCache[$sourcePath]
    }
    $lengthMatches = $exists -and $actualLength -eq $record.expectedLength
    $hashMatches = $exists -and $actualHash -eq $record.expectedSha256
    $status = if (-not $exists) {
        'missing'
    }
    elseif ($lengthMatches -and $hashMatches) {
        'matched'
    }
    else {
        'content-drift-reinventory-required'
    }
    $results.Add([pscustomobject]@{
        name = $record.name
        status = $status
        activePath = $sourcePath
        expectedLength = $record.expectedLength
        actualLength = $actualLength
        expectedSha256 = $record.expectedSha256
        actualSha256 = $actualHash
        actualLastWriteTime = $lastWriteTime
        capturedPath = $record.capturedPath
        snapshotOwner = $record.owner
        snapshotLabel = $record.label
    })
}

$resultArray = $results.ToArray()
$mismatches = @($resultArray | Where-Object { $_.status -ne 'matched' })
$result = [pscustomobject]@{
    schemaVersion = 1
    generatedAt = (Get-Date).ToString('o')
    status = if ($mismatches.Count -eq 0) { 'passed' } else { 'requires-reinventory' }
    mode = 'read-only source migration audit; no build, deployment, or process operation'
    imagePacks2 = $imagePacksPath
    inputSnapshots = $inputSnapshots.ToArray()
    counts = [pscustomobject]@{
        rawSnapshotReferences = $inputRecords.Count
        uniqueExpectedSnapshots = $resultArray.Count
        matched = @($resultArray | Where-Object { $_.status -eq 'matched' }).Count
        contentDrift = @($resultArray | Where-Object { $_.status -eq 'content-drift-reinventory-required' }).Count
        missing = @($resultArray | Where-Object { $_.status -eq 'missing' }).Count
    }
    sources = $resultArray
    decision = if ($mismatches.Count -eq 0) {
        'All captured source identities are available at the active read-only source root.'
    }
    else {
        'Do not reuse affected inventory or release evidence. Re-inventory every missing or content-drift source before a new build.'
    }
    deployment = [pscustomobject]@{
        authorized = $false
        performed = $false
        imagePacks2Write = $false
        processOperation = $false
    }
}

if (-not [string]::IsNullOrWhiteSpace($OutputFile)) {
    $outputPath = [IO.Path]::GetFullPath($OutputFile)
    if (Test-Path -LiteralPath $outputPath) {
        throw "Refusing to overwrite an existing migration report: $outputPath"
    }
    New-Item -ItemType Directory -Path (Split-Path -Parent $outputPath) -Force | Out-Null
    $result | ConvertTo-Json -Depth 8 | Set-Content -LiteralPath $outputPath -Encoding UTF8
}

if ($FailOnMismatch -and $mismatches.Count -gt 0) {
    throw "Source migration requires re-inventory for $($mismatches.Count) source snapshot(s)."
}
if ($AsJson) {
    $result | ConvertTo-Json -Depth 8
}
else {
    $result
}
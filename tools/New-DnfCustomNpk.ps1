[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)]
    [string[]]$SourceNpk,

    [Parameter(Mandatory = $true)]
    [string[]]$IncludeImgPath,

    [Parameter(Mandatory = $true)]
    [string]$OutputPath,

    [string]$SummaryPath
)

$ErrorActionPreference = 'Stop'

$repoRoot = (Resolve-Path -LiteralPath (Split-Path -Parent $PSScriptRoot)).Path
$outputFullPath = [IO.Path]::GetFullPath($OutputPath)
$repoPrefix = $repoRoot.TrimEnd([IO.Path]::DirectorySeparatorChar, [IO.Path]::AltDirectorySeparatorChar) + [IO.Path]::DirectorySeparatorChar
if (-not $outputFullPath.StartsWith($repoPrefix, [StringComparison]::OrdinalIgnoreCase)) {
    throw "Output must stay inside the repository: $outputFullPath"
}
if ([IO.Path]::GetExtension($outputFullPath) -ine '.NPK') {
    throw "Final output must use the .NPK extension: $outputFullPath"
}
if (Test-Path -LiteralPath $outputFullPath) {
    throw "Refusing to overwrite an existing artifact: $outputFullPath"
}

$summaryFullPath = $null
if (-not [string]::IsNullOrWhiteSpace($SummaryPath)) {
    $summaryFullPath = [IO.Path]::GetFullPath($SummaryPath)
    if (-not $summaryFullPath.StartsWith($repoPrefix, [StringComparison]::OrdinalIgnoreCase)) {
        throw "Summary must stay inside the repository: $summaryFullPath"
    }
    if ([IO.Path]::GetExtension($summaryFullPath) -ine '.json') {
        throw "Package summary must use the .json extension: $summaryFullPath"
    }
    if ($summaryFullPath -ieq $outputFullPath) {
        throw 'Package summary and final NPK paths must differ.'
    }
    if (Test-Path -LiteralPath $summaryFullPath) {
        throw "Refusing to overwrite an existing package summary: $summaryFullPath"
    }
}

$nameKey = [Text.Encoding]::ASCII.GetBytes(
    'puchikon@neople dungeon and fighter ' + ('DNF' * 73) + [char]0)
if ($nameKey.Length -ne 256) {
    throw "Unexpected NPK filename key length $($nameKey.Length)."
}

function Get-HashText {
    param([byte[]]$Bytes)

    $sha = [Security.Cryptography.SHA256]::Create()
    try {
        return [BitConverter]::ToString($sha.ComputeHash($Bytes)).Replace('-', '')
    }
    finally {
        $sha.Dispose()
    }
}

function Test-ByteArrayEqual {
    param(
        [byte[]]$Left,
        [byte[]]$Right
    )

    if ($null -eq $Left -or $null -eq $Right -or $Left.Length -ne $Right.Length) {
        return $false
    }
    for ($index = 0; $index -lt $Left.Length; $index++) {
        if ($Left[$index] -ne $Right[$index]) {
            return $false
        }
    }
    return $true
}

function ConvertFrom-NpkPathBytes {
    param([byte[]]$Encrypted)

    if ($Encrypted.Length -ne 256) {
        throw 'Encrypted NPK path has an invalid length.'
    }
    $plain = New-Object byte[] 256
    for ($index = 0; $index -lt 256; $index++) {
        $plain[$index] = $Encrypted[$index] -bxor $nameKey[$index]
    }
    $nullIndex = [Array]::IndexOf($plain, [byte]0)
    if ($nullIndex -lt 1) {
        throw 'NPK path is empty or not null terminated.'
    }
    return [Text.Encoding]::ASCII.GetString($plain, 0, $nullIndex)
}

function ConvertTo-NpkPathBytes {
    param([string]$Path)

    $encoded = [Text.Encoding]::ASCII.GetBytes($Path)
    if ($encoded.Length -ge 256 -or [Text.Encoding]::ASCII.GetString($encoded) -cne $Path) {
        throw "NPK path must be ASCII and shorter than 256 bytes: $Path"
    }
    $plain = New-Object byte[] 256
    [Array]::Copy($encoded, $plain, $encoded.Length)
    $encrypted = New-Object byte[] 256
    for ($index = 0; $index -lt 256; $index++) {
        $encrypted[$index] = $plain[$index] -bxor $nameKey[$index]
    }
    return ,$encrypted
}

function Read-NpkFile {
    param(
        [string]$Path,
        [Collections.Generic.HashSet[string]]$RequestedPaths
    )

    $resolved = (Resolve-Path -LiteralPath $Path).Path
    $stream = [IO.File]::Open($resolved, [IO.FileMode]::Open, [IO.FileAccess]::Read, [IO.FileShare]::Read)
    $reader = New-Object IO.BinaryReader($stream, [Text.Encoding]::ASCII, $true)
    $sha = [Security.Cryptography.SHA256]::Create()
    try {
        $magic = [Text.Encoding]::ASCII.GetString($reader.ReadBytes(16)).TrimEnd([char]0)
        if ($magic -ne 'NeoplePack_Bill') {
            throw "Invalid NPK magic in $resolved."
        }
        $count = $reader.ReadInt32()
        if ($count -le 0) {
            throw "Invalid NPK entry count in $resolved."
        }
        $headerLength = 20L + 264L * $count
        $dataStart = $headerLength + 32L
        if ($dataStart -gt $stream.Length) {
            throw "NPK header exceeds file length: $resolved"
        }

        $paths = New-Object 'Collections.Generic.HashSet[string]' ([StringComparer]::OrdinalIgnoreCase)
        $entries = New-Object 'Collections.Generic.List[object]'
        for ($entryIndex = 0; $entryIndex -lt $count; $entryIndex++) {
            $offset = [long]$reader.ReadInt32()
            $size = [long]$reader.ReadInt32()
            $internalPath = ConvertFrom-NpkPathBytes -Encrypted $reader.ReadBytes(256)
            if (-not $paths.Add($internalPath)) {
                throw "Duplicate internal path in ${resolved}: $internalPath"
            }
            if ($offset -lt $dataStart -or $size -le 0 -or $offset + $size -gt $stream.Length) {
                throw "NPK entry is outside the file: $internalPath"
            }
            $entries.Add([pscustomobject]@{
                Path = $internalPath
                Offset = $offset
                Size = $size
            })
        }

        $storedHeaderHash = $reader.ReadBytes(32)
        $hashInputLength = [int]($headerLength - ($headerLength % 17L))
        $stream.Position = 0
        $hashInput = $reader.ReadBytes($hashInputLength)
        $computedHeaderHash = $sha.ComputeHash($hashInput)
        if (-not (Test-ByteArrayEqual -Left $storedHeaderHash -Right $computedHeaderHash)) {
            throw "NPK header SHA-256 is invalid: $resolved"
        }

        $selected = @()
        foreach ($entry in $entries) {
            if (-not $RequestedPaths.Contains($entry.Path)) {
                continue
            }
            $stream.Position = $entry.Offset
            $payload = $reader.ReadBytes([int]$entry.Size)
            if ($payload.Length -ne $entry.Size) {
                throw "Could not read the full IMG payload: $($entry.Path)"
            }
            $magicEnd = [Array]::IndexOf($payload, [byte]0, 0, 18)
            if ($magicEnd -lt 0) {
                throw "Selected payload has no null-terminated IMG magic: $($entry.Path)"
            }
            $imgMagic = [Text.Encoding]::ASCII.GetString($payload, 0, $magicEnd)
            if ($imgMagic -ne 'Neople Img File' -and $imgMagic -ne 'Neople Image File') {
                throw "Selected payload has invalid IMG magic: $($entry.Path)"
            }
            $selected += [pscustomobject]@{
                Path = $entry.Path
                Payload = $payload
                PayloadSha256 = Get-HashText -Bytes $payload
                SourceNpk = $resolved
            }
        }

        return [pscustomobject]@{
            Path = $resolved
            FileSha256 = (Get-FileHash -LiteralPath $resolved -Algorithm SHA256).Hash
            EntryCount = $count
            Selected = $selected
        }
    }
    finally {
        $sha.Dispose()
        $reader.Dispose()
        $stream.Dispose()
    }
}

function Write-NpkFile {
    param(
        [string]$Path,
        [object[]]$Entries
    )

    $count = $Entries.Count
    if ($count -le 0) {
        throw 'Refusing to write an empty NPK.'
    }
    $headerLength = 20L + 264L * $count
    $nextOffset = $headerLength + 32L
    $offsets = New-Object long[] $count
    for ($index = 0; $index -lt $count; $index++) {
        $offsets[$index] = $nextOffset
        $nextOffset += $Entries[$index].Payload.Length
        if ($nextOffset -gt [int]::MaxValue) {
            throw 'Custom NPK exceeds the supported 32-bit offset range.'
        }
    }

    $headerStream = New-Object IO.MemoryStream
    $writer = New-Object IO.BinaryWriter($headerStream, [Text.Encoding]::ASCII, $true)
    try {
        $magic = New-Object byte[] 16
        $magicText = [Text.Encoding]::ASCII.GetBytes('NeoplePack_Bill')
        [Array]::Copy($magicText, $magic, $magicText.Length)
        $writer.Write($magic)
        $writer.Write([int]$count)
        for ($index = 0; $index -lt $count; $index++) {
            $writer.Write([int]$offsets[$index])
            $writer.Write([int]$Entries[$index].Payload.Length)
            $writer.Write((ConvertTo-NpkPathBytes -Path $Entries[$index].Path))
        }
        $writer.Flush()
        $headerBytes = $headerStream.ToArray()
    }
    finally {
        $writer.Dispose()
        $headerStream.Dispose()
    }
    if ($headerBytes.Length -ne $headerLength) {
        throw 'Internal NPK header length mismatch.'
    }

    $hashInputLength = [int]($headerLength - ($headerLength % 17L))
    $sha = [Security.Cryptography.SHA256]::Create()
    try {
        $headerHash = $sha.ComputeHash($headerBytes, 0, $hashInputLength)
    }
    finally {
        $sha.Dispose()
    }

    $output = [IO.File]::Open($Path, [IO.FileMode]::CreateNew, [IO.FileAccess]::Write, [IO.FileShare]::None)
    try {
        $output.Write($headerBytes, 0, $headerBytes.Length)
        $output.Write($headerHash, 0, $headerHash.Length)
        foreach ($entry in $Entries) {
            $output.Write($entry.Payload, 0, $entry.Payload.Length)
        }
        $output.Flush($true)
    }
    finally {
        $output.Dispose()
    }
}

$requested = New-Object 'Collections.Generic.HashSet[string]' ([StringComparer]::OrdinalIgnoreCase)
$orderedPaths = @()
foreach ($internalPath in $IncludeImgPath) {
    if ([string]::IsNullOrWhiteSpace($internalPath) -or -not $requested.Add($internalPath)) {
        throw "IncludeImgPath contains an empty or duplicate value: $internalPath"
    }
    $orderedPaths += $internalPath
}

$selectedByPath = New-Object 'Collections.Generic.Dictionary[string,object]' ([StringComparer]::OrdinalIgnoreCase)
$sources = @()
foreach ($source in $SourceNpk) {
    $sourceInfo = Read-NpkFile -Path $source -RequestedPaths $requested
    $sources += $sourceInfo
    foreach ($entry in $sourceInfo.Selected) {
        if ($selectedByPath.ContainsKey($entry.Path)) {
            throw "Selected IMG appears in more than one source NPK: $($entry.Path)"
        }
        $selectedByPath.Add($entry.Path, $entry)
    }
}

$orderedEntries = @()
foreach ($internalPath in $orderedPaths) {
    if (-not $selectedByPath.ContainsKey($internalPath)) {
        throw "Requested IMG was not found in the provided source NPK files: $internalPath"
    }
    $orderedEntries += $selectedByPath[$internalPath]
}

$outputDirectory = Split-Path -Parent $outputFullPath
New-Item -ItemType Directory -Path $outputDirectory -Force | Out-Null
$temporaryPath = Join-Path $outputDirectory ('.' + [IO.Path]::GetFileName($outputFullPath) + '.' + [Guid]::NewGuid().ToString('N') + '.tmp')
$temporarySummaryPath = $null
$outputCommitted = $false
$summaryCommitted = $false
$resultJson = $null
try {
    Write-NpkFile -Path $temporaryPath -Entries $orderedEntries
    $outputCheck = Read-NpkFile -Path $temporaryPath -RequestedPaths $requested
    if ($outputCheck.EntryCount -ne $orderedEntries.Count -or $outputCheck.Selected.Count -ne $orderedEntries.Count) {
        throw 'Temporary custom NPK entry count validation failed.'
    }
    foreach ($entry in $orderedEntries) {
        $verified = $outputCheck.Selected | Where-Object { $_.Path -ieq $entry.Path }
        if (@($verified).Count -ne 1 -or $verified.PayloadSha256 -ne $entry.PayloadSha256) {
            throw "Temporary custom NPK payload validation failed: $($entry.Path)"
        }
    }

    $packagerPath = (Resolve-Path -LiteralPath $MyInvocation.MyCommand.Path).Path
    $result = [ordered]@{
        schemaVersion = 1
        generatedAtUtc = [DateTime]::UtcNow.ToString('o')
        output = $outputFullPath
        length = (Get-Item -LiteralPath $temporaryPath).Length
        sha256 = (Get-FileHash -LiteralPath $temporaryPath -Algorithm SHA256).Hash
        packageSummaryPath = $summaryFullPath
        entryCount = $orderedEntries.Count
        entries = @($orderedEntries | ForEach-Object {
            [ordered]@{
                path = $_.Path
                payloadLength = $_.Payload.Length
                payloadSha256 = $_.PayloadSha256
                sourceNpk = $_.SourceNpk
            }
        })
        sources = @($sources | ForEach-Object {
            [ordered]@{
                path = $_.Path
                sha256 = $_.FileSha256
                entryCount = $_.EntryCount
            }
        })
        packager = [ordered]@{
            path = $packagerPath
            length = (Get-Item -LiteralPath $packagerPath).Length
            sha256 = (Get-FileHash -LiteralPath $packagerPath -Algorithm SHA256).Hash
        }
        deployment = 'not-performed-by-packager'
    }
    $resultJson = $result | ConvertTo-Json -Depth 8

    if ($null -ne $summaryFullPath) {
        $summaryDirectory = Split-Path -Parent $summaryFullPath
        New-Item -ItemType Directory -Path $summaryDirectory -Force | Out-Null
        $temporarySummaryPath = Join-Path $summaryDirectory (
            '.' + [IO.Path]::GetFileName($summaryFullPath) + '.' + [Guid]::NewGuid().ToString('N') + '.tmp')
        $resultJson | Set-Content -LiteralPath $temporarySummaryPath -Encoding UTF8
        $summaryCheck = Get-Content -LiteralPath $temporarySummaryPath -Raw -Encoding UTF8 | ConvertFrom-Json
        if ($summaryCheck.output -ine $outputFullPath -or
            [long]$summaryCheck.length -ne (Get-Item -LiteralPath $temporaryPath).Length -or
            $summaryCheck.sha256 -ne (Get-FileHash -LiteralPath $temporaryPath -Algorithm SHA256).Hash -or
            [int]$summaryCheck.entryCount -ne $orderedEntries.Count -or
            $summaryCheck.deployment -ne 'not-performed-by-packager') {
            throw 'Temporary package summary validation failed.'
        }
    }

    [IO.File]::Move($temporaryPath, $outputFullPath)
    $outputCommitted = $true
    if ($null -ne $summaryFullPath) {
        try {
            [IO.File]::Move($temporarySummaryPath, $summaryFullPath)
            $summaryCommitted = $true
        }
        catch {
            if (Test-Path -LiteralPath $outputFullPath -PathType Leaf) {
                Remove-Item -LiteralPath $outputFullPath -Force
            }
            $outputCommitted = $false
            throw
        }
    }
}
finally {
    if (Test-Path -LiteralPath $temporaryPath) {
        Remove-Item -LiteralPath $temporaryPath -Force
    }
    if ($null -ne $temporarySummaryPath -and (Test-Path -LiteralPath $temporarySummaryPath)) {
        Remove-Item -LiteralPath $temporarySummaryPath -Force
    }
}

if (-not $outputCommitted -or ($null -ne $summaryFullPath -and -not $summaryCommitted)) {
    throw 'Custom NPK and package summary were not committed together.'
}
$resultJson

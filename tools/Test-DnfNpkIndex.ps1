param(
    [Parameter(Mandatory = $true)]
    [string]$Path,

    [int]$ExpectedEntryCount = 0,

    [string]$ExpectedSha256,

    [switch]$AsJson
)

$ErrorActionPreference = 'Stop'

$resolvedPath = (Resolve-Path -LiteralPath $Path).Path
$item = Get-Item -LiteralPath $resolvedPath
$fileHash = (Get-FileHash -LiteralPath $resolvedPath -Algorithm SHA256).Hash

if (-not [string]::IsNullOrWhiteSpace($ExpectedSha256) -and
    $fileHash -ne $ExpectedSha256.ToUpperInvariant()) {
    throw "SHA-256 mismatch for $resolvedPath. Expected $ExpectedSha256, found $fileHash."
}

$stream = [IO.File]::Open(
    $resolvedPath,
    [IO.FileMode]::Open,
    [IO.FileAccess]::Read,
    [IO.FileShare]::Read)
$reader = New-Object IO.BinaryReader($stream, [Text.Encoding]::ASCII, $true)
$sha256 = [Security.Cryptography.SHA256]::Create()

try {
    $magic = [Text.Encoding]::ASCII.GetString($reader.ReadBytes(16)).TrimEnd([char]0)
    if ($magic -ne 'NeoplePack_Bill') {
        throw "Invalid NPK magic '$magic'."
    }

    $entryCount = $reader.ReadInt32()
    if ($entryCount -le 0) {
        throw "Invalid NPK entry count $entryCount."
    }
    if ($ExpectedEntryCount -gt 0 -and $entryCount -ne $ExpectedEntryCount) {
        throw "NPK entry count mismatch. Expected $ExpectedEntryCount, found $entryCount."
    }

    $headerLength = 20L + 264L * $entryCount
    $dataStart = $headerLength + 32L
    if ($dataStart -gt $stream.Length) {
        throw "NPK header extends beyond the file ($dataStart/$($stream.Length))."
    }

    $nameKey = [Text.Encoding]::ASCII.GetBytes(
        'puchikon@neople dungeon and fighter ' + ('DNF' * 73) + [char]0)
    if ($nameKey.Length -ne 256) {
        throw "Unexpected NPK filename key length $($nameKey.Length)."
    }

    $entries = New-Object 'Collections.Generic.List[object]'
    $paths = New-Object 'Collections.Generic.HashSet[string]' ([StringComparer]::OrdinalIgnoreCase)
    for ($entryIndex = 0; $entryIndex -lt $entryCount; $entryIndex++) {
        $offset = [long]$reader.ReadInt32()
        $size = [long]$reader.ReadInt32()
        $encryptedName = $reader.ReadBytes(256)
        if ($encryptedName.Length -ne 256) {
            throw "Truncated NPK index entry $entryIndex."
        }

        $plainName = New-Object byte[] 256
        for ($byteIndex = 0; $byteIndex -lt 256; $byteIndex++) {
            $plainName[$byteIndex] = $encryptedName[$byteIndex] -bxor $nameKey[$byteIndex]
        }
        $nullIndex = [Array]::IndexOf($plainName, [byte]0)
        if ($nullIndex -lt 0) {
            throw "NPK path at index $entryIndex is not null terminated."
        }

        $internalPath = [Text.Encoding]::ASCII.GetString($plainName, 0, $nullIndex)
        if ([string]::IsNullOrWhiteSpace($internalPath)) {
            throw "NPK path at index $entryIndex is empty."
        }
        if (-not $paths.Add($internalPath)) {
            throw "Duplicate NPK path '$internalPath'."
        }
        if ($offset -lt $dataStart -or $size -le 0 -or $offset + $size -gt $stream.Length) {
            throw "NPK entry '$internalPath' is outside the file ($offset + $size/$($stream.Length))."
        }

        $entries.Add([PSCustomObject]@{
            Index = $entryIndex
            Offset = $offset
            Size = $size
            Path = $internalPath
        })
    }

    $storedHeaderHash = $reader.ReadBytes(32)
    if ($storedHeaderHash.Length -ne 32) {
        throw 'NPK header SHA-256 is truncated.'
    }
    $hashInputLength = [int]($headerLength - ($headerLength % 17L))
    $stream.Position = 0
    $hashInput = $reader.ReadBytes($hashInputLength)
    $computedHeaderHash = $sha256.ComputeHash($hashInput)
    $storedHeaderHashText = [BitConverter]::ToString($storedHeaderHash).Replace('-', '')
    $computedHeaderHashText = [BitConverter]::ToString($computedHeaderHash).Replace('-', '')
    if ($storedHeaderHashText -ne $computedHeaderHashText) {
        throw "NPK header SHA-256 mismatch. Expected $storedHeaderHashText, computed $computedHeaderHashText."
    }

    $versionCounts = @{}
    foreach ($entry in $entries) {
        $stream.Position = $entry.Offset
        $imgHeader = $reader.ReadBytes([Math]::Min(28, [int]$entry.Size))
        if ($imgHeader.Length -lt 28) {
            throw "IMG '$($entry.Path)' has a truncated header."
        }

        $magicEnd = [Array]::IndexOf($imgHeader, [byte]0, 0, 18)
        if ($magicEnd -lt 0) {
            throw "IMG '$($entry.Path)' has no null-terminated magic."
        }
        $imgMagic = [Text.Encoding]::ASCII.GetString($imgHeader, 0, $magicEnd)
        if ($imgMagic -ne 'Neople Img File' -and $imgMagic -ne 'Neople Image File') {
            throw "IMG '$($entry.Path)' has invalid magic '$imgMagic'."
        }

        $version = [BitConverter]::ToInt32($imgHeader, 24)
        if ($version -notin @(1, 2, 4, 5, 6)) {
            throw "IMG '$($entry.Path)' has unsupported version $version."
        }
        if ($versionCounts.ContainsKey($version)) {
            $versionCounts[$version]++
        }
        else {
            $versionCounts[$version] = 1
        }
    }

    $versionSummary = [ordered]@{}
    foreach ($version in ($versionCounts.Keys | Sort-Object)) {
        $versionSummary[[string]$version] = $versionCounts[$version]
    }

    $result = [PSCustomObject]@{
        Path = $resolvedPath
        Length = $item.Length
        Sha256 = $fileHash
        NpkMagic = $magic
        EntryCount = $entryCount
        UniquePathCount = $paths.Count
        HeaderSha256Valid = $true
        DataStart = $dataStart
        ImgMagicValidCount = $entryCount
        ImgVersionCounts = $versionSummary
        Validator = 'tools/Test-DnfNpkIndex.ps1'
        ParserDependency = 'PowerShell/.NET only; no ExtractorSharp'
    }

    if ($AsJson) {
        $result | ConvertTo-Json -Depth 5
    }
    else {
        $result | Format-List
    }
}
finally {
    $sha256.Dispose()
    $reader.Dispose()
    $stream.Dispose()
}

[CmdletBinding()]
param(
    [string]$Path,

    [switch]$AsJson
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
$OutputEncoding = [Console]::OutputEncoding = New-Object System.Text.UTF8Encoding($false)

function Resolve-FullPath {
    param(
        [Parameter(Mandatory = $true)]
        [string]$Value,

        [Parameter(Mandatory = $true)]
        [string]$BaseDirectory
    )

    if ([IO.Path]::IsPathRooted($Value)) {
        return [IO.Path]::GetFullPath($Value)
    }
    return [IO.Path]::GetFullPath((Join-Path $BaseDirectory $Value))
}

function Test-StartsWithBytes {
    param(
        [Parameter(Mandatory = $true)]
        [byte[]]$Bytes,

        [Parameter(Mandatory = $true)]
        [byte[]]$Prefix
    )

    if ($Bytes.Length -lt $Prefix.Length) {
        return $false
    }
    for ($index = 0; $index -lt $Prefix.Length; $index++) {
        if ($Bytes[$index] -ne $Prefix[$index]) {
            return $false
        }
    }
    return $true
}

$repoRoot = Split-Path -Parent $PSScriptRoot
$scanRoot = if ([string]::IsNullOrWhiteSpace($Path)) {
    $repoRoot
}
else {
    Resolve-FullPath -Value $Path -BaseDirectory $repoRoot
}

if (-not (Test-Path -LiteralPath $scanRoot)) {
    throw "PowerShell source scan path was not found: $scanRoot"
}

$utf8Bom = [byte[]](0xEF, 0xBB, 0xBF)
$utf16LeBom = [byte[]](0xFF, 0xFE)
$utf16BeBom = [byte[]](0xFE, 0xFF)
$utf32LeBom = [byte[]](0xFF, 0xFE, 0x00, 0x00)
$utf32BeBom = [byte[]](0x00, 0x00, 0xFE, 0xFF)
$strictUtf8 = New-Object System.Text.UTF8Encoding($false, $true)
$issues = New-Object System.Collections.Generic.List[object]

$item = Get-Item -LiteralPath $scanRoot
$generatedDirectoryNames = @(
    'node_modules',
    '.runs',
    'out',
    'dist',
    'build',
    'test-results',
    'playwright-report',
    'coverage'
)
$files = @(if ($item -is [IO.FileInfo]) {
    $item
}
else {
    Get-ChildItem -LiteralPath $scanRoot -Recurse -File | Where-Object {
        $relativePath = $_.FullName.Substring($item.FullName.Length).TrimStart(
            [IO.Path]::DirectorySeparatorChar,
            [IO.Path]::AltDirectorySeparatorChar)
        $segments = @($relativePath -split '[\\/]')
        $_.Extension -in @('.ps1', '.psm1', '.psd1') -and
        @($segments | Where-Object { $_ -in $generatedDirectoryNames }).Count -eq 0 -and
        -not $relativePath.StartsWith('tools\bin\', [StringComparison]::OrdinalIgnoreCase)
    } | Sort-Object FullName
})

$asciiFileCount = 0
$utf8BomFileCount = 0
foreach ($file in $files) {
    $bytes = [IO.File]::ReadAllBytes($file.FullName)
    $hasUtf8Bom = Test-StartsWithBytes -Bytes $bytes -Prefix $utf8Bom
    $hasUnsupportedBom = (Test-StartsWithBytes -Bytes $bytes -Prefix $utf32LeBom) -or
        (Test-StartsWithBytes -Bytes $bytes -Prefix $utf32BeBom) -or
        (Test-StartsWithBytes -Bytes $bytes -Prefix $utf16LeBom) -or
        (Test-StartsWithBytes -Bytes $bytes -Prefix $utf16BeBom)

    if ($hasUnsupportedBom) {
        $issues.Add([pscustomobject]@{
            code = 'unsupported-encoding'
            path = $file.FullName
            message = 'PowerShell source must be ASCII without BOM or UTF-8 with BOM.'
        })
        continue
    }

    $offset = if ($hasUtf8Bom) { 3 } else { 0 }
    try {
        $null = $strictUtf8.GetString($bytes, $offset, $bytes.Length - $offset)
    }
    catch {
        $issues.Add([pscustomobject]@{
            code = 'invalid-utf8'
            path = $file.FullName
            message = $_.Exception.Message
        })
        continue
    }

    $hasNonAscii = $false
    for ($index = $offset; $index -lt $bytes.Length; $index++) {
        if ($bytes[$index] -gt 0x7F) {
            $hasNonAscii = $true
            break
        }
    }

    if ($hasNonAscii -and -not $hasUtf8Bom) {
        $issues.Add([pscustomobject]@{
            code = 'utf8-bom-required'
            path = $file.FullName
            message = 'Windows PowerShell 5.1 misdecodes non-ASCII UTF-8 source without a BOM.'
        })
    }
    elseif ($hasUtf8Bom) {
        $utf8BomFileCount++
    }
    else {
        $asciiFileCount++
    }

    $tokens = $null
    $parseErrors = $null
    [void][Management.Automation.Language.Parser]::ParseFile(
        $file.FullName,
        [ref]$tokens,
        [ref]$parseErrors)
    foreach ($parseError in @($parseErrors)) {
        $issues.Add([pscustomobject]@{
            code = 'parse-error'
            path = $file.FullName
            message = "Line $($parseError.Extent.StartLineNumber): $($parseError.Message)"
        })
    }
}

$status = if ($issues.Count -eq 0) { 'passed' } else { 'failed' }
$issueArray = $issues.ToArray()
$result = [pscustomobject]@{
    schemaVersion = 1
    status = $status
    scanRoot = $scanRoot
    powershellVersion = $PSVersionTable.PSVersion.ToString()
    fileCount = $files.Count
    asciiWithoutBomCount = $asciiFileCount
    utf8WithBomCount = $utf8BomFileCount
    issueCount = $issues.Count
    issues = $issueArray
}

if ($issues.Count -gt 0) {
    $details = @($issues | ForEach-Object { "$($_.code):$($_.path)" }) -join '; '
    throw "PowerShell source gate failed with $($issues.Count) issue(s): $details"
}

if ($AsJson) {
    $result | ConvertTo-Json -Depth 8
}
else {
    $result
}

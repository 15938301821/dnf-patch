[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)]
    [string]$SourcePath,

    [string]$RepoRoot
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
$OutputEncoding = [Console]::OutputEncoding = New-Object System.Text.UTF8Encoding($false)

function Resolve-FullPath {
    param(
        [Parameter(Mandatory = $true)]
        [string]$Path,

        [string]$BasePath = (Get-Location).Path
    )

    if ([System.IO.Path]::IsPathRooted($Path)) {
        return [System.IO.Path]::GetFullPath($Path)
    }

    return [System.IO.Path]::GetFullPath((Join-Path -Path $BasePath -ChildPath $Path))
}

function Assert-NoReparsePointInChain {
    param(
        [Parameter(Mandatory = $true)][string]$Path,
        [Parameter(Mandatory = $true)][string]$RootPath
    )

    $root = (Get-Item -LiteralPath $RootPath -Force).FullName.TrimEnd([System.IO.Path]::DirectorySeparatorChar, [System.IO.Path]::AltDirectorySeparatorChar)
    $rootPrefix = $root + [System.IO.Path]::DirectorySeparatorChar
    $current = Get-Item -LiteralPath $Path -Force

    while ($null -ne $current) {
        if (($current.Attributes -band [System.IO.FileAttributes]::ReparsePoint) -ne 0) {
            throw "路径链不能包含符号链接或重解析点：$($current.FullName)"
        }

        if ($current.FullName.Equals($root, [System.StringComparison]::OrdinalIgnoreCase)) {
            return
        }

        $parent = if ($current -is [System.IO.DirectoryInfo]) { $current.Parent } else { $current.Directory }
        if ($null -eq $parent -or (-not $parent.FullName.Equals($root, [System.StringComparison]::OrdinalIgnoreCase) -and -not $parent.FullName.StartsWith($rootPrefix, [System.StringComparison]::OrdinalIgnoreCase))) {
            throw "路径链越出仓库根：$Path"
        }
        $current = $parent
    }
}

function Get-Utf8Text {
    param([Parameter(Mandatory = $true)][string]$Path)

    $bytes = [System.IO.File]::ReadAllBytes($Path)
    $decoder = New-Object System.Text.UTF8Encoding($false, $true)

    try {
        $text = $decoder.GetString($bytes)
    }
    catch {
        throw "源文件不是有效 UTF-8：$Path"
    }

    if ($text.Length -gt 0 -and $text[0] -eq [char]0xFEFF) {
        return $text.Substring(1)
    }

    return $text
}

function Get-TextSha256 {
    param([Parameter(Mandatory = $true)][string]$Text)

    $bytes = (New-Object System.Text.UTF8Encoding($false)).GetBytes($Text)
    $sha = [System.Security.Cryptography.SHA256]::Create()
    try {
        return ([System.BitConverter]::ToString($sha.ComputeHash($bytes))).Replace('-', '')
    }
    finally {
        $sha.Dispose()
    }
}

if (-not [System.IO.Path]::IsPathRooted($SourcePath)) {
    throw "源文件必须使用绝对路径：$SourcePath"
}

$sourceFullPath = Resolve-FullPath -Path $SourcePath
if (-not (Test-Path -LiteralPath $sourceFullPath -PathType Leaf)) {
    throw "源文件不存在：$sourceFullPath"
}

$sourceItem = Get-Item -LiteralPath $sourceFullPath -Force

if ([string]::IsNullOrWhiteSpace($RepoRoot)) {
    $RepoRoot = Join-Path -Path $PSScriptRoot -ChildPath '..\..\..\..'
}

$repoFullPath = Resolve-FullPath -Path $RepoRoot
if (-not (Test-Path -LiteralPath $repoFullPath -PathType Container)) {
    throw "仓库根不存在：$repoFullPath"
}

$repoItem = Get-Item -LiteralPath $repoFullPath -Force
$repoFullPath = $repoItem.FullName.TrimEnd([System.IO.Path]::DirectorySeparatorChar, [System.IO.Path]::AltDirectorySeparatorChar)
$repoPrefix = $repoFullPath + [System.IO.Path]::DirectorySeparatorChar

if (-not $sourceFullPath.StartsWith($repoPrefix, [System.StringComparison]::OrdinalIgnoreCase)) {
    throw "源文件必须位于当前仓库内：$sourceFullPath"
}

Assert-NoReparsePointInChain -Path $sourceFullPath -RootPath $repoFullPath

$extension = [System.IO.Path]::GetExtension($sourceFullPath).ToLowerInvariant()
if ($extension -notin @('.md', '.txt')) {
    throw "只接受 .md 或 .txt 源文件：$sourceFullPath"
}

$relativePath = $sourceFullPath.Substring($repoPrefix.Length).Replace('\', '/')
$segments = @($relativePath.Split('/') | Where-Object { $_.Length -gt 0 })
$professionHint = if ($segments.Count -ge 3 -and $segments[0].Equals('jobs', [System.StringComparison]::OrdinalIgnoreCase)) { $segments[1] } else { $null }
$warnings = New-Object System.Collections.Generic.List[string]

if ($null -eq $professionHint) {
    $warnings.Add('源文件不在 jobs 下的职业子目录内，无法从路径确定职业候选。')
}
elseif ($segments.Count -gt 3) {
    $warnings.Add('源文件不是职业目录的直属文件；职业候选仍取 jobs 下一层目录，需检查显式职业声明。')
}

$text = Get-Utf8Text -Path $sourceFullPath
if ([string]::IsNullOrWhiteSpace($text)) {
    throw "源文件为空：$sourceFullPath"
}
$lines = [System.Text.RegularExpressions.Regex]::Split($text, "\r\n|\n|\r")
$headings = New-Object System.Collections.Generic.List[object]
$codeBlocks = New-Object System.Collections.Generic.List[object]
$activeFence = $null
$activeContent = $null

for ($index = 0; $index -lt $lines.Count; $index++) {
    $line = $lines[$index]
    $lineNumber = $index + 1

    if ($null -ne $activeFence) {
        $fenceCharacter = [System.Text.RegularExpressions.Regex]::Escape($activeFence.Marker.Substring(0, 1))
        $closePattern = '^\s*' + $fenceCharacter + '{' + $activeFence.Marker.Length + ',}\s*$'

        if ($line -match $closePattern) {
            $content = [string]::Join("`n", $activeContent.ToArray())
            $preview = ($content -replace '\s+', ' ').Trim()
            if ($preview.Length -gt 160) {
                $preview = $preview.Substring(0, 160)
            }

            $codeBlocks.Add([pscustomobject]@{
                startLine = $activeFence.StartLine
                endLine = $lineNumber
                language = $activeFence.Language
                lineCount = $activeContent.Count
                sha256 = Get-TextSha256 -Text $content
                preview = $preview
            })
            $activeFence = $null
            $activeContent = $null
            continue
        }

        $activeContent.Add($line)
        continue
    }

    if ($line -match '^\s*(?<fence>`{3,}|~{3,})(?<info>.*)$') {
        $activeFence = [pscustomobject]@{
            Marker = $Matches['fence']
            Language = $Matches['info'].Trim()
            StartLine = $lineNumber
        }
        $activeContent = New-Object System.Collections.Generic.List[string]
        continue
    }

    if ($line -match '^(?<marks>#{1,6})[ \t]+(?<title>.+?)\s*$') {
        $title = ($Matches['title'] -replace '\s+#+\s*$', '').Trim()
        $headings.Add([pscustomobject]@{
            line = $lineNumber
            level = $Matches['marks'].Length
            title = $title
        })
    }
}

if ($null -ne $activeFence) {
    $warnings.Add("第 $($activeFence.StartLine) 行开始的代码块没有闭合。")
}

$firstTitle = $headings | Where-Object { $_.level -eq 1 } | Select-Object -First 1
$result = [ordered]@{
    schemaVersion = 1
    source = [ordered]@{
        path = $sourceFullPath
        relativePath = $relativePath
        length = $sourceItem.Length
        lastWriteTime = $sourceItem.LastWriteTime.ToString('o')
        sha256 = (Get-FileHash -LiteralPath $sourceFullPath -Algorithm SHA256).Hash
        encoding = 'utf-8'
    }
    routeHints = [ordered]@{
        professionFromPath = $professionHint
        firstLevelOneTitle = if ($null -ne $firstTitle) { $firstTitle.title } else { $null }
    }
    inventory = [ordered]@{
        lineCount = $lines.Count
        headingCount = $headings.Count
        fencedCodeBlockCount = $codeBlocks.Count
        headings = @($headings.ToArray())
        fencedCodeBlocks = @($codeBlocks.ToArray())
    }
    warnings = @($warnings.ToArray())
}

$result | ConvertTo-Json -Depth 8

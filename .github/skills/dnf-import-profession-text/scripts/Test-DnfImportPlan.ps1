[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)]
    [string]$SourcePath,

    [Parameter(Mandatory = $true)]
    [string]$ProfessionName,

    [string]$ThemeName,

    [Parameter(Mandatory = $true)]
    [AllowEmptyCollection()]
    [string[]]$PromptName,

    [AllowEmptyCollection()]
    [string[]]$ThemePromptName = @(),

    [string]$RepoRoot
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
$OutputEncoding = [Console]::OutputEncoding = New-Object System.Text.UTF8Encoding($false)
$script:Errors = New-Object System.Collections.Generic.List[object]
$script:Warnings = New-Object System.Collections.Generic.List[object]
$script:Targets = New-Object System.Collections.Generic.List[object]

function Add-Issue {
    param(
        [Parameter(Mandatory = $true)][string]$Code,
        [Parameter(Mandatory = $true)][string]$Path,
        [Parameter(Mandatory = $true)][string]$Message,
        [switch]$Warning
    )

    $issue = [pscustomobject]@{
        code    = $Code
        path    = $Path
        message = $Message
    }
    if ($Warning) {
        $script:Warnings.Add($issue)
    }
    else {
        $script:Errors.Add($issue)
    }
}

function Resolve-FullPath {
    param(
        [Parameter(Mandatory = $true)][string]$Path,
        [string]$BasePath = (Get-Location).Path
    )

    if ([System.IO.Path]::IsPathRooted($Path)) {
        return [System.IO.Path]::GetFullPath($Path)
    }
    return [System.IO.Path]::GetFullPath((Join-Path -Path $BasePath -ChildPath $Path))
}

function Test-ReparsePointChain {
    param(
        [Parameter(Mandatory = $true)][string]$Path,
        [Parameter(Mandatory = $true)][string]$RootPath,
        [Parameter(Mandatory = $true)][string]$Code
    )

    $root = (Get-Item -LiteralPath $RootPath -Force).FullName.TrimEnd([System.IO.Path]::DirectorySeparatorChar, [System.IO.Path]::AltDirectorySeparatorChar)
    $rootPrefix = $root + [System.IO.Path]::DirectorySeparatorChar
    $candidate = $Path
    while (-not (Test-Path -LiteralPath $candidate)) {
        $parent = [System.IO.Path]::GetDirectoryName($candidate)
        if ([string]::IsNullOrWhiteSpace($parent) -or $parent -eq $candidate) {
            Add-Issue -Code $Code -Path $Path -Message '找不到位于仓库内的既有父目录。'
            return $false
        }
        $candidate = $parent
    }

    $current = Get-Item -LiteralPath $candidate -Force
    while ($null -ne $current) {
        if (($current.Attributes -band [System.IO.FileAttributes]::ReparsePoint) -ne 0) {
            Add-Issue -Code $Code -Path $current.FullName -Message '目标路径链不能包含符号链接或重解析点。'
            return $false
        }
        if ($current.FullName.Equals($root, [System.StringComparison]::OrdinalIgnoreCase)) {
            return $true
        }

        $parent = if ($current -is [System.IO.DirectoryInfo]) { $current.Parent } else { $current.Directory }
        if ($null -eq $parent -or (-not $parent.FullName.Equals($root, [System.StringComparison]::OrdinalIgnoreCase) -and -not $parent.FullName.StartsWith($rootPrefix, [System.StringComparison]::OrdinalIgnoreCase))) {
            Add-Issue -Code $Code -Path $Path -Message '目标路径链越出仓库根。'
            return $false
        }
        $current = $parent
    }

    return $false
}

function Convert-ToSafeName {
    param([Parameter(Mandatory = $true)][AllowEmptyString()][string]$Value)

    $result = ($Value -replace '\s+', ' ').Trim()
    $result = $result.Replace(':', '：').Replace('/', '／').Replace('\', '／')
    $result = $result.Replace('*', '＊').Replace('?', '？').Replace('"', '＂')
    $result = $result.Replace('<', '＜').Replace('>', '＞').Replace('|', '｜')
    return $result.TrimEnd([char[]]@(' ', '.')).Normalize([System.Text.NormalizationForm]::FormC)
}

function Test-SafeLeafName {
    param(
        [Parameter(Mandatory = $true)][AllowEmptyString()][string]$Value,
        [Parameter(Mandatory = $true)][string]$Path,
        [Parameter(Mandatory = $true)][string]$Code
    )

    if ([string]::IsNullOrWhiteSpace($Value) -or $Value -in @('.', '..')) {
        Add-Issue -Code $Code -Path $Path -Message '名称不能为空、点目录或父目录。'
        return $false
    }
    if ($Value -match '^(?i:CON|PRN|AUX|NUL|COM[1-9]|LPT[1-9])$') {
        Add-Issue -Code $Code -Path $Path -Message '名称是 Windows 设备保留名。'
        return $false
    }
    if ($Value.IndexOfAny([System.IO.Path]::GetInvalidFileNameChars()) -ge 0 -or $Value.EndsWith(' ') -or $Value.EndsWith('.')) {
        Add-Issue -Code $Code -Path $Path -Message '名称含 Windows 非法字符或尾随空格/句点。'
        return $false
    }
    return $true
}

function Add-Target {
    param(
        [Parameter(Mandatory = $true)][string]$Path,
        [Parameter(Mandatory = $true)][string]$BasePath,
        [Parameter(Mandatory = $true)][string]$Kind,
        [Parameter(Mandatory = $true)][string]$RepoPath
    )

    $fullPath = [System.IO.Path]::GetFullPath($Path)
    $base = [System.IO.Path]::GetFullPath($BasePath).TrimEnd([System.IO.Path]::DirectorySeparatorChar, [System.IO.Path]::AltDirectorySeparatorChar)
    $basePrefix = $base + [System.IO.Path]::DirectorySeparatorChar
    if (-not $fullPath.StartsWith($basePrefix, [System.StringComparison]::OrdinalIgnoreCase)) {
        Add-Issue -Code 'target-escape' -Path $fullPath -Message '目标路径越出允许的职业或主题目录。'
        return
    }

    if (-not (Test-ReparsePointChain -Path $fullPath -RootPath $RepoPath -Code 'target-reparse-point')) {
        return
    }
    $state = if (Test-Path -LiteralPath $fullPath -PathType Leaf) {
        'existing-file'
    }
    elseif (Test-Path -LiteralPath $fullPath -PathType Container) {
        Add-Issue -Code 'target-type-collision' -Path $fullPath -Message '文件目标与现有目录冲突。'
        'wrong-type'
    }
    else {
        'missing'
    }

    $repoPrefix = $RepoPath.TrimEnd([System.IO.Path]::DirectorySeparatorChar, [System.IO.Path]::AltDirectorySeparatorChar) + [System.IO.Path]::DirectorySeparatorChar
    $script:Targets.Add([pscustomobject]@{
            kind         = $Kind
            path         = $fullPath
            relativePath = $fullPath.Substring($repoPrefix.Length).Replace('\', '/')
            state        = $state
        })
}

if ([string]::IsNullOrWhiteSpace($RepoRoot)) {
    $RepoRoot = Join-Path -Path $PSScriptRoot -ChildPath '..\..\..\..'
}

$repoFullPath = Resolve-FullPath -Path $RepoRoot
if (-not (Test-Path -LiteralPath $repoFullPath -PathType Container)) {
    throw "仓库根不存在：$repoFullPath"
}
$repoFullPath = (Get-Item -LiteralPath $repoFullPath -Force).FullName.TrimEnd([System.IO.Path]::DirectorySeparatorChar, [System.IO.Path]::AltDirectorySeparatorChar)
$repoPrefix = $repoFullPath + [System.IO.Path]::DirectorySeparatorChar

$sourceFullPath = $null
$sourceSummary = $null
if (-not [System.IO.Path]::IsPathRooted($SourcePath)) {
    Add-Issue -Code 'source-not-absolute' -Path $SourcePath -Message '源文件必须使用绝对路径。'
}
else {
    $sourceFullPath = Resolve-FullPath -Path $SourcePath
    if (-not $sourceFullPath.StartsWith($repoPrefix, [System.StringComparison]::OrdinalIgnoreCase) -or -not (Test-Path -LiteralPath $sourceFullPath -PathType Leaf)) {
        Add-Issue -Code 'source-route' -Path $sourceFullPath -Message '源文件不存在或不在当前仓库内。'
    }
    else {
        $sourcePathSafe = Test-ReparsePointChain -Path $sourceFullPath -RootPath $repoFullPath -Code 'source-reparse-point'
        if ($sourcePathSafe) {
            if ([System.IO.Path]::GetExtension($sourceFullPath).ToLowerInvariant() -notin @('.md', '.txt')) {
                Add-Issue -Code 'source-extension' -Path $sourceFullPath -Message '源文件扩展名必须是 .md 或 .txt。'
            }

            try {
                $bytes = [System.IO.File]::ReadAllBytes($sourceFullPath)
                $decoder = New-Object System.Text.UTF8Encoding($false, $true)
                $decodedText = $decoder.GetString($bytes)
                if ([string]::IsNullOrWhiteSpace($decodedText)) {
                    Add-Issue -Code 'source-empty' -Path $sourceFullPath -Message '源文件为空或只包含空白。'
                }
            }
            catch {
                Add-Issue -Code 'source-utf8' -Path $sourceFullPath -Message '源文件不是有效 UTF-8。'
            }

            $sourceSummary = [ordered]@{
                path   = $sourceFullPath
                sha256 = (Get-FileHash -LiteralPath $sourceFullPath -Algorithm SHA256).Hash
            }
        }
    }
}

$professionSafeName = Convert-ToSafeName -Value $ProfessionName
$professionPath = Join-Path -Path $repoFullPath -ChildPath $professionSafeName
$professionNameValid = Test-SafeLeafName -Value $professionSafeName -Path $professionPath -Code 'profession-name'
$professionPathSafe = $false
if ($professionSafeName -in @('.codex', '.git', 'docs', 'tools')) {
    Add-Issue -Code 'reserved-profession' -Path $professionPath -Message '基础设施目录不能作为职业目录。'
    $professionNameValid = $false
}
if (-not $professionSafeName.Equals($ProfessionName, [System.StringComparison]::Ordinal)) {
    Add-Issue -Code 'profession-normalization' -Path $professionPath -Message '职业名必须与源文件直属目录原名完全一致，不能在导入时重命名。'
    $professionNameValid = $false
}
if ($professionNameValid -and -not (Test-Path -LiteralPath $professionPath -PathType Container)) {
    Add-Issue -Code 'profession-missing' -Path $professionPath -Message '职业目录不存在；源设计文件必须先位于目标职业目录内。'
}
elseif ($professionNameValid) {
    $professionPathSafe = Test-ReparsePointChain -Path $professionPath -RootPath $repoFullPath -Code 'profession-reparse-point'
}

if ($null -ne $sourceFullPath -and $sourceFullPath.StartsWith($repoPrefix, [System.StringComparison]::OrdinalIgnoreCase)) {
    $sourceRelative = $sourceFullPath.Substring($repoPrefix.Length).Replace('\', '/')
    $sourceSegments = @($sourceRelative.Split('/') | Where-Object { $_.Length -gt 0 })
    if ($sourceSegments.Count -lt 2 -or -not $sourceSegments[0].Equals($professionSafeName, [System.StringComparison]::OrdinalIgnoreCase)) {
        Add-Issue -Code 'source-profession-route' -Path $sourceFullPath -Message '源文件的仓库根下一层目录与目标职业不一致。'
    }
}

$themeSafeName = $null
$themePath = $null
$themeNameValid = $false
if (-not [string]::IsNullOrWhiteSpace($ThemeName)) {
    $themeSafeName = Convert-ToSafeName -Value $ThemeName
    $themePath = Join-Path -Path $professionPath -ChildPath $themeSafeName
    $themeNameValid = Test-SafeLeafName -Value $themeSafeName -Path $themePath -Code 'theme-name'
    if ($themeSafeName -in @('prompts', 'frames', 'npk', 'validation', 'AGENTS.md', 'manifest.json', 'README.md')) {
        Add-Issue -Code 'reserved-theme' -Path $themePath -Message '主题名与职业基础目录冲突。'
        $themeNameValid = $false
    }
    if (-not $themeSafeName.Equals($ThemeName, [System.StringComparison]::Ordinal)) {
        Add-Issue -Code 'theme-normalized' -Path $themePath -Message "主题名已规范化为 [$themeSafeName]。" -Warning
    }
    if ($themeNameValid) {
        if (Test-Path -LiteralPath $themePath -PathType Leaf) {
            Add-Issue -Code 'theme-type-collision' -Path $themePath -Message '主题目录名与现有文件冲突。'
        }
        else {
            $themePathSafe = Test-ReparsePointChain -Path $themePath -RootPath $repoFullPath -Code 'theme-reparse-point'
            if (-not $themePathSafe) {
                $themeNameValid = $false
            }
        }
    }
}

$promptPlans = New-Object System.Collections.Generic.List[object]
$promptKeys = @{}
foreach ($displayName in $PromptName) {
    $safeName = Convert-ToSafeName -Value $displayName
    $valid = Test-SafeLeafName -Value $safeName -Path $professionPath -Code 'prompt-name'
    if ($safeName -eq 'README') {
        Add-Issue -Code 'reserved-prompt-name' -Path $professionPath -Message 'Prompt 名不能与 prompts/README.md 索引冲突。'
        $valid = $false
    }
    $fileName = $safeName + '.md'
    $key = $fileName.Normalize([System.Text.NormalizationForm]::FormC).ToLowerInvariant()
    if ($promptKeys.ContainsKey($key)) {
        Add-Issue -Code 'prompt-name-collision' -Path $professionPath -Message "Prompt 文件名规范化后碰撞：[$($promptKeys[$key])] 与 [$displayName]。"
        $valid = $false
    }
    else {
        $promptKeys[$key] = $displayName
    }

    if ($valid) {
        $promptPlans.Add([pscustomobject]@{
                displayName = $displayName
                safeName    = $safeName
                fileName    = $fileName
            })
    }
}

if ($PromptName.Count -eq 0) {
    Add-Issue -Code 'empty-prompt-plan' -Path $professionPath -Message '至少需要一个有明确文本证据的 Prompt 条目。'
}

$themePromptPlans = New-Object System.Collections.Generic.List[object]
$themePromptKeys = @{}
foreach ($displayName in $ThemePromptName) {
    $matches = @($promptPlans | Where-Object { $_.displayName.Equals($displayName, [System.StringComparison]::Ordinal) })
    if ($matches.Count -ne 1) {
        Add-Issue -Code 'theme-prompt-not-in-profession-plan' -Path $professionPath -Message "主题 Prompt [$displayName] 不在职业 Prompt 完整计划中。"
        continue
    }

    $prompt = $matches[0]
    $key = $prompt.fileName.Normalize([System.Text.NormalizationForm]::FormC).ToLowerInvariant()
    if ($themePromptKeys.ContainsKey($key)) {
        Add-Issue -Code 'theme-prompt-name-collision' -Path $professionPath -Message "主题 Prompt 重复：[$displayName]。"
        continue
    }
    $themePromptKeys[$key] = $true
    $themePromptPlans.Add($prompt)
}

if ([string]::IsNullOrWhiteSpace($ThemeName) -and $ThemePromptName.Count -gt 0) {
    Add-Issue -Code 'theme-prompt-without-theme' -Path $professionPath -Message '没有主题路由时不能提供主题 Prompt 计划。'
}
elseif (-not [string]::IsNullOrWhiteSpace($ThemeName) -and $ThemePromptName.Count -eq 0) {
    Add-Issue -Code 'empty-theme-prompt-plan' -Path $themePath -Message '主题导入至少需要一个有明确来源证据的主题 Prompt 条目。'
}

$lastThemeProfessionIndex = -1
foreach ($themePrompt in $themePromptPlans) {
    $professionIndex = -1
    for ($index = 0; $index -lt $promptPlans.Count; $index++) {
        if ($promptPlans[$index].fileName.Equals($themePrompt.fileName, [System.StringComparison]::OrdinalIgnoreCase)) {
            $professionIndex = $index
            break
        }
    }
    if ($professionIndex -le $lastThemeProfessionIndex) {
        Add-Issue -Code 'theme-prompt-order' -Path $themePath -Message '主题 Prompt 必须保持职业 Prompt 的相对顺序。'
        break
    }
    $lastThemeProfessionIndex = $professionIndex
}

if ($professionNameValid -and $professionPathSafe) {
    Add-Target -Path (Join-Path -Path $professionPath -ChildPath 'AGENTS.md') -BasePath $professionPath -Kind 'profession-agents' -RepoPath $repoFullPath
    Add-Target -Path (Join-Path -Path $professionPath -ChildPath 'prompts\README.md') -BasePath $professionPath -Kind 'profession-index' -RepoPath $repoFullPath
    foreach ($prompt in $promptPlans) {
        Add-Target -Path (Join-Path -Path $professionPath -ChildPath ('prompts\' + $prompt.fileName)) -BasePath $professionPath -Kind 'profession-prompt' -RepoPath $repoFullPath
    }

    if ($null -ne $themePath -and $themeNameValid) {
        Add-Target -Path (Join-Path -Path $themePath -ChildPath 'AGENTS.md') -BasePath $themePath -Kind 'theme-agents' -RepoPath $repoFullPath
        Add-Target -Path (Join-Path -Path $themePath -ChildPath 'prompts\README.md') -BasePath $themePath -Kind 'theme-index' -RepoPath $repoFullPath
        foreach ($prompt in $themePromptPlans) {
            Add-Target -Path (Join-Path -Path $themePath -ChildPath ('prompts\' + $prompt.fileName)) -BasePath $themePath -Kind 'theme-prompt' -RepoPath $repoFullPath
        }
    }
}

if ($null -ne $sourceFullPath) {
    foreach ($target in $script:Targets) {
        if ($target.path.Equals($sourceFullPath, [System.StringComparison]::OrdinalIgnoreCase)) {
            Add-Issue -Code 'source-target-overlap' -Path $sourceFullPath -Message '源文件不能同时是生成或更新目标。'
        }
    }
}

$baselineChanges = New-Object System.Collections.Generic.List[object]
try {
    $gitOutput = @(& git --literal-pathspecs -C $repoFullPath -c core.quotepath=false status --porcelain=v1 --untracked-files=all -- $professionSafeName 2>&1)
    if ($LASTEXITCODE -ne 0) {
        throw ($gitOutput -join "`n")
    }
    foreach ($line in $gitOutput) {
        $textLine = [string]$line
        if ($textLine.Length -lt 4) {
            continue
        }
        $statusCode = $textLine.Substring(0, 2)
        $pathText = $textLine.Substring(3).Trim()
        $changedPaths = if ($pathText.Contains(' -> ')) { @($pathText.Split(@(' -> '), [System.StringSplitOptions]::None)) } else { @($pathText) }
        foreach ($changedPath in $changedPaths) {
            $relativeChangedPath = $changedPath.Replace('\', '/').Trim()
            $fullChangedPath = [System.IO.Path]::GetFullPath((Join-Path -Path $repoFullPath -ChildPath $relativeChangedPath))
            $exists = Test-Path -LiteralPath $fullChangedPath -PathType Leaf
            if ($exists -and -not (Test-ReparsePointChain -Path $fullChangedPath -RootPath $repoFullPath -Code 'baseline-reparse-point')) {
                $exists = $false
            }
            $sha256 = if ($exists) { (Get-FileHash -LiteralPath $fullChangedPath -Algorithm SHA256).Hash } else { $null }
            $baselineChanges.Add([pscustomobject]@{
                    status       = $statusCode
                    relativePath = $relativeChangedPath
                    exists       = $exists
                    sha256       = $sha256
                })
        }
    }
}
catch {
    Add-Issue -Code 'git-baseline' -Path $professionPath -Message '无法读取职业目录的初始 git 状态；写入前必须解决。'
}

$result = [ordered]@{
    schemaVersion   = 1
    status          = if ($script:Errors.Count -eq 0) { 'passed' } else { 'failed' }
    source          = $sourceSummary
    route           = [ordered]@{
        profession     = $professionSafeName
        professionPath = $professionPath
        theme          = $themeSafeName
        themePath      = $themePath
    }
    prompts         = @($promptPlans.ToArray())
    themePrompts    = @($themePromptPlans.ToArray())
    targets         = @($script:Targets.ToArray())
    baselineChanges = @($baselineChanges.ToArray())
    errors          = @($script:Errors.ToArray())
    warnings        = @($script:Warnings.ToArray())
}

$result | ConvertTo-Json -Depth 8
if ($script:Errors.Count -gt 0) {
    exit 1
}

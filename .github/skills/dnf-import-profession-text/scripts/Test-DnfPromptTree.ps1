[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)]
    [string]$ProfessionPath,

    [string]$ThemePath,

    [string]$SourcePath,

    [string]$ExpectedSourceSha256,

    [AllowEmptyCollection()]
    [string[]]$ExpectedPromptFileName = @(),

    [AllowEmptyCollection()]
    [string[]]$AllowedChangedRelativePath = @(),

    [AllowEmptyCollection()]
    [object[]]$BaselineChange = @(),

    [string]$RepoRoot
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
$OutputEncoding = [Console]::OutputEncoding = New-Object System.Text.UTF8Encoding($false)
$script:Errors = New-Object System.Collections.Generic.List[object]
$script:Warnings = New-Object System.Collections.Generic.List[object]
$script:CheckedFiles = New-Object System.Collections.Generic.List[string]
$script:TextCache = @{}
$script:RepoRootPath = $null

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

function Add-Issue {
    param(
        [Parameter(Mandatory = $true)][string]$Code,
        [Parameter(Mandatory = $true)][string]$Path,
        [Parameter(Mandatory = $true)][string]$Message,
        [switch]$Warning
    )

    $issue = [pscustomobject]@{
        code = $Code
        path = $Path
        message = $Message
    }

    if ($Warning) {
        $script:Warnings.Add($issue)
    }
    else {
        $script:Errors.Add($issue)
    }
}

function Test-ReparsePointChain {
    param(
        [Parameter(Mandatory = $true)][string]$Path,
        [Parameter(Mandatory = $true)][string]$RootPath,
        [Parameter(Mandatory = $true)][string]$Code
    )

    $root = (Get-Item -LiteralPath $RootPath -Force).FullName.TrimEnd([System.IO.Path]::DirectorySeparatorChar, [System.IO.Path]::AltDirectorySeparatorChar)
    $rootPrefix = $root + [System.IO.Path]::DirectorySeparatorChar
    $current = Get-Item -LiteralPath $Path -Force

    while ($null -ne $current) {
        if (($current.Attributes -band [System.IO.FileAttributes]::ReparsePoint) -ne 0) {
            Add-Issue -Code $Code -Path $current.FullName -Message '路径链不能包含符号链接或重解析点。'
            return $false
        }

        if ($current.FullName.Equals($root, [System.StringComparison]::OrdinalIgnoreCase)) {
            return $true
        }

        $parent = if ($current -is [System.IO.DirectoryInfo]) { $current.Parent } else { $current.Directory }
        if ($null -eq $parent -or (-not $parent.FullName.Equals($root, [System.StringComparison]::OrdinalIgnoreCase) -and -not $parent.FullName.StartsWith($rootPrefix, [System.StringComparison]::OrdinalIgnoreCase))) {
            Add-Issue -Code $Code -Path $Path -Message '路径链越出仓库根。'
            return $false
        }
        $current = $parent
    }

    return $false
}

function Get-Utf8Text {
    param([Parameter(Mandatory = $true)][string]$Path)

    if ($script:TextCache.ContainsKey($Path)) {
        return $script:TextCache[$Path]
    }

    if ($null -ne $script:RepoRootPath) {
        $rootPrefix = $script:RepoRootPath.TrimEnd([System.IO.Path]::DirectorySeparatorChar, [System.IO.Path]::AltDirectorySeparatorChar) + [System.IO.Path]::DirectorySeparatorChar
        $fullPath = [System.IO.Path]::GetFullPath($Path)
        if (-not $fullPath.StartsWith($rootPrefix, [System.StringComparison]::OrdinalIgnoreCase)) {
            Add-Issue -Code 'file-route' -Path $fullPath -Message '待读文件越出仓库根。'
            return $null
        }
        if (-not (Test-ReparsePointChain -Path $fullPath -RootPath $script:RepoRootPath -Code 'file-reparse-point')) {
            return $null
        }
    }

    try {
        $bytes = [System.IO.File]::ReadAllBytes($Path)
        $decoder = New-Object System.Text.UTF8Encoding($false, $true)
        $text = $decoder.GetString($bytes)
        if ($text.Length -gt 0 -and $text[0] -eq [char]0xFEFF) {
            $text = $text.Substring(1)
        }
        $script:CheckedFiles.Add($Path)
        if ([string]::IsNullOrWhiteSpace($text)) {
            Add-Issue -Code 'empty-file' -Path $Path -Message '文件为空或只包含空白。'
            return $null
        }
        $script:TextCache[$Path] = $text
        return $text
    }
    catch {
        Add-Issue -Code 'invalid-utf8' -Path $Path -Message '文件不存在、不可读或不是有效 UTF-8。'
        return $null
    }
}

function Get-HeadFileText {
    param([Parameter(Mandatory = $true)][string]$Path)

    if ($null -eq $script:RepoRootPath) {
        return ''
    }
    $rootPrefix = $script:RepoRootPath.TrimEnd([System.IO.Path]::DirectorySeparatorChar, [System.IO.Path]::AltDirectorySeparatorChar) + [System.IO.Path]::DirectorySeparatorChar
    $fullPath = [System.IO.Path]::GetFullPath($Path)
    if (-not $fullPath.StartsWith($rootPrefix, [System.StringComparison]::OrdinalIgnoreCase)) {
        return ''
    }

    $relativePath = $fullPath.Substring($rootPrefix.Length).Replace('\', '/')
    $objectSpec = 'HEAD:' + $relativePath
    $previousErrorActionPreference = $ErrorActionPreference
    $ErrorActionPreference = 'SilentlyContinue'
    try {
        $blobId = @(& git -C $script:RepoRootPath rev-parse --verify $objectSpec 2>$null)
        $revisionExitCode = $LASTEXITCODE
    }
    finally {
        $ErrorActionPreference = $previousErrorActionPreference
    }
    if ($revisionExitCode -ne 0 -or $blobId.Count -ne 1) {
        return ''
    }

    $previousErrorActionPreference = $ErrorActionPreference
    $ErrorActionPreference = 'SilentlyContinue'
    try {
        $content = @(& git -C $script:RepoRootPath cat-file blob $blobId[0] 2>$null)
        $catFileExitCode = $LASTEXITCODE
    }
    finally {
        $ErrorActionPreference = $previousErrorActionPreference
    }
    if ($catFileExitCode -ne 0) {
        return ''
    }
    return ($content -join "`n")
}

function Get-NormalizedIndexHeading {
    param([Parameter(Mandatory = $true)][string]$Heading)

    return (($Heading -replace '^\s*[一二三四五六七八九十百0-9]+[、.．]\s*', '') -replace '\s+#+\s*$', '').Trim()
}

function Get-MarkdownHeadings {
    param([Parameter(Mandatory = $true)][AllowEmptyString()][string]$Text)

    $items = New-Object System.Collections.Generic.List[object]
    $lines = [System.Text.RegularExpressions.Regex]::Split($Text, "\r\n|\n|\r")
    $activeFence = $null

    for ($index = 0; $index -lt $lines.Count; $index++) {
        $line = $lines[$index]
        if ($null -ne $activeFence) {
            $fenceCharacter = [System.Text.RegularExpressions.Regex]::Escape($activeFence.Substring(0, 1))
            $closePattern = '^[ ]{0,3}' + $fenceCharacter + '{' + $activeFence.Length + ',}[ \t]*$'
            if ($line -match $closePattern) {
                $activeFence = $null
            }
            continue
        }

        if ($line -match '^[ ]{0,3}(?<fence>`{3,}|~{3,})(?<info>.*)$') {
            $activeFence = $Matches['fence']
            continue
        }

        if ($line -match '^(?<marks>#{1,6})[ \t]+(?<title>.+?)\s*$') {
            $title = ($Matches['title'] -replace '\s+#+\s*$', '').Trim()
            $items.Add([pscustomobject]@{
                line = $index + 1
                level = $Matches['marks'].Length
                title = $title
            })
        }
    }

    return @($items.ToArray())
}

function Get-LevelTwoHeadings {
    param([Parameter(Mandatory = $true)][AllowEmptyString()][string]$Text)

    return @(Get-MarkdownHeadings -Text $Text | Where-Object { $_.level -eq 2 } | ForEach-Object { Get-NormalizedIndexHeading -Heading $_.title })
}

function Get-LevelTwoSection {
    param(
        [Parameter(Mandatory = $true)][AllowEmptyString()][string]$Text,
        [Parameter(Mandatory = $true)][string]$Name
    )

    $lines = [System.Text.RegularExpressions.Regex]::Split($Text, "\r\n|\n|\r")
    $capturing = $false
    $content = New-Object System.Collections.Generic.List[string]
    $activeFence = $null

    foreach ($line in $lines) {
        if ($null -ne $activeFence) {
            if ($capturing) {
                $content.Add($line)
            }
            $fenceCharacter = [System.Text.RegularExpressions.Regex]::Escape($activeFence.Substring(0, 1))
            $closePattern = '^[ ]{0,3}' + $fenceCharacter + '{' + $activeFence.Length + ',}[ \t]*$'
            if ($line -match $closePattern) {
                $activeFence = $null
            }
            continue
        }

        if ($line -match '^[ ]{0,3}(?<fence>`{3,}|~{3,})(?<info>.*)$') {
            $activeFence = $Matches['fence']
            if ($capturing) {
                $content.Add($line)
            }
            continue
        }

        if ($line -match '^##[ \t]+(?<title>.+?)\s*$') {
            $heading = Get-NormalizedIndexHeading -Heading $Matches['title']
            if ($capturing) {
                break
            }
            if ($heading -eq $Name) {
                $capturing = $true
            }
            continue
        }

        if ($capturing) {
            $content.Add($line)
        }
    }

    if (-not $capturing) {
        return $null
    }

    return [string]::Join("`n", $content.ToArray()).Trim()
}

function Test-HeadingOrder {
    param(
        [Parameter(Mandatory = $true)][string]$Path,
        [Parameter(Mandatory = $true)][AllowEmptyString()][string]$Text,
        [Parameter(Mandatory = $true)][string[]]$Expected
    )

    $actual = @(Get-LevelTwoHeadings -Text $Text)
    if ($actual.Count -ne $Expected.Count) {
        Add-Issue -Code 'heading-count' -Path $Path -Message "二级章节应为 $($Expected.Count) 个，实际为 $($actual.Count)：$($actual -join ' / ')"
        return
    }

    for ($index = 0; $index -lt $Expected.Count; $index++) {
        if ($actual[$index] -ne $Expected[$index]) {
            Add-Issue -Code 'heading-order' -Path $Path -Message "第 $($index + 1) 个二级章节应为 [$($Expected[$index])]，实际为 [$($actual[$index])]。"
        }
    }
}

function Test-HasTitle {
    param(
        [Parameter(Mandatory = $true)][string]$Path,
        [Parameter(Mandatory = $true)][AllowEmptyString()][string]$Text
    )

    $titles = @(Get-MarkdownHeadings -Text $Text | Where-Object { $_.level -eq 1 })
    if ($titles.Count -eq 0) {
        Add-Issue -Code 'missing-title' -Path $Path -Message '缺少非空一级标题。'
    }
    elseif ($titles.Count -gt 1) {
        Add-Issue -Code 'multiple-titles' -Path $Path -Message '只能有一个一级标题。'
    }
}

function Get-SingleTitleText {
    param([Parameter(Mandatory = $true)][AllowEmptyString()][string]$Text)

    $titles = @(Get-MarkdownHeadings -Text $Text | Where-Object { $_.level -eq 1 })
    if ($titles.Count -eq 1) {
        return $titles[0].title
    }
    return $null
}

function Convert-ToSafeFileStem {
    param([Parameter(Mandatory = $true)][string]$Value)

    $result = ($Value -replace '\s+', ' ').Trim()
    $result = $result.Replace(':', '：').Replace('/', '／').Replace('\', '／')
    $result = $result.Replace('*', '＊').Replace('?', '？').Replace('"', '＂')
    $result = $result.Replace('<', '＜').Replace('>', '＞').Replace('|', '｜')
    return $result.TrimEnd([char[]]@(' ', '.')).Normalize([System.Text.NormalizationForm]::FormC)
}

function Test-RequiredHeadingGroups {
    param(
        [Parameter(Mandatory = $true)][string]$Path,
        [Parameter(Mandatory = $true)][AllowEmptyString()][string]$Text,
        [Parameter(Mandatory = $true)][object[]]$Groups
    )

    $headings = @(Get-LevelTwoHeadings -Text $Text)
    foreach ($group in $Groups) {
        $matchedHeading = $headings | Where-Object { $_ -match $group.Pattern } | Select-Object -First 1
        if ($null -eq $matchedHeading) {
            Add-Issue -Code $group.Code -Path $Path -Message "缺少非空的 [$($group.Label)] 规则章节。"
            continue
        }

        $section = Get-LevelTwoSection -Text $Text -Name $matchedHeading
        if ([string]::IsNullOrWhiteSpace($section)) {
            Add-Issue -Code $group.Code -Path $Path -Message "[$matchedHeading] 规则章节不能为空。"
        }
    }
}

function Test-Sequence {
    param(
        [Parameter()][AllowEmptyCollection()][string[]]$Actual = @(),
        [Parameter()][AllowEmptyCollection()][string[]]$Expected = @(),
        [Parameter(Mandatory = $true)][string]$Path,
        [Parameter(Mandatory = $true)][string]$Code,
        [Parameter(Mandatory = $true)][string]$Label
    )

    if ($Actual.Count -ne $Expected.Count) {
        Add-Issue -Code $Code -Path $Path -Message "$Label 数量或顺序不一致。期望：$($Expected -join '、')；实际：$($Actual -join '、')"
        return
    }

    for ($index = 0; $index -lt $Expected.Count; $index++) {
        if (-not $Actual[$index].Equals($Expected[$index], [System.StringComparison]::OrdinalIgnoreCase)) {
            Add-Issue -Code $Code -Path $Path -Message "$Label 第 $($index + 1) 项应为 [$($Expected[$index])]，实际为 [$($Actual[$index])]。"
            return
        }
    }
}

function Test-PromptFence {
    param(
        [Parameter(Mandatory = $true)][string]$Path,
        [Parameter(Mandatory = $true)][AllowEmptyString()][string]$Text,
        [Parameter(Mandatory = $true)][string]$SectionName
    )

    $section = Get-LevelTwoSection -Text $Text -Name $SectionName
    if ($null -eq $section) {
        Add-Issue -Code 'missing-text-fence' -Path $Path -Message "[$SectionName] 必须包含非空的 ```text 围栏代码块。"
        return
    }

    $lines = [System.Text.RegularExpressions.Regex]::Split($section.Trim(), "\r\n|\n|\r")
    if ($lines.Count -lt 3 -or $lines[0] -notmatch '^[ ]{0,3}(?<fence>`{3,})text[ \t]*$') {
        Add-Issue -Code 'invalid-text-fence' -Path $Path -Message "[$SectionName] 必须只包含一个 ```text 围栏代码块。"
        return
    }

    $marker = $Matches['fence']
    $closePattern = '^[ ]{0,3}`{' + $marker.Length + ',}[ \t]*$'
    if ($lines[$lines.Count - 1] -notmatch $closePattern) {
        Add-Issue -Code 'invalid-text-fence' -Path $Path -Message "[$SectionName] 的围栏代码块没有合法闭合。"
        return
    }

    $body = [string]::Join("`n", $lines[1..($lines.Count - 2)])
    if ([string]::IsNullOrWhiteSpace($body)) {
        Add-Issue -Code 'empty-prompt-fence' -Path $Path -Message "[$SectionName] 的 Prompt 代码块为空。"
    }
    elseif ($body -notmatch '[A-Za-z]' -or $body -match '[\u3400-\u9fff]') {
        Add-Issue -Code 'prompt-language' -Path $Path -Message "[$SectionName] 的代码块必须是可直接组合的英文 Prompt。"
    }
}

function Test-ForbiddenContent {
    param(
        [Parameter(Mandatory = $true)][string]$Path,
        [Parameter(Mandatory = $true)][AllowEmptyString()][string]$Text,
        [switch]$CheckResourceAuthority,
        [AllowEmptyString()][string]$ResourceAuthorityText = '',
        [AllowEmptyString()][string]$ExistingRuleText = ''
    )

    $checks = @(
        @{ Code = 'absolute-path'; Pattern = '(?m)\b[A-Za-z]:[\\/][^\r\n]+|(?<!\\)\\\\(?:\?\\|[^\\\s]+\\[^\\\s]+)[^\r\n]*'; Message = '生成规则或 Prompt 中不能保存机器绝对路径、UNC 路径或设备路径。' },
        @{ Code = 'format-downgrade'; Pattern = '(?is)\bver\s*5\b.{0,30}(转|转换|降级).{0,20}\bver\s*2\b'; Message = '发现 Ver5 转 Ver2 的格式降级指令。' },
        @{ Code = 'unsafe-claim'; Pattern = '(?i)TP\s*安全|绝对安全|零风险|不会.{0,8}(封号|被封)|不会.{0,12}(触发|遭遇).{0,12}(反作弊|检测)|兼容所有客户端|所有客户端.{0,8}兼容|(?:规避|绕过).{0,12}(检测|反作弊)|保证.{0,16}(安全|防封|不封号)'; Message = '发现客户端兼容、检测规避或账号安全声明。' },
        @{ Code = 'deployment-step'; Pattern = '(?i)(丢入|复制到|放入|写入|移动到|安装到|拖入|部署到|部署至).{0,24}ImagePacks2'; Message = '文本导入产物不能包含部署步骤。' },
        @{ Code = 'coverage-claim'; Pattern = '(?i)(已完成|已实现|已证明).{0,12}全技能|全技能.{0,8}(完整|全部|100\s*%).{0,8}覆盖|(?:完整|全部|100\s*%).{0,8}覆盖.{0,8}全技能|全技能已完成|全技能.{0,8}已覆盖|已覆盖.{0,8}全技能|fullSkillCoverageProven\s*[:=]\s*true'; Message = '发现未经 manifest 证明的全技能覆盖声明。' }
    )

    foreach ($check in $checks) {
        if ($Text -match $check.Pattern) {
            Add-Issue -Code $check.Code -Path $Path -Message $check.Message
        }
    }

    $resourcePatterns = @(
        @{ Code = 'npk-mapping'; Pattern = '(?i)(?<value>[\p{L}\p{N}_%!.#$^@（）·/\\-][\p{L}\p{N}_%!.#$^@()（）·/\\-]*\.npk)\b'; Label = 'NPK' },
        @{ Code = 'img-mapping'; Pattern = '(?i)(?<value>[\p{L}\p{N}_%!.#$^@（）·/\\-][\p{L}\p{N}_%!.#$^@()（）·/\\-]*\.img)\b'; Label = 'IMG' }
    )

    foreach ($resourcePattern in $resourcePatterns) {
        $authorityFullTokens = @{}
        $authorityBaseCounts = @{}
        foreach ($authorityMatch in [System.Text.RegularExpressions.Regex]::Matches($ResourceAuthorityText, $resourcePattern.Pattern)) {
            $authorityResource = $authorityMatch.Groups['value'].Value.Replace('\', '/').TrimStart('.', '/')
            $authorityKey = $authorityResource.Normalize([System.Text.NormalizationForm]::FormC).ToLowerInvariant()
            $authorityFullTokens[$authorityKey] = $true
            $authorityBase = [System.IO.Path]::GetFileName($authorityResource).Normalize([System.Text.NormalizationForm]::FormC).ToLowerInvariant()
            if ($authorityBaseCounts.ContainsKey($authorityBase)) {
                $authorityBaseCounts[$authorityBase]++
            }
            else {
                $authorityBaseCounts[$authorityBase] = 1
            }
        }

        $existingRuleTokens = @{}
        foreach ($existingMatch in [System.Text.RegularExpressions.Regex]::Matches($ExistingRuleText, $resourcePattern.Pattern)) {
            $existingResource = $existingMatch.Groups['value'].Value.Replace('\', '/').TrimStart('.', '/')
            $existingKey = $existingResource.Normalize([System.Text.NormalizationForm]::FormC).ToLowerInvariant()
            $existingRuleTokens[$existingKey] = $true
        }

        $seenResources = @{}
        foreach ($match in [System.Text.RegularExpressions.Regex]::Matches($Text, $resourcePattern.Pattern)) {
            $resource = $match.Groups['value'].Value.TrimStart('.', '/')
            $normalizedResource = $resource.Replace('\', '/').Normalize([System.Text.NormalizationForm]::FormC)
            $key = $normalizedResource.ToLowerInvariant()
            if ($seenResources.ContainsKey($key)) {
                continue
            }
            $seenResources[$key] = $true

            if (-not $CheckResourceAuthority) {
                Add-Issue -Code $resourcePattern.Code -Path $Path -Message "Prompt 树中发现具体 $($resourcePattern.Label) 引用 [$resource]；资源事实只能进入经核验的 manifest 或规则。"
            }
            else {
                $resourceBase = [System.IO.Path]::GetFileName($normalizedResource).ToLowerInvariant()
                $manifestAuthorized = $authorityFullTokens.ContainsKey($key) -or ((-not $normalizedResource.Contains('/')) -and $authorityBaseCounts.ContainsKey($resourceBase) -and $authorityBaseCounts[$resourceBase] -eq 1)
                $existingRuleAuthorized = $existingRuleTokens.ContainsKey($key)
                if (-not $manifestAuthorized -and -not $existingRuleAuthorized) {
                    Add-Issue -Code 'unverified-resource-reference' -Path $Path -Message "规则中具体 $($resourcePattern.Label) 引用 [$resource] 未在 manifest 或 HEAD 既有规则中找到。"
                }
            }
        }
    }

    $conceptPattern = '(?i)512\s*[x×]\s*512|transparent background|no character|no background|centered composition|透明背景|无角色|无背景|(?:强制)?居中'
    foreach ($conceptMatch in [System.Text.RegularExpressions.Regex]::Matches($Text, $conceptPattern)) {
        $conceptValue = $conceptMatch.Value
        $contextStart = [System.Math]::Max(0, $conceptMatch.Index - 180)
        $contextLength = [System.Math]::Min($Text.Length - $contextStart, $conceptMatch.Length + 360)
        $context = $Text.Substring($contextStart, $contextLength)
        $hasConditionalContext = $context -match '(?is)概念.{0,100}(适用|选择|建议|画布|条件)|只.{0,60}概念|不是.{0,60}硬规则|不得.{0,50}(统一|强制)|不(?:把|将|使用).{0,70}(设为|作为|删除|排除)|排除.{0,30}(重新)?居中|按源帧|源资源|仅在.{0,60}(分类|确认|适用)'
        if (-not $hasConditionalContext) {
            Add-Issue -Code 'conditional-concept-rule' -Path $Path -Message "[$($conceptValue)] 必须明确限制为有适用条件的概念图建议。" -Warning
            break
        }
    }
}

function Test-SafeFileNames {
    param(
        [Parameter()][AllowEmptyCollection()][System.IO.FileInfo[]]$Files = @(),
        [Parameter(Mandatory = $true)][string]$ScopePath
    )

    $seen = @{}
    $reservedPattern = '^(CON|PRN|AUX|NUL|COM[1-9]|LPT[1-9])$'
    $invalidCharacters = [System.IO.Path]::GetInvalidFileNameChars()

    foreach ($file in $Files) {
        if ($file.BaseName -match $reservedPattern) {
            Add-Issue -Code 'reserved-file-name' -Path $file.FullName -Message '文件名是 Windows 设备保留名。'
        }
        if ($file.Name.IndexOfAny($invalidCharacters) -ge 0 -or $file.Name.EndsWith(' ') -or $file.Name.EndsWith('.')) {
            Add-Issue -Code 'invalid-file-name' -Path $file.FullName -Message '文件名含 Windows 非法字符或尾随空格/句点。'
        }

        $key = $file.Name.Normalize([System.Text.NormalizationForm]::FormC).ToLowerInvariant()
        if ($seen.ContainsKey($key)) {
            Add-Issue -Code 'file-name-collision' -Path $ScopePath -Message "文件名规范化后碰撞：$($seen[$key]) 与 $($file.Name)"
        }
        else {
            $seen[$key] = $file.Name
        }
    }
}

function Test-Index {
    param(
        [Parameter(Mandatory = $true)][string]$IndexPath,
        [Parameter()][AllowEmptyCollection()][System.IO.FileInfo[]]$PromptFiles = @()
    )

    if (-not (Test-Path -LiteralPath $IndexPath -PathType Leaf)) {
        Add-Issue -Code 'missing-index' -Path $IndexPath -Message '缺少 prompts/README.md。'
        return
    }

    $text = Get-Utf8Text -Path $IndexPath
    if ($null -eq $text) {
        return
    }

    Test-HasTitle -Path $IndexPath -Text $text
    Test-HeadingOrder -Path $IndexPath -Text $text -Expected @('职责', '加载顺序', '稳定结构', '当前文件', '覆盖状态')
    Test-ForbiddenContent -Path $IndexPath -Text $text

    $section = Get-LevelTwoSection -Text $text -Name '当前文件'
    if ($null -eq $section) {
        return
    }

    $listed = New-Object System.Collections.Generic.List[string]
    $sectionLines = [System.Text.RegularExpressions.Regex]::Split($section, "\r\n|\n|\r")
    foreach ($line in $sectionLines) {
        if ([string]::IsNullOrWhiteSpace($line)) {
            continue
        }

        $entry = $null
        if ($line -match '^\s*[-*+]\s+`(?<path>[^`]+\.md)`\s*$') {
            $entry = $Matches['path']
        }
        elseif ($line -match '^\s*[-*+]\s+\[[^\]]+\]\((?<path>[^)]+\.md)\)\s*$') {
            $entry = $Matches['path']
        }
        elseif ($line -match '(?i)\.md') {
            Add-Issue -Code 'invalid-index-entry' -Path $IndexPath -Message "当前文件中的条目必须是直接子文件代码项或 Markdown 链接：$line"
        }

        if ($null -ne $entry) {
            $normalizedEntry = $entry.Replace('\', '/')
            if ($normalizedEntry.Contains('/') -or [System.IO.Path]::GetFileName($normalizedEntry) -ne $normalizedEntry) {
                Add-Issue -Code 'invalid-index-path' -Path $IndexPath -Message "当前文件只能列直接子文件，不能包含目录：$entry"
            }
            else {
                $listed.Add($normalizedEntry)
            }
        }
    }

    $actualNames = @($PromptFiles | ForEach-Object { $_.Name })
    $listedNames = @($listed.ToArray())
    $missing = @($actualNames | Where-Object { $_ -notin $listedNames })
    $stale = @($listedNames | Where-Object { $_ -notin $actualNames })
    $duplicates = @($listedNames | Group-Object | Where-Object { $_.Count -gt 1 } | ForEach-Object { $_.Name })

    if ($missing.Count -gt 0) {
        Add-Issue -Code 'index-missing-files' -Path $IndexPath -Message "当前文件未列出：$($missing -join '、')"
    }
    if ($stale.Count -gt 0) {
        Add-Issue -Code 'index-stale-files' -Path $IndexPath -Message "当前文件列出不存在的文件：$($stale -join '、')"
    }
    if ($duplicates.Count -gt 0) {
        Add-Issue -Code 'index-duplicates' -Path $IndexPath -Message "当前文件重复列出：$($duplicates -join '、')"
    }

    return @($listedNames)
}

function Test-ProfessionPrompt {
    param([Parameter(Mandatory = $true)][System.IO.FileInfo]$File)

    $text = Get-Utf8Text -Path $File.FullName
    if ($null -eq $text) {
        return
    }

    Test-HasTitle -Path $File.FullName -Text $text
    Test-HeadingOrder -Path $File.FullName -Text $text -Expected @('职业稳定语义', '职业通用 Prompt', '源资源约束', '阶段验收')
    Test-PromptFence -Path $File.FullName -Text $text -SectionName '职业通用 Prompt'
    Test-ForbiddenContent -Path $File.FullName -Text $text

    $title = Get-SingleTitleText -Text $text
    if ($null -ne $title) {
        $expectedName = (Convert-ToSafeFileStem -Value $title) + '.md'
        if (-not $File.Name.Equals($expectedName, [System.StringComparison]::OrdinalIgnoreCase)) {
            Add-Issue -Code 'profession-title-file-name' -Path $File.FullName -Message "职业 Prompt 一级标题规范化后应对应文件名 [$expectedName]。"
        }
    }
}

function Test-ThemePrompt {
    param(
        [Parameter(Mandatory = $true)][System.IO.FileInfo]$File,
        [Parameter(Mandatory = $true)][string]$ProfessionPromptsPath,
        [Parameter(Mandatory = $true)][string]$ThemeName
    )

    $text = Get-Utf8Text -Path $File.FullName
    if ($null -eq $text) {
        return
    }

    Test-HasTitle -Path $File.FullName -Text $text
    Test-HeadingOrder -Path $File.FullName -Text $text -Expected @('职业基础', '主题增量 Prompt', '具体变化', '主题验收', '主题排除')
    Test-PromptFence -Path $File.FullName -Text $text -SectionName '主题增量 Prompt'
    Test-ForbiddenContent -Path $File.FullName -Text $text

    $professionPromptPath = Join-Path -Path $ProfessionPromptsPath -ChildPath $File.Name
    if (-not (Test-Path -LiteralPath $professionPromptPath -PathType Leaf)) {
        Add-Issue -Code 'missing-profession-prompt' -Path $File.FullName -Message "缺少同名职业 Prompt：$professionPromptPath"
    }
    else {
        $professionText = Get-Utf8Text -Path $professionPromptPath
        $professionTitle = if ($null -ne $professionText) { Get-SingleTitleText -Text $professionText } else { $null }
        $themeTitle = Get-SingleTitleText -Text $text
        $expectedThemeTitle = if ($null -ne $professionTitle) { $professionTitle + ' - ' + $ThemeName } else { $null }
        if ($null -ne $expectedThemeTitle -and $null -ne $themeTitle -and -not $themeTitle.Equals($expectedThemeTitle, [System.StringComparison]::Ordinal)) {
            Add-Issue -Code 'theme-title' -Path $File.FullName -Message "主题 Prompt 一级标题必须是 [$expectedThemeTitle]。"
        }
    }

    $professionSection = Get-LevelTwoSection -Text $text -Name '职业基础'
    $expectedReference = '../../prompts/' + $File.Name
    if ($null -eq $professionSection -or $professionSection.Replace('\', '/') -notmatch [System.Text.RegularExpressions.Regex]::Escape($expectedReference)) {
        Add-Issue -Code 'profession-reference' -Path $File.FullName -Message "职业基础必须引用 $expectedReference"
    }
}

if ([string]::IsNullOrWhiteSpace($RepoRoot)) {
    $RepoRoot = Join-Path -Path $PSScriptRoot -ChildPath '..\..\..\..'
}

$repoFullPath = (Get-Item -LiteralPath (Resolve-FullPath -Path $RepoRoot) -Force).FullName.TrimEnd([System.IO.Path]::DirectorySeparatorChar, [System.IO.Path]::AltDirectorySeparatorChar)
$script:RepoRootPath = $repoFullPath
$repoPrefix = $repoFullPath + [System.IO.Path]::DirectorySeparatorChar
$professionFullPath = Resolve-FullPath -Path $ProfessionPath

if (-not $professionFullPath.StartsWith($repoPrefix, [System.StringComparison]::OrdinalIgnoreCase)) {
    throw "职业目录必须位于当前仓库内：$professionFullPath"
}
if (-not (Test-Path -LiteralPath $professionFullPath -PathType Container)) {
    throw "职业目录不存在：$professionFullPath"
}

$professionItem = Get-Item -LiteralPath $professionFullPath -Force
$professionPathSafe = Test-ReparsePointChain -Path $professionFullPath -RootPath $repoFullPath -Code 'profession-reparse-point'

$professionRelative = $professionFullPath.Substring($repoPrefix.Length).Replace('\', '/')
if ($professionRelative.Contains('/')) {
    Add-Issue -Code 'profession-route' -Path $professionFullPath -Message '职业目录必须是仓库根的直属子目录。'
}
if ($professionRelative -in @('.codex', '.git', 'docs', 'tools')) {
    Add-Issue -Code 'reserved-profession-route' -Path $professionFullPath -Message '基础设施目录不能作为职业目录。'
}

$manifestAuthorityText = ''
$manifestPath = Join-Path -Path $professionFullPath -ChildPath 'manifest.json'
if ($professionPathSafe -and (Test-Path -LiteralPath $manifestPath -PathType Leaf)) {
    $manifestAuthorityText = Get-Utf8Text -Path $manifestPath
    if ($null -ne $manifestAuthorityText) {
        try {
            $null = $manifestAuthorityText | ConvertFrom-Json
        }
        catch {
            Add-Issue -Code 'invalid-manifest-json' -Path $manifestPath -Message '现有 manifest.json 不是有效 JSON，不能作为资源引用依据。'
            $manifestAuthorityText = ''
        }
    }
    else {
        $manifestAuthorityText = ''
    }
}

$professionAgentsPath = Join-Path -Path $professionFullPath -ChildPath 'AGENTS.md'
if (-not $professionPathSafe) {
    # 重解析点错误已说明停止读取职业树的原因。
}
elseif (-not (Test-Path -LiteralPath $professionAgentsPath -PathType Leaf)) {
    Add-Issue -Code 'missing-profession-agents' -Path $professionAgentsPath -Message '缺少职业 AGENTS.md。'
}
else {
    $professionAgentsText = Get-Utf8Text -Path $professionAgentsPath
    if ($null -ne $professionAgentsText) {
        $professionExistingRuleText = Get-HeadFileText -Path $professionAgentsPath
        Test-HasTitle -Path $professionAgentsPath -Text $professionAgentsText
        Test-RequiredHeadingGroups -Path $professionAgentsPath -Text $professionAgentsText -Groups @(
            @{ Code = 'profession-boundary-section'; Pattern = '职责|职业.*边界'; Label = '职责边界' },
            @{ Code = 'profession-fact-section'; Pattern = '资源.*事实|事实.*源'; Label = '资源事实源' },
            @{ Code = 'profession-prompt-section'; Pattern = 'Prompt.*分层|提示词.*分层'; Label = 'Prompt 分层' },
            @{ Code = 'profession-layer-section'; Pattern = '人物|特效|武器|Cut-in'; Label = '人物/特效/武器/Cut-in 边界' },
            @{ Code = 'profession-acceptance-section'; Pattern = '验收|回归'; Label = '职业验收' },
            @{ Code = 'profession-coverage-section'; Pattern = '覆盖|全技能'; Label = '覆盖状态' }
        )
        Test-ForbiddenContent -Path $professionAgentsPath -Text $professionAgentsText -CheckResourceAuthority -ResourceAuthorityText $manifestAuthorityText -ExistingRuleText $professionExistingRuleText
    }
}

$professionPromptsPath = Join-Path -Path $professionFullPath -ChildPath 'prompts'
$professionPromptFiles = @()
$professionIndexNames = @()
if (-not $professionPathSafe) {
    # 不遍历不安全的职业路径。
}
elseif (-not (Test-Path -LiteralPath $professionPromptsPath -PathType Container)) {
    Add-Issue -Code 'missing-profession-prompts' -Path $professionPromptsPath -Message '缺少职业 prompts 目录。'
}
else {
    $professionPromptsItem = Get-Item -LiteralPath $professionPromptsPath -Force
    if (Test-ReparsePointChain -Path $professionPromptsPath -RootPath $repoFullPath -Code 'profession-prompts-reparse-point') {
        $professionPromptFiles = @(Get-ChildItem -LiteralPath $professionPromptsPath -File -Filter '*.md' | Where-Object { $_.Name -ne 'README.md' } | Sort-Object Name)
        if ($professionPromptFiles.Count -eq 0) {
            Add-Issue -Code 'empty-profession-prompts' -Path $professionPromptsPath -Message '职业 prompts 目录没有逐技能 Prompt。'
        }
        Test-SafeFileNames -Files $professionPromptFiles -ScopePath $professionPromptsPath
        $professionIndexNames = @(Test-Index -IndexPath (Join-Path -Path $professionPromptsPath -ChildPath 'README.md') -PromptFiles $professionPromptFiles)
        foreach ($file in $professionPromptFiles) {
            Test-ProfessionPrompt -File $file
        }
    }
}

if ($ExpectedPromptFileName.Count -gt 0) {
    Test-Sequence -Actual $professionIndexNames -Expected $ExpectedPromptFileName -Path $professionPromptsPath -Code 'profession-source-order' -Label '职业 Prompt 索引'
}

$themeFullPath = $null
$themePromptFiles = @()
$themeIndexNames = @()
if (-not [string]::IsNullOrWhiteSpace($ThemePath)) {
    $themeFullPath = Resolve-FullPath -Path $ThemePath
    $themePrefix = $professionFullPath.TrimEnd([System.IO.Path]::DirectorySeparatorChar, [System.IO.Path]::AltDirectorySeparatorChar) + [System.IO.Path]::DirectorySeparatorChar
    if (-not $professionPathSafe) {
        Add-Issue -Code 'theme-parent-unsafe' -Path $themeFullPath -Message '职业目录不安全，不能读取主题树。'
    }
    elseif (-not $themeFullPath.StartsWith($themePrefix, [System.StringComparison]::OrdinalIgnoreCase)) {
        Add-Issue -Code 'theme-route' -Path $themeFullPath -Message '主题目录必须位于目标职业目录内。'
    }
    elseif (-not (Test-Path -LiteralPath $themeFullPath -PathType Container)) {
        Add-Issue -Code 'missing-theme' -Path $themeFullPath -Message '主题目录不存在。'
    }
    else {
        $themeItem = Get-Item -LiteralPath $themeFullPath -Force
        $themePathSafe = Test-ReparsePointChain -Path $themeFullPath -RootPath $repoFullPath -Code 'theme-reparse-point'

        if ($themePathSafe) {
            $themeRelative = $themeFullPath.Substring($themePrefix.Length).Replace('\', '/')
            if ($themeRelative.Contains('/')) {
                Add-Issue -Code 'theme-route' -Path $themeFullPath -Message '主题目录必须是职业目录的直属子目录。'
            }
            if ($themeRelative -in @('prompts', 'frames', 'npk', 'validation')) {
                Add-Issue -Code 'reserved-theme-route' -Path $themeFullPath -Message '主题名与职业基础目录冲突。'
            }

            $themeAuthorityText = $manifestAuthorityText

            $themeAgentsPath = Join-Path -Path $themeFullPath -ChildPath 'AGENTS.md'
            if (-not (Test-Path -LiteralPath $themeAgentsPath -PathType Leaf)) {
                Add-Issue -Code 'missing-theme-agents' -Path $themeAgentsPath -Message '缺少主题 AGENTS.md。'
            }
            else {
                $themeAgentsText = Get-Utf8Text -Path $themeAgentsPath
                if ($null -ne $themeAgentsText) {
                    $themeExistingRuleText = Get-HeadFileText -Path $themeAgentsPath
                    Test-HasTitle -Path $themeAgentsPath -Text $themeAgentsText
                    Test-RequiredHeadingGroups -Path $themeAgentsPath -Text $themeAgentsText -Groups @(
                        @{ Code = 'theme-target-section'; Pattern = '主题.*目标'; Label = '主题目标' },
                        @{ Code = 'theme-style-section'; Pattern = '色板|材质|风格'; Label = '色板与材质' },
                        @{ Code = 'theme-prompt-section'; Pattern = 'Prompt.*路由|提示词.*路由'; Label = 'Prompt 路由' },
                        @{ Code = 'theme-scope-section'; Pattern = '修改.*范围|修改.*边界'; Label = '修改范围' },
                        @{ Code = 'theme-acceptance-section'; Pattern = '验收|回归'; Label = '主题验收' }
                    )
                    Test-ForbiddenContent -Path $themeAgentsPath -Text $themeAgentsText -CheckResourceAuthority -ResourceAuthorityText $themeAuthorityText -ExistingRuleText $themeExistingRuleText
                }
            }

            $themePromptsPath = Join-Path -Path $themeFullPath -ChildPath 'prompts'
            if (-not (Test-Path -LiteralPath $themePromptsPath -PathType Container)) {
                Add-Issue -Code 'missing-theme-prompts' -Path $themePromptsPath -Message '缺少主题 prompts 目录。'
            }
            else {
                $themePromptsItem = Get-Item -LiteralPath $themePromptsPath -Force
                if (Test-ReparsePointChain -Path $themePromptsPath -RootPath $repoFullPath -Code 'theme-prompts-reparse-point') {
                    $themePromptFiles = @(Get-ChildItem -LiteralPath $themePromptsPath -File -Filter '*.md' | Where-Object { $_.Name -ne 'README.md' } | Sort-Object Name)
                    if ($themePromptFiles.Count -eq 0) {
                        Add-Issue -Code 'empty-theme-prompts' -Path $themePromptsPath -Message '主题 prompts 目录没有逐技能 Prompt。'
                    }
                    Test-SafeFileNames -Files $themePromptFiles -ScopePath $themePromptsPath
                    $themeIndexNames = @(Test-Index -IndexPath (Join-Path -Path $themePromptsPath -ChildPath 'README.md') -PromptFiles $themePromptFiles)
                    foreach ($file in $themePromptFiles) {
                        Test-ThemePrompt -File $file -ProfessionPromptsPath $professionPromptsPath -ThemeName $themeRelative
                    }
                }
            }
        }
    }
}

if ($themeIndexNames.Count -gt 0) {
    if ($ExpectedPromptFileName.Count -gt 0) {
        Test-Sequence -Actual $themeIndexNames -Expected $ExpectedPromptFileName -Path $themeFullPath -Code 'theme-source-order' -Label '主题 Prompt 索引'
    }
    else {
        $professionThemeOrder = @($professionIndexNames | Where-Object { $_ -in $themeIndexNames })
        Test-Sequence -Actual $themeIndexNames -Expected $professionThemeOrder -Path $themeFullPath -Code 'theme-profession-order' -Label '主题与职业 Prompt 相对顺序'
    }
}

$sourceSummary = $null
if (-not [string]::IsNullOrWhiteSpace($SourcePath)) {
    if (-not [System.IO.Path]::IsPathRooted($SourcePath)) {
        Add-Issue -Code 'source-not-absolute' -Path $SourcePath -Message 'SourcePath 必须是绝对路径。'
        $sourceFullPath = $null
    }
    else {
        $sourceFullPath = Resolve-FullPath -Path $SourcePath
    }

    if ($null -ne $sourceFullPath -and (-not $sourceFullPath.StartsWith($repoPrefix, [System.StringComparison]::OrdinalIgnoreCase) -or -not (Test-Path -LiteralPath $sourceFullPath -PathType Leaf))) {
        Add-Issue -Code 'source-route' -Path $sourceFullPath -Message '源文件不存在或不在当前仓库内。'
    }
    elseif ($null -ne $sourceFullPath) {
        $sourceItem = Get-Item -LiteralPath $sourceFullPath -Force
        $sourcePathSafe = Test-ReparsePointChain -Path $sourceFullPath -RootPath $repoFullPath -Code 'source-reparse-point'

        if ($sourcePathSafe) {
            if ([System.IO.Path]::GetExtension($sourceFullPath).ToLowerInvariant() -notin @('.md', '.txt')) {
                Add-Issue -Code 'source-extension' -Path $sourceFullPath -Message '源文件扩展名必须是 .md 或 .txt。'
            }

            $null = Get-Utf8Text -Path $sourceFullPath

            $professionSourcePrefix = $professionFullPath.TrimEnd([System.IO.Path]::DirectorySeparatorChar, [System.IO.Path]::AltDirectorySeparatorChar) + [System.IO.Path]::DirectorySeparatorChar
            if (-not $sourceFullPath.StartsWith($professionSourcePrefix, [System.StringComparison]::OrdinalIgnoreCase)) {
                Add-Issue -Code 'source-profession-route' -Path $sourceFullPath -Message '源文件不属于正在验证的职业目录。'
            }

            $sourceSummary = [ordered]@{
                path = $sourceFullPath
                sha256 = (Get-FileHash -LiteralPath $sourceFullPath -Algorithm SHA256).Hash
            }
            if (-not [string]::IsNullOrWhiteSpace($ExpectedSourceSha256) -and -not $sourceSummary.sha256.Equals($ExpectedSourceSha256, [System.StringComparison]::OrdinalIgnoreCase)) {
                Add-Issue -Code 'source-hash' -Path $sourceFullPath -Message "源文件 SHA-256 已变化；期望 $ExpectedSourceSha256，实际 $($sourceSummary.sha256)。"
            }
        }
    }
}

$currentChanges = New-Object System.Collections.Generic.List[object]
if ($AllowedChangedRelativePath.Count -gt 0) {
    $allowedChanges = @{}
    foreach ($allowedPath in $AllowedChangedRelativePath) {
        if ([string]::IsNullOrWhiteSpace($allowedPath) -or [System.IO.Path]::IsPathRooted($allowedPath)) {
            Add-Issue -Code 'allowed-change-path' -Path ([string]$allowedPath) -Message '允许变化路径必须是非空的仓库相对路径。'
            continue
        }
        $normalizedAllowedPath = $allowedPath.Replace('\', '/').TrimStart('.', '/')
        if (-not $normalizedAllowedPath.StartsWith($professionRelative + '/', [System.StringComparison]::OrdinalIgnoreCase)) {
            Add-Issue -Code 'allowed-change-route' -Path $allowedPath -Message '允许变化路径必须位于目标职业目录内。'
            continue
        }
        $allowedChanges[$normalizedAllowedPath.Normalize([System.Text.NormalizationForm]::FormC).ToLowerInvariant()] = $true
    }

    $baselineChanges = @{}
    foreach ($baselineEntry in $BaselineChange) {
        $propertyNames = @($baselineEntry.PSObject.Properties.Name)
        if ('status' -notin $propertyNames -or 'relativePath' -notin $propertyNames -or 'exists' -notin $propertyNames -or 'sha256' -notin $propertyNames) {
            Add-Issue -Code 'baseline-change-schema' -Path $professionFullPath -Message '初始 git 变化快照缺少 status、relativePath、exists 或 sha256。'
            continue
        }
        $baselinePath = [string]$baselineEntry.relativePath
        if ([string]::IsNullOrWhiteSpace($baselinePath) -or [System.IO.Path]::IsPathRooted($baselinePath)) {
            Add-Issue -Code 'baseline-change-path' -Path $baselinePath -Message '初始 git 变化必须使用非空仓库相对路径。'
            continue
        }
        $normalizedBaselinePath = $baselinePath.Replace('\', '/').Trim()
        if (-not $normalizedBaselinePath.StartsWith($professionRelative + '/', [System.StringComparison]::OrdinalIgnoreCase)) {
            Add-Issue -Code 'baseline-change-route' -Path $baselinePath -Message '初始 git 变化不在目标职业目录内。'
            continue
        }
        $baselineKey = $normalizedBaselinePath.Normalize([System.Text.NormalizationForm]::FormC).ToLowerInvariant()
        $baselineChanges[$baselineKey] = [pscustomobject]@{
            status = [string]$baselineEntry.status
            relativePath = $normalizedBaselinePath
            exists = [bool]$baselineEntry.exists
            sha256 = if ($null -ne $baselineEntry.sha256) { [string]$baselineEntry.sha256 } else { $null }
        }
    }

    try {
        $gitOutput = @(& git --literal-pathspecs -C $repoFullPath -c core.quotepath=false status --porcelain=v1 --untracked-files=all -- $professionRelative 2>&1)
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
                $normalizedChangedPath = $changedPath.Replace('\', '/').Trim()
                $fullChangedPath = [System.IO.Path]::GetFullPath((Join-Path -Path $repoFullPath -ChildPath $normalizedChangedPath))
                $currentExists = Test-Path -LiteralPath $fullChangedPath -PathType Leaf
                if ($currentExists -and -not (Test-ReparsePointChain -Path $fullChangedPath -RootPath $repoFullPath -Code 'changed-file-reparse-point')) {
                    $currentExists = $false
                }
                $currentSha256 = if ($currentExists) { (Get-FileHash -LiteralPath $fullChangedPath -Algorithm SHA256).Hash } else { $null }
                $currentEntry = [pscustomobject]@{
                    status = $statusCode
                    relativePath = $normalizedChangedPath
                    exists = $currentExists
                    sha256 = $currentSha256
                }
                $currentChanges.Add($currentEntry)
                $changeKey = $normalizedChangedPath.Normalize([System.Text.NormalizationForm]::FormC).ToLowerInvariant()
                if ($allowedChanges.ContainsKey($changeKey)) {
                    continue
                }
                if (-not $baselineChanges.ContainsKey($changeKey)) {
                    Add-Issue -Code 'unexpected-change' -Path $normalizedChangedPath -Message '职业树中存在预写计划之外的变化。'
                    continue
                }

                $baselineEntry = $baselineChanges[$changeKey]
                $sameStatus = $currentEntry.status.Equals($baselineEntry.status, [System.StringComparison]::Ordinal)
                $sameExistence = $currentEntry.exists -eq $baselineEntry.exists
                $sameHash = ($null -eq $currentEntry.sha256 -and $null -eq $baselineEntry.sha256) -or ($null -ne $currentEntry.sha256 -and $null -ne $baselineEntry.sha256 -and $currentEntry.sha256.Equals($baselineEntry.sha256, [System.StringComparison]::OrdinalIgnoreCase))
                if (-not $sameStatus -or -not $sameExistence -or -not $sameHash) {
                    Add-Issue -Code 'baseline-change-mutated' -Path $normalizedChangedPath -Message '计划前已存在的非目标变化在导入期间被修改。'
                }
            }
        }

        $currentChangeKeys = @{}
        foreach ($currentEntry in $currentChanges) {
            $currentChangeKeys[$currentEntry.relativePath.Normalize([System.Text.NormalizationForm]::FormC).ToLowerInvariant()] = $true
        }
        foreach ($baselineKey in $baselineChanges.Keys) {
            if (-not $allowedChanges.ContainsKey($baselineKey) -and -not $currentChangeKeys.ContainsKey($baselineKey)) {
                Add-Issue -Code 'baseline-change-missing' -Path $baselineChanges[$baselineKey].relativePath -Message '计划前已存在的非目标变化在导入期间消失。'
            }
        }
    }
    catch {
        Add-Issue -Code 'git-change-check' -Path $professionFullPath -Message '无法读取职业目录的最终 git 状态。'
    }
}

$result = [ordered]@{
    schemaVersion = 1
    status = if ($script:Errors.Count -eq 0) { 'passed' } else { 'failed' }
    professionPath = $professionFullPath
    themePath = $themeFullPath
    source = $sourceSummary
    changes = @($currentChanges.ToArray())
    counts = [ordered]@{
        professionPrompts = $professionPromptFiles.Count
        themePrompts = $themePromptFiles.Count
        checkedFiles = $script:CheckedFiles.Count
        errors = $script:Errors.Count
        warnings = $script:Warnings.Count
    }
    errors = @($script:Errors.ToArray())
    warnings = @($script:Warnings.ToArray())
}

$result | ConvertTo-Json -Depth 8
if ($script:Errors.Count -gt 0) {
    exit 1
}

Set-StrictMode -Version Latest

function Get-DnfPatchRepositoryRoot {
    return [IO.Path]::GetFullPath((Join-Path $PSScriptRoot '..'))
}

function Resolve-DnfPatchPath {
    param(
        [Parameter(Mandatory = $true)]
        [string]$Value,

        [string]$BaseDirectory = (Get-DnfPatchRepositoryRoot)
    )

    $native = $Value.Replace('/', [IO.Path]::DirectorySeparatorChar)
    if ([IO.Path]::IsPathRooted($native)) {
        return [IO.Path]::GetFullPath($native)
    }
    return [IO.Path]::GetFullPath((Join-Path $BaseDirectory $native))
}

function Get-DnfPatchLocalSettings {
    param(
        [string]$RepositoryRoot = (Get-DnfPatchRepositoryRoot),
        [switch]$Required
    )

    $settingsPath = Join-Path $RepositoryRoot '.dnf-patch.local.json'
    if (-not (Test-Path -LiteralPath $settingsPath -PathType Leaf)) {
        if ($Required) {
            throw "Machine-local settings were not found: $settingsPath"
        }
        return $null
    }

    $settings = Get-Content -LiteralPath $settingsPath -Raw -Encoding UTF8 | ConvertFrom-Json
    if ($settings.schemaVersion -ne 1) {
        throw "Unsupported machine-local settings schemaVersion: $($settings.schemaVersion)"
    }
    if ($null -eq $settings.policy -or $settings.policy.sourceReadOnly -ne $true) {
        throw 'Machine-local settings must declare policy.sourceReadOnly=true.'
    }
    if ($settings.policy.deploymentTargetConfigured -ne $false) {
        throw 'Machine-local settings must not configure a deployment target.'
    }
    return $settings
}

function Resolve-DnfImagePacks2 {
    param(
        [string]$Path,
        [string]$RepositoryRoot = (Get-DnfPatchRepositoryRoot)
    )

    $candidate = $Path
    if ([string]::IsNullOrWhiteSpace($candidate)) {
        $candidate = $env:DNF_PATCH_IMAGEPACKS2
    }
    if ([string]::IsNullOrWhiteSpace($candidate)) {
        $settings = Get-DnfPatchLocalSettings -RepositoryRoot $RepositoryRoot -Required
        if ($null -ne $settings.PSObject.Properties['imagePacks2'] -and
            -not [string]::IsNullOrWhiteSpace([string]$settings.imagePacks2)) {
            $candidate = [string]$settings.imagePacks2
        }
        elseif ($null -ne $settings.PSObject.Properties['dnfSourceRoot'] -and
            -not [string]::IsNullOrWhiteSpace([string]$settings.dnfSourceRoot)) {
            $sourceRoot = Resolve-DnfPatchPath -Value ([string]$settings.dnfSourceRoot) `
                -BaseDirectory $RepositoryRoot
            $candidate = Join-Path $sourceRoot 'ImagePacks2'
        }
    }
    if ([string]::IsNullOrWhiteSpace($candidate)) {
        throw 'ImagePacks2 is not configured. Set -ImagePacks2, DNF_PATCH_IMAGEPACKS2, or .dnf-patch.local.json.'
    }

    $resolved = Resolve-DnfPatchPath -Value $candidate -BaseDirectory $RepositoryRoot
    if (-not (Test-Path -LiteralPath $resolved -PathType Container)) {
        throw "ImagePacks2 directory was not found: $resolved"
    }
    return (Resolve-Path -LiteralPath $resolved).Path
}

function Resolve-DnfExtractorDirectory {
    param(
        [string]$Path,
        [string]$RepositoryRoot = (Get-DnfPatchRepositoryRoot)
    )

    $candidate = $Path
    if ([string]::IsNullOrWhiteSpace($candidate)) {
        $settings = Get-DnfPatchLocalSettings -RepositoryRoot $RepositoryRoot
        if ($null -ne $settings -and $null -ne $settings.tools -and
            $null -ne $settings.tools.PSObject.Properties['extractorDirectory']) {
            $candidate = [string]$settings.tools.extractorDirectory
        }
    }
    if ([string]::IsNullOrWhiteSpace($candidate)) {
        $candidate = 'tools/bin'
    }

    $resolved = Resolve-DnfPatchPath -Value $candidate -BaseDirectory $RepositoryRoot
    foreach ($name in @('ExtractorSharp.Core.dll', 'ExtractorSharp.Json.dll', 'zlib1.dll')) {
        $dependency = Join-Path $resolved $name
        if (-not (Test-Path -LiteralPath $dependency -PathType Leaf)) {
            throw "Local ExtractorSharp dependency was not found: $dependency"
        }
    }
    return (Resolve-Path -LiteralPath $resolved).Path
}

function Resolve-DnfDirectXTexTool {
    param(
        [Parameter(Mandatory = $true)]
        [ValidateSet('texconv.exe', 'texdiag.exe')]
        [string]$Name,

        [string]$Path,
        [string]$RepositoryRoot = (Get-DnfPatchRepositoryRoot)
    )

    if (-not [string]::IsNullOrWhiteSpace($Path)) {
        $resolved = Resolve-DnfPatchPath -Value $Path -BaseDirectory $RepositoryRoot
    }
    else {
        $directory = $null
        $settings = Get-DnfPatchLocalSettings -RepositoryRoot $RepositoryRoot
        if ($null -ne $settings -and $null -ne $settings.tools -and
            $null -ne $settings.tools.PSObject.Properties['directXTexDirectory']) {
            $directory = [string]$settings.tools.directXTexDirectory
        }
        if ([string]::IsNullOrWhiteSpace($directory)) {
            $directory = 'tools/bin/directxtex/may2026'
        }
        $resolved = Join-Path (Resolve-DnfPatchPath -Value $directory -BaseDirectory $RepositoryRoot) $Name
    }
    if (-not (Test-Path -LiteralPath $resolved -PathType Leaf)) {
        throw "Local DirectXTex tool was not found: $resolved"
    }
    return (Resolve-Path -LiteralPath $resolved).Path
}

function Resolve-DnfAsepriteExecutable {
    param(
        [string]$Path,
        [string]$RepositoryRoot = (Get-DnfPatchRepositoryRoot)
    )

    $candidate = $Path
    $expectedHash = $null
    if ([string]::IsNullOrWhiteSpace($candidate)) {
        $settings = Get-DnfPatchLocalSettings -RepositoryRoot $RepositoryRoot
        $manifestValue = $null
        if ($null -ne $settings -and $null -ne $settings.tools -and
            $null -ne $settings.tools.PSObject.Properties['asepriteExecutable']) {
            $candidate = [string]$settings.tools.asepriteExecutable
        }
        elseif ($null -ne $settings -and $null -ne $settings.tools -and
            $null -ne $settings.tools.PSObject.Properties['asepriteCurrentManifest']) {
            $manifestValue = [string]$settings.tools.asepriteCurrentManifest
        }
        if ([string]::IsNullOrWhiteSpace($manifestValue)) {
            $manifestValue = 'tools/bin/aseprite/current.json'
        }
        if ([string]::IsNullOrWhiteSpace($candidate)) {
            $manifestPath = Resolve-DnfPatchPath -Value $manifestValue -BaseDirectory $RepositoryRoot
            if (-not (Test-Path -LiteralPath $manifestPath -PathType Leaf)) {
                throw "Aseprite is not imported. Expected local manifest: $manifestPath"
            }
            $manifest = Get-Content -LiteralPath $manifestPath -Raw -Encoding UTF8 | ConvertFrom-Json
            if ($manifest.schemaVersion -ne 1 -or
                [string]::IsNullOrWhiteSpace([string]$manifest.relativeExecutable) -or
                [string]::IsNullOrWhiteSpace([string]$manifest.sha256)) {
                throw "Aseprite current manifest is invalid: $manifestPath"
            }
            $candidate = Resolve-DnfPatchPath -Value ([string]$manifest.relativeExecutable) `
                -BaseDirectory (Split-Path -Parent $manifestPath)
            $expectedHash = ([string]$manifest.sha256).ToUpperInvariant()
        }
    }

    $resolved = Resolve-DnfPatchPath -Value $candidate -BaseDirectory $RepositoryRoot
    if (-not (Test-Path -LiteralPath $resolved -PathType Leaf)) {
        throw "Aseprite executable was not found: $resolved"
    }
    if ($null -ne $expectedHash) {
        $actualHash = (Get-FileHash -LiteralPath $resolved -Algorithm SHA256).Hash
        if ($actualHash -ne $expectedHash) {
            throw "Aseprite executable SHA-256 changed: actual=$actualHash expected=$expectedHash"
        }
    }
    return (Resolve-Path -LiteralPath $resolved).Path
}

function Resolve-DnfSourceNpk {
    param(
        [Parameter(Mandatory = $true)]
        [string]$ConfiguredPath,

        [string]$ImagePacks2,
        [string]$RepositoryRoot = (Get-DnfPatchRepositoryRoot)
    )

    $imagePacksPath = Resolve-DnfImagePacks2 -Path $ImagePacks2 -RepositoryRoot $RepositoryRoot
    $fileName = [IO.Path]::GetFileName($ConfiguredPath.Replace('/', [IO.Path]::DirectorySeparatorChar))
    if ([string]::IsNullOrWhiteSpace($fileName) -or
        -not $fileName.EndsWith('.NPK', [StringComparison]::OrdinalIgnoreCase)) {
        throw "Configured source path does not identify an NPK file: $ConfiguredPath"
    }
    $sourcePath = Join-Path $imagePacksPath $fileName
    if (-not (Test-Path -LiteralPath $sourcePath -PathType Leaf)) {
        throw "Configured source NPK was not found in the active read-only ImagePacks2: $sourcePath"
    }
    return (Resolve-Path -LiteralPath $sourcePath).Path
}

function Get-DnfFileSnapshot {
    param(
        [Parameter(Mandatory = $true)]
        [string]$Path
    )

    $resolved = (Resolve-Path -LiteralPath $Path).Path
    $item = Get-Item -LiteralPath $resolved
    return [pscustomobject]@{
        path = $resolved
        length = [long]$item.Length
        lastWriteTime = $item.LastWriteTime.ToString('o')
        sha256 = (Get-FileHash -LiteralPath $resolved -Algorithm SHA256).Hash
    }
}

Export-ModuleMember -Function @(
    'Get-DnfPatchRepositoryRoot',
    'Resolve-DnfPatchPath',
    'Get-DnfPatchLocalSettings',
    'Resolve-DnfImagePacks2',
    'Resolve-DnfExtractorDirectory',
    'Resolve-DnfDirectXTexTool',
    'Resolve-DnfAsepriteExecutable',
    'Resolve-DnfSourceNpk',
    'Get-DnfFileSnapshot'
)
[CmdletBinding()]
param(
    [string]$ImagePacks2,
    [string]$AsepritePath,
    [switch]$RequireAseprite,
    [switch]$AsJson
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

Import-Module (Join-Path $PSScriptRoot 'DnfPatch.Toolchain.psm1') -Force
$repoRoot = Get-DnfPatchRepositoryRoot
$settings = Get-DnfPatchLocalSettings -RepositoryRoot $repoRoot -Required
$settingsPath = Join-Path $repoRoot '.dnf-patch.local.json'
$imagePacksPath = Resolve-DnfImagePacks2 -Path $ImagePacks2 -RepositoryRoot $repoRoot
$extractorDirectory = Resolve-DnfExtractorDirectory -RepositoryRoot $repoRoot
$texconv = Resolve-DnfDirectXTexTool -Name 'texconv.exe' -RepositoryRoot $repoRoot
$texdiag = Resolve-DnfDirectXTexTool -Name 'texdiag.exe' -RepositoryRoot $repoRoot

$aseprite = $null
$asepriteError = $null
try {
    $aseprite = Resolve-DnfAsepriteExecutable -Path $AsepritePath -RepositoryRoot $repoRoot
}
catch {
    $asepriteError = $_.Exception.Message
    if ($RequireAseprite) {
        throw
    }
}

$extractorFiles = foreach ($name in @('ExtractorSharp.Core.dll', 'ExtractorSharp.Json.dll', 'zlib1.dll')) {
    Get-DnfFileSnapshot -Path (Join-Path $extractorDirectory $name)
}
$directXTexFiles = foreach ($path in @($texconv, $texdiag)) {
    $snapshot = Get-DnfFileSnapshot -Path $path
    $signature = Get-AuthenticodeSignature -LiteralPath $path
    [pscustomobject]@{
        path = $snapshot.path
        length = $snapshot.length
        sha256 = $snapshot.sha256
        signatureStatus = $signature.Status.ToString()
    }
}

$asepriteRecord = if ($null -ne $aseprite) {
    try {
        $snapshot = Get-DnfFileSnapshot -Path $aseprite
        $versionOutput = (& $aseprite --version 2>&1 | Out-String).Trim()
        if ($LASTEXITCODE -ne 0) {
            throw "Aseprite --version failed: $versionOutput"
        }
        $capability = Test-DnfAsepriteApiCapability -Executable $aseprite -RepositoryRoot $repoRoot
        [pscustomobject]@{
            available = $true
            path = $snapshot.path
            version = $versionOutput
            length = $snapshot.length
            sha256 = $snapshot.sha256
            apiCapability = $capability
        }
    }
    catch {
        if ($RequireAseprite) {
            throw
        }
        [pscustomobject]@{
            available = $false
            reason = $_.Exception.Message
        }
    }
}
else {
    [pscustomobject]@{
        available = $false
        reason = $asepriteError
    }
}

$compiler = 'C:\Windows\Microsoft.NET\Framework\v4.0.30319\csc.exe'
$x86PowerShell = 'C:\Windows\SysWOW64\WindowsPowerShell\v1.0\powershell.exe'
$result = [pscustomobject]@{
    schemaVersion = 1
    status = if ($asepriteRecord.available) { 'passed' } else { 'partial-aseprite-not-imported' }
    mode = 'read-only local toolchain check; no build, deployment, or process operation'
    settings = Get-DnfFileSnapshot -Path $settingsPath
    source = [pscustomobject]@{
        imagePacks2 = $imagePacksPath
        npkCount = @(Get-ChildItem -LiteralPath $imagePacksPath -File -Filter '*.NPK').Count
        readOnlyPolicy = [bool]$settings.policy.sourceReadOnly
        deploymentTargetConfigured = [bool]$settings.policy.deploymentTargetConfigured
    }
    aseprite = $asepriteRecord
    extractorSharp = @($extractorFiles)
    directXTex = @($directXTexFiles)
    systemPrerequisites = [pscustomobject]@{
        windowsPowerShellVersion = $PSVersionTable.PSVersion.ToString()
        x86PowerShell = $x86PowerShell
        x86PowerShellAvailable = Test-Path -LiteralPath $x86PowerShell -PathType Leaf
        dotNetFrameworkCompiler = $compiler
        dotNetFrameworkCompilerAvailable = Test-Path -LiteralPath $compiler -PathType Leaf
    }
}

if ($AsJson) {
    $result | ConvertTo-Json -Depth 8
}
else {
    $result
}
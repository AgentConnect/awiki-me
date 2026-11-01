#requires -Version 7.0
[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)][string]$TenantConfigPath,
    [switch]$PrepareOnly
)

# Build-only identity overlays: never patch the user's checkout or enable E2E.
Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
$Root = [IO.Path]::GetFullPath((Join-Path $PSScriptRoot '..'))
$Core = [IO.Path]::GetFullPath((Join-Path $Root '../awiki-cli-rs2'))
if ([Environment]::OSVersion.Platform -ne [PlatformID]::Win32NT -or
    [Runtime.InteropServices.RuntimeInformation]::OSArchitecture -ne 'X64') {
    throw 'Manual Windows builds require native Windows x64.'
}
$TenantConfigPath = (Resolve-Path -LiteralPath $TenantConfigPath).Path
$TenantBytes = [IO.File]::ReadAllBytes($TenantConfigPath)
$Tenant = [Text.Encoding]::UTF8.GetString($TenantBytes) | ConvertFrom-Json
if ($Tenant.schema_version -ne 1 -or $Tenant.default_slot -ne 'primary' -or
    $Tenant.tenants.primary.backend_origin -ne 'https://awiki.info' -or
    $Tenant.tenants.primary.did_host -ne 'awiki.info' -or
    $Tenant.tenants.secondary.backend_origin -ne 'https://awiki.ai' -or
    $Tenant.tenants.secondary.did_host -ne 'awiki.ai') {
    throw 'Use the computer-use awiki.info / awiki.ai two-slot tenant configuration.'
}
$TenantHash = (Get-FileHash -LiteralPath $TenantConfigPath -Algorithm SHA256).Hash.ToLowerInvariant()
$TenantBase64 = [Convert]::ToBase64String($TenantBytes)
$Run = Join-Path $Root ('build/computer-use/windows-' + (Get-Date -Format 'yyyyMMdd-HHmmss-fff'))
New-Item -ItemType Directory -Path $Run | Out-Null

function Assert-NativeExit([string]$Step) {
    if ($LASTEXITCODE -ne 0) { throw "$Step failed: $LASTEXITCODE" }
}
function Replace-Required([string]$Path, [string]$Before, [string]$After) {
    $value = [IO.File]::ReadAllText($Path)
    if (-not $value.Contains($Before)) { throw "Identity overlay no longer matches: $Path" }
    [IO.File]::WriteAllText($Path, $value.Replace($Before, $After), [Text.UTF8Encoding]::new($false))
}

$Files = @(Get-ChildItem -LiteralPath (Join-Path $Root 'lib'), (Join-Path $Root 'assets'),
    (Join-Path $Root 'windows') -File -Recurse | Where-Object {
        $_.FullName -notmatch '[\\/]ephemeral[\\/]'
    })
$Metadata = [ordered]@{
    status = 'prepared'; platform = 'windows-x64'; entrypoint = 'lib/main.dart'
    app_commit = (& git -C $Root rev-parse HEAD)
    app_dirty = [bool](@(& git -C $Root status --porcelain).Count)
    core_commit = (& git -C $Core rev-parse HEAD)
    core_dirty = [bool](@(& git -C $Core status --porcelain).Count)
    dependency_mode = 'registry'; tenant_sha256 = $TenantHash
    builder_sha256 = (Get-FileHash -LiteralPath $PSCommandPath).Hash
    apps = @()
}
foreach ($Role in @('admin', 'joiner')) {
    $Label = if ($Role -eq 'admin') { 'Admin' } else { 'Joiner' }
    $Product = "AWikiMeComputerUse$Label"
    $Title = "AWiki Me CU $Label"
    $Guid = if ($Role -eq 'admin') { '21e045cf-28ae-4f82-9715-f059cd74a723' } else { 'fbfb8215-f610-42d6-bdbc-c56fb0e637e7' }
    $Source = Join-Path $Run $Role
    New-Item -ItemType Directory -Path $Source | Out-Null
    foreach ($File in $Files) {
        $Relative = [IO.Path]::GetRelativePath($Root, $File.FullName)
        $Destination = Join-Path $Source $Relative
        New-Item -ItemType Directory -Path (Split-Path $Destination) -Force | Out-Null
        Copy-Item -LiteralPath $File.FullName -Destination $Destination
    }
    foreach ($Name in @('pubspec.yaml', 'pubspec.lock', 'analysis_options.yaml', 'l10n.yaml')) {
        if (Test-Path (Join-Path $Root $Name)) { Copy-Item (Join-Path $Root $Name) $Source }
    }
    $CorePackage = (Join-Path $Core 'packages/awiki_im_core').Replace('\', '/')
    Replace-Required (Join-Path $Source 'pubspec.yaml') 'path: ../awiki-cli-rs2/packages/awiki_im_core' ("path: '" + $CorePackage.Replace("'", "''") + "'")
    $Header = Join-Path $Source 'windows/runner/app_constants.h'
    Replace-Required $Header 'AI_AWIKI_AWIKIME_FLUTTER_WINDOW' "AI_AWIKI_AWIKIME_CU_$Label"
    Replace-Required $Header 'ai.awiki.awikime.single-instance' "ai.awiki.awikime.cu.$Role.single-instance"
    Replace-Required $Header 'ai.awiki.awikime.activate.v1' "ai.awiki.awikime.cu.$Role.activate.v1"
    Replace-Required $Header 'ai.awiki.awikime.shutdown-for-update.v1' "ai.awiki.awikime.cu.$Role.shutdown-for-update.v1"
    Replace-Required $Header 'L"AWiki Me"' "L`"$Title`""
    Replace-Required $Header 'AWiki.AWikiMe' "AWiki.AWikiMe.CU.$Label"
    Replace-Required $Header '42f66431-9bea-46c4-ac14-475b9044a2be' $Guid
    Replace-Required (Join-Path $Source 'windows/runner/Runner.rc') '"AWiki Me"' "`"$Product`""
    Replace-Required (Join-Path $Source 'windows/runner/desktop_shell.cpp') 'L"AWikiMe"' "L`"$Product`""
    Replace-Required (Join-Path $Source 'windows/runner/desktop_shell.cpp') 'L"AWiki Me"' "L`"$Title`""
    Replace-Required (Join-Path $Source 'windows/runner/window_placement.cpp') 'AWikiMeDevelopment' $Product
    foreach ($Path in @('windows/runner/scope_secret_store.cpp', 'lib/src/data/storage/platform_scope_secret_repository.dart')) {
        Replace-Required (Join-Path $Source $Path) 'ai.awiki.awikime.dev.scope-secrets' "ai.awiki.awikime.dev.cu.$Role.scope-secrets"
    }
    $Notifications = Join-Path $Source 'lib/src/data/services/app_notification_facade.dart'
    Replace-Required $Notifications 'AWiki.AWikiMe' "AWiki.AWikiMe.CU.$Label"
    Replace-Required $Notifications '42f66431-9bea-46c4-ac14-475b9044a2be' $Guid
    $Metadata.apps += [ordered]@{
        role = $Role; title = $Title; product = $Product; source = $Source
        executable = (Join-Path $Source 'build/windows/x64/runner/Debug/AWikiMe.exe')
        secret_service = "ai.awiki.awikime.dev.cu.$Role.scope-secrets"
    }
}
$Manifest = Join-Path $Run 'build.json'
$Metadata | ConvertTo-Json -Depth 8 | Set-Content -LiteralPath $Manifest -Encoding utf8
if ($PrepareOnly) { Write-Output $Manifest; return }

# Put dumpbin on PATH to avoid the SDK builder's single-result discovery issue.
$OldPath = $env:PATH
$OldRegistry = $env:AWIKI_RELEASE_REGISTRY
$OldPub = $env:PUB_HOSTED_URL
$Step = 'toolchain'
try {
    $VsWhere = Join-Path ${env:ProgramFiles(x86)} 'Microsoft Visual Studio/Installer/vswhere.exe'
    $Vs = & $VsWhere -latest -products '*' -requires Microsoft.VisualStudio.Component.VC.Tools.x86.x64 -property installationPath
    Assert-NativeExit 'Visual Studio discovery'
    $Dumpbin = @(Get-ChildItem "$Vs/VC/Tools/MSVC/*/bin/Hostx64/x64/dumpbin.exe" | Sort-Object FullName -Descending)
    if ($Dumpbin.Count -eq 0) { throw 'MSVC x64 dumpbin is required.' }
    $env:PATH = $Dumpbin[0].DirectoryName + ';' + $env:PATH
    # The SDK registry helper invokes python3; Windows may expose only python.exe.
    $Python = (Get-Command python -CommandType Application -ErrorAction Stop | Select-Object -First 1).Source
    & $Python -c 'import sys; assert sys.version_info >= (3, 10)'
    Assert-NativeExit 'Python runtime check'
    $Tools = Join-Path $Run 'tools'
    New-Item -ItemType Directory -Path $Tools | Out-Null
    [IO.File]::WriteAllText((Join-Path $Tools 'python3.cmd'), "@echo off`r`n@`"$Python`" %*`r`n")
    $env:PATH = $Tools + ';' + $env:PATH
    $env:AWIKI_RELEASE_REGISTRY = '1'
    $env:PUB_HOSTED_URL = 'https://mirrors.tuna.tsinghua.edu.cn/dart-pub'
    $Step = 'core-registry-build'
    & (Join-Path $Core 'scripts/flutter/build-windows.ps1')
    $Dll = Join-Path $Core 'packages/awiki_im_core/windows/bin/awiki_im_core.dll'
    $DllHash = (Get-FileHash $Dll -Algorithm SHA256).Hash
    foreach ($App in $Metadata.apps) {
        $Step = 'flutter-' + $App.role
        Push-Location $App.source
        try {
            & flutter pub get
            Assert-NativeExit 'flutter pub get'
            & flutter build windows --debug --no-pub --target=lib/main.dart "--dart-define=AWIKI_BUILTIN_TENANTS_BASE64=$TenantBase64" "--dart-define=AWIKI_BUILTIN_TENANTS_SHA256=$TenantHash"
            Assert-NativeExit 'flutter build windows'
            $Output = Split-Path $App.executable
            foreach ($Required in @('AWikiMe.exe', 'flutter_windows.dll', 'awiki_im_core.dll', 'data/flutter_assets')) {
                if (-not (Test-Path (Join-Path $Output $Required))) { throw "Missing runtime artifact: $Required" }
            }
            if ((Get-FileHash (Join-Path $Output 'awiki_im_core.dll')).Hash -ne $DllHash) { throw 'Stale native Core DLL' }
            if ((Get-Item $App.executable).VersionInfo.ProductName -ne $App.product) { throw 'Unexpected application storage identity' }
            $App.exe_sha256 = (Get-FileHash $App.executable).Hash
        } finally { Pop-Location }
    }
    $Metadata.core_dll_sha256 = $DllHash
    $Metadata.status = 'built'
    $Metadata | ConvertTo-Json -Depth 8 | Set-Content -LiteralPath $Manifest -Encoding utf8
    Write-Output "Built two standalone Windows Debug Apps: $Manifest"
} catch {
    $Metadata.status = 'failed'
    $Metadata.failed_step = $Step
    $Metadata | ConvertTo-Json -Depth 8 | Set-Content -LiteralPath $Manifest -Encoding utf8
    throw
} finally {
    $env:PATH = $OldPath
    $env:AWIKI_RELEASE_REGISTRY = $OldRegistry
    $env:PUB_HOSTED_URL = $OldPub
}

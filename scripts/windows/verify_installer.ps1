[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)][string]$BaseInstaller,
    [Parameter(Mandatory = $true)][string]$UpgradeInstaller,
    [Parameter(Mandatory = $true)][string]$ExpectedVersion,
    [Parameter(Mandatory = $true)][string]$ExpectedBaseRuntimeManifest,
    [Parameter(Mandatory = $true)][string]$ExpectedRuntimeManifest,
    [Parameter(Mandatory = $true)][string[]]$ObsoleteRuntimeFiles
)

$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest

$AppDir = Join-Path $env:LOCALAPPDATA 'Programs\AWiki Me'
$AppExe = Join-Path $AppDir 'AWikiMe.exe'
$CoreDll = Join-Path $AppDir 'awiki_im_core.dll'
$RuntimeManifestName = 'awiki-runtime-manifest.json'
$RuntimeFileListName = 'awiki-runtime-files.txt'
$InstalledRuntimeManifest = Join-Path $AppDir $RuntimeManifestName
$ExpectedBaseRuntimeManifest = (Resolve-Path -LiteralPath $ExpectedBaseRuntimeManifest).Path
$ExpectedRuntimeManifest = (Resolve-Path -LiteralPath $ExpectedRuntimeManifest).Path
$SupportDir = Join-Path $env:LOCALAPPDATA 'AWiki\AWikiMe\support'
$SupportSentinel = Join-Path $SupportDir 'installer-ci-sentinel.json'
$CacheDir = Join-Path $env:LOCALAPPDATA 'AWiki\AWikiMe\cache'
$CacheSentinel = Join-Path $CacheDir 'installer-ci-cache-sentinel.json'
$CredentialTarget = 'ai.awiki.awikime.scope-secrets/scope/00000000-0000-4000-8000-000000000001'
$UninstallKey = 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Uninstall\{6D68B66D-87E1-4F18-93C5-AE56D58C5211}_is1'
$ExpectedSupportSentinelHash = ''
$ExpectedCacheSentinelHash = ''

function Invoke-Installer([string]$Path, [switch]$ExpectFailure) {
    $process = Start-Process `
        -FilePath $Path `
        -ArgumentList @('/VERYSILENT', '/SUPPRESSMSGBOXES', '/NORESTART', '/CURRENTUSER') `
        -PassThru `
        -Wait
    if ($ExpectFailure) {
        if ($process.ExitCode -eq 0) { throw "Installer unexpectedly succeeded: $Path" }
    }
    elseif ($process.ExitCode -ne 0) {
        throw "Installer failed with exit code $($process.ExitCode): $Path"
    }
}

function Invoke-Uninstaller {
    $uninstaller = Join-Path $AppDir 'unins000.exe'
    if (Test-Path $uninstaller) {
        $process = Start-Process `
            -FilePath $uninstaller `
            -ArgumentList @('/VERYSILENT', '/SUPPRESSMSGBOXES', '/NORESTART') `
            -PassThru `
            -Wait
        if ($process.ExitCode -ne 0) {
            throw "Uninstaller failed with exit code $($process.ExitCode)"
        }
    }
}

function Assert-RuntimeManifest([string]$ExpectedManifest) {
    if (-not (Test-Path -LiteralPath $InstalledRuntimeManifest -PathType Leaf)) {
        throw "Installed runtime manifest is missing: $InstalledRuntimeManifest"
    }
    $installedManifestHash = (Get-FileHash -LiteralPath $InstalledRuntimeManifest -Algorithm SHA256).Hash
    $expectedManifestHash = (Get-FileHash -LiteralPath $ExpectedManifest -Algorithm SHA256).Hash
    if ($installedManifestHash -cne $expectedManifestHash) {
        throw 'Installed runtime manifest does not match the build stage manifest'
    }

    $manifest = Get-Content -LiteralPath $InstalledRuntimeManifest -Raw | ConvertFrom-Json
    if ($manifest.schemaVersion -ne 1 -or $null -eq $manifest.files) {
        throw 'Installed runtime manifest has an unsupported schema'
    }
    $expectedPaths = @{}
    foreach ($entry in @($manifest.files)) {
        $relative = [string]$entry.path
        $parts = @($relative -split '/')
        if ([string]::IsNullOrWhiteSpace($relative) -or
            [IO.Path]::IsPathRooted($relative) -or
            $parts -contains '..' -or
            $expectedPaths.ContainsKey($relative)) {
            throw "Installed runtime manifest contains an invalid path: $relative"
        }
        if ([string]$entry.sha256 -cnotmatch '^[0-9a-f]{64}$' -or [int64]$entry.sizeBytes -lt 0) {
            throw "Installed runtime manifest contains invalid metadata: $relative"
        }
        $path = Join-Path $AppDir ($relative.Replace('/', '\'))
        if (-not (Test-Path -LiteralPath $path -PathType Leaf)) {
            throw "Installed runtime file is missing: $relative"
        }
        $file = Get-Item -LiteralPath $path
        if ([int64]$file.Length -ne [int64]$entry.sizeBytes) {
            throw "Installed runtime file size mismatch: $relative"
        }
        $hash = (Get-FileHash -LiteralPath $path -Algorithm SHA256).Hash.ToLowerInvariant()
        if ($hash -cne [string]$entry.sha256) {
            throw "Installed runtime file hash mismatch: $relative"
        }
        $expectedPaths[$relative] = $true
    }

    $runtimeFileList = Join-Path $AppDir $RuntimeFileListName
    if (-not (Test-Path -LiteralPath $runtimeFileList -PathType Leaf)) {
        throw "Installed runtime allowlist is missing: $runtimeFileList"
    }
    $ownedPaths = @{}
    foreach ($relative in @(Get-Content -LiteralPath $runtimeFileList)) {
        $parts = @($relative -split '/')
        if ([string]::IsNullOrWhiteSpace($relative) -or
            [IO.Path]::IsPathRooted($relative) -or
            $relative.Contains('\') -or
            $parts -contains '.' -or
            $parts -contains '..' -or
            $ownedPaths.ContainsKey($relative)) {
            throw "Installed runtime allowlist contains an invalid path: $relative"
        }
        $ownedPaths[$relative] = $true
    }
    $expectedOwnedPaths = @{}
    $expectedOwnedPathValues = @($expectedPaths.Keys)
    $expectedOwnedPathValues += $RuntimeManifestName
    foreach ($relative in $expectedOwnedPathValues) {
        $expectedOwnedPaths[$relative] = $true
    }
    $allowlistMissing = @(
        $expectedOwnedPaths.Keys | Where-Object { -not $ownedPaths.ContainsKey($_) }
    )
    $allowlistUnexpected = @(
        $ownedPaths.Keys | Where-Object { -not $expectedOwnedPaths.ContainsKey($_) }
    )
    if ($allowlistMissing.Count -gt 0 -or $allowlistUnexpected.Count -gt 0) {
        throw "Installed runtime allowlist mismatch; missing=$($allowlistMissing -join ','); unexpected=$($allowlistUnexpected -join ',')"
    }

    $actualPaths = @(
        Get-ChildItem -LiteralPath $AppDir -Recurse -File |
            ForEach-Object {
                $relative = [IO.Path]::GetRelativePath($AppDir, $_.FullName).Replace('\', '/')
                if ($relative -cne $RuntimeManifestName -and
                    $relative -notmatch '^unins[0-9]{3}\.(dat|exe|msg)$') {
                    $relative
                }
            }
    )
    $missing = @($expectedPaths.Keys | Where-Object { $_ -notin $actualPaths })
    $unexpected = @($actualPaths | Where-Object { -not $expectedPaths.ContainsKey($_) })
    if ($missing.Count -gt 0 -or $unexpected.Count -gt 0) {
        throw "Installed runtime file set mismatch; missing=$($missing -join ','); unexpected=$($unexpected -join ',')"
    }
}

function Assert-Installed([string]$Version, [string]$ExpectedManifest) {
    foreach ($path in @(
        $AppExe,
        $CoreDll,
        (Join-Path $AppDir 'flutter_windows.dll'),
        (Join-Path $AppDir 'vcruntime140.dll'),
        (Join-Path $AppDir 'vcruntime140_1.dll'),
        (Join-Path $AppDir 'msvcp140.dll'),
        (Join-Path $AppDir 'data')
    )) {
        if (-not (Test-Path $path)) { throw "Installed application is incomplete: $path" }
    }
    $displayVersion = (Get-ItemProperty -Path $UninstallKey -Name DisplayVersion).DisplayVersion
    if ($displayVersion -ne $Version) {
        throw "Installed version is $displayVersion, expected $Version"
    }
    Assert-RuntimeManifest $ExpectedManifest
}

function Assert-ObsoleteRuntimeFiles([bool]$ExpectedToExist) {
    foreach ($relative in $ObsoleteRuntimeFiles) {
        $parts = @($relative -split '/')
        if ([string]::IsNullOrWhiteSpace($relative) -or
            [IO.Path]::IsPathRooted($relative) -or
            $parts -contains '..') {
            throw "Obsolete runtime fixture has an invalid path: $relative"
        }
        $path = Join-Path $AppDir $relative.Replace('/', '\')
        $exists = Test-Path -LiteralPath $path -PathType Leaf
        if ($exists -ne $ExpectedToExist) {
            $expectation = if ($ExpectedToExist) { 'installed' } else { 'removed during upgrade' }
            throw "Obsolete runtime fixture was not $expectation`: $relative"
        }
    }
}

function Assert-PreservedExternalState {
    foreach ($sentinel in @(
        @{ Name = 'support'; Path = $SupportSentinel; Hash = $ExpectedSupportSentinelHash },
        @{ Name = 'cache'; Path = $CacheSentinel; Hash = $ExpectedCacheSentinelHash }
    )) {
        if (-not (Test-Path -LiteralPath $sentinel.Path -PathType Leaf)) {
            throw "LocalAppData $($sentinel.Name) state was deleted"
        }
        $actualHash = (Get-FileHash -LiteralPath $sentinel.Path -Algorithm SHA256).Hash
        if (-not $sentinel.Hash -or $actualHash -cne $sentinel.Hash) {
            throw "LocalAppData $($sentinel.Name) state was modified"
        }
    }
    $credentialList = (& cmdkey.exe /list) -join [Environment]::NewLine
    if ($credentialList -notmatch [regex]::Escape($CredentialTarget)) {
        throw 'Credential Manager item was deleted'
    }
}

function Start-AppAndAssertRunning {
    $main = Start-Process -FilePath $AppExe -PassThru
    Start-Sleep -Seconds 8
    if ($main.HasExited) {
        throw "AWikiMe.exe exited during startup with code $($main.ExitCode)"
    }
    return $main
}

function Assert-AppProcessExited([Diagnostics.Process]$Process, [string]$Operation) {
    if (-not $Process.WaitForExit(30000)) {
        throw "AWikiMe.exe did not exit during $Operation"
    }
}

try {
    Invoke-Uninstaller
    Invoke-Installer $BaseInstaller
    Assert-Installed '0.0.0' $ExpectedBaseRuntimeManifest
    Assert-ObsoleteRuntimeFiles $true

    New-Item -ItemType Directory -Force -Path $SupportDir | Out-Null
    New-Item -ItemType Directory -Force -Path $CacheDir | Out-Null
    '{"preserve":"support"}' | Set-Content -Encoding UTF8 -Path $SupportSentinel
    '{"preserve":"cache"}' | Set-Content -Encoding UTF8 -Path $CacheSentinel
    $ExpectedSupportSentinelHash = (Get-FileHash -LiteralPath $SupportSentinel -Algorithm SHA256).Hash
    $ExpectedCacheSentinelHash = (Get-FileHash -LiteralPath $CacheSentinel -Algorithm SHA256).Hash
    & cmdkey.exe "/generic:$CredentialTarget" '/user:awiki-installer-ci' '/pass:not-a-production-secret' | Out-Null
    if ($LASTEXITCODE -ne 0) { throw 'Failed to create Credential Manager test item' }
    Assert-PreservedExternalState

    $upgradeProcess = Start-AppAndAssertRunning
    Invoke-Installer $UpgradeInstaller
    Assert-AppProcessExited $upgradeProcess 'overwrite upgrade'
    Assert-ObsoleteRuntimeFiles $false
    Assert-Installed $ExpectedVersion $ExpectedRuntimeManifest
    Assert-PreservedExternalState

    $repairProcess = Start-AppAndAssertRunning
    Invoke-Installer $UpgradeInstaller
    Assert-AppProcessExited $repairProcess 'same-version repair'
    Assert-Installed $ExpectedVersion $ExpectedRuntimeManifest
    Assert-PreservedExternalState

    Invoke-Installer $BaseInstaller -ExpectFailure
    Assert-Installed $ExpectedVersion $ExpectedRuntimeManifest
    Assert-PreservedExternalState

    $uninstallProcess = Start-AppAndAssertRunning
    Invoke-Uninstaller
    Assert-AppProcessExited $uninstallProcess 'running-app uninstall'
    if (Test-Path -LiteralPath $AppDir) {
        throw 'Application directory remains after uninstall'
    }
    if (Test-Path -LiteralPath $UninstallKey) {
        throw 'Uninstall registration remains after uninstall'
    }
    Assert-PreservedExternalState
}
finally {
    try { Invoke-Uninstaller } catch { Write-Warning $_ }
    & cmdkey.exe "/delete:$CredentialTarget" | Out-Null
    Remove-Item -Force -ErrorAction SilentlyContinue $SupportSentinel
    Remove-Item -Force -ErrorAction SilentlyContinue $CacheSentinel
}

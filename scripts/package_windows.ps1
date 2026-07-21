[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)][ValidateSet('windows-x64')][string]$Target,
    [Parameter(Mandatory = $true)][string]$Version,
    [Parameter(Mandatory = $true)][int]$BuildNumber,
    [Parameter(Mandatory = $true)][string]$AppRef,
    [Parameter(Mandatory = $true)][string]$CoreRef,
    [Parameter(Mandatory = $true)][string]$AnpRef,
    [Parameter(Mandatory = $true)][string]$PrimaryTenantDomain,
    [Parameter(Mandatory = $true)][string]$OutputDir,
    [string]$CoreDir = (Join-Path $PSScriptRoot '..\..\awiki-cli-rs2'),
    [string]$AnpDir = (Join-Path $PSScriptRoot '..\..\anp\anp'),
    [string]$InnoCompiler = ''
)

$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest

$RootDir = (Resolve-Path (Join-Path $PSScriptRoot '..')).Path
$CoreDir = (Resolve-Path $CoreDir).Path
$AnpDir = (Resolve-Path $AnpDir).Path
$OutputDir = [IO.Path]::GetFullPath($OutputDir)
$RuntimeManifestName = 'awiki-runtime-manifest.json'
$RuntimeFileListName = 'awiki-runtime-files.txt'

function Assert-ExitCode([string]$Label) {
    if ($LASTEXITCODE -ne 0) {
        throw "$Label failed with exit code $LASTEXITCODE"
    }
}

function Read-GitRef([string]$Directory) {
    $value = (& git -C $Directory rev-parse 'HEAD^{commit}').Trim()
    Assert-ExitCode "git rev-parse in $Directory"
    return $value
}

function Find-VsWhere {
    $candidate = Join-Path ${env:ProgramFiles(x86)} 'Microsoft Visual Studio\Installer\vswhere.exe'
    if (-not (Test-Path $candidate)) {
        throw 'Visual Studio vswhere.exe was not found'
    }
    return $candidate
}

function Find-InnoCompiler {
    if ($InnoCompiler -and (Test-Path $InnoCompiler)) {
        return (Resolve-Path $InnoCompiler).Path
    }
    $command = Get-Command ISCC.exe -ErrorAction SilentlyContinue
    if ($command) {
        return $command.Source
    }
    $candidate = Join-Path ${env:ProgramFiles(x86)} 'Inno Setup 6\ISCC.exe'
    if (Test-Path $candidate) {
        return $candidate
    }
    throw 'Inno Setup 6 ISCC.exe was not found'
}

function Compile-Installer(
    [string]$Compiler,
    [string]$AppSourceDir,
    [string]$InstallerVersion,
    [string]$OutputBaseFilename,
    [string]$Destination
) {
    New-Item -ItemType Directory -Force -Path $Destination | Out-Null
    $numericVersion = ($InstallerVersion -split '-')[0]
    $versionInfoVersion = "$numericVersion.$BuildNumber"
    & $Compiler `
        "/DMyAppSourceDir=$AppSourceDir" `
        "/DMySetupIcon=$(Join-Path $RootDir 'windows\runner\resources\app_icon.ico')" `
        "/DMyAppVersion=$InstallerVersion" `
        "/DMyVersionInfoVersion=$versionInfoVersion" `
        "/DMyBuildNumber=$BuildNumber" `
        "/DMyOutputDir=$Destination" `
        "/DMyOutputBaseFilename=$OutputBaseFilename" `
        (Join-Path $RootDir 'installer\windows\awiki-me.iss')
    Assert-ExitCode 'Inno Setup compiler'
}

function Write-RuntimeManifest(
    [string]$StageDirectory,
    [string]$ManifestVersion,
    [string]$ExpectedManifest
) {
    $manifestPath = Join-Path $StageDirectory $RuntimeManifestName
    $fileListPath = Join-Path $StageDirectory $RuntimeFileListName
    Remove-Item -LiteralPath $manifestPath -Force -ErrorAction SilentlyContinue
    Remove-Item -LiteralPath $fileListPath -Force -ErrorAction SilentlyContinue
    $ownedPaths = @(
        Get-ChildItem -LiteralPath $StageDirectory -Recurse -File |
            Sort-Object FullName |
            ForEach-Object {
                [IO.Path]::GetRelativePath($StageDirectory, $_.FullName).Replace('\', '/')
            }
    )
    if ($ownedPaths.Count -eq 0) {
        throw 'Windows runtime stage is empty'
    }
    $ownedPaths += $RuntimeFileListName
    $ownedPaths += $RuntimeManifestName
    $ownedPaths = @($ownedPaths | Sort-Object -Unique)
    [IO.File]::WriteAllLines(
        $fileListPath,
        [string[]]$ownedPaths,
        [System.Text.UTF8Encoding]::new($false)
    )
    $entries = @(
        Get-ChildItem -LiteralPath $StageDirectory -Recurse -File |
            Sort-Object FullName |
            ForEach-Object {
                $relativePath = [IO.Path]::GetRelativePath($StageDirectory, $_.FullName).Replace('\', '/')
                [ordered]@{
                    path = $relativePath
                    sizeBytes = [int64]$_.Length
                    sha256 = (Get-FileHash -LiteralPath $_.FullName -Algorithm SHA256).Hash.ToLowerInvariant()
                }
            }
    )
    $manifestData = [ordered]@{
        schemaVersion = 1
        version = $ManifestVersion
        buildNumber = $BuildNumber
        sourceRefs = [ordered]@{
            app = $AppRef
            imCore = $CoreRef
            anp = $AnpRef
        }
        files = $entries
    }
    $manifestData | ConvertTo-Json -Depth 6 | Set-Content -LiteralPath $manifestPath -Encoding utf8
    Copy-Item -LiteralPath $manifestPath -Destination $ExpectedManifest -Force
}

if ($Version -notmatch '^\d+\.\d+\.\d+([-.][0-9A-Za-z.-]+)?$') {
    throw "Invalid semantic version: $Version"
}
if ($BuildNumber -le 0) {
    throw 'BuildNumber must be greater than zero'
}
foreach ($ref in @($AppRef, $CoreRef, $AnpRef)) {
    if ($ref -cnotmatch '^[0-9a-f]{40}$') {
        throw 'Source refs must be lowercase 40-character SHAs'
    }
}
if ((Read-GitRef $RootDir) -ne $AppRef) { throw 'APP checkout ref mismatch' }
if ((Read-GitRef $CoreDir) -ne $CoreRef) { throw 'Core checkout ref mismatch' }
if ((Read-GitRef $AnpDir) -ne $AnpRef) { throw 'ANP checkout ref mismatch' }

$flutterOutput = @(& flutter --version)
Assert-ExitCode 'flutter --version'
$flutterVersionLine = $flutterOutput | Where-Object { $_ -match '^Flutter\s+\S+' } | Select-Object -Last 1
$flutterVersion = if ($flutterVersionLine -match '^Flutter\s+(\S+)') { $Matches[1] } else { '' }
if ($flutterVersion -ne '3.44.0') {
    throw "Flutter must be 3.44.0, got $flutterVersion"
}
Push-Location $CoreDir
try {
    $rustVersion = ((& rustc --version) -split '\s+')[1]
    Assert-ExitCode 'rustc --version'
    if ($rustVersion -ne '1.88.0') {
        throw "Rust must be 1.88.0, got $rustVersion"
    }
    $coreBuild = Join-Path $CoreDir 'scripts\flutter\build-windows.ps1'
    if (-not (Test-Path $coreBuild)) {
        throw "Core Windows build script is missing: $coreBuild"
    }
    & $coreBuild
    Assert-ExitCode 'Core Windows native build'
}
finally {
    Pop-Location
}

Push-Location $RootDir
try {
    & flutter pub get
    Assert-ExitCode 'flutter pub get'
    & flutter build windows `
        --release `
        --no-pub `
        "--dart-define=AWIKI_PRIMARY_TENANT_DOMAIN=$PrimaryTenantDomain" `
        "--dart-define=AWIKI_APP_SOURCE_REF=$AppRef" `
        "--dart-define=AWIKI_IM_CORE_SOURCE_REF=$CoreRef" `
        --build-name $Version `
        --build-number $BuildNumber
    Assert-ExitCode 'flutter build windows'
}
finally {
    Pop-Location
}

$ReleaseDir = Join-Path $RootDir 'build\windows\x64\runner\Release'
$Executable = Join-Path $ReleaseDir 'AWikiMe.exe'
$CoreDll = Join-Path $ReleaseDir 'awiki_im_core.dll'
foreach ($required in @(
    $Executable,
    $CoreDll,
    (Join-Path $ReleaseDir 'flutter_windows.dll'),
    (Join-Path $ReleaseDir 'data')
)) {
    if (-not (Test-Path $required)) {
        throw "Windows release output is incomplete: $required"
    }
}

$vswhere = Find-VsWhere
$vsPath = (& $vswhere -latest -products * -requires Microsoft.VisualStudio.Component.VC.ATL -property installationPath).Trim()
if (-not $vsPath) {
    throw 'Visual Studio 2022 with the x64 ATL component is required'
}
$windowsSdkLib = Join-Path ${env:ProgramFiles(x86)} 'Windows Kits\10\Lib'
if (-not (Test-Path $windowsSdkLib) -or
    -not (Get-ChildItem $windowsSdkLib -Directory | Where-Object { $_.Name -match '^10\.0\.' })) {
    throw 'A Windows 10/11 SDK was not found'
}
$msvcTools = Get-ChildItem (Join-Path $vsPath 'VC\Tools\MSVC') -Directory | Sort-Object Name -Descending | Select-Object -First 1
$dumpbin = Join-Path $msvcTools.FullName 'bin\Hostx64\x64\dumpbin.exe'
if (-not (Test-Path $dumpbin)) {
    throw "dumpbin.exe was not found: $dumpbin"
}
$headers = (& $dumpbin /headers $CoreDll) -join "`n"
Assert-ExitCode 'dumpbin /headers'
if ($headers -notmatch '8664 machine \(x64\)') {
    throw 'awiki_im_core.dll is not an x64 PE image'
}
$exports = (& $dumpbin /exports $CoreDll) -join "`n"
Assert-ExitCode 'dumpbin /exports'
foreach ($symbol in @(
    'frb_get_rust_content_hash',
    'frb_pde_ffi_dispatcher_primary',
    'frb_pde_ffi_dispatcher_sync',
    'frb_dart_fn_deliver_output'
)) {
    if ($exports -notmatch [regex]::Escape($symbol)) {
        throw "awiki_im_core.dll is missing export $symbol"
    }
}

$redistRoot = Join-Path $msvcTools.FullName '..\..\..\Redist\MSVC'
$crtDirectory = Get-ChildItem $redistRoot -Directory -ErrorAction SilentlyContinue |
    Sort-Object Name -Descending |
    ForEach-Object { Join-Path $_.FullName 'x64\Microsoft.VC143.CRT' } |
    Where-Object { Test-Path $_ } |
    Select-Object -First 1
if (-not $crtDirectory) {
    throw 'Microsoft.VC143.CRT x64 redistributable directory was not found'
}
$runtimeDlls = @(Get-ChildItem -LiteralPath $crtDirectory -Filter '*.dll' -File | Sort-Object Name)
if ($runtimeDlls.Count -eq 0) {
    throw 'Microsoft.VC143.CRT does not contain any x64 runtime DLLs'
}
foreach ($requiredRuntime in @('vcruntime140.dll', 'vcruntime140_1.dll', 'msvcp140.dll')) {
    if ($requiredRuntime -notin $runtimeDlls.Name) {
        throw "Required MSVC runtime DLL is missing: $requiredRuntime"
    }
}
foreach ($runtimeDll in $runtimeDlls) {
    Copy-Item -LiteralPath $runtimeDll.FullName -Destination (Join-Path $ReleaseDir $runtimeDll.Name) -Force
}

$StageRoot = Join-Path $RootDir 'build\package\windows-x64'
$AppStage = Join-Path $StageRoot 'app'
if (Test-Path $StageRoot) { Remove-Item -Recurse -Force $StageRoot }
New-Item -ItemType Directory -Force -Path $AppStage | Out-Null
Copy-Item (Join-Path $ReleaseDir '*') $AppStage -Recurse -Force
$ExpectedRuntimeManifest = Join-Path $StageRoot "expected-$RuntimeManifestName"
Write-RuntimeManifest $AppStage $Version $ExpectedRuntimeManifest

$compiler = Find-InnoCompiler
if (-not (Test-Path (Join-Path $RootDir 'windows\runner\resources\app_icon.ico'))) {
    throw 'Windows runner app_icon.ico is required for the installer'
}
$CurrentBaseName = "AWiki-Me-$Version-windows-x64"
Compile-Installer $compiler $AppStage $Version $CurrentBaseName $OutputDir
$Installer = Join-Path $OutputDir "$CurrentBaseName.exe"
if (-not (Test-Path $Installer)) {
    throw "Expected installer was not produced: $Installer"
}
$installerHash = (Get-FileHash -LiteralPath $Installer -Algorithm SHA256).Hash.ToLowerInvariant()
if ($installerHash -notmatch '^[0-9a-f]{64}$') {
    throw 'Windows installer SHA-256 could not be computed'
}
Write-Output "Windows installer SHA-256: $installerHash"

# A lower-version fixture contains files that do not exist in the upgrade. It
# proves overwrite cleanup as well as downgrade and data-preservation behavior.
$FixtureDir = Join-Path $StageRoot 'fixtures'
$FixtureBaseName = 'AWiki-Me-test-base'
$BaseAppStage = Join-Path $StageRoot 'base-app'
New-Item -ItemType Directory -Force -Path $BaseAppStage | Out-Null
Copy-Item (Join-Path $AppStage '*') $BaseAppStage -Recurse -Force
$ObsoleteRuntimeFiles = @(
    'obsolete-runtime-fixture.dll'
    'data/flutter_assets/obsolete-runtime-fixture.txt'
)
Set-Content `
    -LiteralPath (Join-Path $BaseAppStage $ObsoleteRuntimeFiles[0]) `
    -Value 'obsolete DLL fixture' `
    -Encoding utf8
$obsoleteAsset = Join-Path $BaseAppStage $ObsoleteRuntimeFiles[1].Replace('/', '\')
New-Item -ItemType Directory -Force -Path (Split-Path -Parent $obsoleteAsset) | Out-Null
Set-Content -LiteralPath $obsoleteAsset -Value 'obsolete data fixture' -Encoding utf8
$ExpectedBaseRuntimeManifest = Join-Path $StageRoot "expected-base-$RuntimeManifestName"
Write-RuntimeManifest $BaseAppStage '0.0.0' $ExpectedBaseRuntimeManifest
Compile-Installer $compiler $BaseAppStage '0.0.0' $FixtureBaseName $FixtureDir
$BaseInstaller = Join-Path $FixtureDir "$FixtureBaseName.exe"
& (Join-Path $PSScriptRoot 'windows\verify_installer.ps1') `
    -BaseInstaller $BaseInstaller `
    -UpgradeInstaller $Installer `
    -ExpectedVersion $Version `
    -ExpectedBaseRuntimeManifest $ExpectedBaseRuntimeManifest `
    -ExpectedRuntimeManifest $ExpectedRuntimeManifest `
    -ObsoleteRuntimeFiles $ObsoleteRuntimeFiles
Assert-ExitCode 'Windows installer verification'

Copy-Item -LiteralPath $ExpectedRuntimeManifest -Destination (Join-Path $OutputDir $RuntimeManifestName) -Force
$runtimeFileSummary = @(
    'AWikiMe.exe'
    'awiki_im_core.dll'
    'flutter_windows.dll'
    'data'
    $RuntimeManifestName
    $RuntimeFileListName
    $runtimeDlls.Name
) | Sort-Object -Unique

Push-Location $RootDir
try {
    & dart run tool/package_manifest.dart metadata `
        --target $Target `
        --filename "$CurrentBaseName.exe" `
        --signing-state unsigned `
        --version $Version `
        --build-number $BuildNumber `
        --app-ref $AppRef `
        --core-ref $CoreRef `
        --anp-ref $AnpRef `
        --runtime-files ($runtimeFileSummary -join ',') `
        --output (Join-Path $OutputDir 'artifact-metadata.json')
    Assert-ExitCode 'Windows artifact metadata generation'
}
finally {
    Pop-Location
}

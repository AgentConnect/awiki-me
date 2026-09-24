# Explicit source-build verification packaging; never publishes a release.
[CmdletBinding()]
param(
  [Parameter(Mandatory=$true)][ValidatePattern('^\d+\.\d+\.\d+[-.0-9A-Za-z]*$')][string]$Version,
  [Parameter(Mandatory=$true)][int]$BuildNumber,
  [Parameter(Mandatory=$true)][ValidatePattern('^[0-9a-f]{40}$')][string]$CoreRef
)
$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest
if ($env:AWIKI_SOURCE_INTEGRATION -ne '1' -or $env:AWIKI_RELEASE_REGISTRY -eq '1') { throw 'Explicit source integration required' }
$RootDir = (Resolve-Path (Join-Path $PSScriptRoot '../..')).Path
$CoreDir = (Resolve-Path (Join-Path $RootDir '../awiki-cli-rs2')).Path
$AppRef = (git -C $RootDir rev-parse HEAD).Trim()
if ((git -C $CoreDir rev-parse HEAD).Trim() -ne $CoreRef) { throw 'Core source mismatch' }
$manifest = Get-Content (Join-Path $CoreDir 'dependencies.source.json') -Raw | ConvertFrom-Json
$AnpRef = $manifest.dependencies.anp.commit
$ReleaseDir = Join-Path $RootDir 'build/windows/x64/runner/Release'
$OutputDir = Join-Path $RootDir 'build/windows-verification'
New-Item -ItemType Directory -Force $OutputDir | Out-Null
$vswhere = Join-Path ${env:ProgramFiles(x86)} 'Microsoft Visual Studio/Installer/vswhere.exe'
$vsPath = (& $vswhere -latest -products * -property installationPath).Trim()
$crt = Get-ChildItem (Join-Path $vsPath 'VC/Redist/MSVC') -Directory |
  Sort-Object Name -Descending | ForEach-Object { Join-Path $_.FullName 'x64/Microsoft.VC143.CRT' } |
  Where-Object { Test-Path $_ } | Select-Object -First 1
if (-not $crt) { throw 'x64 CRT missing' }
Copy-Item (Join-Path $crt '*.dll') $ReleaseDir -Force
foreach ($file in @('AWikiMe.exe','awiki_im_core.dll','vcruntime140.dll','msvcp140.dll')) {
  if (-not (Test-Path (Join-Path $ReleaseDir $file))) { throw "Missing runtime $file" }
}
if ((Get-FileHash (Join-Path $ReleaseDir 'data/flutter_assets/assets/security/cacert-2026-08-13.pem') -Algorithm SHA256).Hash.ToLowerInvariant() -ne 'f66dff1bdf8f96060b8177976f8b7d9254bc89bc4db933d769f7384d28480bc9') { throw 'Packaged CA digest mismatch' }
$RuntimeManifestName = 'awiki-runtime-manifest.json'
$RuntimeFileListName = 'awiki-runtime-files.txt'
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

Write-RuntimeManifest $ReleaseDir $Version (Join-Path $OutputDir $RuntimeManifestName)
$compiler = Join-Path ${env:ProgramFiles(x86)} 'Inno Setup 6/ISCC.exe'
& $compiler "/DMyAppSourceDir=$ReleaseDir" "/DMySetupIcon=$RootDir/windows/runner/resources/app_icon.ico" `
  "/DMyAppVersion=$Version" "/DMyVersionInfoVersion=$(($Version -split '-')[0]).$BuildNumber" `
  "/DMyBuildNumber=$BuildNumber" "/DMyOutputDir=$OutputDir" "/DMyOutputBaseFilename=AWikiMe-$Version-windows-x64-test" `
  (Join-Path $RootDir 'installer/windows/awiki-me.iss')
if ($LASTEXITCODE -ne 0) { throw 'Installer compilation failed' }
Copy-Item (Join-Path $CoreDir 'dependencies.source.json') (Join-Path $OutputDir 'core-dependencies.source.json')
Copy-Item (Join-Path $CoreDir '.artifacts/dependencies/source/resolution.json') (Join-Path $OutputDir 'core-resolution.json')
Copy-Item (Join-Path $CoreDir '.artifacts/dependencies/source/command-result.json') (Join-Path $OutputDir 'core-command-result.json')
Get-ChildItem $OutputDir -Filter '*.exe' | ForEach-Object {
  "$((Get-FileHash $_.FullName -Algorithm SHA256).Hash.ToLowerInvariant())  $($_.Name)"
} | Set-Content (Join-Path $OutputDir 'SHA256SUMS') -Encoding utf8

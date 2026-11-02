#requires -Version 7.0
[CmdletBinding()]
param(
  [Parameter(Mandatory=$true)][string]$ConfigPath,
  [Parameter(Mandatory=$true)][string]$PinFixturePath,
  [string]$OtpPresetPath,
  [string]$PythonBin,
  [string]$RegistrationFixturePath,
  [string]$RegistrationDiscoveryFixturePath,
  [string]$HostedFixturePath,
  [string]$HostedPhoneFixturePath,
  [string]$Case = 'full',
  [string[]]$CaseId = @(),
  [string]$RunId = ('windows-' + (Get-Date -Format 'yyyyMMdd-HHmmss')),
  [switch]$PrepareOnly
)

Set-StrictMode -Version Latest
$ErrorActionPreference='Stop'
$ProjectRoot=[IO.Path]::GetFullPath((Join-Path $PSScriptRoot '..'))
$WorkspaceRoot=Split-Path $ProjectRoot
if(-not $IsWindows -or [Runtime.InteropServices.RuntimeInformation]::OSArchitecture -ne 'X64'){
  throw 'Native Windows x64 is required; WSL is not a Windows E2E lane.'
}
if($RunId -notmatch '^[A-Za-z0-9][A-Za-z0-9_-]{0,80}$' -or $Case -notmatch '^[a-z0-9-]+$'){
  throw 'Invalid case or run ID.'
}
$ConfigPath=(Resolve-Path -LiteralPath $ConfigPath).Path
$PinFixturePath=(Resolve-Path -LiteralPath $PinFixturePath).Path
if($OtpPresetPath){$OtpPresetPath=(Resolve-Path -LiteralPath $OtpPresetPath).Path}
$keys=@('PATH','PUB_HOSTED_URL','CARGO_NET_GIT_FETCH_WITH_CLI','AWIKI_SYSTEM_TEST_MODE',
  'AWIKI_SYSTEM_TEST_TARGET','AWIKI_MULTI_DEVICE_REMOTE_JOIN_E2E_ENABLED',
  'AWIKI_MULTI_DEVICE_REMOTE_RECOVERY_E2E_ENABLED','AWIKI_PIN_RECOVERY_E2E_FIXTURE',
  'AWIKI_E2E_WINDOWS_PTY_BRIDGE','AWIKI_E2E_NODE_BIN','AWIKI_E2E_PYTHON_BIN','CARGO_BUILD_JOBS',
  'AWIKI_E2E_CLI_BINARY','AWIKI_E2E_CLI_SOURCE_REF','AWIKI_MESSAGE_SYNC_V2_RECOVERY_E2E',
  'AWIKI_MULTI_DEVICE_E2E_OPERATOR_MODE','AWIKI_ACCOUNT_STATE_V1_E2E',
  'AWIKI_ACCOUNT_STATE_E2E_OPERATOR_COMMAND_JSON','AWIKI_ACCOUNT_STATE_TEST_FAILPOINTS_ENABLED',
  'UV_PROJECT_ENVIRONMENT')
$keys+=@('AWIKI_REGISTRATION_FIXTURE','AWIKI_REGISTRATION_DISCOVERY_FIXTURE',
  'AWIKI_HOSTED_FIXTURE_PATH','AWIKI_HOSTED_PHONE_FIXTURE_PATH','PYTHONPATH',
  'AWIKI_E2E_AGENT_AVATAR_FIXTURE_COMMAND')
$previous=@{}
foreach($key in $keys){$previous[$key]=[Environment]::GetEnvironmentVariable($key,'Process')}
Push-Location $ProjectRoot
try{
  $fixturePaths=@{
    AWIKI_REGISTRATION_FIXTURE=$RegistrationFixturePath
    AWIKI_REGISTRATION_DISCOVERY_FIXTURE=$RegistrationDiscoveryFixturePath
    AWIKI_HOSTED_FIXTURE_PATH=$HostedFixturePath
    AWIKI_HOSTED_PHONE_FIXTURE_PATH=$HostedPhoneFixturePath
  }
  foreach($entry in $fixturePaths.GetEnumerator()){
    if($entry.Value){
      $fixturePath=(Resolve-Path -LiteralPath $entry.Value).Path
      [Environment]::SetEnvironmentVariable($entry.Key,$fixturePath,'Process')
    }
  }
  foreach($folder in @((Join-Path $WorkspaceRoot '.tools/flutter/bin'),
      (Join-Path $WorkspaceRoot '.tools/uv'),
      (Join-Path $WorkspaceRoot '.tools/node-v24.19.0-win-x64'))){
    if(Test-Path -LiteralPath $folder){$env:PATH=$folder+';'+$env:PATH}
  }
  foreach($tool in @('pwsh.exe','git.exe','cargo.exe','node.exe','flutter.bat','dart.bat')){
    if(-not (Get-Command $tool -CommandType Application -ErrorAction SilentlyContinue)){
      throw "Required Windows E2E tool not found: $tool"
    }
  }
  $dart=(Get-Command dart.bat -CommandType Application | Select-Object -First 1).Source
  if($Case -in @('full','pin-recovery')){
    & $dart run tool/check_windows_pin_backend.dart
    if($LASTEXITCODE -ne 0){throw 'Realm configuration is unavailable; repair the reviewed backend before building/running PIN E2E.'}
  }
  $env:AWIKI_E2E_NODE_BIN=(Get-Command node.exe -CommandType Application | Select-Object -First 1).Source
  if(-not $PythonBin){$PythonBin=$env:AWIKI_E2E_PYTHON_BIN}
  if($PythonBin){
    $PythonBin=(Resolve-Path -LiteralPath $PythonBin).Path
    if($PythonBin -match '(?i)\\Microsoft\\WindowsApps\\' -or [IO.Path]::GetExtension($PythonBin) -ne '.exe'){
      throw 'Select native python.exe with -PythonBin; Windows Store aliases are not test interpreters.'
    }
    $pythonPlatform=& $PythonBin -I -c 'import sys,struct; print(sys.platform+":"+str(struct.calcsize("P")*8))'
    if($LASTEXITCODE -ne 0 -or $pythonPlatform -ne 'win32:64'){throw 'Native Windows x64 Python is required.'}
    $env:AWIKI_E2E_PYTHON_BIN=$PythonBin
  }
  if($Case -eq 'full' -and -not $env:AWIKI_E2E_PYTHON_BIN){
    throw 'Full Windows E2E requires -PythonBin pointing to native Python for offline ACP fixtures.'
  }
  if(($Case -eq 'full' -or $Case -eq 'agent-avatars') -and
      -not (Test-Path -LiteralPath (Join-Path $WorkspaceRoot 'awiki-system-test/.venv/Scripts/python.exe'))){
    throw 'Prepare the native Windows awiki-system-test venv for the owning Agent avatar fixture.'
  }
  if($Case -in @('full','agent-avatars')){
    $uv=(Get-Command uv.exe -CommandType Application -ErrorAction Stop).Source
    $systemTestRoot=Join-Path $WorkspaceRoot 'awiki-system-test'
    $env:UV_PROJECT_ENVIRONMENT=Join-Path $systemTestRoot '.venv'
    & $uv sync --project $systemTestRoot --locked --check *> $null
    if($LASTEXITCODE -ne 0){
      throw 'Synchronize the native awiki-system-test environment with uv sync --locked; stale SDK or relocated editable installs cannot attest this run.'
    }
  }
  if(-not $env:CARGO_BUILD_JOBS){$env:CARGO_BUILD_JOBS='2'}
  $needsDsh=$Case -eq 'full' -or ($Case -eq 'multi-device-remote-join' -and
    ($CaseId.Count -eq 0 -or $CaseId -contains 'DEVICE-JOIN-E2E-006'))
  if($needsDsh){
    $dshRoot=Join-Path $WorkspaceRoot 'dsh-awiki'
    $pnpm=(Get-Command pnpm.cmd -CommandType Application -ErrorAction Stop).Source
    if(-not (Test-Path -LiteralPath (Join-Path $dshRoot 'scripts/device-join-e2e.mjs'))){
      throw 'The owning dsh-awiki Device Join driver is required for this suite.'
    }
    Push-Location $dshRoot
    try{
      & $env:AWIKI_E2E_NODE_BIN scripts/check-dependency-sources.mjs
      if($LASTEXITCODE -ne 0){throw 'Prepare the selected DSH dependencies with its owning dependency workflow.'}
      & $pnpm run prepare:test-native
      if($LASTEXITCODE -ne 0){throw 'The selected native Windows DSH providers could not be loaded.'}
      & $pnpm run build
      if($LASTEXITCODE -ne 0){throw 'The current DSH Device Join host could not be built on Windows.'}
    }finally{Pop-Location}
  }
  $env:AWIKI_E2E_WINDOWS_PTY_BRIDGE=Join-Path $ProjectRoot 'tests/e2e/windows/pty_bridge.cjs'
  & $env:AWIKI_E2E_NODE_BIN $env:AWIKI_E2E_WINDOWS_PTY_BRIDGE --check *> $null
  if($LASTEXITCODE -ne 0){
    $npm=(Get-Command npm.cmd -CommandType Application -ErrorAction Stop).Source
    & $npm ci --prefix tests/e2e/windows --ignore-scripts --no-audit --no-fund
    if($LASTEXITCODE -ne 0){throw 'Pinned ConPTY dependencies could not be prepared.'}
    & $env:AWIKI_E2E_NODE_BIN $env:AWIKI_E2E_WINDOWS_PTY_BRIDGE --check
    if($LASTEXITCODE -ne 0){throw 'Native Windows ConPTY is unavailable.'}
  }
  $env:CARGO_NET_GIT_FETCH_WITH_CLI='true'
  if(-not $env:PUB_HOSTED_URL){$env:PUB_HOSTED_URL='https://mirrors.tuna.tsinghua.edu.cn/dart-pub'}
  & $dart run tool/ensure_windows_im_core.dart
  if($LASTEXITCODE -ne 0){throw 'Current Windows SDK could not be verified.'}
  & $dart run tool/prepare_windows_e2e_rust_tools.dart
  if($LASTEXITCODE -ne 0){throw 'Current native Windows CLI/probe/Daemon could not be prepared.'}
  $arguments=@('run','tool/prepare_windows_e2e_environment.dart',"--config=$ConfigPath",
    "--pin-fixture=$PinFixturePath","--run-id=$RunId")
  if($OtpPresetPath){$arguments+="--otp-preset=$OtpPresetPath"}
  $prepared=@(& $dart @arguments)
  if($LASTEXITCODE -ne 0){throw 'Windows protected environment preparation failed.'}
  $environment=($prepared | Where-Object { $_ -match '^\{' } | Select-Object -Last 1) | ConvertFrom-Json
  if(-not $environment -or $environment.platform -ne 'windows' -or
      $environment.serviceOrigin -ne 'https://awiki.info'){
    throw 'The prepared environment did not attest the Windows awiki.info target.'
  }
  $env:AWIKI_SYSTEM_TEST_MODE='remote'
  $env:AWIKI_SYSTEM_TEST_TARGET='awiki-info-testing'
  $env:AWIKI_MULTI_DEVICE_REMOTE_JOIN_E2E_ENABLED='1'
  $env:AWIKI_MULTI_DEVICE_REMOTE_RECOVERY_E2E_ENABLED='1'
  $env:AWIKI_PIN_RECOVERY_E2E_FIXTURE=$environment.pinFixturePath
  $env:AWIKI_E2E_CLI_BINARY=$environment.cliBinary
  $env:AWIKI_E2E_CLI_SOURCE_REF=$environment.cliSourceRef
  if($Case -eq 'full' -or $Case -match 'functional|paging-recovery|agent-avatars'){
    foreach($entry in $environment.operatorEnvironment.PSObject.Properties){
      [Environment]::SetEnvironmentVariable($entry.Name,[string]$entry.Value,'Process')
    }
  }
  $run=@('run','tests/e2e/runner.dart','--case',$Case,'--config',$environment.configPath,
    '--run-id',$RunId)
  foreach($selectedId in $CaseId){$run+=@('--case-id',$selectedId)}
  if($PrepareOnly){$run+='--prepare-only'}
  & $dart @run
  $result=$LASTEXITCODE
  if($result -ne 0){throw "Windows E2E failed with exit code $result; inspect the native report."}
}finally{
  foreach($key in $keys){[Environment]::SetEnvironmentVariable($key,$previous[$key],'Process')}
  Pop-Location
}

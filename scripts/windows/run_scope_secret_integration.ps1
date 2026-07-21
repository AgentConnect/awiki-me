[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)][string]$ReleaseDir
)

$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest

$ReleaseDir = (Resolve-Path $ReleaseDir).Path
$AppExe = Join-Path $ReleaseDir 'AWikiMe.exe'
if (-not (Test-Path -LiteralPath $AppExe -PathType Leaf)) {
    throw "Production scope-secret probe executable is missing: $AppExe"
}

$ScopeId = [guid]::NewGuid().ToString('D').ToLowerInvariant()
$OtherScopeId = [guid]::NewGuid().ToString('D').ToLowerInvariant()
$Account = "scope/$ScopeId"
$CredentialTarget = "ai.awiki.awikime.scope-secrets/$Account"
$ResultRoot = Join-Path `
    ([IO.Path]::GetTempPath()) `
    "awiki-windows-scope-secret-$([guid]::NewGuid().ToString('N'))"
$mismatchEnvelope = $null

$credentialBridge = @'
using System;
using System.ComponentModel;
using System.Runtime.InteropServices;
using System.Text;

public static class AwikiScopeSecretCredentialProbe
{
    private const int CredTypeGeneric = 1;
    private const int CredPersistLocalMachine = 2;
    private const int ErrorNotFound = 1168;

    [StructLayout(LayoutKind.Sequential, CharSet = CharSet.Unicode)]
    private struct Credential
    {
        public int Flags;
        public int Type;
        public string TargetName;
        public string Comment;
        public System.Runtime.InteropServices.ComTypes.FILETIME LastWritten;
        public int CredentialBlobSize;
        public IntPtr CredentialBlob;
        public int Persist;
        public int AttributeCount;
        public IntPtr Attributes;
        public string TargetAlias;
        public string UserName;
    }

    [DllImport("advapi32.dll", EntryPoint = "CredWriteW", CharSet = CharSet.Unicode, SetLastError = true)]
    private static extern bool CredWrite(ref Credential credential, int flags);

    [DllImport("advapi32.dll", EntryPoint = "CredDeleteW", CharSet = CharSet.Unicode, SetLastError = true)]
    private static extern bool CredDelete(string target, int type, int flags);

    public static void WriteUtf8(string target, string account, string value)
    {
        byte[] bytes = Encoding.UTF8.GetBytes(value);
        IntPtr blob = Marshal.AllocCoTaskMem(bytes.Length);
        try
        {
            Marshal.Copy(bytes, 0, blob, bytes.Length);
            var credential = new Credential {
                Type = CredTypeGeneric,
                TargetName = target,
                CredentialBlobSize = bytes.Length,
                CredentialBlob = blob,
                Persist = CredPersistLocalMachine,
                UserName = account
            };
            if (!CredWrite(ref credential, 0))
                throw new Win32Exception(Marshal.GetLastWin32Error(), "CredWriteW failed");
        }
        finally
        {
            for (int index = 0; index < bytes.Length; index++)
                Marshal.WriteByte(blob, index, 0);
            Array.Clear(bytes, 0, bytes.Length);
            Marshal.FreeCoTaskMem(blob);
        }
    }

    public static void Delete(string target)
    {
        if (!CredDelete(target, CredTypeGeneric, 0))
        {
            int error = Marshal.GetLastWin32Error();
            if (error != ErrorNotFound)
                throw new Win32Exception(error, "CredDeleteW failed");
        }
    }
}
'@

Add-Type -TypeDefinition $credentialBridge

function Invoke-ProbePhase([string]$Phase) {
    $resultPath = Join-Path $ResultRoot "$Phase.json"
    Remove-Item -LiteralPath $resultPath -Force -ErrorAction SilentlyContinue

    $startInfo = [Diagnostics.ProcessStartInfo]::new()
    $startInfo.FileName = $AppExe
    $startInfo.UseShellExecute = $false
    $startInfo.ArgumentList.Add("--awiki-scope-probe-phase=$Phase")
    $startInfo.ArgumentList.Add("--awiki-scope-probe-id=$ScopeId")
    $startInfo.ArgumentList.Add("--awiki-scope-probe-result=$resultPath")
    $process = [Diagnostics.Process]::Start($startInfo)
    if ($null -eq $process) {
        throw "Failed to start production scope-secret phase: $Phase"
    }
    try {
        if (-not $process.WaitForExit(30000)) {
            $process.Kill()
            throw "Production scope-secret phase timed out: $Phase"
        }
        if ($process.ExitCode -ne 0) {
            $reportedCode = 'result_missing'
            if (Test-Path -LiteralPath $resultPath -PathType Leaf) {
                $failedResult = Get-Content -LiteralPath $resultPath -Raw | ConvertFrom-Json
                $reportedCode = [string]$failedResult.code
            }
            throw "Production scope-secret phase failed: $Phase ($reportedCode)"
        }
    }
    finally {
        $process.Dispose()
    }

    if (-not (Test-Path -LiteralPath $resultPath -PathType Leaf)) {
        throw "Production scope-secret phase did not write a result: $Phase"
    }
    $result = Get-Content -LiteralPath $resultPath -Raw | ConvertFrom-Json
    if ($result.case_id -ne 'NATIVE-E2E-002' -or
        $result.phase -ne $Phase -or
        $result.status -ne 'passed' -or
        $result.code -ne 'ok') {
        throw "Production scope-secret result contract mismatch: $Phase"
    }
}

function New-ScopeMismatchEnvelope([string]$MismatchedScopeId) {
    $keyBytes = [byte[]]::new(32)
    [Security.Cryptography.RandomNumberGenerator]::Fill($keyBytes)
    try {
        $payload = [ordered]@{
            schema_version = 1
            scope_id = $MismatchedScopeId
            revision = 2
            active_secrets = [ordered]@{
                identity_vault_root = [ordered]@{
                    key_id = [guid]::NewGuid().ToString('D').ToLowerInvariant()
                    key_version = 1
                    algorithm = 'raw-256'
                    material_b64 = [Convert]::ToBase64String($keyBytes)
                }
            }
        }
        return ($payload | ConvertTo-Json -Compress -Depth 6)
    }
    finally {
        [Array]::Clear($keyBytes, 0, $keyBytes.Length)
    }
}

try {
    New-Item -ItemType Directory -Force -Path $ResultRoot | Out-Null
    [AwikiScopeSecretCredentialProbe]::Delete($CredentialTarget)

    Invoke-ProbePhase 'provision'
    Invoke-ProbePhase 'reopen'

    [AwikiScopeSecretCredentialProbe]::WriteUtf8(
        $CredentialTarget,
        $Account,
        '{broken'
    )
    Invoke-ProbePhase 'corrupt'

    $mismatchEnvelope = New-ScopeMismatchEnvelope $OtherScopeId
    [AwikiScopeSecretCredentialProbe]::WriteUtf8(
        $CredentialTarget,
        $Account,
        $mismatchEnvelope
    )
    Invoke-ProbePhase 'scope_mismatch'

    Invoke-ProbePhase 'cleanup'
    Write-Host 'NATIVE-E2E-002 passed on Windows: production MethodChannel and Credential Manager lifecycle verified'
}
finally {
    $mismatchEnvelope = $null
    [AwikiScopeSecretCredentialProbe]::Delete($CredentialTarget)
    Remove-Item -LiteralPath $ResultRoot -Recurse -Force -ErrorAction SilentlyContinue
}

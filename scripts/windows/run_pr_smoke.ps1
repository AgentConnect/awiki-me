[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)][string]$ReleaseDir
)

$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest

$ReleaseDir = (Resolve-Path $ReleaseDir).Path
$AppExe = Join-Path $ReleaseDir 'AWikiMe.exe'
$CredentialTarget = 'ai.awiki.awikime.scope-secrets/scope/00000000-0000-4000-8000-000000000002'
$primary = $null

foreach ($path in @(
    $AppExe,
    (Join-Path $ReleaseDir 'awiki_im_core.dll'),
    (Join-Path $ReleaseDir 'flutter_windows.dll'),
    (Join-Path $ReleaseDir 'data')
)) {
    if (-not (Test-Path $path)) {
        throw "Windows release smoke input is missing: $path"
    }
}

$credentialProbe = @'
using System;
using System.ComponentModel;
using System.Runtime.InteropServices;
using System.Text;

public static class AwikiCredentialManagerProbe
{
    private const int CredTypeGeneric = 1;
    private const int CredPersistLocalMachine = 2;

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

    [DllImport("advapi32.dll", EntryPoint = "CredReadW", CharSet = CharSet.Unicode, SetLastError = true)]
    private static extern bool CredRead(string target, int type, int flags, out IntPtr credential);

    [DllImport("advapi32.dll", EntryPoint = "CredDeleteW", CharSet = CharSet.Unicode, SetLastError = true)]
    private static extern bool CredDelete(string target, int type, int flags);

    [DllImport("advapi32.dll", SetLastError = false)]
    private static extern void CredFree(IntPtr buffer);

    public static void RoundTrip(string target)
    {
        byte[] expected = Encoding.UTF8.GetBytes("awiki-scope-secret-envelope-v1");
        IntPtr blob = Marshal.AllocCoTaskMem(expected.Length);
        try
        {
            Marshal.Copy(expected, 0, blob, expected.Length);
            var credential = new Credential {
                Type = CredTypeGeneric,
                TargetName = target,
                CredentialBlobSize = expected.Length,
                CredentialBlob = blob,
                Persist = CredPersistLocalMachine,
                UserName = "scope/00000000-0000-4000-8000-000000000002"
            };
            if (!CredWrite(ref credential, 0))
                throw new Win32Exception(Marshal.GetLastWin32Error(), "CredWriteW failed");
        }
        finally
        {
            Marshal.FreeCoTaskMem(blob);
        }

        IntPtr readPointer;
        if (!CredRead(target, CredTypeGeneric, 0, out readPointer))
            throw new Win32Exception(Marshal.GetLastWin32Error(), "CredReadW failed");
        try
        {
            var read = (Credential)Marshal.PtrToStructure(readPointer, typeof(Credential));
            byte[] actual = new byte[read.CredentialBlobSize];
            Marshal.Copy(read.CredentialBlob, actual, 0, actual.Length);
            if (!Convert.ToBase64String(actual).Equals(Convert.ToBase64String(expected), StringComparison.Ordinal))
                throw new InvalidOperationException("CredentialBlob roundtrip mismatch");
        }
        finally
        {
            CredFree(readPointer);
        }
    }

    public static void Delete(string target)
    {
        if (!CredDelete(target, CredTypeGeneric, 0))
        {
            int error = Marshal.GetLastWin32Error();
            if (error != 1168)
                throw new Win32Exception(error, "CredDeleteW failed");
        }
    }
}
'@

Add-Type -TypeDefinition $credentialProbe

try {
    [AwikiCredentialManagerProbe]::Delete($CredentialTarget)
    [AwikiCredentialManagerProbe]::RoundTrip($CredentialTarget)

    $primary = Start-Process -FilePath $AppExe -PassThru
    Start-Sleep -Seconds 10
    if ($primary.HasExited) {
        throw "Primary AWikiMe.exe exited during startup with code $($primary.ExitCode)"
    }

    $secondary = Start-Process -FilePath $AppExe -PassThru -Wait
    if ($secondary.ExitCode -ne 0) {
        throw "Second-instance activation failed with code $($secondary.ExitCode)"
    }
    if ($primary.HasExited) {
        throw 'Primary AWikiMe.exe exited when the second instance activated it'
    }

    $shutdown = Start-Process `
        -FilePath $AppExe `
        -ArgumentList '--shutdown-for-update' `
        -PassThru `
        -Wait
    if ($shutdown.ExitCode -ne 0) {
        throw "shutdownForUpdate failed with code $($shutdown.ExitCode)"
    }
    if (-not $primary.WaitForExit(30000)) {
        throw 'Primary AWikiMe.exe did not exit within 30 seconds'
    }
}
finally {
    [AwikiCredentialManagerProbe]::Delete($CredentialTarget)
    if ($null -ne $primary -and -not $primary.HasExited) {
        Stop-Process -Id $primary.Id -Force -ErrorAction SilentlyContinue
    }
}

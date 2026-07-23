# Windows x64 packaging

AWiki Me packages one Windows x64 application for Windows 10 22H2 and Windows
11 with Flutter 3.44.0, Rust 1.88.0, the `x86_64-pc-windows-msvc` target, the
Visual Studio 2022 ATL toolchain, and Inno Setup 6.3.2. The same x64 package
runs natively on x64 Windows and through the operating system's x64 emulation
on Windows 11 ARM64. It is not a native ARM64 build. The result is an unsigned
per-user installer:

```text
AWiki-Me-Windows-x64-<version>.exe
```

The installer defaults program files to
`%LOCALAPPDATA%\Programs\AWiki Me`, lets the user choose another directory on a
first install, and reuses that directory automatically for upgrades and repairs.
Its Inno architecture matcher is `x64compatible`, so one x64 installer accepts
both native x64 Windows and x64-compatible Windows 11 ARM64 systems.
It never removes product data under `%LOCALAPPDATA%\AWiki\AWikiMe` or AWiki
Credential Manager entries during an upgrade, repair, or uninstall. Windows may
display a SmartScreen warning because this phase intentionally does not sign the
installer.

## Source and workflow contract

`scripts/package_app.sh` is the only local entry point. It does not compile an
application and never changes `pubspec.yaml`. Before dispatch it requires:

- clean `awiki-me` and `awiki-cli-rs2` worktrees;
- a configured upstream for each current branch;
- each local HEAD to equal the exact remote branch tip;
- an exact APP, IM Core, and ANP 40-character commit SHA; and
- the ANP SHA to match `awiki-cli-rs2/scripts/release/cli/release-config.json`.

The script resolves the repository's current default branch and dispatches the
stable `.github/workflows/package-app.yml` controller from that branch with a
unique UUID. The APP and Core source revisions remain the exact commits from
their independently selected, pushed branches. The script waits for that exact
run, downloads only its aggregate artifact, and verifies every size and SHA-256
before installing it locally. A complete four-target run atomically replaces
`dist/<version>/` and `dist/latest.json`. A strict target subset is stored under
`dist/validation/<version>+<build>/<request-id>/` and cannot replace the global
latest manifest.

The default branch registers and protects the packaging workflow; it is not the
required source branch for a release. Any reviewed APP and Core branch can be
packaged without first merging its source into the default branch.

The workflow uploads Actions artifacts only. It does not create a GitHub Release,
upload to a web server, alter public download configuration, or publish an
automatic update.

## Protected Environment

Repository administrators must create a protected GitHub Environment named
`app-packaging`. Configure these Environment secrets without committing their
contents:

| Secret | Purpose |
| --- | --- |
| `AWIKI_CI_READ_TOKEN` | Fine-grained, read-only access to private `AgentConnect/awiki-cli-rs2` |
| `AWIKI_ANDROID_KEYSTORE_BASE64` | Base64-encoded existing Android debug keystore used by the current product release policy |
| `AWIKI_ANDROID_STORE_PASSWORD` | Android keystore password |
| `AWIKI_ANDROID_KEY_ALIAS` | Android signing alias |
| `AWIKI_ANDROID_KEY_PASSWORD` | Android key password |
| `AWIKI_MACOS_P12_BASE64` | Base64-encoded Apple signing identity bundle |
| `AWIKI_MACOS_P12_PASSWORD` | Apple identity bundle password |
| `AWIKI_MACOS_SIGNING_IDENTITY` | Exact non-ad-hoc codesign identity name |
| `AWIKI_MACOS_DEVELOPMENT_TEAM` | Matching ten-character Apple Team ID |

Pull-request CI must not read these secrets. The full package workflow is a
manual `workflow_dispatch` job registered on the default branch. The Environment
has no required reviewer or wait timer, and its deployment policy only permits
the default controller branch.

Repository variable `AWIKI_APP_RELEASE_ACTORS` contains a non-empty JSON array
of GitHub logins allowed to package the App, for example `["smartGrey"]`. An
unprivileged authorization job validates the initial request. Every job that
enters `app-packaging` independently rechecks both the original actor and the
re-run actor on every attempt. Each release operator uses an individual GitHub
account with two-factor authentication; release accounts and tokens are never
shared between computers.

Android intentionally retains the existing debug signing identity in this
phase. The worker continues to require certificate SHA-256
`F2:67:E9:18:57:54:ED:C1:2B:E5:69:69:1B:39:B9:EF:D4:EF:1E:CF:2D:7E:D8:18:81:42:69:B3:70:85:D8:75`.
The APK remains a non-debuggable release-mode arm64 package; retaining this
certificate preserves overwrite-install compatibility with existing builds.
Changing the Android signing identity is outside this release scope.

## Targets

`scripts/package_app.config` accepts any non-empty subset of:

```text
android-arm64
macos-arm64
macos-x64
windows-x64
```

The default is the complete four-platform set. A local override can select a
smaller subset for a focused package run:

```bash
# scripts/package_app.local.config (Git-ignored)
PACKAGE_TARGETS="windows-x64"

scripts/package_app.sh
```

A one-off target selection should be made in the Git-ignored local config. The
tracked configuration keeps the complete four-target default, and the packaging
entry refuses a dirty source worktree. Each run is self-contained: a later
four-target run rebuilds every platform and never splices in a prior subset.

## Installer lifecycle

The runner executable is `AWikiMe.exe`. Before overwriting an installed copy,
Inno invokes:

```text
AWikiMe.exe --shutdown-for-update
```

The second process asks the primary instance to shut down and returns only after
the primary instance has released the desktop shell. A non-zero result aborts
installation, so a running DLL is never overwritten. The installer permits a
same-version repair and a higher-version overwrite, but rejects a downgrade.

The Start menu contains launch and uninstall shortcuts. The launch and
optional desktop shortcuts use AUMID `AWiki.AWikiMe`. Toast initialization uses
GUID `42f66431-9bea-46c4-ac14-475b9044a2be`; those identities must remain stable
across upgrades.

The Windows ICO is generated deterministically from the canonical macOS 1024px
app icon. Regenerate it after changing that source, or verify the committed ICO
without writing it:

```bash
dart run tool/generate_windows_icon.dart
dart run tool/generate_windows_icon.dart --check
```

The packaging worker runs the check before compiling the Windows executable and
installer.

## Verification

The Windows worker verifies the PE x64 machine type, required FRB exports,
`flutter_windows.dll`, `awiki_im_core.dll`, the Flutter `data` directory, and
copies the complete x64 `Microsoft.VC143.CRT` DLL set from Visual Studio 2022
into the application. The installer uses these app-local DLLs and never launches
a machine-wide runtime installer, so the per-user installation stays
non-elevated. The worker writes a recursive runtime manifest with the size and
SHA-256 of every staged file, compiles one Release installer, computes its
SHA-256, and emits artifact metadata. The aggregate job independently recomputes
the digest before producing the selected package set.

Shared analysis and automated tests remain outside the packaging workflow and
run through the existing development validation process. The packaging workflow
does not run a Windows-only Debug, Credential Manager, application smoke, or
installer-lifecycle test suite. `scripts/windows/verify_installer.ps1` remains an
explicit development tool. MSVC and Inno compilation require the `windows-2022`
GitHub runner; DPI, tray, screenshot, font, and file-dialog behavior remain
Windows VM acceptance checks.

# Windows x64 packaging

AWiki Me packages Windows 10 22H2 and Windows 11 x64 with Flutter 3.44.0,
Rust 1.88.0, the `x86_64-pc-windows-msvc` target, the Visual Studio 2022 ATL
toolchain, and Inno Setup 6.3.2. The result is an unsigned per-user installer:

```text
AWiki-Me-<version>-windows-x64.exe
```

The installer writes program files to
`%LOCALAPPDATA%\Programs\AWiki Me`. It never removes product data under
`%LOCALAPPDATA%\AWiki\AWikiMe` or AWiki Credential Manager entries during an
upgrade, repair, or uninstall. Windows may display a SmartScreen warning because
this phase intentionally does not sign the installer.

## Source and workflow contract

`scripts/package_app.sh` is the only local entry point. It does not compile an
application and never changes `pubspec.yaml`. Before dispatch it requires:

- clean `awiki-me` and `awiki-cli-rs2` worktrees;
- a configured upstream for each current branch;
- each local HEAD to equal the exact remote branch tip;
- an exact APP, IM Core, and ANP 40-character commit SHA; and
- the ANP SHA to match `awiki-cli-rs2/scripts/release/cli/release-config.json`.

The script dispatches `.github/workflows/package-app.yml` with a unique UUID,
waits for that exact run, downloads only its aggregate artifact, and verifies
every size and SHA-256 before writing `dist/<version>/` and `dist/latest.json`.

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
| `AWIKI_ANDROID_KEYSTORE_BASE64` | Base64-encoded Android release keystore |
| `AWIKI_ANDROID_STORE_PASSWORD` | Android keystore password |
| `AWIKI_ANDROID_KEY_ALIAS` | Android signing alias |
| `AWIKI_ANDROID_KEY_PASSWORD` | Android key password |
| `AWIKI_MACOS_P12_BASE64` | Base64-encoded Apple signing identity bundle |
| `AWIKI_MACOS_P12_PASSWORD` | Apple identity bundle password |
| `AWIKI_MACOS_SIGNING_IDENTITY` | Exact non-ad-hoc codesign identity name |
| `AWIKI_MACOS_DEVELOPMENT_TEAM` | Matching ten-character Apple Team ID |

Pull-request CI must not read these secrets. The full package workflow is a
manual `workflow_dispatch` job after the workflow exists on the default branch.

## Targets

`scripts/package_app.config` accepts any non-empty subset of:

```text
android-arm64
macos-arm64
macos-x64
windows-x64
```

The default deliberately remains the pre-Windows set of Android arm64 plus both
macOS architectures. Select Windows explicitly until maintainers decide to
change the default:

```bash
# scripts/package_app.local.config (Git-ignored)
PACKAGE_TARGETS="windows-x64"

scripts/package_app.sh
```

A one-off target selection should be made in the Git-ignored local config, or by
editing and committing the release configuration. The packaging entry refuses a
dirty worktree.

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

The Start menu and optional desktop shortcuts use AUMID `AWiki.AWikiMe`. Toast
initialization uses GUID `42f66431-9bea-46c4-ac14-475b9044a2be`; those identities
must remain stable across upgrades.

## Verification

The Windows worker verifies the PE x64 machine type, required FRB exports,
`flutter_windows.dll`, `awiki_im_core.dll`, the Flutter `data` directory, and
copies the complete x64 `Microsoft.VC143.CRT` DLL set from Visual Studio 2022
into the application. The installer uses these app-local DLLs and never launches
a machine-wide runtime installer, so the per-user installation stays
non-elevated. Before compilation, the worker writes a recursive runtime manifest
with the size and SHA-256 of every staged file. Fresh install, running-app
upgrade, same-version repair, downgrade rejection, and running-app uninstall all
verify the installed manifest and payload against that immutable stage. It
computes the installer SHA-256, then the aggregate job independently recomputes
that digest before publishing the manifest. The worker compiles a lower-version
fixture and then runs a real
silent install, application startup, graceful update shutdown, overwrite upgrade,
downgrade rejection, uninstall, LocalAppData preservation, and Credential Manager
preservation sequence.

macOS can validate shell syntax, workflow structure, target parsing, metadata,
manifest hashes, and Dart unit tests. MSVC compilation, Inno compilation, Windows
Credential Manager, installer lifecycle, and the executable smoke test require the
`windows-2022` GitHub runner.

# One-host App↔App E2E mode

`multi-device-app-pair` is the reusable macOS E2E mode for scenarios that need
two independently runnable AWiki Me processes on one computer. Its first and
currently only product case is `DEVICE-JOIN-E2E-004`, a real `awiki.info`
member Join from one App to another App.

## Isolation model

The two roles are product processes, not two widget trees in one test process:

| Boundary | Admin App | Joining App |
| --- | --- | --- |
| Bundle ID | `ai.awiki.awikime.dev.e2e.pair.admin` | `ai.awiki.awikime.dev.e2e.pair.joiner` |
| Flutter build directory | run-local `build/admin` root | run-local `build/joiner` root |
| App bundle | `AWikiMe-admin.app` | `AWikiMe-joiner.app` |
| App/native Core state | fresh admin Storage Scope | fresh joiner Storage Scope |
| Flutter driver | attaches to the admin VM service | attaches to the joiner VM service |

The runner builds the roles sequentially, launches both bundles directly, then
attaches two `flutter drive --use-existing-app` processes concurrently. The
stable, distinct bundle IDs keep the operating-system application identities
separate; the per-run build and state roots prevent one role from reusing the
other role's binary product or identity vault.

## Coordination boundary

The runner creates an authenticated loopback-only coordinator for the duration
of the pair. Product state still advances only through the visible App UI,
native Core, realtime notification path, and remote services.

The coordinator may:

- exchange bounded lifecycle checkpoints between the two test roles;
- compare the two six-digit SAS values in memory and return only
  `ready/matched`.

It may not:

- call a product API, hydrate the Join inbox, request App sync, or mutate Core;
- persist OTP, SAS, challenge, proof, token, or authorization values;
- place SAS values in logs, reports, or case attestation.

The run-config token is mode-local, stored with file mode `0600`, and deleted
when the pair stops. Both App state roots are also removed after the processes
are terminated. Remote test identities and Join side effects remain governed
by the suite residual ledger.

## Reusable builder

`tool/build_isolated_e2e_app.dart` is the generic build boundary. It accepts an
`integration_test/*_test.dart` target, isolated state/work/artifact roots, a
bundle ID, and repeated Dart defines. It always makes a Debug macOS build with
`--no-pub`; each work root owns its Flutter XDG settings and build directory.
All three roots must be non-overlapping descendants of the repository so the
Flutter relative build-dir contract and cleanup boundary remain auditable.
On the current Intel development host it rejects any executable that is not
x86_64-only. The output is one JSON artifact manifest containing the copied App
and executable paths.

The App-pair runner is the supported caller today. Future E2E modes may reuse
the builder, but must define their own orchestration, isolation oracle, secret
policy, cleanup, catalog case, and suite entry. This does not make every
existing E2E a dual-App test.

## Run

Use the same reviewed remote account variables as the App↔CLI Join suite, but
the YAML does not need `cliPeer.binary` or `cliPeer.sourceRef`:

```bash
AWIKI_MULTI_DEVICE_REMOTE_JOIN_E2E_ENABLED=1 \
AWIKI_MULTI_DEVICE_E2E_PHONE=<dedicated-test-phone> \
AWIKI_MULTI_DEVICE_E2E_OTP_COMMAND_JSON='<reviewed-json-argv-resolver>' \
AWIKI_MULTI_DEVICE_E2E_HANDLE_PREFIX=apppair \
dart run tests/e2e/runner.dart \
  --case multi-device-app-pair \
  --config <local-awiki-info-macos-config.yaml>
```

The operator must complete the real macOS user-presence prompt in the admin
App. `--prepare-only` validates prerequisites but intentionally does not build
the pair, because the compiled targets require the ephemeral coordinator of an
executing run. Flutter is resolved from `PATH` by default; a host whose Flutter
SDK is not on `PATH` can set `AWIKI_E2E_FLUTTER_BIN` to the absolute executable.

# Windows HTTPS trust

The App-owned User Service utility client and update service use one HTTP client
factory. Windows uses a private `SecurityContext(withTrustedRoots: true)` with
the fixed Mozilla public CA extract documented in `assets/security/README.md`.
Dart seeds this context from its built-in Mozilla roots on Windows, not from
the Windows certificate store.
Other platforms retain their existing `http.Client()` behavior. Core transports,
identity, signing and backend contracts are unchanged.

This handles valid public HTTPS chains that the Dart built-in roots on a Windows
installation cannot validate. It does not read, repair, or change the Windows
certificate store. A private CA installed only in that store is not automatically
trusted; corporate/private CA support is outside this fix. The public bundle
supplements Dart's built-in trust and is not a replica of browser
revocation/distrust policy. Normal hostname, expiry and chain
checks remain enabled. No `badCertificateCallback`, TLS downgrade, request replay
or certificate-prompt bypass is permitted.

Each service owns its default client and closes it with the service; injected
clients remain caller-owned. Concurrent first requests share initialization.
Closing during initialization prevents pending sends and closes the new client.
Only immutable verified bundle bytes are shared; no credentials or connections
are shared across tenant client lifetimes. Missing/corrupt/unparseable resources
fail closed before sending. Asset integrity uses a compiled digest, not a
replacement for installer authenticity/signing.

TLS failures use `transport.tls_handshake_failed`; trust initialization failures
use `transport.trust_bundle_invalid`. Copyable diagnostics contain only a stable
code, host, App version and CA version. They never include the URI path/query,
request body, phone, OTP, authorization header or original exception. TLS failures
do not establish that a root is missing: clock, hostname, interception or server
configuration can also cause them. A failed default Dart `HttpClient()` request
does not establish the contents of the Windows OS store. Input and explicit
retry remain available.
Silent update checks stay silent; cached minimum-version policy is retained.

## Verification

- `flutter test tests/unit/app_http_client_test.dart`
- `flutter test tests/unit/registration_entry_test.dart tests/unit/registration_entry_widget_test.dart`
- `flutter test tests/unit/app_update_provider_test.dart tests/unit/data/services/app_update_service_test.dart`
- `flutter test tests/e2e/flutter/native/windows_https_trust_test.dart`

The controlled TLS suite uses public test-only certificates and process-local
contexts. It must pass on Windows CI and never imports OS certificates. Manual
acceptance on a machine with the observed Dart default trust gap includes
read-only account and update checks, then an operator login using the verification
installer. Read-only
transport checks are not evidence of an actual account login.

## Review and release boundary (2026-09-24)

Security review covered the union of Dart's built-in roots and the fixed bundle,
asset-integrity failure, strict hostname/expiry/chain rejection, connection
ownership, single-send semantics,
tenant stale-result fences and diagnostic redaction. The fixed bundle adds public
trust anchors; it does not bypass validation or add a trust-on-first-use decision.
The controlled TLS fixtures pass on macOS as a non-Windows transport regression;
Windows remains the authoritative platform check.

Existing cross-service coverage is reused:
`awiki-system-test/tests_v2/user_service/test_registration_account_first.py::test_registration_check_routes_names_and_rejects_invalid_invites`.
It passes against `singapore-staging` with no registration, OTP or invite
consumption. No new System Test contract is needed because neither RPC payloads
nor identity authority change. The new real TLS checks belong to the App's native
E2E lane and run directly in the existing Windows CI job, independently of the
Mac/Linux remote-account runner.

For an explicit source verification installer, dispatch `ci.yml` with
`sdk_dependencies=source`, `validation_only=true`, an exact `cli_ref`, and
`verification_version` / `verification_build`. This uses the normal Windows
installer template, includes source/dependency receipts and a runtime manifest,
and uploads private Actions artifacts for review. The verification tenant fixture
selects Singapore. Formal `package-app.yml` / `package_windows.ps1` retain their
registry requirements. No download pointer or server version policy is changed.

Use numeric package metadata, for example `0.1.34` and build `45`. Core's
client-version contract does not accept a prerelease suffix such as `-test.1`;
that suffix causes `invalid_input` during App bootstrap, before login. The test
marker belongs in the installer filename. CI and the packager validate canonical
numeric metadata and Windows component bounds before packaging, and the packager
requires the executable's ProductVersion to match the installer metadata.
The native bootstrap test receives the actual Release executable version through
a test-only PackageInfo seam (Flutter test has no build-name/build-number flags),
then opens/reopens the real Core with isolated local state. It also reproduces the
rejected prerelease version. The process/single-instance smoke alone does not
prove successful App bootstrap: the startup error screen keeps a process alive.

The separately built `windows_https_probe.dart` uses the production factory and
adapters, process-memory update storage, synthetic account input and public
read-only endpoints. It records Dart default trust before/after, account-check and
update-check success. It does not start the App session, read its account files,
request OTP or log in. Run with `AWIKI_HTTPS_PROBE_REPORT` pointing to a test-owned
file and remove the extracted probe after saving that report. Keep actual login
explicitly pending until the operator completes it with the verification App.

# Windows HTTPS trust

The App-owned User Service utility client and update service use one HTTP client
factory. Windows uses a private `SecurityContext(withTrustedRoots: true)` with
the fixed Mozilla public CA extract documented in `assets/security/README.md`.
Other platforms retain their existing `http.Client()` behavior. Core transports,
identity, signing and backend contracts are unchanged.

This handles valid public HTTPS chains on Windows installations whose root stores
load successfully but lack a public root and cannot populate it online. It does
not repair Windows or change its certificate store. The public bundle supplements
system trust, including private roots; this is not a corporate CA allowlist or a
replica of browser revocation/distrust policy. Normal hostname, expiry and chain
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
configuration can also cause them. Input and explicit retry remain available.
Silent update checks stay silent; cached minimum-version policy is retained.

## Verification

- `flutter test tests/unit/app_http_client_test.dart`
- `flutter test tests/unit/registration_entry_test.dart tests/unit/registration_entry_widget_test.dart`
- `flutter test tests/unit/app_update_provider_test.dart tests/unit/data/services/app_update_service_test.dart`
- `flutter test tests/e2e/flutter/native/windows_https_trust_test.dart`

The controlled TLS suite uses public test-only certificates and process-local
contexts. It must pass on Windows CI and never imports OS certificates. Manual
acceptance on a machine with the original root gap includes read-only account and
update checks, then an operator login using the verification installer. Read-only
transport checks are not evidence of an actual account login.

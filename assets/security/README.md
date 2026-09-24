# Windows public CA bundle

Source: https://curl.se/ca/cacert-2026-08-13.pem

Mozilla CA extract dated 2026-08-13, distributed by curl. 121 certificates,
188900 bytes. SHA-256:
`f66dff1bdf8f96060b8177976f8b7d9254bc89bc4db933d769f7384d28480bc9`.

License: Mozilla Public License 2.0, reproduced in `LICENSE-MPL-2.0.txt`.
The extract's original header and certificate labels are retained.

Update only through a reviewed App release: obtain the dated extract and digest
from https://curl.se/docs/caextract.html, review certificate additions/removals,
update the asset name, version and digest in `app_http_client_io.dart`, and run
the unit, controlled TLS and Windows smoke checks described in
`docs/windows-https-trust.md`. There is no runtime download or system-store import.

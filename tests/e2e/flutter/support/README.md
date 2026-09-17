# Integration Test Support

Place helpers that are only used by `tests/e2e/flutter/` here. Keep reusable fake
objects that are also needed by unit tests in `tests/unit/support/` instead.

`enter_existing_account.dart` follows the visible account-first existing-account
entrance for Join/Recovery scenarios. It does not inspect ownership, inject
provider state, request OTP, or replace the caller's authentication assertions.

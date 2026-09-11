import 'package:flutter_test/flutter_test.dart';

import '../../e2e/root_transfer_registry_observer.dart';

void main() {
  test(
    'only exact transient Root import Registry reads are observable again',
    () {
      const conflict =
          'transport unavailable: transport unavailable: DID-WBA HTTP '
          'signature generation failed: identity binding conflict: '
          'identity provider changed concurrently';
      expect(
        isPendingRootImportRegistryRead(
          code: 'service_error',
          message: 'Authorization bearer token is required',
        ),
        isTrue,
      );
      expect(
        isPendingRootImportRegistryRead(
          code: 'transport_unavailable',
          message: conflict,
        ),
        isTrue,
      );
      for (final (code, message) in <(String, String)>[
        ('permission_denied', conflict),
        ('transport_unavailable', '$conflict: another error'),
        ('transport_unavailable', 'HTTP request failed'),
        ('transport_unavailable', 'identity provider changed concurrently'),
        ('auth_revoked', 'Authorization bearer token is required'),
        ('service_error', 'DID document checkpoint conflict'),
      ]) {
        expect(
          isPendingRootImportRegistryRead(code: code, message: message),
          isFalse,
        );
      }
    },
  );
}

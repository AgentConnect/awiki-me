// Test-only classification for a bounded read after accepted Root delivery.
// The observer uses public local-readiness and Registry reads. Authentication
// and provider convergence stay Core-owned; it never retries the Root transfer.
bool isPendingRootImportRegistryRead({
  required String code,
  required String message,
}) =>
    (code == 'service_error' &&
        message == 'Authorization bearer token is required') ||
    (code == 'transport_unavailable' &&
        message ==
            'transport unavailable: transport unavailable: DID-WBA HTTP '
                'signature generation failed: identity binding conflict: '
                'identity provider changed concurrently');

// One read-only observation. The caller owns the original deadline and session
// fences. A delivery ACK alone does not establish local management authority.
Future<T?> readRegistryWhenLocalManagementReady<T>({
  required Future<bool> Function() localManagementReady,
  required Future<T> Function() readRegistry,
}) async {
  if (!await localManagementReady()) return null;
  return readRegistry();
}

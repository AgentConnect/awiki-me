// Test-only classification for a bounded read after accepted Root delivery.
// Each subsequent public Registry read opens a fresh identity client; it never
// refreshes auth, changes provider state, or retries the Root transfer itself.
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

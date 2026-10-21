/// Safe Core capability projection. Hosts do not parse protocol discovery here.
abstract interface class BackendCapabilitiesPort {
  Future<Map<String, dynamic>> backendCapabilities({bool force = false});
}

/// Independent Core state notifications, scoped to the current tenant/session.
abstract interface class BackendCapabilitiesObservationPort {
  Stream<Map<String, dynamic>> watchBackendCapabilities();
}

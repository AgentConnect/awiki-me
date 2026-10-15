/// Safe Core capability projection. Hosts do not parse protocol discovery here.
abstract interface class BackendCapabilitiesPort {
  Future<Map<String, dynamic>> backendCapabilities({bool force = false});
}

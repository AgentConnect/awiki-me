typedef AccountStateSyncRequestHandler =
    Future<void> Function(String reason, {bool force});

/// Decouples feature-local refresh intents from the presentation coordinator.
///
/// The production coordinator attaches one handler for the active provider
/// scope. Tests and unsupported compositions can keep using their legacy
/// feature adapters while no handler is attached.
class AccountStateSyncRequestBus {
  AccountStateSyncRequestHandler? _handler;

  bool get hasHandler => _handler != null;

  void attach(AccountStateSyncRequestHandler handler) {
    _handler = handler;
  }

  void detach() => _handler = null;

  Future<void> request(String reason, {bool force = false}) {
    final handler = _handler;
    if (handler == null) {
      return Future<void>.value();
    }
    return handler(reason, force: force);
  }
}

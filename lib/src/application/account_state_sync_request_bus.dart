import 'models/product_local_models.dart';

typedef AccountStateSyncRequestHandler =
    Future<void> Function(
      String reason, {
      bool force,
      AccountStateVersionFloor? minimumVersion,
    });

class AccountStateVersionFloor {
  AccountStateVersionFloor({required this.domain, required this.version}) {
    if (!isCanonicalProductDecimal(version)) {
      throw ArgumentError.value(
        version,
        'version',
        'must be a canonical decimal string',
      );
    }
  }

  final ProductAccountDomain domain;
  final String version;
}

class AccountStateVersionFloorNotReached implements Exception {
  AccountStateVersionFloorNotReached(
    Map<ProductAccountDomain, String> minimumVersions,
  ) : minimumVersions = Map<ProductAccountDomain, String>.unmodifiable(
        minimumVersions,
      );

  final Map<ProductAccountDomain, String> minimumVersions;

  @override
  String toString() => 'account_state_version_floor_not_reached';
}

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

  Future<void> request(
    String reason, {
    bool force = false,
    AccountStateVersionFloor? minimumVersion,
  }) {
    final handler = _handler;
    if (handler == null) {
      return Future<void>.value();
    }
    return handler(reason, force: force, minimumVersion: minimumVersion);
  }
}

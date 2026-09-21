import '../../application/ports/notify_preference_port.dart';
import '../services/authenticated_user_service_rpc_client.dart';

class UserServiceNotifyPreferenceAdapter implements NotifyPreferencePort {
  UserServiceNotifyPreferenceAdapter(this.client);
  final AuthenticatedUserServiceRpcClient client;
  static const path = '/user-service/v1/push/rpc';
  @override
  Future<NotifyPreference> load() async => NotifyPreference.fromJson(
    await client.rpcCall(
      path: path,
      method: 'get_notify_preference',
      params: {},
    ),
  );
  @override
  Future<NotifyPreference> save(
    NotifyPreference previous, {
    required bool enabled,
    required bool urgentEnabled,
    List<String>? mutedPeerDids,
  }) async => NotifyPreference.fromJson(
    await client.rpcCall(
      path: path,
      method: 'set_notify_preference',
      params: {
        'enabled': enabled,
        'urgent_enabled': urgentEnabled,
        'expected_version': previous.version,
        'muted_peer_dids': mutedPeerDids ?? previous.mutedPeerDids,
      },
    ),
  );
}

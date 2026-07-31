import '../models/remote_push_sync_receipt.dart';
import '../tenant/app_tenant.dart';

final class RemotePushSessionContext {
  const RemotePushSessionContext({
    required this.storageScopeId,
    required this.ownerDid,
    required this.generation,
  });

  final StorageScopeId storageScopeId;
  final String ownerDid;
  final int generation;

  bool matches(RemotePushSessionContext? other) {
    return other != null &&
        storageScopeId == other.storageScopeId &&
        ownerDid == other.ownerDid &&
        generation == other.generation;
  }
}

abstract interface class RemotePushSyncPort {
  Future<RemotePushSyncReceipt> requestRemotePushSync();
}

abstract interface class RemotePushNavigationPort {
  Future<void> showConversationList(RemotePushSessionContext context);

  Future<void> openConversation(
    RemotePushSessionContext context,
    String conversationId,
  );
}

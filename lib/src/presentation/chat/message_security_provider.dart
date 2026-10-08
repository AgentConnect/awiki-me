import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/app_services.dart';
import '../../application/models/product_local_models.dart';
import '../app_shell/providers/session_provider.dart';

String _key(String conversationId) => 'message_security:$conversationId';

/// ProductLocalStore belongs to the current tenant/device storage scope and
/// resolves ownerDid to the stable local account owner.
final messageSecurityProvider = FutureProvider.autoDispose.family<bool, String>((
  ref,
  conversationId,
) async {
  final epoch = ref.watch(sessionProvider).activeEpoch;
  if (epoch == null) throw StateError('No active account');
  final preference = await ref.watch(productLocalStoreProvider).loadUiPreference(
    ownerDid: epoch.ownerDid,
    key: _key(conversationId),
  );
  if (!epoch.matches(ref.read(sessionProvider))) {
    throw StateError('Account changed');
  }
  switch (preference?.valueJson) {
    case null:
    case '"plain"': return false;
    case '"e2ee-required"': return true;
    default: throw StateError('消息安全偏好不可用，请重新选择消息模式');
  }
});

Future<void> setMessageSecurity(WidgetRef ref, String conversationId, bool encrypted) async {
  final epoch = ref.read(sessionProvider).activeEpoch;
  if (epoch == null) throw StateError('No active account');
  await ref.read(productLocalStoreProvider).saveUiPreference(LocalUiPreference(
    ownerDid: epoch.ownerDid,
    key: _key(conversationId),
    valueJson: encrypted ? '"e2ee-required"' : '"plain"',
    updatedAt: DateTime.now().toUtc(),
  ));
  if (epoch.matches(ref.read(sessionProvider))) {
    ref.invalidate(messageSecurityProvider(conversationId));
  }
}

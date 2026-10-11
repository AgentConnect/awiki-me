import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/app_services.dart';
import '../../application/models/product_local_models.dart';
import '../app_shell/providers/session_provider.dart';

final messageSecurityProvider = AsyncNotifierProvider.autoDispose
    .family<MessageSecurityController, bool, String>(
      MessageSecurityController.new,
    );

/// UI preference only. Each send captures its own immutable security intent.
class MessageSecurityController
    extends AutoDisposeFamilyAsyncNotifier<bool, String> {
  Future<void> _writes = Future<void>.value();
  int _revision = 0;
  int _generation = 0;
  bool _persisted = false;

  @override
  Future<bool> build(String conversationId) async {
    final generation = ++_generation;
    ref.onDispose(() => _generation++);
    final epoch = ref.watch(sessionProvider).activeEpoch;
    if (epoch == null) throw StateError('No active account');
    final preference = await ref
        .watch(productLocalStoreProvider)
        .loadUiPreference(
          ownerDid: epoch.ownerDid,
          key: 'message_security:$conversationId',
        );
    if (generation != _generation ||
        !epoch.matches(ref.read(sessionProvider))) {
      throw StateError('Account changed');
    }
    _persisted = switch (preference?.valueJson) {
      null || '"plain"' => false,
      '"e2ee-required"' => true,
      _ => throw StateError('消息安全偏好不可用，请重试'),
    };
    return _persisted;
  }

  Future<void> setEncrypted(bool encrypted) {
    if (!state.hasValue || state.hasError) throw StateError('消息模式尚未就绪');
    final epoch = ref.read(sessionProvider).activeEpoch;
    if (epoch == null) throw StateError('No active account');
    final store = ref.read(productLocalStoreProvider);
    final generation = _generation;
    final revision = ++_revision;
    state = AsyncData(encrypted);
    final write = _writes.then((_) async {
      await store.saveUiPreference(
        LocalUiPreference(
          ownerDid: epoch.ownerDid,
          key: 'message_security:$arg',
          valueJson: encrypted ? '"e2ee-required"' : '"plain"',
          updatedAt: DateTime.now().toUtc(),
        ),
      );
      if (generation == _generation) _persisted = encrypted;
    });
    _writes = write.catchError((Object _) {});
    return write.catchError((Object error, StackTrace stack) {
      if (generation == _generation &&
          revision == _revision &&
          epoch.matches(ref.read(sessionProvider))) {
        state = AsyncData(_persisted);
      }
      Error.throwWithStackTrace(error, stack);
    });
  }
}

Future<void> setMessageSecurity(
  WidgetRef ref,
  String conversationId,
  bool encrypted,
) => ref
    .read(messageSecurityProvider(conversationId).notifier)
    .setEncrypted(encrypted);

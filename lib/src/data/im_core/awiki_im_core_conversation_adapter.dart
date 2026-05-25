import '../../application/models/app_thread_ref.dart';
import '../../application/ports/conversation_core_port.dart';
import '../../domain/entities/conversation_summary.dart';
import 'awiki_im_core_mappers.dart';
import 'awiki_im_core_runtime.dart';

class AwikiImCoreConversationAdapter implements ConversationCorePort {
  AwikiImCoreConversationAdapter({
    required AwikiImCoreRuntime runtime,
    AwikiImCoreMappers mappers = const AwikiImCoreMappers(),
  }) : _runtime = runtime,
       _mappers = mappers;

  final AwikiImCoreRuntime _runtime;
  final AwikiImCoreMappers _mappers;

  @override
  Future<List<ConversationSummary>> listConversations({
    int limit = 100,
    bool unreadOnly = false,
  }) async {
    final client = await _runtime.currentClient();
    final ownerDid = (await client.identity.current()).did;
    final page = await client.messages.conversations(
      limit: limit,
      unreadOnly: unreadOnly,
    );
    return page.items
        .map(
          (conversation) =>
              _mappers.conversationFromCore(conversation, ownerDid: ownerDid),
        )
        .toList();
  }

  @override
  Future<void> markThreadRead(AppThreadRef thread) {
    // TODO(im-core): SDK only exposes markRead(messageIds) and current Message
    // DTOs do not expose read-state. Do not page history and guess unread ids.
    throw UnsupportedError('IM Core markThreadRead is not available yet');
  }
}

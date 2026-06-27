import 'package:awiki_im_core/awiki_im_core.dart' as core;

import '../../application/models/app_thread_ref.dart';
import '../../application/ports/message_sync_core_port.dart';
import 'awiki_im_core_mappers.dart';
import 'awiki_im_core_runtime.dart';

class AwikiImCoreMessageSyncAdapter implements MessageSyncCorePort {
  AwikiImCoreMessageSyncAdapter({
    required AwikiImCoreRuntime runtime,
    AwikiImCoreMappers mappers = const AwikiImCoreMappers(),
  }) : _runtime = runtime,
       _mappers = mappers;

  final AwikiImCoreRuntime _runtime;
  final AwikiImCoreMappers _mappers;

  @override
  Future<MessageSyncDeltaResult> syncDelta({
    int? limit,
    String? deviceId,
    String? reason,
  }) {
    return _runtime.withCurrentClient((client) async {
      final result = await client.messages.syncDelta(
        core.SyncDeltaRequest(limit: limit, deviceId: deviceId, reason: reason),
      );
      return MessageSyncDeltaResult(
        eventsApplied: result.eventsApplied,
        pagesFetched: result.pagesFetched,
        lastAppliedEventSeq: result.lastAppliedEventSeq,
        hasMore: result.hasMore,
        snapshotRequired: result.snapshotRequired,
        retentionFloorEventSeq: result.retentionFloorEventSeq,
        warnings: result.warnings,
      );
    });
  }

  @override
  Future<MessageSyncThreadAfterResult> syncThreadAfter({
    required AppThreadRef thread,
    String? afterServerSeq,
    int? limit,
  }) {
    return _runtime.withCurrentClient((client) async {
      final ownerDid = (await client.identity.current()).did;
      final result = await client.messages.syncThreadAfter(
        core.SyncThreadAfterRequest(
          thread: _mappers.threadRefToCore(thread),
          afterServerSeq: afterServerSeq,
          limit: limit,
        ),
      );
      return MessageSyncThreadAfterResult(
        messages: result.messages
            .map(
              (message) =>
                  _mappers.chatMessageFromCore(message, ownerDid: ownerDid),
            )
            .toList(),
        nextAfterServerSeq: result.nextAfterServerSeq,
        hasMore: result.hasMore,
        warnings: result.warnings,
      );
    });
  }
}

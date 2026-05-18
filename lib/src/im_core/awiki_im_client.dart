import 'dart:async';

import 'apis/attachment_api.dart';
import 'apis/conversation_api.dart';
import 'apis/group_api.dart';
import 'apis/local_store_api.dart';
import 'apis/message_api.dart';
import 'apis/outbox_api.dart';
import 'apis/realtime_api.dart';
import 'apis/reserved_apis.dart';
import 'models/client_models.dart';
import 'models/event_models.dart';

abstract class AwikiImClient {
  Stream<ImEventDto> get events;
  Stream<ImConnectionStateDto> get connectionStates;

  Future<void> initialize(ImClientConfig config);
  Future<void> setSession(ImSessionContext session);
  Future<void> updateAuth(ImAuthUpdate update);
  Future<void> clearSession();
  Future<void> close();

  Future<ImEngineStatusDto> status();
  Future<ImCapabilitiesDto> capabilities();

  ImConversationApi get conversations;
  ImMessageApi get messages;
  ImGroupApi get groups;
  ImRealtimeApi get realtime;
  ImAttachmentApi get attachments;
  ImOutboxApi get outbox;
  ImLocalStoreApi get localStore;

  ImDirectSecureApi get directSecure;
  ImGroupE2eeApi get groupE2ee;
  ImMigrationApi get migration;
  ImAdvancedAttachmentApi get advancedAttachments;
}

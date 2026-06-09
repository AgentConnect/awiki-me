import 'dart:convert';

const mvpAppActionAllowlist = <String>[
  'message.summarize_plain',
  'message.create_draft',
  'contact.read',
  'contact.update_display_name',
  'contact.update_note',
];

const appActionWriteActions = <String>[
  'contact.update_display_name',
  'contact.update_note',
];

final class AgentControlPayloads {
  const AgentControlPayloads._();

  static const commandSchema = 'awiki.agent.command.v1';
  static const statusSchema = 'awiki.agent.status.v1';
  static const daemonBootstrapSchema = 'awiki.daemon.bootstrap.v1';
  static const messageSyncSchema = 'awiki.message.sync.v1';
  static const appCapabilitiesSchema = 'awiki.app.capabilities.v1';
  static const appActionSchema = 'awiki.app.action.v1';
  static const appActionResultSchema = 'awiki.app.action.result.v1';
  static const notificationSchema = 'awiki.agent.notification.v1';

  static Map<String, Object?>? decode(String? payloadJson) {
    if (payloadJson == null || payloadJson.trim().isEmpty) {
      return null;
    }
    try {
      final decoded = jsonDecode(payloadJson);
      if (decoded is! Map) {
        return null;
      }
      return decoded.map(
        (key, value) => MapEntry(key.toString(), value as Object?),
      );
    } on Object {
      return null;
    }
  }

  static String? schema(String? payloadJson) {
    final rawSchema = decode(payloadJson)?['schema'];
    if (rawSchema is! String || rawSchema.trim().isEmpty) {
      return null;
    }
    return rawSchema;
  }

  static bool isCommand(String? payloadJson) =>
      schema(payloadJson) == commandSchema;

  static bool isStatus(String? payloadJson) =>
      schema(payloadJson) == statusSchema;

  static bool isSystemSchema(String? value) {
    final normalized = value?.trim();
    if (normalized == null || normalized.isEmpty) {
      return false;
    }
    return normalized.startsWith('awiki.') ||
        normalized == commandSchema ||
        normalized == statusSchema ||
        normalized == daemonBootstrapSchema ||
        normalized == messageSyncSchema ||
        normalized == appCapabilitiesSchema ||
        normalized == appActionSchema ||
        normalized == appActionResultSchema ||
        normalized == notificationSchema;
  }

  static bool isControl(String? payloadJson) =>
      isSystemSchema(schema(payloadJson));

  static bool isAllowedAppAction(String action) {
    final normalized = action.trim();
    if (normalized.isEmpty || _containsForbiddenAction(normalized)) {
      return false;
    }
    return mvpAppActionAllowlist.contains(normalized);
  }

  static bool requiresAppActionConfirmation(
    String action, {
    bool requireConfirmationForWriteActions = true,
  }) {
    if (!requireConfirmationForWriteActions) {
      return false;
    }
    return appActionWriteActions.contains(action.trim());
  }

  static AppCapabilitiesPayload? decodeAppCapabilities(String? payloadJson) =>
      AppCapabilitiesPayload.fromPayloadJson(payloadJson);

  static AppActionRequestPayload? decodeAppAction(String? payloadJson) =>
      AppActionRequestPayload.fromPayloadJson(payloadJson);

  static AppActionResultPayload? decodeAppActionResult(String? payloadJson) =>
      AppActionResultPayload.fromPayloadJson(payloadJson);

  static MessageSyncPayload? decodeMessageSync(String? payloadJson) =>
      MessageSyncPayload.fromPayloadJson(payloadJson);
}

final class AppCapabilitiesPayload {
  const AppCapabilitiesPayload({
    required this.capabilities,
    this.requireConfirmationForWriteActions = true,
  });

  final List<String> capabilities;
  final bool requireConfirmationForWriteActions;

  List<String> get allowedMvpCapabilities => capabilities
      .where(AgentControlPayloads.isAllowedAppAction)
      .toList(growable: false);

  static AppCapabilitiesPayload? fromPayloadJson(String? payloadJson) {
    final payload = AgentControlPayloads.decode(payloadJson);
    if (payload?['schema'] != AgentControlPayloads.appCapabilitiesSchema) {
      return null;
    }
    return AppCapabilitiesPayload(
      capabilities: _stringList(payload?['capabilities']),
      requireConfirmationForWriteActions:
          payload?['require_confirmation_for_write_actions'] is bool
          ? payload!['require_confirmation_for_write_actions']! as bool
          : true,
    );
  }
}

final class AppActionRequestPayload {
  const AppActionRequestPayload({
    required this.actionId,
    required this.action,
    required this.state,
    this.bindingId,
    this.ownerDid,
    this.appInstanceId,
    this.runtimeAgentDid,
    this.runtimeProfileId,
    this.runId,
    this.sourceMessageId,
    this.conversationId,
    this.requiresConfirmation = false,
    this.args = const <String, Object?>{},
  });

  final String actionId;
  final String action;
  final String state;
  final String? bindingId;
  final String? ownerDid;
  final String? appInstanceId;
  final String? runtimeAgentDid;
  final String? runtimeProfileId;
  final String? runId;
  final String? sourceMessageId;
  final String? conversationId;
  final bool requiresConfirmation;
  final Map<String, Object?> args;

  bool get isAllowedInMvp => AgentControlPayloads.isAllowedAppAction(action);

  bool get needsUserConfirmation =>
      state == appActionStateRequiresConfirmation || requiresConfirmation;

  static AppActionRequestPayload? fromPayloadJson(String? payloadJson) {
    final payload = AgentControlPayloads.decode(payloadJson);
    if (payload?['schema'] != AgentControlPayloads.appActionSchema) {
      return null;
    }
    if (_containsForbiddenActionPayload(payload)) {
      return null;
    }
    final actionId = _nonEmptyString(payload?['action_id']);
    final action = _nonEmptyString(payload?['action']);
    if (actionId == null || action == null) {
      return null;
    }
    final state = _nonEmptyString(payload?['state']) ?? appActionStateRequested;
    if (!isSupportedAppActionState(state)) {
      return null;
    }
    return AppActionRequestPayload(
      actionId: actionId,
      action: action,
      state: state,
      bindingId: _nonEmptyString(payload?['binding_id']),
      ownerDid: _nonEmptyString(payload?['owner_did']),
      appInstanceId: _nonEmptyString(payload?['app_instance_id']),
      runtimeAgentDid: _nonEmptyString(payload?['runtime_agent_did']),
      runtimeProfileId: _nonEmptyString(payload?['runtime_profile_id']),
      runId: _nonEmptyString(payload?['run_id']),
      sourceMessageId: _nonEmptyString(payload?['source_message_id']),
      conversationId: _nonEmptyString(payload?['conversation_id']),
      requiresConfirmation: payload?['requires_confirmation'] == true,
      args: _objectMap(payload?['args']),
    );
  }
}

final class AppActionResultPayload {
  const AppActionResultPayload({
    required this.actionId,
    required this.action,
    required this.state,
    this.result = const <String, Object?>{},
    this.errorCode,
    this.errorSummary,
  });

  final String actionId;
  final String action;
  final String state;
  final Map<String, Object?> result;
  final String? errorCode;
  final String? errorSummary;

  bool get isTerminal =>
      state == appActionStateRejected ||
      state == appActionStateSucceeded ||
      state == appActionStateFailed;

  static AppActionResultPayload? fromPayloadJson(String? payloadJson) {
    final payload = AgentControlPayloads.decode(payloadJson);
    if (payload?['schema'] != AgentControlPayloads.appActionResultSchema) {
      return null;
    }
    if (_containsForbiddenActionPayload(payload)) {
      return null;
    }
    final actionId = _nonEmptyString(payload?['action_id']);
    final action = _nonEmptyString(payload?['action']);
    final state = _nonEmptyString(payload?['state']);
    if (actionId == null ||
        action == null ||
        state == null ||
        !isSupportedAppActionState(state)) {
      return null;
    }
    return AppActionResultPayload(
      actionId: actionId,
      action: action,
      state: state,
      result: _objectMap(payload?['result']),
      errorCode: _nonEmptyString(payload?['error_code']),
      errorSummary: _nonEmptyString(payload?['error_summary']),
    );
  }
}

final class MessageSyncPayload {
  const MessageSyncPayload({required this.payload});

  final Map<String, Object?> payload;

  static MessageSyncPayload? fromPayloadJson(String? payloadJson) {
    final payload = AgentControlPayloads.decode(payloadJson);
    if (payload?['schema'] != AgentControlPayloads.messageSyncSchema) {
      return null;
    }
    if (_containsForbiddenActionPayload(payload)) {
      return null;
    }
    return MessageSyncPayload(payload: Map.unmodifiable(payload!));
  }
}

final class AppActionRecord {
  const AppActionRecord({
    required this.actionId,
    required this.action,
    required this.state,
    this.request,
    this.result,
  });

  final String actionId;
  final String action;
  final String state;
  final AppActionRequestPayload? request;
  final AppActionResultPayload? result;

  bool get requiresConfirmation =>
      state == appActionStateRequiresConfirmation ||
      request?.requiresConfirmation == true;

  bool get isTerminal =>
      state == appActionStateRejected ||
      state == appActionStateSucceeded ||
      state == appActionStateFailed;

  AppActionRecord applyResult(AppActionResultPayload nextResult) {
    if (nextResult.actionId != actionId || nextResult.action != action) {
      return this;
    }
    return AppActionRecord(
      actionId: actionId,
      action: action,
      state: nextResult.state,
      request: request,
      result: nextResult,
    );
  }
}

final class AppActionReducer {
  const AppActionReducer._();

  static Map<String, AppActionRecord> reducePayloadJson(
    Map<String, AppActionRecord> current,
    String? payloadJson,
  ) {
    final request = AgentControlPayloads.decodeAppAction(payloadJson);
    if (request != null) {
      return <String, AppActionRecord>{
        ...current,
        request.actionId: AppActionRecord(
          actionId: request.actionId,
          action: request.action,
          state: request.state,
          request: request,
          result: current[request.actionId]?.result,
        ),
      };
    }
    final result = AgentControlPayloads.decodeAppActionResult(payloadJson);
    if (result != null) {
      final existing = current[result.actionId];
      if (existing != null) {
        return <String, AppActionRecord>{
          ...current,
          result.actionId: existing.applyResult(result),
        };
      }
      return <String, AppActionRecord>{
        ...current,
        result.actionId: AppActionRecord(
          actionId: result.actionId,
          action: result.action,
          state: result.state,
          result: result,
        ),
      };
    }
    return current;
  }
}

const appActionStateRequested = 'requested';
const appActionStateRequiresConfirmation = 'requires_confirmation';
const appActionStateAccepted = 'accepted';
const appActionStateRejected = 'rejected';
const appActionStateSucceeded = 'succeeded';
const appActionStateFailed = 'failed';

bool isSupportedAppActionState(String state) {
  return const <String>{
    appActionStateRequested,
    appActionStateRequiresConfirmation,
    appActionStateAccepted,
    appActionStateRejected,
    appActionStateSucceeded,
    appActionStateFailed,
  }.contains(state.trim());
}

List<String> _stringList(Object? value) {
  if (value is! Iterable) {
    return const <String>[];
  }
  return value
      .whereType<String>()
      .map((entry) => entry.trim())
      .where((entry) => entry.isNotEmpty)
      .toList(growable: false);
}

Map<String, Object?> _objectMap(Object? value) {
  if (value is! Map) {
    return const <String, Object?>{};
  }
  return value.map((key, value) => MapEntry(key.toString(), value as Object?));
}

String? _nonEmptyString(Object? value) {
  if (value is! String) {
    return null;
  }
  final trimmed = value.trim();
  return trimmed.isEmpty ? null : trimmed;
}

bool _containsForbiddenActionPayload(Object? value) {
  if (value is Map) {
    for (final entry in value.entries) {
      if (_containsForbiddenPrivateState(entry.key.toString()) ||
          _containsForbiddenActionPayload(entry.value)) {
        return true;
      }
    }
    return false;
  }
  if (value is Iterable) {
    return value.any(_containsForbiddenActionPayload);
  }
  if (value is String) {
    return _containsForbiddenPrivateState(value);
  }
  return false;
}

bool _containsForbiddenAction(String value) {
  final lower = value.toLowerCase();
  return lower.contains('e2ee') ||
      lower.contains('export') ||
      lower.contains('delete') ||
      lower.contains('identity') ||
      lower.contains('key');
}

bool _containsForbiddenPrivateState(String value) {
  final lower = value.toLowerCase();
  return lower.contains('private_key') ||
      lower.contains('private key') ||
      lower.contains('private_state') ||
      lower.contains('session_private') ||
      lower.contains('key_package_private') ||
      lower.contains('e2ee_plaintext') ||
      lower.contains('rtok_') ||
      lower.contains('jwt') ||
      lower.contains('bearer ') ||
      lower.contains('begin private key') ||
      lower.contains('registration_token') ||
      lower.contains('secret');
}

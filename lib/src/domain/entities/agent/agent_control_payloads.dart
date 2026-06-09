import 'dart:convert';

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
}

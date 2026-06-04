import 'dart:convert';

final class AgentControlPayloads {
  const AgentControlPayloads._();

  static const commandSchema = 'awiki.agent.command.v1';
  static const statusSchema = 'awiki.agent.status.v1';

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

  static bool isControl(String? payloadJson) =>
      isCommand(payloadJson) || isStatus(payloadJson);
}

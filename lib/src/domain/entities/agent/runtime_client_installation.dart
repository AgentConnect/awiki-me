import 'agent_command.dart';

enum RuntimeClientInstallationStatus { ready, missing, unavailable, unknown }

class RuntimeClientInstallation {
  const RuntimeClientInstallation({
    required this.status,
    this.version,
    this.reasonCode,
  });
  final RuntimeClientInstallationStatus status;
  final String? version;
  final String? reasonCode;
  bool get ready => status == RuntimeClientInstallationStatus.ready;
}

class RuntimeClientInstallationReport {
  const RuntimeClientInstallationReport(this.clients);
  final Map<RuntimeAgentKind, RuntimeClientInstallation> clients;

  factory RuntimeClientInstallationReport.parse(Map<String, Object?> json) {
    if (json['schema_version'] != 1 || json['clients'] is! List) {
      throw const FormatException('unsupported_client_inspection');
    }
    final clients = <RuntimeAgentKind, RuntimeClientInstallation>{};
    for (final value in json['clients']! as List) {
      if (value is! Map) continue;
      final matching = RuntimeAgentKind.values.where(
        (kind) => kind.runtime == value['kind'],
      );
      if (matching.isEmpty) continue;
      final kind = matching.first;
      if (clients.containsKey(kind)) {
        throw const FormatException('duplicate_client_inspection');
      }
      clients[kind] = RuntimeClientInstallation(
        status: switch (value['status']) {
          'ready' => RuntimeClientInstallationStatus.ready,
          'missing' => RuntimeClientInstallationStatus.missing,
          'unavailable' => RuntimeClientInstallationStatus.unavailable,
          _ => RuntimeClientInstallationStatus.unknown,
        },
        version: value['version'] is String ? value['version'] as String : null,
        reasonCode: value['reason_code'] is String
            ? value['reason_code'] as String
            : null,
      );
    }
    return RuntimeClientInstallationReport(Map.unmodifiable(clients));
  }
}

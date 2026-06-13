import 'agent_im_config.dart';

final class RemoteEvidenceCommand {
  const RemoteEvidenceCommand({required this.label, required this.command});

  final String label;
  final String command;

  Map<String, Object?> toJson() => <String, Object?>{
    'label': label,
    'command': command,
  };
}

final class AgentImRemoteAdapter {
  const AgentImRemoteAdapter(this.config);

  final AgentImDelegatedConfig config;

  List<RemoteEvidenceCommand> planEvidenceCommands(String runId) {
    if (!config.remote.collectLogs) {
      return const <RemoteEvidenceCommand>[];
    }
    final alias = config.remote.sshAlias;
    return <RemoteEvidenceCommand>[
      RemoteEvidenceCommand(
        label: 'remote health summary',
        command: 'ssh $alias "echo health-check for $runId"',
      ),
      RemoteEvidenceCommand(
        label: 'daemon and hermes logs by runId',
        command: 'ssh $alias "echo collect daemon hermes logs for $runId"',
      ),
      RemoteEvidenceCommand(
        label: 'message-service fanout logs by runId',
        command: 'ssh $alias "echo collect message-service logs for $runId"',
      ),
    ];
  }
}

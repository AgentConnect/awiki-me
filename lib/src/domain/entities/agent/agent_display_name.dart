import 'agent_status.dart';
import 'agent_summary.dart';

class AgentDisplayName {
  const AgentDisplayName._();

  static String title(AgentSummary agent) {
    final name = agent.displayName.trim();
    if (_isUserVisibleName(name)) {
      return name;
    }
    return fallbackForKind(agent.kind);
  }

  static String fallbackForKind(AgentKind kind) {
    return kind == AgentKind.daemon ? 'Unnamed daemon' : 'Unnamed agent';
  }

  static bool isUserVisibleName(String name) {
    return _isUserVisibleName(name.trim());
  }

  static bool _isUserVisibleName(String name) {
    if (name.isEmpty || name.startsWith('did:')) {
      return false;
    }
    final normalized = name.toLowerCase();
    return !normalized.startsWith('awiki-daemon-') &&
        !normalized.startsWith('awiki-agent-') &&
        !normalized.startsWith('awiki_daemon_') &&
        !normalized.startsWith('awiki_agent_');
  }
}

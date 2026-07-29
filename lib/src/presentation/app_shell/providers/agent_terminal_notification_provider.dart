import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../domain/entities/agent/agent_terminal_notification.dart';

final agentTerminalNotificationDeduplicatorProvider =
    Provider<AgentTerminalNotificationDeduplicator>((ref) {
      final deduplicator = AgentTerminalNotificationDeduplicator();
      ref.onDispose(deduplicator.clear);
      return deduplicator;
    });

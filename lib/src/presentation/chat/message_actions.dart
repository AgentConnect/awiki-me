import 'dart:async';

import 'package:flutter/widgets.dart';

import '../../domain/entities/chat_message.dart';
import '../../domain/entities/conversation_summary.dart';

enum MessageActionId { copySelection, copyAll, selectAll }

enum MessageActionGroup {
  selection,
  communication,
  content,
  management,
  danger,
}

enum MessageActionMenuDismissPolicy {
  beforeExecution,
  afterExecution,
  keepOpen,
}

@immutable
final class MessageActionContext {
  const MessageActionContext({
    required this.message,
    required this.conversation,
    required this.fullText,
    required this.selectedText,
    required this.platform,
  });

  final ChatMessage message;
  final ConversationSummary conversation;
  final String fullText;
  final String? selectedText;
  final TargetPlatform platform;

  bool get isDesktop => switch (platform) {
    TargetPlatform.linux ||
    TargetPlatform.macOS ||
    TargetPlatform.windows => true,
    TargetPlatform.android ||
    TargetPlatform.fuchsia ||
    TargetPlatform.iOS => false,
  };

  String get copySelectionText {
    final selection = selectedText;
    return selection != null && selection.isNotEmpty ? selection : fullText;
  }
}

typedef MessageActionAvailability = bool Function(MessageActionContext context);
typedef MessageActionHandler =
    FutureOr<void> Function(MessageActionContext context);

@immutable
final class MessageActionSpec {
  const MessageActionSpec({
    required this.id,
    required this.group,
    required this.order,
    required this.label,
    required this.icon,
    required this.onInvoke,
    this.isVisible = _alwaysAvailable,
    this.isEnabled = _alwaysAvailable,
    this.dismissPolicy = MessageActionMenuDismissPolicy.beforeExecution,
    this.preserveSelectionOnDismiss = false,
    this.destructive = false,
  });

  final MessageActionId id;
  final MessageActionGroup group;
  final int order;
  final String label;
  final IconData icon;
  final MessageActionHandler onInvoke;
  final MessageActionAvailability isVisible;
  final MessageActionAvailability isEnabled;
  final MessageActionMenuDismissPolicy dismissPolicy;
  final bool preserveSelectionOnDismiss;
  final bool destructive;

  static bool _alwaysAvailable(MessageActionContext _) => true;
}

final class MessageActionCatalog {
  const MessageActionCatalog(this._specs);

  final List<MessageActionSpec> _specs;

  List<MessageActionSpec> resolve(MessageActionContext context) {
    final actions = <({int index, MessageActionSpec spec})>[
      for (var index = 0; index < _specs.length; index++)
        if (_specs[index].isVisible(context))
          (index: index, spec: _specs[index]),
    ];
    actions.sort((left, right) {
      final groupOrder = left.spec.group.index.compareTo(
        right.spec.group.index,
      );
      if (groupOrder != 0) {
        return groupOrder;
      }
      final actionOrder = left.spec.order.compareTo(right.spec.order);
      return actionOrder != 0 ? actionOrder : left.index.compareTo(right.index);
    });
    return <MessageActionSpec>[for (final action in actions) action.spec];
  }
}

typedef MessageActionDismiss = void Function({required bool preserveSelection});
typedef MessageActionUnexpectedError =
    FutureOr<void> Function(Object error, StackTrace stackTrace);

final class MessageActionExecutor {
  MessageActionId? _activeAction;

  MessageActionId? get activeAction => _activeAction;

  Future<bool> execute({
    required MessageActionSpec action,
    required MessageActionContext context,
    required MessageActionDismiss dismissMenu,
    required MessageActionUnexpectedError onUnexpectedError,
  }) async {
    if (_activeAction != null || !action.isEnabled(context)) {
      return false;
    }
    _activeAction = action.id;
    try {
      if (action.dismissPolicy ==
          MessageActionMenuDismissPolicy.beforeExecution) {
        dismissMenu(preserveSelection: action.preserveSelectionOnDismiss);
      }
      await action.onInvoke(context);
      if (action.dismissPolicy ==
          MessageActionMenuDismissPolicy.afterExecution) {
        dismissMenu(preserveSelection: action.preserveSelectionOnDismiss);
      }
      return true;
    } on Object catch (error, stackTrace) {
      await onUnexpectedError(error, stackTrace);
      return false;
    } finally {
      _activeAction = null;
    }
  }
}

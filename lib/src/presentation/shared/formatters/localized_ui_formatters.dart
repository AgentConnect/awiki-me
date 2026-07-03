import 'package:awiki_me/l10n/app_localizations.dart';

import '../../../application/models/attachment_models.dart';
import '../../../domain/entities/agent/agent_display_name.dart';
import '../../../domain/entities/agent/agent_status.dart';
import '../../../domain/entities/agent/agent_summary.dart';
import '../../../domain/entities/chat_attachment.dart';
import '../../../domain/entities/chat_message.dart';
import '../../../domain/entities/conversation_summary.dart';
import '../../agents/agent_runtime_display.dart';
import '../../agents/agent_ui_messages.dart';
import '../../agents/agent_visual_status.dart';
import '../../agents/agents_provider.dart';
import '../../conversation_list/conversation_peer_classifier.dart';
import 'markdown_preview_formatter.dart';

String localizeAgentTitle(AppLocalizations l10n, AgentSummary agent) {
  final title = AgentDisplayName.title(agent).trim();
  if (title.isEmpty ||
      title == AgentDisplayName.fallbackForKind(agent.kind) ||
      title == 'Unnamed daemon' ||
      title == 'Unnamed agent') {
    return localizeAgentFallbackTitle(l10n, agent.kind);
  }
  return title;
}

String localizeAgentFallbackTitle(AppLocalizations l10n, AgentKind kind) {
  return kind == AgentKind.daemon
      ? l10n.agentUnnamedDaemon
      : l10n.agentUnnamedRuntime;
}

String localizeAgentVisualStatus(
  AppLocalizations l10n,
  AgentVisualStatus status,
) {
  return switch (status.kind) {
    AgentVisualStatusKind.processing => l10n.agentStatusProcessing,
    AgentVisualStatusKind.ready => l10n.agentStatusReady,
    AgentVisualStatusKind.needsConfig => l10n.agentStatusNeedsConfig,
    AgentVisualStatusKind.needsUpgrade => l10n.agentStatusNeedsUpgrade,
    AgentVisualStatusKind.failed => l10n.agentStatusFailed,
    AgentVisualStatusKind.offline => l10n.agentStatusOffline,
    AgentVisualStatusKind.disabled => l10n.agentStatusDisabled,
    AgentVisualStatusKind.unknown => l10n.agentStatusUnknown,
  };
}

String localizeAgentVisualStatusSemantic(
  AppLocalizations l10n,
  AgentVisualStatus status,
) {
  return l10n.agentStatusSemantic(localizeAgentVisualStatus(l10n, status));
}

String localizeDaemonUpgradeProgress(
  AppLocalizations l10n,
  DaemonUpgradeProgress progress,
) {
  return _localizeDaemonUpgradeStage(l10n, progress.stage);
}

String localizeDaemonUpgradeProgressCompact(
  AppLocalizations l10n,
  DaemonUpgradeProgress progress,
) {
  final message = localizeDaemonUpgradeProgress(l10n, progress);
  final percent = progress.percent;
  if (percent != null && percent > 0 && percent < 100) {
    return '$message ${percent.round()}%';
  }
  if (percent != null && percent >= 100) {
    return '$message 100%';
  }
  return message;
}

String _localizeDaemonUpgradeStage(AppLocalizations l10n, String stage) {
  return switch (stage.trim().toLowerCase()) {
    'requested' => l10n.daemonUpgradeRequesting,
    'waiting_for_daemon' => l10n.daemonUpgradeWaitingForDaemon,
    'manifest' => l10n.daemonUpgradeFetchingManifest,
    'selecting_source' => l10n.daemonUpgradeSelectingSource,
    'downloading' => l10n.daemonUpgradeDownloading,
    'retrying_source' => l10n.daemonUpgradeRetryingSource,
    'verifying' => l10n.daemonUpgradeVerifying,
    'extracting' => l10n.daemonUpgradeExtracting,
    'installing' => l10n.daemonUpgradeInstalling,
    'restarting' => l10n.daemonUpgradeRestarting,
    _ => l10n.daemonUpgradeInProgress,
  };
}

String localizeAgentListSubtitle(
  AppLocalizations l10n,
  AgentRuntimeDisplay runtime,
  AgentVisualStatus visualStatus, {
  bool isRuntime = false,
  int runtimeCount = 0,
  bool isUpgrading = false,
  bool isCancelling = false,
  DaemonUpgradeProgress? upgradeProgress,
  String? upgradeError,
  bool isDeleting = false,
}) {
  if (isDeleting) {
    return l10n.agentListDeletingSync;
  }
  final statusLabel = upgradeError != null
      ? l10n.agentListUpgradeFailed
      : isCancelling
      ? l10n.agentListCancellingUpgrade
      : isUpgrading
      ? upgradeProgress == null
            ? l10n.daemonUpgradeInProgress
            : localizeDaemonUpgradeProgressCompact(l10n, upgradeProgress)
      : localizeAgentVisualStatus(l10n, visualStatus);
  if (isRuntime) {
    return l10n.agentRuntimeSubtitle(runtime.label, statusLabel);
  }
  return l10n.agentDaemonSubtitle(runtimeCount, statusLabel);
}

String localizeAgentUiMessage(AppLocalizations l10n, String message) {
  if (message.startsWith(AgentUiMessageCodes.upgradeDownloadFailedPrefix)) {
    final summary = message
        .substring(AgentUiMessageCodes.upgradeDownloadFailedPrefix.length)
        .trim();
    return l10n.agentUpgradeDownloadFailed(summary);
  }
  return switch (message) {
    AgentUiMessageCodes.loginRequired => l10n.agentErrorLoginRequired,
    AgentUiMessageCodes.handleUnavailable => l10n.agentErrorHandleUnavailable,
    AgentUiMessageCodes.messageAgentDisabled =>
      l10n.agentErrorMessageAgentDisabled,
    AgentUiMessageCodes.selectDaemon => l10n.agentErrorSelectDaemon,
    AgentUiMessageCodes.daemonBootstrapMissing =>
      l10n.agentErrorDaemonBootstrapMissing,
    AgentUiMessageCodes.daemonUnreachableDelete =>
      l10n.agentErrorDaemonUnreachableDelete,
    AgentUiMessageCodes.messageAgentMissing =>
      l10n.agentErrorMessageAgentMissing,
    AgentUiMessageCodes.statusSyncWaiting => l10n.agentStatusSyncStillWaiting,
    AgentUiMessageCodes.upgradeCancelNoResponse =>
      l10n.agentUpgradeCancelNoResponse,
    AgentUiMessageCodes.scopeMismatch => l10n.agentErrorScopeMismatch,
    AgentUiMessageCodes.controllerHandleMismatch =>
      l10n.agentErrorControllerHandleMismatch,
    AgentUiMessageCodes.controllerScopeMissing =>
      l10n.agentErrorControllerScopeMissing,
    AgentUiMessageCodes.installCommandUsed => l10n.agentErrorInstallCommandUsed,
    AgentUiMessageCodes.sessionExpired => l10n.agentErrorSessionExpired,
    AgentUiMessageCodes.requestTimeout => l10n.agentErrorRequestTimeout,
    AgentUiMessageCodes.networkPreserved => l10n.agentErrorNetworkPreserved,
    AgentUiMessageCodes.loadFailed => l10n.agentErrorLoadFailed,
    AgentUiMessageCodes.statusSessionExpired =>
      l10n.agentErrorStatusSessionExpired,
    AgentUiMessageCodes.statusTimeout => l10n.agentErrorStatusTimeout,
    AgentUiMessageCodes.statusNetworkPreserved =>
      l10n.agentErrorStatusNetworkPreserved,
    AgentUiMessageCodes.statusRefreshFailed =>
      l10n.agentErrorStatusRefreshFailed,
    AgentUiMessageCodes.upgradeIncomplete => l10n.agentUpgradeIncomplete,
    AgentUiMessageCodes.upgradeNotCancellable =>
      l10n.agentUpgradeNotCancellable,
    AgentUiMessageCodes.upgradeCancelFailed => l10n.agentUpgradeCancelFailed,
    _ => message,
  };
}

String? localizeConversationCompactBadge(
  AppLocalizations l10n,
  ConversationPeerClassification classification,
) {
  if (classification.isGroup) {
    return l10n.conversationPeerBadgeGroup;
  }
  if (classification.isAgent) {
    return l10n.conversationPeerBadgeAi;
  }
  return null;
}

String? localizeConversationChatBadge(
  AppLocalizations l10n,
  ConversationPeerClassification classification,
) {
  if (classification.isMyRuntimeAgent) {
    return l10n.conversationPeerChatBadgeMyAgent;
  }
  if (classification.isAgent) {
    return l10n.conversationPeerChatBadgeAgent;
  }
  return null;
}

String localizeConversationPeerType(
  AppLocalizations l10n,
  ConversationPeerClassification classification,
) {
  return switch (classification.kind) {
    ConversationPeerKind.group => l10n.conversationPeerTypeGroup,
    ConversationPeerKind.myRuntimeAgent ||
    ConversationPeerKind.agent => l10n.conversationPeerTypeAgent,
    ConversationPeerKind.human ||
    ConversationPeerKind.unknown => l10n.conversationPeerTypeUser,
  };
}

String localizeConversationPeerOwner(
  AppLocalizations l10n,
  ConversationPeerClassification classification,
) {
  return switch (classification.kind) {
    ConversationPeerKind.group => l10n.conversationPeerOwnerGroup,
    ConversationPeerKind.myRuntimeAgent =>
      l10n.conversationPeerOwnerMyRuntimeAgent,
    ConversationPeerKind.agent => l10n.conversationPeerOwnerAgent,
    ConversationPeerKind.human ||
    ConversationPeerKind.unknown => l10n.conversationPeerOwnerUser,
  };
}

String localizeAttachmentName(
  AppLocalizations l10n,
  ChatAttachment attachment,
) {
  return localizeAttachmentFilename(l10n, attachment.filename);
}

String localizeAttachmentDraftName(
  AppLocalizations l10n,
  AttachmentDraft attachment,
) {
  return localizeAttachmentFilename(l10n, attachment.filename);
}

String localizeAttachmentFilename(AppLocalizations l10n, String filename) {
  final normalized = filename.trim();
  if (normalized.isEmpty || _isLegacyUntitledAttachment(normalized)) {
    return l10n.chatAttachmentFileFallback;
  }
  return normalized;
}

String localizeMessagePreview(AppLocalizations l10n, ChatMessage message) {
  final attachment = message.attachment;
  if (attachment != null) {
    final caption = attachment.caption?.trim();
    if (caption != null && caption.isNotEmpty) {
      return markdownPlainTextPreview(caption);
    }
    return l10n.conversationsAttachmentPreview(
      localizeAttachmentName(l10n, attachment),
    );
  }
  return localizeLegacyConversationPreview(l10n, message.previewText);
}

String localizeConversationPreview(
  AppLocalizations l10n,
  ConversationSummary conversation,
) {
  final snapshot = conversation.lastMessageSnapshot;
  if (snapshot != null) {
    return localizeMessagePreview(l10n, snapshot);
  }
  return localizeLegacyConversationPreview(
    l10n,
    conversation.lastMessagePreview,
  );
}

String localizeLegacyConversationPreview(
  AppLocalizations l10n,
  String preview,
) {
  final normalized = preview.trim();
  if (normalized.isEmpty) {
    return '';
  }
  for (final prefix in const <String>['[Attachment]', '[附件]']) {
    if (normalized == prefix) {
      return l10n.conversationsAttachmentPreview(
        l10n.chatAttachmentFileFallback,
      );
    }
    if (normalized.startsWith('$prefix ')) {
      final filename = normalized.substring(prefix.length).trim();
      return l10n.conversationsAttachmentPreview(
        localizeAttachmentFilename(l10n, filename),
      );
    }
  }
  return markdownPlainTextPreview(normalized);
}

bool _isLegacyUntitledAttachment(String value) {
  final normalized = value.trim().toLowerCase();
  return normalized == 'untitled attachment';
}

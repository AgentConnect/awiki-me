part of '../chat_page.dart';

class _DateDivider extends StatelessWidget {
  const _DateDivider({required this.label});

  final String label;

  @override
  Widget build(BuildContext context) {
    final responsive = context.awikiResponsive;
    final theme = context.awikiTheme;
    return Padding(
      padding: EdgeInsets.fromLTRB(
        0,
        responsive.displayScaled(12),
        0,
        responsive.displayScaled(6),
      ),
      child: Center(
        child: Text(
          label,
          style: TextStyle(
            color: theme.secondaryText,
            fontSize: 11,
            fontFeatures: const <FontFeature>[FontFeature.tabularFigures()],
          ),
        ),
      ),
    );
  }
}

class _AgentProcessingIndicator extends StatelessWidget {
  const _AgentProcessingIndicator({
    required this.label,
    required this.avatarSeed,
    required this.macStyle,
  });

  final String label;
  final String avatarSeed;
  final bool macStyle;

  @override
  Widget build(BuildContext context) {
    final responsive = context.awikiResponsive;
    final theme = context.awikiTheme;
    final bubbleColor = macStyle ? AwikiMePalette.mist : theme.subtleSurface;
    final borderColor = macStyle
        ? AwikiMePalette.hairline
        : theme.border.withValues(alpha: 0.72);
    final textColor = macStyle
        ? AwikiMePalette.mutedNeutral
        : theme.secondaryText;
    return Semantics(
      liveRegion: true,
      label: label,
      child: Row(
        mainAxisAlignment: MainAxisAlignment.start,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          AvatarBadge(
            seed: avatarSeed,
            size: macStyle
                ? responsive.displayScaled(34)
                : responsive.scaled(28),
          ),
          SizedBox(
            width: macStyle
                ? responsive.displayScaled(10)
                : responsive.spacing(12),
          ),
          Flexible(
            child: ConstrainedBox(
              constraints: BoxConstraints(
                maxWidth: macStyle
                    ? responsive.displayScaled(420)
                    : (responsive.isLarge ? 500 : 640),
              ),
              child: Container(
                padding: EdgeInsets.symmetric(
                  horizontal: macStyle
                      ? responsive.displayScaled(13)
                      : responsive.spacing(15),
                  vertical: macStyle
                      ? responsive.displayScaled(9)
                      : responsive.spacing(12),
                ),
                decoration: BoxDecoration(
                  color: bubbleColor,
                  borderRadius: BorderRadius.only(
                    topLeft: Radius.circular(
                      macStyle
                          ? responsive.displayScaled(8)
                          : responsive.scaled(6),
                    ),
                    topRight: Radius.circular(
                      macStyle
                          ? responsive.displayScaled(10)
                          : responsive.scaled(20),
                    ),
                    bottomLeft: Radius.circular(
                      macStyle
                          ? responsive.displayScaled(10)
                          : responsive.scaled(20),
                    ),
                    bottomRight: Radius.circular(
                      macStyle
                          ? responsive.displayScaled(10)
                          : responsive.scaled(20),
                    ),
                  ),
                  border: Border.all(color: borderColor),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: <Widget>[
                    CupertinoActivityIndicator(
                      radius: macStyle
                          ? responsive.displayScaled(6.5)
                          : responsive.scaled(7),
                      color: textColor,
                    ),
                    SizedBox(
                      width: macStyle
                          ? responsive.displayScaled(8)
                          : responsive.spacing(9),
                    ),
                    Flexible(
                      child: Text(
                        label,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          color: textColor,
                          fontSize: macStyle
                              ? responsive.displayScaled(13)
                              : responsive.metaSm,
                          fontWeight: FontWeight.w400,
                          height: 1.3,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _PersonalAgentProcessingStatus extends StatelessWidget {
  const _PersonalAgentProcessingStatus({
    required this.label,
    required this.overdue,
    required this.macStyle,
    required this.alignEnd,
  });

  final String label;
  final bool overdue;
  final bool macStyle;
  final bool alignEnd;

  @override
  Widget build(BuildContext context) {
    final responsive = context.awikiResponsive;
    final theme = context.awikiTheme;
    final foreground = overdue
        ? (macStyle ? const Color(0xFF9A5A00) : const Color(0xFF936300))
        : (macStyle ? AwikiMePalette.mutedNeutral : theme.secondaryText);
    final background = overdue
        ? const Color(0xFFFFF5DC)
        : (macStyle ? AwikiMePalette.mist : theme.subtleSurface);
    final border = overdue
        ? const Color(0xFFE9D49D)
        : (macStyle
              ? AwikiMePalette.hairline
              : theme.border.withValues(alpha: 0.68));
    final iconSize = macStyle
        ? responsive.displayScaled(12.5)
        : responsive.scaled(13);
    final horizontalInset = macStyle
        ? responsive.displayScaled(6)
        : responsive.spacing(6);
    return Semantics(
      liveRegion: true,
      label: label,
      child: Padding(
        padding: EdgeInsetsDirectional.only(
          start: alignEnd ? 0 : horizontalInset,
          end: alignEnd ? horizontalInset : 0,
        ),
        child: Align(
          alignment: alignEnd ? Alignment.centerRight : Alignment.centerLeft,
          child: ConstrainedBox(
            constraints: BoxConstraints(
              maxWidth: macStyle
                  ? responsive.displayScaled(320)
                  : (responsive.isLarge ? 360 : 300),
            ),
            child: Container(
              padding: EdgeInsets.symmetric(
                horizontal: macStyle
                    ? responsive.displayScaled(9)
                    : responsive.spacing(10),
                vertical: macStyle
                    ? responsive.displayScaled(5)
                    : responsive.spacing(6),
              ),
              decoration: BoxDecoration(
                color: background,
                borderRadius: BorderRadius.circular(
                  macStyle ? responsive.displayScaled(8) : 12,
                ),
                border: Border.all(color: border),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: <Widget>[
                  if (overdue)
                    Icon(
                      CupertinoIcons.clock,
                      color: foreground,
                      size: iconSize,
                    )
                  else
                    CupertinoActivityIndicator(
                      radius: iconSize / 2,
                      color: foreground,
                    ),
                  SizedBox(
                    width: macStyle
                        ? responsive.displayScaled(7)
                        : responsive.spacing(7),
                  ),
                  Flexible(
                    child: Text(
                      label,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        color: foreground,
                        fontSize: macStyle
                            ? responsive.displayScaled(11.5)
                            : responsive.metaSm,
                        fontWeight: FontWeight.w400,
                        height: 1.25,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _GroupSystemEventNotice extends ConsumerWidget {
  const _GroupSystemEventNotice({
    required this.message,
    required this.macStyle,
  });

  final ChatMessage message;
  final bool macStyle;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final responsive = context.awikiResponsive;
    final theme = context.awikiTheme;
    final event = message.groupSystemEvent;
    final actorName = event == null
        ? null
        : ref.watch(
            publicIdentityDisplayNameProvider(
              PublicIdentityDisplayNameRequest(
                did: event.actorDid,
                unknownLabel: context.l10n.commonUnknown,
              ),
            ),
          );
    final subjectName = event == null
        ? null
        : ref.watch(
            publicIdentityDisplayNameProvider(
              PublicIdentityDisplayNameRequest(
                did: event.subjectDid,
                unknownLabel: context.l10n.commonUnknown,
              ),
            ),
          );
    final text = localizeMessagePreview(
      context.l10n,
      message,
      groupEventActorName: actorName,
      groupEventSubjectName: subjectName,
    );
    final foreground = theme.secondaryText;
    final background = theme.subtleSurface;
    return Semantics(
      liveRegion: true,
      label: text,
      child: Center(
        child: ConstrainedBox(
          constraints: BoxConstraints(
            maxWidth: macStyle
                ? responsive.displayScaled(360)
                : (responsive.isLarge ? 420 : 300),
          ),
          child: Container(
            padding: EdgeInsets.symmetric(
              horizontal: macStyle
                  ? responsive.displayScaled(10)
                  : responsive.spacing(11),
              vertical: macStyle
                  ? responsive.displayScaled(5)
                  : responsive.spacing(6),
            ),
            decoration: BoxDecoration(
              color: background,
              borderRadius: BorderRadius.circular(999),
            ),
            child: Text(
              text,
              key: Key('chat-group-system-event:${message.localId}'),
              textAlign: TextAlign.center,
              maxLines: 3,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                color: foreground,
                fontSize: macStyle
                    ? responsive.displayScaled(12)
                    : responsive.metaSm,
                fontWeight: FontWeight.w400,
                height: 1.25,
              ),
            ),
          ),
        ),
      ),
    );
  }
}

sealed class _PersonalAgentTimelineItem {
  const _PersonalAgentTimelineItem();
}

class _PersonalAgentSyncTimelineItem extends _PersonalAgentTimelineItem {
  const _PersonalAgentSyncTimelineItem(this.record);

  final PersonalAgentSyncRecord record;
}

class _PersonalAgentActionTimelineItem extends _PersonalAgentTimelineItem {
  const _PersonalAgentActionTimelineItem(this.record);

  final AppActionRecord record;
}

class _PersonalAgentRecoveryCard extends StatelessWidget {
  const _PersonalAgentRecoveryCard({
    required this.item,
    required this.macStyle,
    this.onConfirm,
    this.onReject,
  });

  final _PersonalAgentTimelineItem item;
  final bool macStyle;
  final Future<void> Function()? onConfirm;
  final Future<void> Function()? onReject;

  @override
  Widget build(BuildContext context) {
    final responsive = context.awikiResponsive;
    final theme = context.awikiTheme;
    final content = switch (item) {
      _PersonalAgentSyncTimelineItem(:final record) =>
        _PersonalAgentCardContent.sync(record, context.l10n),
      _PersonalAgentActionTimelineItem(:final record) =>
        _PersonalAgentCardContent.action(record, context.l10n),
    };
    final isAttention = content.tone == _PersonalAgentCardTone.attention;
    final isDanger = content.tone == _PersonalAgentCardTone.danger;
    final accent = isDanger
        ? theme.danger
        : isAttention
        ? const Color(0xFF996300)
        : theme.primary;
    final background = macStyle
        ? CupertinoColors.white
        : (isDanger
              ? const Color(0xFFFFF3F1)
              : isAttention
              ? const Color(0xFFFFF7E6)
              : theme.subtleSurface);
    final border = isDanger
        ? const Color(0xFFFFD1CA)
        : isAttention
        ? const Color(0xFFEAD49A)
        : (macStyle
              ? AwikiMePalette.hairline
              : theme.border.withValues(alpha: 0.76));
    final width = macStyle
        ? responsive.displayScaled(420)
        : (responsive.isLarge ? 500.0 : 640.0);
    return Semantics(
      liveRegion: true,
      label: content.title,
      child: Align(
        alignment: Alignment.centerLeft,
        child: ConstrainedBox(
          constraints: BoxConstraints(maxWidth: width),
          child: Container(
            key: Key('personal-agent-card:${content.keySuffix}'),
            padding: EdgeInsets.symmetric(
              horizontal: macStyle
                  ? responsive.displayScaled(12)
                  : responsive.spacing(14),
              vertical: macStyle
                  ? responsive.displayScaled(10)
                  : responsive.spacing(12),
            ),
            decoration: BoxDecoration(
              color: background,
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: border),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: <Widget>[
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: <Widget>[
                    Icon(
                      content.icon,
                      color: accent,
                      size: macStyle
                          ? responsive.displayScaled(16)
                          : responsive.iconSm,
                    ),
                    SizedBox(
                      width: macStyle
                          ? responsive.displayScaled(8)
                          : responsive.spacing(9),
                    ),
                    Expanded(
                      child: Text(
                        content.title,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          color: macStyle
                              ? AwikiMePalette.inkNeutral
                              : theme.title,
                          fontSize: macStyle
                              ? responsive.displayScaled(13)
                              : responsive.metaSm,
                          fontWeight: FontWeight.w400,
                          height: 1.25,
                        ),
                      ),
                    ),
                  ],
                ),
                if (content.detail != null) ...<Widget>[
                  SizedBox(
                    height: macStyle
                        ? responsive.displayScaled(7)
                        : responsive.spacing(7),
                  ),
                  Text(
                    content.detail!,
                    maxLines: 3,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      color: macStyle
                          ? AwikiMePalette.mutedNeutral
                          : theme.secondaryText,
                      fontSize: macStyle
                          ? responsive.displayScaled(12)
                          : responsive.metaSm,
                      fontWeight: FontWeight.w400,
                      height: 1.35,
                    ),
                  ),
                ],
                if (content.preview != null) ...<Widget>[
                  SizedBox(
                    height: macStyle
                        ? responsive.displayScaled(9)
                        : responsive.spacing(9),
                  ),
                  Container(
                    width: double.infinity,
                    padding: EdgeInsets.symmetric(
                      horizontal: macStyle
                          ? responsive.displayScaled(10)
                          : responsive.spacing(10),
                      vertical: macStyle
                          ? responsive.displayScaled(8)
                          : responsive.spacing(8),
                    ),
                    decoration: BoxDecoration(
                      color: macStyle
                          ? AwikiMePalette.mist
                          : theme.surface.withValues(alpha: 0.72),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Text(
                      content.preview!,
                      maxLines: 4,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        color: macStyle
                            ? AwikiMePalette.inkNeutral
                            : theme.title,
                        fontSize: macStyle
                            ? responsive.displayScaled(12.5)
                            : responsive.bodySm,
                        height: 1.35,
                      ),
                    ),
                  ),
                ],
                if (content.hasActions) ...<Widget>[
                  SizedBox(
                    height: macStyle
                        ? responsive.displayScaled(10)
                        : responsive.spacing(10),
                  ),
                  Wrap(
                    spacing: macStyle
                        ? responsive.displayScaled(8)
                        : responsive.spacing(8),
                    runSpacing: macStyle
                        ? responsive.displayScaled(8)
                        : responsive.spacing(8),
                    children: <Widget>[
                      _PersonalAgentActionButton(
                        key: Key(
                          'personal-agent-action-confirm:${content.keySuffix}',
                        ),
                        label: content.confirmLabel,
                        icon: CupertinoIcons.check_mark_circled,
                        accent: theme.primary,
                        macStyle: macStyle,
                        semanticsIdentifier:
                            'personal-agent-action-confirm:${content.keySuffix}',
                        onTap: onConfirm,
                      ),
                      _PersonalAgentActionButton(
                        key: Key(
                          'personal-agent-action-reject:${content.keySuffix}',
                        ),
                        label: content.rejectLabel,
                        icon: CupertinoIcons.xmark_circle,
                        accent: theme.secondaryText,
                        macStyle: macStyle,
                        semanticsIdentifier:
                            'personal-agent-action-reject:${content.keySuffix}',
                        onTap: onReject,
                      ),
                    ],
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _PersonalAgentActionButton extends StatelessWidget {
  const _PersonalAgentActionButton({
    super.key,
    required this.label,
    required this.icon,
    required this.accent,
    required this.macStyle,
    required this.semanticsIdentifier,
    required this.onTap,
  });

  final String label;
  final IconData icon;
  final Color accent;
  final bool macStyle;
  final String semanticsIdentifier;
  final Future<void> Function()? onTap;

  @override
  Widget build(BuildContext context) {
    final responsive = context.awikiResponsive;
    final enabled = onTap != null;
    return AppPressable(
      onTap: enabled ? () => unawaited(onTap!()) : null,
      enabled: enabled,
      semanticLabel: label,
      semanticsIdentifier: semanticsIdentifier,
      tooltip: label,
      borderRadius: BorderRadius.circular(8),
      child: const SizedBox.shrink(),
      builder: (context, state, child) {
        final foreground = enabled ? accent : context.awikiTheme.tertiaryText;
        return AnimatedContainer(
          duration: const Duration(milliseconds: 120),
          curve: Curves.easeOutCubic,
          padding: EdgeInsets.symmetric(
            horizontal: macStyle
                ? responsive.displayScaled(10)
                : responsive.spacing(10),
            vertical: macStyle
                ? responsive.displayScaled(6)
                : responsive.spacing(7),
          ),
          decoration: BoxDecoration(
            color: state.pressed
                ? foreground.withValues(alpha: 0.12)
                : foreground.withValues(alpha: 0.08),
            borderRadius: BorderRadius.circular(8),
            border: Border.all(color: foreground.withValues(alpha: 0.18)),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: <Widget>[
              Icon(
                icon,
                size: macStyle
                    ? responsive.displayScaled(14)
                    : responsive.scaled(14),
                color: foreground,
              ),
              SizedBox(
                width: macStyle
                    ? responsive.displayScaled(6)
                    : responsive.spacing(6),
              ),
              Text(
                label,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  color: foreground,
                  fontSize: macStyle
                      ? responsive.displayScaled(12)
                      : responsive.metaSm,
                  fontWeight: FontWeight.w400,
                  height: 1.2,
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}

enum _PersonalAgentCardTone { neutral, attention, danger }

class _PersonalAgentCardContent {
  const _PersonalAgentCardContent({
    required this.keySuffix,
    required this.title,
    required this.icon,
    this.detail,
    this.preview,
    this.tone = _PersonalAgentCardTone.neutral,
    required this.confirmLabel,
    required this.rejectLabel,
    this.hasActions = false,
  });

  final String keySuffix;
  final String title;
  final IconData icon;
  final String? detail;
  final String? preview;
  final _PersonalAgentCardTone tone;
  final String confirmLabel;
  final String rejectLabel;
  final bool hasActions;

  factory _PersonalAgentCardContent.sync(
    PersonalAgentSyncRecord record,
    AppLocalizations l10n,
  ) {
    final key = record.identityKey;
    if (record.isUnsupported) {
      return _PersonalAgentCardContent(
        keySuffix: key,
        title: l10n.personalAgentSkipped,
        icon: CupertinoIcons.exclamationmark_triangle,
        detail: _personalAgentOptionalDetail(record.unsupportedReason),
        tone: _PersonalAgentCardTone.attention,
        confirmLabel: l10n.commonConfirm,
        rejectLabel: l10n.commonReject,
      );
    }
    if (record.isFailed) {
      return _PersonalAgentCardContent(
        keySuffix: key,
        title: l10n.personalAgentFailed,
        icon: CupertinoIcons.exclamationmark_circle,
        detail:
            _personalAgentOptionalDetail(record.lastErrorSummary) ??
            _personalAgentOptionalDetail(record.lastErrorCode),
        tone: _PersonalAgentCardTone.danger,
        confirmLabel: l10n.commonConfirm,
        rejectLabel: l10n.commonReject,
      );
    }
    if (record.isRuntimeFinal) {
      return _PersonalAgentCardContent(
        keySuffix: key,
        title: l10n.personalAgentCompleted,
        icon: CupertinoIcons.check_mark_circled,
        detail: record.hasText ? l10n.personalAgentResultGenerated : null,
        preview: _personalAgentOptionalDetail(
          record.summaryText ?? record.draftText,
        ),
        confirmLabel: l10n.commonConfirm,
        rejectLabel: l10n.commonReject,
      );
    }
    if (record.isRuntimeStatus) {
      return _PersonalAgentCardContent(
        keySuffix: key,
        title: l10n.personalAgentProcessing,
        icon: CupertinoIcons.clock,
        detail: _personalAgentOptionalDetail(record.state),
        confirmLabel: l10n.commonConfirm,
        rejectLabel: l10n.commonReject,
      );
    }
    return _PersonalAgentCardContent(
      keySuffix: key,
      title: l10n.personalAgentReceived,
      icon: CupertinoIcons.bolt_horizontal_circle,
      detail: _personalAgentOptionalDetail(record.processingStatus),
      confirmLabel: l10n.commonConfirm,
      rejectLabel: l10n.commonReject,
    );
  }

  factory _PersonalAgentCardContent.action(
    AppActionRecord record,
    AppLocalizations l10n,
  ) {
    final request = record.request;
    final draft = _draftPreviewForAppActionRecord(record);
    if (record.state == appActionStateSucceeded) {
      return _PersonalAgentCardContent(
        keySuffix: record.actionId,
        title: record.action == 'message.create_draft'
            ? l10n.personalAgentDraftApplied
            : l10n.personalAgentAppActionCompleted,
        icon: CupertinoIcons.check_mark_circled,
        preview: draft,
        confirmLabel: l10n.commonConfirm,
        rejectLabel: l10n.commonReject,
      );
    }
    if (record.state == appActionStateRejected) {
      return _PersonalAgentCardContent(
        keySuffix: record.actionId,
        title: l10n.personalAgentRequestRejected,
        icon: CupertinoIcons.xmark_circle,
        tone: _PersonalAgentCardTone.attention,
        confirmLabel: l10n.commonConfirm,
        rejectLabel: l10n.commonReject,
      );
    }
    if (record.state == appActionStateFailed) {
      return _PersonalAgentCardContent(
        keySuffix: record.actionId,
        title: l10n.personalAgentAppActionFailed,
        icon: CupertinoIcons.exclamationmark_circle,
        detail:
            _personalAgentOptionalDetail(record.result?.errorSummary) ??
            _personalAgentOptionalDetail(record.result?.errorCode),
        preview: draft,
        tone: _PersonalAgentCardTone.danger,
        confirmLabel: l10n.commonConfirm,
        rejectLabel: l10n.commonReject,
      );
    }
    return _PersonalAgentCardContent(
      keySuffix: record.actionId,
      title: _appActionTitle(record.action, l10n),
      icon: CupertinoIcons.square_pencil,
      detail: request?.needsUserConfirmation == true
          ? l10n.personalAgentWaitingConfirmation
          : null,
      preview: draft,
      hasActions: true,
      confirmLabel: record.action == 'message.create_draft'
          ? l10n.personalAgentUseDraft
          : l10n.commonConfirm,
      rejectLabel: l10n.commonReject,
    );
  }
}

String _appActionTitle(String action, AppLocalizations l10n) {
  return switch (action) {
    'message.create_draft' => l10n.personalAgentActionCreateDraft,
    'message.summarize_plain' => l10n.personalAgentActionSummarize,
    'contact.read' => l10n.personalAgentActionReadContact,
    'contact.update_display_name' => l10n.personalAgentActionUpdateDisplayName,
    'contact.update_note' => l10n.personalAgentActionUpdateNote,
    _ => l10n.personalAgentActionGeneric,
  };
}

String? _draftPreviewForAppActionRecord(AppActionRecord record) {
  final resultDraft = record.result?.result['draft_text']?.toString().trim();
  if (resultDraft != null && resultDraft.isNotEmpty) {
    return resultDraft;
  }
  final args = record.request?.args ?? const <String, Object?>{};
  String? value(Object? raw) {
    final text = raw?.toString().trim();
    return text == null || text.isEmpty ? null : text;
  }

  final message = args['message'];
  return value(args['draft_text']) ??
      value(args['draft']) ??
      value(args['text']) ??
      value(args['content']) ??
      (message is Map ? value(message['text']) : null);
}

String? _personalAgentOptionalDetail(String? value) {
  final trimmed = value?.trim();
  return trimmed == null || trimmed.isEmpty ? null : trimmed;
}

class _NewMessagesButton extends StatelessWidget {
  const _NewMessagesButton({required this.macStyle, required this.onTap});

  final bool macStyle;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final responsive = context.awikiResponsive;
    return Positioned(
      right: macStyle ? responsive.displayScaled(28) : responsive.spacing(18),
      bottom: macStyle ? responsive.displayScaled(18) : responsive.spacing(18),
      child: CupertinoButton(
        key: const Key('chat-new-messages-button'),
        minimumSize: Size.zero,
        padding: EdgeInsets.symmetric(
          horizontal: macStyle
              ? responsive.displayScaled(12)
              : responsive.spacing(12),
          vertical: macStyle
              ? responsive.displayScaled(7)
              : responsive.spacing(7),
        ),
        color: AwikiMePalette.brandAccent,
        borderRadius: BorderRadius.circular(999),
        onPressed: onTap,
        child: Text(
          context.l10n.conversationsNewMessages,
          style: TextStyle(
            color: CupertinoColors.white,
            fontSize: macStyle
                ? responsive.displayScaled(12)
                : responsive.metaSm,
            fontWeight: FontWeight.w400,
            letterSpacing: 0,
          ),
        ),
      ),
    );
  }
}

class _MessageAvatar extends StatelessWidget {
  const _MessageAvatar({
    required this.messageId,
    required this.label,
    required this.isMine,
    required this.size,
    this.avatarUri,
    this.userId,
  });

  final String messageId;
  final String label;
  final bool isMine;
  final double size;
  final String? avatarUri;
  final String? userId;

  @override
  Widget build(BuildContext context) {
    return KeyedSubtree(
      key: Key('chat-message-avatar:$messageId:${isMine ? 'mine' : 'peer'}'),
      child: AvatarBadge(
        seed: label,
        size: size,
        avatarUri: avatarUri,
        userId: userId,
      ),
    );
  }
}

class _ChatBubbleShapeBorder extends ShapeBorder {
  const _ChatBubbleShapeBorder({
    required this.isMine,
    required this.radius,
    required this.tailExtent,
    required this.side,
  });

  final bool isMine;
  final double radius;
  final double tailExtent;
  final BorderSide side;

  @override
  EdgeInsetsGeometry get dimensions => EdgeInsets.zero;

  @override
  Path getInnerPath(Rect rect, {TextDirection? textDirection}) {
    return _buildPath(rect.deflate(side.width));
  }

  @override
  Path getOuterPath(Rect rect, {TextDirection? textDirection}) {
    return _buildPath(rect);
  }

  Path _buildPath(Rect rect) {
    final width = rect.width;
    final height = rect.height;
    final resolvedTail = tailExtent.clamp(0.0, width / 3).toDouble();
    final bodyWidth = width - resolvedTail;
    final maxRadiusByHeight = ((height - 9) / 2).clamp(0.0, height / 2);
    final maxRadius = bodyWidth < height ? bodyWidth / 2 : maxRadiusByHeight;
    final resolvedRadius = radius.clamp(0.0, maxRadius).toDouble();
    final joinHalfHeight = (resolvedTail * 0.8).clamp(4.0, 5.0);
    final minTailCenter = resolvedRadius + joinHalfHeight;
    final maxTailCenter = height - resolvedRadius - joinHalfHeight;
    final preferredTailCenter = resolvedRadius + 4;
    final tailCenter = maxTailCenter >= minTailCenter
        ? preferredTailCenter.clamp(minTailCenter, maxTailCenter).toDouble()
        : height / 2;
    final bodyLeft = resolvedTail;
    final bodyRight = width;
    const tipX = 1.0;

    double x(double localX) =>
        isMine ? rect.right - localX : rect.left + localX;
    double y(double localY) => rect.top + localY;

    return Path()
      ..moveTo(x(bodyLeft + resolvedRadius), y(0))
      ..lineTo(x(bodyRight - resolvedRadius), y(0))
      ..quadraticBezierTo(x(bodyRight), y(0), x(bodyRight), y(resolvedRadius))
      ..lineTo(x(bodyRight), y(height - resolvedRadius))
      ..quadraticBezierTo(
        x(bodyRight),
        y(height),
        x(bodyRight - resolvedRadius),
        y(height),
      )
      ..lineTo(x(bodyLeft + resolvedRadius), y(height))
      ..quadraticBezierTo(
        x(bodyLeft),
        y(height),
        x(bodyLeft),
        y(height - resolvedRadius),
      )
      ..lineTo(x(bodyLeft), y(tailCenter + joinHalfHeight))
      ..cubicTo(
        x(bodyLeft - 0.8),
        y(tailCenter + joinHalfHeight - 0.3),
        x(tipX + 2.8),
        y(tailCenter + 2.8),
        x(tipX + 1.3),
        y(tailCenter + 1.3),
      )
      ..quadraticBezierTo(
        x(tipX - 0.2),
        y(tailCenter),
        x(tipX + 1.3),
        y(tailCenter - 1.3),
      )
      ..cubicTo(
        x(tipX + 2.8),
        y(tailCenter - 2.8),
        x(bodyLeft - 0.8),
        y(tailCenter - joinHalfHeight + 0.3),
        x(bodyLeft),
        y(tailCenter - joinHalfHeight),
      )
      ..lineTo(x(bodyLeft), y(resolvedRadius))
      ..quadraticBezierTo(x(bodyLeft), y(0), x(bodyLeft + resolvedRadius), y(0))
      ..close();
  }

  @override
  void paint(Canvas canvas, Rect rect, {TextDirection? textDirection}) {
    if (side.style == BorderStyle.none || side.width <= 0) {
      return;
    }
    canvas.drawPath(
      getOuterPath(rect, textDirection: textDirection),
      side.toPaint()
        ..isAntiAlias = true
        ..strokeJoin = StrokeJoin.round,
    );
  }

  @override
  ShapeBorder scale(double t) {
    return _ChatBubbleShapeBorder(
      isMine: isMine,
      radius: radius * t,
      tailExtent: tailExtent * t,
      side: side.scale(t),
    );
  }

  @override
  bool operator ==(Object other) {
    return other is _ChatBubbleShapeBorder &&
        other.isMine == isMine &&
        other.radius == radius &&
        other.tailExtent == tailExtent &&
        other.side == side;
  }

  @override
  int get hashCode => Object.hash(isMine, radius, tailExtent, side);
}

class _MessageBubble extends StatelessWidget {
  const _MessageBubble({
    required this.message,
    required this.mentionPresentation,
    required this.senderLabel,
    required this.senderAvatarUri,
    required this.senderAvatarUserId,
    required this.showSenderLabel,
    this.macStyle = false,
    this.onRetry,
    this.onDownload,
    this.onCancelDownload,
    this.onResolveImagePreview,
    this.onCopyImage,
    this.onSaveImage,
    this.isDownloading = false,
    this.onSenderInfoTap,
  });

  final ChatMessage message;
  final ChatMentionPresentationResolver mentionPresentation;
  final String senderLabel;
  final String? senderAvatarUri;
  final String? senderAvatarUserId;
  final bool showSenderLabel;
  final bool macStyle;
  final Future<void> Function()? onRetry;
  final Future<void> Function()? onDownload;
  final Future<void> Function()? onCancelDownload;
  final Future<String> Function()? onResolveImagePreview;
  final Future<void> Function(String path)? onCopyImage;
  final Future<void> Function(String path)? onSaveImage;
  final bool isDownloading;
  final VoidCallback? onSenderInfoTap;

  Widget _withE2eMessageSemantics({required Widget child}) {
    return e2eSemantics(
      identifier: e2eMessageIdentifier(message.content),
      label: message.content,
      child: child,
    );
  }

  Widget _withSenderInfoTap({
    required BuildContext context,
    required Widget child,
    required double borderRadius,
  }) {
    final tap = onSenderInfoTap;
    if (tap == null) {
      return child;
    }
    return AppPressable(
      onTap: tap,
      semanticLabel: context.l10n.chatViewPeerInfo,
      tooltip: context.l10n.chatViewPeerInfo,
      borderRadius: BorderRadius.circular(borderRadius),
      child: child,
    );
  }

  ({double fontSize, double bottomSpacing}) _senderLabelMetrics(
    BuildContext context, {
    required bool macStyle,
  }) {
    final responsive = context.awikiResponsive;
    return (
      fontSize: macStyle ? responsive.displayScaled(11.5) : responsive.metaSm,
      bottomSpacing: macStyle
          ? responsive.displayScaled(5)
          : responsive.spacing(5),
    );
  }

  Widget _buildSenderLabel(BuildContext context, {required bool macStyle}) {
    final responsive = context.awikiResponsive;
    final theme = context.awikiTheme;
    final metrics = _senderLabelMetrics(context, macStyle: macStyle);
    return Padding(
      padding: EdgeInsets.only(
        left: macStyle ? responsive.displayScaled(2) : responsive.spacing(4),
        bottom: metrics.bottomSpacing,
      ),
      child: Text(
        senderLabel,
        key: Key('chat-message-sender:${message.localId}'),
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: TextStyle(
          color: macStyle ? AwikiMePalette.mutedNeutral : theme.secondaryText,
          fontSize: metrics.fontSize,
          fontWeight: FontWeight.w400,
          height: 1.2,
        ),
      ),
    );
  }

  Widget _alignAvatarWithBubbleTop(
    BuildContext context, {
    required bool macStyle,
    required Widget child,
  }) {
    if (!showSenderLabel) {
      return child;
    }
    final metrics = _senderLabelMetrics(context, macStyle: macStyle);
    return Padding(
      padding: EdgeInsets.only(
        top: metrics.fontSize * 1.2 + metrics.bottomSpacing,
      ),
      child: child,
    );
  }

  Widget _withSendingIndicator(
    BuildContext context, {
    required bool isMine,
    required bool macStyle,
    required Widget child,
  }) {
    if (!isMine || message.sendState != MessageSendState.sending) {
      return child;
    }
    final responsive = context.awikiResponsive;
    final gap = macStyle ? responsive.displayScaled(7) : responsive.spacing(8);
    return _DelayedSendingMessageRow(
      key: ValueKey<String>('chat-delayed-send:${message.localId}'),
      messageId: message.localId,
      macStyle: macStyle,
      gap: gap,
      child: child,
    );
  }

  Widget? _buildAgentMessageCard(BuildContext context) {
    final projection = message.agentMessage;
    if (projection == null) return null;
    if (projection is InvalidAgentMessageProjection) {
      return Semantics(
        label: context.l10n.agentMessageUnsupported,
        child: Container(
          key: Key('agent-message-invalid:${message.localId}'),
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: context.awikiTheme.subtleSurface,
            border: Border.all(color: context.awikiTheme.border),
            borderRadius: BorderRadius.circular(12),
          ),
          child: Text(context.l10n.agentMessageUnsupported),
        ),
      );
    }
    final structured = (projection as ValidAgentMessageProjection).message;
    return AgentMessageCard(
      message: structured,
      timeLabel: _agentMessageTimeLabel(message.createdAt),
      copy: AgentMessageCardCopy(
        message: context.l10n.agentMessageKindMessage,
        taskResult: context.l10n.agentMessageKindTaskResult,
        alert: context.l10n.agentMessageKindAlert,
        urgent: context.l10n.agentMessageUrgent,
        urgentCall: context.l10n.agentMessageUrgentCall,
      ),
      onOpenConversation: null,
    );
  }

  Widget _buildMacBubble(
    BuildContext context,
    bool isMine,
    double maxBubbleWidth,
  ) {
    final responsive = context.awikiResponsive;
    final theme = context.awikiTheme;
    final attachment = message.attachment;
    final textStyle = TextStyle(
      color: isMine ? theme.onOutgoingMessage : theme.title,
      fontSize: 14,
      fontWeight: FontWeight.w400,
      height: 1.45,
    );
    final agentCard = _buildAgentMessageCard(context);
    final messageContent = message.attachment == null
        ? _MessageTextContent(
            text: message.content,
            mentions: message.mentions,
            payloadJson: message.payloadJson,
            mentionPresentation: mentionPresentation,
            style: textStyle,
            renderMarkdown: !isMine,
          )
        : _AttachmentContent(
            message: message,
            mentionPresentation: mentionPresentation,
            macStyle: true,
            onDownload: onDownload,
            onCancelDownload: onCancelDownload,
            onResolveImagePreview: onResolveImagePreview,
            onCopyImage: onCopyImage,
            onSaveImage: onSaveImage,
            isDownloading: isDownloading,
          );
    final child = _MessageSelectableContent(
      key: Key('chat-message-selection:${message.localId}'),
      text: _copyableMessageText(context, message),
      child: messageContent,
    );
    final bubble = Column(
      crossAxisAlignment: isMine
          ? CrossAxisAlignment.end
          : CrossAxisAlignment.start,
      children: <Widget>[
        if (showSenderLabel) _buildSenderLabel(context, macStyle: true),
        _withSendingIndicator(
          context,
          isMine: isMine,
          macStyle: true,
          child: agentCard != null
              ? Container(
                  key: Key('chat-message-bubble:${message.localId}'),
                  constraints: BoxConstraints(maxWidth: maxBubbleWidth),
                  child: SelectionArea(child: agentCard),
                )
              : Container(
                  key: Key('chat-message-bubble:${message.localId}'),
                  constraints: BoxConstraints(maxWidth: maxBubbleWidth),
                  padding: EdgeInsets.symmetric(
                    horizontal: responsive.displayScaled(13),
                    vertical: responsive.displayScaled(9),
                  ),
                  decoration: BoxDecoration(
                    color: attachment != null
                        ? theme.surface
                        : isMine
                        ? theme.outgoingMessage
                        : theme.incomingMessage,
                    borderRadius: BorderRadius.only(
                      topLeft: Radius.circular(
                        responsive.displayScaled(isMine ? 13 : 4),
                      ),
                      topRight: Radius.circular(
                        responsive.displayScaled(isMine ? 4 : 13),
                      ),
                      bottomLeft: Radius.circular(responsive.displayScaled(13)),
                      bottomRight: Radius.circular(
                        responsive.displayScaled(13),
                      ),
                    ),
                    boxShadow: attachment != null
                        ? const <BoxShadow>[
                            BoxShadow(
                              color: Color(0x0D000000),
                              blurRadius: 2,
                              offset: Offset(0, 1),
                            ),
                          ]
                        : null,
                  ),
                  child: child,
                ),
        ),
        if (message.sendState == MessageSendState.failed) ...<Widget>[
          SizedBox(height: responsive.displayScaled(8)),
          Row(
            mainAxisSize: MainAxisSize.min,
            children: <Widget>[
              SelectionArea(
                child: Text(
                  context.l10n.chatSendFailed,
                  style: const TextStyle(
                    fontSize: 12,
                    color: AwikiMePalette.dangerRed,
                    fontWeight: FontWeight.w400,
                  ),
                ),
              ),
              if (onRetry != null) ...<Widget>[
                SizedBox(width: responsive.displayScaled(10)),
                AppPressableText(
                  key: Key('chat-retry-message:${message.localId}'),
                  onTap: onRetry,
                  semanticLabel: context.l10n.chatRetrySend,
                  child: Text(
                    context.l10n.commonRetry,
                    style: const TextStyle(
                      fontSize: 12,
                      color: AwikiMePalette.brandAccent,
                      fontWeight: FontWeight.w400,
                    ),
                  ),
                ),
              ],
            ],
          ),
        ],
      ],
    );
    return _withE2eMessageSemantics(
      child: Row(
        mainAxisAlignment: isMine
            ? MainAxisAlignment.end
            : MainAxisAlignment.start,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          if (!isMine) ...<Widget>[
            _alignAvatarWithBubbleTop(
              context,
              macStyle: true,
              child: _withSenderInfoTap(
                context: context,
                borderRadius: responsive.displayScaled(15),
                child: _MessageAvatar(
                  messageId: message.localId,
                  label: senderLabel,
                  avatarUri: senderAvatarUri,
                  userId: senderAvatarUserId,
                  isMine: false,
                  size: responsive.displayScaled(30),
                ),
              ),
            ),
            SizedBox(width: responsive.displayScaled(8)),
          ],
          Flexible(child: bubble),
          if (isMine) ...<Widget>[
            SizedBox(width: responsive.displayScaled(8)),
            _alignAvatarWithBubbleTop(
              context,
              macStyle: true,
              child: _withSenderInfoTap(
                context: context,
                borderRadius: responsive.displayScaled(15),
                child: _MessageAvatar(
                  messageId: message.localId,
                  label: senderLabel,
                  avatarUri: senderAvatarUri,
                  userId: senderAvatarUserId,
                  isMine: true,
                  size: responsive.displayScaled(30),
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildCompactBubble(
    BuildContext context,
    bool isMine,
    double maxBubbleWidth,
  ) {
    final responsive = context.awikiResponsive;
    final theme = context.awikiTheme;
    final attachment = message.attachment;
    final textStyle = TextStyle(
      color: isMine ? theme.onOutgoingMessage : theme.title,
      fontSize: 14,
      fontWeight: FontWeight.w400,
      height: 1.45,
    );
    final agentCard = _buildAgentMessageCard(context);
    final messageContent = attachment == null
        ? _MessageTextContent(
            text: message.content,
            mentions: message.mentions,
            payloadJson: message.payloadJson,
            mentionPresentation: mentionPresentation,
            style: textStyle,
            renderMarkdown: !isMine,
          )
        : _AttachmentContent(
            message: message,
            mentionPresentation: mentionPresentation,
            macStyle: false,
            onDownload: onDownload,
            onCancelDownload: onCancelDownload,
            onResolveImagePreview: onResolveImagePreview,
            onCopyImage: onCopyImage,
            onSaveImage: onSaveImage,
            isDownloading: isDownloading,
          );
    final content = _MessageSelectableContent(
      key: Key('chat-message-selection:${message.localId}'),
      text: _copyableMessageText(context, message),
      child: messageContent,
    );
    final bubbleColor = attachment != null
        ? theme.surface
        : isMine
        ? theme.outgoingMessage
        : theme.surface;
    final bubbleBorderColor = isMine
        ? AwikiMePalette.brandAccent.withValues(alpha: 0.28)
        : theme.border;
    final bubbleRadius = responsive.displayScaled(16);
    final bubbleTailExtent = responsive.displayScaled(6);
    final bubbleShape = _ChatBubbleShapeBorder(
      isMine: isMine,
      radius: bubbleRadius,
      tailExtent: bubbleTailExtent,
      side: BorderSide(color: bubbleBorderColor),
    );
    final horizontalPadding = responsive.displayScaled(13);
    final bubble = Column(
      crossAxisAlignment: isMine
          ? CrossAxisAlignment.end
          : CrossAxisAlignment.start,
      children: <Widget>[
        if (showSenderLabel) _buildSenderLabel(context, macStyle: false),
        _withSendingIndicator(
          context,
          isMine: isMine,
          macStyle: false,
          child: agentCard != null
              ? Container(
                  key: Key('chat-message-bubble:${message.localId}'),
                  constraints: BoxConstraints(maxWidth: maxBubbleWidth),
                  child: SelectionArea(child: agentCard),
                )
              : Container(
                  key: Key('chat-message-bubble:${message.localId}'),
                  constraints: BoxConstraints(maxWidth: maxBubbleWidth),
                  padding: EdgeInsets.fromLTRB(
                    horizontalPadding + (isMine ? 0 : bubbleTailExtent),
                    responsive.displayScaled(9),
                    horizontalPadding + (isMine ? bubbleTailExtent : 0),
                    responsive.displayScaled(9),
                  ),
                  decoration: ShapeDecoration(
                    color: bubbleColor,
                    shape: bubbleShape,
                    shadows: attachment != null
                        ? const <BoxShadow>[
                            BoxShadow(
                              color: Color(0x0D000000),
                              blurRadius: 2,
                              offset: Offset(0, 1),
                            ),
                          ]
                        : null,
                  ),
                  child: content,
                ),
        ),
        if (message.sendState == MessageSendState.failed) ...<Widget>[
          SizedBox(height: responsive.spacing(6)),
          Row(
            mainAxisSize: MainAxisSize.min,
            children: <Widget>[
              SelectionArea(
                child: Text(
                  context.l10n.chatSendFailed,
                  style: TextStyle(
                    fontSize: responsive.metaSm,
                    color: theme.danger,
                    fontWeight: FontWeight.w400,
                  ),
                ),
              ),
              if (onRetry != null) ...<Widget>[
                SizedBox(width: responsive.spacing(10)),
                AppPressableText(
                  key: Key('chat-retry-message:${message.localId}'),
                  onTap: onRetry,
                  semanticLabel: context.l10n.chatRetrySend,
                  child: Text(
                    context.l10n.commonRetry,
                    style: TextStyle(
                      fontSize: responsive.metaSm,
                      color: theme.primaryDark,
                      fontWeight: FontWeight.w400,
                    ),
                  ),
                ),
              ],
            ],
          ),
        ],
      ],
    );
    return _withE2eMessageSemantics(
      child: Row(
        mainAxisAlignment: isMine
            ? MainAxisAlignment.end
            : MainAxisAlignment.start,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          if (!isMine) ...<Widget>[
            _alignAvatarWithBubbleTop(
              context,
              macStyle: false,
              child: _withSenderInfoTap(
                context: context,
                borderRadius: responsive.displayScaled(16),
                child: _MessageAvatar(
                  messageId: message.localId,
                  label: senderLabel,
                  avatarUri: senderAvatarUri,
                  userId: senderAvatarUserId,
                  isMine: false,
                  size: responsive.displayScaled(32),
                ),
              ),
            ),
            SizedBox(width: responsive.spacing(8)),
          ],
          Flexible(child: bubble),
          if (isMine) ...<Widget>[
            SizedBox(width: responsive.spacing(8)),
            _alignAvatarWithBubbleTop(
              context,
              macStyle: false,
              child: _withSenderInfoTap(
                context: context,
                borderRadius: responsive.displayScaled(16),
                child: _MessageAvatar(
                  messageId: message.localId,
                  label: senderLabel,
                  avatarUri: senderAvatarUri,
                  userId: senderAvatarUserId,
                  isMine: true,
                  size: responsive.displayScaled(32),
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final isMine = message.isMine;
    final responsive = context.awikiResponsive;
    return LayoutBuilder(
      builder: (context, constraints) {
        final fallbackWidth = responsive.displayScaled(macStyle ? 420 : 300);
        final availableWidth = constraints.maxWidth;
        final maxBubbleWidth = availableWidth.isFinite
            ? availableWidth * (macStyle ? 0.68 : 0.72)
            : fallbackWidth;
        if (macStyle) {
          return _buildMacBubble(context, isMine, maxBubbleWidth);
        }
        return _buildCompactBubble(context, isMine, maxBubbleWidth);
      },
    );
  }
}

String _agentMessageTimeLabel(DateTime value) {
  final local = value.toLocal();
  return '${local.hour.toString().padLeft(2, '0')}:'
      '${local.minute.toString().padLeft(2, '0')}';
}

class _DelayedSendingMessageRow extends StatefulWidget {
  const _DelayedSendingMessageRow({
    super.key,
    required this.messageId,
    required this.macStyle,
    required this.gap,
    required this.child,
  });

  static const Duration delay = Duration(seconds: 3);

  final String messageId;
  final bool macStyle;
  final double gap;
  final Widget child;

  @override
  State<_DelayedSendingMessageRow> createState() =>
      _DelayedSendingMessageRowState();
}

class _DelayedSendingMessageRowState extends State<_DelayedSendingMessageRow> {
  Timer? _timer;
  bool _showIndicator = false;

  @override
  void initState() {
    super.initState();
    _scheduleIndicator();
  }

  @override
  void didUpdateWidget(covariant _DelayedSendingMessageRow oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.messageId != widget.messageId) {
      _scheduleIndicator();
    }
  }

  void _scheduleIndicator() {
    _timer?.cancel();
    _showIndicator = false;
    _timer = Timer(_DelayedSendingMessageRow.delay, () {
      if (!mounted) {
        return;
      }
      setState(() => _showIndicator = true);
    });
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (!_showIndicator) {
      return widget.child;
    }
    return Row(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.center,
      children: <Widget>[
        _SendingMessageIndicator(
          key: Key('chat-sending-indicator:${widget.messageId}'),
          macStyle: widget.macStyle,
        ),
        SizedBox(width: widget.gap),
        Flexible(child: widget.child),
      ],
    );
  }
}

class _SendingMessageIndicator extends StatelessWidget {
  const _SendingMessageIndicator({super.key, required this.macStyle});

  final bool macStyle;

  @override
  Widget build(BuildContext context) {
    final responsive = context.awikiResponsive;
    final theme = context.awikiTheme;
    final size = macStyle
        ? responsive.displayScaled(18)
        : responsive.scaled(18);
    final radius = macStyle
        ? responsive.displayScaled(6)
        : responsive.scaled(6);
    return Semantics(
      label: context.l10n.chatSending,
      liveRegion: true,
      child: SizedBox.square(
        dimension: size,
        child: Center(
          child: CupertinoActivityIndicator(
            radius: radius,
            color: macStyle
                ? AwikiMePalette.messagePreview
                : theme.tertiaryText,
          ),
        ),
      ),
    );
  }
}

const int _maxInlineImageBytes = 20 * 1024 * 1024;

class _AttachmentContent extends ConsumerStatefulWidget {
  const _AttachmentContent({
    required this.message,
    required this.mentionPresentation,
    required this.macStyle,
    required this.onDownload,
    required this.onCancelDownload,
    required this.onResolveImagePreview,
    required this.onCopyImage,
    required this.onSaveImage,
    required this.isDownloading,
  });

  final ChatMessage message;
  final ChatMentionPresentationResolver mentionPresentation;
  final bool macStyle;
  final Future<void> Function()? onDownload;
  final Future<void> Function()? onCancelDownload;
  final Future<String> Function()? onResolveImagePreview;
  final Future<void> Function(String path)? onCopyImage;
  final Future<void> Function(String path)? onSaveImage;
  final bool isDownloading;

  @override
  ConsumerState<_AttachmentContent> createState() => _AttachmentContentState();
}

class _AttachmentContentState extends ConsumerState<_AttachmentContent> {
  AttachmentPreviewHandle? _previewHandle;
  AttachmentPreviewHandle? _transferHandle;

  @override
  void initState() {
    super.initState();
    _preparePreview();
  }

  @override
  void didUpdateWidget(covariant _AttachmentContent oldWidget) {
    super.didUpdateWidget(oldWidget);
    final oldAttachment = oldWidget.message.attachment;
    final attachment = widget.message.attachment;
    final gainedRemoteResolver =
        oldWidget.onResolveImagePreview == null &&
        widget.onResolveImagePreview != null;
    if (oldWidget.message.localId != widget.message.localId ||
        oldAttachment?.attachmentId != attachment?.attachmentId ||
        oldAttachment?.localPath != attachment?.localPath ||
        oldAttachment?.objectUri != attachment?.objectUri ||
        oldAttachment?.sizeBytes != attachment?.sizeBytes ||
        oldAttachment?.mimeType != attachment?.mimeType ||
        oldAttachment?.filename != attachment?.filename ||
        (oldWidget.onResolveImagePreview == null) !=
            (widget.onResolveImagePreview == null)) {
      _preparePreview(retryFailed: gainedRemoteResolver);
    }
  }

  void _preparePreview({bool retryFailed = false}) {
    final attachment = widget.message.attachment!;
    final handle = ref
        .read(attachmentPreviewServiceProvider)
        .previewHandleFor(widget.message);
    _transferHandle = handle;
    if (!_isInlineImageAttachment(attachment)) {
      _previewHandle = null;
      return;
    }
    final localPath = attachment.localPath?.trim();
    final sizeBytes = attachment.sizeBytes;
    final resolve = widget.onResolveImagePreview;
    final hasLocalSource = localPath != null && localPath.isNotEmpty;
    final canResolveRemote =
        resolve != null &&
        sizeBytes != null &&
        sizeBytes > 0 &&
        sizeBytes <= _maxInlineImageBytes;
    if (!hasLocalSource && !canResolveRemote) {
      _previewHandle = null;
      return;
    }

    _previewHandle = handle;
    final phase = handle.snapshot.phase;
    if ((phase == AttachmentPreviewPhase.idle ||
            (retryFailed && phase == AttachmentPreviewPhase.failed)) &&
        resolve != null) {
      unawaited(
        resolve().then<void>((_) {}, onError: (Object _, StackTrace _) {}),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final message = widget.message;
    final attachment = message.attachment!;
    final responsive = context.awikiResponsive;
    final theme = context.awikiTheme;
    final caption = attachment.caption?.trim() ?? '';
    final titleStyle = TextStyle(
      color: widget.macStyle ? AwikiMePalette.inkNeutral : theme.title,
      fontSize: 13,
      fontWeight: FontWeight.w400,
      height: 1.25,
    );
    final metaStyle = TextStyle(
      color: widget.macStyle
          ? AwikiMePalette.mutedNeutral
          : theme.secondaryText,
      fontSize: 11,
      fontWeight: FontWeight.w400,
      height: 1.25,
    );
    final attachmentBody = _buildAttachmentBody(
      context,
      attachment: attachment,
      titleStyle: titleStyle,
      metaStyle: metaStyle,
    );
    final hasCaption = caption.isNotEmpty;
    final captionGap = widget.macStyle
        ? responsive.displayScaled(9)
        : responsive.spacing(9);
    final content = hasCaption
        ? _AttachmentCaptionLayout(
            gap: captionGap,
            caption: _MessageTextContent(
              text: caption,
              mentions: message.mentions,
              payloadJson: message.payloadJson,
              mentionPresentation: widget.mentionPresentation,
              style: TextStyle(
                color: widget.macStyle
                    ? AwikiMePalette.inkNeutral
                    : theme.title,
                fontSize: widget.macStyle
                    ? responsive.displayScaled(14)
                    : responsive.bodyMd,
                height: 1.4,
              ),
              renderMarkdown: !message.isMine,
            ),
            divider: _AttachmentCaptionDivider(macStyle: widget.macStyle),
            attachment: attachmentBody,
          )
        : attachmentBody;
    return ConstrainedBox(
      key: Key('chat-attachment-content:${message.localId}'),
      constraints: BoxConstraints(
        minWidth: _previewHandle == null
            ? (widget.macStyle
                  ? responsive.displayScaled(280)
                  : responsive.displayScaled(240))
            : 0,
        maxWidth: widget.macStyle
            ? responsive.displayScaled(360)
            : responsive.displayScaled(300),
      ),
      child: content,
    );
  }

  Widget _buildAttachmentBody(
    BuildContext context, {
    required ChatAttachment attachment,
    required TextStyle titleStyle,
    required TextStyle metaStyle,
  }) {
    final handle = _previewHandle;
    if (handle == null) {
      final responsive = context.awikiResponsive;
      final transfer = _transferHandle;
      final card = SizedBox(
        width: widget.macStyle
            ? responsive.displayScaled(280)
            : responsive.displayScaled(240),
        child: _AttachmentFileCard(
          message: widget.message,
          macStyle: widget.macStyle,
          onDownload: widget.onDownload,
          onCancelDownload: widget.onCancelDownload,
          isDownloading: widget.isDownloading,
          titleStyle: titleStyle,
          metaStyle: metaStyle,
          transferSnapshot: transfer?.snapshot,
        ),
      );
      if (transfer == null) {
        return card;
      }
      return StreamBuilder<AttachmentPreviewSnapshot>(
        key: ObjectKey(transfer),
        stream: transfer.changes,
        initialData: transfer.snapshot,
        builder: (context, _) => SizedBox(
          width: widget.macStyle
              ? responsive.displayScaled(280)
              : responsive.displayScaled(240),
          child: _AttachmentFileCard(
            message: widget.message,
            macStyle: widget.macStyle,
            onDownload: widget.onDownload,
            onCancelDownload: widget.onCancelDownload,
            isDownloading: widget.isDownloading,
            titleStyle: titleStyle,
            metaStyle: metaStyle,
            transferSnapshot: transfer.snapshot,
          ),
        ),
      );
    }
    return StreamBuilder<AttachmentPreviewSnapshot>(
      key: ObjectKey(handle),
      stream: handle.changes,
      initialData: handle.snapshot,
      builder: (context, _) {
        final snapshot = handle.snapshot;
        final path = snapshot.path?.trim();
        final Widget content;
        if (snapshot.phase == AttachmentPreviewPhase.ready &&
            path != null &&
            path.isNotEmpty) {
          content = _InlineImagePreview(
            message: widget.message,
            path: path,
            onOpen: widget.onDownload,
            onCopy: widget.onCopyImage,
            onSave: widget.onSaveImage,
            onDecodeFailure: () {
              ref
                  .read(attachmentPreviewServiceProvider)
                  .reportPreviewDecodeFailure(
                    message: widget.message,
                    path: path,
                  );
            },
          );
        } else if (snapshot.phase == AttachmentPreviewPhase.failed) {
          content = _InlineImageFileFallback(
            message: widget.message,
            macStyle: widget.macStyle,
            onDownload: widget.onDownload,
            onCancelDownload: widget.onCancelDownload,
            isDownloading: widget.isDownloading,
            titleStyle: titleStyle,
            metaStyle: metaStyle,
            transferSnapshot: snapshot,
          );
        } else if (snapshot.phase == AttachmentPreviewPhase.paused) {
          content = _InlineImageFileFallback(
            message: widget.message,
            macStyle: widget.macStyle,
            onDownload: widget.onDownload,
            onCancelDownload: widget.onCancelDownload,
            isDownloading: widget.isDownloading,
            titleStyle: titleStyle,
            metaStyle: metaStyle,
            transferSnapshot: snapshot,
          );
        } else {
          content = _InlineImageLoading(
            onCancelDownload: widget.onCancelDownload,
            macStyle: widget.macStyle,
          );
        }
        return _InlineImageEnvelope(
          messageId: widget.message.localId,
          macStyle: widget.macStyle,
          dimensions: snapshot.dimensions,
          child: content,
        );
      },
    );
  }
}

class _AttachmentCaptionLayout extends MultiChildRenderObjectWidget {
  _AttachmentCaptionLayout({
    required this.gap,
    required Widget caption,
    required Widget divider,
    required Widget attachment,
  }) : super(children: <Widget>[caption, divider, attachment]);

  final double gap;

  @override
  _RenderAttachmentCaptionLayout createRenderObject(BuildContext context) {
    return _RenderAttachmentCaptionLayout(gap: gap);
  }

  @override
  void updateRenderObject(
    BuildContext context,
    _RenderAttachmentCaptionLayout renderObject,
  ) {
    renderObject.gap = gap;
  }
}

class _AttachmentCaptionParentData extends ContainerBoxParentData<RenderBox> {}

class _RenderAttachmentCaptionLayout extends RenderBox
    with
        ContainerRenderObjectMixin<RenderBox, _AttachmentCaptionParentData>,
        RenderBoxContainerDefaultsMixin<
          RenderBox,
          _AttachmentCaptionParentData
        > {
  _RenderAttachmentCaptionLayout({required double gap}) : _gap = gap;

  double _gap;

  double get gap => _gap;

  set gap(double value) {
    if (_gap == value) {
      return;
    }
    _gap = value;
    markNeedsLayout();
  }

  @override
  void setupParentData(RenderBox child) {
    if (child.parentData is! _AttachmentCaptionParentData) {
      child.parentData = _AttachmentCaptionParentData();
    }
  }

  @override
  void performLayout() {
    assert(childCount == 3);
    final caption = firstChild!;
    final divider = childAfter(caption)!;
    final attachment = childAfter(divider)!;
    final childConstraints = constraints.loosen();

    caption.layout(childConstraints, parentUsesSize: true);
    attachment.layout(childConstraints, parentUsesSize: true);
    final contentWidth = caption.size.width > attachment.size.width
        ? caption.size.width
        : attachment.size.width;
    final width = constraints.constrainWidth(contentWidth);
    divider.layout(
      BoxConstraints(minWidth: width, maxWidth: width),
      parentUsesSize: true,
    );

    final captionParentData =
        caption.parentData! as _AttachmentCaptionParentData;
    final dividerParentData =
        divider.parentData! as _AttachmentCaptionParentData;
    final attachmentParentData =
        attachment.parentData! as _AttachmentCaptionParentData;
    captionParentData.offset = Offset.zero;
    dividerParentData.offset = Offset(0, caption.size.height + gap);
    attachmentParentData.offset = Offset(
      0,
      caption.size.height + gap + divider.size.height + gap,
    );
    size = constraints.constrain(
      Size(
        width,
        caption.size.height +
            gap +
            divider.size.height +
            gap +
            attachment.size.height,
      ),
    );
  }

  @override
  void paint(PaintingContext context, Offset offset) {
    defaultPaint(context, offset);
  }

  @override
  bool hitTestChildren(BoxHitTestResult result, {required Offset position}) {
    return defaultHitTestChildren(result, position: position);
  }
}

const double _inlineImageFallbackAspectRatio = 4 / 3;
const double _inlineImageFallbackWidth = 240;
const double _minimumInlineImagePreviewExtent = 120;
const double _minimumInlineImageInteractiveExtent = 44;

Size _fitInlineImageEnvelope({
  required AttachmentImageDimensions? dimensions,
  required double devicePixelRatio,
  required double fallbackWidth,
  required double maxWidth,
  required double maxHeight,
  required double minimumPreviewExtent,
  required double minimumInteractiveExtent,
}) {
  assert(devicePixelRatio > 0 && devicePixelRatio.isFinite);
  assert(fallbackWidth > 0 && fallbackWidth.isFinite);
  assert(maxWidth >= 0 && maxWidth.isFinite);
  assert(maxHeight >= 0 && maxHeight.isFinite);
  assert(minimumPreviewExtent >= 0 && minimumPreviewExtent.isFinite);
  assert(minimumInteractiveExtent >= 0 && minimumInteractiveExtent.isFinite);
  if (maxWidth == 0 || maxHeight == 0) {
    return Size.zero;
  }

  final naturalSize = dimensions == null
      ? Size(fallbackWidth, fallbackWidth / _inlineImageFallbackAspectRatio)
      : Size(
          dimensions.pixelWidth / devicePixelRatio,
          dimensions.pixelHeight / devicePixelRatio,
        );
  var scale = 1.0;
  final widthScale = maxWidth / naturalSize.width;
  final heightScale = maxHeight / naturalSize.height;
  if (widthScale < scale) {
    scale = widthScale;
  }
  if (heightScale < scale) {
    scale = heightScale;
  }

  var contentWidth = naturalSize.width * scale;
  var contentHeight = naturalSize.height * scale;
  if (dimensions != null) {
    final longestSide = contentWidth > contentHeight
        ? contentWidth
        : contentHeight;
    if (longestSide < minimumPreviewExtent) {
      var previewScale = minimumPreviewExtent / longestSide;
      final maximumWidthScale = maxWidth / contentWidth;
      final maximumHeightScale = maxHeight / contentHeight;
      if (maximumWidthScale < previewScale) {
        previewScale = maximumWidthScale;
      }
      if (maximumHeightScale < previewScale) {
        previewScale = maximumHeightScale;
      }
      contentWidth *= previewScale;
      contentHeight *= previewScale;
    }
  }

  final minimumWidth = maxWidth < minimumInteractiveExtent
      ? maxWidth
      : minimumInteractiveExtent;
  final minimumHeight = maxHeight < minimumInteractiveExtent
      ? maxHeight
      : minimumInteractiveExtent;
  return Size(
    contentWidth < minimumWidth ? minimumWidth : contentWidth,
    contentHeight < minimumHeight ? minimumHeight : contentHeight,
  );
}

class _InlineImageEnvelope extends StatelessWidget {
  const _InlineImageEnvelope({
    required this.messageId,
    required this.macStyle,
    required this.dimensions,
    required this.child,
  });

  final String messageId;
  final bool macStyle;
  final AttachmentImageDimensions? dimensions;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final responsive = context.awikiResponsive;
    final preferredMaxExtent = macStyle
        ? responsive.displayScaled(320)
        : responsive.displayScaled(300);
    final radius = macStyle
        ? responsive.displayScaled(12)
        : responsive.displayScaled(14);
    final fallbackWidth = responsive.displayScaled(_inlineImageFallbackWidth);
    final minimumPreviewExtent = responsive.displayScaled(
      _minimumInlineImagePreviewExtent,
    );
    final minimumInteractiveExtent = responsive
        .displayScaled(_minimumInlineImageInteractiveExtent)
        .clamp(_minimumInlineImageInteractiveExtent, double.infinity)
        .toDouble();
    final devicePixelRatio = MediaQuery.devicePixelRatioOf(context);
    return LayoutBuilder(
      builder: (context, constraints) {
        final availableWidth = constraints.maxWidth.isFinite
            ? constraints.maxWidth
            : preferredMaxExtent;
        final maxExtent = availableWidth < preferredMaxExtent
            ? availableWidth
            : preferredMaxExtent;
        final availableHeight = constraints.maxHeight.isFinite
            ? constraints.maxHeight
            : preferredMaxExtent;
        final maxHeight = availableHeight < preferredMaxExtent
            ? availableHeight
            : preferredMaxExtent;
        final size = _fitInlineImageEnvelope(
          dimensions: dimensions,
          devicePixelRatio: devicePixelRatio,
          fallbackWidth: fallbackWidth,
          maxWidth: maxExtent,
          maxHeight: maxHeight,
          minimumPreviewExtent: minimumPreviewExtent,
          minimumInteractiveExtent: minimumInteractiveExtent,
        );
        return SizedBox(
          key: Key('chat-inline-image-envelope:$messageId'),
          width: size.width,
          height: size.height,
          child: ClipRRect(
            borderRadius: BorderRadius.circular(radius),
            child: ColoredBox(color: AwikiMePalette.mist, child: child),
          ),
        );
      },
    );
  }
}

class _InlineImageLoading extends StatelessWidget {
  const _InlineImageLoading({this.onCancelDownload, this.macStyle = false});

  final Future<void> Function()? onCancelDownload;
  final bool macStyle;

  @override
  Widget build(BuildContext context) {
    final cancel = onCancelDownload;
    return SizedBox.expand(
      key: const Key('chat-inline-image-loading'),
      child: Stack(
        alignment: Alignment.center,
        children: <Widget>[
          const CupertinoActivityIndicator(),
          if (cancel != null)
            Positioned(
              right: 8,
              bottom: 8,
              child: _AttachmentActionButton(
                key: const Key('chat-cancel-inline-image-download'),
                macStyle: macStyle,
                isLoading: true,
                onTap: cancel,
                onCancel: cancel,
                sizeOverride: 32,
              ),
            ),
        ],
      ),
    );
  }
}

class _InlineImageFileFallback extends StatelessWidget {
  const _InlineImageFileFallback({
    required this.message,
    required this.macStyle,
    required this.onDownload,
    required this.onCancelDownload,
    required this.isDownloading,
    required this.titleStyle,
    required this.metaStyle,
    required this.transferSnapshot,
  });

  final ChatMessage message;
  final bool macStyle;
  final Future<void> Function()? onDownload;
  final Future<void> Function()? onCancelDownload;
  final bool isDownloading;
  final TextStyle titleStyle;
  final TextStyle metaStyle;
  final AttachmentPreviewSnapshot? transferSnapshot;

  @override
  Widget build(BuildContext context) {
    final responsive = context.awikiResponsive;
    final padding = macStyle
        ? responsive.displayScaled(12)
        : responsive.spacing(12);
    final minimumCardWidth = macStyle
        ? responsive.displayScaled(220)
        : responsive.scaled(210);
    final minimumCardHeight = macStyle
        ? responsive.displayScaled(38)
        : responsive.scaled(40);
    return LayoutBuilder(
      builder: (context, constraints) {
        final canShowFullCard =
            constraints.maxWidth >= minimumCardWidth + padding * 2 &&
            constraints.maxHeight >= minimumCardHeight + padding * 2;
        if (canShowFullCard) {
          return SizedBox.expand(
            child: Center(
              child: Padding(
                padding: EdgeInsets.all(padding),
                child: _AttachmentFileCard(
                  message: message,
                  macStyle: macStyle,
                  onDownload: onDownload,
                  onCancelDownload: onCancelDownload,
                  isDownloading: isDownloading,
                  titleStyle: titleStyle,
                  metaStyle: metaStyle,
                  transferSnapshot: transferSnapshot,
                ),
              ),
            ),
          );
        }

        final open = onDownload;
        final compactContent = open == null
            ? Semantics(
                image: true,
                label: localizeAttachmentName(
                  context.l10n,
                  message.attachment!,
                ),
                child: Icon(
                  CupertinoIcons.doc_fill,
                  color: macStyle
                      ? AwikiMePalette.brandAccent
                      : context.awikiTheme.primary,
                  size: macStyle
                      ? responsive.displayScaled(20)
                      : responsive.iconSm,
                ),
              )
            : _AttachmentActionButton(
                key: Key('chat-open-attachment:${message.localId}'),
                macStyle: macStyle,
                isLoading: isDownloading,
                onTap: open,
                onCancel: onCancelDownload,
                sizeOverride: _minimumInlineImageInteractiveExtent,
              );
        return SizedBox.expand(
          key: Key('chat-inline-image-compact-fallback:${message.localId}'),
          child: FittedBox(fit: BoxFit.scaleDown, child: compactContent),
        );
      },
    );
  }
}

class _InlineImagePreview extends ConsumerWidget {
  const _InlineImagePreview({
    required this.message,
    required this.path,
    required this.onOpen,
    required this.onCopy,
    required this.onSave,
    required this.onDecodeFailure,
  });

  final ChatMessage message;
  final String path;
  final Future<void> Function()? onOpen;
  final Future<void> Function(String path)? onCopy;
  final Future<void> Function(String path)? onSave;
  final VoidCallback onDecodeFailure;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final preview = LayoutBuilder(
      builder: (context, constraints) {
        const framePlaceholder = _InlineImageLoading();
        final image = ref.watch(chatImageWidgetBuilderProvider)(
          path: path,
          width: constraints.maxWidth,
          height: constraints.maxHeight,
          fit: BoxFit.contain,
          framePlaceholder: framePlaceholder,
          errorFallback: _InlineImageFailureSignal(
            key: ValueKey<String>('chat-inline-image-failure:$path'),
            placeholder: framePlaceholder,
            onFailure: onDecodeFailure,
          ),
        );
        return SizedBox.expand(
          key: Key('chat-inline-image:${message.localId}'),
          child: image,
        );
      },
    );
    return SelectionContainer.disabled(
      child: _InlineImageInteractionRegion(
        key: Key('chat-image-interaction:${message.localId}'),
        messageId: message.localId,
        path: path,
        onOpen: onOpen,
        onCopy: onCopy,
        onSave: onSave,
        child: preview,
      ),
    );
  }
}

enum _InlineImageAction { copy, save }

class _InlineImageInteractionRegion extends StatefulWidget {
  const _InlineImageInteractionRegion({
    super.key,
    required this.messageId,
    required this.path,
    required this.onOpen,
    required this.onCopy,
    required this.onSave,
    required this.child,
  });

  final String messageId;
  final String path;
  final Future<void> Function()? onOpen;
  final Future<void> Function(String path)? onCopy;
  final Future<void> Function(String path)? onSave;
  final Widget child;

  @override
  State<_InlineImageInteractionRegion> createState() =>
      _InlineImageInteractionRegionState();
}

class _InlineImageInteractionRegionState
    extends State<_InlineImageInteractionRegion> {
  Offset? _secondaryTapPosition;

  bool get _hasActions => widget.onCopy != null || widget.onSave != null;

  @override
  Widget build(BuildContext context) {
    final expanded = context.awikiResponsive.isExpanded;
    final customActions = <CustomSemanticsAction, VoidCallback>{
      if (widget.onCopy != null)
        CustomSemanticsAction(label: context.l10n.chatCopyImage): () {
          unawaited(_invoke(_InlineImageAction.copy));
        },
      if (widget.onSave != null)
        CustomSemanticsAction(label: context.l10n.chatSaveImageAs): () {
          unawaited(_invoke(_InlineImageAction.save));
        },
    };
    return Semantics(
      image: true,
      button: widget.onOpen != null,
      label: context.l10n.chatViewAttachment,
      customSemanticsActions: customActions,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: widget.onOpen == null ? null : () => unawaited(widget.onOpen!()),
        onLongPress: !expanded && _hasActions
            ? () {
                unawaited(HapticFeedback.mediumImpact());
                unawaited(_showCompactMenu());
              }
            : null,
        onSecondaryTapDown: expanded && _hasActions
            ? (details) {
                _secondaryTapPosition = details.globalPosition;
              }
            : null,
        onSecondaryTap: expanded && _hasActions
            ? () => unawaited(_showDesktopMenu())
            : null,
        child: widget.child,
      ),
    );
  }

  Future<void> _showCompactMenu() {
    return AppNavigator.showSheet<void>(
      context,
      (_) => AppDropMenu(
        title: context.l10n.chatImageActionsTitle,
        items: <AppDropMenuItem>[
          if (widget.onCopy != null)
            AppDropMenuItem(
              buttonKey: Key('chat-image-copy-action:${widget.messageId}'),
              label: context.l10n.chatCopyImage,
              icon: CupertinoIcons.doc_on_doc,
              onTap: () => _invoke(_InlineImageAction.copy),
            ),
          if (widget.onSave != null)
            AppDropMenuItem(
              buttonKey: Key('chat-image-save-action:${widget.messageId}'),
              label: context.l10n.chatSaveImageAs,
              icon: CupertinoIcons.arrow_down_to_line,
              onTap: () => _invoke(_InlineImageAction.save),
            ),
        ],
      ),
    );
  }

  Future<void> _showDesktopMenu() async {
    final overlay = Overlay.of(
      context,
      rootOverlay: true,
    ).context.findRenderObject();
    final position = _secondaryTapPosition;
    if (overlay is! RenderBox || position == null) {
      return;
    }
    final responsive = context.awikiResponsive;
    final theme = context.awikiTheme;
    final selected = await showMenu<_InlineImageAction>(
      context: context,
      useRootNavigator: true,
      semanticLabel: context.l10n.chatImageActionsTitle,
      position: RelativeRect.fromRect(
        Rect.fromPoints(position, position),
        Offset.zero & overlay.size,
      ),
      color: theme.surface,
      surfaceTintColor: CupertinoColors.transparent,
      shadowColor: theme.title.withValues(alpha: 0.18),
      elevation: 12,
      menuPadding: EdgeInsets.all(responsive.displayScaled(4)),
      constraints: BoxConstraints.tightFor(
        width: responsive.displayScaled(200),
      ),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(responsive.displayScaled(10)),
        side: BorderSide(color: theme.border),
      ),
      items: <PopupMenuEntry<_InlineImageAction>>[
        if (widget.onCopy != null)
          _desktopMenuItem(
            action: _InlineImageAction.copy,
            key: Key('chat-image-copy-action:${widget.messageId}'),
            label: context.l10n.chatCopyImage,
            icon: CupertinoIcons.doc_on_doc,
          ),
        if (widget.onSave != null)
          _desktopMenuItem(
            action: _InlineImageAction.save,
            key: Key('chat-image-save-action:${widget.messageId}'),
            label: context.l10n.chatSaveImageAs,
            icon: CupertinoIcons.arrow_down_to_line,
          ),
      ],
    );
    if (!mounted || selected == null) {
      return;
    }
    await _invoke(selected);
  }

  PopupMenuItem<_InlineImageAction> _desktopMenuItem({
    required _InlineImageAction action,
    required Key key,
    required String label,
    required IconData icon,
  }) {
    final responsive = context.awikiResponsive;
    final theme = context.awikiTheme;
    return PopupMenuItem<_InlineImageAction>(
      key: key,
      value: action,
      height: responsive.displayScaled(38),
      padding: EdgeInsets.symmetric(horizontal: responsive.displayScaled(10)),
      child: Row(
        children: <Widget>[
          Icon(
            icon,
            size: responsive.displayScaled(16),
            color: theme.secondaryText,
          ),
          SizedBox(width: responsive.displayScaled(10)),
          Expanded(
            child: Text(
              label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                color: theme.title,
                fontSize: 13,
                fontWeight: FontWeight.w400,
                letterSpacing: 0,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _invoke(_InlineImageAction action) async {
    switch (action) {
      case _InlineImageAction.copy:
        await widget.onCopy?.call(widget.path);
        return;
      case _InlineImageAction.save:
        await widget.onSave?.call(widget.path);
        return;
    }
  }
}

class _InlineImageFailureSignal extends StatefulWidget {
  const _InlineImageFailureSignal({
    super.key,
    required this.onFailure,
    required this.placeholder,
  });

  final VoidCallback onFailure;
  final Widget placeholder;

  @override
  State<_InlineImageFailureSignal> createState() =>
      _InlineImageFailureSignalState();
}

class _InlineImageFailureSignalState extends State<_InlineImageFailureSignal> {
  @override
  void initState() {
    super.initState();
    final onFailure = widget.onFailure;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) {
        onFailure();
      }
    });
  }

  @override
  Widget build(BuildContext context) => widget.placeholder;
}

class _AttachmentFileCard extends StatelessWidget {
  const _AttachmentFileCard({
    required this.message,
    required this.macStyle,
    required this.onDownload,
    required this.onCancelDownload,
    required this.isDownloading,
    required this.titleStyle,
    required this.metaStyle,
    required this.transferSnapshot,
  });

  final ChatMessage message;
  final bool macStyle;
  final Future<void> Function()? onDownload;
  final Future<void> Function()? onCancelDownload;
  final bool isDownloading;
  final TextStyle titleStyle;
  final TextStyle metaStyle;
  final AttachmentPreviewSnapshot? transferSnapshot;

  @override
  Widget build(BuildContext context) {
    final attachment = message.attachment!;
    final responsive = context.awikiResponsive;
    final theme = context.awikiTheme;
    return Row(
      key: Key('chat-attachment-file-card:${message.localId}'),
      mainAxisSize: MainAxisSize.max,
      children: <Widget>[
        Container(
          width: macStyle
              ? responsive.displayScaled(38)
              : responsive.scaled(40),
          height: macStyle
              ? responsive.displayScaled(38)
              : responsive.scaled(40),
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: macStyle
                ? AwikiMePalette.brandAccentSoft
                : theme.surface.withValues(alpha: 0.72),
            borderRadius: BorderRadius.circular(
              macStyle ? responsive.displayScaled(8) : 10,
            ),
            border: Border.all(
              color: macStyle ? AwikiMePalette.hairline : theme.border,
            ),
          ),
          child: Icon(
            CupertinoIcons.doc_fill,
            color: macStyle ? AwikiMePalette.brandAccent : theme.primary,
            size: macStyle ? responsive.displayScaled(20) : responsive.iconSm,
          ),
        ),
        SizedBox(
          width: macStyle
              ? responsive.displayScaled(10)
              : responsive.spacing(10),
        ),
        Expanded(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              _MessagePlainText(
                text: localizeAttachmentName(context.l10n, attachment),
                maxLines: 2,
                style: titleStyle,
              ),
              SizedBox(
                height: macStyle
                    ? responsive.displayScaled(4)
                    : responsive.spacing(4),
              ),
              Text(
                _attachmentTransferMeta(context, transferSnapshot) ??
                    _formatAttachmentMeta(
                      context.l10n,
                      attachment.mimeType,
                      attachment.sizeBytes,
                    ),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: metaStyle,
              ),
            ],
          ),
        ),
        if (onDownload != null) ...<Widget>[
          SizedBox(
            width: macStyle
                ? responsive.displayScaled(10)
                : responsive.spacing(10),
          ),
          _AttachmentActionButton(
            key: Key('chat-open-attachment:${message.localId}'),
            macStyle: macStyle,
            isLoading:
                isDownloading ||
                transferSnapshot?.phase == AttachmentPreviewPhase.loading,
            onTap: onDownload!,
            onCancel: onCancelDownload,
          ),
        ],
      ],
    );
  }
}

bool _isInlineImageAttachment(ChatAttachment attachment) {
  return isSupportedAttachmentPreviewImage(attachment);
}

bool _isSupportedInlineImage({
  required String mimeType,
  required String filename,
}) {
  final normalizedMimeType = mimeType.trim().toLowerCase();
  if (<String>{
    'image/png',
    'image/jpeg',
    'image/jpg',
    'image/gif',
    'image/webp',
  }.contains(normalizedMimeType)) {
    return true;
  }
  if (normalizedMimeType.isNotEmpty &&
      normalizedMimeType != 'application/octet-stream') {
    return false;
  }
  final normalizedFilename = filename.trim().toLowerCase();
  return <String>[
    '.png',
    '.jpg',
    '.jpeg',
    '.gif',
    '.webp',
  ].any(normalizedFilename.endsWith);
}

class _MessageTextContent extends StatelessWidget {
  const _MessageTextContent({
    required this.text,
    required this.mentions,
    required this.payloadJson,
    required this.mentionPresentation,
    required this.style,
    required this.renderMarkdown,
  });

  final String text;
  final List<ChatMessageMention> mentions;
  final String? payloadJson;
  final ChatMentionPresentationResolver mentionPresentation;
  final TextStyle style;
  final bool renderMarkdown;

  @override
  Widget build(BuildContext context) {
    final validMentions = _validMentionsForText(
      text: text,
      mentions: mentions,
      payloadJson: payloadJson,
    );
    if (renderMarkdown &&
        (validMentions.isEmpty || _messageTextContainsMarkdownSyntax(text))) {
      final mentionBuilders = validMentions.isEmpty
          ? null
          : <String, MarkdownElementBuilder>{
              _awikiMentionTag: _AwikiMarkdownMentionBuilder(),
            };
      return MarkdownBody(
        data: validMentions.isEmpty
            ? text
            : _textWithMarkdownMentionMarkers(
                text,
                validMentions,
                mentionPresentation,
              ),
        selectable: false,
        shrinkWrap: true,
        styleSheet: _chatMarkdownStyleSheet(context, style),
        inlineSyntaxes: validMentions.isEmpty
            ? null
            : <md.InlineSyntax>[_AwikiMarkdownMentionSyntax()],
        builders: mentionBuilders ?? const <String, MarkdownElementBuilder>{},
      );
    }
    if (validMentions.isNotEmpty) {
      return Text.rich(
        TextSpan(
          style: style,
          children: _mentionTextSpans(context, validMentions),
        ),
        textWidthBasis: TextWidthBasis.parent,
        textHeightBehavior: _messageTextHeightBehavior,
      );
    }
    return Text(
      text,
      style: style,
      textWidthBasis: TextWidthBasis.parent,
      textHeightBehavior: _messageTextHeightBehavior,
    );
  }

  List<InlineSpan> _mentionTextSpans(
    BuildContext context,
    List<ChatMessageMention> validMentions,
  ) {
    final theme = context.awikiTheme;
    final spans = <InlineSpan>[];
    var cursor = 0;
    final mentionStyle = _mentionHighlightStyle(theme, style);
    for (final mention in validMentions) {
      if (mention.start < cursor || mention.end > text.length) {
        continue;
      }
      if (mention.start > cursor) {
        spans.add(TextSpan(text: text.substring(cursor, mention.start)));
      }
      spans.add(
        TextSpan(
          text:
              mentionPresentation.surfaceForTarget(mention.target) ??
              text.substring(mention.start, mention.end),
          style: mentionStyle,
        ),
      );
      cursor = mention.end;
    }
    if (cursor < text.length) {
      spans.add(TextSpan(text: text.substring(cursor)));
    }
    return spans;
  }
}

const _messageTextHeightBehavior = TextHeightBehavior(
  applyHeightToFirstAscent: false,
  applyHeightToLastDescent: false,
);

String _copyableMessageText(BuildContext context, ChatMessage message) {
  final attachment = message.attachment;
  if (attachment == null) {
    return message.content;
  }
  final caption = attachment.caption?.trim() ?? '';
  final filename = localizeAttachmentName(context.l10n, attachment).trim();
  return <String>[
    if (caption.isNotEmpty) caption,
    if (filename.isNotEmpty) filename,
  ].join('\n');
}

class _MessageSelectableContent extends StatelessWidget {
  const _MessageSelectableContent({
    super.key,
    required this.text,
    required this.child,
  });

  final String text;
  final Widget child;

  Future<void> _copyAll(SelectableRegionState selectableRegionState) async {
    await Clipboard.setData(ClipboardData(text: text));
    selectableRegionState.hideToolbar(false);
  }

  List<ContextMenuButtonItem> _contextMenuItems(
    BuildContext context,
    SelectableRegionState selectableRegionState,
  ) {
    final items = List<ContextMenuButtonItem>.of(
      selectableRegionState.contextMenuButtonItems,
    );
    var copyIndex = items.indexWhere(
      (item) => item.type == ContextMenuButtonType.copy,
    );
    if (copyIndex < 0) {
      final selectAllIndex = items.indexWhere(
        (item) => item.type == ContextMenuButtonType.selectAll,
      );
      copyIndex = selectAllIndex >= 0 ? selectAllIndex : 0;
      items.insert(
        copyIndex,
        ContextMenuButtonItem(
          type: ContextMenuButtonType.copy,
          onPressed: () => _copyAll(selectableRegionState),
        ),
      );
    }
    final selectAllIndex = items.indexWhere(
      (item) => item.type == ContextMenuButtonType.selectAll,
    );
    final insertionIndex = selectAllIndex >= 0 ? selectAllIndex : copyIndex + 1;
    items.insert(
      insertionIndex,
      ContextMenuButtonItem(
        label: context.l10n.commonCopyAll,
        onPressed: () => _copyAll(selectableRegionState),
      ),
    );
    return items;
  }

  @override
  Widget build(BuildContext context) {
    return SelectionArea(
      contextMenuBuilder: (context, selectableRegionState) {
        return AdaptiveTextSelectionToolbar.buttonItems(
          anchors: selectableRegionState.contextMenuAnchors,
          buttonItems: _contextMenuItems(context, selectableRegionState),
        );
      },
      child: child,
    );
  }
}

List<ChatMessageMention> _validMentionsForText({
  required String text,
  required List<ChatMessageMention> mentions,
  required String? payloadJson,
}) {
  final result = <ChatMessageMention>[];
  final seen = <String>{};

  void addMention(ChatMessageMention mention) {
    if (!mention.rangeMatches(text)) {
      return;
    }
    final key =
        '${mention.id}:${mention.start}:${mention.end}:${mention.surface}';
    if (seen.add(key)) {
      result.add(mention);
    }
  }

  for (final mention in mentions) {
    addMention(mention);
  }

  final payload = ChatMentionPayload.tryParsePayloadJson(payloadJson);
  if (payload != null) {
    for (final mention in payload.mentions) {
      addMention(mention);
    }
  }

  result.sort((a, b) => a.start.compareTo(b.start));
  return result;
}

TextStyle _mentionHighlightStyle(
  AwikiMeThemeTokens theme,
  TextStyle baseStyle,
) {
  return baseStyle.copyWith(
    color: theme.primary,
    fontWeight: FontWeight.w400,
    backgroundColor: theme.primary.withValues(alpha: 0.10),
  );
}

const _awikiMentionTag = 'awikiMention';
const _awikiMentionStartMarker = '\uE000';
const _awikiMentionSeparatorMarker = '\uE001';
const _awikiMentionEndMarker = '\uE002';
const _awikiMentionStartMarkerCodeUnit = 0xE000;

String _textWithMarkdownMentionMarkers(
  String text,
  List<ChatMessageMention> validMentions,
  ChatMentionPresentationResolver mentionPresentation,
) {
  final buffer = StringBuffer();
  var cursor = 0;
  for (var index = 0; index < validMentions.length; index += 1) {
    final mention = validMentions[index];
    if (mention.start < cursor || mention.end > text.length) {
      continue;
    }
    if (mention.start > cursor) {
      buffer.write(text.substring(cursor, mention.start));
    }
    buffer
      ..write(_awikiMentionStartMarker)
      ..write(index.toRadixString(36))
      ..write(_awikiMentionSeparatorMarker)
      ..write(
        mentionPresentation.surfaceForTarget(mention.target) ??
            text.substring(mention.start, mention.end),
      )
      ..write(_awikiMentionEndMarker);
    cursor = mention.end;
  }
  if (cursor < text.length) {
    buffer.write(text.substring(cursor));
  }
  return buffer.toString();
}

class _AwikiMarkdownMentionSyntax extends md.InlineSyntax {
  _AwikiMarkdownMentionSyntax()
    : super(
        '$_awikiMentionStartMarker([0-9a-z]+)'
        '$_awikiMentionSeparatorMarker'
        '([^$_awikiMentionEndMarker]+)'
        '$_awikiMentionEndMarker',
        startCharacter: _awikiMentionStartMarkerCodeUnit,
      );

  @override
  bool onMatch(md.InlineParser parser, Match match) {
    final surface = match.group(2) ?? '';
    parser.addNode(md.Element.text(_awikiMentionTag, surface));
    return true;
  }
}

class _AwikiMarkdownMentionBuilder extends MarkdownElementBuilder {
  @override
  Widget visitElementAfterWithContext(
    BuildContext context,
    md.Element element,
    TextStyle? preferredStyle,
    TextStyle? parentStyle,
  ) {
    final theme = context.awikiTheme;
    final baseStyle =
        parentStyle ?? preferredStyle ?? DefaultTextStyle.of(context).style;
    return Text.rich(
      TextSpan(
        text: element.textContent,
        style: _mentionHighlightStyle(theme, baseStyle),
      ),
    );
  }
}

bool _messageTextContainsMarkdownSyntax(String text) {
  final value = text.trimRight();
  if (value.isEmpty) {
    return false;
  }
  return RegExp(r'(^|\n)\s{0,3}#{1,6}\s+\S').hasMatch(value) ||
      RegExp(r'(^|\n)\s{0,3}([-*+]\s+|\d+[.)]\s+)').hasMatch(value) ||
      RegExp(r'(^|\n)\s{0,3}>\s+\S').hasMatch(value) ||
      RegExp(r'(^|\n)\s{0,3}```').hasMatch(value) ||
      RegExp(r'(`[^`\n]+`|\*\*[^*\n].*?\*\*|__[^_\n].*?__)').hasMatch(value) ||
      RegExp(r'(\[[^\]\n]+\]\([^)]+\)|~~[^~\n].*?~~)').hasMatch(value);
}

MarkdownStyleSheet _chatMarkdownStyleSheet(
  BuildContext context,
  TextStyle bodyStyle,
) {
  final theme = context.awikiTheme;
  final responsive = context.awikiResponsive;
  final fontSize = bodyStyle.fontSize ?? responsive.bodyMd;
  final codeBackground = theme.surface.withValues(alpha: 0.74);
  final quoteBackground = theme.surface.withValues(alpha: 0.58);
  return MarkdownStyleSheet(
    a: bodyStyle.copyWith(
      color: theme.primary,
      fontWeight: FontWeight.w400,
      decoration: TextDecoration.none,
    ),
    p: bodyStyle,
    pPadding: EdgeInsets.zero,
    strong: bodyStyle.copyWith(fontWeight: FontWeight.w400),
    em: bodyStyle.copyWith(fontStyle: FontStyle.italic),
    del: bodyStyle.copyWith(decoration: TextDecoration.lineThrough),
    code: bodyStyle.copyWith(
      fontFamily: 'monospace',
      fontSize: fontSize * 0.92,
      backgroundColor: codeBackground,
    ),
    h1: bodyStyle.copyWith(fontSize: fontSize + 2, fontWeight: FontWeight.w400),
    h1Padding: EdgeInsets.only(bottom: responsive.spacing(4)),
    h2: bodyStyle.copyWith(fontSize: fontSize + 1, fontWeight: FontWeight.w400),
    h2Padding: EdgeInsets.only(bottom: responsive.spacing(4)),
    h3: bodyStyle.copyWith(fontWeight: FontWeight.w400),
    h3Padding: EdgeInsets.only(bottom: responsive.spacing(3)),
    h4: bodyStyle.copyWith(fontWeight: FontWeight.w400),
    h4Padding: EdgeInsets.only(bottom: responsive.spacing(3)),
    h5: bodyStyle.copyWith(fontWeight: FontWeight.w400),
    h5Padding: EdgeInsets.zero,
    h6: bodyStyle.copyWith(fontWeight: FontWeight.w400),
    h6Padding: EdgeInsets.zero,
    blockSpacing: responsive.spacing(6),
    listIndent: responsive.spacing(18),
    listBullet: bodyStyle,
    listBulletPadding: EdgeInsets.only(right: responsive.spacing(5)),
    blockquote: bodyStyle,
    blockquotePadding: EdgeInsets.symmetric(
      horizontal: responsive.spacing(9),
      vertical: responsive.spacing(6),
    ),
    blockquoteDecoration: BoxDecoration(
      color: quoteBackground,
      border: Border(
        left: BorderSide(color: theme.border, width: responsive.scaled(3)),
      ),
      borderRadius: BorderRadius.circular(6),
    ),
    codeblockPadding: EdgeInsets.all(responsive.spacing(8)),
    codeblockDecoration: BoxDecoration(
      color: codeBackground,
      borderRadius: BorderRadius.circular(6),
      border: Border.all(color: theme.border.withValues(alpha: 0.8)),
    ),
    horizontalRuleDecoration: BoxDecoration(
      border: Border(top: BorderSide(color: theme.border)),
    ),
  );
}

class _MessagePlainText extends StatelessWidget {
  const _MessagePlainText({
    required this.text,
    required this.style,
    this.maxLines,
  });

  final String text;
  final TextStyle style;
  final int? maxLines;

  @override
  Widget build(BuildContext context) {
    return Text(
      text,
      maxLines: maxLines,
      style: style,
      overflow: maxLines == null ? null : TextOverflow.ellipsis,
      textWidthBasis: TextWidthBasis.parent,
      textHeightBehavior: const TextHeightBehavior(
        applyHeightToFirstAscent: false,
        applyHeightToLastDescent: false,
      ),
    );
  }
}

class _AttachmentCaptionDivider extends StatelessWidget {
  const _AttachmentCaptionDivider({required this.macStyle});

  final bool macStyle;

  @override
  Widget build(BuildContext context) {
    final responsive = context.awikiResponsive;
    final theme = context.awikiTheme;
    final horizontalInset = macStyle
        ? responsive.displayScaled(2)
        : responsive.spacing(2);
    return Padding(
      padding: EdgeInsets.symmetric(horizontal: horizontalInset),
      child: DecoratedBox(
        key: const Key('chat-attachment-caption-divider'),
        decoration: BoxDecoration(
          color: macStyle
              ? AwikiMePalette.messagePreview.withValues(alpha: 0.95)
              : theme.secondaryText.withValues(alpha: 0.24),
          borderRadius: BorderRadius.circular(1),
        ),
        child: const SizedBox(height: 1),
      ),
    );
  }
}

class _AttachmentActionButton extends StatelessWidget {
  const _AttachmentActionButton({
    super.key,
    required this.macStyle,
    required this.isLoading,
    required this.onTap,
    this.onCancel,
    this.sizeOverride,
  });

  final bool macStyle;
  final bool isLoading;
  final Future<void> Function() onTap;
  final Future<void> Function()? onCancel;
  final double? sizeOverride;

  @override
  Widget build(BuildContext context) {
    final responsive = context.awikiResponsive;
    final theme = context.awikiTheme;
    final size =
        sizeOverride ??
        (macStyle ? responsive.displayScaled(32) : responsive.scaled(34));
    final cancel = isLoading ? onCancel : null;
    return AppIconButton(
      onPressed: cancel != null
          ? () async => cancel()
          : isLoading
          ? null
          : () async => onTap(),
      semanticLabel: cancel == null
          ? context.l10n.chatViewAttachment
          : context.l10n.commonCancel,
      tooltip: cancel == null
          ? context.l10n.chatViewAttachment
          : context.l10n.commonCancel,
      isLoading: isLoading && cancel == null,
      size: size,
      backgroundColor: macStyle ? CupertinoColors.white : theme.surface,
      borderColor: macStyle ? AwikiMePalette.hairline : theme.border,
      borderRadius: BorderRadius.circular(
        macStyle ? responsive.displayScaled(8) : 10,
      ),
      child: Icon(
        cancel == null ? CupertinoIcons.eye : CupertinoIcons.xmark,
        color: macStyle ? AwikiMePalette.brandAccent : theme.primary,
        size: macStyle ? responsive.displayScaled(17) : responsive.iconSm,
      ),
    );
  }
}

String _formatAttachmentMeta(
  AppLocalizations l10n,
  String mimeType,
  int? sizeBytes,
) {
  final parts = <String>[];
  final type = mimeType.trim();
  if (type.isNotEmpty && type != 'application/octet-stream') {
    parts.add(type);
  }
  if (sizeBytes != null && sizeBytes >= 0) {
    parts.add(_formatFileSize(sizeBytes));
  }
  return parts.isEmpty ? l10n.chatAttachmentFileFallback : parts.join(' · ');
}

String? _attachmentTransferMeta(
  BuildContext context,
  AttachmentPreviewSnapshot? snapshot,
) {
  final phase = snapshot?.phase;
  if (phase != AttachmentPreviewPhase.loading &&
      phase != AttachmentPreviewPhase.paused) {
    return null;
  }
  final received = snapshot?.receivedBytes;
  final total = snapshot?.totalBytes;
  if (received != null && total != null && total > 0) {
    final percent = (received * 100 / total).clamp(0, 100).floor();
    return phase == AttachmentPreviewPhase.paused
        ? context.l10n.attachmentDownloadPausedProgress('$percent%')
        : context.l10n.attachmentDownloadingProgress('$percent%');
  }
  if (received != null && received > 0) {
    final progress = _formatFileSize(received);
    return phase == AttachmentPreviewPhase.paused
        ? context.l10n.attachmentDownloadPausedProgress(progress)
        : context.l10n.attachmentDownloadingProgress(progress);
  }
  return phase == AttachmentPreviewPhase.paused
      ? context.l10n.attachmentDownloadPaused
      : context.l10n.attachmentDownloading;
}

String _formatFileSize(int bytes) {
  const units = <String>['B', 'KB', 'MB', 'GB'];
  var value = bytes.toDouble();
  var unitIndex = 0;
  while (value >= 1024 && unitIndex < units.length - 1) {
    value /= 1024;
    unitIndex += 1;
  }
  if (unitIndex == 0) {
    return '$bytes ${units[unitIndex]}';
  }
  return '${value.toStringAsFixed(value >= 10 ? 0 : 1)} ${units[unitIndex]}';
}

part of '../chat_page.dart';

class _DateDivider extends StatelessWidget {
  const _DateDivider({required this.label});

  final String label;

  @override
  Widget build(BuildContext context) {
    final responsive = context.awikiResponsive;
    return Center(
      child: AppSurface(
        margin: EdgeInsets.only(bottom: responsive.spacing(24)),
        padding: responsive.scaledInsets(
          const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
        ),
        color: context.awikiTheme.subtleSurface,
        radius: AwikiMeRadii.pill,
        child: Text(label, style: AwikiMeTextStyles.meta),
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
    final bubbleColor = macStyle
        ? const Color(0xFFF8FAFD)
        : theme.subtleSurface;
    final borderColor = macStyle
        ? const Color(0xFFDDE5F0)
        : theme.border.withValues(alpha: 0.72);
    final textColor = macStyle ? const Color(0xFF66728A) : theme.secondaryText;
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
                          fontWeight: FontWeight.w500,
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
        : (macStyle ? const Color(0xFF64718A) : theme.secondaryText);
    final background = overdue
        ? const Color(0xFFFFF5DC)
        : (macStyle ? const Color(0xFFF6F8FC) : theme.subtleSurface);
    final border = overdue
        ? const Color(0xFFE9D49D)
        : (macStyle
              ? const Color(0xFFE0E7F1)
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
                        fontWeight: FontWeight.w500,
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
    final foreground = macStyle ? const Color(0xFF5F6E84) : theme.secondaryText;
    final background = macStyle
        ? const Color(0xFFF6F8FC)
        : theme.subtleSurface.withValues(alpha: 0.92);
    final border = macStyle
        ? const Color(0xFFE0E7F1)
        : theme.border.withValues(alpha: 0.72);
    final iconSize = macStyle
        ? responsive.displayScaled(12)
        : responsive.scaled(12);
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
              borderRadius: BorderRadius.circular(
                macStyle ? responsive.displayScaled(999) : 999,
              ),
              border: Border.all(color: border),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              mainAxisAlignment: MainAxisAlignment.center,
              children: <Widget>[
                Icon(
                  CupertinoIcons.person_2_fill,
                  size: iconSize,
                  color: foreground.withValues(alpha: 0.82),
                ),
                SizedBox(
                  width: macStyle
                      ? responsive.displayScaled(6)
                      : responsive.spacing(6),
                ),
                Flexible(
                  child: Text(
                    text,
                    key: Key('chat-group-system-event:${message.localId}'),
                    textAlign: TextAlign.center,
                    maxLines: 3,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      color: foreground,
                      fontSize: macStyle
                          ? responsive.displayScaled(11.5)
                          : responsive.metaSm,
                      fontWeight: FontWeight.w500,
                      height: 1.25,
                    ),
                  ),
                ),
              ],
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
              ? const Color(0xFFDDE5F0)
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
                              ? const Color(0xFF17213A)
                              : theme.title,
                          fontSize: macStyle
                              ? responsive.displayScaled(13)
                              : responsive.metaSm,
                          fontWeight: FontWeight.w700,
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
                          ? const Color(0xFF66728A)
                          : theme.secondaryText,
                      fontSize: macStyle
                          ? responsive.displayScaled(12)
                          : responsive.metaSm,
                      fontWeight: FontWeight.w500,
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
                          ? const Color(0xFFF7F9FC)
                          : theme.surface.withValues(alpha: 0.72),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Text(
                      content.preview!,
                      maxLines: 4,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        color: macStyle ? const Color(0xFF17213A) : theme.title,
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
                  fontWeight: FontWeight.w600,
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
        color: const Color(0xFF0B65F8),
        borderRadius: BorderRadius.circular(999),
        onPressed: onTap,
        child: Text(
          context.l10n.conversationsNewMessages,
          style: TextStyle(
            color: CupertinoColors.white,
            fontSize: macStyle
                ? responsive.displayScaled(12)
                : responsive.metaSm,
            fontWeight: FontWeight.w600,
            letterSpacing: 0,
          ),
        ),
      ),
    );
  }
}

class _MessageBubble extends StatelessWidget {
  const _MessageBubble({
    required this.message,
    required this.senderLabel,
    required this.showSenderLabel,
    this.macStyle = false,
    this.onRetry,
    this.onDownload,
    this.onResolveImagePreview,
    this.isDownloading = false,
    this.onPeerInfoTap,
  });

  final ChatMessage message;
  final String senderLabel;
  final bool showSenderLabel;
  final bool macStyle;
  final Future<void> Function()? onRetry;
  final Future<void> Function()? onDownload;
  final Future<String> Function()? onResolveImagePreview;
  final bool isDownloading;
  final VoidCallback? onPeerInfoTap;

  Widget _withE2eMessageSemantics({required Widget child}) {
    return e2eSemantics(
      identifier: e2eMessageIdentifier(message.content),
      label: message.content,
      child: child,
    );
  }

  Widget _withPeerInfoTap({
    required BuildContext context,
    required Widget child,
    required double borderRadius,
  }) {
    final tap = onPeerInfoTap;
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

  Widget _buildSenderLabel(BuildContext context, {required bool macStyle}) {
    final responsive = context.awikiResponsive;
    final theme = context.awikiTheme;
    return Padding(
      padding: EdgeInsets.only(
        left: macStyle ? responsive.displayScaled(2) : responsive.spacing(4),
        bottom: macStyle ? responsive.displayScaled(5) : responsive.spacing(5),
      ),
      child: Text(
        senderLabel,
        key: Key('chat-message-sender:${message.localId}'),
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: TextStyle(
          color: macStyle ? const Color(0xFF66728A) : theme.secondaryText,
          fontSize: macStyle
              ? responsive.displayScaled(11.5)
              : responsive.metaSm,
          fontWeight: FontWeight.w500,
          height: 1.2,
        ),
      ),
    );
  }

  double _senderLabelOffset(BuildContext context, {required bool macStyle}) {
    final responsive = context.awikiResponsive;
    final fontSize = macStyle
        ? responsive.displayScaled(11.5)
        : responsive.metaSm;
    final bottom = macStyle
        ? responsive.displayScaled(5)
        : responsive.spacing(5);
    return fontSize * 1.2 + bottom;
  }

  double _senderContentTopInset(
    BuildContext context, {
    required bool macStyle,
  }) {
    final responsive = context.awikiResponsive;
    return macStyle ? responsive.displayScaled(10) : responsive.spacing(10);
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

  Widget _buildMacBubble(BuildContext context, bool isMine) {
    final responsive = context.awikiResponsive;
    final textStyle = TextStyle(
      color: const Color(0xFF17213A),
      fontSize: responsive.displayScaled(14),
      height: 1.45,
    );
    final child = message.attachment == null
        ? _MessageTextContent(
            text: message.content,
            mentions: message.mentions,
            payloadJson: message.payloadJson,
            style: textStyle,
            renderMarkdown: !isMine,
          )
        : _AttachmentContent(
            message: message,
            macStyle: true,
            onDownload: onDownload,
            onResolveImagePreview: onResolveImagePreview,
            isDownloading: isDownloading,
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
          child: Container(
            constraints: BoxConstraints(
              maxWidth: responsive.displayScaled(420),
            ),
            padding: EdgeInsets.symmetric(
              horizontal: responsive.displayScaled(14),
              vertical: responsive.displayScaled(10),
            ),
            decoration: BoxDecoration(
              color: isMine ? const Color(0xFFEAF2FF) : CupertinoColors.white,
              borderRadius: BorderRadius.circular(responsive.displayScaled(10)),
              border: Border.all(
                color: isMine
                    ? const Color(0xFFEAF2FF)
                    : const Color(0xFFDDE5F0),
              ),
            ),
            child: SelectionArea(child: child),
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
                  style: TextStyle(
                    fontSize: responsive.displayScaled(12),
                    color: const Color(0xFFFF3B30),
                    fontWeight: FontWeight.w600,
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
                    style: TextStyle(
                      fontSize: responsive.displayScaled(12),
                      color: const Color(0xFF0B65F8),
                      fontWeight: FontWeight.w500,
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
            Padding(
              padding: EdgeInsets.only(
                top: showSenderLabel
                    ? _senderLabelOffset(context, macStyle: true)
                    : 0,
              ),
              child: _withPeerInfoTap(
                context: context,
                borderRadius: responsive.displayScaled(17),
                child: AvatarBadge(
                  seed: senderLabel,
                  size: responsive.displayScaled(34),
                ),
              ),
            ),
            SizedBox(width: responsive.displayScaled(10)),
          ],
          Flexible(
            child: Padding(
              padding: EdgeInsets.only(
                top: showSenderLabel
                    ? _senderContentTopInset(context, macStyle: true)
                    : 0,
              ),
              child: bubble,
            ),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final isMine = message.isMine;
    final theme = context.awikiTheme;
    final responsive = context.awikiResponsive;
    final textStyle = TextStyle(
      color: theme.title,
      fontSize: responsive.bodyMd,
      height: responsive.isPhone ? 1.5 : 1.4,
    );
    if (macStyle) {
      return _buildMacBubble(context, isMine);
    }
    return _withE2eMessageSemantics(
      child: Row(
        mainAxisAlignment: isMine
            ? MainAxisAlignment.end
            : MainAxisAlignment.start,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          if (!isMine) ...<Widget>[
            Padding(
              padding: EdgeInsets.only(
                top: showSenderLabel
                    ? _senderLabelOffset(context, macStyle: false)
                    : 0,
              ),
              child: _withPeerInfoTap(
                context: context,
                borderRadius: responsive.scaled(14),
                child: AvatarBadge(
                  seed: senderLabel,
                  size: responsive.scaled(28),
                ),
              ),
            ),
            SizedBox(width: responsive.spacing(12)),
          ],
          Flexible(
            child: Padding(
              padding: EdgeInsets.only(
                top: showSenderLabel
                    ? _senderContentTopInset(context, macStyle: false)
                    : 0,
              ),
              child: ConstrainedBox(
                constraints: BoxConstraints(
                  maxWidth: responsive.isLarge ? 500 : 640,
                ),
                child: Column(
                  crossAxisAlignment: isMine
                      ? CrossAxisAlignment.end
                      : CrossAxisAlignment.start,
                  children: <Widget>[
                    if (showSenderLabel)
                      _buildSenderLabel(context, macStyle: false),
                    _withSendingIndicator(
                      context,
                      isMine: isMine,
                      macStyle: false,
                      child: Container(
                        padding: responsive.scaledInsets(
                          const EdgeInsets.symmetric(
                            horizontal: 18,
                            vertical: 16,
                          ),
                        ),
                        decoration: BoxDecoration(
                          color: isMine
                              ? AwikiMePalette.actionBlueSoft
                              : theme.subtleSurface,
                          borderRadius: BorderRadius.only(
                            topLeft: Radius.circular(isMine ? 22 : 6),
                            topRight: Radius.circular(isMine ? 6 : 22),
                            bottomLeft: const Radius.circular(22),
                            bottomRight: const Radius.circular(22),
                          ),
                        ),
                        child: SelectionArea(
                          child: message.attachment == null
                              ? _MessageTextContent(
                                  text: message.content,
                                  mentions: message.mentions,
                                  payloadJson: message.payloadJson,
                                  style: textStyle,
                                  renderMarkdown: !isMine,
                                )
                              : _AttachmentContent(
                                  message: message,
                                  macStyle: false,
                                  onDownload: onDownload,
                                  onResolveImagePreview: onResolveImagePreview,
                                  isDownloading: isDownloading,
                                ),
                        ),
                      ),
                    ),
                    if (message.sendState ==
                        MessageSendState.failed) ...<Widget>[
                      SizedBox(height: responsive.spacing(8)),
                      Row(
                        mainAxisSize: MainAxisSize.min,
                        children: <Widget>[
                          SelectionArea(
                            child: Text(
                              context.l10n.chatSendFailed,
                              style: TextStyle(
                                fontSize: responsive.metaSm,
                                color: theme.danger,
                                fontWeight: FontWeight.w500,
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
                                  fontWeight: FontWeight.w500,
                                ),
                              ),
                            ),
                          ],
                        ],
                      ),
                    ],
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
            color: macStyle ? const Color(0xFF8A96AA) : theme.tertiaryText,
          ),
        ),
      ),
    );
  }
}

const int _maxInlineImageBytes = 20 * 1024 * 1024;

class _AttachmentContent extends StatefulWidget {
  const _AttachmentContent({
    required this.message,
    required this.macStyle,
    required this.onDownload,
    required this.onResolveImagePreview,
    required this.isDownloading,
  });

  final ChatMessage message;
  final bool macStyle;
  final Future<void> Function()? onDownload;
  final Future<String> Function()? onResolveImagePreview;
  final bool isDownloading;

  @override
  State<_AttachmentContent> createState() => _AttachmentContentState();
}

class _AttachmentContentState extends State<_AttachmentContent> {
  Future<String?>? _previewPath;

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
    if (oldWidget.message.localId != widget.message.localId ||
        oldAttachment?.attachmentId != attachment?.attachmentId ||
        oldAttachment?.localPath != attachment?.localPath) {
      _preparePreview();
    }
  }

  void _preparePreview() {
    final attachment = widget.message.attachment!;
    if (!_isInlineImageAttachment(attachment)) {
      _previewPath = null;
      return;
    }
    final localPath = attachment.localPath?.trim();
    if (localPath != null && localPath.isNotEmpty) {
      _previewPath = Future<String?>.value(localPath);
      return;
    }
    final sizeBytes = attachment.sizeBytes;
    final resolve = widget.onResolveImagePreview;
    if (resolve == null ||
        sizeBytes == null ||
        sizeBytes <= 0 ||
        sizeBytes > _maxInlineImageBytes) {
      _previewPath = null;
      return;
    }
    _previewPath = resolve().then<String?>((path) => path);
  }

  @override
  Widget build(BuildContext context) {
    final message = widget.message;
    final attachment = message.attachment!;
    final responsive = context.awikiResponsive;
    final theme = context.awikiTheme;
    final caption = attachment.caption?.trim();
    final titleStyle = TextStyle(
      color: widget.macStyle ? const Color(0xFF17213A) : theme.title,
      fontSize: widget.macStyle
          ? responsive.displayScaled(13.5)
          : responsive.bodyMd,
      fontWeight: FontWeight.w500,
      height: 1.25,
    );
    final metaStyle = TextStyle(
      color: widget.macStyle ? const Color(0xFF66728A) : theme.secondaryText,
      fontSize: widget.macStyle
          ? responsive.displayScaled(12)
          : responsive.metaSm,
      fontWeight: FontWeight.w500,
      height: 1.25,
    );
    return ConstrainedBox(
      constraints: BoxConstraints(
        minWidth: widget.macStyle
            ? responsive.displayScaled(220)
            : responsive.scaled(210),
        maxWidth: widget.macStyle
            ? responsive.displayScaled(360)
            : responsive.scaled(420),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          if (caption != null && caption.isNotEmpty) ...<Widget>[
            _MessageTextContent(
              text: caption,
              mentions: message.mentions,
              payloadJson: message.payloadJson,
              style: TextStyle(
                color: widget.macStyle ? const Color(0xFF17213A) : theme.title,
                fontSize: widget.macStyle
                    ? responsive.displayScaled(14)
                    : responsive.bodyMd,
                height: 1.4,
              ),
              renderMarkdown: !message.isMine,
            ),
            SizedBox(
              height: widget.macStyle
                  ? responsive.displayScaled(9)
                  : responsive.spacing(9),
            ),
            _AttachmentCaptionDivider(macStyle: widget.macStyle),
            SizedBox(
              height: widget.macStyle
                  ? responsive.displayScaled(9)
                  : responsive.spacing(9),
            ),
          ],
          _buildAttachmentBody(
            context,
            attachment: attachment,
            titleStyle: titleStyle,
            metaStyle: metaStyle,
          ),
        ],
      ),
    );
  }

  Widget _buildAttachmentBody(
    BuildContext context, {
    required ChatAttachment attachment,
    required TextStyle titleStyle,
    required TextStyle metaStyle,
  }) {
    final future = _previewPath;
    if (future == null) {
      return _AttachmentFileCard(
        message: widget.message,
        macStyle: widget.macStyle,
        onDownload: widget.onDownload,
        isDownloading: widget.isDownloading,
        titleStyle: titleStyle,
        metaStyle: metaStyle,
      );
    }
    return FutureBuilder<String?>(
      future: future,
      builder: (context, snapshot) {
        final path = snapshot.data?.trim();
        if (snapshot.connectionState == ConnectionState.waiting) {
          return _InlineImageLoading(macStyle: widget.macStyle);
        }
        if (snapshot.hasError || path == null || path.isEmpty) {
          return _AttachmentFileCard(
            message: widget.message,
            macStyle: widget.macStyle,
            onDownload: widget.onDownload,
            isDownloading: widget.isDownloading,
            titleStyle: titleStyle,
            metaStyle: metaStyle,
          );
        }
        return _InlineImagePreview(
          message: widget.message,
          path: path,
          macStyle: widget.macStyle,
          onOpen: widget.onDownload,
          errorFallback: _AttachmentFileCard(
            message: widget.message,
            macStyle: widget.macStyle,
            onDownload: widget.onDownload,
            isDownloading: widget.isDownloading,
            titleStyle: titleStyle,
            metaStyle: metaStyle,
          ),
        );
      },
    );
  }
}

class _InlineImageLoading extends StatelessWidget {
  const _InlineImageLoading({required this.macStyle});

  final bool macStyle;

  @override
  Widget build(BuildContext context) {
    final responsive = context.awikiResponsive;
    return Container(
      key: const Key('chat-inline-image-loading'),
      height: macStyle ? responsive.displayScaled(150) : responsive.scaled(170),
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: const Color(0xFFF1F4F8),
        borderRadius: BorderRadius.circular(10),
      ),
      child: const CupertinoActivityIndicator(),
    );
  }
}

class _InlineImagePreview extends ConsumerWidget {
  const _InlineImagePreview({
    required this.message,
    required this.path,
    required this.macStyle,
    required this.onOpen,
    required this.errorFallback,
  });

  final ChatMessage message;
  final String path;
  final bool macStyle;
  final Future<void> Function()? onOpen;
  final Widget errorFallback;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final responsive = context.awikiResponsive;
    final image = ref.watch(chatImageWidgetBuilderProvider)(
      path: path,
      fit: BoxFit.contain,
      errorFallback: errorFallback,
    );
    final preview = ClipRRect(
      key: Key('chat-inline-image:${message.localId}'),
      borderRadius: BorderRadius.circular(
        macStyle ? responsive.displayScaled(9) : responsive.radius(12),
      ),
      child: ConstrainedBox(
        constraints: BoxConstraints(
          maxWidth: macStyle
              ? responsive.displayScaled(320)
              : responsive.scaled(360),
          maxHeight: macStyle
              ? responsive.displayScaled(300)
              : responsive.scaled(340),
        ),
        child: image,
      ),
    );
    final open = onOpen;
    if (open == null) {
      return preview;
    }
    return Semantics(
      button: true,
      label: context.l10n.chatViewAttachment,
      child: GestureDetector(onTap: () => unawaited(open()), child: preview),
    );
  }
}

class _AttachmentFileCard extends StatelessWidget {
  const _AttachmentFileCard({
    required this.message,
    required this.macStyle,
    required this.onDownload,
    required this.isDownloading,
    required this.titleStyle,
    required this.metaStyle,
  });

  final ChatMessage message;
  final bool macStyle;
  final Future<void> Function()? onDownload;
  final bool isDownloading;
  final TextStyle titleStyle;
  final TextStyle metaStyle;

  @override
  Widget build(BuildContext context) {
    final attachment = message.attachment!;
    final responsive = context.awikiResponsive;
    final theme = context.awikiTheme;
    return Row(
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
                ? const Color(0xFFEAF2FF)
                : theme.surface.withValues(alpha: 0.72),
            borderRadius: BorderRadius.circular(
              macStyle ? responsive.displayScaled(8) : 10,
            ),
            border: Border.all(
              color: macStyle ? const Color(0xFFDDE5F0) : theme.border,
            ),
          ),
          child: Icon(
            CupertinoIcons.doc_fill,
            color: macStyle ? const Color(0xFF0B65F8) : theme.primary,
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
            isLoading: isDownloading,
            onTap: onDownload!,
          ),
        ],
      ],
    );
  }
}

bool _isInlineImageAttachment(ChatAttachment attachment) {
  return _isSupportedInlineImage(
    mimeType: attachment.mimeType,
    filename: attachment.filename,
  );
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
    required this.style,
    required this.renderMarkdown,
  });

  final String text;
  final List<ChatMessageMention> mentions;
  final String? payloadJson;
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
            : _textWithMarkdownMentionMarkers(text, validMentions),
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
      );
    }
    if (!renderMarkdown) {
      return _MessagePlainText(text: text, style: style);
    }
    return _MessagePlainText(text: text, style: style);
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
          text: text.substring(mention.start, mention.end),
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
    fontWeight: FontWeight.w700,
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
      ..write(text.substring(mention.start, mention.end))
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
      fontWeight: FontWeight.w600,
      decoration: TextDecoration.none,
    ),
    p: bodyStyle,
    pPadding: EdgeInsets.zero,
    strong: bodyStyle.copyWith(fontWeight: FontWeight.w700),
    em: bodyStyle.copyWith(fontStyle: FontStyle.italic),
    del: bodyStyle.copyWith(decoration: TextDecoration.lineThrough),
    code: bodyStyle.copyWith(
      fontFamily: 'monospace',
      fontSize: fontSize * 0.92,
      backgroundColor: codeBackground,
    ),
    h1: bodyStyle.copyWith(fontSize: fontSize + 2, fontWeight: FontWeight.w700),
    h1Padding: EdgeInsets.only(bottom: responsive.spacing(4)),
    h2: bodyStyle.copyWith(fontSize: fontSize + 1, fontWeight: FontWeight.w700),
    h2Padding: EdgeInsets.only(bottom: responsive.spacing(4)),
    h3: bodyStyle.copyWith(fontWeight: FontWeight.w700),
    h3Padding: EdgeInsets.only(bottom: responsive.spacing(3)),
    h4: bodyStyle.copyWith(fontWeight: FontWeight.w600),
    h4Padding: EdgeInsets.only(bottom: responsive.spacing(3)),
    h5: bodyStyle.copyWith(fontWeight: FontWeight.w600),
    h5Padding: EdgeInsets.zero,
    h6: bodyStyle.copyWith(fontWeight: FontWeight.w600),
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
              ? const Color(0xFFC3CDDB).withValues(alpha: 0.95)
              : theme.secondaryText.withValues(alpha: 0.24),
          borderRadius: BorderRadius.circular(1),
        ),
        child: const SizedBox(height: 1, width: double.infinity),
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
  });

  final bool macStyle;
  final bool isLoading;
  final Future<void> Function() onTap;

  @override
  Widget build(BuildContext context) {
    final responsive = context.awikiResponsive;
    final theme = context.awikiTheme;
    final size = macStyle
        ? responsive.displayScaled(32)
        : responsive.scaled(34);
    return AppIconButton(
      onPressed: isLoading ? null : () async => onTap(),
      semanticLabel: context.l10n.chatViewAttachment,
      tooltip: context.l10n.chatViewAttachment,
      isLoading: isLoading,
      size: size,
      backgroundColor: macStyle ? CupertinoColors.white : theme.surface,
      borderColor: macStyle ? const Color(0xFFDDE5F0) : theme.border,
      borderRadius: BorderRadius.circular(
        macStyle ? responsive.displayScaled(8) : 10,
      ),
      child: Icon(
        CupertinoIcons.eye,
        color: macStyle ? const Color(0xFF0B65F8) : theme.primary,
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

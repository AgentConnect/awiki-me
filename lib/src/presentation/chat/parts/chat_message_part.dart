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

class _MessageAgentProcessingStatus extends StatelessWidget {
  const _MessageAgentProcessingStatus({
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
          '有新消息',
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
    this.isDownloading = false,
    this.onPeerInfoTap,
  });

  final ChatMessage message;
  final String senderLabel;
  final bool showSenderLabel;
  final bool macStyle;
  final Future<void> Function()? onRetry;
  final Future<void> Function()? onDownload;
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
    required Widget child,
    required double borderRadius,
  }) {
    final tap = onPeerInfoTap;
    if (tap == null) {
      return child;
    }
    return AppPressable(
      onTap: tap,
      semanticLabel: '查看用户或智能体信息',
      tooltip: '查看用户或智能体信息',
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
    return Row(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.center,
      children: <Widget>[
        _SendingMessageIndicator(macStyle: macStyle),
        SizedBox(width: gap),
        Flexible(child: child),
      ],
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
            style: textStyle,
            renderMarkdown: !isMine,
          )
        : _AttachmentContent(
            message: message,
            macStyle: true,
            onDownload: onDownload,
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
                  '发送失败',
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
                  onTap: onRetry,
                  semanticLabel: '重试发送',
                  child: Text(
                    '重试',
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
                                  style: textStyle,
                                  renderMarkdown: !isMine,
                                )
                              : _AttachmentContent(
                                  message: message,
                                  macStyle: false,
                                  onDownload: onDownload,
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
                              '发送失败',
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
                              onTap: onRetry,
                              semanticLabel: '重试发送',
                              child: Text(
                                '重试',
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

class _SendingMessageIndicator extends StatelessWidget {
  const _SendingMessageIndicator({required this.macStyle});

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
      label: '发送中',
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

class _AttachmentContent extends StatelessWidget {
  const _AttachmentContent({
    required this.message,
    required this.macStyle,
    required this.onDownload,
    required this.isDownloading,
  });

  final ChatMessage message;
  final bool macStyle;
  final Future<void> Function()? onDownload;
  final bool isDownloading;

  @override
  Widget build(BuildContext context) {
    final attachment = message.attachment!;
    final responsive = context.awikiResponsive;
    final theme = context.awikiTheme;
    final caption = attachment.caption?.trim();
    final titleStyle = TextStyle(
      color: macStyle ? const Color(0xFF17213A) : theme.title,
      fontSize: macStyle ? responsive.displayScaled(13.5) : responsive.bodyMd,
      fontWeight: FontWeight.w500,
      height: 1.25,
    );
    final metaStyle = TextStyle(
      color: macStyle ? const Color(0xFF66728A) : theme.secondaryText,
      fontSize: macStyle ? responsive.displayScaled(12) : responsive.metaSm,
      fontWeight: FontWeight.w500,
      height: 1.25,
    );
    return ConstrainedBox(
      constraints: BoxConstraints(
        minWidth: macStyle
            ? responsive.displayScaled(220)
            : responsive.scaled(210),
        maxWidth: macStyle
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
              mentions: const <ChatMessageMention>[],
              style: TextStyle(
                color: macStyle ? const Color(0xFF17213A) : theme.title,
                fontSize: macStyle
                    ? responsive.displayScaled(14)
                    : responsive.bodyMd,
                height: 1.4,
              ),
              renderMarkdown: !message.isMine,
            ),
            SizedBox(
              height: macStyle
                  ? responsive.displayScaled(9)
                  : responsive.spacing(9),
            ),
            _AttachmentCaptionDivider(macStyle: macStyle),
            SizedBox(
              height: macStyle
                  ? responsive.displayScaled(9)
                  : responsive.spacing(9),
            ),
          ],
          Row(
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
                  size: macStyle
                      ? responsive.displayScaled(20)
                      : responsive.iconSm,
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
                      text: attachment.displayName,
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
                  macStyle: macStyle,
                  isLoading: isDownloading,
                  onTap: onDownload!,
                ),
              ],
            ],
          ),
        ],
      ),
    );
  }
}

class _MessageTextContent extends StatelessWidget {
  const _MessageTextContent({
    required this.text,
    required this.mentions,
    required this.style,
    required this.renderMarkdown,
  });

  final String text;
  final List<ChatMessageMention> mentions;
  final TextStyle style;
  final bool renderMarkdown;

  @override
  Widget build(BuildContext context) {
    final validMentions =
        mentions.where((mention) => mention.rangeMatches(text)).toList()
          ..sort((a, b) => a.start.compareTo(b.start));
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
    return MarkdownBody(
      data: text,
      selectable: false,
      shrinkWrap: true,
      styleSheet: _chatMarkdownStyleSheet(context, style),
    );
  }

  List<InlineSpan> _mentionTextSpans(
    BuildContext context,
    List<ChatMessageMention> validMentions,
  ) {
    final theme = context.awikiTheme;
    final spans = <InlineSpan>[];
    var cursor = 0;
    final mentionStyle = style.copyWith(
      color: theme.primary,
      fontWeight: FontWeight.w700,
      backgroundColor: theme.primary.withValues(alpha: 0.10),
    );
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
      semanticLabel: '查看附件',
      tooltip: '查看附件',
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

String _formatAttachmentMeta(String mimeType, int? sizeBytes) {
  final parts = <String>[];
  final type = mimeType.trim();
  if (type.isNotEmpty && type != 'application/octet-stream') {
    parts.add(type);
  }
  if (sizeBytes != null && sizeBytes >= 0) {
    parts.add(_formatFileSize(sizeBytes));
  }
  return parts.isEmpty ? '文件' : parts.join(' · ');
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

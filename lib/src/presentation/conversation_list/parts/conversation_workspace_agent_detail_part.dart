part of '../conversation_workspace_page.dart';

class _MacAgentDetailPanel extends ConsumerWidget {
  const _MacAgentDetailPanel({required this.conversation, this.onBack});

  final ConversationSummary conversation;
  final VoidCallback? onBack;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final classification = ref
        .watch(
          conversationPeerClassificationProvider(
            ConversationPeerTarget.fromConversation(conversation),
          ),
        )
        .maybeWhen(
          data: (value) => value,
          orElse: () => conversation.isGroup
              ? const ConversationPeerClassification.group()
              : const ConversationPeerClassification.unknown(),
        );
    final address = conversation.targetDid?.trim().isNotEmpty == true
        ? conversation.targetDid!.trim()
        : conversation.groupId ?? conversation.threadId;
    final children = <Widget>[
      if (onBack == null) ...<Widget>[
        Text(
          context.l10n.conversationInfoTitle,
          style: const TextStyle(
            color: Color(0xFF101B32),
            fontSize: 16,
            fontWeight: FontWeight.w400,
          ),
        ),
        const SizedBox(height: 22),
      ],
      _MacDetailRow(
        label: context.l10n.conversationIdentityStatus,
        child: Row(
          children: <Widget>[
            const Icon(
              CupertinoIcons.checkmark_shield_fill,
              color: Color(0xFF17BF63),
              size: 16,
            ),
            const SizedBox(width: 6),
            Text(
              context.l10n.conversationIdentityVerified,
              style: const TextStyle(
                color: Color(0xFF17BF63),
                fontSize: 12,
                fontWeight: FontWeight.w500,
              ),
            ),
          ],
        ),
      ),
      _MacDetailRow(
        label: context.l10n.conversationOwnerLabel,
        text: localizeConversationPeerOwner(context.l10n, classification),
      ),
      _MacDetailRow(
        label: 'DID:',
        child: CopyableDidLine(
          value: address,
          copySemanticLabel: context.l10n.chatPeerInfoCopyDid,
          copiedMessage: context.l10n.chatPeerInfoDidCopied,
          textKey: const Key('mac-conversation-did-value'),
          buttonKey: const Key('mac-conversation-copy-did-button'),
        ),
      ),
      _MacDetailRow(
        label: context.l10n.conversationTypeLabel,
        text: localizeConversationPeerType(context.l10n, classification),
      ),
      const SizedBox(height: 16),
      _MacDetailCard(
        title: context.l10n.conversationCapabilitiesTitle,
        children: <Widget>[
          _MacAbilityGridItem(
            icon: CupertinoIcons.chat_bubble_text,
            label: context.l10n.conversationCapabilitySendMessage,
          ),
          _MacAbilityGridItem(
            icon: CupertinoIcons.person_crop_circle,
            label: context.l10n.conversationCapabilityViewProfile,
          ),
          _MacAbilityGridItem(
            icon: CupertinoIcons.shield,
            label: context.l10n.conversationCapabilitySecureConnection,
          ),
          _MacAbilityGridItem(
            icon: CupertinoIcons.doc_text,
            label: context.l10n.conversationCapabilityHistory,
          ),
        ],
      ),
      const SizedBox(height: 14),
      _MacDetailCard(
        title: context.l10n.conversationStatusTitle,
        children: <Widget>[
          _MacStatusLine(
            label: context.l10n.conversationUnreadMessagesLabel,
            value: context.l10n.conversationUnreadMessagesValue(
              conversation.unreadCount,
            ),
            color: const Color(0xFF0B65F8),
          ),
          _MacStatusLine(
            label: context.l10n.conversationLatestPreviewLabel,
            value: conversation.lastMessagePreview.trim().isEmpty
                ? context.l10n.conversationsNoMessagePreview
                : conversation.lastMessagePreview.trim(),
            color: const Color(0xFF66728A),
            indicatorKey: const Key('mac-conversation-preview-status-dot'),
            valueKey: const Key('mac-conversation-preview-status-value'),
          ),
          _MacStatusLine(
            label: context.l10n.conversationConnectionStatusLabel,
            value: context.l10n.conversationConnectionEstablished,
            color: const Color(0xFF17BF63),
          ),
        ],
      ),
    ];
    if (onBack != null) {
      return _MacPanelShell(
        title: context.l10n.conversationInfoTitle,
        onClose: onBack!,
        closeIcon: CupertinoIcons.chevron_left,
        closeButtonKey: const Key('mac-compact-panel-back-button'),
        closeSemanticLabel: context.l10n.conversationBackToChat,
        closeButtonLeading: true,
        child: ListView(
          padding: const EdgeInsets.fromLTRB(18, 18, 18, 22),
          children: children,
        ),
      );
    }
    return DecoratedBox(
      decoration: const BoxDecoration(color: Color(0xFFF8FAFD)),
      child: SafeArea(
        bottom: false,
        child: ListView(
          padding: const EdgeInsets.fromLTRB(18, 22, 18, 22),
          children: children,
        ),
      ),
    );
  }
}

class _MacDetailRow extends StatelessWidget {
  const _MacDetailRow({required this.label, this.text, this.child});

  final String label;
  final String? text;
  final Widget? child;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 14),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          SizedBox(
            width: 70,
            child: Text(
              label,
              style: const TextStyle(
                color: Color(0xFF34415C),
                fontSize: 12,
                fontWeight: FontWeight.w500,
              ),
            ),
          ),
          Expanded(
            child:
                child ??
                Text(
                  text ?? '',
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    color: Color(0xFF17213A),
                    fontSize: 12,
                    height: 1.35,
                  ),
                ),
          ),
        ],
      ),
    );
  }
}

class _MacDetailCard extends StatelessWidget {
  const _MacDetailCard({required this.title, required this.children});

  final String title;
  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: CupertinoColors.white,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: const Color(0xFFE5EAF2)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Text(
            title,
            style: const TextStyle(
              color: Color(0xFF17213A),
              fontSize: 13,
              fontWeight: FontWeight.w500,
            ),
          ),
          const SizedBox(height: 10),
          Wrap(spacing: 8, runSpacing: 8, children: children),
        ],
      ),
    );
  }
}

class _MacAbilityGridItem extends StatelessWidget {
  const _MacAbilityGridItem({required this.icon, required this.label});

  final IconData icon;
  final String label;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 96,
      padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 9),
      decoration: BoxDecoration(
        color: const Color(0xFFFBFDFF),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: const Color(0xFFE5EAF2)),
      ),
      child: Row(
        children: <Widget>[
          Icon(icon, size: 15, color: const Color(0xFF34415C)),
          const SizedBox(width: 6),
          Expanded(
            child: Text(
              label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                color: Color(0xFF34415C),
                fontSize: 10.5,
                fontWeight: FontWeight.w500,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _MacStatusLine extends StatelessWidget {
  const _MacStatusLine({
    required this.label,
    required this.value,
    required this.color,
    this.indicatorKey,
    this.valueKey,
  });

  final String label;
  final String value;
  final Color color;
  final Key? indicatorKey;
  final Key? valueKey;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 5),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          SizedBox(
            width: 70,
            child: Text(
              label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                color: Color(0xFF66728A),
                fontSize: 12,
                height: 1.35,
              ),
            ),
          ),
          Padding(
            padding: const EdgeInsets.only(top: 4.6),
            child: Icon(
              CupertinoIcons.circle_fill,
              key: indicatorKey,
              color: color,
              size: 7,
            ),
          ),
          const SizedBox(width: 6),
          Expanded(
            child: Text(
              value,
              key: valueKey,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              textAlign: TextAlign.left,
              style: const TextStyle(
                color: Color(0xFF17213A),
                fontSize: 12,
                height: 1.35,
                fontWeight: FontWeight.w500,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

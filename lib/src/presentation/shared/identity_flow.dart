import 'package:flutter/cupertino.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/e2e_semantics.dart';
import '../../app/app_router.dart';
import '../../app/app_services.dart';
import '../../app/ui_feedback.dart';
import '../../application/thread_id_utils.dart';
import '../../domain/entities/conversation_summary.dart';
import '../../domain/entities/relationship_summary.dart';
import '../../domain/entities/user_profile.dart';
import '../../l10n/app_message.dart';
import '../../l10n/l10n.dart';
import '../app_shell/providers/navigation_provider.dart';
import '../app_shell/providers/selected_conversation_provider.dart';
import '../app_shell/providers/session_provider.dart';
import '../chat/chat_page.dart';
import '../chat/chat_provider.dart';
import '../conversation_list/conversation_provider.dart';
import '../friends/friends_provider.dart';
import 'awiki_me_feedback.dart';
import 'avatar_badge.dart';
import 'formatters/display_formatters.dart';
import 'responsive_layout.dart';
import 'widgets/app_widgets.dart';

enum IdentityFlowMode { startConversation, addContact }

class IdentityFlowResult {
  const IdentityFlowResult({required this.profile, this.reason, this.note});

  final UserProfile profile;
  final String? reason;
  final String? note;
}

String normalizeDidOrHandleInput(String rawValue) {
  var value = rawValue.trim();
  while (value.startsWith('@')) {
    value = value.substring(1).trimLeft();
  }
  return value;
}

String dmThreadIdForDids(String myDid, String peerDid) {
  return canonicalDirectThreadId(myDid, peerDid);
}

Future<void> openDirectConversationForProfile(
  BuildContext context,
  WidgetRef ref,
  UserProfile profile,
) async {
  await openDirectConversationForDid(
    context,
    ref,
    peerDid: profile.did,
    peerName: DidDisplayFormatter.profileName(profile),
    avatarSeed: profile.handle ?? profile.did,
  );
}

Future<void> openDirectConversationForDid(
  BuildContext context,
  WidgetRef ref, {
  required String peerDid,
  required String peerName,
  String? avatarSeed,
}) async {
  final session = ref.read(sessionProvider).session;
  if (session == null) {
    ref
        .read(uiFeedbackProvider.notifier)
        .showError(AppMessage.sessionExpiredRelogin());
    return;
  }

  final peer = peerDid.trim();
  if (!peer.startsWith('did:')) {
    ref
        .read(uiFeedbackProvider.notifier)
        .showError(AppMessage.fromError(StateError('联系人身份无效，无法打开会话。')));
    return;
  }

  final threadId = dmThreadIdForDids(session.did, peer);
  final existing = ref
      .read(conversationListProvider)
      .conversations
      .where((item) => item.threadId == threadId);
  final conversation = existing.isNotEmpty
      ? _directConversationForPeer(
          existing.first,
          peerDid: peer,
          peerName: peerName,
          avatarSeed: avatarSeed,
        )
      : ConversationSummary(
          threadId: threadId,
          displayName: _directConversationName(peerName, peer),
          lastMessagePreview: '',
          lastMessageAt: DateTime.now(),
          unreadCount: 0,
          isGroup: false,
          targetDid: peer,
          avatarSeed: avatarSeed ?? peer,
        );

  ref.read(conversationListProvider.notifier).upsertConversation(conversation);
  await ref.read(chatThreadsProvider.notifier).openConversation(conversation);
  if (!context.mounted) {
    return;
  }

  if (context.awikiResponsive.supportsTwoPane) {
    ref
        .read(selectedConversationProvider.notifier)
        .selectConversation(conversation);
    ref.read(shellTabProvider.notifier).setTab(0);
    return;
  }
  await AppNavigator.push(context, (_) => ChatPage(conversation: conversation));
}

ConversationSummary _directConversationForPeer(
  ConversationSummary existing, {
  required String peerDid,
  required String peerName,
  String? avatarSeed,
}) {
  final existingTarget = existing.targetDid?.trim() ?? '';
  final keepExistingName =
      !existing.isGroup &&
      existingTarget == peerDid &&
      existing.displayName.trim().isNotEmpty;
  return ConversationSummary(
    threadId: existing.threadId,
    displayName: keepExistingName
        ? existing.displayName
        : _directConversationName(peerName, peerDid),
    lastMessagePreview: existing.lastMessagePreview,
    lastMessageAt: existing.lastMessageAt,
    unreadCount: existing.unreadCount,
    isGroup: false,
    targetDid: peerDid,
    groupId: null,
    avatarSeed: avatarSeed ?? existing.avatarSeed ?? peerDid,
  );
}

String _directConversationName(String peerName, String peerDid) {
  final name = peerName.trim();
  if (name.isNotEmpty) {
    return name;
  }
  return DidDisplayFormatter.compactDid(peerDid);
}

Future<void> showStartConversationDialog(
  BuildContext context,
  WidgetRef ref,
) async {
  final result = await AppNavigator.showDialog<IdentityFlowResult>(
    context,
    (_) => const IdentityLookupDialog(mode: IdentityFlowMode.startConversation),
  );
  if (result == null || !context.mounted) {
    return;
  }
  await openDirectConversationForProfile(context, ref, result.profile);
}

Future<void> showAddIdentityDialog(BuildContext context, WidgetRef ref) async {
  final result = await AppNavigator.showDialog<IdentityFlowResult>(
    context,
    (_) => const IdentityLookupDialog(mode: IdentityFlowMode.addContact),
  );
  if (result == null) {
    return;
  }

  try {
    await ref.read(friendsProvider.notifier).follow(result.profile.did);
    await ref.read(friendsProvider.notifier).refresh();
    ref
        .read(uiFeedbackProvider.notifier)
        .showInfo(AppMessage.addFriendFollowed());
  } catch (error) {
    ref
        .read(uiFeedbackProvider.notifier)
        .showError(AppMessage.fromError(error));
  }
}

class IdentityLookupDialog extends ConsumerStatefulWidget {
  const IdentityLookupDialog({super.key, required this.mode});

  final IdentityFlowMode mode;

  @override
  ConsumerState<IdentityLookupDialog> createState() =>
      _IdentityLookupDialogState();
}

class _IdentityLookupDialogState extends ConsumerState<IdentityLookupDialog> {
  final _queryController = TextEditingController();
  final _reasonController = TextEditingController();
  final _noteController = TextEditingController();
  bool _isResolving = false;
  UserProfile? _profile;
  RelationshipSummary? _relationship;
  String? _errorText;

  bool get _isAddContact => widget.mode == IdentityFlowMode.addContact;

  @override
  void dispose() {
    _queryController.dispose();
    _reasonController.dispose();
    _noteController.dispose();
    super.dispose();
  }

  Future<void> _resolve() async {
    final query = normalizeDidOrHandleInput(_queryController.text);
    if (query.isEmpty) {
      setState(() => _errorText = '请输入 handle 或 DID。');
      return;
    }
    setState(() {
      _isResolving = true;
      _errorText = null;
      _profile = null;
      _relationship = null;
    });
    try {
      final profile = await ref
          .read(profileApplicationServiceProvider)
          .loadPublicProfile(query);
      RelationshipSummary? relationship;
      if (_isAddContact) {
        try {
          relationship = await ref
              .read(relationshipApplicationServiceProvider)
              .status(profile.did);
        } catch (_) {
          relationship = null;
        }
      }
      if (!mounted) {
        return;
      }
      setState(() {
        _profile = profile;
        _relationship = relationship;
        _isResolving = false;
      });
    } catch (_) {
      if (!mounted) {
        return;
      }
      setState(() {
        _isResolving = false;
        _errorText = '未找到该身份，请检查 handle / DID 是否正确。';
      });
    }
  }

  void _submit() {
    final profile = _profile;
    if (profile == null) {
      return;
    }
    if (_isAddContact) {
      final relationship = _relationship?.relationship.trim() ?? 'none';
      if (relationship.isNotEmpty && relationship != 'none') {
        ref
            .read(uiFeedbackProvider.notifier)
            .showInfo(AppMessage.addFriendAlreadyExists());
        Navigator.of(context).pop();
        return;
      }
      if (_reasonController.text.trim().isEmpty) {
        setState(() => _errorText = '请填写添加理由。');
        return;
      }
    }
    Navigator.of(context).pop(
      IdentityFlowResult(
        profile: profile,
        reason: _reasonController.text.trim(),
        note: _noteController.text.trim(),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final title = _isAddContact ? '添加联系人 / Agent' : '发起新消息';
    final subtitle = _isAddContact
        ? '输入 handle 或 DID，确认身份后发送连接请求。'
        : '输入 handle、DID 或 Agent 地址，确认身份后开始可信会话。';
    final actionLabel = _isAddContact ? '发送请求' : '开始聊天';
    final responsive = context.awikiResponsive;
    final maxWidth = responsive.isPhone ? double.infinity : 560.0;
    return CupertinoPopupSurface(
      isSurfacePainted: false,
      child: Center(
        child: SafeArea(
          child: ConstrainedBox(
            constraints: BoxConstraints(
              maxWidth: maxWidth,
              maxHeight: MediaQuery.sizeOf(context).height - 48,
            ),
            child: DecoratedBox(
              decoration: BoxDecoration(
                color: CupertinoColors.white,
                borderRadius: BorderRadius.circular(22),
                boxShadow: const <BoxShadow>[
                  BoxShadow(
                    color: Color(0x240B1F3A),
                    blurRadius: 32,
                    offset: Offset(0, 14),
                  ),
                ],
              ),
              child: SingleChildScrollView(
                padding: const EdgeInsets.fromLTRB(24, 22, 24, 24),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: <Widget>[
                    Row(
                      children: <Widget>[
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: <Widget>[
                              Text(
                                title,
                                style: const TextStyle(
                                  color: Color(0xFF101B32),
                                  fontSize: 20,
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                              const SizedBox(height: 6),
                              Text(
                                subtitle,
                                style: const TextStyle(
                                  color: Color(0xFF66728A),
                                  fontSize: 13,
                                  height: 1.35,
                                ),
                              ),
                            ],
                          ),
                        ),
                        GestureDetector(
                          onTap: () => Navigator.of(context).pop(),
                          behavior: HitTestBehavior.opaque,
                          child: const Padding(
                            padding: EdgeInsets.all(6),
                            child: Icon(
                              CupertinoIcons.xmark,
                              color: Color(0xFF34415C),
                              size: 20,
                            ),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 22),
                    _IdentitySearchInput(
                      controller: _queryController,
                      isResolving: _isResolving,
                      onSubmitted: _resolve,
                    ),
                    const SizedBox(height: 14),
                    SizedBox(
                      width: double.infinity,
                      child: AppPrimaryButton(
                        key: const Key('identity-lookup-search-button'),
                        label: _isResolving ? '匹配中...' : '匹配身份',
                        semanticsIdentifier:
                            'e2e-identity-lookup-search-button',
                        onPressed: _isResolving ? null : _resolve,
                      ),
                    ),
                    if (_errorText != null) ...<Widget>[
                      const SizedBox(height: 12),
                      _InlineNotice(text: _errorText!, danger: true),
                    ],
                    if (_profile != null) ...<Widget>[
                      const SizedBox(height: 18),
                      _IdentityPreviewCard(
                        profile: _profile!,
                        relationship: _relationship,
                      ),
                      const SizedBox(height: 12),
                      const _InlineNotice(
                        text: '消息将通过已验证 DID 连接发送；首次联系外部身份请谨慎确认。',
                      ),
                      if (_isAddContact) ...<Widget>[
                        const SizedBox(height: 16),
                        AppTextField(
                          key: const Key('identity-add-reason-field'),
                          controller: _reasonController,
                          label: '添加理由（必填）',
                          placeholder: '说明你希望建立连接的原因',
                          multiline: true,
                        ),
                        const SizedBox(height: 12),
                        AppTextField(
                          controller: _noteController,
                          label: '备注（可选）',
                          placeholder: '例如：融资协作 Agent',
                        ),
                      ],
                    ],
                    const SizedBox(height: 22),
                    Row(
                      children: <Widget>[
                        Expanded(
                          child: AppSecondaryButton(
                            label: context.l10n.commonCancel,
                            onPressed: () => Navigator.of(context).pop(),
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: AppPrimaryButton(
                            key: Key(
                              _isAddContact
                                  ? 'identity-add-contact-button'
                                  : 'identity-start-chat-button',
                            ),
                            label: actionLabel,
                            semanticsIdentifier: _isAddContact
                                ? 'e2e-identity-add-contact-button'
                                : 'e2e-identity-start-chat-button',
                            onPressed: _profile == null ? null : _submit,
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _IdentitySearchInput extends StatelessWidget {
  const _IdentitySearchInput({
    required this.controller,
    required this.isResolving,
    required this.onSubmitted,
  });

  final TextEditingController controller;
  final bool isResolving;
  final Future<void> Function() onSubmitted;

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 52,
      padding: const EdgeInsets.symmetric(horizontal: 14),
      decoration: BoxDecoration(
        color: const Color(0xFFFBFDFF),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: const Color(0xFFDDE5F0)),
      ),
      child: Row(
        children: <Widget>[
          const Icon(CupertinoIcons.search, color: Color(0xFF34415C), size: 20),
          const SizedBox(width: 10),
          Expanded(
            child: e2eSemantics(
              identifier: 'e2e-identity-lookup-input',
              label: '输入 handle 或 DID',
              textField: true,
              child: CupertinoTextField(
                key: const Key('identity-lookup-input'),
                controller: controller,
                enabled: !isResolving,
                placeholder: '输入 @handle / DID / Agent 地址',
                textInputAction: TextInputAction.search,
                onSubmitted: (_) async => onSubmitted(),
                decoration: null,
                padding: EdgeInsets.zero,
                style: const TextStyle(color: Color(0xFF17213A), fontSize: 14),
                placeholderStyle: const TextStyle(
                  color: Color(0xFF8A96AA),
                  fontSize: 14,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _IdentityPreviewCard extends StatelessWidget {
  const _IdentityPreviewCard({required this.profile, this.relationship});

  final UserProfile profile;
  final RelationshipSummary? relationship;

  @override
  Widget build(BuildContext context) {
    final displayName = DidDisplayFormatter.profileName(profile);
    final handle = profile.handle?.trim();
    final relationshipLabel = relationship?.relationship.trim();
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: const Color(0xFFFBFDFF),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: const Color(0xFFDDE5F0)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Row(
            children: <Widget>[
              AvatarBadge(seed: displayName, size: 52),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: <Widget>[
                    Text(
                      displayName,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        color: Color(0xFF101B32),
                        fontSize: 17,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    const SizedBox(height: 5),
                    Text(
                      handle == null || handle.isEmpty
                          ? profile.did
                          : '@$handle',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        color: Color(0xFF66728A),
                        fontSize: 12,
                      ),
                    ),
                  ],
                ),
              ),
              const _IdentityStatusPill(label: '已验证'),
            ],
          ),
          const SizedBox(height: 14),
          _IdentityMetaLine(label: 'DID', value: profile.did),
          _IdentityMetaLine(label: '类型', value: _inferIdentityType(profile)),
          _IdentityMetaLine(
            label: '关系',
            value: relationshipLabel == null || relationshipLabel.isEmpty
                ? 'none'
                : relationshipLabel,
          ),
          if (profile.bio.trim().isNotEmpty)
            _IdentityMetaLine(label: '简介', value: profile.bio.trim()),
          if (profile.tags.isNotEmpty) ...<Widget>[
            const SizedBox(height: 10),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: profile.tags
                  .map(
                    (tag) => AppPill(
                      label: tag,
                      backgroundColor: const Color(0xFFEAF2FF),
                      foregroundColor: const Color(0xFF0B65F8),
                    ),
                  )
                  .toList(),
            ),
          ],
        ],
      ),
    );
  }

  String _inferIdentityType(UserProfile profile) {
    final joined = <String>[
      profile.nickName,
      profile.handle ?? '',
      profile.bio,
      ...profile.tags,
    ].join(' ').toLowerCase();
    if (joined.contains('agent') || joined.contains('智能体')) {
      return 'Agent';
    }
    return '用户';
  }
}

class _IdentityStatusPill extends StatelessWidget {
  const _IdentityStatusPill({required this.label});

  final String label;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 5),
      decoration: BoxDecoration(
        color: const Color(0xFFE6F8EE),
        borderRadius: BorderRadius.circular(999),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          const Icon(
            CupertinoIcons.checkmark_shield_fill,
            size: 13,
            color: Color(0xFF10A85A),
          ),
          const SizedBox(width: 4),
          Text(
            label,
            style: const TextStyle(
              color: Color(0xFF10A85A),
              fontSize: 12,
              fontWeight: FontWeight.w500,
            ),
          ),
        ],
      ),
    );
  }
}

class _IdentityMetaLine extends StatelessWidget {
  const _IdentityMetaLine({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(top: 8),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          SizedBox(
            width: 52,
            child: Text(
              '$label:',
              style: const TextStyle(
                color: Color(0xFF34415C),
                fontSize: 12,
                fontWeight: FontWeight.w500,
              ),
            ),
          ),
          Expanded(
            child: Text(
              value,
              maxLines: label == 'DID' ? 2 : 3,
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

class _InlineNotice extends StatelessWidget {
  const _InlineNotice({required this.text, this.danger = false});

  final String text;
  final bool danger;

  @override
  Widget build(BuildContext context) {
    if (danger) {
      return AwikiMeErrorNotice(message: text, compact: true);
    }
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: const Color(0xFFEAF2FF),
        borderRadius: BorderRadius.circular(10),
      ),
      child: Text(
        text,
        style: const TextStyle(
          color: Color(0xFF0B65F8),
          fontSize: 12,
          height: 1.35,
        ),
      ),
    );
  }
}

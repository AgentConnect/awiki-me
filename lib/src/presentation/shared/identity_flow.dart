import 'package:flutter/cupertino.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:awiki_me/l10n/app_localizations.dart';

import '../../app/e2e_semantics.dart';
import '../../app/app_router.dart';
import '../../app/app_services.dart';
import '../../app/ui_feedback.dart';
import '../../application/ports/directory_core_port.dart';
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
import 'app_dialog.dart';
import 'awiki_me_feedback.dart';
import 'avatar_badge.dart';
import 'formatters/display_formatters.dart';
import 'responsive_layout.dart';
import 'semantic_pill.dart';
import 'widgets/app_widgets.dart';

enum IdentityFlowMode { startConversation, followContact }

class IdentityFlowResult {
  const IdentityFlowResult({required this.profile});

  final UserProfile profile;
}

typedef IdentityConfirmAction = Future<void> Function(UserProfile profile);

class IdentityLookupDialogConfig {
  const IdentityLookupDialogConfig({
    required this.title,
    required this.subtitle,
    required this.actionLabel,
    required this.actionButtonKey,
    required this.actionSemanticsIdentifier,
    required this.previewNoticeText,
    this.searchButtonKey = const Key('identity-lookup-search-button'),
    this.inputKey = const Key('identity-lookup-input'),
    this.inputSemanticsIdentifier = 'e2e-identity-lookup-input',
    required this.inputSemanticsLabel,
    required this.inputPlaceholder,
    required this.searchLabel,
    required this.resolvingLabel,
    required this.submittingLabel,
    this.loadRelationship = false,
    this.showRelationship = true,
  });

  final String title;
  final String subtitle;
  final String actionLabel;
  final Key actionButtonKey;
  final String actionSemanticsIdentifier;
  final String previewNoticeText;
  final Key searchButtonKey;
  final Key inputKey;
  final String inputSemanticsIdentifier;
  final String inputSemanticsLabel;
  final String inputPlaceholder;
  final String searchLabel;
  final String resolvingLabel;
  final String submittingLabel;
  final bool loadRelationship;
  final bool showRelationship;

  factory IdentityLookupDialogConfig.forMode(
    IdentityFlowMode mode,
    AppLocalizations l10n,
  ) {
    switch (mode) {
      case IdentityFlowMode.startConversation:
        return IdentityLookupDialogConfig(
          title: l10n.quickActionStartConversation,
          subtitle: l10n.identityStartConversationSubtitle,
          actionLabel: l10n.identityStartConversationAction,
          actionButtonKey: const Key('identity-start-chat-button'),
          actionSemanticsIdentifier: 'e2e-identity-start-chat-button',
          previewNoticeText: l10n.identityStartConversationNotice,
          inputSemanticsLabel: l10n.identityInputSemantics,
          inputPlaceholder: l10n.identityInputPlaceholder,
          searchLabel: l10n.identitySearchLabel,
          resolvingLabel: l10n.identityResolving,
          submittingLabel: l10n.identitySubmitting,
        );
      case IdentityFlowMode.followContact:
        return IdentityLookupDialogConfig(
          title: l10n.identityFollowContactTitle,
          subtitle: l10n.identityFollowContactSubtitle,
          actionLabel: l10n.identityFollowContactAction,
          actionButtonKey: const Key('identity-add-contact-button'),
          actionSemanticsIdentifier: 'e2e-identity-add-contact-button',
          previewNoticeText: l10n.identityFollowContactNotice,
          inputSemanticsLabel: l10n.identityInputSemantics,
          inputPlaceholder: l10n.identityInputPlaceholder,
          searchLabel: l10n.identitySearchLabel,
          resolvingLabel: l10n.identityResolving,
          submittingLabel: l10n.identitySubmitting,
          loadRelationship: true,
        );
    }
  }

  factory IdentityLookupDialogConfig.addGroupMember(AppLocalizations l10n) {
    return IdentityLookupDialogConfig(
      title: l10n.identityAddGroupMemberTitle,
      subtitle: l10n.identityAddGroupMemberSubtitle,
      actionLabel: l10n.identityAddGroupMemberAction,
      actionButtonKey: const Key('identity-add-group-member-button'),
      actionSemanticsIdentifier: 'e2e-identity-add-group-member-button',
      previewNoticeText: l10n.identityAddGroupMemberNotice,
      inputSemanticsLabel: l10n.identityInputSemantics,
      inputPlaceholder: l10n.identityInputPlaceholder,
      searchLabel: l10n.identitySearchLabel,
      resolvingLabel: l10n.identityResolving,
      submittingLabel: l10n.identitySubmitting,
      showRelationship: false,
    );
  }
}

String normalizeDidOrHandleInput(String rawValue) {
  var value = rawValue.trim();
  while (value.startsWith('@')) {
    value = value.substring(1).trimLeft();
  }
  return value;
}

Future<UserProfile> resolveIdentityProfile(
  WidgetRef ref,
  String rawQuery,
) async {
  final query = normalizeDidOrHandleInput(rawQuery);
  if (query.isEmpty) {
    throw ArgumentError('identity_query_required');
  }
  try {
    final resolution = await ref
        .read(directoryApplicationServiceProvider)
        .resolvePeer(query);
    return resolution.profile ?? identityProfileFromResolution(resolution);
  } catch (_) {
    return ref.read(profileApplicationServiceProvider).loadPublicProfile(query);
  }
}

UserProfile identityProfileFromResolution(DirectoryPeerResolution resolution) {
  final did = resolution.did.trim();
  if (did.isEmpty) {
    throw StateError('identity_missing_did');
  }
  final handle = resolution.handle?.trim();
  final displayName = handle == null || handle.isEmpty
      ? DidDisplayFormatter.compactDid(did)
      : handle;
  return UserProfile(
    did: did,
    displayName: displayName,
    bio: '',
    tags: const <String>[],
    profileMarkdown: '',
    handle: handle,
    fullHandle: handle,
  );
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
    peerHandle: profile.fullHandle ?? profile.handle,
    peerName: DidDisplayFormatter.profileName(profile),
    avatarUri: profile.avatarUri,
    avatarSeed: profile.handle ?? profile.did,
  );
}

Future<void> openDirectConversationForDid(
  BuildContext context,
  WidgetRef ref, {
  required String peerDid,
  required String peerName,
  String? peerHandle,
  String? avatarUri,
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
        .showError(
          AppMessage.fromError(StateError('identity_invalid_contact')),
        );
    return;
  }

  final peerTarget = _directPeerTarget(peerDid: peer, peerHandle: peerHandle);
  final conversationId = _directConversationIdForDid(peer);
  final existing = ref
      .read(conversationListProvider)
      .conversations
      .where(
        (item) =>
            item.conversationId?.trim() == conversationId ||
            item.threadId == conversationId ||
            item.targetPeer?.trim() == peerTarget ||
            item.targetDid?.trim() == peer,
      )
      .toList(growable: false);
  final existingConversation = existing.isEmpty
      ? null
      : _preferAuthoritativeDirectConversation(existing);
  final conversation = existing.isNotEmpty
      ? _directConversationForPeer(
          existingConversation!,
          peerDid: peer,
          peerTarget: peerTarget,
          peerName: peerName,
          avatarUri: avatarUri,
          avatarSeed: avatarSeed,
          fallbackConversationId: conversationId,
        )
      : ConversationSummary(
          conversationId: conversationId,
          threadId: conversationId,
          displayName: _directConversationName(peerName, peer),
          lastMessagePreview: '',
          lastMessageAt: DateTime.now(),
          unreadCount: 0,
          isGroup: false,
          targetDid: peer,
          avatarUri: avatarUri,
          targetPeer: peerTarget,
          avatarSeed: avatarSeed ?? peer,
        );

  ref.read(conversationListProvider.notifier).startConversation(conversation);
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
  required String peerTarget,
  required String peerName,
  String? avatarUri,
  String? avatarSeed,
  required String fallbackConversationId,
}) {
  final existingConversationId = existing.conversationId?.trim();
  final conversationId =
      existingConversationId != null && existingConversationId.isNotEmpty
      ? existingConversationId
      : fallbackConversationId;
  final existingTarget = existing.targetDid?.trim() ?? '';
  final existingPeer = existing.targetPeer?.trim() ?? '';
  final keepExistingName =
      !existing.isGroup &&
      (existingTarget == peerDid || existingPeer == peerTarget) &&
      existing.displayName.trim().isNotEmpty;
  return ConversationSummary(
    conversationId: conversationId,
    threadId: conversationId,
    displayName: keepExistingName
        ? existing.displayName
        : _directConversationName(peerName, peerDid),
    lastMessagePreview: existing.lastMessagePreview,
    lastMessageAt: existing.lastMessageAt,
    unreadCount: existing.unreadCount,
    isGroup: false,
    targetDid: peerDid,
    targetPeer: peerTarget,
    groupId: null,
    avatarUri: avatarUri ?? existing.avatarUri,
    avatarSeed: avatarSeed ?? existing.avatarSeed ?? peerDid,
    lastMessagePayloadJson: existing.lastMessagePayloadJson,
    lastMessageSnapshot: existing.lastMessageSnapshot,
    conversationKey: existing.conversationKey,
    peerLifecycleState: existing.peerLifecycleState,
  );
}

String _directConversationIdForDid(String peerDid) {
  return 'dm:${peerDid.trim()}';
}

ConversationSummary _preferAuthoritativeDirectConversation(
  List<ConversationSummary> conversations,
) {
  assert(conversations.isNotEmpty);
  return conversations.firstWhere((conversation) {
    final conversationId = conversation.conversationId?.trim();
    return conversationId != null && conversationId.isNotEmpty;
  }, orElse: () => conversations.first);
}

String _directPeerTarget({required String peerDid, String? peerHandle}) {
  final handle = peerHandle?.trim();
  if (handle != null && handle.isNotEmpty) {
    return handle.toLowerCase();
  }
  return peerDid.trim();
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

Future<void> showFollowIdentityDialog(
  BuildContext context,
  WidgetRef ref,
) async {
  final result = await AppNavigator.showDialog<IdentityFlowResult>(
    context,
    (_) => const IdentityLookupDialog(mode: IdentityFlowMode.followContact),
  );
  if (result == null) {
    return;
  }

  try {
    await ref.read(friendsProvider.notifier).follow(result.profile.did);
    await ref.read(friendsProvider.notifier).refresh();
    ref
        .read(uiFeedbackProvider.notifier)
        .showInfo(AppMessage.followContactSucceeded());
  } catch (error) {
    ref
        .read(uiFeedbackProvider.notifier)
        .showError(AppMessage.fromError(error));
  }
}

class IdentityLookupDialog extends ConsumerStatefulWidget {
  const IdentityLookupDialog({
    super.key,
    this.mode,
    this.config,
    this.onConfirm,
  }) : assert(mode != null || config != null);

  final IdentityFlowMode? mode;
  final IdentityLookupDialogConfig? config;
  final IdentityConfirmAction? onConfirm;

  @override
  ConsumerState<IdentityLookupDialog> createState() =>
      _IdentityLookupDialogState();
}

class _IdentityLookupDialogState extends ConsumerState<IdentityLookupDialog> {
  final _queryController = TextEditingController();
  bool _isResolving = false;
  bool _isSubmitting = false;
  UserProfile? _profile;
  RelationshipSummary? _relationship;
  String? _errorText;

  IdentityLookupDialogConfig get _config =>
      widget.config ??
      IdentityLookupDialogConfig.forMode(widget.mode!, context.l10n);

  @override
  void dispose() {
    _queryController.dispose();
    super.dispose();
  }

  Future<void> _resolve() async {
    final query = normalizeDidOrHandleInput(_queryController.text);
    if (query.isEmpty) {
      setState(() => _errorText = context.l10n.identityQueryRequired);
      return;
    }
    setState(() {
      _isResolving = true;
      _errorText = null;
      _profile = null;
      _relationship = null;
    });
    try {
      final resolved = await _resolveIdentity(query);
      final profile = resolved.profile;
      RelationshipSummary? relationship;
      if (_config.loadRelationship) {
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
        _errorText = context.l10n.identityResolveFailed;
      });
    }
  }

  Future<_ResolvedIdentity> _resolveIdentity(String query) async {
    final profile = await resolveIdentityProfile(ref, query);
    return _ResolvedIdentity(profile: profile);
  }

  Future<void> _submit() async {
    final profile = _profile;
    if (profile == null || _isSubmitting || _isResolving) {
      return;
    }
    if (_config.loadRelationship) {
      final relationship = _relationship?.relationship.trim() ?? 'none';
      if (relationship.isNotEmpty && relationship != 'none') {
        ref
            .read(uiFeedbackProvider.notifier)
            .showInfo(AppMessage.followContactAlreadyFollowing());
        Navigator.of(context).pop();
        return;
      }
    }
    final confirm = widget.onConfirm;
    if (confirm == null) {
      Navigator.of(context).pop(IdentityFlowResult(profile: profile));
      return;
    }
    setState(() {
      _isSubmitting = true;
      _errorText = null;
    });
    try {
      await confirm(profile);
      if (!mounted) {
        return;
      }
      Navigator.of(context).pop(IdentityFlowResult(profile: profile));
    } catch (error) {
      if (!mounted) {
        return;
      }
      setState(() {
        _isSubmitting = false;
        _errorText = AppMessage.fromError(error).resolve(context.l10n);
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final config = _config;
    final responsive = context.awikiResponsive;
    return AppDialogScaffold(
      maxWidth: 560,
      maxHeightFraction: 0.9,
      horizontalPadding: responsive.isPhone ? 14 : 16,
      verticalPadding: 24,
      borderRadius: BorderRadius.circular(responsive.radius(16)),
      avoidViewInsets: true,
      padding: EdgeInsets.fromLTRB(
        responsive.spacing(22),
        responsive.spacing(20),
        responsive.spacing(22),
        responsive.spacing(22),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          AppDialogHeader(
            title: config.title,
            subtitle: config.subtitle,
            onClose: () => Navigator.of(context).pop(),
            isCloseEnabled: !_isSubmitting,
          ),
          const SizedBox(height: 22),
          Flexible(
            child: SingleChildScrollView(
              keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: <Widget>[
                  _IdentitySearchInput(
                    controller: _queryController,
                    enabled: !_isResolving && !_isSubmitting,
                    keyValue: config.inputKey,
                    semanticsIdentifier: config.inputSemanticsIdentifier,
                    semanticsLabel: config.inputSemanticsLabel,
                    placeholder: config.inputPlaceholder,
                    onSubmitted: _resolve,
                  ),
                  const SizedBox(height: 14),
                  AppPrimaryButton(
                    key: config.searchButtonKey,
                    label: _isResolving
                        ? config.resolvingLabel
                        : config.searchLabel,
                    semanticsIdentifier: 'e2e-identity-lookup-search-button',
                    onPressed: _isResolving || _isSubmitting ? null : _resolve,
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
                      showRelationship: config.showRelationship,
                    ),
                    const SizedBox(height: 12),
                    _InlineNotice(text: config.previewNoticeText),
                  ],
                ],
              ),
            ),
          ),
          const SizedBox(height: 22),
          Row(
            children: <Widget>[
              Expanded(
                child: AppSecondaryButton(
                  label: context.l10n.commonCancel,
                  onPressed: _isSubmitting
                      ? null
                      : () => Navigator.of(context).pop(),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: AppPrimaryButton(
                  key: config.actionButtonKey,
                  label: _isSubmitting
                      ? config.submittingLabel
                      : config.actionLabel,
                  semanticsIdentifier: config.actionSemanticsIdentifier,
                  onPressed: _profile == null || _isResolving || _isSubmitting
                      ? null
                      : _submit,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _ResolvedIdentity {
  const _ResolvedIdentity({required this.profile});

  final UserProfile profile;
}

class _IdentitySearchInput extends StatelessWidget {
  const _IdentitySearchInput({
    required this.controller,
    required this.enabled,
    required this.keyValue,
    required this.semanticsIdentifier,
    required this.semanticsLabel,
    required this.placeholder,
    required this.onSubmitted,
  });

  final TextEditingController controller;
  final bool enabled;
  final Key keyValue;
  final String semanticsIdentifier;
  final String semanticsLabel;
  final String placeholder;
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
              identifier: semanticsIdentifier,
              label: semanticsLabel,
              textField: true,
              child: CupertinoTextField(
                key: keyValue,
                controller: controller,
                enabled: enabled,
                placeholder: placeholder,
                textInputAction: TextInputAction.search,
                onSubmitted: (_) async {
                  if (enabled) {
                    await onSubmitted();
                  }
                },
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
  const _IdentityPreviewCard({
    required this.profile,
    this.relationship,
    this.showRelationship = true,
  });

  final UserProfile profile;
  final RelationshipSummary? relationship;
  final bool showRelationship;

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
              AvatarBadge(
                seed: displayName,
                size: 52,
                avatarUri: profile.avatarUri,
              ),
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
              _IdentityStatusPill(label: context.l10n.identityVerified),
            ],
          ),
          const SizedBox(height: 14),
          _IdentityMetaLine(label: 'DID', value: profile.did),
          _IdentityMetaLine(
            label: context.l10n.identityTypeLabel,
            value: _inferIdentityType(context.l10n, profile),
          ),
          if (showRelationship)
            _IdentityMetaLine(
              label: context.l10n.identityRelationshipLabel,
              value: relationshipLabel == null || relationshipLabel.isEmpty
                  ? localizeRelationshipLabel(context.l10n, 'none')
                  : localizeRelationshipLabel(context.l10n, relationshipLabel),
            ),
          if (profile.bio.trim().isNotEmpty)
            _IdentityMetaLine(
              label: context.l10n.identityBioLabel,
              value: profile.bio.trim(),
            ),
          if (profile.tags.isNotEmpty) ...<Widget>[
            const SizedBox(height: 10),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: profile.tags
                  .map(
                    (tag) => SemanticPill(
                      label: tag,
                      tone: SemanticPillTone.metadata,
                    ),
                  )
                  .toList(),
            ),
          ],
        ],
      ),
    );
  }

  String _inferIdentityType(AppLocalizations l10n, UserProfile profile) {
    final joined = <String>[
      profile.subjectType ?? '',
      profile.displayName,
      profile.handle ?? '',
      profile.bio,
      ...profile.tags,
    ].join(' ').toLowerCase();
    if (joined.contains('agent') || joined.contains('智能体')) {
      return l10n.identityTypeAgent;
    }
    return l10n.identityTypeUser;
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

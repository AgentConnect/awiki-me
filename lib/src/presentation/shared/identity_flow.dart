// [INPUT]: DID/handle queries, directory/profile services, relationship state, and conversation projections.
// [OUTPUT]: Resolved identity UI state and canonical direct-conversation navigation.
// [POS]: Shared identity lookup and Direct chat entry flow for contacts and conversation surfaces.
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
import '../profile/peer_display_profile_provider.dart';
import 'app_dialog.dart';
import 'awiki_me_design.dart';
import 'avatar_badge.dart';
import 'formatters/display_formatters.dart';
import 'responsive_layout.dart';
import 'widgets/app_widgets.dart';
import 'widgets/awiki_desktop.dart';

enum IdentityFlowMode { startConversation, followContact }

class IdentityFlowResult {
  const IdentityFlowResult({required this.profile, this.conversationId});

  final UserProfile profile;
  final String? conversationId;
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
  final expectedEpoch = _requireActiveSessionEpoch(ref);
  return (await _resolveIdentityProfile(
    ref,
    rawQuery,
    expectedEpoch: expectedEpoch,
  )).profile;
}

Future<_ResolvedIdentity> _resolveIdentityProfile(
  WidgetRef ref,
  String rawQuery, {
  required SessionEpoch expectedEpoch,
}) async {
  _requireSessionEpochCurrent(ref, expectedEpoch);
  final query = normalizeDidOrHandleInput(rawQuery);
  if (query.isEmpty) {
    throw ArgumentError('identity_query_required');
  }
  Object? directoryError;
  for (var attempt = 0; attempt < 3; attempt += 1) {
    try {
      final resolution = await ref
          .read(directoryApplicationServiceProvider)
          .resolvePeer(query);
      _requireSessionEpochCurrent(ref, expectedEpoch);
      return _ResolvedIdentity(
        profile: identityProfileFromResolution(resolution),
        conversationId: resolution.conversationId,
      );
    } catch (error) {
      if (isSessionEpochChangedError(error)) {
        rethrow;
      }
      _requireSessionEpochCurrent(ref, expectedEpoch);
      directoryError = error;
      if (attempt < 2) {
        await Future<void>.delayed(Duration(milliseconds: 150 * (attempt + 1)));
        _requireSessionEpochCurrent(ref, expectedEpoch);
      }
    }
  }
  if (!query.startsWith('did:')) {
    // A handle lookup owns the user-id/full-handle peer scope. Falling back to
    // a public profile here would silently reopen the legacy dm:<DID> alias.
    Error.throwWithStackTrace(
      directoryError ?? StateError('directory_resolution_failed'),
      StackTrace.current,
    );
  }
  final profile = await ref
      .read(profileApplicationServiceProvider)
      .loadPublicProfile(query);
  _requireSessionEpochCurrent(ref, expectedEpoch);
  return _ResolvedIdentity(profile: profile);
}

UserProfile identityProfileFromResolution(DirectoryPeerResolution resolution) {
  final did = resolution.did.trim();
  if (did.isEmpty) {
    throw StateError('identity_missing_did');
  }
  final handle = resolution.handle?.trim();
  final profile = resolution.profile;
  final profileHandle = _normalizedOptionalHandle(
    profile?.fullHandle ?? profile?.handle,
  );
  // A display DTO cannot replace the identity returned by Core's directory.
  // Discard inconsistent display data rather than relabeling it as this peer.
  if (profile != null &&
      profile.did.trim() == did &&
      (profileHandle == null ||
          handle == null ||
          profileHandle == _normalizedOptionalHandle(handle))) {
    return profile.copyWith(handle: handle, fullHandle: handle);
  }
  return UserProfile(
    did: did,
    displayName: '',
    bio: '',
    tags: const <String>[],
    profileMarkdown: '',
    handle: handle,
    fullHandle: handle,
  );
}

enum DirectConversationOpenResult { opened, notOpened }

Future<void> openDirectConversationForProfile(
  BuildContext context,
  WidgetRef ref,
  UserProfile profile, {
  String? conversationId,
  SessionEpoch? expectedEpoch,
  bool pushWithinCurrentNavigator = false,
}) async {
  await openDirectConversationForProfileWithResult(
    context,
    ref,
    profile,
    conversationId: conversationId,
    expectedEpoch: expectedEpoch,
    pushWithinCurrentNavigator: pushWithinCurrentNavigator,
  );
}

Future<DirectConversationOpenResult> openDirectConversationForProfileWithResult(
  BuildContext context,
  WidgetRef ref,
  UserProfile profile, {
  String? conversationId,
  SessionEpoch? expectedEpoch,
  bool pushWithinCurrentNavigator = false,
  bool dismissSourceRoutes = true,
}) {
  return openDirectConversationForDidWithResult(
    context,
    ref,
    peerDid: profile.did,
    peerHandle: profile.fullHandle ?? profile.handle,
    peerName: DidDisplayFormatter.profileName(profile),
    peerProfile: profile,
    avatarUri: profile.avatarUri,
    avatarSeed: profile.handle ?? profile.did,
    conversationId: conversationId,
    expectedEpoch: expectedEpoch,
    pushWithinCurrentNavigator: pushWithinCurrentNavigator,
    dismissSourceRoutes: dismissSourceRoutes,
  );
}

Future<String> resolveCanonicalConversationIdForProfile(
  WidgetRef ref,
  UserProfile profile, {
  SessionEpoch? expectedEpoch,
}) async {
  final operationEpoch = expectedEpoch ?? _requireActiveSessionEpoch(ref);
  final resolved = await _resolveDirectPeer(
    ref,
    peerDid: profile.did,
    peerHandle: profile.fullHandle ?? profile.handle,
    expectedEpoch: operationEpoch,
  );
  _requireSessionEpochCurrent(ref, operationEpoch);
  return resolved.conversationId;
}

Future<void> openDirectConversationForDid(
  BuildContext context,
  WidgetRef ref, {
  required String peerDid,
  required String peerName,
  String? peerHandle,
  String? avatarUri,
  String? avatarSeed,
  String? conversationId,
  SessionEpoch? expectedEpoch,
  bool popCurrentRouteOnTwoPane = false,
  bool pushWithinCurrentNavigator = false,
}) async {
  await openDirectConversationForDidWithResult(
    context,
    ref,
    peerDid: peerDid,
    peerName: peerName,
    peerHandle: peerHandle,
    avatarUri: avatarUri,
    avatarSeed: avatarSeed,
    conversationId: conversationId,
    expectedEpoch: expectedEpoch,
    popCurrentRouteOnTwoPane: popCurrentRouteOnTwoPane,
    pushWithinCurrentNavigator: pushWithinCurrentNavigator,
  );
}

Future<DirectConversationOpenResult> openDirectConversationForDidWithResult(
  BuildContext context,
  WidgetRef ref, {
  required String peerDid,
  required String peerName,
  UserProfile? peerProfile,
  String? peerHandle,
  String? avatarUri,
  String? avatarSeed,
  String? conversationId,
  SessionEpoch? expectedEpoch,
  bool popCurrentRouteOnTwoPane = false,
  bool pushWithinCurrentNavigator = false,
  bool dismissSourceRoutes = true,
}) async {
  final operationEpoch = expectedEpoch ?? ref.read(sessionProvider).activeEpoch;
  if (operationEpoch == null) {
    ref
        .read(uiFeedbackProvider.notifier)
        .showError(AppMessage.sessionExpiredRelogin());
    return DirectConversationOpenResult.notOpened;
  }
  if (!_isSessionEpochCurrent(ref, operationEpoch)) {
    return DirectConversationOpenResult.notOpened;
  }

  final peer = peerDid.trim();
  if (!peer.startsWith('did:')) {
    ref
        .read(uiFeedbackProvider.notifier)
        .showError(
          AppMessage.fromError(StateError('identity_invalid_contact')),
        );
    return DirectConversationOpenResult.notOpened;
  }

  late final _ResolvedDirectPeer resolvedPeer;
  try {
    resolvedPeer = await _resolveDirectPeer(
      ref,
      peerDid: peer,
      peerHandle: peerHandle,
      resolvedConversationId: conversationId,
      expectedEpoch: operationEpoch,
    );
  } catch (error) {
    if (isSessionEpochChangedError(error) ||
        !_isSessionEpochCurrent(ref, operationEpoch)) {
      return DirectConversationOpenResult.notOpened;
    }
    ref
        .read(uiFeedbackProvider.notifier)
        .showError(AppMessage.fromError(error));
    return DirectConversationOpenResult.notOpened;
  }
  if (!_isSessionEpochCurrent(ref, operationEpoch)) {
    return DirectConversationOpenResult.notOpened;
  }
  final canonicalConversationId = resolvedPeer.conversationId;
  late final ConversationSummary conversation;
  try {
    conversation = await ref
        .read(conversationListProvider.notifier)
        .commitConversationId(
          canonicalConversationId,
          expectedEpoch: operationEpoch,
        );
    if (!_isSessionEpochCurrent(ref, operationEpoch)) {
      return DirectConversationOpenResult.notOpened;
    }
    final displayProfile = resolvedPeer.profile ?? peerProfile;
    if (displayProfile != null &&
        displayProfile.did == resolvedPeer.did &&
        (conversation.targetDid == null ||
            conversation.targetDid == displayProfile.did)) {
      ref
          .read(peerDisplayProfileProvider.notifier)
          .updateFromRemote(
            ownerDid: operationEpoch.ownerDid,
            peerPersonaId: conversation.peerPersonaId,
            expectedEpoch: operationEpoch,
            profile: identityProfileFromResolution(
              DirectoryPeerResolution(
                input: resolvedPeer.did,
                did: resolvedPeer.did,
                handle: resolvedPeer.handle,
                profile: displayProfile,
              ),
            ),
          );
    }
    await ref.read(chatThreadsProvider.notifier).openConversation(conversation);
  } catch (error) {
    if (isSessionEpochChangedError(error) ||
        !_isSessionEpochCurrent(ref, operationEpoch)) {
      return DirectConversationOpenResult.notOpened;
    }
    ref
        .read(uiFeedbackProvider.notifier)
        .showError(AppMessage.fromError(error));
    return DirectConversationOpenResult.notOpened;
  }
  if (!context.mounted || !_isSessionEpochCurrent(ref, operationEpoch)) {
    return DirectConversationOpenResult.notOpened;
  }

  if (pushWithinCurrentNavigator ||
      !AwikiShellNavigationScope.isPresent(context)) {
    await AppNavigator.push(
      context,
      (_) => ChatPage(conversation: conversation),
    );
    return DirectConversationOpenResult.opened;
  }

  ref
      .read(selectedConversationProvider.notifier)
      .selectConversation(conversation);
  ref
      .read(shellDestinationProvider.notifier)
      .selectForLayout(
        ShellDestination.messages,
        expanded: context.awikiResponsive.usesDesktopLayout,
      );
  if (dismissSourceRoutes) {
    if (popCurrentRouteOnTwoPane &&
        context.awikiResponsive.supportsTwoPane &&
        context.mounted) {
      await Navigator.of(context).maybePop();
    }
    if (!context.mounted) {
      return DirectConversationOpenResult.opened;
    }
    final navigator = Navigator.of(context);
    if (navigator.canPop()) {
      navigator.popUntil((route) => route.isFirst);
    }
  }
  return DirectConversationOpenResult.opened;
}

Future<_ResolvedDirectPeer> _resolveDirectPeer(
  WidgetRef ref, {
  required String peerDid,
  required SessionEpoch expectedEpoch,
  String? peerHandle,
  String? resolvedConversationId,
}) async {
  _requireSessionEpochCurrent(ref, expectedEpoch);
  final providedHandle = _normalizedOptionalHandle(peerHandle);
  final providedConversationId = resolvedConversationId?.trim();
  if (providedConversationId != null && providedConversationId.isNotEmpty) {
    _validateResolvedDirectConversation(conversationId: providedConversationId);
    return _ResolvedDirectPeer(
      did: peerDid,
      handle: providedHandle,
      conversationId: providedConversationId,
    );
  }

  // A profile's Handle is presentation data. Resolve its DID through Core;
  // only Core may establish the canonical Handle/Persona route for that DID.
  final resolution = await ref
      .read(directoryApplicationServiceProvider)
      .resolvePeer(peerDid);
  _requireSessionEpochCurrent(ref, expectedEpoch);
  final resolvedDid = resolution.did.trim();
  if (!resolvedDid.startsWith('did:')) {
    throw StateError('identity_invalid_contact');
  }
  if (resolvedDid != peerDid) {
    throw StateError('identity_resolution_did_mismatch');
  }
  final resolvedHandle = _normalizedOptionalHandle(resolution.handle);
  final canonicalConversationId = resolution.conversationId?.trim() ?? '';
  _validateResolvedDirectConversation(conversationId: canonicalConversationId);
  return _ResolvedDirectPeer(
    did: resolvedDid,
    handle: resolvedHandle,
    conversationId: canonicalConversationId,
    profile: resolution.profile == null
        ? null
        : identityProfileFromResolution(resolution),
  );
}

void _validateResolvedDirectConversation({required String conversationId}) {
  if (!conversationId.startsWith('dm:peer-scope:v1:')) {
    throw StateError('identity_missing_canonical_conversation');
  }
}

String? _normalizedOptionalHandle(String? value) {
  var handle = value?.trim();
  if (handle == null || handle.isEmpty) {
    return null;
  }
  while (handle!.startsWith('@')) {
    handle = handle.substring(1).trimLeft();
  }
  return handle.isEmpty ? null : handle.toLowerCase();
}

SessionEpoch _requireActiveSessionEpoch(WidgetRef ref) {
  final epoch = ref.read(sessionProvider).activeEpoch;
  if (epoch == null) {
    throw sessionEpochChangedError();
  }
  return epoch;
}

bool _isSessionEpochCurrent(WidgetRef ref, SessionEpoch expectedEpoch) {
  return expectedEpoch.matches(ref.read(sessionProvider));
}

void _requireSessionEpochCurrent(WidgetRef ref, SessionEpoch expectedEpoch) {
  if (!_isSessionEpochCurrent(ref, expectedEpoch)) {
    throw sessionEpochChangedError();
  }
}

Future<void> showStartConversationDialog(
  BuildContext context,
  WidgetRef ref,
) async {
  final expectedEpoch = ref.read(sessionProvider).activeEpoch;
  if (expectedEpoch == null) {
    return;
  }
  final result = await AppNavigator.showDialog<IdentityFlowResult>(
    context,
    (_) => const IdentityLookupDialog(mode: IdentityFlowMode.startConversation),
  );
  if (result == null ||
      !context.mounted ||
      !_isSessionEpochCurrent(ref, expectedEpoch)) {
    return;
  }
  await openDirectConversationForProfile(
    context,
    ref,
    result.profile,
    conversationId: result.conversationId,
    expectedEpoch: expectedEpoch,
  );
}

Future<void> showFollowIdentityDialog(
  BuildContext context,
  WidgetRef ref,
) async {
  final expectedEpoch = ref.read(sessionProvider).activeEpoch;
  if (expectedEpoch == null) {
    return;
  }
  final result = await AppNavigator.showDialog<IdentityFlowResult>(
    context,
    (_) => const IdentityLookupDialog(mode: IdentityFlowMode.followContact),
  );
  if (result == null || !_isSessionEpochCurrent(ref, expectedEpoch)) {
    return;
  }

  try {
    await ref.read(friendsProvider.notifier).follow(result.profile.did);
    if (!_isSessionEpochCurrent(ref, expectedEpoch)) {
      return;
    }
    ref
        .read(uiFeedbackProvider.notifier)
        .showInfo(AppMessage.followContactSucceeded());
  } catch (error) {
    if (isSessionEpochChangedError(error) ||
        !_isSessionEpochCurrent(ref, expectedEpoch)) {
      return;
    }
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
  String? _conversationId;
  RelationshipSummary? _relationship;
  String? _errorText;
  late final SessionEpoch? _dialogEpoch;

  IdentityLookupDialogConfig get _config =>
      widget.config ??
      IdentityLookupDialogConfig.forMode(widget.mode!, context.l10n);

  @override
  void initState() {
    super.initState();
    _dialogEpoch = ref.read(sessionProvider).activeEpoch;
  }

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
      _conversationId = null;
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
      if (!_isDialogEpochCurrent()) {
        Navigator.of(context).pop();
        return;
      }
      setState(() {
        _profile = profile;
        _conversationId = resolved.conversationId;
        _relationship = relationship;
        _isResolving = false;
      });
    } catch (error) {
      if (!mounted) {
        return;
      }
      if (isSessionEpochChangedError(error) || !_isDialogEpochCurrent()) {
        Navigator.of(context).pop();
        return;
      }
      setState(() {
        _isResolving = false;
        _errorText = context.l10n.identityResolveFailed;
      });
    }
  }

  Future<_ResolvedIdentity> _resolveIdentity(String query) async {
    final epoch = _dialogEpoch;
    if (epoch == null) {
      throw sessionEpochChangedError();
    }
    return _resolveIdentityProfile(ref, query, expectedEpoch: epoch);
  }

  Future<void> _submit() async {
    final profile = _profile;
    if (profile == null || _isSubmitting || _isResolving) {
      return;
    }
    if (!_isDialogEpochCurrent()) {
      Navigator.of(context).pop();
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
      Navigator.of(context).pop(
        IdentityFlowResult(profile: profile, conversationId: _conversationId),
      );
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
      if (!_isDialogEpochCurrent()) {
        Navigator.of(context).pop();
        return;
      }
      Navigator.of(context).pop(
        IdentityFlowResult(profile: profile, conversationId: _conversationId),
      );
    } catch (error) {
      if (!mounted) {
        return;
      }
      if (isSessionEpochChangedError(error) || !_isDialogEpochCurrent()) {
        Navigator.of(context).pop();
        return;
      }
      setState(() {
        _isSubmitting = false;
        _errorText = AppMessage.fromError(error).resolve(context.l10n);
      });
    }
  }

  bool _isDialogEpochCurrent() {
    final epoch = _dialogEpoch;
    return epoch != null && _isSessionEpochCurrent(ref, epoch);
  }

  @override
  Widget build(BuildContext context) {
    final config = _config;
    final responsive = context.awikiResponsive;
    final theme = context.awikiTheme;
    // Reference `.dlg`: a title, one search field with the match listed
    // below it, and right-aligned cancel / primary actions.
    return AppDialogScaffold(
      maxWidth: 420,
      maxHeightFraction: 0.9,
      horizontalPadding: responsive.isPhone ? 14 : 16,
      verticalPadding: 24,
      avoidViewInsets: true,
      compactCentered: true,
      padding: const EdgeInsets.fromLTRB(20, 20, 20, 16),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          Text(
            config.title,
            style: TextStyle(
              color: theme.title,
              fontSize: 19,
              height: 1.25,
              fontWeight: FontWeight.w400,
            ),
          ),
          const SizedBox(height: 14),
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
                    searchButton: _IdentitySearchButton(
                      key: config.searchButtonKey,
                      label: _isResolving
                          ? config.resolvingLabel
                          : config.searchLabel,
                      busy: _isResolving,
                      onTap: _isResolving || _isSubmitting ? null : _resolve,
                    ),
                  ),
                  if (_errorText != null) ...<Widget>[
                    const SizedBox(height: 8),
                    Text(
                      _errorText!,
                      style: TextStyle(color: theme.danger, fontSize: 12),
                    ),
                  ],
                  if (_profile != null) ...<Widget>[
                    const SizedBox(height: 12),
                    _IdentityPreviewCard(
                      profile: _profile!,
                      relationship: _relationship,
                      showRelationship: config.showRelationship,
                    ),
                    const SizedBox(height: 8),
                    Text(
                      config.previewNoticeText,
                      style: TextStyle(
                        color: theme.secondaryText,
                        fontSize: 12,
                        height: 1.4,
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ),
          const SizedBox(height: 16),
          AwikiDialogActionRow(
            cancelLabel: context.l10n.commonCancel,
            onCancel: _isSubmitting ? null : () => Navigator.of(context).pop(),
            primaryKey: config.actionButtonKey,
            primaryLabel: _isSubmitting
                ? config.submittingLabel
                : config.actionLabel,
            primarySemanticsIdentifier: config.actionSemanticsIdentifier,
            onPrimary: _profile == null || _isResolving || _isSubmitting
                ? null
                : _submit,
          ),
        ],
      ),
    );
  }
}

class _ResolvedIdentity {
  const _ResolvedIdentity({required this.profile, this.conversationId});

  final UserProfile profile;
  final String? conversationId;
}

class _ResolvedDirectPeer {
  const _ResolvedDirectPeer({
    required this.did,
    required this.handle,
    required this.conversationId,
    this.profile,
  });

  final String did;
  final String? handle;
  final String conversationId;
  final UserProfile? profile;
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
    required this.searchButton,
  });

  final TextEditingController controller;
  final bool enabled;
  final Key keyValue;
  final String semanticsIdentifier;
  final String semanticsLabel;
  final String placeholder;
  final Future<void> Function() onSubmitted;
  final Widget searchButton;

  @override
  Widget build(BuildContext context) {
    final theme = context.awikiTheme;
    final phone = context.awikiResponsive.isPhone;
    return Container(
      height: phone ? 48 : 38,
      padding: EdgeInsets.fromLTRB(phone ? 14 : 10, 0, phone ? 5 : 4, 0),
      decoration: BoxDecoration(
        color: phone ? theme.glass : theme.surface,
        borderRadius: BorderRadius.circular(phone ? 16 : 6),
        border: Border.all(
          color: phone ? theme.glassEdge : theme.border,
          width: phone ? 0.5 : 1,
        ),
      ),
      child: Row(
        children: <Widget>[
          Icon(
            CupertinoIcons.search,
            color: theme.secondaryText,
            size: phone ? 17 : 15,
          ),
          const SizedBox(width: 8),
          Expanded(
            child: e2eSemantics(
              identifier: semanticsIdentifier,
              label: semanticsLabel,
              textField: true,
              child: CupertinoTextField(
                key: keyValue,
                controller: controller,
                enabled: enabled,
                autofocus: true,
                placeholder: placeholder,
                textInputAction: TextInputAction.search,
                onSubmitted: (_) async {
                  if (enabled) {
                    await onSubmitted();
                  }
                },
                decoration: null,
                padding: EdgeInsets.zero,
                style: TextStyle(color: theme.title, fontSize: phone ? 16 : 14),
                placeholderStyle: TextStyle(
                  color: theme.secondaryText,
                  fontSize: phone ? 16 : 14,
                ),
              ),
            ),
          ),
          const SizedBox(width: 6),
          searchButton,
        ],
      ),
    );
  }
}

/// Inline trigger inside the search field; Enter does the same.
class _IdentitySearchButton extends StatelessWidget {
  const _IdentitySearchButton({
    super.key,
    required this.label,
    required this.busy,
    required this.onTap,
  });

  final String label;
  final bool busy;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final theme = context.awikiTheme;
    final phone = context.awikiResponsive.isPhone;
    final radius = BorderRadius.circular(phone ? 18 : 5);
    return AppPressable(
      onTap: onTap,
      enabled: onTap != null,
      semanticLabel: label,
      semanticsIdentifier: 'e2e-identity-lookup-search-button',
      button: true,
      borderRadius: radius,
      builder: (context, state, child) => AnimatedContainer(
        duration: const Duration(milliseconds: 120),
        height: phone ? 38 : 28,
        padding: const EdgeInsets.symmetric(horizontal: 12),
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: phone
              ? theme.glassLens
              : (state.hovered || state.pressed
                    ? theme.title.withValues(alpha: 0.12)
                    : theme.title.withValues(alpha: 0.065)),
          borderRadius: radius,
        ),
        child: child,
      ),
      child: busy
          ? const CupertinoActivityIndicator(radius: 7)
          : Text(
              label,
              style: TextStyle(
                color: theme.title,
                fontSize: phone ? 14 : 13,
                height: 1,
              ),
            ),
    );
  }
}

/// Reference `.match`: one compact row with the avatar, name,
/// "@handle · verified" and a verified shield.
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
    final theme = context.awikiTheme;
    final phone = context.awikiResponsive.isPhone;
    final displayName = DidDisplayFormatter.identityLookupTitle(profile);
    final secondaryHandle = DidDisplayFormatter.identityLookupSecondaryHandle(
      profile,
    );
    final relationshipLabel = relationship?.relationship.trim();
    final metaStyle = TextStyle(color: theme.secondaryText, fontSize: 12);
    final isAgent = profile.identityType.isAgent;
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 10),
      decoration: BoxDecoration(
        color: phone ? theme.glass : theme.surface,
        borderRadius: BorderRadius.circular(phone ? 14 : 8),
        border: Border.all(
          color: phone ? theme.glassEdge : theme.border,
          width: phone ? 0.5 : 1,
        ),
      ),
      child: Row(
        children: <Widget>[
          AvatarBadge(
            seed: displayName,
            size: 36,
            avatarUri: profile.avatarUri,
            isAgent: isAgent,
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: <Widget>[
                Text(
                  displayName,
                  key: const Key('identity-preview-display-name'),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(color: theme.title, fontSize: 14),
                ),
                const SizedBox(height: 2),
                Row(
                  children: <Widget>[
                    if (secondaryHandle.isNotEmpty) ...<Widget>[
                      Flexible(
                        child: Text(
                          secondaryHandle,
                          key: const Key('identity-preview-handle-value'),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: metaStyle,
                        ),
                      ),
                      Text(' · ', style: metaStyle),
                    ],
                    Text(context.l10n.identityVerified, style: metaStyle),
                    if (showRelationship &&
                        relationshipLabel != null &&
                        relationshipLabel.isNotEmpty &&
                        relationshipLabel != 'none') ...<Widget>[
                      Text(' · ', style: metaStyle),
                      Flexible(
                        child: Text(
                          localizeRelationshipLabel(
                            context.l10n,
                            relationshipLabel,
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: metaStyle,
                        ),
                      ),
                    ],
                  ],
                ),
                // The full identity stays visible: the DID is what the
                // conversation or follow will actually bind to.
                const SizedBox(height: 2),
                Text(
                  DidDisplayFormatter.compactDidPath(profile.did),
                  key: const Key('identity-preview-did-value'),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: theme.tertiaryText,
                    fontSize: 11,
                    fontFamily: 'monospace',
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 8),
          Icon(CupertinoIcons.checkmark_shield, size: 16, color: theme.success),
        ],
      ),
    );
  }
}

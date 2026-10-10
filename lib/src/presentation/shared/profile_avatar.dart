import 'dart:async';
import 'dart:math' as math;
import 'dart:ui' as ui;
import 'package:flutter/cupertino.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart' show Tooltip;
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/avatar/avatar_image_cache.dart';
import '../../l10n/l10n.dart';
import '../app_shell/providers/session_provider.dart';
import '../profile/peer_display_profile_provider.dart';
import 'avatar_badge.dart';
import 'agent_avatar_image.dart';
import 'awiki_me_design.dart';

/// Profile-only interaction; list/message avatars keep their existing actions.
class ProfileAvatar extends ConsumerStatefulWidget {
  const ProfileAvatar({
    super.key,
    required this.seed,
    this.userId,
    this.avatarUri,
    this.size = 64,
    this.onEdit,
  });
  final String seed;
  final String? userId;
  final String? avatarUri;
  final double size;
  final VoidCallback? onEdit;
  @override
  ConsumerState<ProfileAvatar> createState() => _ProfileAvatarState();
}

class _ProfileAvatarState extends ConsumerState<ProfileAvatar> {
  bool _hover = false;
  bool _focus = false;

  @override
  Widget build(BuildContext context) {
    final input = (
      did: widget.userId,
      uri: widget.avatarUri,
      thumbnail: null as String?,
    );
    final reference = ref.watch(avatarReferenceProvider(input));
    final isAgent = ref.watch(avatarIsAgentProvider(widget.userId));
    final editable = widget.onEdit != null;
    final active = editable || safeAvatarUri(reference.uri) != null;
    final label = editable
        ? context.l10n.profileAvatarChange
        : context.l10n.avatarView;
    final theme = context.awikiTheme;
    final touch =
        !kIsWeb &&
        {
          TargetPlatform.android,
          TargetPlatform.iOS,
        }.contains(defaultTargetPlatform);
    void activate() {
      if (!active) return;
      if (editable) {
        widget.onEdit!();
        return;
      }
      unawaited(
        showCupertinoDialog<void>(
          context: context,
          barrierDismissible: true,
          builder: (_) => AvatarPreviewDialog(input: input),
        ),
      );
    }

    return MouseRegion(
      onEnter: (_) => setState(() => _hover = true),
      onExit: (_) => setState(() => _hover = false),
      child: Tooltip(
        message: active ? label : '',
        child: Semantics(
          button: active,
          label: active ? label : widget.seed,
          child: FocusableActionDetector(
            enabled: active,
            mouseCursor: active ? SystemMouseCursors.click : MouseCursor.defer,
            onShowFocusHighlight: (value) => setState(() => _focus = value),
            shortcuts: const {
              SingleActivator(LogicalKeyboardKey.enter): ActivateIntent(),
              SingleActivator(LogicalKeyboardKey.space): ActivateIntent(),
            },
            actions: {
              ActivateIntent: CallbackAction<ActivateIntent>(
                onInvoke: (_) {
                  activate();
                  return null;
                },
              ),
            },
            child: GestureDetector(
              behavior: HitTestBehavior.opaque,
              onTap: active ? activate : null,
              child: Container(
                decoration: BoxDecoration(
                  shape: isAgent ? BoxShape.rectangle : BoxShape.circle,
                  borderRadius: isAgent
                      ? BorderRadius.circular(widget.size * .24)
                      : null,
                  border: _focus
                      ? Border.all(color: theme.primaryDark, width: 2)
                      : null,
                ),
                child: Stack(
                  clipBehavior: Clip.none,
                  children: [
                    AvatarBadge(
                      seed: widget.seed,
                      userId: widget.userId,
                      avatarUri: widget.avatarUri,
                      size: widget.size,
                    ),
                    if (editable && (_hover || _focus))
                      Positioned.fill(
                        child: DecoratedBox(
                          decoration: BoxDecoration(
                            shape: isAgent
                                ? BoxShape.rectangle
                                : BoxShape.circle,
                            borderRadius: isAgent
                                ? BorderRadius.circular(widget.size * .24)
                                : null,
                            color: const Color(0x66000000),
                          ),
                          child: Icon(
                            CupertinoIcons.camera,
                            color: CupertinoColors.white,
                            size: widget.size * .32,
                          ),
                        ),
                      ),
                    if (editable && touch)
                      Positioned(
                        right: -2,
                        bottom: -2,
                        child: Container(
                          padding: const EdgeInsets.all(4),
                          decoration: BoxDecoration(
                            color: theme.primaryDark,
                            shape: BoxShape.circle,
                          ),
                          child: Icon(
                            CupertinoIcons.camera_fill,
                            size: 14,
                            color: theme.primaryForeground,
                          ),
                        ),
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

class AvatarPreviewDialog extends ConsumerStatefulWidget {
  const AvatarPreviewDialog({super.key, required this.input});
  final AvatarReferenceInput input;
  @override
  ConsumerState<AvatarPreviewDialog> createState() =>
      _AvatarPreviewDialogState();
}

class _AvatarPreviewDialogState extends ConsumerState<AvatarPreviewDialog> {
  ui.Image? _image;
  String? _uri;
  String? _loadedUri;
  bool _loading = true;
  int _generation = 0;
  SessionEpoch? _epoch;
  @override
  void initState() {
    super.initState();
    _epoch = ref.read(sessionProvider).activeEpoch;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      final session = ref.read(sessionProvider);
      if (session.session != null && widget.input.did != null) {
        unawaited(
          ref
              .read(peerDisplayProfileProvider.notifier)
              .refreshDisplayProfiles(
                ownerDid: session.session!.did,
                dids: [widget.input.did!],
                force: true,
                expectedEpoch: _epoch,
              ),
        );
      }
    });
  }

  Future<void> _load(String? uri, {bool force = false}) async {
    final generation = ++_generation;
    _image?.dispose();
    _image = null;
    setState(() => _loading = uri != null);
    if (uri == null) return;
    final image = await ref
        .read(avatarImageCacheProvider)
        .load(uri, edge: 512, force: force);
    if (!mounted || generation != _generation) {
      image?.dispose();
      return;
    }
    setState(() {
      _image = image;
      _loadedUri = uri;
      _loading = false;
    });
  }

  @override
  void dispose() {
    _generation++;
    _image?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    ref.listen(sessionProvider.select((state) => state.activeEpoch), (_, next) {
      if (next != _epoch && mounted) Navigator.of(context).pop();
    });
    final reference = ref.watch(avatarReferenceProvider(widget.input));
    final isAgent = ref.watch(avatarIsAgentProvider(widget.input.did));
    final uri = safeAvatarUri(reference.uri)?.toString();
    if (!isAgent && (_uri != uri || (_generation == 0))) {
      _uri = uri;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted && _uri == uri) unawaited(_load(uri));
      });
    }
    final viewport = MediaQuery.sizeOf(context);
    final side = math
        .min(viewport.width - 64, viewport.height - 140)
        .clamp(96.0, 512.0);
    return Shortcuts(
      shortcuts: const {
        SingleActivator(LogicalKeyboardKey.escape): DismissIntent(),
      },
      child: Actions(
        actions: {
          DismissIntent: CallbackAction<DismissIntent>(
            onInvoke: (_) {
              Navigator.of(context).pop();
              return null;
            },
          ),
        },
        child: Focus(
          autofocus: true,
          child: Center(
            child: CupertinoPopupSurface(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    SizedBox(
                      width: side,
                      child: Row(
                        children: [
                          Expanded(
                            child: Text(context.l10n.profileAvatarLabel),
                          ),
                          CupertinoButton(
                            key: const Key('avatar-preview-close'),
                            padding: const EdgeInsets.all(8),
                            onPressed: () => Navigator.of(context).pop(),
                            child: const Icon(CupertinoIcons.xmark),
                          ),
                        ],
                      ),
                    ),
                    SizedBox(
                      width: side,
                      height: side,
                      child: Center(
                        child: isAgent
                            ? AgentAvatarImage(
                                uri: reference.uri,
                                posterUri: reference.thumbnail,
                                size: side,
                                fallback: const Icon(
                                  CupertinoIcons.person_crop_square,
                                ),
                              )
                            : _loading
                            ? const CupertinoActivityIndicator()
                            : _image != null && uri != null && _loadedUri == uri
                            ? RawImage(
                                key: const Key('avatar-preview-image'),
                                image: _image,
                                fit: BoxFit.contain,
                              )
                            : Column(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Text(
                                    uri == null
                                        ? context.l10n.avatarNoImage
                                        : context.l10n.avatarPreviewFailed,
                                  ),
                                  if (uri != null)
                                    CupertinoButton(
                                      onPressed: () => _load(uri, force: true),
                                      child: Text(context.l10n.commonRetry),
                                    ),
                                ],
                              ),
                      ),
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

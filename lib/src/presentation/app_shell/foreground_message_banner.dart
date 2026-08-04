import 'dart:async';

import 'package:flutter/cupertino.dart';

import '../../l10n/l10n.dart';
import '../shared/avatar_badge.dart';
import '../shared/awiki_me_design.dart';
import 'providers/foreground_message_banner_provider.dart';

const Duration foregroundMessageBannerDuration = Duration(seconds: 4);

class ForegroundMessageBanner extends StatefulWidget {
  const ForegroundMessageBanner({
    super.key,
    required this.event,
    required this.onTap,
    required this.onDismiss,
    this.displayDuration = foregroundMessageBannerDuration,
  });

  final ForegroundMessageBannerEvent event;
  final VoidCallback onTap;
  final VoidCallback onDismiss;
  final Duration displayDuration;

  @override
  State<ForegroundMessageBanner> createState() =>
      _ForegroundMessageBannerState();
}

class _ForegroundMessageBannerState extends State<ForegroundMessageBanner>
    with TickerProviderStateMixin {
  late final AnimationController _entranceController;
  late final AnimationController _progressController;
  Timer? _dismissTimer;
  bool _closed = false;
  bool _reduceMotion = false;
  double _verticalDragDistance = 0;

  @override
  void initState() {
    super.initState();
    _entranceController = AnimationController(
      vsync: this,
      duration: AwikiMeMotion.feedback,
    );
    _progressController = AnimationController(
      vsync: this,
      duration: widget.displayDuration,
    );
    _restartPresentation();
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final reduceMotion = MediaQuery.disableAnimationsOf(context);
    if (_reduceMotion == reduceMotion) {
      return;
    }
    _reduceMotion = reduceMotion;
    if (_reduceMotion) {
      _entranceController.value = 1;
    }
  }

  @override
  void didUpdateWidget(covariant ForegroundMessageBanner oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.event.sequence != widget.event.sequence ||
        oldWidget.displayDuration != widget.displayDuration) {
      _restartPresentation();
    }
  }

  @override
  void dispose() {
    _dismissTimer?.cancel();
    _entranceController.dispose();
    _progressController.dispose();
    super.dispose();
  }

  void _restartPresentation() {
    _dismissTimer?.cancel();
    _closed = false;
    _verticalDragDistance = 0;
    _entranceController
      ..stop()
      ..value = _reduceMotion ? 1 : 0
      ..forward();
    _progressController
      ..duration = widget.displayDuration
      ..stop()
      ..value = 0
      ..forward();
    _dismissTimer = Timer(widget.displayDuration, _dismiss);
  }

  void _dismiss() {
    if (_closed || !mounted) {
      return;
    }
    _closed = true;
    _dismissTimer?.cancel();
    widget.onDismiss();
  }

  @override
  Widget build(BuildContext context) {
    final theme = context.awikiTheme;
    final content = widget.event.content;
    final supportingText = content.isGroup
        ? context.l10n.foregroundMessageBannerGroupPreview(
            content.senderLabel,
            content.preview,
          )
        : content.preview;
    final semanticsLabel = context.l10n.foregroundMessageBannerSemanticLabel(
      content.senderLabel,
      content.conversationTitle,
      content.preview,
    );
    final entrance = CurvedAnimation(
      parent: _entranceController,
      curve: AwikiMeMotion.emphasized,
    );

    final card = Semantics(
      identifier: 'foreground-message-banner',
      button: true,
      label: semanticsLabel,
      onTap: widget.onTap,
      child: ExcludeSemantics(
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: widget.onTap,
          onVerticalDragStart: (_) => _verticalDragDistance = 0,
          onVerticalDragUpdate: (details) {
            _verticalDragDistance += details.delta.dy;
          },
          onVerticalDragEnd: (details) {
            final velocity = details.primaryVelocity ?? 0;
            if (_verticalDragDistance <= -24 || velocity <= -250) {
              _dismiss();
            }
          },
          child: Container(
            key: const Key('foreground-message-banner-card'),
            height: 72,
            clipBehavior: Clip.antiAlias,
            decoration: BoxDecoration(
              color: theme.primarySoft,
              borderRadius: BorderRadius.circular(AwikiMeRadii.md),
              border: Border.all(color: theme.primary, width: 1),
              boxShadow: AwikiMeShadows.selectedListItem,
            ),
            child: Stack(
              children: <Widget>[
                Padding(
                  padding: const EdgeInsets.fromLTRB(8, 8, 12, 8),
                  child: Row(
                    children: <Widget>[
                      AvatarBadge(
                        seed: content.avatarSeed,
                        avatarUri: content.avatarUri,
                        size: 48,
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: <Widget>[
                            Row(
                              children: <Widget>[
                                if (content.isGroup) ...<Widget>[
                                  _GroupBadge(
                                    label:
                                        context.l10n.conversationPeerBadgeGroup,
                                  ),
                                  const SizedBox(width: 8),
                                ],
                                Expanded(
                                  child: Text(
                                    content.conversationTitle,
                                    key: const Key(
                                      'foreground-message-banner-title',
                                    ),
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    style: TextStyle(
                                      color: theme.title,
                                      fontSize: 15,
                                      fontWeight: FontWeight.w600,
                                      height: 1.2,
                                    ),
                                  ),
                                ),
                                const SizedBox(width: 8),
                                Text(
                                  context.l10n.foregroundMessageBannerJustNow,
                                  style: TextStyle(
                                    color: theme.tertiaryText,
                                    fontSize: 11,
                                    height: 1.2,
                                  ),
                                ),
                              ],
                            ),
                            const SizedBox(height: 5),
                            Text(
                              supportingText,
                              key: const Key(
                                'foreground-message-banner-preview',
                              ),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(
                                color: theme.secondaryText,
                                fontSize: 13,
                                height: 1.2,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
                Positioned(
                  left: 0,
                  right: 0,
                  bottom: 0,
                  height: 3,
                  child: AnimatedBuilder(
                    animation: _progressController,
                    builder: (context, _) => Align(
                      alignment: Alignment.centerLeft,
                      child: FractionallySizedBox(
                        key: const Key('foreground-message-banner-progress'),
                        widthFactor: 1 - _progressController.value,
                        child: ColoredBox(color: theme.primary),
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );

    return FadeTransition(
      opacity: entrance,
      child: SlideTransition(
        position: Tween<Offset>(
          begin: _reduceMotion ? Offset.zero : const Offset(0, -0.18),
          end: Offset.zero,
        ).animate(entrance),
        child: card,
      ),
    );
  }
}

class _GroupBadge extends StatelessWidget {
  const _GroupBadge({required this.label});

  final String label;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      decoration: BoxDecoration(
        color: const Color(0xFFEFE4FF),
        borderRadius: BorderRadius.circular(AwikiMeRadii.pill),
      ),
      child: Text(
        label,
        style: const TextStyle(
          color: Color(0xFF7C3AED),
          fontSize: 10,
          fontWeight: FontWeight.w600,
          height: 1.2,
        ),
      ),
    );
  }
}

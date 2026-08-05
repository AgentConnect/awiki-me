import 'package:flutter/cupertino.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart' show Icons;
import 'package:flutter/services.dart';

import 'awiki_me_design.dart';

bool usesBrandedStartupSplash(TargetPlatform platform) {
  return platform == TargetPlatform.android || platform == TargetPlatform.iOS;
}

class AwikiMeStartupPlaceholder extends StatelessWidget {
  const AwikiMeStartupPlaceholder({super.key, this.statusLabel});

  final String? statusLabel;

  @override
  Widget build(BuildContext context) {
    if (usesBrandedStartupSplash(defaultTargetPlatform)) {
      return AwikiMeStartupSplash(statusLabel: statusLabel);
    }

    final theme = context.awikiTheme;
    final status = statusLabel?.trim();
    final semanticStatus = status == null || status.isEmpty
        ? _StartupSplashCopy.resolve(context).loadingLabel
        : status;
    return CupertinoPageScaffold(
      key: const Key('app-desktop-startup-placeholder'),
      backgroundColor: theme.background,
      child: Semantics(
        container: true,
        liveRegion: true,
        label: semanticStatus,
        child: ExcludeSemantics(
          child: Center(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: <Widget>[
                CupertinoActivityIndicator(
                  key: const Key('desktop-startup-progress'),
                  radius: 10,
                  color: theme.primary,
                ),
                if (status != null && status.isNotEmpty) ...<Widget>[
                  const SizedBox(height: 12),
                  Text(
                    status,
                    key: const Key('desktop-startup-status'),
                    style: TextStyle(
                      color: theme.secondaryText,
                      fontSize: 12,
                      height: 1.35,
                    ),
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

class AwikiMeStartupSplash extends StatefulWidget {
  const AwikiMeStartupSplash({super.key, this.statusLabel});

  final String? statusLabel;

  @override
  State<AwikiMeStartupSplash> createState() => _AwikiMeStartupSplashState();
}

class _AwikiMeStartupSplashState extends State<AwikiMeStartupSplash>
    with SingleTickerProviderStateMixin {
  late final AnimationController _progressController;
  bool? _motionDisabled;

  @override
  void initState() {
    super.initState();
    _progressController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1400),
    );
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final motionDisabled =
        MediaQuery.maybeOf(context)?.disableAnimations ?? false;
    if (_motionDisabled == motionDisabled) {
      return;
    }
    _motionDisabled = motionDisabled;
    if (motionDisabled) {
      _progressController
        ..stop()
        ..value = 0.6;
    } else {
      _progressController.repeat(reverse: true);
    }
  }

  @override
  void dispose() {
    _progressController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = context.awikiTheme;
    final copy = _StartupSplashCopy.resolve(context);
    final statusLabel = widget.statusLabel?.trim();
    final background = Color.alphaBlend(
      theme.primarySoft.withValues(alpha: 0.34),
      theme.surface,
    );
    final overlayStyle = SystemUiOverlayStyle(
      statusBarColor: background,
      statusBarIconBrightness: Brightness.dark,
      statusBarBrightness: Brightness.light,
      systemNavigationBarColor: background,
      systemNavigationBarIconBrightness: Brightness.dark,
      systemNavigationBarDividerColor: background,
    );
    final semanticStatus = statusLabel == null || statusLabel.isEmpty
        ? copy.loadingLabel
        : statusLabel;

    return AnnotatedRegion<SystemUiOverlayStyle>(
      value: overlayStyle,
      child: CupertinoPageScaffold(
        key: const Key('app-startup-splash'),
        backgroundColor: background,
        child: LayoutBuilder(
          builder: (context, constraints) {
            final locale =
                Localizations.maybeLocaleOf(context) ??
                View.of(context).platformDispatcher.locale;
            final usesChineseReference =
                locale.languageCode.toLowerCase() == 'zh';
            final usesStandardTextScale =
                MediaQuery.textScalerOf(context).scale(1) <= 1.1;
            final portraitReferenceLayout =
                usesChineseReference &&
                usesStandardTextScale &&
                constraints.maxHeight >= 700 &&
                constraints.maxWidth <= constraints.maxHeight;
            return Semantics(
              container: true,
              liveRegion: true,
              label: '${copy.brand}. $semanticStatus',
              child: ExcludeSemantics(
                child: portraitReferenceLayout
                    ? _StartupReferenceLayout(
                        copy: copy,
                        statusLabel: statusLabel,
                        progressAnimation: _progressController,
                        motionDisabled: _motionDisabled ?? false,
                      )
                    : _StartupCompactLayout(
                        copy: copy,
                        statusLabel: statusLabel,
                        progressAnimation: _progressController,
                        motionDisabled: _motionDisabled ?? false,
                      ),
              ),
            );
          },
        ),
      ),
    );
  }
}

class _StartupReferenceLayout extends StatelessWidget {
  const _StartupReferenceLayout({
    required this.copy,
    required this.statusLabel,
    required this.progressAnimation,
    required this.motionDisabled,
  });

  final _StartupSplashCopy copy;
  final String? statusLabel;
  final Animation<double> progressAnimation;
  final bool motionDisabled;

  @override
  Widget build(BuildContext context) {
    final theme = context.awikiTheme;
    return Center(
      child: FittedBox(
        fit: BoxFit.contain,
        child: SizedBox(
          width: 390,
          height: 844,
          child: Stack(
            children: <Widget>[
              Positioned(
                left: 112,
                top: 246,
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(6),
                  child: Image.asset(
                    'assets/branding/awiki-me-logo.png',
                    key: const Key('startup-splash-logo'),
                    width: 24,
                    height: 24,
                    fit: BoxFit.cover,
                  ),
                ),
              ),
              Positioned(
                left: 148,
                top: 242,
                width: 150,
                height: 34,
                child: Text(
                  copy.brand,
                  key: const Key('startup-splash-brand'),
                  maxLines: 1,
                  style: TextStyle(
                    color: theme.title,
                    fontSize: 25,
                    height: 1.2,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
              Positioned(
                left: 48,
                top: 318,
                width: 294,
                height: 40,
                child: Text(
                  copy.title,
                  key: const Key('startup-splash-title'),
                  maxLines: 1,
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    color: theme.title,
                    fontSize: 26,
                    height: 1.35,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
              Positioned(
                left: 36,
                top: 372,
                width: 318,
                height: 28,
                child: Text(
                  copy.subtitle,
                  key: const Key('startup-splash-subtitle'),
                  maxLines: 1,
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    color: theme.secondaryText,
                    fontSize: 15,
                    height: 28 / 15,
                    fontWeight: FontWeight.w400,
                  ),
                ),
              ),
              for (var index = 0; index < copy.features.length; index++)
                Positioned(
                  left: 36,
                  top: 454 + (index * 56),
                  width: 318,
                  height: 28,
                  child: _StartupReferenceFeatureRow(
                    index: index,
                    feature: copy.features[index],
                  ),
                ),
              Positioned(
                left: 76,
                top: 756,
                child: _StartupProgressIndicator(
                  animation: progressAnimation,
                  motionDisabled: motionDisabled,
                ),
              ),
              if (statusLabel != null && statusLabel!.isNotEmpty)
                Positioned(
                  left: 36,
                  top: 774,
                  width: 318,
                  child: Text(
                    statusLabel!,
                    key: const Key('startup-splash-status'),
                    maxLines: 1,
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      color: theme.secondaryText,
                      fontSize: 12,
                      height: 1.35,
                    ),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

class _StartupReferenceFeatureRow extends StatelessWidget {
  const _StartupReferenceFeatureRow({
    required this.index,
    required this.feature,
  });

  final int index;
  final _StartupFeature feature;

  @override
  Widget build(BuildContext context) {
    final theme = context.awikiTheme;
    return Row(
      key: Key('startup-splash-feature-$index'),
      children: <Widget>[
        SizedBox(
          width: 20,
          height: 20,
          child: Icon(
            feature.icon,
            key: Key('startup-splash-feature-icon-$index'),
            size: 20,
            color: theme.primary,
          ),
        ),
        const SizedBox(width: 8),
        Text(
          feature.title,
          maxLines: 1,
          style: TextStyle(
            color: theme.body,
            fontSize: 15,
            height: 28 / 15,
            fontWeight: FontWeight.w400,
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Text(
            feature.subtitle,
            maxLines: 1,
            overflow: TextOverflow.clip,
            style: TextStyle(
              color: theme.secondaryText,
              fontSize: 15,
              height: 28 / 15,
              fontWeight: FontWeight.w400,
            ),
          ),
        ),
      ],
    );
  }
}

class _StartupCompactLayout extends StatelessWidget {
  const _StartupCompactLayout({
    required this.copy,
    required this.statusLabel,
    required this.progressAnimation,
    required this.motionDisabled,
  });

  final _StartupSplashCopy copy;
  final String? statusLabel;
  final Animation<double> progressAnimation;
  final bool motionDisabled;

  @override
  Widget build(BuildContext context) {
    final theme = context.awikiTheme;
    return SafeArea(
      child: SingleChildScrollView(
        physics: const ClampingScrollPhysics(),
        padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 20),
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 360),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: <Widget>[
                _StartupBrandRow(copy: copy),
                const SizedBox(height: 16),
                Text(
                  copy.title,
                  key: const Key('startup-splash-title'),
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    color: theme.title,
                    fontSize: 24,
                    height: 1.25,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  copy.subtitle,
                  key: const Key('startup-splash-subtitle'),
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    color: theme.secondaryText,
                    fontSize: 13,
                    height: 1.45,
                  ),
                ),
                const SizedBox(height: 22),
                for (var index = 0; index < copy.features.length; index++) ...[
                  _StartupFeatureRow(
                    index: index,
                    feature: copy.features[index],
                  ),
                  if (index != copy.features.length - 1)
                    const SizedBox(height: 12),
                ],
                const SizedBox(height: 24),
                _StartupProgressIndicator(
                  animation: progressAnimation,
                  motionDisabled: motionDisabled,
                ),
                if (statusLabel != null && statusLabel!.isNotEmpty) ...[
                  const SizedBox(height: 10),
                  Text(
                    statusLabel!,
                    key: const Key('startup-splash-status'),
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      color: theme.secondaryText,
                      fontSize: 12,
                      height: 1.35,
                    ),
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

class _StartupBrandRow extends StatelessWidget {
  const _StartupBrandRow({required this.copy});

  final _StartupSplashCopy copy;

  @override
  Widget build(BuildContext context) {
    final theme = context.awikiTheme;
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      mainAxisSize: MainAxisSize.min,
      children: <Widget>[
        ClipRRect(
          borderRadius: BorderRadius.circular(6),
          child: Image.asset(
            'assets/branding/awiki-me-logo.png',
            key: const Key('startup-splash-logo'),
            width: 24,
            height: 24,
            fit: BoxFit.cover,
            excludeFromSemantics: true,
          ),
        ),
        const SizedBox(width: 12),
        Text(
          copy.brand,
          key: const Key('startup-splash-brand'),
          style: TextStyle(
            color: theme.title,
            fontSize: 25,
            height: 1.2,
            fontWeight: FontWeight.w700,
          ),
        ),
      ],
    );
  }
}

class _StartupFeatureRow extends StatelessWidget {
  const _StartupFeatureRow({required this.index, required this.feature});

  final int index;
  final _StartupFeature feature;

  @override
  Widget build(BuildContext context) {
    final theme = context.awikiTheme;
    return Row(
      key: Key('startup-splash-feature-$index'),
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        SizedBox(
          width: 20,
          height: 20,
          child: Icon(
            feature.icon,
            key: Key('startup-splash-feature-icon-$index'),
            size: 20,
            color: theme.primary,
          ),
        ),
        const SizedBox(width: 8),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              Text(
                feature.title,
                style: TextStyle(
                  color: theme.title,
                  fontSize: 14,
                  height: 1.25,
                  fontWeight: FontWeight.w600,
                ),
              ),
              const SizedBox(height: 3),
              Text(
                feature.subtitle,
                style: TextStyle(
                  color: theme.secondaryText,
                  fontSize: 12.5,
                  height: 1.42,
                  fontWeight: FontWeight.w400,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class _StartupProgressIndicator extends StatelessWidget {
  const _StartupProgressIndicator({
    required this.animation,
    required this.motionDisabled,
  });

  final Animation<double> animation;
  final bool motionDisabled;

  @override
  Widget build(BuildContext context) {
    final theme = context.awikiTheme;
    return SizedBox(
      key: const Key('startup-splash-progress'),
      width: 238,
      height: 4,
      child: ClipRRect(
        borderRadius: BorderRadius.circular(AwikiMeRadii.pill),
        child: ColoredBox(
          color: theme.primarySoft,
          child: LayoutBuilder(
            builder: (context, constraints) {
              final segmentWidth = constraints.maxWidth * 0.6;
              if (motionDisabled) {
                return Align(
                  alignment: Alignment.centerLeft,
                  child: SizedBox(
                    width: segmentWidth,
                    height: double.infinity,
                    child: ColoredBox(color: theme.primary),
                  ),
                );
              }
              return FadeTransition(
                opacity: Tween<double>(begin: 0.72, end: 1).animate(
                  CurvedAnimation(parent: animation, curve: Curves.easeInOut),
                ),
                child: Align(
                  alignment: Alignment.centerLeft,
                  child: SizedBox(
                    width: segmentWidth,
                    height: double.infinity,
                    child: ColoredBox(color: theme.primary),
                  ),
                ),
              );
            },
          ),
        ),
      ),
    );
  }
}

class _StartupSplashCopy {
  const _StartupSplashCopy({
    required this.brand,
    required this.title,
    required this.subtitle,
    required this.loadingLabel,
    required this.features,
  });

  final String brand;
  final String title;
  final String subtitle;
  final String loadingLabel;
  final List<_StartupFeature> features;

  static _StartupSplashCopy resolve(BuildContext context) {
    final locale =
        Localizations.maybeLocaleOf(context) ??
        View.of(context).platformDispatcher.locale;
    return locale.languageCode.toLowerCase() == 'zh' ? _zh : _en;
  }

  static const _StartupSplashCopy _zh = _StartupSplashCopy(
    brand: 'AWiki Me',
    title: '连接你的 Agent 世界',
    subtitle: '安全连接人、Agent 与组织，协作更简单。',
    loadingLabel: '正在安全恢复会话',
    features: <_StartupFeature>[
      _StartupFeature(
        icon: Icons.gpp_good_outlined,
        title: '安全协作',
        subtitle: '端到端保护身份与消息',
      ),
      _StartupFeature(
        icon: Icons.auto_awesome_outlined,
        title: '智能体随行',
        subtitle: '连接 Daemon 上的 Agent',
      ),
      _StartupFeature(
        icon: Icons.chat_bubble_outline,
        title: '人与 Agent 同群',
        subtitle: '在一个群里完成协作',
      ),
    ],
  );

  static const _StartupSplashCopy _en = _StartupSplashCopy(
    brand: 'AWiki Me',
    title: 'Connect your Agent world',
    subtitle:
        'Securely connect people, Agents, and organizations for smarter collaboration.',
    loadingLabel: 'Restoring your session securely',
    features: <_StartupFeature>[
      _StartupFeature(
        icon: Icons.gpp_good_outlined,
        title: 'Secure collaboration',
        subtitle: 'Encrypted messages with credentials kept on this device',
      ),
      _StartupFeature(
        icon: Icons.auto_awesome_outlined,
        title: 'Agents with you',
        subtitle: 'Connect to Daemon Agents for conversation and diagnostics',
      ),
      _StartupFeature(
        icon: Icons.chat_bubble_outline,
        title: 'People and Agents together',
        subtitle: 'Collaborate on messages, tasks, and contacts in one group',
      ),
    ],
  );
}

class _StartupFeature {
  const _StartupFeature({
    required this.icon,
    required this.title,
    required this.subtitle,
  });

  final IconData icon;
  final String title;
  final String subtitle;
}

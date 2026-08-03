import 'package:flutter/cupertino.dart';
import 'package:flutter/services.dart';

import 'awiki_me_design.dart';

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
        ..value = 0.28;
    } else {
      _progressController.repeat();
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
        child: SafeArea(
          child: LayoutBuilder(
            builder: (context, constraints) {
              return Semantics(
                container: true,
                liveRegion: true,
                label: '${copy.brand}. $semanticStatus',
                child: ExcludeSemantics(
                  child: SingleChildScrollView(
                    physics: const ClampingScrollPhysics(),
                    padding: const EdgeInsets.symmetric(
                      horizontal: 24,
                      vertical: 28,
                    ),
                    child: ConstrainedBox(
                      constraints: BoxConstraints(
                        minHeight: constraints.maxHeight - 56,
                      ),
                      child: Center(
                        child: ConstrainedBox(
                          constraints: const BoxConstraints(maxWidth: 360),
                          child: Column(
                            mainAxisSize: MainAxisSize.min,
                            crossAxisAlignment: CrossAxisAlignment.stretch,
                            children: <Widget>[
                              _StartupBrandRow(copy: copy),
                              const SizedBox(height: 22),
                              Text(
                                copy.title,
                                key: const Key('startup-splash-title'),
                                textAlign: TextAlign.center,
                                style: TextStyle(
                                  color: theme.title,
                                  fontSize: 27,
                                  height: 1.24,
                                  fontWeight: FontWeight.w700,
                                ),
                              ),
                              const SizedBox(height: 9),
                              Text(
                                copy.subtitle,
                                key: const Key('startup-splash-subtitle'),
                                textAlign: TextAlign.center,
                                style: TextStyle(
                                  color: theme.secondaryText,
                                  fontSize: 13.5,
                                  height: 1.5,
                                  fontWeight: FontWeight.w400,
                                ),
                              ),
                              const SizedBox(height: 32),
                              for (
                                var index = 0;
                                index < copy.features.length;
                                index++
                              ) ...<Widget>[
                                _StartupFeatureRow(
                                  index: index,
                                  feature: copy.features[index],
                                ),
                                if (index != copy.features.length - 1)
                                  const SizedBox(height: 16),
                              ],
                              const SizedBox(height: 36),
                              Align(
                                child: _StartupProgressIndicator(
                                  animation: _progressController,
                                  motionDisabled: _motionDisabled ?? false,
                                ),
                              ),
                              if (statusLabel != null &&
                                  statusLabel.isNotEmpty) ...<Widget>[
                                const SizedBox(height: 12),
                                Text(
                                  statusLabel,
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
          borderRadius: BorderRadius.circular(15),
          child: Image.asset(
            'assets/branding/awiki-me-logo.png',
            key: const Key('startup-splash-logo'),
            width: 54,
            height: 54,
            fit: BoxFit.cover,
            excludeFromSemantics: true,
          ),
        ),
        const SizedBox(width: 13),
        Text(
          copy.brand,
          key: const Key('startup-splash-brand'),
          style: TextStyle(
            color: theme.title,
            fontSize: 22,
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
        Container(
          width: 40,
          height: 40,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: theme.primarySoft.withValues(alpha: 0.78),
            borderRadius: BorderRadius.circular(11),
          ),
          child: Icon(feature.icon, size: 19, color: theme.primary),
        ),
        const SizedBox(width: 12),
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
      width: 128,
      height: 3,
      child: ClipRRect(
        borderRadius: BorderRadius.circular(AwikiMeRadii.pill),
        child: ColoredBox(
          color: theme.primarySoft,
          child: LayoutBuilder(
            builder: (context, constraints) {
              final segmentWidth = constraints.maxWidth * 0.24;
              if (motionDisabled) {
                return Align(
                  alignment: Alignment.centerLeft,
                  child: SizedBox(
                    width: segmentWidth,
                    child: ColoredBox(color: theme.primary),
                  ),
                );
              }
              return AnimatedBuilder(
                animation: animation,
                builder: (context, child) {
                  final travel = constraints.maxWidth + segmentWidth;
                  return Transform.translate(
                    offset: Offset(
                      (travel * animation.value) - segmentWidth,
                      0,
                    ),
                    child: child,
                  );
                },
                child: Align(
                  alignment: Alignment.centerLeft,
                  child: SizedBox(
                    width: segmentWidth,
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
    brand: 'AWiki',
    title: '连接你的 Agent 世界',
    subtitle: '安全连接人、Agent 与组织，协作更智能，决策更高效。',
    loadingLabel: '正在安全恢复会话',
    features: <_StartupFeature>[
      _StartupFeature(
        icon: CupertinoIcons.shield,
        title: '安全协作',
        subtitle: '端到端加密消息，身份凭证只存本地',
      ),
      _StartupFeature(
        icon: CupertinoIcons.sparkles,
        title: '智能体随行',
        subtitle: '连接 Daemon 上的 Agent，随时对话与诊断',
      ),
      _StartupFeature(
        icon: CupertinoIcons.chat_bubble,
        title: '人与 Agent 同群',
        subtitle: '消息、任务、联系人，一个群里完成协作',
      ),
    ],
  );

  static const _StartupSplashCopy _en = _StartupSplashCopy(
    brand: 'AWiki',
    title: 'Connect your Agent world',
    subtitle:
        'Securely connect people, Agents, and organizations for smarter collaboration.',
    loadingLabel: 'Restoring your session securely',
    features: <_StartupFeature>[
      _StartupFeature(
        icon: CupertinoIcons.shield,
        title: 'Secure collaboration',
        subtitle: 'Encrypted messages with credentials kept on this device',
      ),
      _StartupFeature(
        icon: CupertinoIcons.sparkles,
        title: 'Agents with you',
        subtitle: 'Connect to Daemon Agents for conversation and diagnostics',
      ),
      _StartupFeature(
        icon: CupertinoIcons.chat_bubble,
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
